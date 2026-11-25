-- Upgrade only the known old ground templates, on the original entity so
-- durability, ownership and other mods' data survive streaming and reloading.
local physics = {"PhysicsThrowableComponent", "PhysicsKeepInWorldComponent",
    "PhysicsImageShapeComponent", "PhysicsBodyComponent", "VelocityComponent"}
local dir = "mods/noita_hideout/files/items/"

local function migrate(entity, templates)
    if not EntityHasTag(entity, "item_physics") or EntityGetRootEntity(entity) ~= entity then return end
    local item = EntityGetFirstComponent(entity, "ItemComponent")
    local oldItem = item and templates[ComponentGetValue2(item, "item_name")]
    if not oldItem or not EntityHasTag(entity, oldItem.tag) or not ComponentGetValue2(item, "is_pickable") then return end
    local sprite = EntityGetFirstComponentIncludingDisabled(entity, "SpriteComponent", "enabled_in_hand")
    if not sprite or ComponentGetValue2(sprite, "image_file") ~= oldItem.image
        or EntityGetFirstComponentIncludingDisabled(entity, "PhysicsBody2Component")
        or EntityGetFirstComponentIncludingDisabled(entity, "PhysicsShapeComponent")
        or EntityGetFirstComponentIncludingDisabled(entity, "PhysicsJointComponent")
        or EntityGetFirstComponentIncludingDisabled(entity, "PhysicsJoint2Component") then return end

    local old = {}
    for _, kind in ipairs(physics) do
        local found = EntityGetComponentIncludingDisabled(entity, kind)
        if not found or #found ~= 1 then return end
        old[kind] = found[1]
    end
    local body, shape = old.PhysicsBodyComponent, old.PhysicsImageShapeComponent
    if ComponentGetValue2(shape, "image_file") ~= oldItem.image or ComponentGetValue2(shape, "body_id") ~= 1
        or ComponentGetValue2(body, "uid") ~= 1 then return end

    ComponentAddTag(sprite, "enabled_in_world")
    ComponentSetValue2(sprite, "z_index", -1.5)
    EntitySetComponentIsEnabled(entity, sprite, true)
    ComponentSetValue2(body, "kills_entity", false)
    ComponentSetValue2(body, "on_death_leave_physics_body", false)
    ComponentSetValue2(body, "is_enabled", false)
    for _, kind in ipairs(physics) do EntitySetComponentIsEnabled(entity, old[kind], false) end
    for _, kind in ipairs(physics) do EntityRemoveComponent(entity, old[kind]) end
    EntityRemoveTag(entity, "item_physics")
    return true
end

return function(bags, cards)
    local groups = {}
    if bags then
        local templates = {}
        for _, kind in ipairs({"travel_satchel", "travel_pack", "loot_case"}) do
            templates["$nh_hideout_" .. kind] = {tag="noita_hideout_" .. kind,image=dir .. kind .. ".png"}
        end
        groups[#groups+1] = {tag="nh_loot_bag",templates=templates}
    end
    if cards then
        local templates = {}
        local function addCards(order, suffix)
            for _, id in ipairs(order) do
                templates["$nh_card_" .. id] = {tag="nh_companion_" .. id,image=dir .. "card_" .. id .. suffix}
            end
        end
        addCards(NHCompanions.order, "_world.png")
        addCards(NHTarot.order, ".png")
        groups[#groups+1] = {tag="noita_hideout_summon_card",templates=templates}
    end
    return function()
        local converted = 0
        for _, group in ipairs(groups) do
            for _, entity in ipairs(EntityGetWithTag(group.tag) or {}) do
                if migrate(entity, group.templates) then
                    converted = converted + 1
                    if converted == 8 then return end
                end
            end
        end
    end
end
