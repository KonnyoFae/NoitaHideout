NHUI = {}

local foods=dofile("mods/noita_hideout/files/cooking.lua").byId
local bags=(NHLootBags or dofile("mods/noita_hideout/files/loot_bags.lua")).types
local gunCatalog=NHGuns or dofile("mods/noita_hideout/files/guns.lua")
local guns=gunCatalog.types
local turretCatalog=NHTurrets or dofile("mods/noita_hideout/files/turrets.lua")
local turrets=turretCatalog.types
local stormProducts=NHStormProducts or dofile("mods/noita_hideout/files/storm_products.lua")
local gui
local scrollMenu=dofile("mods/noita_hideout/files/menu_scroll.lua")
local drawTravel=dofile("mods/noita_hideout/files/travel/hud.lua")
local worldBars=dofile("mods/noita_hideout/files/world_status_bar.lua")
local travelRoutes=dofile("mods/noita_hideout/files/travel/routes.lua")
local tab = "shop"
local homeWasOpen=false
local warehouse_tab, folded = "wand", false
local dismantle_mode=false
local sorted_stock={}
local secure_folded=false
local equipment_tab="gear"
local bankRowHeight=13
local bank_hold
local warehouse_tabs_y=22
local warehouse_tabs = {
    {id=75,key="wand",zh="魔杖",en="Wands",shortZh="杖",shortEn="Wand"},
    {id=76,key="spell",zh="法术",en="Spells",shortZh="术",shortEn="Spell"},
    {id=77,key="containers",zh="容器",en="Containers",shortEn="Cont."},
    {id=78,key="supplies",zh="消耗品",en="Supplies",shortZh="消耗",shortEn="Sup."},
    {id=79,key="equipment",zh="装备",en="Equipment",shortEn="Gear"},
    {id=80,key="materials",zh="物料",en="Materials",shortEn="Mats"},
    {id=82,key="essences",zh="精华",en="Essences",shortEn="Ess."},
    {id=83,key="collection",zh="藏品",en="Collection",shortEn="Cards"},
}
local workshop_folded=false
local travelSession
local recipe_category="alchemy"
local spell_family
local alchemy_mode="synthesis"
local shop_category="materials"
local expansion_section="inventory"
local selected_entry,salvage_target
local farm_page,selected_plot="plots",nil
local livestock_page,selected_pen="pens",nil
local work_tabs={
    {key="shop",id=220,zh="转化",en="Convert"},
    {key="orders",id=212,zh="工坊",en="Workshop"},
    {key="expansion",id=218,zh="扩建",en="Build"},
    {key="upgrade",id=219,zh="升级",en="Upgrades"},
    {key="farm",id=221,zh="种植",en="Farm"},
    {key="livestock",id=223,zh="畜牧",en="Livestock"},
    {key="samples",id=213,zh="测试物资",en="Supplies"},
}
local recipe_tabs={
    {key="alchemy",id=250,zh="炼金",en="Alchemy"},
    {key="medical",id=251,zh="医疗",en="Medical"},
    {key="weapons",id=252,zh="武器",en="Weapons"},
    {key="containers",id=266,zh="容器",en="Containers"},
    {key="equipment",id=253,zh="装备",en="Equipment"},
    {key="food",id=222,zh="食物",en="Food"},
    {key="spell",id=225,zh="法术",en="Spells"},
}
local alchemy_tabs={
    {key="synthesis",id=254,zh="炼成",en="Synthesis"},
    {key="decomposition",id=255,zh="分解",en="Decomposition"},
    {key="rubedo",id=267,zh="红化",en="Rubedo"},
    {key="logistics",id=268,zh="后勤资源包",en="Logistics packs"},
}
local shop_tabs={
    {key="storm_products",id=269,zh="产物转化",en="Storm products"},
    {key="services",id=265,zh="服务",en="Services"},
    {key="materials",id=256,zh="物料",en="Materials"},
    {key="supplies",id=257,zh="消耗品",en="Consumables"},
    {key="livestock",id=259,zh="幼畜",en="Youngstock"},
}
local expansion_tabs={
    {key="inventory",id=270,zh="库存",en="Storage"},
    {key="workshop",id=271,zh="工坊",en="Workshop"},
    {key="production",id=272,zh="生产",en="Production"},
    {key="support",id=273,zh="支援",en="Support"},
}
local farm_tabs={
    {key="plots",id=410,zh="田地",en="Plots"},
    {key="stock",id=411,zh="农产库存",en="Crop stock"},
}
local livestock_tabs={
    {key="pens",id=440,zh="栏舍",en="Pens"},
    {key="produce",id=441,zh="畜产库存",en="Produce"},
}
local white = { 0.96, 0.93, 0.84 }
local gold = { 1.00, 0.83, 0.47 }
local muted = { 0.76, 0.80, 0.78 }
local green = { 0.62, 0.95, 0.75 }
local function tint(color)
    GuiColorSetForNextWidget(gui, color[1], color[2], color[3], 1)
end

-- Trim at character boundaries. The GUI can run with either Chinese or English game fonts.
local function fit(value, available, scale)
    local original = tostring(value or ""):gsub("[\r\n]+", " ")
    local width = GuiGetTextDimensions(gui, original, scale)
    if width <= available then return original, false end
    local chars = {}
    for char in original:gmatch("[^\128-\191][\128-\191]*") do
        chars[#chars + 1] = char
    end
    local lo, hi = 0, #chars
    while lo < hi do
        local n = math.ceil((lo + hi) / 2)
        local w = GuiGetTextDimensions(gui, table.concat(chars, "", 1, n) .. "...", scale)
        if w <= available then lo = n else hi = n - 1 end
    end
    return table.concat(chars, "", 1, lo) .. "...", true
end

local drag, last_case_frame
local last_inventory_layout
local case_columns,case_rows=4,3
local visible_case_slots=case_columns*case_rows
local equipment_tabs_y,equipment_grid_y=19,36
local revealSafe
local loading
local transfer_slot
function NHUI.showTransfer(container,kind,slot)
    if container=="gear" then
        secure_folded,equipment_tab=false,"gear"
    elseif container=="safe" then
        secure_folded,equipment_tab=false,"safe"
        revealSafe=math.floor((slot-1)/case_columns)
    else
        folded,loading,dismantle_mode=false,nil,false
        warehouse_tab=container=="docks" and "materials" or NHStore.category(kind)
        transfer_slot=container=="warehouse" and slot or nil
    end
end
local material_rows=4
local function compact(n)
    local unit,suffix
    if n>=1e12 then unit,suffix=1e12,"T"
    elseif n>=1e9 then unit,suffix=1e9,"B"
    elseif n>=1e6 then unit,suffix=1e6,"M"
    elseif n>=1e3 then unit,suffix=1e3,"k"
    else return tostring(n) end
    return tostring(math.floor(n/unit*10)/10)..suffix
end
local function storage_key(key)
    if key=="valuable" then return "safe" end
    if key=="warehouse" or key=="docks" then return key end
end

local function slot_at(layout,x,y)
    for i=#layout,1,-1 do
        local box=layout[i]
        if x>=box.x and y>=box.y and x<box.x+box.w and y<box.y+box.h then return box.slot end
    end
end

local function use_source(slot)
    if not slot or not slot.kind then return end
    if slot.dismantle and not (slot.dismantle=="supplies" and bags[slot.kind]) then return end
    if not (slot.key=="valuable" and slot.kind=="relic_chain") and not NHNative.usableKind(slot.kind) then return end
    local source={kind=slot.kind}
    if slot.key=="native" and slot.entity then
        source.container,source.entity,source.parent="native",slot.entity,slot.parent
        source.lane,source.xslot,source.yslot=slot.lane,slot.xslot,slot.yslot
    elseif (slot.key=="warehouse" or slot.key=="valuable") and slot.entity then
        source.container,source.slot,source.storedId=storage_key(slot.key),slot.safeSlot,slot.entity
        if slot.key=="warehouse" and NHRedRelics.types[slot.kind] and NHUI.shiftDown() then source.preview=true end
    elseif slot.key=="gear" and (NHShields.supply(slot.kind) or NHEquipment.links[slot.kind]) and slot.entity then
        source.container,source.storedId="gear",slot.entity
    elseif slot.key=="dose" and slot.pouchId then
        source.container,source.pouchId,source.cell="pouch",slot.pouchId,slot.cell
    elseif slot.key=="card_cell" and slot.walletId then
        source.container,source.walletId,source.cell="card_wallet",slot.walletId,slot.cell
    else return end
    source.remaining,source.count,source.subtype,source.species=slot.remaining,slot.count,slot.subtype,slot.species
    return source
end

local function hovered_inventory_slot()
    local layout=last_inventory_layout
    if not layout or drag then return end
    local age=GameGetFrameNum()-layout.frame
    if age<0 or age>1 then return end
    local sw,sh=GuiGetScreenDimensions(gui)
    if sw~=layout.width or sh~=layout.height then return end
    local wx,wy=DEBUG_GetMouseWorld()
    local cx,cy,cw,ch=GameGetCameraBounds()
    return slot_at(layout,(wx-cx)*sw/cw,(wy-cy)*sh/ch)
end

function NHUI.useTarget()
    return use_source(hovered_inventory_slot())
end

local function quick_source(slot)
    return slot and not slot.dismantle and slot.entity and slot.kind and slot.kind~="other"
        and (slot.key=="native" or slot.key=="valuable" or slot.key=="warehouse" or slot.key=="docks")
end

function NHUI.quickTarget()
    local slot=hovered_inventory_slot()
    if quick_source(slot) then return slot end
end

function NHUI.shiftDown()
    return InputIsKeyDown and (InputIsKeyDown(225) or InputIsKeyDown(229))
end

local function same_use(source,prepared)
    if not source then return false end
    for key,value in pairs(source) do if prepared[key]~=value then return false end end
    for key,value in pairs(prepared) do if source[key]~=value then return false end end
    return true
end
local full_tile = "data/ui_gfx/inventory/full_inventory_box.png"
local tile = "data/ui_gfx/inventory/quick_inventory_box.png"
local icons = {
    pouch = "mods/noita_hideout/files/items/pouch.png",
    dose = "mods/noita_hideout/files/items/dose.png",
    wand = "data/items_gfx/handgun.png", potion = "data/items_gfx/potion.png",
}

local function cursor_tip(lines,mx,my,sw,sh,scale)
    local pad=4*scale
    local line_h=10*scale
    local limit=math.max(1,math.floor((sh-2*pad-4)/line_h))
    local width=0
    local count=math.min(#lines,limit)
    for i=1,count do
        if i==limit and #lines>limit then lines[i]="… +"..(#lines-limit+1) end
        lines[i]=fit(lines[i],sw-2*pad-4,scale)
        local text_width=GuiGetTextDimensions(gui,lines[i],scale)
        width=math.max(width,text_width)
    end
    width=width+2*pad
    local height=count*line_h+2*pad
    local x,y=mx+8*scale,my+8*scale
    if x+width>sw-2 then x=mx-width-5*scale end
    if y+height>sh-2 then y=my-height-5*scale end
    x=math.max(2,math.min(x,sw-width-2))
    y=math.max(2,math.min(y,sh-height-2))
    GuiZSetForNextWidget(gui,-92)
    GuiImageNinePiece(gui,200,x,y,width,height,1)
    for i=1,count do
        GuiZSetForNextWidget(gui,-93)
        tint(i==1 and gold or white)
        GuiText(gui,x+pad,y+pad+(i-1)*line_h,lines[i],scale)
    end
end

local function item_details(slot,model,tr)
    local red=NHRedRelics.types[slot.kind]
    if red then
        local current=(slot.view or slot).remaining
        local lines={tr(red.zh,red.en),tr(red.noteZh,red.noteEn)}
        if current~=nil then lines[#lines+1]=string.format(tr("剩余耐久 %d / %d","Durability %d / %d"),current,red.item.remaining) end
        if current==0 then lines[#lines+1]=tr("已耗尽，仍可全额分解","Exhausted. Dismantles for full value.") end
        return lines
    end
    local shield=NHShields.types[slot.kind]
    if shield then
        local charge=slot.view and slot.view.charge or shield.cells*NHShields.cell
        return {tr(shield.zh,shield.en),string.format(tr("盾量 %.2f / %d 格","Charge %.2f / %d cells"),charge/NHShields.cell,shield.cells),
            tr("每格为最大生命的 50%（初始 50 点）","Each cell holds 50% max HP (initially 50 points)"),
            tr("盾上减伤 ","Shield resistance ")..shield.resist.."%",shield.poly and tr("装备时免疫变形","Polymorph immunity while equipped") or nil}
    elseif NHFirearms.rigs[slot.kind] then
        return {slot.name,string.format(tr("备弹 %d / %d","Reserve %d / %d"),(slot.view or slot).reserve or 0,NHFirearms.rigs[slot.kind].capacity)}
    elseif NHFirearms.items[slot.kind] and NHFirearms.items[slot.kind].magazine then
        local d=NHFirearms.items[slot.kind]
        if d.fixed then return {tr(d.zh,d.en),tr(d.noteZh,d.noteEn)} end
        return {tr(d.zh,d.en),string.format(tr("枪内 %d / %d","Loaded %d / %d"),(slot.view or slot).rounds or 0,d.magazine),tr(d.noteZh,d.noteEn),tr("单击已存放的枪以装配","Click a stored gun to fit attachments")}
    elseif NHShields.supply(slot.kind) then
        local d=NHShields.supply(slot.kind)
        return {tr(d.zh,d.en),tr(d.noteZh,d.noteEn),string.format(tr("剩余耐久 %d / %d","Uses left %d / %d"),slot.remaining or d.uses,d.uses)}
    end
    local record=slot.view and slot.view.potion
    if record then
        local used,capacity=NHPotion.fillLevel(record)
        local lines={NHPotion.containerName(record,model.lang).."  "..used.."/"..capacity}
        local names={}
        for name in pairs(record.materials) do names[#names+1]=name end
        table.sort(names)
        for _,name in ipairs(names) do
            lines[#lines+1]=NHPotion.materialName(name,model.lang).."  "..string.format("%.0f",record.materials[name])
        end
        return lines
    end
    if slot.kind=="relic" and slot.view then return {slot.name,NHRelics.description(slot.view.relic,model.lang)} end
    if slot.kind=="relic_chain" then
        local lines={slot.name}
        if slot.view and slot.view.relics then
            for _,name in ipairs(slot.view.relics) do lines[#lines+1]=name end
            if #slot.view.relics==0 then lines[#lines+1]=tr("未装入遗物","No relics socketed.") end
        end
        lines[#lines+1]=slot.key=="valuable" and tr("点击或右键打开，拖入遗物以激活","Click or right-click to open. Drag in a relic to activate it.")
            or tr("移入安全箱后可打开遗物链，取出或激活遗物","Move to the secure case to open the chain and remove or activate relics.")
        return lines
    end
    if slot.kind=="pouch" or slot.kind=="card_wallet" then
        local details={slot.name,tr("点击或右键打开，拖动移动","Click or right-click to open. Drag to move.")}
        if slot.view and slot.view.capacity then
            table.insert(details,2,tr("容量 ","Slots ")..slot.view.capacity)
        end
        if slot.view and slot.view.doses then
            table.insert(details,2,tr("针剂数量 ","Injectors: ")..slot.view.doses)
        end
        return details
    end
    local turret=turrets[slot.kind]
    local storm=stormProducts.types[slot.kind]
    if storm then return {tr(storm.zh,storm.en).." ×"..(slot.count or 1),
        tr("每组上限 ","Stack limit ")..stormProducts.stackLimit,
        tr("在消耗品页转为藏身处资源","Convert to hideout resources in Supplies."),
        tr("在产物转化页加工或出售资源","Process or sell resources in Storm products.")} end
    if turret then return {tr(turret.zh,turret.en).." ×"..(slot.count or 1),tr(turret.noteZh,turret.noteEn)} end
    local gun=guns[slot.kind]
    if gun then return {tr(gun.zh,gun.en).." ×"..(slot.count or 1),
        tr("当前弹量 ","Loaded ")..slot.remaining.."/"..gun.capacity,tr(gun.noteZh,gun.noteEn)} end
    local bag=bags[slot.kind]
    if bag and bag.guaranteedPack then
        local pack=bags[bag.guaranteedPack]
        return {tr(bag.zh,bag.en).." ×"..(slot.count or 1),
            tr("右键开启，必得一个","Right-click for one ")..tr(pack.zh,pack.en),
            tr("另得一件奖励","Plus one bonus item"),
            tr("食品 %d%% · 遗物 %d%% · 塔罗牌 %d%%","Food %d%% · Relic %d%% · Tarot %d%%"):format(bag.food,bag.relic,bag.tarot)}
    end
    if bag and bag.loot then
        local loot=bags[bag.loot]
        return {tr(bag.zh,bag.en).." ×"..(slot.count or 1),tr("补满已装备护盾与弹挂","Refills equipped shield and ammo rig"),
            tr("充能器、弹药盒各一件","One charger and one ammo box"),tr("普通随机奖励 · ","Standard loot · ")..tr(loot.zh,loot.en)}
    end
    if bag then
        local chance=bag.chances
        return {tr(bag.zh,bag.en).." ×"..(slot.count or 1),tr("右键打开，奖励落在脚边","Right-click to open at your feet"),
            tr("必得 %d 金和一件补给","Always drops %d gold and one supply"):format(bag.gold*10),
            tr("食物 %d%% · 医疗 %d%%","Food %d%% · Medical %d%%"):format(chance.food,chance.medical),
            tr("工具 %d%% · 针剂 %d%%","Tool %d%% · Injector %d%%"):format(chance.tool,chance.dose),
            tr("额外掉落 · 塔罗牌 %d%% · 同伴卡 %d%%","Bonus drops · Tarot %d%% · Companion card %d%%"):format(bag.tarot,bag.card),
            bag.red and tr("额外大红 %d%% · 每盒独立","Extra red relic %d%% · Independent per box"):format(bag.red) or nil}
    end
    local food=foods[slot.kind]
    if food then
        local lines={slot.name,tr("当前份剩余 ","Current portion ")..(slot.remaining or food.uses).."/"..food.uses
            ..tr("   数量 ","   Count ")..(slot.count or 1)}
        for _,note in ipairs(tr(food.notesZh,food.notesEn)) do lines[#lines+1]=note end
        return lines
    end
    if NHEquipment.links[slot.kind] then
        local device=NHEquipment.links[slot.kind]
        return {slot.name,tr("剩余部署次数 ","Deployments left ")..(slot.remaining or device.uses).."/"..device.uses,
            tr(device.noteZh,device.noteEn)}
    end
    local surgery=NHSurgeryKits.types[slot.kind]
    if surgery then
        return {slot.name,tr("清除负面状态","Clears harmful conditions"),
            string.format(tr("恢复最大生命的 %d%%","Restores %d%% of maximum HP"),surgery.healPercent),
            string.format(tr("用时 %d 秒，受伤时仍可继续","Takes %d s, even while taking damage."),surgery.castFrames/60),
            tr("剩余次数 ","Uses left ")..(slot.remaining or surgery.uses).."/"..surgery.uses.."  ×"..(slot.count or 1)}
    end
    local kit=NHMedkits.types[slot.kind]
    if kit then
        local healing=string.format(tr("用时 %g 秒，恢复最大生命的 %d%%","After %g s, restores %d%% of max HP"),kit.castFrames/60,kit.healPercent)
        return {(slot.name or kit.zh)..((slot.count or 1)>1 and " ×"..slot.count or ""),tr("剩余次数 ","Uses left ")..(slot.remaining or kit.uses).."/"..kit.uses,healing}
    end
    if slot.kind=="summon_card" then
        local species=NHCompanions.cardDefinition(slot.species)
        local lines={species and tr(species.zh,species.en) or slot.name,
            tr("耐久 ","Durability ")..slot.remaining.."/"..NHCompanions.cardCapacity(slot.species),
            tr("数量 ","Count ")..string.format("%.0f",slot.count or 1)}
        if NHTarot.types[slot.species] then lines[#lines+1]=tr(species.noteZh,species.noteEn); return lines end
        if not species then return lines end
        lines[#lines+1]=tr(species.combatZh,species.combatEn)
        local immunity=NHCompanions.immunities.types[slot.species]
        lines[#lines+1]=tr(immunity.zh,immunity.en)
        if not model.affinityPoints then return lines end
        local points=model.affinityPoints(slot.species)
        local tier=NHAffinity.tier(points)
        local bonus=NHCompanions.bonuses[tier]
        local affinity=tr("好感度 ","Affinity ")..points.."/"..NHAffinity.maxPoints
        local nextTier=NHAffinity.thresholds[tier+2]
        lines[#lines+1]=nextTier and (affinity..tr("   下一阶段 ","   Next at ")..nextTier) or affinity
        lines[#lines+1]=tr("救援可保留金币 ","Gold kept on rescue: ")..points
        lines[#lines+1]=tr("随行时对应设施产量 +","Matching facility output while active +")..("%.2f%%"):format(NHAffinity.productionBasisPoints(points)/100)
        if points>1000 then lines[#lines+1]=tr("随行产卡概率 +","Extra card chance +")..("%.2f%%"):format(NHAffinity.incomeBasisPoints(points)/100) end
        if slot.species=="dryad" then lines[#lines+1]=tr("毒泥免疫","Toxic sludge immunity")
        elseif slot.species=="bee" then lines[#lines+1]=tr("提高移动速度","Faster movement") end
        if species.shield and bonus.shieldRecharge>0 then
            local rate=math.floor(100*bonus.shieldRecharge/NHCompanions.bonuses[3].shieldRecharge+0.5)
            lines[#lines+1]=tr("飞弹护盾 · 原版充能速度的 %d%%","Projectile shield at %d%% of normal recharge"):format(rate)
        end
        if species.role=="flight" then
            lines[#lines+1]=tr("上升速度 +%d%%","Ascent speed +%d%%"):format(species.lift+bonus.lift)
            lines[#lines+1]=tr("每秒恢复 %d%% 飞行能量","Restores %d%% flight fuel per second"):format(species.fuel+bonus.fuel)
        elseif species.role=="melee" then
            lines[#lines+1]=tr("领域半径 %d，每半秒造成 %d 近战伤害","Field radius %d, deals %d melee damage every 0.5 s"):format(species.radius,bonus.fieldDamage)
            lines[#lines+1]=tr("近战减伤 %d%%，免疫击退","Melee resistance %d%%, knockback immunity"):format(bonus.meleeResist)
        else
            lines[#lines+1]=tr("每秒恢复最大生命的 %g%%","Heals %g%% of max HP per second"):format(bonus.heal)
            lines[#lines+1]=tr("行动速度 +%d%%","Movement speed +%d%%"):format(bonus.speed)
            lines[#lines+1]=tr("持续汇聚法力，法杖额外回复 %d 法力/秒","Mana regeneration, extra %d wand mana/s"):format(bonus.mana)
        end
        lines[#lines+1]=tr("每 %d 分钟赠送 %d 级礼物盒","Every %d min: tier %d gift box"):format(NHCompanions.giftMinutes(species),bonus.giftLevel)
        return lines
    end
    if slot.kind=="dose" then
        local d=NHInjectors.get(slot.subtype)
        return {tr(d.zh,d.en),tr("耐久 ","Durability ")..(slot.remaining or model.maxUses).."/"..model.maxUses
            ..tr("   数量 ","   Count ")..(slot.count or 1),tr(d.zhEffect,d.enEffect)}
    end
    local throwable=NHThrowables.types[slot.kind]
    if throwable then
        return {tr(throwable.zh,throwable.en).." ×"..(slot.count or 1),tr(throwable.noteZh,throwable.noteEn)}
    end
    return {slot.name or slot.kind}
end

-- Dimensions here are GUI units. Container cells keep the native tile pitch
-- while the three panels share the available horizontal space at spawn.
local function home_layout(sw,scale,tile_width)
    local room=(sw-10)/scale-10
    local bench=math.min(186,math.floor(room*0.30))
    local stash=math.min(230,math.floor(room*0.43))
    local secure=math.min(187,math.max(16+4*tile_width,room-bench-stash))
    stash=math.min(stash,room-bench-secure)
    local stash_x=sw-5-stash*scale
    local middle=(5+secure*scale+stash_x-bench*scale)/2
    return {stashX=stash_x,stash=stash,middle=middle,bench=bench,secure=secure}
end

local function stash_tabs(width,scale,tr)
    local tabs={}
    local available=width-8
    local label_room=available-(#warehouse_tabs-1)*2
    local total=0
    for i,t in ipairs(warehouse_tabs) do
        local name=tr(t.zh,t.en)
        local w=GuiGetTextDimensions(gui,name,scale)/scale
        tabs[i]={name=name,full=name,w=w}
        total=total+w
    end
    -- Use recognizable short labels before shrinking text on narrow displays.
    if total*0.85>label_room then
        total=0
        for i,t in ipairs(warehouse_tabs) do
            local pos=tabs[i]
            pos.name=tr(t.shortZh or t.zh,t.shortEn or t.en)
            pos.w=GuiGetTextDimensions(gui,pos.name,scale)/scale
            total=total+pos.w
        end
    end
    local factor=math.min(1,label_room/total)
    local spacing=math.min(8,(available-total*factor)/(#tabs-1))
    local x=4
    for _,pos in ipairs(tabs) do
        pos.x,pos.scale,pos.w=x,scale*factor,pos.w*factor
        x=x+pos.w+spacing
    end
    return tabs,warehouse_tabs_y+15
end

local function time_text(seconds)
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end

local function rate_text(rate)
    return (string.format("%.2f",rate):gsub("%.?0+$",""))
end

local function transfer_batch(elapsed,limit)
    if elapsed==0 then return 1 end
    if elapsed>=24 and (elapsed-24)%6==0 then
        return math.min(limit,5*2^math.floor((elapsed-24)/24))
    end
end

local bankUnits={"","k","M","B","T","P"}
local function bank_amount(n)
    if n<1000 then return string.format("%.0f",n) end
    local unit,index=1,1
    while index<#bankUnits and n>=unit*1000 do unit,index=unit*1000,index+1 end
    local precision=n>=100*unit and 1 or n>=10*unit and 10 or 100
    return tostring(math.floor(n/(unit/precision))/precision)..bankUnits[index]
end

local function open_shop()
    tab,selected_entry,salvage_target,bank_hold="shop",nil,nil,nil
end

local function draw_shop_bank(model,left,top,width,scale,tr,dispatch,mx,my)
    local title=tr("存款余额：","Savings:")
    local deposit,withdraw=tr("[存入]","[Deposit]"),tr("[取出]","[Withdraw]")
    local balance=model.bankGold or 0
    local amount=bank_amount(balance)
    local titleW=GuiGetTextDimensions(gui,title)
    local depositW=GuiGetTextDimensions(gui,deposit)
    local withdrawW=GuiGetTextDimensions(gui,withdraw)
    -- Reserve a fixed balance cell so crossing 999 or 1M cannot interrupt a held transfer.
    local balanceW=GuiGetTextDimensions(gui,"8.88M")
    local gap=2
    local rowScale=scale*math.min(1,(width-12)/(titleW+depositW+balanceW+withdrawW+3*gap))
    local x=left+6*scale
    local y=top
    local depositX=x+(titleW+gap)*rowScale
    local balanceX=depositX+(depositW+gap)*rowScale
    local withdrawX=balanceX+(balanceW+gap)*rowScale
    tint(muted)
    GuiText(gui,x,y,title,rowScale)
    tint(gold)
    GuiText(gui,balanceX+(balanceW-GuiGetTextDimensions(gui,amount))*rowScale/2,y,amount,rowScale)
    GuiTooltip(gui,title,string.format("%.0f",balance))
    local frame=GameGetFrameNum()
    local previous=bank_hold
    bank_hold=nil
    local function transfer(id,caption,direction,bx,source,destination)
        local limit=source and destination and not model.walletInfinite and math.min(source,NHStore.maxGold-destination) or 0
        tint(limit>0 and green or muted)
        GuiButton(gui,id,bx,y,caption,rowScale)
        local help=tr("点按转移 1 金币，按住加速","Click for 1 gold, hold to transfer faster")
        if model.ewWalletPaused then help=tr("EW 共享金币或等待连接确认，私人银行暂停存取","Private wallet transfers paused while gold is shared or EW is connecting")
        elseif model.walletInfinite then help=tr("无限金币钱包不支持存取","Transfers unavailable with infinite gold")
        elseif not model.walletGold then help=tr("当前钱包不可用","Wallet unavailable")
        else help=help.."\n"..tr("随身金币 ","Wallet ")..string.format("%.0f",model.walletGold) end
        GuiTooltip(gui,caption,help)
        local w,h=GuiGetTextDimensions(gui,caption,rowScale)
        if limit<=0 or drag or mx<bx or mx>=bx+w or my<y or my>=y+h or not InputIsMouseButtonDown(1) then return end
        if InputIsMouseButtonJustDown(1) then bank_hold={id=id,start=frame}
        elseif previous and previous.id==id and previous.frame==frame-1 then bank_hold=previous end
        if bank_hold then
            bank_hold.frame=frame
            local batch=transfer_batch(frame-bank_hold.start,10000)
            if batch then dispatch("bank_transfer",{direction=direction,amount=math.min(limit,batch)}) end
        end
    end
    transfer(274,deposit,"deposit",depositX,model.walletGold,model.bankGold)
    transfer(275,withdraw,"withdraw",withdrawX,model.bankGold,model.walletGold)
end

local essence_columns,essence_rows=4,5
local function stock_rows(key,entries)
    local cache=sorted_stock[key]
    if not cache then return entries end
    if cache.source~=entries then
        local sorted={}
        for i,entry in ipairs(entries) do sorted[i]=entry end
        table.sort(sorted,function(a,b)
            if a.amount~=b.amount then return a.amount>b.amount end
            return a.key<b.key
        end)
        cache.source,cache.rows=entries,sorted
    end
    return cache.rows
end

local function draw_essences(entries,start,limit,left,top,width,scale,mx,my)
    local column_width=(width-8)/essence_columns
    local cell_width=(column_width-3)*scale
    local stacked=column_width<50
    local pitch=stacked and 18 or 14
    local line_height=(stacked and 9 or 13)*scale
    local tip
    for i=1,math.min(limit,#entries-start+1) do
        local entry=entries[start+i-1]
        local kind=NHEssences.types[entry.key]
        local x=left+(4+(i-1)%essence_columns*column_width)*scale
        local y=top+(2+math.floor((i-1)/essence_columns)*pitch)*scale
        local value=compact(entry.amount)
        local full_width,full_height=GuiGetTextDimensions(gui,value)
        local value_scale=math.min(scale,(stacked and cell_width or cell_width*0.55)/full_width,line_height/full_height)
        local value_width=GuiGetTextDimensions(gui,value,value_scale)
        local name_space=stacked and cell_width or cell_width-value_width-2*scale
        local name=entry.name:gsub("精华$",""):gsub(" [Ee]ssence$","")
        if kind and entry.name==kind.en and GuiGetTextDimensions(gui,name,scale)>name_space then
            name=kind.shortEn
        end
        local name_width,name_height=GuiGetTextDimensions(gui,name)
        local name_scale=math.min(scale,name_space/math.max(1,name_width),line_height/name_height)
        local color=kind and kind.color or white
        tint(color)
        GuiText(gui,x,y,name,name_scale)
        tint(color)
        GuiText(gui,stacked and x or x+cell_width-value_width,y+(stacked and 9*scale or 0),value,value_scale)
        if mx>=x and mx<x+column_width*scale and my>=y and my<y+pitch*scale then
            tip={entry.name.."  "..string.format("%.0f",entry.amount)}
        end
    end
    return tip
end

local function show_production_project(id)
    tab,expansion_section,selected_entry="expansion","production",id
end

local function draw_farm(farm,y,tr,button,label,value_row,dispatch)
    if #farm.plots==0 then
        if button(412,6,y,tr("去扩建田地","Build farmland")) then
            show_production_project("farmland")
        end
        return
    end
    local plot=selected_plot and farm.plots[selected_plot]
    local crops={}
    for _,crop in ipairs(farm.crops) do crops[crop.id]=crop end
    if not plot then
        for i,entry in ipairs(farm.plots) do
            local crop=crops[entry.crop]
            local state=tr("空闲","Empty")
            if crop then
                state=crop.name.."  "..(entry.blocked and tr("库存已满","Storage full") or time_text(farm.remaining))
            end
            local title=string.format(tr("田 %d","Plot %d"),i).."   "..state
            if button(420+i,6,y+(i-1)*13,title) then selected_plot=i end
        end
        return
    end
    if button(413,6,y,tr("< 田地","< Plots")) then selected_plot=nil; return end
    local crop=crops[plot.crop]
    local title=string.format(tr("田 %d","Plot %d"),plot.id)
    label(y+14,title.." · "..(crop and crop.name or tr("选择作物","Choose crop")),white)
    local choices_y=y+28
    if crop then
        if plot.blocked then label(y+28,tr("农产库存已满","Crop storage full"),muted)
        else value_row(y+28,tr("下次分钟结算","Next settlement"),time_text(farm.remaining),white) end
        choices_y=y+42
    end
    for i,choice in ipairs(farm.crops) do
        local active=plot.crop==choice.id
        local output=rate_text(choice.plotRate)..tr("/分","/min")
        local name=(active and "["..choice.name.."]" or choice.name).."  "..output
        local detail=choice.name.."  "..output..tr("（单块田）"," per plot").."   "
            ..tr("库存 ","In storage ")..string.format("%.0f",choice.stock)
        if not choice.unlocked then detail=detail.."   "..tr("需要农业设备","Needs farming equipment") end
        if button(430+i,6,choices_y+(i-1)*13,name,active and green or choice.unlocked and gold or muted,detail)
            and choice.unlocked and not active then
            dispatch("farm_plant",{plot=plot.id,token=plot.token,crop=choice.id})
        end
    end
end

local forage_rows={
    dog={{"犬娘卡","Hound maiden card","3%"}},
    cat={{"猫娘卡","Cat maiden card","3%"}},
    queen_bee={{"蜂娘卡","Bee card","3%"}},
    dragon_egg=NHDragonLoot.odds,
    gel_pool={
        {"香料 + 激活剂","Spice + injector",NHGelPool.bonusChance.."%","同时产出 1 份香料和 1 支随机满耐久激活剂。香料存入农产库存，激活剂存入消耗品库。",
            "Adds 1 spice to crop stock and 1 random full-charge injector to supplies in the same harvest."},
        {"凝胶少女卡","Gel maiden card","3%","每轮独立抽取，获得的卡片存入藏品库。","Rolled separately each cycle. The card goes to the collection."},
    },
}

local function show_forage(species,y,tr,value_row)
    for _,reward in ipairs(forage_rows[species] or {}) do
        local name=tr(reward[1],reward[2])
        value_row(y,name,reward[3],muted,reward[4] and name,reward[4] and tr(reward[4],reward[5]))
        y=y+13
    end
    return y
end

local function find_pen(farm,species)
    if not species then return end
    for _,pen in ipairs(farm.pens) do
        if pen.species==species then return pen end
    end
end

local function draw_livestock(farm,y,tr,button,label,value_row)
    if #farm.pens==0 then
        if button(442,6,y,tr("去扩建畜牧设备","Build livestock pens")) then show_production_project("livestock") end
        if button(446,6,y+13,tr("建造凝胶池","Build gel pool")) then show_production_project("gel_pool") end
        return
    end
    local pen=find_pen(farm,selected_pen)
    if not pen then
        for i,p in ipairs(farm.pens) do
            local text=p.title.."   "..p.count.."/"..p.capacity
            if p.count>0 then
                local remaining=p.adults>0 and farm.remaining or p.growthRemaining
                text=text.."   "..(p.blocked and tr("库存已满","Storage full") or time_text(remaining))
            end
            if button(450+i,6,y+(i-1)*13,text) then selected_pen=p.species end
        end
        return
    end
    if button(443,6,y,tr("< 栏舍","< Pens")) then selected_pen=nil; return end
    label(y+14,pen.title,white)
    value_row(y+27,tr("已用 / 容量","Used / capacity"),pen.count.." / "..pen.capacity,white)
    value_row(y+40,tr("成熟 / 成长中","Adult / growing"),pen.adults.." / "..pen.juveniles,white)
    local interval=pen.petRows and tr("同伴卡抽取间隔","Companion card interval") or tr("抽取间隔","Reward roll interval")
    value_row(y+53,interval,pen.effectivePeriod and time_text(pen.effectivePeriod) or tr("未生产","Idle"),white)
    local next_y=y+66
    if pen.growthRemaining then
        local maturity=pen.species=="dragon_egg" and tr("下次孵化","Next hatch") or tr("下次成熟","Next maturity")
        value_row(next_y,maturity,time_text(pen.growthRemaining),white)
        next_y=next_y+13
    end
    if pen.blocked then
        local full=tr("畜产库存已满","Produce storage full")
        if pen.petRows then full=tr("寻物等待库存空位","Finds awaiting storage space")
        elseif pen.species=="dragon_egg" then full=tr("存钱罐已满","Bank full")
        elseif pen.species=="gel_pool" then full=tr("草药或纤维库存已满","Herb or fiber stock full") end
        label(next_y,full,muted)
        next_y=next_y+13
    elseif pen.adults>0 then
        value_row(next_y,tr("下次分钟结算","Next settlement"),time_text(farm.remaining),white)
        next_y=next_y+13
    end
    if pen.petRows then
        for _,row in ipairs(pen.petRows) do
            local detail
            if row.fraction then detail=tr("已累计 ","Saved progress ")..math.floor(row.fraction*100).."%"
            elseif row.id=="dog_find" then detail=tr("每份等概率获得 3 纤维、2 粮食或 1 草药。","Each bundle is equally likely to contain 3 fiber, 2 grain or 1 herb.")
            else detail=tr("每件为一支满弹发射器或一个诱饵。猫窝升级可找到更多种类。","Each find is one loaded launcher or one decoy. Upgrading the cattery opens more types.") end
            value_row(next_y,row.label,row.rate..tr("/分","/min"),white,row.label,detail)
            next_y=next_y+13
        end
        if (pen.findsPending or 0)>0 then
            value_row(next_y,tr("待入库物品","Items awaiting space"),compact(pen.findsPending),gold)
            next_y=next_y+13
        end
        if (pen.sharedFindsPending or 0)>0 then
            value_row(next_y,tr("猫狗共有待入库大红","Joint valuables awaiting space"),compact(pen.sharedFindsPending),gold)
            next_y=next_y+13
        end
    else
        value_row(next_y,tr("每分 ","/min ")..pen.rateLabel,pen.rateValue,white,tr("每分钟产量","Output per minute"),pen.rateLabel.."   "..pen.rateValue)
        next_y=next_y+13
    end
    if pen.rareProgress then
        value_row(next_y,tr("珍品进度","Rare treasure progress"),pen.rareProgress.."/100",gold,
            tr("下次珍品","Next rare treasure"),tr("每次寻宝增加 33 点，满 100 点时本次交付珍品，余数保留。","Each discovery adds 33 points. At 100 the discovery is rare and the remainder carries over."))
        next_y=next_y+13
    end
    next_y=show_forage(pen.species,next_y,tr,value_row)
    if pen.species=="dragon_egg" and (farm.dragonPending or 0)>0 then
        value_row(next_y,tr("已找到，待入库","Found, awaiting space"),compact(farm.dragonPending),gold)
        next_y=next_y+13
    elseif pen.species=="gel_pool" then
        if (farm.gelPending or 0)>0 then
            value_row(next_y,tr("待入库激活剂","Injectors awaiting space"),compact(farm.gelPending),gold)
            next_y=next_y+13
        end
        if (farm.gelSpicePending or 0)>0 then
            value_row(next_y,tr("待入库香料","Spice awaiting space"),compact(farm.gelSpicePending),gold)
            next_y=next_y+13
        end
    end
    if pen.count<pen.capacity then
        if button(444,6,next_y,tr("转化","Convert to ")..pen.young) then
            tab,shop_category,selected_entry="shop","livestock",pen.species
        end
    elseif pen.canExpand then
        if button(447,6,next_y,tr("扩建栏位","Expand capacity")) then
            show_production_project(pen.expansion)
        end
    else
        label(next_y,tr("已达饲养上限","Maximum capacity"),muted)
    end
end

local function position_work_tabs(tabs,y,width,scale,tr,debug)
    local x,positions=6,{}
    for _,t in ipairs(tabs) do
        if t.key~="samples" or debug then
            local name=tr(t.zh,t.en)
            local w=GuiGetTextDimensions(gui,name,scale)/scale
            if x>6 and x+w>width-5 then x,y=6,y+13 end
            positions[#positions+1]={id=t.id,key=t.key,name=name,x=x,y=y}
            x=x+w+7
        end
    end
    return positions,y+16
end

local function draw_workshop(model,layout,scale,sh,tr,dispatch,mx,my,panels)
    local left,width=layout.middle,layout.bench
    if not model.debug and tab=="samples" then open_shop() end
    local nav,body=layout.workTabs,layout.navEnd
    local nav_end=body
    local crafting=tab=="orders"
    local alchemy=crafting and recipe_category=="alchemy"
    local spells=crafting and recipe_category=="spell"
    local shopping=tab=="shop"
    local building=tab=="expansion"
    local farming=tab=="farm"
    local ranching=tab=="livestock"
    local menu=model.progression[tab]
    if building then
        menu={}
        for _,project in ipairs(model.progression.expansion) do
            if project.section==expansion_section then menu[#menu+1]=project end
        end
    elseif spells then
        menu=spell_family and model.spellRecipes[spell_family] or model.spellFamilies
    elseif crafting then
        menu={}
        for _,recipe in ipairs(model.recipes) do
            if recipe.category==recipe_category and (not alchemy or recipe.alchemyMode==alchemy_mode) then
                menu[#menu+1]=recipe
            end
        end
    elseif shopping then
        menu={}
        for _,good in ipairs(model.shopGoods or {}) do
            if good.category==shop_category then menu[#menu+1]=good end
        end
    end
    local selected
    for _,item in ipairs(menu or {}) do
        if item.id==selected_entry then selected=item; break end
    end
    local recipe_detail=selected and (crafting or (shopping and selected.inputs))
    local outputs=recipe_detail and selected.outputs
    local catalysts=recipe_detail and selected.catalysts
    local catalyst_count=catalysts and #catalysts or 0
    local show_outputs=outputs and (#outputs>1 or (#outputs==1 and (outputs[1].name~=selected.name or catalyst_count>0)))
    local salvage
    if salvage_target and (model.salvage_enabled or salvage_target.mode=="collectible") then
        local category=model.warehouse[NHStore.category(salvage_target.kind)]
        salvage=category and category[salvage_target.slot]
        if not salvage or salvage.id~=salvage_target.id or salvage.kind~=salvage_target.kind
            or not (salvage_target.mode=="collectible" and NHRedRelics.types[salvage.kind] or salvage.salvage_yield)
            or ((salvage_target.mode=="store_contents")~=(salvage.store_contents~=nil))
            or (salvage_target.mode=="essence" and not salvage.essence) then salvage_target,salvage=nil,nil end
    end
    local per_card=salvage and salvage_target.mode=="essence" and salvage.essence.per_card
    local shop_bank=shopping and not salvage
    if shop_bank then
        nav_end=body+bankRowHeight
        body=nav_end
    end
    local category_tabs
    if not salvage then
        if building and not selected then category_tabs=expansion_tabs
        elseif crafting and not selected then category_tabs=recipe_tabs
        elseif shopping and not selected then category_tabs=shop_tabs
        elseif farming then category_tabs=farm_tabs
        elseif ranching then category_tabs=livestock_tabs end
    end
    local category_nav,alchemy_nav
    local function position_subtabs(navWidth)
        category_nav,body=position_work_tabs(category_tabs,nav_end,navWidth or width,scale,tr)
        if alchemy then alchemy_nav,body=position_work_tabs(alchemy_tabs,body,navWidth or width,scale,tr) end
    end
    if category_tabs then position_subtabs() end
    local function available(item)
        if crafting then return item.ready and item.unlocked~=false and not model.order_active end
        if shopping then return item.ready end
        return item.canBuy
    end
    local preview=recipe_detail and (selected.category=="medical" or selected.category=="weapons" or selected.category=="storm_products") and selected.icon
    local body_height=62
    if tab=="samples" and not salvage then body_height=82
    elseif salvage and salvage_target.mode=="collectible" then body_height=80+12*#NHRedRelics.resourceKeys
    elseif salvage then
        body_height=77+(salvage.essence and 14 or 0)+(salvage.spell_uses~=nil and 13 or 0)+(per_card and 13 or 0)
        if salvage.store_contents then body_height=body_height+13+12*#salvage.store_contents end
    elseif ranching then
        local pen=find_pen(model.farm,selected_pen)
        if livestock_page=="produce" then body_height=13*(1+#model.farm.produce)+5
        elseif pen then
            body_height=92+13*#(forage_rows[pen.species] or {})
            if pen.petRows then body_height=body_height+13*(#pen.petRows-1) end
            if (pen.findsPending or 0)>0 then body_height=body_height+13 end
            if (pen.sharedFindsPending or 0)>0 then body_height=body_height+13 end
            if pen.rareProgress then body_height=body_height+13 end
            if pen.count>0 then body_height=body_height+13 end
            if pen.growthRemaining then body_height=body_height+13 end
            if pen.species=="dragon_egg" and (model.farm.dragonPending or 0)>0 then body_height=body_height+13 end
            if pen.species=="gel_pool" then
                if (model.farm.gelPending or 0)>0 then body_height=body_height+13 end
                if (model.farm.gelSpicePending or 0)>0 then body_height=body_height+13 end
            end
        else body_height=13*math.max(2,#model.farm.pens)+5 end
    elseif farming then
        local farm=model.farm
        local plot=selected_plot and farm.plots[selected_plot]
        if farm_page=="stock" then body_height=13*(1+#farm.crops)+5
        elseif not plot then body_height=13*math.max(1,#farm.plots)+5
        else body_height=(plot.crop and 42 or 28)+13*#farm.crops+2 end
    elseif recipe_detail then
        body_height=68+12*#selected.inputs+(preview and 5 or 0)
        if spells then body_height=body_height+13 end
        if catalyst_count>0 then body_height=body_height+13+12*catalyst_count end
        if show_outputs then body_height=body_height+13+12*#outputs end
        if outputs and outputs[1] and outputs[1].stock then body_height=body_height+13 end
        if selected.medkit then body_height=body_height+(NHSurgeryKits.types[selected.id] and 65 or 39)
        elseif foods[selected.id] then body_height=body_height+13*(1+#foods[selected.id].notesZh)
        elseif selected.note then body_height=body_height+13 end
        if model.order_active and selected.unlocked==false then body_height=body_height+13 end
    elseif shopping and selected then
        body_height=86+(selected.scrap and 14 or 0)+(NHLivestock.species[selected.id] and 65 or 0)+13*#(forage_rows[selected.id] or {})
    elseif selected then body_height=80+12*#selected.costs
    elseif menu then
        body_height=5+13*math.max(1,#menu)
        if spells and spell_family then body_height=body_height+13 end
        if crafting and model.order_active then body_height=body_height+15 end
    end
    local height=workshop_folded and 20 or layout.panelHeight
    local top=sh-5-height*scale
    panels[#panels+1]={x=left,y=top,w=width*scale,h=height*scale,slot={key="panel"}}
    local detailTop,detailBottom
    local function visibleDetail(y,h)
        return not detailTop or (y>=detailTop and y+(h or 10)<=detailBottom)
    end
    local function label(y,value,color,x)
        if not visibleDetail(y) then return end
        x=x or 6
        local txt,short=fit(value,(width-x-6)*scale,scale)
        tint(color or white)
        GuiText(gui,left+x*scale,top+y*scale,txt,scale)
        if short then GuiTooltip(gui,value,"") end
    end
    local function recipe_icon(id,y,path,size)
        if not path then return 6 end
        if not visibleDetail(y,size) then return 8+size end
        local w,h=GuiGetImageDimensions(gui,path)
        if w<=0 or h<=0 then return 6 end
        GuiImage(gui,id,left+6*scale,top+y*scale,path,1,size*scale/math.max(w,h))
        return 8+size
    end
    local function button(id,x,y,value,color,tip,detail)
        if not visibleDetail(y) then return false end
        local txt,short=fit(value,(width-x-5)*scale,scale)
        tint(color or gold)
        local clicked=GuiButton(gui,id,left+x*scale,top+y*scale,txt,scale)
        if tip or short then GuiTooltip(gui,tip or value,detail or "") end
        return clicked and not drag
    end
    GuiZSetForNextWidget(gui,-79)
    GuiImageNinePiece(gui,210,left,top,width*scale,height*scale,1)
    local hover=mx>=left and mx<left+width*scale and my>=top and my<top+height*scale
    local toggleHint=travelSession and not workshop_folded and tr("折叠后显示旅行终端","Fold to show travel routes")
    if button(211,6,3,(workshop_folded and "[+] " or "[-] ")..tr("藏身处","Hideout"),nil,toggleHint) then
        workshop_folded=not workshop_folded
        if not workshop_folded then open_shop() end
        return hover
    end
    if workshop_folded then return hover end
    for _,t in ipairs(nav) do
        if button(t.id,t.x,t.y,t.name,t.key==tab and gold or muted) then
            tab,selected_entry,salvage_target=t.key,nil,nil
            selected_pen=nil
            selected_plot=nil
            return hover
        end
    end
    if shop_bank then draw_shop_bank(model,left,top+layout.navEnd*scale,width,scale,tr,dispatch,mx,my) end
    -- Keep all navigation above the scrolling body when there is room. On a
    -- narrow screen wrapped subcategories may scroll, but the main tabs stay put.
    local listHeader=(spells and spell_family and 13 or 0)+(crafting and model.order_active and 15 or 0)
    local rowList=menu and not selected and not salvage and height-body-listHeader>=17
    local function scroll_body(key,start,pitch)
        local room=height-3-start
        if room<=0 then return end
        local overflow=math.max(0,body+body_height-(height-3))
        local visible=math.max(1,math.floor(room/pitch))
        local steps=math.ceil(overflow/pitch)
        local first=scrollMenu.rows(gui,key,7102,visible+steps,visible,left,top+start*scale,width*scale,room*scale,scale,mx,my,nil,drag)
        local offset=math.min(first*pitch,overflow)
        detailTop,detailBottom=start+offset,height-3+offset
        top=top-offset*scale
        if steps>0 then width=width-5 end
    end
    local section=building and expansion_section or (spells and spell_family) or (alchemy and alchemy_mode)
        or (crafting and recipe_category) or (shopping and shop_category) or (farming and farm_page) or (ranching and livestock_page) or tab
    local viewKey=table.concat({tab,section,selected and selected.id or (farming and selected_plot) or (ranching and selected_pen) or ""},"/")
    local pageBody=not rowList and not salvage and not selected
    local scrollTabs=pageBody and category_tabs and height-body<38 and body+body_height>height-3
    if scrollTabs then
        position_subtabs(width-5)
        scroll_body(viewKey,nav_end,13)
    end
    for _,t in ipairs(category_nav or {}) do
        local current=building and expansion_section or ranching and livestock_page or farming and farm_page or (shopping and shop_category or recipe_category)
        if button(t.id,t.x,t.y,t.name,t.key==current and gold or muted) then
            if building then expansion_section=t.key
            elseif ranching then livestock_page,selected_pen=t.key,nil
            elseif farming then farm_page,selected_plot=t.key,nil
            elseif shopping then shop_category=t.key else recipe_category=t.key end
            selected_entry=nil
            return hover
        end
    end
    for _,t in ipairs(alchemy_nav or {}) do
        if button(t.id,t.x,t.y,t.name,t.key==alchemy_mode and gold or muted) then
            alchemy_mode,selected_entry=t.key,nil
            return hover
        end
    end
    if pageBody and not scrollTabs then scroll_body(viewKey,body,13) end
    -- Quantities and timers stay visible even when a long name needs a tooltip.
    local function value_row(y,name,value,color,tip,detail)
        if not visibleDetail(y) then return end
        local right=width-6-GuiGetTextDimensions(gui,value,scale)/scale
        local txt,short=fit(name,(right-9)*scale,scale)
        tint(muted)
        GuiText(gui,left+6*scale,top+y*scale,txt,scale)
        if short or detail then GuiTooltip(gui,name,detail or "") end
        tint(color)
        GuiText(gui,left+right*scale,top+y*scale,value,scale)
        if tip then GuiTooltip(gui,tip,detail or "") end
    end
    local function stock_table(entries,y)
        local rate_label=width<110 and tr("每分","/min") or tr("每分钟","Per min")
        local rows={{name=tr("产物","Item"),stock=tr("库存","Stock"),rate=rate_label}}
        local kennel=find_pen(model.farm,"dog")
        for _,entry in ipairs(entries) do
            local rate=rate_text(entry.perMinute)
            rows[#rows+1]={name=entry.name,stock=compact(entry.stock),rate=rate,entry=entry}
        end
        local stock_w,rate_w=0,0
        for _,r in ipairs(rows) do
            r.stockWidth=GuiGetTextDimensions(gui,r.stock,scale)
            r.rateWidth=GuiGetTextDimensions(gui,r.rate,scale)
            stock_w=math.max(stock_w,r.stockWidth)
            rate_w=math.max(rate_w,r.rateWidth)
        end
        local name_x=left+4*scale
        local rate_right=left+(width-3)*scale
        -- A scrollbar and large balances can otherwise squeeze every crop name down to "...".
        local min_name=GuiGetTextDimensions(gui,tr("草...","W..."),scale)
        local number_factor=math.min(1,(rate_right-name_x-6*scale-min_name)/(stock_w+rate_w))
        local stock_right=rate_right-rate_w*number_factor-3*scale
        local name_w=stock_right-stock_w*number_factor-3*scale-name_x
        for i,r in ipairs(rows) do
            local logicalY=y+(i-1)*13
            if visibleDetail(logicalY) then
                local row_y=top+logicalY*scale
                local entry=r.entry
                local detail=entry and string.format(tr("库存 %.0f\n每分钟产量 %s","Stock %.0f\nOutput per minute %s"),
                    entry.stock,r.rate)
                if entry and kennel and kennel.adults>0 and (entry.id=="fiber" or entry.id=="grain" or entry.id=="herb") then
                    detail=detail..tr("\n犬寻物按长期平均值计入。","\nIncludes the average from dog finds.")
                end
                tint(entry and white or muted)
                GuiText(gui,name_x,row_y,fit(r.name,name_w,scale),scale)
                if detail then GuiTooltip(gui,r.name,detail) end
                tint(entry and entry.stock>0 and white or muted)
                GuiText(gui,stock_right-r.stockWidth*number_factor,row_y,r.stock,scale*number_factor)
                if detail then GuiTooltip(gui,r.name,detail) end
                tint(entry and entry.perMinute>0 and green or muted)
                GuiText(gui,rate_right-r.rateWidth*number_factor,row_y,r.rate,scale*number_factor)
                if detail then GuiTooltip(gui,r.name,detail)
                else GuiTooltip(gui,tr("每分钟产量","Output per minute"),tr("包含设施和随行好感加成，小数结转。随机产物显示平均值。","Includes facilities and active affinity. Fractions carry over. Random yields show their average.")) end
            end
        end
    end
    local function cost(y,name,have,need,detail,essence)
        if not visibleDetail(y) then return end
        local balance=compact(have).." / "..compact(need)
        local tip=string.format("%s  %.0f / %.0f",name,have,need)
        local kind=NHEssences.types[essence]
        if not kind then
            value_row(y,name,balance,have>=need and green or gold,tip,detail)
            return
        end
        local x,right=left+6*scale,left+(width-6)*scale
        local text=name
        local amount_width=GuiGetTextDimensions(gui,balance,scale)
        if GuiGetTextDimensions(gui,text,scale)+amount_width+3*scale>right-x then
            text=tr(kind.zh:gsub("精华$",""),kind.shortEn)
        end
        local factor=math.min(1,(right-x-3*scale)/(GuiGetTextDimensions(gui,text,scale)+amount_width))
        tint(kind.color)
        GuiText(gui,x,top+y*scale,text,scale*factor)
        GuiTooltip(gui,tip,detail or "")
        tint(kind.color)
        GuiText(gui,right-amount_width*factor,top+y*scale,balance,scale*factor)
        GuiTooltip(gui,tip,detail or "")
    end
    local function order_status(y)
        local remaining=time_text(model.order_remaining)
        value_row(y,tr("生产中：","Making: ")..model.order_name,remaining,white,tr("剩余 ","Time left ")..remaining)
    end
    if salvage and salvage_target.mode=="collectible" then
        local def=NHRedRelics.types[salvage.kind]
        label(body,tr("分解藏品","Dismantle collectible"),gold)
        scroll_body("salvage/"..def.id,body+13,12)
        label(body+13,tr(def.zh,def.en))
        local y=body+27
        for _,key in ipairs(NHRedRelics.resourceKeys) do
            local pack=NHStore.alchemyResources[key]
            value_row(y,tr(pack.zh,pack.en),"+"..NHRedRelics.resourceAmount,green)
            y=y+12
        end
        for _,species in ipairs({def.tarot,def.companion}) do
            local card=NHCompanions.cardDefinition(species)
            value_row(y,tr(card.zh,card.en),"+"..NHRedRelics.cardCount,green)
            y=y+12
        end
        if button(260,6,y+2,tr("确认分解","Dismantle item"),green) then
            dispatch("salvage",salvage_target)
            salvage_target=nil
            return hover
        end
        if button(261,6,y+15,tr("取消","Cancel")) then salvage_target=nil end
    elseif salvage then
        label(body,tr("拆解","Dismantle"),gold)
        scroll_body("salvage/"..salvage.kind.."/"..salvage_target.mode,body+13,12)
        label(body+13,salvage.name)
        local y=body+27
        local extract=salvage_target.mode=="essence"
        local amount,stock=salvage.salvage_yield,salvage.salvage_stock
        if salvage.store_contents then
            label(y,tr("存入物料库","Store in bulk storage"),muted)
            y=y+13
            for _,entry in ipairs(salvage.store_contents) do
                value_row(y,entry.name,"+"..compact(entry.amount),green,nil,string.format("%.0f",entry.amount))
                y=y+12
            end
        end
        if salvage.essence then
            local essence=tr("精华","Essence")
            local scrap=tr("碎片","Scrap")
            local choice=extract and "["..essence.."]" or essence
            if button(262,6,y,choice,extract and gold or muted) then salvage_target.mode="essence"; return hover end
            local x=13+GuiGetTextDimensions(gui,choice,scale)/scale
            if button(263,x,y,extract and scrap or "["..scrap.."]",extract and muted or gold) then
                salvage_target.mode="scrap"; return hover
            end
            y=y+14
        end
        if salvage.spell_uses~=nil then
            value_row(y,tr("剩余次数","Charges left"),salvage.spell_uses<0 and "∞" or tostring(salvage.spell_uses),
                white,nil,tr("剩余次数不影响回收量","Remaining charges do not affect the yield"))
            y=y+13
        end
        if extract then
            amount,stock=salvage.essence.amount,salvage.essence.stock
            if per_card then
                local full=tr("每张满额","Per full card")
                local detail=salvage.essence.basis
                if detail then
                    detail=detail.."\n"..tr("每 1 点标称治疗量折合 1 个治疗精华。",
                        "1 HP of potential healing yields 1 healing essence.")
                else
                    detail=tr("按原版满次数估算伤害或功能价值。\n无限次按 20 次计。超过 375 的部分\n按八分之一折算，整卡四舍五入。",
                        "Priced by damage or utility at full charges.\nUnlimited spells use a 20-cast reference.\nValue above 375 counts at one eighth.\nThe total is rounded to the nearest unit.")
                end
                value_row(y,full,tostring(per_card),white,full,detail)
                y=y+13
            end
            value_row(y,salvage.essence.name,"+"..amount,green)
            value_row(y+12,tr("当前库存","In storage"),compact(stock),white,string.format("%.0f",stock))
        else
            label(y,salvage.salvage_name.." +"..amount,green)
            label(y+12,tr("现有碎片 ","Current scrap ")..compact(stock),muted)
        end
        if salvage.materials_fit==false then label(y+26,tr("物料库空间不足","Material storage full"),muted)
        elseif amount<=NHStore.maxResourceAmount-stock then
            local confirm=salvage.store_contents and tr("存放并拆解","Store and dismantle")
                or extract and tr("确认提取","Extract essence") or tr("确认拆解","Dismantle item")
            if button(260,6,y+26,confirm,green) then
                dispatch("salvage",salvage_target)
                salvage_target=nil
                return hover
            end
        else label(y+26,tr("库存已满","Storage full"),muted) end
        if button(261,6,y+38,tr("取消","Cancel")) then salvage_target=nil end
    elseif ranching then
        if livestock_page=="produce" then stock_table(model.farm.produce,body)
        else draw_livestock(model.farm,body,tr,button,label,value_row) end
    elseif farming then
        if farm_page=="stock" then stock_table(model.farm.crops,body)
        else draw_farm(model.farm,body,tr,button,label,value_row,dispatch) end
    elseif recipe_detail then
        local back=tr("< 返回配方","< Recipes")
        local confirm=tr("确认制造","Confirm craft")
        if shopping then
            back,confirm=tr("< 产物转化","< Storm products"),tr("确认加工","Process")
        elseif spells then
            local family=NHEssences.types[spell_family]
            back,confirm="< "..tr(family.zh,family.en),tr("合成法术","Craft spell")
        elseif alchemy then
            if alchemy_mode=="synthesis" then
                back,confirm=tr("< 炼成","< Synthesis"),tr("确认炼成","Synthesize")
            elseif alchemy_mode=="rubedo" then
                back,confirm=tr("< 红化","< Rubedo"),tr("确认红化","Transmute")
            elseif alchemy_mode=="logistics" then
                back,confirm=tr("< 后勤资源包","< Logistics packs"),tr("制作资源包","Craft packs")
            else
                back,confirm=tr("< 分解","< Decomposition"),tr("确认分解","Decompose")
            end
        end
        if button(240,6,body,back) then selected_entry=nil; return hover end
        scroll_body("recipe/"..selected.id,body+13,12)
        local x=recipe_icon(610,body+14,preview,16)
        label(body+(preview and 17 or 14),show_outputs and selected.name or selected.name.." ×"..selected.output,available(selected) and green or white,x)
        local y=body+(preview and 32 or 27)
        value_row(y,tr("交付","Delivery"),tr("即时完成","Instant"),white)
        if outputs and outputs[1] and outputs[1].stock then
            y=y+13
            value_row(y,tr("成品库存","In storage"),compact(outputs[1].stock),white,string.format("%.0f",outputs[1].stock))
        end
        y=y+13
        if spells then
            local spell_type=selected.spellType=="static_projectile" and tr("静态投射物","Static projectile") or tr("投射物","Projectile")
            label(y,spell_type..tr(" → 法术仓库"," → Spell storage"),muted)
            y=y+13
        end
        label(y,tr("原料  库存 / 所需","Ingredients  stock / cost"),muted)
        for _,input in ipairs(selected.inputs) do
            y=y+12
            cost(y,input.name,input.available,input.amount,input.detail,input.essence)
        end
        if catalyst_count>0 then
            y=y+13
            label(y,tr("催化剂（完工归还）","Catalyst (returned)"),muted)
            local detail=tr("开工时暂存，完成后原数归还。","Held when the batch starts and returned in full at completion.")
            for _,sample in ipairs(catalysts) do
                y=y+12
                if sample.held and sample.held>0 then
                    local held=tr("暂存 ","Held ")..string.format("%.0f",sample.held)
                    value_row(y,sample.name,held,green,held,tr("当前库存 ","Stock ")..string.format("%.0f",sample.available).."\n"..detail)
                else
                    cost(y,sample.name,sample.available,sample.amount,detail)
                end
            end
        end
        if show_outputs then
            y=y+13
            label(y,catalyst_count>0 and tr("净产出","Net output") or tr("每批产出","Batch output"),muted)
            for _,result in ipairs(outputs) do
                y=y+12
                value_row(y,result.name,"×"..compact(result.amount),white,result.name.." ×"..result.amount)
            end
        end
        if selected.medkit then
            y=y+13
            value_row(y,tr("使用次数","Uses"),tostring(selected.medkit.uses),white)
            y=y+13
            value_row(y,tr("每次回血","Healing per use"),selected.medkit.healPercent..tr("% 最大生命","% max HP"),white)
            if selected.medkit.castFrames then
                y=y+13
                value_row(y,tr("使用时间","Use time"),(selected.medkit.castFrames/60)..tr(" 秒"," s"),white)
            end
            if NHSurgeryKits.types[selected.id] then
                y=y+13
                label(y,tr("清除负面状态","Clears harmful conditions"),white)
                y=y+13
                label(y,tr("受伤时仍可继续手术","Surgery continues through damage."),muted)
            end
        elseif foods[selected.id] then
            local food=foods[selected.id]
            y=y+13
            label(y,tr("每份 "..food.uses.." 口",food.uses.." bites per portion"),white)
            for _,line in ipairs(tr(food.notesZh,food.notesEn)) do
                y=y+13
                label(y,line,muted)
            end
        elseif selected.note then
            y=y+13
            label(y,selected.note,muted)
        end
        y=y+15
        if model.order_active then
            order_status(y)
            if selected.unlocked==false then
                y=y+13
                label(y,selected.reason,muted)
            end
        elseif available(selected) then
            if button(214,6,y,confirm,green) then dispatch("craft",{id=selected.id}) end
        else label(y,selected.reason or tr("材料或空位不足","Need stock or space"),muted) end
    elseif shopping and selected and selected.yield then
        if button(240,6,body,tr("< 返回列表","< Offers")) then selected_entry=nil; return hover end
        scroll_body(viewKey,body+13,12)
        label(body+14,selected.name,white,recipe_icon(610,body+14,selected.icon,12))
        label(body+27,tr("资源  库存 / 所需","Resource  stock / cost"),muted)
        cost(body+39,selected.resourceName,selected.resourceStock,selected.quantity)
        local y=body+52
        value_row(y,tr("存钱罐金币","Bank gold"),tostring(selected.yield.gold),green)
        y=y+13
        if available(selected) then
            if button(258,6,y,tr("确认出售","Sell"),green) then dispatch("shop_buy",{id=selected.id}) end
        else label(y,selected.reason,gold) end
    elseif shopping and selected then
        if button(240,6,body,tr("< 返回列表","< Offers")) then selected_entry=nil; return hover end
        scroll_body(viewKey,body+13,12)
        label(body+14,selected.name,white)
        value_row(body+27,tr("数量","Quantity"),string.format("%.0f",selected.quantity),white)
        local destination=selected.category=="materials" and tr("物料","Materials") or tr("消耗品","Supplies")
        local animal=NHLivestock.species[selected.id]
        if animal then destination=tr(animal.pen[1],animal.pen[2]) end
        if selected.scrap then
            value_row(body+40,tr("奥术碎片","Arcane scrap"),tostring(selected.scrap),white)
        else value_row(body+40,animal and tr("送往","Destination") or tr("入库","Warehouse"),destination,white) end
        if selected.scrap then
            value_row(body+53,tr("保单","Policy"),selected.insured and tr("已投保","Active") or tr("未投保","Uninsured"),gold)
        else value_row(body+53,tr("耗金","Gold cost"),string.format("%.0f",selected.price),gold) end
        local confirm_y=body+70
        if selected.scrap then
            label(confirm_y,tr("致命伤时返回出生点，随身金留在原地。","Return to spawn on lethal damage. Carried gold stays behind."),muted)
            confirm_y=confirm_y+14
        end
        if animal then
            local pen=find_pen(model.farm,selected.id)
            local count,capacity=pen and pen.count or 0,pen and pen.capacity or 0
            value_row(confirm_y,tr("已用 / 容量","Used / capacity"),count.." / "..capacity,white)
            confirm_y=confirm_y+13
            if animal.growth>0 then
                value_row(confirm_y,selected.id=="dragon_egg" and tr("孵化时间","Incubation") or tr("成长时间","Growth time"),time_text(animal.growth/60),white)
                confirm_y=confirm_y+13
            end
            local current=pen and pen.effectivePeriod
            local petPen=selected.id=="dog" or selected.id=="cat"
            value_row(confirm_y,petPen and tr("同伴卡抽取间隔","Companion card interval") or tr("当前抽取间隔","Reward roll interval"),current and time_text(current) or tr("未生产","Idle"),white)
            confirm_y=confirm_y+13
            if count<capacity then
                local period=time_text(animal.period/60/(count+1))
                value_row(confirm_y,tr("转化后全部成熟","Once all mature"),period,green,
                    petPen and tr("全部成熟后的同伴卡抽取间隔","Companion card interval once all are mature")
                        or tr("全部成熟后的抽取间隔","Roll interval once all are mature"))
                confirm_y=confirm_y+13
            end
            if pen then
                value_row(confirm_y,tr("每分 ","/min ")..pen.rateLabel,pen.rateValue,white,tr("当前每分钟产量","Current output per minute"),pen.rateLabel.."   "..pen.rateValue)
            end
            confirm_y=show_forage(selected.id,confirm_y+13,tr,value_row)
        end
        if available(selected) then
            if button(258,6,confirm_y,selected.scrap and tr("投保","Insure") or tr("确认转化","Convert gold"),green) then
                dispatch("shop_buy",{id=selected.id,pen=selected.pen})
            end
        else label(confirm_y,selected.reason,gold) end
    elseif selected then
        if button(240,6,body,tr("< 返回列表","< Projects")) then selected_entry=nil; return hover end
        scroll_body(viewKey,body+13,12)
        label(body+14,selected.name,available(selected) and green or white)
        label(body+27,tr("当前：","Now: ")..selected.current)
        if selected.next then label(body+39,tr("升级后：","Next: ")..selected.next) end
        local y=body+51
        if #selected.costs>0 then
            label(y,tr("物料  库存 / 所需","Materials  stock / cost"),muted)
            for _,input in ipairs(selected.costs) do
                y=y+12
                cost(y,input.name,input.available,input.amount,input.detail,input.key)
            end
            y=y+13
        end
        if selected.canBuy then
            local confirm=tab=="expansion" and tr("确认扩建","Confirm build") or tr("确认升级","Confirm upgrade")
            if button(241,6,y,confirm,green) then
                dispatch("buy_upgrade",{id=selected.id,level=selected.level})
                selected_entry=nil
            end
        elseif selected.planned then label(y,tr("尚未开放","In development"),muted)
        elseif selected.maxed then label(y,tr("已完成","Complete"),muted)
        elseif selected.id=="agri_equipment" and model.farm and #model.farm.plots==0 then
            label(y,tr("先开垦一块田","Build a field first"),muted)
        else label(y,tr("所需物料不足","Insufficient stock"),gold) end
    elseif menu then
        local y=body
        if spells and spell_family then
            local family=NHEssences.types[spell_family]
            if button(226,6,y,"< "..tr(family.zh,family.en),family.color,tr("返回精华分类","Back to essence types")) then
                spell_family=nil
                return hover
            end
            y=y+13
        end
        if crafting and model.order_active then
            order_status(y)
            y=y+15
        end
        if crafting and #menu==0 then label(y,tr("暂无配方","No recipes yet"),muted) end
        if shopping and #menu==0 then label(y,tr("暂无商品","No goods for sale"),muted) end
        local first,count=0,#menu
        if rowList then
            local room=height-y-3
            local visible=math.max(1,math.floor(room/13))
            first=scrollMenu.rows(gui,tab.."/"..section,7100,#menu,visible,left,top+y*scale,width*scale,room*scale,scale,mx,my,nil,drag)
            count=math.min(count,visible)
            if #menu>visible then width=width-5 end
        end
        for i=1,count do
            local item=menu[first+i]
            local row_y=y+(i-1)*13
            local color=available(item) and green or white
            if item.planned or item.maxed or item.unlocked==false then color=muted end
            if spells and not spell_family then color=NHEssences.types[item.id].color end
            local x=(crafting or shopping) and recipe_icon(600+i,row_y,item.icon,10) or 6
            if button(i<=5 and 243+i or 7200+i,x,row_y,item.name,color,item.actionId and item.name,item.actionId) then
                if spells and not spell_family then spell_family=item.id else selected_entry=item.id end
                return hover
            end
        end
    else
        if button(216,6,body+3,tr("生成测试魔杖和混合瓶","Spawn wand and flask")) then dispatch("preview_items") end
        label(body+17,tr("在脚边拾取样品","Pick up the samples at your feet"),muted)
        if button(217,6,body+33,tr("重发测试针剂包","Reissue test pouch"),gold,
            tr("替换现有针剂包，内含两支激活剂。","Replace the current pouch with two doses.")) then dispatch("restock") end
        if button(480,6,body+49,tr("领取全部召唤卡","Claim all summon cards"),gold,
            string.format(tr("共 %d 种召唤卡，每种各发一张满耐久卡。","One full-charge card for each of the %d companions."),#NHCompanions.order)) then
            folded,warehouse_tab,transfer_slot=false,"collection",1
            dispatch("test_cards")
        end
        if button(481,6,body+65,tr("领取空卡片夹","Claim empty card wallet"),gold) then
            folded,warehouse_tab,transfer_slot=false,"equipment",1
            dispatch("test_wallet")
        end
    end
    return hover
end

local function draw_surgery(cast,tr,x,y,width,scale)
    local format=NHFirearms.packs[cast.kind] and tr("补弹中  %.1f 秒","Resupply  %.1f s") or NHShields.chargers[cast.kind] and tr("充能中  %.1f 秒","Charging  %.1f s")
        or NHMedkits.types[cast.kind] and tr("治疗中  %.1f 秒","Treating  %.1f s") or tr("手术中  %.1f 秒","Surgery  %.1f s")
    local caption=string.format(format,math.ceil((cast.total-cast.elapsed)/6)/10)
    local factor=math.min(scale,width/GuiGetTextDimensions(gui,caption))
    tint(white)
    GuiText(gui,x,y,caption,factor)
    local pixel="data/ui_gfx/1px_white.png"
    tint(muted)
    GuiImage(gui,5031,x,y+12*scale,pixel,0.4,width,2*scale)
    if cast.elapsed>0 then
        GuiZSetForNextWidget(gui,-81)
        tint(green)
        GuiImage(gui,5032,x,y+12*scale,pixel,1,width*cast.elapsed/cast.total,2*scale)
    end
end

local function slot_uses(slot,doseCapacity)
    local kind=slot.kind
    local view=slot.view or slot
    local red=NHRedRelics.types[kind]
    if red and view.remaining~=nil then return view.remaining,red.item.remaining end
    if NHFirearms.rigs[kind] then return view.reserve or 0,NHFirearms.rigs[kind].capacity end
    local firearm=NHFirearms.items[kind]
    if firearm and firearm.magazine and view.rounds~=nil then return view.rounds,firearm.magazine end

    local capacity=NHMedkits.capacity(kind)
    if guns[kind] then capacity=guns[kind].capacity
    elseif foods[kind] then capacity=foods[kind].uses
    elseif NHEquipment.links[kind] then capacity=NHEquipment.links[kind].uses
    elseif kind=="summon_card" then capacity=NHCompanions.cardCapacity(view.species or slot.species)
    elseif kind=="dose" then capacity=doseCapacity end
    return slot.remaining or capacity,capacity
end

local function draw_travel_panel(v,layout,scale,sh,tr,dispatch,mx,my,panels,fresh)
    if not travelSession.entries then
        local entries={}
        for _,group in ipairs(v.groups) do
            entries[#entries+1]=group
            if travelSession.expanded[group.world] then
                for _,route in ipairs(group.routes) do entries[#entries+1]=route end
            end
        end
        travelSession.entries=entries
    end
    local entries=travelSession.entries
    local pitch,header=22,27
    local visible=math.min(#entries,math.max(1,math.floor((layout.panelHeight-24-header-4)/pitch)))
    local left,width=layout.middle,layout.bench*scale
    local height=(header+visible*pitch+4)*scale
    local top=sh-5-24*scale-height
    panels[#panels+1]={x=left,y=top,w=width,h=height,slot={key="panel"}}
    GuiZSetForNextWidget(gui,-79)
    GuiImageNinePiece(gui,7350,left,top,width,height,1)
    local function line(x,y,value,color,size,room,detail)
        size=math.max(size*0.85,math.min(size,room/math.max(1,GuiGetTextDimensions(gui,value,1))))
        local text,short=fit(value,room,size)
        tint(color)
        GuiText(gui,x,y,text,size)
        if short or detail then GuiTooltip(gui,value,detail or "") end
    end
    local x,y=left+5*scale,top+header*scale
    local w=width-10*scale
    line(x,top+3*scale,tr("旅行终端","Travel terminal"),gold,scale,w)
    line(x,top+15*scale,tr("点击航点开启传送门","Click a stop to open its portal"),muted,0.85*scale,w)
    local arrived=travelSession.frame==GameGetFrameNum()
    local first=scrollMenu.rows(gui,"travel/routes",7352,#entries,visible,x,y,w,pitch*visible*scale,scale,mx,my,arrived and 0 or nil,drag)
    if #entries>visible then w=w-6*scale end
    for slot=1,visible do
        local row=entries[first+slot]
        local hovered=mx>=x and mx<x+w and my>=y and my<y+pitch*scale
        local clicked=hovered and not drag and not fresh and not arrived and InputIsMouseButtonJustDown(1)
        local active=row.kind and row.kind==v.gateKind and row.x==v.gateX and row.y==v.gateY
        if hovered or active then
            GuiZSetForNextWidget(gui,-79)
            GuiImage(gui,7360+slot,x,y,"data/ui_gfx/1px_white.png",hovered and 0.17 or 0.09,w,pitch*scale)
        end
        if row.routes then
            local world=row.world
            local name=tr("主世界","Main world")
            if world<0 then name=tr("西 %d 平行世界","West world %d"):format(-world)
            elseif world>0 then name=tr("东 %d 平行世界","East world %d"):format(world) end
            local expanded=travelSession.expanded[world]
            local title=(expanded and "[-] " or "[+] ")..name
            line(x+2*scale,y,title,gold,scale,w-4*scale)
            line(x+5*scale,y+11*scale,tr("已解锁 %d 站","Stops unlocked: %d"):format(#row.routes),muted,0.85*scale,w-7*scale)
            if clicked then
                travelSession.expanded[world]=not expanded
                travelSession.entries=nil
            end
        else
            local name,detail=travelRoutes.label(row,tr)
            local pos=("(%d, %d)"):format(row.x,row.y)
            line(x+5*scale,y,(active and "> " or "")..name,active and green or white,scale,w-7*scale,pos)
            line(x+5*scale,y+11*scale,detail~="" and detail or pos,muted,0.85*scale,w-7*scale)
            if clicked then dispatch("travel_to",row.index) end
        end
        y=y+pitch*scale
    end
end

local function draw_case(model, ox, oy, scale, sw, sh, tr, label, dispatch,layout,pw,ph,popupHeight,collapsed)
    local frame = GameGetFrameNum()
    local fresh = last_case_frame ~= frame - 1
    if fresh then drag,loading,dismantle_mode=nil,nil,false end
    last_case_frame = frame
    local wx, wy = DEBUG_GetMouseWorld()
    local cx, cy, cw, ch = GameGetCameraBounds()
    local mx, my = (wx-cx)*sw/cw, (wy-cy)*sh/ch
    local slots = {}
    local panels={}
    -- Container rows advance by the native tile width, including its border.
    local qw,qh = GuiGetImageDimensions(gui,tile)
    local function slot(column,y,key,kind,name,icon,entity,left,top)
        local x = 8 + column * qw
        slots[#slots+1] = {x=(left or ox)+x*scale, y=(top or oy)+y*scale, key=key, kind=kind,
            name=name, icon=icon, entity=entity, pouchId=kind=="pouch" and entity or nil,
            walletId=kind=="card_wallet" and entity or nil}
    end

    local standalone = model.mode=="container"
    if model.gear and not standalone and not collapsed then
        local x=ox+8*scale
        for i,key in ipairs({"gear","safe"}) do
            local title=i==1 and tr("装备","Gear") or tr("安全箱","Secure case")
            local y=oy+equipment_tabs_y*scale
            local tabScale=math.min(scale,(pw/2-8)*scale/GuiGetTextDimensions(gui,title))
            local width=GuiGetTextDimensions(gui,title,tabScale)
            tint(equipment_tab==key and gold or muted)
            local clicked=GuiButton(gui,5100+i,x,y,title,tabScale)
            local over=drag and mx>=x and mx<x+width and my>=y and my<y+12*scale
            if clicked or over then equipment_tab=key end
            x=x+width+8*scale
        end
    end
    if not standalone and not collapsed and (not model.gear or equipment_tab=="safe") then
        local gridY=model.gear and equipment_grid_y or 25
        local totalRows=math.ceil(model.capacity/case_columns)
        local gridHeight=math.min(case_rows,totalRows)*qh
        local row=scrollMenu.rows(gui,"safe",7110,totalRows,case_rows,
            ox+6*scale,oy+gridY*scale,math.min(pw-6,case_columns*qw+9)*scale,gridHeight*scale,scale,mx,my,revealSafe,drag)
        revealSafe=nil
        local start=row*case_columns
        for i=1,math.min(visible_case_slots,model.capacity-start) do
            local n=start+i
            local v = model.secure_loot[n] or {}
            slot((i-1)%case_columns,gridY+math.floor((i-1)/case_columns)*qh,"valuable",v.kind,v.name or tr("空格","Empty slot"),v.icon,v.id)
            slots[#slots].safeSlot,slots[#slots].dockSlot,slots[#slots].view=n,v.dockSlot,v
            slots[#slots].remaining,slots[#slots].count,slots[#slots].subtype,slots[#slots].species=v.remaining,v.count,v.subtype,v.species
        end
    end
    local popupY = model.popup and not standalone and not collapsed and -(popupHeight+5) or 0
    if model.gear and not standalone and not collapsed and equipment_tab=="gear" then
        for pair,heading in ipairs({tr("护盾<充能器","Shield<Charger"),tr("弹挂<弹药盒","Rig<Ammo box")}) do
            local rowY=equipment_grid_y+(pair-1)*(qh+15)
            local width=GuiGetTextDimensions(gui,heading)
            local headingScale=math.min(scale,2*qw*scale/width)
            tint(muted)
            GuiText(gui,ox+(8+qw)*scale-width*headingScale/2,oy+rowY*scale,heading,headingScale)
        end
        local linkColumn=2.5
        local linkX=8+linkColumn*qw
        local linkTitle=tr("数据链","Data link")
        local linkScale=scale*math.min(1,(pw-4-linkX)/GuiGetTextDimensions(gui,linkTitle))
        tint(muted)
        GuiText(gui,ox+linkX*scale,oy+equipment_grid_y*scale,linkTitle,linkScale)
        for i,field in ipairs({"shield","charger","rig","ammo","link"}) do
            local v=model.gear[field] or {}
            local title=({tr("护盾","Shield"),tr("充能器","Charger"),tr("弹挂","Ammo rig"),tr("弹药盒","Ammo box"),tr("数据链","Data link")})[i]
            local column=field=="link" and linkColumn or (i-1)%2
            local row=i==5 and 0 or math.floor((i-1)/2)
            slot(column,equipment_grid_y+12+row*(qh+15),"gear",v.kind,v.name or title,v.icon,v.id)
            local entry=slots[#slots]
            entry.safeSlot,entry.view,entry.count,entry.remaining=i,v,v.count,v.remaining
        end

    end
    if model.popup and not collapsed then
        if not standalone then
            GuiZSetForNextWidget(gui,-79)
            GuiImageNinePiece(gui,37,ox,oy+popupY*scale,pw*scale,popupHeight*scale,1)
        end
        label(8,popupY+5,model.pouchName,pw-43,white)
        if GuiButton(gui,38,ox+(pw-34)*scale,oy+(popupY+5)*scale,tr("关闭","Close"),scale) then
            drag=nil
            dispatch("close_container")
            return
        end
        for i=1,(model.walletId and model.walletCapacity or model.pouchCapacity) do
            local col=(i-1)%4
            local rowY=popupY+23+math.floor((i-1)/4)*qh
            local cell=model.cells[i]
            if model.gunId then
                local title=i==1 and tr("命中","Impact") or tr("弹道","Flight")
                slot(col,rowY,"gun_socket",cell and "spell",cell and tr(cell.zh,cell.en) or title,cell and cell.icon,cell and cell.id)
                slots[#slots].gunId=model.gunId
                label(8+col*qw,rowY+qh,title,qw,muted)
            elseif model.chainId then
                slot(col,rowY,"relic_cell",cell and "relic",cell and cell.name or tr("遗物插槽","Relic socket"),cell and cell.icon,cell and cell.id)
                slots[#slots].chainId,slots[#slots].view=model.chainId,cell
            elseif model.walletId then
                local species=cell and NHCompanions.cardDefinition(cell.species)
                slot(col,rowY,"card_cell",cell and "summon_card",species and tr(species.zh,species.en) or tr("空格","Empty slot"),cell and cell.icon)
            else
                local d=cell and NHInjectors.get(cell.subtype)
                slot(col,rowY,"dose",cell and "dose",d and tr(d.zh,d.en) or tr("空格","Empty slot"),d and d.icon)
            end
            local v=slots[#slots]
            v.cell,v.pouchId,v.walletId=i,model.pouchId,model.walletId
            if cell then v.remaining,v.count,v.subtype,v.species=cell.remaining,cell.count,cell.subtype,cell.species end
        end
    end

    local perk_top
    if not standalone and not collapsed then
        perk_top=NHPerks.draw(gui,model,ox,oy,scale,pw,qw,qh,popupY,tr,slot,slots,function(action,args)
            if not fresh and not drag then dispatch(action,args) end
        end)
    end
    local stock_tip
    if layout then
        local showTravel=travelSession and workshop_folded
        draw_workshop(model,layout,scale,sh,tr,dispatch,mx,my,panels)
        if showTravel and workshop_folded then
            draw_travel_panel(model.travel,layout,scale,sh,tr,dispatch,mx,my,panels,fresh)
        end
        local left,width=layout.stashX,layout.stash
        local cols=math.max(1,math.min(10,math.floor((width-16)/qw)))
        local tabs,grid_y=layout.tabs,layout.gridY
        local content_height=layout.contentHeight
        local height=folded and 20 or layout.panelHeight
        local top=sh-5-height*scale
        local warehouse_hover=mx>=left and mx<left+width*scale and my>=top and my<top+height*scale
        panels[#panels+1]={x=left,y=top,w=width*scale,h=height*scale,slot={key="panel"}}
        if warehouse_hover and drag and not folded then
            local src=drag.source
            if src.key=="gear" then warehouse_tab="equipment"
            elseif src.key=="gun_socket" then warehouse_tab="spell"
            elseif src.key=="dose" then warehouse_tab="supplies"
            elseif src.key=="card_cell" or (src.key=="valuable" and NHStore.category(src.kind)=="collection") then warehouse_tab="collection"
            elseif (src.key=="valuable" or src.key=="relic_cell") and NHStore.category(src.kind)=="equipment" then warehouse_tab="equipment"
            elseif src.key=="valuable" and NHFirearms.items[src.kind] then warehouse_tab=NHStore.category(src.kind)
            elseif src.key=="native" and src.kind~="other" and (warehouse_tab~="materials" or src.kind~="potion") then
                warehouse_tab=NHStore.category(src.kind)
            end
        end
        GuiZSetForNextWidget(gui,-79)
        GuiImageNinePiece(gui,70,left,top,width*scale,height*scale,1)
        tint(gold)
        local stash_name=model.remote_linked and tr("仓库 · 远程","Stash · Remote") or tr("仓库","Stash")
        if GuiButton(gui,71,left+6*scale,top+3*scale,(folded and "[+] " or "[-] ")..stash_name,scale) and not drag then
            folded,loading,dismantle_mode=not folded,nil,false
            return
        end
        if not folded then
            for i,t in ipairs(warehouse_tabs) do
                local pos=tabs[i]
                tint(t.key==warehouse_tab and gold or muted)
                local bx,by=left+pos.x*scale,top+warehouse_tabs_y*scale
                local clicked=GuiButton(gui,t.id,bx,by,pos.name,pos.scale)
                if pos.name~=pos.full and not drag then GuiTooltip(gui,pos.full,"") end
                -- A stored bottle can cross between both pages without visiting the quick bar.
                local cross=drag and drag.source.kind=="potion" and
                    ((drag.source.key=="warehouse" and t.key=="materials") or (drag.source.key=="docks" and t.key=="containers"))
                local over=cross and mx>=bx and mx<bx+pos.w*scale and my>=by and my<by+10*scale
                if (clicked and not drag or over) and warehouse_tab~=t.key then
                    warehouse_tab,loading,dismantle_mode=t.key,nil,false
                    return
                end
            end
            local bulk=warehouse_tab=="materials"
            local essences=warehouse_tab=="essences"
            local footerY=top+(height-14)*scale
            local sortLabel=tr("一键整理","Sort")
            local sortWidth=GuiGetTextDimensions(gui,sortLabel,scale)
            local sortX=left+(width-6)*scale-sortWidth
            tint(gold)
            if GuiButton(gui,7080,sortX,footerY,sortLabel,scale) and not drag then
                transfer_slot=1
                if bulk or essences then sorted_stock[warehouse_tab]={}
                else dispatch("organize_warehouse",{category=warehouse_tab}) end
            end
            GuiTooltip(gui,sortLabel,(bulk or essences) and tr("按库存量从多到少排列","Sort by amount, highest first")
                or tr("同类物品排在一起，空格移到末尾","Group similar items and move empty slots to the end"))
            if warehouse_tab=="containers" or warehouse_tab=="spell" or warehouse_tab=="supplies" then
                local spellTab=warehouse_tab=="spell"
                local supplies=warehouse_tab=="supplies"
                local enabled=supplies or model.salvage_enabled
                if not enabled or dismantle_mode~=warehouse_tab then dismantle_mode=false end
                local caption=(dismantle_mode and "[x] " or "[ ] ")..(supplies and tr("快售／转化","Sell / convert") or spellTab and tr("快速提取","Quick extract") or tr("存放并拆解","Store and dismantle"))
                local x=left+6*scale
                local buttonScale=math.min(scale,(sortX-x-5*scale)/GuiGetTextDimensions(gui,caption))
                tint(enabled and (dismantle_mode and green or white) or muted)
                if GuiButton(gui,7081,x,footerY,caption,buttonScale) and enabled and not drag then
                    dismantle_mode=not dismantle_mode and warehouse_tab
                    salvage_target=nil
                end
                GuiTooltip(gui,caption,supplies and tr("左键出售普通消耗品，或将风暴产物转为资源。按住 Shift 处理整组。","Click to sell a supply or convert a storm product to resources. Hold Shift for the stack.")
                    or model.salvage_enabled and (spellTab and tr("左键点已解锁合成的法术，整叠提取为精华。","Click a spell with an unlocked recipe to extract its whole stack as essence.") or tr("开启后，左键点容器即可存入全部物料并拆解空壳。","Enable, then click a container to store its contents and dismantle the shell."))
                    or tr("需要先建造拆解台","Build the dismantling station first"))
            else dismantle_mode=false end
            local capacity=essences and #model.essences or model.warehouse_capacity[warehouse_tab]
            local columns=essences and essence_columns or (bulk and 2 or cols)
            local visibleRows=essences and essence_rows or (bulk and material_rows or math.floor(content_height/qh))
            local count=bulk and #model.materials or capacity
            local listY=bulk and grid_y+qh+26 or grid_y
            local pitch=bulk and 11 or (essences and ((width-8)/essence_columns<50 and 18 or 14) or qh)
            local row=scrollMenu.rows(gui,"stash/"..warehouse_tab,7112,math.ceil(count/columns),visibleRows,
                left,top+listY*scale,width*scale,visibleRows*pitch*scale,scale,mx,my,
                transfer_slot and math.floor((transfer_slot-1)/columns),drag)
            transfer_slot=nil
            local start,visible=row*columns,visibleRows*columns
            if essences then
                stock_tip=draw_essences(stock_rows(warehouse_tab,model.essences),start+1,visible,left,top+grid_y*scale,width,scale,mx,my)
            elseif bulk then
                local docks,materials=model.docks,stock_rows(warehouse_tab,model.materials)
                local column_width=math.floor((width-12)/2)
                for n=1,2 do
                    local dock=docks[n] or {}
                    local x0=left+(n-1)*column_width*scale
                    local title=n==1 and tr("药瓶","Flask") or tr("粉末袋","Powder pouch")
                    slot(0,grid_y,"docks",dock.kind,dock.name or title,dock.icon,dock.id,x0,top)
                    slots[#slots].safeSlot,slots[#slots].view=n,dock
                    local x=x0+(qw+10)*scale
                    local title_fit=fit(title,(column_width-qw-10)*scale,scale)
                    GuiText(gui,x,top+grid_y*scale,title_fit,scale)
                    if dock.id then
                        GuiText(gui,x,top+(grid_y+10)*scale,compact(dock.used).."/"..compact(dock.capacity),0.85*scale)
                        tint(dock.used>0 and gold or muted)
                        if GuiButton(gui,180+n,x0+8*scale,top+(grid_y+qh+1)*scale,tr("全部卸入","Unload all"),scale)
                            and not drag and dock.used>0 then
                            dispatch("material_transfer",{container="docks",slot=n,storedId=dock.id,unload=true})
                            return
                        end
                    end
                end
                local y=grid_y+qh+15
                GuiText(gui,left+8*scale,top+y*scale,tr("库存 ","Stock ")..#materials.."/"..capacity,scale)
                if #materials==0 then
                    tint(muted)
                    GuiText(gui,left+8*scale,top+(y+13)*scale,tr("库存为空","Empty"),scale)
                end
                local held_target
                for i=1,visible do
                    local mat=materials[start+i]
                    if mat then
                        local col=(i-1)%2
                        local row=math.floor((i-1)/2)+1
                        local row_y=top+(y+11*row)*scale
                        local start_x=left+(8+col*column_width)*scale
                        local end_x=start_x+(column_width-4)*scale
                        local dock=docks[mat.slot]
                        local enabled=dock and dock.used<dock.capacity
                        local amount=compact(mat.amount)
                        local bx=end_x-9*scale
                        local count_x=bx-4*scale-GuiGetTextDimensions(gui,amount,scale)
                        local name=fit(mat.name,count_x-start_x-3*scale,scale)
                        GuiText(gui,start_x,row_y,name,scale)
                        GuiText(gui,count_x,row_y,amount,scale)
                        tint(enabled and gold or muted)
                        if not mat.hideout then GuiButton(gui,186+i,bx,row_y,"+",scale) end
                        local hover=mx>=start_x and mx<end_x and my>=row_y and my<row_y+11*scale
                        if hover then
                            local tip=enabled and tr("点按 1 单位，按住加速","Click for 1 unit; hold to load faster")
                                or (mat.hideout and tr("藏身处专用材料，用于工坊配方。","Hideout material for workshop recipes.")
                                or (not mat.slot and tr("无匹配容器","No compatible container")
                                or (dock and tr("容器已满","Container full") or tr("请先放入对应容器","Dock a compatible container first"))))
                            stock_tip={mat.name.."  "..string.format("%.0f",mat.amount),tip}
                        end
                        if enabled and hover and not drag and not fresh then
                            if InputIsMouseButtonJustDown(1) then
                                loading={name=mat.key,id=dock.id,start=frame}
                            end
                            if loading and loading.name==mat.key and loading.id==dock.id and InputIsMouseButtonDown(1) then
                                held_target=true
                                local batch=transfer_batch(frame-loading.start,100)
                                if batch then
                                    dispatch("material_transfer",{container="docks",slot=mat.slot,storedId=dock.id,material=mat.key,amount=batch})
                                end
                            end
                        end
                    end
                end
                if not held_target then loading=nil end
            else
                local rows=model.warehouse[warehouse_tab] or {}
                for i=0,math.min(visible,capacity-start)-1 do
                    local n=start+i+1
                    local v=rows[n] or {}
                    slot(i%cols,grid_y+math.floor(i/cols)*qh,"warehouse",v.kind,v.name or tr("空格","Empty slot"),v.icon,v.id,left,top)
                    local target=slots[#slots]
                    target.view=v
                    target.dismantle=dismantle_mode
                    target.subtype,target.species=v.subtype,v.species
                    target.safeSlot,target.remaining,target.count,target.dockSlot=n,v.remaining,v.count,v.dockSlot
                end
            end
        end
    else
        loading,dismantle_mode=nil,false
        if drag and (drag.source.key=="warehouse" or drag.source.key=="docks") then drag=nil end
    end

    local native_x = tonumber(MagicNumbersGetValue("UI_BARS_POS_X"))
    local native_y = tonumber(MagicNumbersGetValue("UI_BARS_POS_Y"))
    local full_offset = tonumber(MagicNumbersGetValue("UI_FULL_INVENTORY_OFFSET_X"))
    local fw,fh = GuiGetImageDimensions(gui,full_tile)
    -- Both pre-update input gating and this frame's dispatch use this draw order.
    local boxes={width=sw,height=sh,frame=frame}
    for _, v in ipairs(model.native_slots) do
        local full = v.lane=="spell"
        local w,h = full and fw or qw,full and fh or qh
        local x = native_x + (full and full_offset or 0) + v.col*w
        local y = native_y + v.yslot*h
        if not standalone or not full then boxes[#boxes+1]={x=x,y=y,w=w,h=h,slot=v} end
    end
    local panel_top=perk_top or (oy+popupY*scale)
    panels[#panels+1]={x=ox,y=panel_top,w=pw*scale,h=oy+ph*scale-panel_top,slot={key="panel"}}
    for _,box in ipairs(panels) do boxes[#boxes+1]=box end
    for _,v in ipairs(slots) do
        boxes[#boxes+1]={x=v.x,y=v.y,w=qw*scale,h=qh*scale,slot=v}
    end
    last_inventory_layout=boxes
    local hovered=slot_at(boxes,mx,my)
    if drag and (model.revision~=drag.revision or model.pouchId~=drag.pouchId or model.walletId~=drag.walletId or model.chainId~=drag.chainId or model.gunId~=drag.gunId) then drag=nil end
    local prepared,pending_use=model.rightUse
    if prepared then
        model.rightUse=nil
        if not fresh and not drag and not InputIsMouseButtonDown(1) then
            local source=use_source(hovered)
            if same_use(source,prepared) then
                if source.preview then
                    salvage_target={id=source.storedId,kind=source.kind,slot=source.slot,mode="collectible"}
                    workshop_folded=false
                else pending_use=source end
            end
        end
    elseif hovered and not hovered.dismantle and hovered.key=="warehouse" and hovered.view
        and not NHRedRelics.types[hovered.kind] and model.salvage_enabled and hovered.view.salvage_yield
        and not fresh and not drag and InputIsMouseButtonJustDown(2) then
        salvage_target={id=hovered.entity,kind=hovered.kind,slot=hovered.safeSlot,
            mode=hovered.view.store_contents and "store_contents" or hovered.view.essence and "essence" or "scrap"}
        workshop_folded=false
    end
    if hovered and hovered.dismantle then
        if warehouse_tab=="supplies" and not fresh and not drag then
            local q=hovered.view.trade
            if q and InputIsMouseButtonJustDown(1) then
                dispatch("supply_trade",{kind=hovered.kind,slot=hovered.safeSlot,id=hovered.entity,count=q.count,remaining=q.remaining,
                    quantity=NHUI.shiftDown() and q.count or 1,mode=q.resource and "convert" or "sell"})
            end
        elseif not fresh and not drag and not NHUI.shiftDown() and InputIsMouseButtonJustDown(1) then
            local mode=hovered.kind=="potion" and hovered.view.salvage_yield and "store_contents"
                or hovered.kind=="spell" and hovered.view.quick_essence and "quick_essence"
            if mode then dispatch("salvage",{kind=hovered.kind,slot=hovered.safeSlot,id=hovered.entity,mode=mode}) end
        end
    elseif not fresh and InputIsMouseButtonJustDown(1) and hovered and hovered.kind and hovered.kind~="reserved"
        and not (model.mode=="case" and NHUI.shiftDown() and quick_source(hovered)) then
        drag={source=hovered,gunId=model.gunId,revision=model.revision,pouchId=model.pouchId,walletId=model.walletId,chainId=model.chainId,x=mx,y=my}
    end
    if drag and ((mx-drag.x)^2+(my-drag.y)^2)>9*scale^2 then drag.moved=true end
    local source=drag and drag.source
    local function drop(target)
        if not source or not target then return end
        if (source.kind=="pouch" or source.kind=="card_wallet" or (source.kind=="relic_chain" and source.key=="valuable") or (storage_key(source.key) and NHFirearms.modes.guns[source.kind])) and source.key==target.key and source.entity==target.entity
            and source.safeSlot==target.safeSlot and not drag.moved then
            return "open_container",source,source.safeSlot
        end
        local from_store=source.key=="valuable" or source.key=="warehouse"
        local to_store=target.key=="valuable" or target.key=="warehouse"
        if target.key=="gun_socket" and not target.kind and from_store and source.view then
            local d=NHFirearms.mods.byAction[source.view.actionId]
            if d and d.slot==target.cell then return "move_gun_attachment",source end
        elseif source.key=="gun_socket" and to_store and not target.kind and (target.key=="valuable" or warehouse_tab=="spell") then
            return "move_gun_attachment",source,target.safeSlot
        end
        if target.key=="gear" and target.safeSlot==NHShields.slot(source.kind) then
            if source.key=="native" and not target.kind then return "place",source,target.safeSlot end
            if from_store and (not target.kind or not NHShields.supply(source.kind)) then return "move_gear",source,target.safeSlot end
        end
        if source.key=="gear" then
            if target.key=="native" and not target.entity and target.lane=="tool" then return "take_gear",target,source.safeSlot,source.entity end
            if to_store and (target.key=="valuable" or warehouse_tab=="equipment") and
                (not target.kind or (NHShields.supply(source.kind) and target.kind==source.kind)) then return "move_gear",source,target.safeSlot end
            return
        end
        local storm=stormProducts.types[source.kind]
        if (NHMedkits.capacity(source.kind) or foods[source.kind] or bags[source.kind] or guns[source.kind] or turrets[source.kind] or storm) and to_store and (not target.kind or target.kind==source.kind)
            and (not target.kind or not storm or (target.count or 1)+(from_store and 1 or source.count or 1)<=stormProducts.stackLimit)
            and (not target.kind or not guns[source.kind] or
                gunCatalog.canCombine(guns[source.kind],source.remaining,target.remaining))
            and (not target.kind or not NHMedkits.capacity(source.kind) or NHMedkits.canCombine(source.kind,NHMedkits.charges(source),NHMedkits.charges(target)))
            and (not target.kind or not turrets[source.kind] or (source.count or 1)+(target.count or 1)
                <=turretCatalog.slotLimit(source.kind,target.safeSlot,target.key=="warehouse" and model.workshopOutput))
            and (target.key=="valuable" or warehouse_tab==NHStore.category(source.kind)) then
            if source.key=="native" then return "place",source,target.safeSlot end
            if from_store and (source.key~=target.key or source.safeSlot~=target.safeSlot) then
                return "move_food",source,target.safeSlot
            end
        end
        if source.kind=="relic" then
            if target.key=="relic_cell" and not target.kind then
                if source.key=="native" then return "place",source end
                if from_store or source.key=="relic_cell" then return "move_chain_relic",source end
            end
            if source.key=="relic_cell" and not target.kind then
                if to_store and (target.key=="valuable" or warehouse_tab=="equipment") then return "move_chain_relic",source,target.safeSlot end
                if target.key=="native" and not target.entity and target.lane=="tool" then return "take_relic",target,nil,source.entity end
            end
        end
        if NHFirearms.items[source.kind] and not NHFirearms.packs[source.kind] and from_store and to_store and not target.kind
            and (target.key=="valuable" or warehouse_tab==NHStore.category(source.kind)) then return "move_firearm",source,target.safeSlot end
        if (source.kind=="relic" or source.kind=="relic_chain" or source.kind=="tablet" or source.kind=="native_valuable" or NHRedRelics.types[source.kind]) and from_store and to_store and not target.kind
            and (target.key=="valuable" or warehouse_tab==NHStore.category(source.kind)) then return "move_relic",source,target.safeSlot end
        if source.kind=="summon_card" then
            local accepts=not target.kind or (target.kind=="summon_card" and NHCompanions.canStack(target,source))
            if target.key=="card_cell" and accepts then
                if source.key=="native" then return "place",source end
                if from_store or (source.key=="card_cell" and source.cell~=target.cell) then return "move_wallet_card",source end
            end
            if to_store and accepts and (target.key=="valuable" or warehouse_tab=="collection") then
                if source.key=="card_cell" then return "move_wallet_card",source,target.safeSlot end
                if from_store and (source.key~=target.key or source.safeSlot~=target.safeSlot) then return "move_stored_card",source,target.safeSlot end
                if source.key=="native" then return "place",source,target.safeSlot end
            end
            if source.key=="card_cell" and target.key=="native" and not target.entity and target.lane=="tool" then return "take_card",target end
        end
        if (source.kind=="card_wallet" or NHEquipment.links[source.kind]) and from_store and to_store and not target.kind
            and (target.key=="valuable" or warehouse_tab=="equipment") and (source.key~=target.key or source.safeSlot~=target.safeSlot) then
            return source.kind=="card_wallet" and "move_wallet" or "move_terminal",source,target.safeSlot
        end
        if model.mode=="case" and source.kind=="perk" and not target.kind then
            if from_store and target.key=="perk" then return "equip_stored_perk",source end
            if source.key=="perk" and to_store and (target.key=="valuable" or warehouse_tab=="supplies") then
                return "store_equipped_perk",source
            end
        end
        if source.kind=="pouch" and from_store and to_store and not target.kind
            and (target.key=="valuable" or warehouse_tab=="equipment") then
            return "move_pouch",source,target.safeSlot
        end
        if target.key=="docks" and not target.kind and source.kind=="potion" and source.dockSlot==target.safeSlot then
            if source.key=="native" then return "place",source,target.safeSlot end
            if from_store then return "move_dock",source,target.safeSlot end
        end
        if source.key=="docks" and to_store and not target.kind and (target.key=="valuable" or warehouse_tab=="containers") then
            return "move_dock",source,target.safeSlot
        end
        local canStack = source.kind=="dose" and target.kind=="dose"
            and (source.subtype or "fire")==(target.subtype or "fire")
            and (source.remaining or model.maxUses)==model.maxUses and (target.remaining or model.maxUses)==model.maxUses
        if from_store and source.kind=="dose" and source.key==target.key
            and source.safeSlot~=target.safeSlot and (not target.kind or canStack) then
            return "move_safe_dose",source,target.safeSlot
        end
        if source.key=="warehouse" and target.key=="warehouse" and not target.kind then
            return "move_warehouse",source,target.safeSlot
        end
        if source.key=="dose" and target.key=="dose" and source.cell~=target.cell and (not target.kind or canStack) then
            return "move_cell",source
        end
        if source.key=="dose" and to_store and (target.key~="warehouse" or warehouse_tab=="supplies") and (not target.kind or canStack) then
            return "unpack_dose",source,target.safeSlot
        end
        if from_store and source.kind=="dose" and target.key=="dose" and (not target.kind or canStack) then
            return "pack_dose",source,source.safeSlot
        end
        if source.key=="native" then
            if target.key=="relic_cell" then return "reject_relic",source end
            if target.key=="perk" and not target.kind and source.kind=="perk" then return "equip_perk",source,target.perkSlot end
            if target.key=="dose" and model.popup and source.kind=="dose" and (not target.kind or canStack) then return "place",source end
            if to_store and (not target.kind or canStack) and source.kind~="other"
                and (target.key~="warehouse" or NHStore.category(source.kind)==warehouse_tab) then
                return "place",source,target.safeSlot
            end
            if target.key~="native" then return "cancel_native",source end
        elseif target.key=="native" and not target.entity then
            local lane=NHFirearms.lane(source.kind)
            if target.lane~=lane then return end
            if source.key=="perk" then return "unequip_perk",target,source.perkSlot,source.entity end
            if source.kind=="pouch" then return "take_pouch",target,source.safeSlot end
            if from_store or source.key=="docks" then return "secure_withdraw",target,source.safeSlot,source.entity end
            if source.key=="dose" then return "take_dose",target end
        end
    end
    local function sprite(v,id,x,y,alpha)
        local gun=NHGuns.types[v.kind]
        local displayArt=gun and gun.displaySprite or NHRedRelics.types[v.kind] and NHRedRelics.types[v.kind].item.icon
        local image = displayArt or (v.kind=="summon_card" and v.species and NHCompanions.cardIcon(v.species)) or v.icon
        if type(image) ~= "string" or not image:match("%.png$") then image=icons[v.kind] end
        if not image then
            GuiText(gui,x-2*scale,y-4*scale,"?",scale)
            return
        end
        local w,h = GuiGetImageDimensions(gui,image)
        if not w or not h or w<=0 or h<=0 then return end
        -- The native inventory icons occupy 16 pixels. Keep their footprint
        -- while drawing the original gun art at the current interface scale.
        local maxZoom=displayArt and 16/math.max(w,h) or 1
        local zoom = math.min(maxZoom,(qw-3)/w,(qh-3)/h)*scale
        GuiZSetForNextWidget(gui,-83)
        local view=v.view
        if view and view.potion then
            if view.tint==nil then view.tint=NHPotion.contentsColor(view.potion) or false end
            if view.tint then
                local c=view.tint
                GuiColorSetForNextWidget(gui,c%256/255,math.floor(c/256)%256/255,math.floor(c/65536)%256/255,1)
            end
        end
        GuiImage(gui,id,x-w*zoom/2,y-h*zoom/2,image,alpha,zoom)
    end
    -- Each glyph is a 6x10 bitmap with one pixel of spacing. Measure and draw
    -- in the same coordinates, independently of the game's language font.
    local function corner_label(v,id,text,bottomRight)
        local width=7*#text-1
        local pad=2*scale
        local zoom=scale*math.min(0.5,(qw-4)/width)
        local x,y=v.x+pad,v.y+pad
        if bottomRight then
            x,y=v.x+qw*scale-pad-width*zoom,v.y+qh*scale-pad-10*zoom
        end
        for i=1,#text do
            local char=text:sub(i,i)
            local frameName=char=="/" and "slash" or char=="x" and "times" or char
            GuiZSetForNextWidget(gui,-84)
            tint(bottomRight and gold or white)
            GuiImage(gui,id+i-1,x+(i-1)*7*zoom,y,"mods/noita_hideout/files/slot_digits.xml",
                1,zoom,zoom,0,1,frameName) -- PlayToEndAndPause on the single-frame glyph.
        end
    end
    for i,v in ipairs(slots) do
        local placement=drop(v)
        if placement=="move_gun_attachment" or placement=="move_gear" or placement=="place" or placement=="move_chain_relic" or placement=="move_relic" or placement=="move_firearm" or placement=="move_pouch" or placement=="move_wallet" or placement=="move_terminal" or placement=="move_wallet_card"
            or placement=="move_stored_card" or placement=="equip_stored_perk" or placement=="store_equipped_perk" then tint(green) end
        GuiImage(gui,1000+i,v.x,v.y,tile,1,scale)
        if v.kind=="reserved" then GuiText(gui,v.x+5*scale,v.y+3*scale,"...",scale)
        elseif v.kind then sprite(v,2000+i,v.x+qw*scale/2,v.y+qh*scale/2,source and source.key==v.key and source.safeSlot==v.safeSlot and source.cell==v.cell and source.perkSlot==v.perkSlot and 0.35 or 1)
        end
        if v.kind then
            local current,maximum=slot_uses(v,model.maxUses)
            local firstGlyph=8192+i*64
            if maximum then corner_label(v,firstGlyph,("%d/%d"):format(current,maximum),false) end
            if (v.count or 1)>1 then
                corner_label(v,firstGlyph+32,("x%.0f"):format(v.count),true)
            end
        end
    end
    local tip=stock_tip
    if source then
        if source.key~="native" then sprite(source,3000,mx,my,0.95) end
        local action=hovered and drop(hovered)
        tip={action=="reject_relic" and tr("无法装入这个遗物插槽","Cannot place in this relic socket")
            or action and action~="cancel_native" and tr("松开放置","Release to place") or tr("拖至对应空格","Drag to a matching slot")}
    elseif hovered and hovered.kind and hovered.key~="native" then
        tip=item_details(hovered,model,tr)
        if hovered.dismantle then
            if warehouse_tab=="supplies" then
                local q=hovered.view.trade
                if q then
                    local all=NHUI.shiftDown()
                    local n=all and q.count or 1
                    if q.resource then
                        local name=NHStore.alchemyResources[q.resource]
                        tip[#tip+1]=string.format(tr("左键转化 %d 件 · %s +%d","Convert %d / %s +%d"),n,tr(name.zh,name.en),q.units*n)
                    else
                        tip[#tip+1]=string.format(tr("左键出售 %d 件 · %g 金","Click to sell %d / %g gold"),n,all and q.allGold or q.oneGold)
                    end
                    if q.count>1 then tip[#tip+1]=tr("按住 Shift 处理整组","Hold Shift for the stack") end
                elseif bags[hovered.kind] then tip[#tip+1]=tr("仅限右键开启","Right-click to open only")
                else tip[#tip+1]=tr("此物品无法回收","No trade value") end
            elseif warehouse_tab=="spell" then
                local e=hovered.view.essence
                tip[#tip+1]=hovered.view.quick_essence and tr("左键提取：","Click to extract: ")..e.name.." +"..e.amount
                    or tr("此法术没有已解锁的合成配方","No unlocked recipe for this spell")
            elseif hovered.view.materials_fit==false then tip[#tip+1]=tr("物料库空间不足","Material storage full")
            elseif hovered.view.salvage_yield then tip[#tip+1]=tr("左键存放并拆解 · 容器碎片 +1","Click to store and dismantle · +1 container scrap")
            else tip[#tip+1]=tr("此物品无法拆解","This item cannot be dismantled") end
        elseif hovered.key=="warehouse" and NHRedRelics.types[hovered.kind] then
            tip[#tip+1]=tr("Shift + 右键预览拆解","Shift + right-click to preview dismantling")
        elseif hovered.key=="warehouse" and model.salvage_enabled and hovered.view.salvage_yield then
            tip[#tip+1]=tr("右键预览拆解","Right-click to preview dismantling")
        elseif not NHRedRelics.types[hovered.kind] and hovered.kind~="pouch" and hovered.kind~="card_wallet" and hovered.kind~="relic_chain" and use_source(hovered) then
            tip[#tip+1]=tr("右键使用","Right-click to use")
        end
    end
    if tip and not source and model.mode=="case" and quick_source(hovered) then
        tip[#tip+1]=hovered.key=="warehouse" and tr("Shift + 左键取出一件","Shift + click to transfer one")
            or tr("Shift + 左键快速转移","Shift + click to transfer")
    end
    if tip then cursor_tip(tip,mx,my,sw,sh,scale) end
    if standalone and model.surgery then
        draw_surgery(model.surgery,tr,ox+8*scale,oy+49*scale,(pw-16)*scale,scale)
    elseif standalone then
        label(8,56,tr("拖动物品以存取","Drag items to transfer"),pw-16,muted)
    end
    if pending_use then
        if pending_use.kind=="pouch" or pending_use.kind=="card_wallet" or pending_use.kind=="relic_chain" then secure_folded=false end
        dispatch("use_inventory",pending_use)
    elseif drag and InputIsMouseButtonJustUp(1) then
        local action, arg, safeSlot, storedId = drop(hovered)
        drag=nil
        if action=="move_gear" then
            dispatch(action,{source=storage_key(source.key) or "gear",destination=storage_key(hovered.key) or "gear",
                container=storage_key(source.key) or storage_key(hovered.key) or "safe",kind=source.kind,
                entity=source.entity,from=source.safeSlot,safeSlot=safeSlot})
            return
        end
        if action=="equip_stored_perk" or action=="store_equipped_perk" then
            dispatch(action,{entity=source.entity,container=storage_key(source.key) or storage_key(hovered.key),
                storageSlot=source.safeSlot or hovered.safeSlot,perkSlot=source.perkSlot or hovered.perkSlot})
            return
        end
        if action then
            if action=="open_container" then secure_folded=false end
            local request = {parent=arg.parent,lane=arg.lane,xslot=arg.xslot,yslot=arg.yslot,
                entity=arg.entity,safeSlot=safeSlot,storedId=storedId,from=arg.safeSlot,kind=source.kind,
                source=storage_key(source.key),destination=storage_key(hovered.key),
                intoGear=hovered.key=="gear",
                container=(source.key=="docks" or hovered.key=="docks") and "docks" or storage_key(source.key) or storage_key(hovered.key) or "safe",
                sourceCell=source.cell,targetCell=hovered and hovered.cell,
                gunId=source.gunId or hovered.gunId,chainId=source.chainId or hovered.chainId,pouchId=source.pouchId or hovered.pouchId,walletId=source.walletId or hovered.walletId,
                species=source.species,remaining=source.remaining,count=source.kind=="summon_card" and (source.count or 1) or source.count,
                intoContainer=hovered and hovered.key=="dose"}
            dispatch(action,request)
        end
    elseif not InputIsMouseButtonDown(1) then drag=nil end
end

local function shield_points(n)
    if n>=1000000 then return ("%.3g"):format(n) end
    if n>0 and n<0.1 then return "<0.1" end
    return (("%.1f"):format(n):gsub("%.0$",""))
end

local function draw_shield(shield,screenWidth)
    if not shield.maxHp or shield.maxHp<=0 then return end
    local right=screenWidth+(tonumber(MagicNumbersGetValue("UI_BARS2_OFFSET_X")) or -40)-1
    local y=(tonumber(MagicNumbersGetValue("UI_BARS_POS_Y")) or 20)+1
    local height=math.max(1,math.floor(4*(tonumber(MagicNumbersGetValue("UI_BARS_SCALE")) or 1)+0.5))
    local cellPoints=NHShields.chargePoints(NHShields.cell,shield.maxHp)
    local live=math.ceil(shield.charge/NHShields.cell)
    local spare=math.max(0,live-1)
    local current=shield.charge/NHShields.cell-spare
    local label=("[%s]+[%s]"):format(shield_points(spare*cellPoints),shield_points(current*cellPoints))
    local labelW,labelH=GuiGetTextDimensions(gui,label)
    -- Native HP uses a fixed 40px track; health points must not stretch it.
    -- Every two shield cells span one health track, including native bar scaling.
    local maxWidth=math.floor((right-4)/shield.cells)
    local cellWidth=math.max(2,math.min(math.max(3,math.floor(20*(tonumber(MagicNumbersGetValue("UI_BARS_SCALE")) or 1)+0.5)),maxWidth))
    local pixel="data/ui_gfx/1px_white.png"
    GuiZSet(gui,-9010)
    for i=1,shield.cells do
        local edge=right-(i-1)*cellWidth
        local span=cellWidth-(i==shield.cells and 0 or 1)
        local filled=math.min(1,math.max(0,shield.charge/NHShields.cell-i+1))
        if filled>0 then
            local w=math.max(1,math.floor(span*filled+0.5))
            GuiColorSetForNextWidget(gui,0.24,0.48,1,1)
            GuiImage(gui,5710+i,edge-w,y,pixel,0.82,w,height)
            -- Clip diagonal bands to the current fill, leaving broken cells clear.
            GuiIdPushString(gui,"shield_stripes_"..i)
            local stripe=0
            for row=0,height-1 do
                local phase=(row-(edge-w))%6
                for column=-6+phase,w-1,6 do
                    local first,last=math.max(0,column),math.min(w,column+3)
                    if last>first then
                        GuiZSetForNextWidget(gui,-9011)
                        GuiColorSetForNextWidget(gui,0.64,0.32,0.94,1)
                        GuiImage(gui,stripe,edge-w+first,y+row,pixel,0.85,last-first,1)
                        stripe=stripe+1
                    end
                end
            end
            GuiIdPop(gui)
            GuiZSetForNextWidget(gui,-9012)
            GuiColorSetForNextWidget(gui,0.76,0.82,1,1)
            GuiImage(gui,5720+i,edge-w,y,pixel,0.92,w,1)
        end
        GuiColorSetForNextWidget(gui,0.64,0.91,1,1)
        GuiImage(gui,5700+i,edge-span,y+height-1,pixel,0.55,span,1)
        if i==live+1 and shield.repair>0 then
            local w=math.max(1,math.floor(span*shield.repair/360))
            GuiZSetForNextWidget(gui,-9011)
            tint(gold)
            GuiImage(gui,5730+i,edge-w,y+height-1,pixel,0.85,w,1)
        end
    end
    GuiColorSetForNextWidget(gui,0.82,0.9,1,1)
    GuiText(gui,math.max(2,right-labelW),math.max(0,y-labelH-3),label)
    GuiZSet(gui,-80)
    return right-shield.cells*cellWidth-3
end

-- Notifications are independent of the equipment window and survive closing it.
local notices={}
function NHUI.notify(message,isError)
    if not message or message=="" then return end
    local frame=GameGetFrameNum()
    local last=notices[#notices]
    if last and last.text==message then last.frame,last.error=frame,isError; return end
    notices[#notices+1]={text=message,frame=frame,error=isError}
    if #notices>3 then table.remove(notices,1) end
end
local function draw_notices(sw,sh)
    local now=GameGetFrameNum()
    for i=#notices,1,-1 do
        local age=now-notices[i].frame
        if age<0 or age>=300 then table.remove(notices,i) end
    end
    GuiZSet(gui,-9020)
    for i,n in ipairs(notices) do
        local alpha=math.min(1,(300-(now-n.frame))/60)
        local text=fit(n.text,math.max(40,sw-30),0.8)
        local w=GuiGetTextDimensions(gui,text,0.8)
        local x,y=math.floor((sw-w)/2),sh-43-(#notices-i)*15
        GuiColorSetForNextWidget(gui,0.08,0.10,0.12,1)
        GuiImage(gui,5800+i,x-5,y-2,"data/ui_gfx/1px_white.png",alpha*0.86,w+10,13)
        local color=n.error and {1,0.55,0.45} or {0.76,0.96,0.83}
        GuiColorSetForNextWidget(gui,color[1],color[2],color[3],alpha)
        GuiText(gui,x,y,text,0.8)
        GuiTooltip(gui,n.text,"")
    end
    GuiZSet(gui,-80)
end
local function draw_rescue(r,sw,tr,shieldLabelRight)
    local line=tr("保险 ","Insurance ")..(r.insured and tr("已投保","Active") or tr("未投保","None"))
    if r.species then line=line..tr(" · 保金 "," · Keep ")..string.format("%.0f",r.kept or 0) end
    -- Keep insurance left of the shield track and clear of vanilla money.
    local right=shieldLabelRight or sw+(tonumber(MagicNumbersGetValue("UI_BARS2_OFFSET_X")) or -40)-44
    local y=(tonumber(MagicNumbersGetValue("UI_BARS_POS_Y")) or 20)+24
    local scale=math.min(0.8,math.max(0.4,(right-5)/GuiGetTextDimensions(gui,line)))
    local w=GuiGetTextDimensions(gui,line,scale)
    GuiZSet(gui,-9010)
    tint(r.insured and green or muted)
    GuiText(gui,right-w,y,line,scale)
    local species=r.species and NHCompanions.species[r.species]
    local detail=tr("同行：","Companion: ")..(species and tr(species.zh,species.en) or tr("无","None"))
        .."\n"..tr("本次保金：","Gold kept: ")..string.format("%.0f",r.kept or 0)
        .."\n"..tr("保金上限：","Gold limit: ")..string.format("%.0f",r.limit or 0)
    GuiTooltip(gui,line,detail)
    GuiZSet(gui,-80)
end
local draw_fire_support=dofile("mods/noita_hideout/files/fire_support_hud.lua")
local mimicLabels={ready={"可拟态","Mimic ready"},unsupported={"未收录形态","Unsupported form"},boss={"首领不可拟态","Boss: cannot mimic"},friendly={"非敌对目标","Not hostile"},
    unstable={"形态不稳定 · 已禁用","Unstable form: disabled"},
    ammo={"弹药不足","Low ammo"},reload={"装填中","Reloading"},
    cooldown={"冷却中","Cooling down"},immune={"自身变形免疫","Polymorph immunity"}}
local function drawMimicTarget(target,sw,sh,tr)
    local cx,cy,cw,ch=GameGetCameraBounds()
    if cw<=0 or ch<=0 then return end
    local x,y=(target.x-cx)*sw/cw,(target.y-cy)*sh/ch
    if x<0 or x>sw or y<0 or y>sh then return end
    local label=tr(unpack(mimicLabels[target.status]))
    if target.substitute then
        local key="$animal_"..target.substitute
        local name=GameTextGetTranslatedOrNot(key)
        label=label..tr(" · 替代："," · Proxy: ")..(name and name~="" and name~=key and name or target.substitute)
    end
    local width,height=GuiGetTextDimensions(gui,label,0.85)
    if target.status=="ready" then tint(green) elseif target.form then tint(gold) else GuiColorSetForNextWidget(gui,1,0.55,0.5,1) end
    GuiText(gui,math.max(0,math.min(sw-width,x-width/2)),math.max(0,math.min(sh-height,y-height-7)),label,0.85)
end
local function draw_deployment(p,sw,sh)
    local d=turrets[p.kind]
    local icon=p.icon or (d and d.icon)
    if not icon then return end
    local cx,cy,cw,ch=GameGetCameraBounds()
    if cw<=0 or ch<=0 then return end
    local sx,sy=sw/cw,sh/ch
    local x,y=(p.x-cx)*sx,(p.y-cy)*sy
    if x<0 or x>sw or y<0 or y>sh then return end
    local color=p.valid and {0.25,1,0.4} or {1,0.25,0.25}
    local function rect(id,rx,ry,w,h,alpha)
        GuiColorSetForNextWidget(gui,color[1],color[2],color[3],1)
        GuiImage(gui,id,rx,ry,"data/ui_gfx/1px_white.png",alpha,w,h)
    end
    GuiZSet(gui,-70)
    local left,top,w,h=x-(p.offsetX or 10)*sx,y-(p.offsetY or 16)*sy,(p.width or 20)*sx,(p.height or 20)*sy
    rect(5830,left,top,w,h,0.16)
    rect(5831,left,top,w,sy,0.85)
    rect(5832,left,top,sx,h,0.85)
    rect(5833,left+w-sx,top,sx,h,0.85)
    rect(5834,left,top+h-sy,w,sy,0.85)
    local iw,ih=GuiGetImageDimensions(gui,icon)
    GuiColorSetForNextWidget(gui,color[1],color[2],color[3],1)
    if p.icon then
        local iconX=x-(p.iconOffsetX or p.offsetX or 10)*sx
        local iconY=y-(p.iconOffsetY or p.offsetY or 16)*sy
        GuiImage(gui,5835,iconX,iconY,icon,0.65,(p.iconWidth or p.width or 20)*sx/iw,(p.iconHeight or p.height or 20)*sy/ih)
    else
        GuiImage(gui,5835,x-8*sx,y-12*sy,icon,0.65,16*sx/iw,16*sy/ih)
    end
    GuiZSet(gui,-80)
end

function NHUI.draw(model, dispatch)
    last_inventory_layout=nil
    local at_home=model.open and model.near and model.mode=="case"
    if at_home and model.travel and model.travel.groups then
        if not travelSession then
            travelSession={folded=workshop_folded,expanded={[0]=true},frame=GameGetFrameNum()}
            workshop_folded=true
        end
        if travelSession.groups~=model.travel.groups then
            travelSession.groups,travelSession.entries=model.travel.groups,nil
        end
    elseif travelSession then
        workshop_folded,travelSession=travelSession.folded,nil
    end
    if at_home and not homeWasOpen then open_shop() end
    homeWasOpen=at_home
    if not model.open then drag,last_case_frame,salvage_target=nil,nil,nil end
    if not gui then
        dofile_once("data/scripts/lib/utilities.lua")
        gui = GuiCreate()
    end
    GuiStartFrame(gui)
    GuiZSet(gui, -80)

    local sw, sh = GuiGetScreenDimensions(gui)
    scrollMenu.begin()
    if model.terminals and #model.terminals>0 then
        local cx,cy,cw,ch=GameGetCameraBounds()
        if cw>0 and ch>0 then
            for _,v in ipairs(model.terminals) do
                local x,y=(v.x-cx)*sw/cw,(v.y-cy)*sh/ch
                if x>=0 and x<=sw and y>=0 and y<=sh then
                    GuiColorSetForNextWidget(gui,1,v.warning and 0.2 or 1,v.warning and 0.2 or 1,v.alpha)
                    GuiText(gui,x-GuiGetTextDimensions(gui,v.text,0.75)/2,y,v.text,0.75)
                end
            end
        end
    end
    local function tr(zh, en) return model.lang == "zh" and zh or en end
    if model.turretStatus then worldBars.drawTurret(gui,model.turretStatus,sw,sh,tr) end
    if model.mimicFrames then
        local seconds=math.ceil(model.mimicFrames/60)
        local caption=tr("拟态剩余 %d 秒","Mimic: %ds"):format(seconds)
        tint(seconds<=5 and gold or green)
        GuiText(gui,sw-10-GuiGetTextDimensions(gui,caption),62,caption)
        return
    end
    if model.fireSupport then draw_fire_support(gui,model.fireSupport,sw,sh,tr) end
    if model.travel and not model.travel.rows and not model.open then drawTravel(gui,model.travel,sw,sh,tr) end
    if model.katana and not model.open then
        local k=model.katana
        local d=NHKatanas.types[k.kind]
        local exhausted=d.durability and k.remaining==0
        local leftHint=d.chargeAttack=="stasis_dash" and tr("左键快斩 / 蓄力时停后松开冲刺","LMB slash / charge stasis, release dash")
            or d.chargeAttack=="dash" and tr("左键快斩 / 蓄满自动冲刺（5 备弹）","LMB slash / full charge: dash (5 ammo)")
            or tr("左键快斩 / 蓄满松开重击","LMB slash / charge, release heavy")
        -- Every quick click starts the same charge timer as a long hold. Keep
        -- its stable hint for the first 0.1 seconds instead of flashing 0%.
        local showCharge=k.charge and k.charge*(k.preparing and NHKatanas.zandatsu.chargeFrames or d.chargeFrames)>=6
        local preparing=k.preparing and (k.charge==nil or showCharge)
        local status=k.plunder and tr("斩夺 %.1f 秒","Blade Mode %.1fs"):format(k.plunder/60)
            or preparing and (exhausted and tr("耐久耗尽 · 左键技能仍可用","No durability · left skills available")
                or d.durability and tr("斩夺蓄势 · 1 耐久 / 30 秒","Preparing · 1 durability / 30s")
                or tr("斩夺蓄势 · 半格护盾","Preparing · half a shield cell"))
            or k.stasis and tr("时停 %.1f 秒 · 松开冲刺","Stasis %.1fs · release to dash"):format(k.stasis/60)
            or k.heavyReady and k.releaseDash and tr("蓄力完成 · 松开冲刺","Charged · release to dash")
            or k.heavyReady and tr("蓄力完成 · 松开重击","Charged · release")
            or showCharge and tr("蓄力 %d%%","Charging %d%%"):format(math.floor(k.charge*100))
            or leftHint
        local hint=k.plunder and (d.freeMovement and tr("自由移动 · 按住左键连斩 · 右键退出","Free movement · hold LMB slashes · RMB exits")
                or tr("移动 30% · 按住左键连斩 · 右键退出","30% movement · hold LMB slashes · RMB exits"))
            or exhausted and tr("右键斩夺不可用 · 左键免费","RMB unavailable · left skills free")
            or d.durability and tr("长按右键：1 耐久，斩夺 30 秒","Hold RMB: 1 durability, Blade Mode 30s")
            or tr("长按右键扣半格，每 5 点维持 1 秒","Hold RMB · half a cell · 1s per 5 points")
        local name=tr(d.zh,d.en)
        if k.remaining~=nil then name=name..tr(" · 耐久 %d/%d"," · Durability %d/%d"):format(k.remaining,d.durability) end
        tint(white)
        GuiText(gui,sw-10-GuiGetTextDimensions(gui,name),62,name)
        tint(k.plunder and green or gold)
        GuiText(gui,sw-10-GuiGetTextDimensions(gui,status),73,status)
        tint(muted)
        GuiText(gui,sw-10-GuiGetTextDimensions(gui,hint),84,hint)
    end
    if model.ammo then
        local a=model.ammo
        if a.mimicTarget then drawMimicTarget(a.mimicTarget,sw,sh,tr) end
        local mode=a.modes[a.index]
        local status
        if a.powered then
            status=tr("堆芯供弹","Reactor feed")
        elseif mode.costs then
            local level=a.charge or 0
            status=tr("蓄力 %d/%d · %d 点","Draw %d/%d · %d ammo"):format(level,#mode.costs-1,mode.costs[level+1])
            if mode.spells then status=tr(unpack(mode.spells[level+1])).." · "..status end
        elseif mode.cost==0 then
            status=a.charge and tr("蓄力 %d/3","Charge %d/3"):format(a.charge) or tr("无需弹药","No ammo needed")
        else status=tr("可射 %d 次","%d shots"):format(math.floor(a.rounds/mode.cost)) end
        local line=("%s  %d/%d  ·  %s"):format(tr(mode.zh,mode.en),a.rounds,a.max,status)
        tint(white)
        GuiText(gui,sw-10-GuiGetTextDimensions(gui,line),62,line)
        local hint=("[%s] %s"):format(a.keyName,tr("模式","Mode"))
        if a.loading then hint=tr("装填 %.1fs","Reload %.1fs"):format(a.loading/60)
        elseif not a.powered then hint=hint..tr("   [R] 换弹","   [R] Reload") end
        hint=hint..tr("  备弹 ","  Reserve ")..a.reserve
        tint(gold)
        GuiText(gui,sw-10-GuiGetTextDimensions(gui,hint),72,hint)
        if a.menu then
            local positions={{0,-28},{66,0},{0,28},{-66,0}}
            GuiZSetForNextWidget(gui,-80)
            GuiImageNinePiece(gui,7810,sw/2-114,sh/2-37,228,77,0.94)
            for index,entry in ipairs(a.modes) do
                local label=tr(entry.zh,entry.en)
                if not a.powered then label=label.." · "..(entry.costs and table.concat(entry.costs,"/") or entry.cost) end
                if index==a.hover then label="> "..label.." <" end
                GuiZSetForNextWidget(gui,-81)
                tint(index==a.hover and gold or index==a.index and green or white)
                GuiText(gui,sw/2+positions[index][1]-GuiGetTextDimensions(gui,label)/2,sh/2+positions[index][2]-3,label)
            end
            local center=tr("松开确认","Release")
            GuiZSetForNextWidget(gui,-81)
            tint(muted)
            GuiText(gui,(sw-GuiGetTextDimensions(gui,center))/2,sh/2-3,center)
        end
    end
    local shieldLabelRight=model.shield and draw_shield(model.shield,sw)
    if model.rescue then draw_rescue(model.rescue,sw,tr,shieldLabelRight) end
    if model.deployment and not model.open then draw_deployment(model.deployment,sw,sh) end
    draw_notices(sw,sh)
    if model.ewDeposit then
        local pending=model.ewDeposit
        local label=pending.canCancel and tr("正在入库","Deposit pending")
            or pending.phase=="return" and tr("请腾出一个栏位取回物品","Free a slot to retrieve the item")
            or pending.phase=="cancel" and tr("正在撤销入库","Cancelling deposit")
            or tr("正在核对入库记录","Checking deposit")
        local cancel=model.open and pending.canCancel and tr("取消入库","Cancel deposit")
        local width=GuiGetTextDimensions(gui,label)
        local cancelWidth=cancel and GuiGetTextDimensions(gui,cancel)+12 or 0
        local x,y=math.floor((sw-width-cancelWidth)/2),sh-27
        GuiZSetForNextWidget(gui,-9021)
        GuiImageNinePiece(gui,5810,x-4,y-2,width+cancelWidth+8,14,0.95)
        GuiZSetForNextWidget(gui,-9022)
        tint(gold)
        GuiText(gui,x,y,label)
        if cancel then
            GuiZSetForNextWidget(gui,-9022)
            if GuiButton(gui,5811,x+width+6,y,cancel) then dispatch("cancel_deposit",pending.tx) end
        end
    end
    if not model.open then
        if model.surgery then
            local w=88
            local x,y=math.floor((sw-w)/2),sh-25
            GuiZSetForNextWidget(gui,-79)
            GuiImageNinePiece(gui,1,x,y,w,19,0.96)
            draw_surgery(model.surgery,tr,x+5,y+1,w-10,1)
            return
        end
        if not model.near and not model.remote_linked then return end
        local caption = model.travel and model.travel.rows and tr("旅行终端 · 打开物品栏","Travel terminal · Open inventory")
            or model.landmarkName and tr(unpack(model.landmarkName))..tr(" · 打开物品栏"," · Open inventory")
            or model.remote_linked and tr("小型终端 · 打开物品栏","Small terminal · Open inventory")
            or model.at_station and tr("圣山存取点 · 打开物品栏","Hideout access · Open inventory")
            or tr("打开物品栏：仓库和工坊", "Open inventory for stash and workshop")
        local text_w = GuiGetTextDimensions(gui, caption)
        local x = math.floor((sw - text_w) / 2)
        local y = sh - 20
        GuiZSetForNextWidget(gui, -79)
        GuiImageNinePiece(gui, 1, x - 5, y - 2, text_w + 10, 15, 0.96)
        tint(gold)
        GuiText(gui, x, y, caption)
        return
    end

    local pw,ph=187,72
    local qw,qh=GuiGetImageDimensions(gui,tile)
    local popupHeight=0
    if model.popup then
        local capacity=model.walletId and model.walletCapacity or model.pouchCapacity
        popupHeight=61+math.floor((capacity-1)/4)*qh
    end
    local collapsed=model.mode=="case" and secure_folded
    if model.mode=="case" and model.gear then
        pw=16+case_columns*qw
        ph=equipment_grid_y+math.max(case_rows*qh,2*qh+27)+8
    elseif model.mode=="case" then
        local rows=math.min(case_rows,math.ceil(model.capacity/case_columns))
        ph=math.max(ph,25+rows*qh+24)+(model.gear and 16 or 0)
    end
    if collapsed then ph=20 end
    local secureHeight=ph
    if model.mode=="container" then
        ph=math.max(ph,popupHeight)
        secureHeight=ph
    elseif not collapsed then
        if model.popup then secureHeight=secureHeight+popupHeight+5 end
        secureHeight=secureHeight+NHPerks.panelSpace(model,qh)
    end
    local s=math.min(1,(sw-10)/(at_home and 310 or pw),(sh-10)/math.max(at_home and 173 or 0,secureHeight))
    if s<=0 then return end
    local layout
    if at_home then
        local content_height=qh+30+material_rows*11
        local function measure_home(scale)
            local panels=home_layout(sw,scale,qw)
            panels.tabs,panels.gridY=stash_tabs(panels.stash,scale,tr)
            panels.workTabs,panels.navEnd=position_work_tabs(work_tabs,18,panels.bench,scale,tr,model.debug)
            panels.contentHeight=content_height
            panels.panelHeight=math.max(panels.gridY,panels.navEnd)+content_height+18
            -- Wrapped navigation and the active order timer still leave room for list rows.
            local _,recipesEnd=position_work_tabs(recipe_tabs,panels.navEnd,panels.bench,scale,tr)
            local _,alchemyEnd=position_work_tabs(alchemy_tabs,recipesEnd,panels.bench,scale,tr)
            local _,shopEnd=position_work_tabs(shop_tabs,panels.navEnd+bankRowHeight,panels.bench,scale,tr)
            -- Extra alchemy tab rows can scroll within the workshop on short screens.
            local alchemyHeight=math.min(alchemyEnd+15+42,(sh-10)/scale)
            panels.panelHeight=math.max(panels.panelHeight,alchemyHeight,recipesEnd+70,shopEnd+55)
            return panels
        end
        layout=measure_home(s)
        local fit_scale=(sh-10)/layout.panelHeight
        if fit_scale<s then
            s=fit_scale
            layout=measure_home(s)
        end
        pw=math.min(pw,layout.secure)
    end
    if collapsed then pw=math.min(pw,90) end
    local ox,oy=model.mode=="case" and 5 or sw-pw*s-5,sh-ph*s-5
    GuiZSetForNextWidget(gui, -79)
    GuiImageNinePiece(gui, 10, ox, oy, pw*s, ph*s, 1)

    local function label(x, y, value, w, color)
        local txt, truncated = fit(value, w * s, s)
        tint(color or white)
        GuiText(gui, ox + x * s, oy + y * s, txt, s)
        if truncated then GuiTooltip(gui, tostring(value), "") end
    end
    if model.mode=="case" then
        local caption=(collapsed and "[+] " or "[-] ")..tr("装备栏","Equipment")
        if model.surgery and not collapsed then caption="[-]" end
        if GuiButton(gui,39,ox+6*s,oy+3*s,caption,s) and not drag then
            secure_folded=not secure_folded
        end
        if model.surgery and not collapsed then
            local width=pw-32
            draw_surgery(model.surgery,tr,ox+24*s,oy+4*s,width*s,s)
        end
    end
    draw_case(model,ox,oy,s,sw,sh,tr,label,dispatch,layout,pw,ph,popupHeight,collapsed)
end
