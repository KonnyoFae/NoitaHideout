NHNative = {}

local item_path = "mods/noita_hideout/files/items/"
local tag = {pouch = "noita_hideout_pouch", dose = "noita_hideout_dose"}
NHNative.icons = {pouch = item_path .. "pouch.png", dose = item_path .. "dose.png"}

-- Noita picks translated item names for ground prompts, inventory slots and held abilities.
function NHNative.registerTranslations()
    local path = "data/translations/common.csv"
    local original = ModTextFileGetContent(path)
    if not original or original:find("\nnh_hideout_pouch,", 1, true) then return end
    local labels = {
        {"nh_hideout_pouch", "Injector pouch", "针剂包"},
        {"nh_hideout_pouch_desc", "Use to take one injector. Store the pouch in the secure case.", "手持使用可取一支针剂。可将整包放回安全箱。"},
        {"nh_hideout_dose", "Fire immunity injector", "耐火激活剂"},
        {"nh_hideout_dose_desc", "Hold and use to inject. Grants fire immunity for one minute.", "手持时点击注射。获得约一分钟的火焰免疫。"},
    }
    local rows = {}
    for _, label in ipairs(labels) do
        -- common.csv columns: key, en, ru, pt-br, es-es, de, fr-fr, it, pl, zh-cn, jp, ko
        local en = label[2]
        rows[#rows+1] = table.concat({label[1], en, en, en, en, en, en, en, en, label[3], en, en}, ",")
    end
    ModTextFileSetContent(path, original:gsub("[\r\n]+$", "") .. "\n" .. table.concat(rows, "\n") .. "\n")
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
