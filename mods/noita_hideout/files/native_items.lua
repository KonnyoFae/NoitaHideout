NHNative = {}

local item_path = "mods/noita_hideout/files/items/"
local equipment=NHEquipment or dofile("mods/noita_hideout/files/equipment.lua")
local injectors=NHInjectors or dofile("mods/noita_hideout/files/injectors.lua")
local medkits=NHMedkits or dofile("mods/noita_hideout/files/medkits.lua")
local surgery_kits=NHSurgeryKits or dofile("mods/noita_hideout/files/surgery_kits.lua")
local throwables=NHThrowables or dofile("mods/noita_hideout/files/throwables.lua")
local tag = {pouch = "noita_hideout_pouch", dose = "noita_hideout_dose"}
NHNative.icons = {pouch = item_path .. "pouch.png", dose = item_path .. "dose.png"}

function NHNative.refreshArt(entity,item,icon)
    ComponentSetValue2(item,"ui_sprite",icon)
    local sprite=EntityGetFirstComponentIncludingDisabled(entity,"SpriteComponent","enabled_in_hand")
    if sprite then
        ComponentSetValue2(sprite,"image_file",icon)
        EntityRefreshSprite(entity,sprite)
    end
    local shape=EntityGetFirstComponentIncludingDisabled(entity,"PhysicsImageShapeComponent")
    if shape then ComponentSetValue2(shape,"image_file",icon) end
    return icon
end

-- Serialized world and inventory entities keep their old component paths.
function NHNative.refreshLinkArt()
    for tier=2,#equipment.linkOrder do
        local kind=equipment.linkOrder[tier]
        for _,id in ipairs(EntityGetWithTag("noita_hideout_"..kind) or {}) do
            local item=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
            if item and ComponentGetValue2(item,"ui_sprite")==equipment.links.remote_terminal.icon then
                NHNative.refreshArt(id,item,equipment.links[kind].icon)
            end
        end
    end
end

function NHNative.language()
    local locale = GameTextGet("$nh_hideout_locale")
    if locale == "zh" or locale == "en" then return locale end
    local name = GameTextGet("$current_language")
    return (name == "简体中文" or name == "完全汉化") and "zh" or "en"
end

local function csvField(text)
    if text:find('[,"\r\n]') then return '"' .. text:gsub('"', '""') .. '"' end
    return text
end

-- Noita picks translated item names for ground prompts, inventory slots and held abilities.
function NHNative.registerTranslations()
    local path = "data/translations/common.csv"
    local original = ModTextFileGetContent(path)
    if not original then return end
    local labels = {
        {"nh_hideout_locale","en","zh"},
        {"nh_hideout_reactor_critical","Core critical · The next hit causes a meltdown","堆芯临界 · 再次受伤将熔解"},
        {"nh_hideout_reactor_direct","Core Direct Feed","堆芯直通"},
        {"nh_hideout_ew_await_pod","A living teammate can call reinforcements with a data link and 5 supply packs.","等待存活队友通过数据链呼叫增援（5 点补给）。"},
        {"nh_hideout_ew_no_sponsor","Reinforcement canceled. No online teammate could cover the 5 supply packs. A teammate can call again.","增援已取消：在线队员的补给均不足 5 点。队友补足资源后可以重新呼叫。"},
        {"nh_hideout_ew_redirect_pod","No clear revival space. A living teammate can move into the open and call again to redirect the same pod for free.","死亡地点附近没有可用空间。存活队友可移到空处，再次呼叫以免费改投这一舱。"},
        {"nh_hideout_ew_wait_failed","Could not enter spectator mode safely. Your character and equipment were kept.","无法安全进入观战，已保留角色和装备。"},
        {"nh_hideout_ew_wait_carrying_peer","Put down the teammate polymorphed into an item before entering spectator mode.","请先放下已变形成物品的队友，再进入观战。"},
        {"nh_storm_sites_confirmed","Incoming storm facilities","风暴设施信号已确认"},
        {"nh_storm_sites_pending_both","Look for oil rigs in the desert and a gas tower in the snowy wasteland.","前往地表沙漠接应油钻，前往落雪荒原接应气塔。"},
        {"nh_storm_sites_pending_well","Look for a gas tower in the snowy wasteland.","前往落雪荒原接应气塔。"},
        {"nh_storm_rigs_arrive","The wind carries a scent of oil…","风里飘来一丝油味……"},
        {"nh_storm_rigs_arrive_desc","A cluster of oil rigs awaits activation in the desert.","一组油钻已在沙漠就位，等待启动。"},
        {"nh_storm_tower_arrives","A hiss breaks the silence of the snow…","风雪中传来一阵嘶鸣……"},
        {"nh_storm_tower_arrives_desc","A gas tower is crystallizing mana in the snowy wasteland.","落雪荒原上的炼气塔已开始凝结法力。"},
        {"nh_storm_ship_arrives","An anchor chain rattles in the wind…","风里传来了锚链的响声……"},
        {"nh_storm_ship_desc","A Hiisi transport is moored above the surface.","一艘嘻嘻运输艇已在地表抛锚。"},
        {"nh_storm_steel_fleet_desc","Two tenders mark the climb to a steel airship overhead.","两艘小艇在空中接应，钢铁飞艇正停泊在它们上方。"},
        {"nh_ship_safe","Cargo safe","运输艇保险柜"},
        {"nh_ship_safe_open","Open cargo safe","打开运输艇保险柜"},
        {"nh_ship_cache","Hold supplies","货舱补给箱"},
        {"nh_ship_cache_open","Open hold supplies","打开货舱补给箱"},
        {"nh_travel_console","Travel terminal","旅行终端"},
        {"nh_travel_open_inventory","Open inventory to choose a destination.","打开物品栏选择传送目的地。"},
        {"nh_support_disabled_aboard","Remote support is disabled aboard the mothership.","母舰上已禁用远程支援。"},
        {"nh_reinforcement_mg_turret","Machine Gun Turret","机枪塔"},
        {"nh_reinforcement_chaingun_turret","Chaingun Turret","链炮塔"},
        {"nh_reinforcement_missile_turret","Salvo Missile Turret","连发导弹塔"},
        {"nh_decoy_kick","Decoy kick","诱饵踢击"},
        {"nh_travel_unlocked","Holy Mountain terminal linked to the mothership.","圣山终端已接入母舰航线。"},
        {"nh_travel_snowcliff_unlocked","Frozen Vault · East Cliff linked to the mothership.","冻结避难所东崖已接入母舰航线。"},
        {"nh_travel_pyramid_unlocked","Pyramid · West Foot linked to the mothership.","金字塔西麓已接入母舰航线。"},
        {"nh_travel_gate_ready","Portal ready. Step inside to travel.","传送门已开启，走入即可通行。"},
        {"nh_travel_blocked","Landing unavailable. Check the departure point.","落点不可用，请在出发处重试。"},
        {"nh_travel_ew_occupied","Cabin terrain or objects remain here. Move them or visit after a storm repair.","此处仍有舱体地形或物件，已保留现场。请移开物件或在风暴维修后再来。"},
        {"nh_travel_rescue_fallback","Mothership unavailable. Diverting to the mines entrance.","母舰暂时无法接收，救援改送矿井入口。"},
        {"nh_storm_scan_empty","No high-value sites within 2048 px. Intel retained.","2048 像素内未发现可用的高价值地点。本次未消耗情报包。"},
        {"nh_hideout_relic_chain","Relic chain","遗物链"},
        {"nh_hideout_relic_chain_desc","Open in the secure case to socket relics.","放入安全箱后打开，装入遗物即可持续生效。"},
        {"nh_card_cat","Cat maiden","猫娘"},
        {"nh_card_dog","Hound maiden","犬娘"},
        {"nh_card_dryad","Dryad summon card","树精召唤卡"},
        {"nh_card_flower_fairy","Flower fairy summon card","花妖召唤卡"},
        {"nh_card_minotaur","Minotaur maiden summon card","米诺陶少女召唤卡"},
        {"nh_card_griffin","Griffin maiden summon card","狮鹫少女召唤卡"},
        {"nh_card_bee","Bee maiden summon card","蜂娘召唤卡"},
        {"nh_card_dragon","Dragon maiden summon card","龙娘召唤卡"},
        {"nh_card_slime","Gel maiden summon card","凝胶少女召唤卡"},
        {"nh_turret_no_ground","Needs clear ground nearby. Deployment pack was not consumed.","附近需要空旷地面，未消耗部署包。"},
        {"nh_lost_gold_case","Lost gold cache","遗落金匣"},
        {"nh_lost_gold","Recovered gold","遗落黄金"},
        {"nh_companion_field","Companion damage field","同伴伤害领域"},
        {"nh_hideout_meal_grain","Grain regeneration","粮食再生"},
        {"nh_hideout_meal_sugar","Sugar regeneration","糖分快速再生"},
        {"nh_hideout_meal_egg","Egg resistance","蛋类减伤"},
        {"nh_hideout_meal_meat","Meat resistance","肉类减伤"},
        {"nh_hideout_meal_speed","Sugar haste","糖分加速"},
        {"nh_hideout_meal_spice","Spiced flight and mana","香料飞行与回魔"},
        {"nh_hideout_food_regen","Food regeneration","食物再生"},
        {"nh_hideout_food_regen_desc","Restores 1% of max HP every 4 seconds.","每 4 秒恢复最大生命的 1%。"},
    }
    for _,def in ipairs(dofile("mods/noita_hideout/files/red_collectibles.lua")) do
        if not def.katana then
            labels[#labels+1]={"nh_hideout_"..def.id,def.en,def.zh}
            labels[#labels+1]={"nh_hideout_"..def.id.."_desc",def.noteEn,def.noteZh}
        end
    end
    local companions=NHCompanions
    if not companions then dofile("mods/noita_hideout/files/companions.lua"); companions=NHCompanions end
    local roleDescriptions={
        flight={"Boosts ascent and restores flight fuel.","提高飞行上升速度并恢复浮空能量。"},
        melee={"Grants a damage field, melee resistance and knockback immunity.","提供伤害领域、近战减伤与防击退。"},
        support={"Restores health and mana and increases movement speed.","持续恢复生命、汇聚法力并提高行动速度。"},
    }
    for _,id in ipairs(companions.order) do
        local spec=companions.species[id]
        local text=roleDescriptions[spec.role]
        local minutes=companions.giftMinutes(spec)
        local immunity=companions.immunities.types[id]
        labels[#labels+1]={"nh_card_"..id.."_desc","Summon for 15 minutes. "..spec.combatEn..". "..immunity.en..". "..text[1].." A gift box every "..minutes.." minutes.",
            "随行 15 分钟。"..spec.combatZh.."。"..immunity.zh.."。"..text[2].."每 "..minutes.." 分钟赠送一件礼物盒。"}
    end
    local firearms=NHFirearms or dofile("mods/noita_hideout/files/firearms.lua")
    for _,kind in ipairs(firearms.order) do
        local d=firearms.items[kind]
        labels[#labels+1]={"nh_hideout_"..kind,d.en,d.zh}
        labels[#labels+1]={"nh_hideout_"..kind.."_desc",d.noteEn,d.noteZh}
    end
    local katanas=NHKatanas or dofile("mods/noita_hideout/files/katanas.lua")
    for _,kind in ipairs(katanas.order) do
        local d=katanas.types[kind]
        labels[#labels+1]={"nh_hideout_"..kind,d.en,d.zh}
        labels[#labels+1]={"nh_hideout_"..kind.."_desc",d.noteEn,d.noteZh}
    end
    for _,d in ipairs(firearms.mods.order) do
        local zh,en=firearms.mods.description(d)
        labels[#labels+1]={d.name:sub(2),d.en,d.zh}
        labels[#labels+1]={d.name:sub(2).."_desc",en,zh}
    end
    local tarot=NHTarot or dofile("mods/noita_hideout/files/tarot.lua")
    for _,id in ipairs(tarot.order) do
        local d=tarot.types[id]
        labels[#labels+1]={"nh_card_"..id,d.en.." tarot card",d.zh.."塔罗牌"}
        labels[#labels+1]={"nh_card_"..id.."_desc",d.noteEn,d.noteZh}
    end
    for _,kind in ipairs({"data_link",unpack(equipment.linkOrder)}) do
        local link=equipment.links[kind]
        labels[#labels+1]={"nh_hideout_"..kind,link.en,link.zh}
        labels[#labels+1]={"nh_hideout_"..kind.."_desc",link.noteEn,link.noteZh}
    end
    local shields=NHShields or dofile("mods/noita_hideout/files/shields.lua")
    for _,kind in ipairs(shields.order) do
        local d=shields.types[kind]
        local r=shields.recipe(d)
        labels[#labels+1]={"nh_hideout_"..kind,d.en,d.zh}
        labels[#labels+1]={"nh_hideout_"..kind.."_desc",r.noteEn,r.noteZh}
    end
    for _,kind in ipairs(shields.chargerOrder) do
        local d=shields.chargers[kind]
        labels[#labels+1]={"nh_hideout_"..kind,d.en,d.zh}
        labels[#labels+1]={"nh_hideout_"..kind.."_desc",d.noteEn,d.noteZh}
    end
    for _,kind in ipairs({"pouch","card_wallet"}) do
        for _,d in ipairs(equipment[kind]) do
            local key=d.name:sub(2)
            labels[#labels+1]={key,d.en,d.zh}
            local zh=kind=="pouch" and " 个针剂格。同种满耐久针剂可以叠放。" or " 个卡片格。同种满耐久召唤卡可以叠放。"
            local en=kind=="pouch" and " injector slots. Matching full syringes stack." or " card slots. Matching full-charge cards stack."
            labels[#labels+1]={key.."_desc","Right-click to open. "..d.capacity..en,"右键打开，内有 "..d.capacity..zh}
        end
    end
    for _,catalog in ipairs({medkits,surgery_kits,throwables}) do
        for _,id in ipairs(catalog.order) do
            local definition=catalog.types[id]
            local key="nh_hideout_"..id
            labels[#labels+1]={key,definition.en,definition.zh}
            labels[#labels+1]={key.."_desc",definition.noteEn,definition.noteZh}
        end
    end
    for _,id in ipairs(injectors.order) do
        local d=injectors.get(id)
        local key="nh_hideout_"..d.filename
        labels[#labels+1]={key,d.en,d.zh}
        labels[#labels+1]={key.."_desc","Five uses. Each grants "..d.enEffect..".","每支可使用五次。每针效果："..d.zhEffect.."。"}
    end
    local bags=NHLootBags or dofile("mods/noita_hideout/files/loot_bags.lua")
    for id,bag in pairs(bags.types) do
        labels[#labels+1]={"nh_hideout_"..id,bag.en,bag.zh}
        if bag.guaranteedPack then
            local pack=bags.types[bag.guaranteedPack]
            labels[#labels+1]={"nh_hideout_"..id.."_desc",
                ("Right-click for one %s plus one bonus item. Food %d%% / relic %d%% / tarot %d%%."):format(pack.en,bag.food,bag.relic,bag.tarot),
                ("右键开启，必得一个%s。另得一件奖励，食品 %d%% / 遗物 %d%% / 塔罗牌 %d%%。"):format(pack.zh,bag.food,bag.relic,bag.tarot)}
        elseif bag.loot then
            local tableName=bags.types[bag.loot]
            labels[#labels+1]={"nh_hideout_"..id.."_desc","Right-click to refill shield and rig. Drops a charger and ammo box plus "..tableName.en.." loot.",
                "右键补满护盾和弹挂，获得充能器、弹药盒及"..tableName.zh.."的随机掉落。"}
        else
            local c=bag.chances
            labels[#labels+1]={"nh_hideout_"..id.."_desc",
                ("Right-click for %d gold and one supply. Food %d%% / medical %d%% / tool %d%% / injector %d%%. Extra tarot %d%% / companion %d%%."):format(
                    bag.gold*10,c.food,c.medical,c.tool,c.dose,bag.tarot,bag.card),
                ("右键开启，获得 %d 金和一件补给。食物 %d%% / 医疗 %d%% / 工具 %d%% / 针剂 %d%%。额外塔罗 %d%% / 同伴卡 %d%%。"):format(
                    bag.gold*10,c.food,c.medical,c.tool,c.dose,bag.tarot,bag.card)}
        end
    end
    local turrets=NHTurrets or dofile("mods/noita_hideout/files/turrets.lua")
    for id,d in pairs(turrets.types) do
        labels[#labels+1]={"nh_hideout_"..id,d.en,d.zh}
        labels[#labels+1]={"nh_hideout_"..id.."_desc",d.noteEn,d.noteZh}
    end
    local guns=NHGuns or dofile("mods/noita_hideout/files/guns.lua")
    for id,g in pairs(guns.types) do
        labels[#labels+1]={"nh_hideout_"..id,g.en,g.zh}
        labels[#labels+1]={"nh_hideout_"..id.."_desc",g.noteEn,g.noteZh}
    end
    local rows = {}
    for _,food in ipairs(dofile("mods/noita_hideout/files/cooking.lua")) do
        labels[#labels+1]={"nh_hideout_"..food.id,food.en,food.zh}
        labels[#labels+1]={"nh_hideout_"..food.id.."_desc",food.noteEn,food.noteZh}
    end
    for _, label in ipairs(labels) do
        -- common.csv columns: key, en, ru, pt-br, es-es, de, fr-fr, it, pl, zh-cn, jp, ko
        if not original:find("\n"..label[1]..",",1,true) then
            local en = csvField(label[2])
            -- Noita reads the last language field only when followed by a comma.
            rows[#rows+1] = table.concat({label[1], en, en, en, en, en, en, en, en, csvField(label[3]), en, en, ""}, ",")
        end
    end
    if #rows>0 then
        ModTextFileSetContent(path, original:gsub("[\r\n]+$", "") .. "\n" .. table.concat(rows, "\n") .. "\n")
    end
end

function NHNative.kind(entity)
    if not entity or entity == 0 then return nil end
    if EntityHasTag(entity, tag.pouch) then return "pouch" end
    if EntityHasTag(entity, tag.dose) then return "dose" end
end

function NHNative.held(player)
    local inventory = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    local item = inventory and ComponentGetValue2(inventory, "mActiveItem")
    if item and item ~= 0 and EntityGetIsAlive(item) and EntityGetRootEntity(item) == player then
        return item
    end
end

function NHNative.spawn(kind, x, y, subtype)
    if not tag[kind] then return nil, "Unknown hideout item." end
    local filename=kind
    if kind=="dose" then
        local dose=injectors.get(subtype)
        if not dose then return nil,"Unknown hideout item." end
        filename=dose.filename
    elseif kind=="pouch" then
        local pouch=equipment.get(kind,subtype)
        if not pouch then return nil,"Unknown hideout item." end
        filename=pouch.filename
    end
    local item = EntityLoad(item_path .. filename .. ".xml", x, y)
    if not item or item == 0 then return nil, "Could not create " .. kind .. "." end
    if NHNative.kind(item) ~= kind or not EntityGetFirstComponentIncludingDisabled(item, "ItemComponent") then
        EntityKill(item)
        return nil, "Invalid hideout item template: " .. kind
    end
    return item
end

function NHNative.usableKind(kind)
    return kind~=nil and (kind=="pouch" or kind=="card_wallet" or NHInventoryUse.supports(kind))
end

function NHNative.heldUseSlot(player,entity)
    local parent=EntityGetParent(entity)
    if not parent or parent==0 or EntityGetName(parent)~="inventory_quick" then return end
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    if not item then return end
    local x,y=ComponentGetValue2(item,"inventory_slot")
    return {container="held",owner=player,entity=entity,parent=parent,lane="tool",xslot=x,yslot=y}
end

-- The native inventory can queue a throw or drop the item between the world
-- callbacks. Restore only the entity and slot identified at the initial click.
function NHNative.recoverUseSlot(player,slot,place)
    if slot.owner and slot.owner~=player then return false end
    local id=slot.entity
    if not id or id==0 then return false end
    local inventory=EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    if inventory and ComponentGetValue2(inventory,"mThrowItem")==id then ComponentSetValue2(inventory,"mThrowItem",0) end
    return EntityGetIsAlive(id) and EntityGetRootEntity(id)==id and place(player,id,slot)
end

local last_player,last_menu,right_down,last_right_mouse,right_claimed,left_claimed
local last_item,held_usable
function NHNative.resetInput()
    last_player,last_menu,last_item=nil,nil,nil
    right_down,last_right_mouse,right_claimed,left_claimed,held_usable=false,false,false,false,false
end

local function suppress(controls,action)
    ComponentSetValue2(controls,"mButtonDown"..action,false)
    ComponentSetValue2(controls,"mButtonFrame"..action,-1)
end

-- Run before the native inventory and shooter update. The raw mouse state
-- survives suppression of the bound actions. The caller rechecks this exact
-- entity or UI slot after the simulation before applying an effect.
function NHNative.prepareRightUse(player,menuOpen,menuTarget)
    if not player then NHNative.resetInput(); return end
    local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    if not controls then NHNative.resetInput(); return end
    local newPlayer=last_player~=player
    if newPlayer then NHNative.resetInput() end
    local held=NHNative.held(player)
    if held~=last_item then
        last_item=held
        -- Collectibles use their bound Fire action in hand; only the menu
        -- claims a right-click on them.
        held_usable=held and not EntityHasTag(held,"nh_red_relic")
            and NHNative.usableKind(NHNative.kind(held) or NHTransfers.item_kind(held))
    end
    local leftMouse=InputIsMouseButtonDown(1)
    local rightMouse=InputIsMouseButtonDown(2)
    local primary=leftMouse or ComponentGetValue2(controls,"mButtonDownFire")
    local secondary=rightMouse or (not leftMouse and ComponentGetValue2(controls,"mButtonDownThrow"))
    local target
    if menuOpen then
        if menuTarget and (NHNative.usableKind(menuTarget.kind) or (menuTarget.container=="safe" and menuTarget.kind=="relic_chain")) then target=menuTarget end
    elseif held_usable then target=held end
    -- A physical release/press can arrive before the engine clears the mapped
    -- Throw field. The mouse edge still represents a distinct click.
    local fresh=secondary and (not right_down or (rightMouse and not last_right_mouse))
    -- Refuse a carried-over edge when a submenu closes while a button is held.
    -- For a remapped Throw action, its stamp distinguishes a press from the
    -- engine re-populating a held ControlsComponent field we just cleared.
    if fresh and not rightMouse then
        local stamp=ComponentGetValue2(controls,"mButtonFrameThrow")
        fresh=type(stamp)=="number" and math.abs(stamp-GameGetFrameNum())<=1
    end
    local menuOpening=menuOpen and not last_menu
    if not secondary then right_claimed=false
    elseif (not menuOpen and held_usable) or (fresh and (target or menuOpening)) then right_claimed=true end
    if not primary then left_claimed=false
    elseif (not menuOpen and held_usable) or (right_claimed and not leftMouse) then left_claimed=true end
    if left_claimed then
        suppress(controls,"Fire")
        ComponentSetValue2(controls,"mButtonLastFrameFire",-1)
        ComponentSetValue2(controls,"mButtonDownDelayLineFire",0)
        if not menuOpen then suppress(controls,"LeftClick") end
    end
    if right_claimed then suppress(controls,"RightClick") end
    if right_claimed or (left_claimed and not menuOpen) then
        suppress(controls,"Throw")
        suppress(controls,"Fire2")
        ComponentSetValue2(controls,"mButtonDownDelayLineThrow",0)
        ComponentSetValue2(controls,"mButtonDownDelayLineFire2",0)
    end
    last_player,last_menu,right_down,last_right_mouse=player,menuOpen,secondary,rightMouse
    if fresh and not newPlayer and not menuOpening then return target end
end
