NHNative = {}

local item_path = "mods/noita_hideout/files/items/"
local tag = {pouch = "noita_hideout_pouch", dose = "noita_hideout_dose"}
NHNative.icons = {pouch = item_path .. "pouch.png", dose = item_path .. "dose.png"}

-- Noita picks translated item names for ground prompts, inventory slots and held abilities.
function NHNative.registerTranslations()
    local path = "data/translations/common.csv"
    local original = ModTextFileGetContent(path)
    if not original then return end
    local labels = {
        {"nh_hideout_medkit","Medkit","医疗包"},
        {"nh_hideout_medkit_desc","Three uses. Each use restores up to 10 HP.","可使用三次，每次最多恢复 10 点生命。"},
        {"nh_hideout_bandage","Bandage","绷带"},
        {"nh_hideout_bandage_desc","Single use. Restores up to 5 HP.","单次使用，最多恢复 5 点生命。"},
        {"nh_hideout_bread","Bread","面包"},
        {"nh_hideout_bread_desc","Restores 1 HP every 4 seconds for 120 seconds. Eating again refreshes the duration.","每 4 秒恢复 1 点生命，持续 120 秒。再次食用刷新时长。"},
        {"nh_hideout_sugar_cube","Sugar cube","糖块"},
        {"nh_hideout_sugar_cube_desc","Increases movement speed for 120 seconds. Eating again refreshes the duration.","提高行动速度，持续 120 秒。再次食用刷新时长。"},
        {"nh_hideout_grenade","Magic grenade","魔法手雷"},
        {"nh_hideout_grenade_desc","Use once to throw a magic grenade.","向瞄准方向投出一枚魔法手雷，使用一次后消耗。"},
        {"nh_hideout_pouch", "Injector pouch", "针剂包"},
        {"nh_hideout_pouch_desc", "Use to open the pouch. Drag injectors into or out of it.", "手持使用可打开针剂包。拖动针剂即可存入或取出。"},
        {"nh_hideout_dose", "Fire immunity injector", "耐火激活剂"},
        {"nh_hideout_dose_desc", "Three uses. Each injection grants one minute of fire immunity.", "每支可使用三次。每次注射获得约一分钟的火焰免疫。"},
    }
    local rows = {}
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

function NHNative.spawn(kind, x, y)
    if not tag[kind] then return nil, "Unknown hideout item." end
    local item = EntityLoad(item_path .. kind .. ".xml", x, y)
    if not item or item == 0 then return nil, "Could not create " .. kind .. "." end
    if NHNative.kind(item) ~= kind or not EntityGetFirstComponentIncludingDisabled(item, "ItemComponent") then
        EntityKill(item)
        return nil, "Invalid hideout item template: " .. kind
    end
    return item
end

local last_player, was_down, after_panel

function NHNative.resetInput()
    last_player, was_down, after_panel = nil, false, false
end

-- Read Noita's bound primary action, including gamepad and remapped buttons.
-- The caller polls all player frames, including open inventories and menus.
function NHNative.pressed(player, blocked)
    local controls = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
    if not controls then return false end
    local down = ComponentGetValue2(controls, "mButtonDownFire")
    if player ~= last_player then
        last_player, was_down, after_panel = player, down, blocked
        return false
    end
    local fresh = down and not was_down
    was_down = down
    if blocked then
        after_panel = true
        return false
    end
    if not fresh then return false end
    if after_panel then
        -- UI suppression of gameplay input can produce a false rising edge when a
        -- menu closes. An actual new press has a current engine input timestamp.
        local stamp = ComponentGetValue2(controls, "mButtonFrameFire")
        if math.abs(stamp - GameGetFrameNum()) > 1 then return false end
        after_panel = false
    end
    return true
end
