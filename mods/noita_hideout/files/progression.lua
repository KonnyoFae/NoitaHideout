-- All purchases operate on the detached profile passed to NHStore.commit.
local catalog = {}
local definitions = {}
local function define(id,group,zh,en,max,cost,options)
    local entry=options or {}
    entry.id,entry.group,entry.zh,entry.en,entry.max,entry.cost=id,group,zh,en,max,cost
    catalog[#catalog+1]=entry
    definitions[id]=entry
end

local stock_cost={{"sand",200},{"water",100}}
define("warehouse_wand","expansion","魔杖库","Wand storage",4,stock_cost,{category="wand"})
define("warehouse_spell","expansion","法术库","Spell storage",4,stock_cost,{category="spell"})
define("warehouse_containers","expansion","容器库","Container storage",4,stock_cost,{category="containers"})
define("warehouse_supplies","expansion","消耗品库","Supply storage",4,stock_cost,{category="supplies"})
define("warehouse_equipment","expansion","装备库","Equipment storage",4,stock_cost,{category="equipment"})
define("warehouse_materials","expansion","物料库","Material storage",4,{{"sand",250},{"slime",100}},{category="materials"})
define("medical","expansion","医疗工位","Medical station",1,{{"water",250},{"slime",100}},
    {effect={"制造医疗物品","Craft medical supplies"}})
define("injector","expansion","针剂工位","Injector station",1,{{"water",250},{"oil",100}},
    {effect={"制造针剂","Craft injectors"}})
define("grenade","expansion","手雷工位","Grenade station",1,{{"gunpowder",150},{"oil",100}},
    {effect={"制造手雷","Craft grenades"}})
define("salvage","expansion","拆解台","Salvage bench",1,{{"sand",250},{"oil",100}},
    {effect={"拆解魔杖、法术与空容器","Salvage wands, spells and empty containers"}})
define("support","expansion","支援站","Support station",0,{},
    {planned=true,effect={"呼叫支援","Call for support"}})
define("perk_pack","expansion","特质打包台","Perk packing",1,{{"slime",200},{"arcane_scrap",1}},
    {effect={"封装附近未拾取的免疫特质","Pack nearby immunity perks"}})
define("safe","upgrade","随身安全箱","Secure case",4,{{"sand",250},{"slime",150}})
define("perk_slots","upgrade","特质栏","Perk slots",3,{{"water",250},{"slime",100}})

local material_names={
    water={"水","Water"},sand={"沙","Sand"},slime={"黏液","Slime"},oil={"油","Oil"},
    gunpowder={"火药","Gunpowder"},arcane_scrap={"奥术碎片","Arcane scrap"},
    empty_container={"仓库空容器","Empty containers in storage"},container_scrap={"容器碎片","Container scrap"},
}
local function inventory(s,key)
    if key=="arcane_scrap" or key=="container_scrap" then return s.resources end
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
    local function add(key,amount)
        local available=key=="empty_container" and empty_count or inventory(s,key)[key] or 0
        result[#result+1]={key=key,name=material_names[key][lang=="zh" and 1 or 2],amount=amount,available=available}
    end
    for _,part in ipairs(entry.cost) do add(part[1],part[2]*(level+1)) end
    if entry.category and level>=1 then add("empty_container",level) end
    if entry.category and level>=2 then add("container_scrap",level-1) end
    return result
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
    if entry.id=="perk_slots" then return level..(zh and " 个特质栏位" or " perk slots") end
    if level==0 then return zh and "未解锁" or "Locked" end
    return entry.effect[zh and 1 or 2]
end

function NHStore.progressMenu(s,lang)
    local result={expansion={},upgrade={}}
    local zh=lang=="zh"
    local empty_count=NHStore.emptyContainerCount(s)
    for _,entry in ipairs(catalog) do
        local level=NHStore.level(s,entry.id)
        local maxed=not entry.planned and level>=entry.max
        local row={id=entry.id,name=zh and entry.zh or entry.en,level=level,planned=entry.planned or false,
            maxed=maxed,canBuy=not maxed and not entry.planned,costs={},current=description(s,entry,0,lang)}
        if entry.planned then row.next=(zh and "后续开放 · " or "Planned: ")..entry.effect[zh and 1 or 2]
        elseif maxed then row.next=zh and "已满级" or "Max level"
        else
            row.next=description(s,entry,1,lang)
            row.costs=costs(s,entry,level,empty_count,lang)
            for _,part in ipairs(row.costs) do
                if part.available<part.amount then row.canBuy=false end
            end
        end
        table.insert(result[entry.group],row)
    end
    return result
end

function NHStore.buyUpgrade(s,request)
    local entry=type(request)=="table" and definitions[request.id]
    if not entry or entry.planned then return false,"Construction unavailable." end
    local level=NHStore.level(s,entry.id)
    if level~=request.level or level>=entry.max then return false,"Upgrade level changed." end
    local payment=costs(s,entry,level,NHStore.emptyContainerCount(s))
    local shells
    for _,part in ipairs(payment) do
        if part.available<part.amount then return false,"Not enough construction resources." end
        if part.key=="empty_container" then shells=part.amount end
    end
    if entry.id=="safe" then
        local ok,reason=NHStore.expandSafe(s,NHStore.safeCapacity(s)+1)
        if not ok then return false,reason end
    end
    if shells then
        local ok,reason=NHStore.spendEmptyContainers(s,shells)
        if not ok then return false,reason end
    end
    for _,part in ipairs(payment) do
        if part.key~="empty_container" then
            local stock=inventory(s,part.key)
            local remaining=stock[part.key]-part.amount
            stock[part.key]=remaining>0 and remaining or nil
        end
    end
    s.levels[entry.id]=level+1
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
