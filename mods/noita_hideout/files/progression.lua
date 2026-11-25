-- All purchases operate on the detached profile passed to NHStore.commit.
local catalog = {}
local definitions = {}
local function define(id,section,zh,en,max,cost,options)
    local entry=options or {}
    entry.id,entry.section,entry.zh,entry.en,entry.max,entry.cost=id,section,zh,en,max,cost
    entry.group=section=="upgrade" and "upgrade" or "expansion"
    catalog[#catalog+1]=entry
    definitions[id]=entry
end

local stock_cost={{"sand",200},{"water",100}}
define("warehouse_wand","inventory","魔杖库","Wand storage",4,stock_cost,{category="wand"})
define("warehouse_spell","inventory","法术库","Spell storage",4,stock_cost,{category="spell"})
define("warehouse_containers","inventory","容器库","Container storage",4,stock_cost,{category="containers"})
define("warehouse_supplies","inventory","消耗品库","Supply storage",4,stock_cost,{category="supplies"})
define("warehouse_equipment","inventory","装备库","Equipment storage",4,stock_cost,{category="equipment"})
define("warehouse_collection","inventory","藏品库","Collection storage",4,stock_cost,{category="collection"})
define("warehouse_materials","inventory","物料库","Material storage",4,{{"sand",250},{"slime",100}},{category="materials"})
define("medical","workshop","医疗工位","Medical station",1,{{"water",250},{"slime",100}},
    {effect={"制造医疗物品","Craft medical supplies"}})
define("injector","workshop","针剂工位","Injector station",1,{{"water",250},{"oil",100}},
    {effect={"制造针剂","Craft injectors"}})
define("grenade","workshop","武器工位","Weapon station",1,{{"gunpowder",150},{"oil",100}},
    {effect={"制造七种战术发射器","Craft seven tactical launchers"}})
define("salvage","workshop","拆解台","Salvage bench",1,{{"sand",250},{"oil",100}},
    {effect={"回收碎片、提取精华和合成法术","Recover scrap, extract essences and craft spells"}})
local function supportStation(id,zh,en,essence,tiers)
    define(id,"support",zh,en,3,nil,{essence=essence,tiers=tiers})
end
supportStation("support","轰炸支援站","Bombardment station","essence_high_energy",{
    {"重炮追踪、徐进弹幕、布雷器","Tracked shell, creeping barrage and minelayer"},
    {"重炮区域轰炸、导弹扫射、等离子扫射","Shell barrage, missile and plasma runs"},
    {"导弹区域轰炸、磁轨炮狙击","Missile barrage and railgun snipe"}})
supportStation("resupply","补给支援站","Supply station","essence_healing",{
    {"基础补给箱、重机枪","Basic boxes and heavy machine gun"},{"进阶补给箱、连发榴弹、重等离子炮","Improved boxes, grenade launcher and heavy plasma"},
    {"高级补给箱、导弹发射器、轨道炮与 BFG","Advanced boxes, missiles, railgun and BFG"}})
supportStation("reinforcement","增援支援站","Reinforcement station","essence_creation",{
    {"机枪无人机、机械士兵、机枪塔","Gun drone, soldier and MG turret"},
    {"维修无人机、机械间谍、导弹机械蟹、链炮塔","Repair drone, spy, missile crab and chaingun turret"},
    {"护盾无人机、激光无人机、机械刺客、机械僧侣、复活机器人","Shield drone, laser drone, assassin, monk and necrobot"}})
supportStation("intel","情报支援站","Intelligence station","essence_force",{
    {"探查、狂暴之环","Recon and berserk field"},
    {"敌人雷达、活力之环、变形之环","Enemy radar, vitality and polymorph fields"},
    {"高价值地点定位、巨大黑洞／白洞、核弹／超级核弹","Site locator, large holes and nuclear strikes"}})
define("perk_pack","workshop","特质打包台","Perk packing",1,{{"slime",200},{"arcane_scrap",1}},
    {effect={"封装附近未拾取的免疫特质","Pack nearby immunity perks"}})
define("safe","upgrade","随身安全箱","Secure case",10,{{"sand",250},{"slime",150}})
define("perk_slots","upgrade","遗物链扩容","Relic chain capacity",3,{{"water",250},{"slime",100}})
define("farmland","production","田地","Farmland",4,{{"soil",150},{"water",100}})
define("agri_equipment","production","农业设备","Farm equipment",1,{{"sand",300},{"water",200}},
    {effect={"种植香料与激活草药","Grow spices and stimulating herbs"}})
define("livestock","production","畜牧设备","Livestock pens",3,{{"sand",200},{"water",150}},
    {housing={"鸡、牛容量各","Chicken and cattle capacity (each)"}})
define("beehive","production","蜂箱","Beehive",3,{{"fiber",12},{"slime",75},{"sugar",8}},
    {housing={"女王蜂容量","Queen bee capacity"}})
define("dragon_nest","production","龙巢","Dragon nest",3,{{"sand",400},{"gunpowder",100},{"oil",150}},
    {housing={"龙容量","Dragon capacity"}})
define("gel_pool","production","凝胶池","Gel pool",3,{{"slime",250},{"water",150},{"soil",100}},
    {housing={"凝胶容量","Gel capacity"}})

define("dog_kennel","production","狗窝","Kennel",3,{{"sand",150},{"water",100},{"fiber",8}},
    {housing={"犬容量","Hound capacity"}})

define("cat_house","production","猫窝","Cattery",3,{{"sand",150},{"water",100},{"fiber",8}},
    {housing={"猫容量","Cat capacity"}})

local material_names={
    oil={"油","Oil"},
    arcane_scrap={"奥术碎片","Arcane scrap"},
    fiber={"纤维","Fiber"},sugar={"糖分","Sugar"},
    empty_container={"仓库空容器","Empty containers in storage"},container_scrap={"容器碎片","Container scrap"},
}
local function inventory(s,key)
    if key=="arcane_scrap" or key=="container_scrap" or NHFarm.crops[key] or NHEssences.types[key] or NHStore.alchemyResources[key] then return s.resources end
    return s.materials
end

function NHStore.emptyContainerCount(s)
    local count=0
    for _,row in ipairs(s.warehouse) do
        if NHPotion.isEmptyContainer(row.item) then count=count+1 end
    end
    return count
end

function NHStore.spendEmptyContainers(s,count)
    if type(count)~="number" or count<1 or count~=math.floor(count) then return false,"Invalid empty container cost." end
    local candidates={}
    for i,row in ipairs(s.warehouse) do
        if NHPotion.isEmptyContainer(row.item) then
            candidates[#candidates+1]={index=i,slot=row.slot or i}
        end
    end
    if #candidates<count then return false,"Not enough empty containers." end
    -- Pay from the first visible warehouse slots, regardless of deposit order.
    table.sort(candidates,function(a,b) return a.slot<b.slot end)
    local spent={}
    for i=1,count do spent[candidates[i].index]=true end
    for i=#s.warehouse,1,-1 do
        if spent[i] then table.remove(s.warehouse,i) end
    end
    return true
end

local function costs(s,entry,level,empty_count,lang)
    local result={}
    local payment={materials={},resources={}}
    local funded=true
    local zh=lang=="zh"
    local function add(key,amount)
        local stock=inventory(s,key)
        local available=key=="empty_container" and empty_count or stock[key] or 0
        local alternatives,name
        if stock==s.materials and key~="empty_container" then
            local input={name=key}
            local sources,labelZh,labelEn=NHStore.ingredientSources(input,entry.group)
            if #sources>1 then
                alternatives=sources
                available=NHStore.ingredientStock(s,input,entry.group)
                if labelZh then name=zh and labelZh.."（合计）" or labelEn.." (total)" end
            end
        end
        local resource=NHEssences.types[key] or NHStore.alchemyResources[key]
        if resource then name=zh and resource.zh or resource.en
        elseif not name then name=material_names[key][zh and 1 or 2] end
        result[#result+1]={key=key,name=name,amount=amount,
            available=available,alternatives=alternatives}
        if key=="empty_container" then
            payment.shells=amount
            if available<amount then funded=false end
        else
            local account=stock==s.materials and payment.materials or payment.resources
            if not NHStore.allocateIngredient(stock,alternatives or {key},amount,account) then funded=false end
        end
    end
    if entry.tiers then
        local tier=level+1
        add("nh_philosopher_stone",tier)
        add("arcane_scrap",({1,5,15})[tier])
        add("container_scrap",5)
        add(entry.essence,100*tier)
    else
        for _,part in ipairs(entry.cost) do add(part[1],part[2]*(level+1)) end
    end
    if entry.category and level>=1 then add("empty_container",level) end
    if entry.category and level>=2 then add("container_scrap",level-1) end
    if entry.id=="safe" and level>=4 then add("container_scrap",level-3) end
    return result,funded and payment or nil
end

function NHStore.level(s,id)
    return (s.levels and s.levels[id]) or 0
end

local function base_capacity(category) return category=="materials" and 16 or 48 end
function NHStore.warehouseCapacity(s,category)
    local base=(s.storageBase and s.storageBase[category]) or base_capacity(category)
    local step=category=="materials" and 8 or 24
    return base+step*NHStore.level(s,"warehouse_"..category)
end

-- Count material types after payment and delivery, including an already
-- funded order's output so unloading another container cannot displace it.
local function material_slots(s,incoming,outgoing)
    local present={}
    for name,count in pairs(s.materials) do
        if count>((outgoing and outgoing[name]) or 0) then present[name]=true end
    end
    for name,count in pairs(incoming or {}) do if count>0 then present[name]=true end end
    local reserved=s.order and s.order.output and s.order.output.materials
    for name,count in pairs(reserved or {}) do if count>0 then present[name]=true end end
    local n=0
    for _ in pairs(present) do n=n+1 end
    return n
end

function NHStore.canStockMaterials(s,incoming,outgoing)
    -- Keep enough numeric headroom for any paid delivery (including its
    -- borrowed samples), even if a flask is unloaded before the order finishes.
    local reserved=s.order and s.order.output and s.order.output.materials
    for name,count in pairs(incoming or {}) do
        local stock=(s.materials[name] or 0)-((outgoing and outgoing[name]) or 0)
        if count>NHStore.maxMaterialAmount-stock-((reserved and reserved[name]) or 0) then return false end
    end
    return material_slots(s,incoming,outgoing)<=NHStore.warehouseCapacity(s,"materials")
end

local function description(s,entry,offset,lang)
    local zh=lang=="zh"
    if entry.category then
        local is_bulk=entry.category=="materials"
        local amount=NHStore.warehouseCapacity(s,entry.category)+offset*(is_bulk and 8 or 24)
        if is_bulk then return amount..(zh and " 种物料" or " material types") end
        return amount..(zh and " 格" or " slots")
    end
    if entry.id=="safe" then return (NHStore.safeCapacity(s)+offset)..(zh and " 格" or " slots") end
    local level=NHStore.level(s,entry.id)+offset
    local efficiency=""
    if entry.section=="production" and level>0 then
        local percent=NHFarm.levelBasisPoints(entry.id,level)/100
        if percent>0 then efficiency=string.format(zh and " · 产量 +%g%%" or " · yield +%g%%",percent) end
    end
    if entry.id=="farmland" then return level..(zh and " 块田地" or (level==1 and " field" or " fields"))..efficiency end
    if entry.housing then
        local text=entry.housing[zh and 1 or 2].." "..NHLivestock.capacityAtLevel(level)
        if entry.id=="gel_pool" and offset==1 and level==1 then
            text=text..(zh and "，附带 1 只成熟凝胶" or " (includes 1 adult gel)")
        end
        return text..efficiency
    end
    if entry.id=="perk_slots" then return (1+level)..(zh and " 个遗物插槽" or " relic sockets") end
    if level==0 then return zh and "未解锁" or "Locked" end
    if entry.tiers then return entry.tiers[level][zh and 1 or 2] end
    return entry.effect[zh and 1 or 2]..efficiency
end

function NHStore.progressMenu(s,lang)
    local result={expansion={},upgrade={}}
    local zh=lang=="zh"
    local empty_count=NHStore.emptyContainerCount(s)
    for _,entry in ipairs(catalog) do
        local level=NHStore.level(s,entry.id)
        local maxed=not entry.planned and (level>=entry.max or (entry.id=="safe" and NHStore.safeCapacity(s)>=12))
        local row={id=entry.id,section=entry.section,name=zh and entry.zh or entry.en,level=level,planned=entry.planned or false,
            maxed=maxed,canBuy=not maxed and not entry.planned,costs={},current=description(s,entry,0,lang)}
        if entry.planned then row.next=(zh and "后续开放 · " or "Planned: ")..entry.effect[zh and 1 or 2]
        elseif maxed then row.next=zh and "已满级" or "Max level"
        else
            row.next=description(s,entry,1,lang)
            local payment
            row.costs,payment=costs(s,entry,level,empty_count,lang)
            row.canBuy=payment~=nil
            if entry.id=="agri_equipment" and NHStore.level(s,"farmland")==0 then
                row.canBuy=false
                row.next=(zh and "先开垦一块田 · " or "Requires farmland · ")..row.next
            end
            if row.canBuy then row.materialPayment=payment.materials end
        end
        if entry.id~="perk_pack" or (NHPerks and NHPerks.enabled) then table.insert(result[entry.group],row) end
    end
    return result
end

function NHStore.buyUpgrade(s,request,now)
    local entry=type(request)=="table" and definitions[request.id]
    if not entry or entry.planned or (entry.id=="perk_pack" and not (NHPerks and NHPerks.enabled)) then return false,"Construction unavailable." end
    local level=NHStore.level(s,entry.id)
    if level~=request.level or level>=entry.max or (entry.id=="safe" and NHStore.safeCapacity(s)>=12) then return false,"Upgrade level changed." end
    if entry.id=="agri_equipment" and NHStore.level(s,"farmland")==0 then return false,"A farm plot is required." end
    local _,payment=costs(s,entry,level,NHStore.emptyContainerCount(s))
    if not payment then return false,"Not enough construction resources." end
    if entry.id=="safe" then
        local ok,reason=NHStore.expandSafe(s,NHStore.safeCapacity(s)+1)
        if not ok then return false,reason end
    end
    if payment.shells then
        local ok,reason=NHStore.spendEmptyContainers(s,payment.shells)
        if not ok then return false,reason end
    end
    if entry.section=="production" then NHFarm.sync(s,now or s.farm.time) end
    NHStore.deductStock(s.materials,payment.materials)
    NHStore.deductStock(s.resources,payment.resources)
    s.levels[entry.id]=level+1
    if entry.id=="gel_pool" and level==0 then
        NHLivestock.deliver(s,"gel_pool",NHLivestock.freePen(s,"gel_pool"),now,true)
    end
    return true
end

local function adopt(s)
    if s.levels then
        -- A pouch in an expanded supply grid may have no matching slot in the new equipment grid.
        for _,pouch in pairs(s.pouches) do
            if pouch.location=="warehouse" and not s.levels.warehouse_equipment
                and pouch.slot>NHStore.warehouseCapacity(s,"equipment")
                and pouch.slot<=NHStore.warehouseCapacity(s,"supplies") then
                pouch.slot=assert(NHStore.freeSlot(s,"warehouse",nil,"pouch"),"No equipment slot for stored pouch")
            end
        end
        return
    end
    s.levels,s.storageBase,s.resources={},{},{}
    -- Existing profiles had unlimited storage. Retain every occupied cell.
    local function preserve(category,used)
        if used>(s.storageBase[category] or base_capacity(category)) then s.storageBase[category]=used end
    end
    for i,row in ipairs(s.warehouse) do preserve(NHStore.category(row.item.kind),row.slot or i) end
    for _,pouch in pairs(s.pouches) do
        if pouch.location=="warehouse" then preserve("equipment",pouch.slot) end
    end
    preserve("materials",material_slots(s))
end

local function validate(s,whole)
    assert(type(s.levels)=="table" and type(s.resources)=="table" and type(s.storageBase)=="table","Invalid hideout development")
    for id,level in pairs(s.levels) do
        assert(definitions[id] and whole(level) and level<=definitions[id].max,"Invalid facility level")
    end
    for category,base in pairs(s.storageBase) do
        assert(definitions["warehouse_"..category] and whole(base) and base>=base_capacity(category),"Invalid warehouse capacity")
    end
    for resource,count in pairs(s.resources) do assert(type(resource)=="string" and whole(count),"Invalid hideout resource") end
    assert(NHStore.canStockMaterials(s),"Material storage capacity exceeded")
end

return {adopt=adopt,validate=validate}
