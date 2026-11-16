NHNative = {}

local item_path = "mods/noita_hideout/files/items/"
local injectors=NHInjectors or dofile("mods/noita_hideout/files/injectors.lua")
local medkits=NHMedkits or dofile("mods/noita_hideout/files/medkits.lua")
local surgery_kits=NHSurgeryKits or dofile("mods/noita_hideout/files/surgery_kits.lua")
local throwables=NHThrowables or dofile("mods/noita_hideout/files/throwables.lua")
local tag = {pouch = "noita_hideout_pouch", dose = "noita_hideout_dose"}
NHNative.icons = {pouch = item_path .. "pouch.png", dose = item_path .. "dose.png"}

-- Noita picks translated item names for ground prompts, inventory slots and held abilities.
function NHNative.registerTranslations()
    local path = "data/translations/common.csv"
    local original = ModTextFileGetContent(path)
    if not original then return end
    local labels = {
        {"nh_hideout_card_wallet","Card wallet","卡片夹"},
        {"nh_hideout_card_wallet_desc","Right-click to open the four-slot card wallet. Matching full-charge cards stack.","右键打开四格卡片夹。同种满耐久召唤卡可以叠放。"},
        {"nh_card_dryad","Dryad summon card","树精召唤卡"},
        {"nh_card_flower_fairy","Flower fairy summon card","花妖召唤卡"},
        {"nh_card_minotaur","Minotaur maiden summon card","米诺陶少女召唤卡"},
        {"nh_card_griffin","Griffin maiden summon card","狮鹫少女召唤卡"},
        {"nh_card_bee","Bee maiden summon card","蜂娘召唤卡"},
        {"nh_card_dragon","Dragon maiden summon card","龙娘召唤卡"},
        {"nh_card_slime","Gel maiden summon card","凝胶少女召唤卡"},
        {"nh_card_dryad_desc","Call the dryad for 3 minutes. She protects against toxic sludge and may give bread. Higher affinity adds healing.","召唤树精接替当前伙伴，随行 3 分钟。树精提供毒泥免疫，途中可能赠送面包。好感度提高后还能恢复生命。"},
        {"nh_card_flower_fairy_desc","Call the flower fairy for 3 minutes. She restores 1 HP every 5 seconds and may give bandages. Higher affinity speeds up healing.","召唤花妖接替当前伙伴，随行 3 分钟。花妖起初每 5 秒恢复 1 HP，途中可能赠送绷带。好感度越高，治疗越频繁。"},
        {"nh_card_minotaur_desc","Call the minotaur maiden for 3 minutes. She grants melee immunity and may give bandages. Higher affinity adds a projectile shield.","召唤米诺陶少女接替当前伙伴，随行 3 分钟。她提供近战免疫，途中可能赠送绷带。好感度提高后额外提供飞弹护盾。"},
        {"nh_card_griffin_desc","Call the griffin maiden for 3 minutes. She speeds up levitation and may give sugar cubes. Higher affinity also restores flight fuel.","召唤狮鹫少女接替当前伙伴，随行 3 分钟。她提高飞行上升速度，途中可能赠送糖块。好感度提高后还能恢复飞行能量。"},
        {"nh_card_bee_desc","Call the bee maiden for 3 minutes. She speeds up movement and may give sugar cubes. Higher affinity restores flight fuel.","召唤蜂娘接替当前伙伴，随行 3 分钟。她提高移动速度，途中可能赠送糖块。好感度提高后还能恢复飞行能量。"},
        {"nh_card_dragon_desc","Call the dragon maiden for 3 minutes. She grants fire immunity and may give magic grenades. Higher affinity adds a projectile shield.","召唤龙娘接替当前伙伴，随行 3 分钟。她提供火焰免疫，途中可能赠送魔法手雷。好感度提高后额外提供飞弹护盾。"},
        {"nh_card_slime_desc","Call the gel maiden for 3 minutes. She grants underwater breathing and may give bandages. Higher affinity adds healing.","召唤凝胶少女接替当前伙伴，随行 3 分钟。她提供水下呼吸，途中可能赠送绷带。好感度提高后还会定期恢复生命。"},
        {"nh_companion_gift","Your companion left you a gift:","伙伴送出了礼物："},
        {"nh_hideout_bandage","Bandage","绷带"},
        {"nh_hideout_bandage_desc","Each roll restores up to 5 HP. The counter shows rolls left.","每卷最多恢复 5 点生命，数字为剩余卷数。"},
        {"nh_hideout_food_regen","Food regeneration","食物再生"},
        {"nh_hideout_food_regen_desc","Restores 1 HP every 4 seconds.","每 4 秒恢复 1 点生命。"},
        {"nh_hideout_pouch", "Injector pouch", "针剂包"},
        {"nh_hideout_pouch_desc", "Right-click to open the injector pouch. Drag injectors into or out of it.", "右键打开针剂包。拖动针剂即可存入或取出。"},
    }
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
        labels[#labels+1]={key.."_desc","Three uses. Each grants "..d.enEffect..".","每支可使用三次。每针效果："..d.zhEffect.."。"}
    end
    local rows = {}
    for _,food in ipairs(dofile("mods/noita_hideout/files/cooking.lua")) do
        labels[#labels+1]={"nh_hideout_"..food.id,food.en,food.zh}
        labels[#labels+1]={"nh_hideout_"..food.id.."_desc",food.noteEn,food.noteZh}
    end
    for _, label in ipairs(labels) do
        -- common.csv columns: key, en, ru, pt-br, es-es, de, fr-fr, it, pl, zh-cn, jp, ko
        local en = label[2]
        if not original:find("\n"..label[1]..",",1,true) then
            rows[#rows+1] = table.concat({label[1], en, en, en, en, en, en, en, en, label[3], en, en}, ",")
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
        held_usable=held and NHNative.usableKind(NHNative.kind(held) or NHTransfers.item_kind(held))
    end
    local leftMouse=InputIsMouseButtonDown(1)
    local rightMouse=InputIsMouseButtonDown(2)
    local primary=leftMouse or ComponentGetValue2(controls,"mButtonDownFire")
    local secondary=rightMouse or (not leftMouse and ComponentGetValue2(controls,"mButtonDownThrow"))
    local target
    if menuOpen then
        if menuTarget and NHNative.usableKind(menuTarget.kind) then target=menuTarget end
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
