local root = "mods/noita_hideout/files/"
local M = {paths = {
    tarot_moon = {root .. "tarot_tactics_moon.xml"},
    tarot_magician = {"data/entities/misc/effect_edit_wands_everywhere.xml"},
}}

-- One workshop batch per field tool, represented by one pickable physical
-- stack. The four elemental launchers use their four-tube workshop batch.
local bundles = {
    {"magic_tube", 4}, {"fire_tube", 4}, {"frost_tube", 4}, {"shock_tube", 4},
    {"derringer", 1}, {"flare_gun", 1}, {"sedative_launcher", 1},
    {"turret_pack", 4}, {"rocket_turret_pack", 4}, {"shield_turret_pack", 4},
}

local function dropPosition(x, y, index)
    local angle = (index - 1) * (2 * math.pi / #bundles)
    local dx, dy = math.cos(angle), math.sin(angle)
    for radius = 28, 12, -8 do
        local px, py = x + radius * dx, y + radius * dy
        if not RaytracePlatforms(x, y, px, py)
            and not RaytracePlatforms(px - 6, py, px + 6, py)
            and not RaytracePlatforms(px, py - 6, px, py + 6) then
            return px, py
        end
    end
    return x, y
end

function M.prepare(player, id, existing, spawn)
    if id == "tarot_moon" then
        return EntityGetFirstComponentIncludingDisabled(player, "CharacterPlatformingComponent") ~= nil
    end
    if id ~= "tarot_magician" then return true end
    local x, y = EntityGetTransform(player)
    for i, bundle in ipairs(bundles) do
        local px, py = dropPosition(x, y - 4, i)
        local entity = spawn(root .. "items/" .. bundle[1] .. ".xml", nil, false, px, py)
        local item = entity and EntityGetFirstComponentIncludingDisabled(entity, "ItemComponent")
        local uses = item and ComponentGetValue2(item, "uses_remaining")
        if not uses or uses <= 0 then return false end
        ComponentSetValue2(item, "uses_remaining", uses * bundle[2])
    end
    return true
end

local gravityTag = "nh_tarot_moon_gravity"
local gravityFactor = 0.6

function M.commit(player, id, timer, existing)
    if id ~= "tarot_moon" or existing then return end
    -- Vanilla LOW_GRAVITY also permanently alters nearby enemies. Only the
    -- user's platforming component should carry this temporary multiplier.
    for _, platform in ipairs(EntityGetComponentIncludingDisabled(player, "CharacterPlatformingComponent") or {}) do
        if not ComponentHasTag(platform, gravityTag) then
            ComponentSetValue2(platform, "pixel_gravity", ComponentGetValue2(platform, "pixel_gravity") * gravityFactor)
            ComponentAddTag(platform, gravityTag)
        end
    end
end

function M.expire(player, id)
    if id ~= "tarot_moon" then return end
    for _, platform in ipairs(EntityGetComponentIncludingDisabled(player, "CharacterPlatformingComponent", gravityTag) or {}) do
        ComponentSetValue2(platform, "pixel_gravity", ComponentGetValue2(platform, "pixel_gravity") / gravityFactor)
        ComponentRemoveTag(platform, gravityTag)
    end
end

return M
