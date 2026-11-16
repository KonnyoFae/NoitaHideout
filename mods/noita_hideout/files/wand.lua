-- Snapshot supported vanilla wands by value. The caller owns the transfer
-- transaction and removes the original only after capture and a durable commit.
NHWand = {}
local items = "data/entities/items/"
local broom = items .. "wand_varpuluuta.xml"
local broom_script = "data/scripts/gun/procedural/wand_varpuluuta.lua"
local source_marker = "noita_hideout_wand_template"
local transfer_marker = "noita_hideout_transfer_id"
local templates = { [broom] = true }
for _, suffix in ipairs({"", "_rng", "_rng_daily"}) do
    templates[items .. "starting_wand" .. suffix .. ".xml"] = true
    templates[items .. "starting_bomb_wand" .. suffix .. ".xml"] = true
end
for _, level in ipairs({"01", "02", "03", "04", "05", "06", "10"}) do
    templates[items .. "wand_level_" .. level .. ".xml"] = true
    templates[items .. "wand_unshuffle_" .. level .. ".xml"] = true
    if level ~= "10" then
        templates[items .. "wand_level_" .. level .. "_p.xml"] = true
        templates[items .. "wand_level_" .. level .. "_better.xml"] = true
        templates[items .. "wand_unshuffle_" .. level .. "_p.xml"] = true
    end
end

local ability_fields = {"mana", "mana_max", "mana_charge_speed", "ui_name", "sprite_file",
    "stat_times_player_has_shot", "stat_times_player_has_edited", "gun_level", "never_reload",
    "item_recoil_recovery_speed", "item_recoil_max", "rotate_in_hand", "rotate_in_hand_amount",
    "rotate_hand_amount", "current_slot_durability", "swim_propel_amount", "mReloadFramesLeft"}
local item_fields = {"item_name", "ui_sprite", "ui_description", "always_use_item_name_in_ui",
    "is_frozen", "is_identified", "uses_remaining", "has_been_picked_by_player"}
local sprite_fields = {"image_file", "offset_x", "offset_y", "rect_animation", "next_rect_animation"}
local card_fields = {"permanently_attached", "uses_remaining", "is_frozen", "is_identified",
    "has_been_picked_by_player"}
local root_types = {}
for t in ("Ability Item Sprite Hotspot ManaReloader Gun Velocity SimplePhysics Hitbox Light " ..
    "AudioLoop SpriteParticleEmitter ItemAlchemy MaterialAreaChecker PhysicsBody PhysicsShape"):gmatch("%S+") do
    root_types[t .. "Component"] = true
end
local first = EntityGetFirstComponentIncludingDisabled
local get = ComponentGetValue2
local set = ComponentSetValue2

local function required(entity, ctype, tag)
    local id
    if tag then id = first(entity, ctype, tag) else id = first(entity, ctype) end
    assert(id and id ~= 0, "Missing " .. ctype)
    return id
end

local function fields(component, keys)
    local values = {}
    for _, k in ipairs(keys) do
        local v = get(component, k)
        assert(v ~= nil, "Cannot read " .. k)
        values[k] = v
    end
    return values
end

local function apply(component, values)
    for k, v in pairs(values) do set(component, k, v) end
end

local function canonical_sprite(sprite)
    -- A PNG has no named animation clips. A procedurally reskinned wand
    -- can retain its base XML's clip names until the first sprite refresh.
    if not sprite.image_file:lower():match("%.png$")
        or (sprite.rect_animation == "" and sprite.next_rect_animation == "") then return sprite end
    local normalized = {}
    for k, v in pairs(sprite) do normalized[k] = v end
    normalized.rect_animation, normalized.next_rect_animation = "", ""
    return normalized
end

local function object_fields(component, name)
    local result = {}
    for field in pairs(assert(ComponentObjectGetMembers(component, name))) do
        local v = ComponentObjectGetValue2(component, name, field)
        if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then result[field] = v end
    end
    return result
end

local function wand_tags(entity)
    local tags = {}
    for tag in (EntityGetTags(entity) or ""):gmatch("[^,]+") do
        if tag ~= "noita_hideout_transfer_item" then tags[tag] = true end
    end
    return tags
end

local function source(entity, ability, item)
    local marker = first(entity, "VariableStorageComponent", source_marker)
    local path = marker and get(marker, "value_string") or EntityGetFilename(entity)
    if templates[path] then return path end
    -- Spawn inventory entries are inline <Entity><Base .../></Entity>.
    -- An inline/streamed entity doesn't always expose its own XML filename.
    if path and path:match("^mods/") then error("Unsupported mod wand template") end
    local label = get(item, "item_name")
    if label == "$item_wand_varpuluuta" then
        for _, comp in ipairs(EntityGetComponentIncludingDisabled(entity, "LuaComponent") or {}) do
            if get(comp, "script_source_file") == broom_script then return broom end
        end
    end
    if get(item, "collect_nondefault_actions") and get(item, "remove_on_death") then
        local sprite = get(ability, "sprite_file")
        if label == "default_gun" and sprite == "data/items_gfx/handgun.xml" then
            return items .. "starting_wand_rng.xml"
        end
        if label == "bomb_wand" and sprite == "data/items_gfx/bomb_wand.xml" then
            return items .. "starting_bomb_wand_rng.xml"
        end
    end
    error("Unsupported or unknown wand template")
end

local function check_root(entity, path)
    for _, c in ipairs(EntityGetAllComponents(entity)) do
        local t = ComponentGetTypeName(c)
        if t == "LuaComponent" then
            local src = get(c, "script_source_file")
            local valid = (path == broom and src == broom_script)
                or get(c, "script_item_picked_up") == "data/scripts/particles/wand_pickup.lua"
                or get(c, "script_material_area_checker_success") == "data/scripts/animals/wand_charm.lua"
                or ((src or "") == "" and not ComponentGetIsEnabled(c))
            assert(valid, "Unsupported wand script or wand still initializing")
        elseif t == "VariableStorageComponent" then
            local name = get(c, "name")
            assert(name == source_marker or name == transfer_marker, "Unsupported wand variable")
        else
            assert(root_types[t], "Unsupported wand component: " .. t)
        end
    end
end

local function capture_card(entity, action)
    assert(not (EntityGetAllChildren(entity) or {})[1], "Unsupported spell attachment")
    assert(not first(entity, "VariableStorageComponent") and not first(entity, "LuaComponent"),
        "Stateful spell is not supported")
    local item = required(entity, "ItemComponent")
    local x, y = get(item, "inventory_slot")
    local id = get(action, "action_id")
    assert(type(id) == "string" and id ~= "", "Spell has no action ID")
    return {id = id, x = x, y = y, item = fields(item, card_fields)}
end

local function capture(entity)
    local ability, item = required(entity, "AbilityComponent"), required(entity, "ItemComponent")
    assert(get(ability, "use_gun_script"), "Hold a wand")
    local path = source(entity, ability, item)
    check_root(entity, path)
    local sprite = required(entity, "SpriteComponent", "item")
    local hotspot = required(entity, "HotspotComponent", "shoot_pos")
    local tip_x, tip_y = get(hotspot, "offset")
    local cards, cleaner = {}, false
    for _, child in ipairs(EntityGetAllChildren(entity) or {}) do
        local action = first(child, "ItemActionComponent")
        if action then
            cards[#cards + 1] = capture_card(child, action)
        else
            local eater = first(child, "CellEaterComponent")
            assert(path == broom and not cleaner and eater and get(eater, "only_stain")
                and first(child, "InheritTransformComponent") and #(EntityGetAllComponents(child)) == 2
                and not (EntityGetAllChildren(child) or {})[1], "Unsupported wand attachment")
            cleaner = fields(eater, {"radius", "eat_probability", "only_stain"})
        end
    end
    assert(path ~= broom or cleaner, "Varpuluuta cleaner is missing")
    local gun = object_fields(ability, "gun_config")
    local cast = object_fields(ability, "gunaction_config")
    assert(gun.deck_capacity ~= nil and cast.fire_rate_wait ~= nil, "Cannot read wand firing settings")
    local frame = GameGetFrameNum()
    local name = get(item, "always_use_item_name_in_ui") and get(item, "item_name") or get(ability, "ui_name")
    return {kind = "wand", name = name, template = path, cards = cards, cleaner = cleaner, tags = wand_tags(entity),
        entity_name = EntityGetName(entity), ability = fields(ability, ability_fields),
        item = fields(item, item_fields), sprite = canonical_sprite(fields(sprite, sprite_fields)), tip = {tip_x, tip_y},
        gun_config = gun, gunaction_config = cast,
        cast_wait = math.max(0, get(ability, "mNextFrameUsable") - frame),
        reload_wait = math.max(0, get(ability, "mReloadNextFrameUsable") - frame)}
end

function NHWand.capture(entity)
    local ok, result = pcall(capture, entity)
    if ok then return result end
    return nil, tostring(result)
end

local function prepare(entity)
    -- Depending on load timing, procedural setup may already have made cards
    -- or its execute_on_added script may still be waiting for the next tick.
    for _, c in ipairs(EntityGetComponentIncludingDisabled(entity, "LuaComponent") or {}) do
        if get(c, "execute_on_added") and get(c, "remove_after_executed")
            and (get(c, "script_source_file") or ""):match("^data/scripts/gun/procedural/") then
            EntityRemoveComponent(entity, c)
        end
    end
    local ability = required(entity, "AbilityComponent")
    set(ability, "add_these_child_actions", "")
    for _, child in ipairs(EntityGetAllChildren(entity) or {}) do
        if first(child, "ItemActionComponent") then
            EntityRemoveFromParent(child)
            EntityKill(child)
        end
    end
    return ability
end

local function add_card(entity, card, x, y)
    local child = CreateItemActionEntity(card.id, x, y)
    assert(child and child ~= 0, "Unavailable spell: " .. card.id)
    EntityAddChild(entity, child) -- also owns cleanup if a later check fails
    assert(get(required(child, "ItemActionComponent"), "action_id") == card.id, "Spell unavailable: " .. card.id)
    local item = required(child, "ItemComponent")
    apply(item, card.item)
    set(item, "inventory_slot", card.x, card.y)
    EntitySetComponentsWithTagEnabled(child, "enabled_in_hand", false)
    EntitySetComponentsWithTagEnabled(child, "enabled_in_world", false)
end

local function build(path, x, y, configure)
    local entity
    local ok, err = pcall(function()
        assert(templates[path], "Unsupported wand template")
        entity = EntityLoad(path, x, y)
        assert(entity and entity ~= 0, "Wand template unavailable")
        configure(entity, prepare(entity))
    end)
    if ok then return entity end
    if entity and entity ~= 0 then EntityKill(entity) end
    return nil, tostring(err)
end

local function verify_values(stored, actual, path)
    if type(stored) ~= "table" or type(actual) ~= "table" then
        assert(stored == actual, "Wand readback mismatch: " .. path)
        return
    end
    for k, v in pairs(stored) do verify_values(v, actual[k], path .. "." .. k) end
    for k in pairs(actual) do assert(stored[k] ~= nil, "Unexpected wand field: " .. path .. "." .. k) end
end

function NHWand.restore(data, x, y)
    return build(data.template, x, y, function(entity, ability)
        -- Normalize old records on read without modifying the journaled entry.
        local normalized = canonical_sprite(data.sprite)
        if normalized ~= data.sprite then
            local copy = {}
            for k, v in pairs(data) do copy[k] = v end
            copy.sprite = normalized
            data = copy
        end
        apply(ability, data.ability)
        for _, object in ipairs({"gun_config", "gunaction_config"}) do
            for k, v in pairs(data[object]) do ComponentObjectSetValue2(ability, object, k, v) end
        end
        set(ability, "mNextFrameUsable", GameGetFrameNum() + data.cast_wait)
        set(ability, "mReloadNextFrameUsable", GameGetFrameNum() + data.reload_wait)
        apply(required(entity, "ItemComponent"), data.item)
        local sprite = required(entity, "SpriteComponent", "item")
        apply(sprite, data.sprite)
        EntityRefreshSprite(entity, sprite)
        set(required(entity, "HotspotComponent", "shoot_pos"), "offset", data.tip[1], data.tip[2])
        EntitySetName(entity, data.entity_name)
        local defaults = wand_tags(entity)
        for tag in pairs(defaults) do if not data.tags[tag] then EntityRemoveTag(entity, tag) end end
        for tag in pairs(data.tags) do if not defaults[tag] then EntityAddTag(entity, tag) end end
        if data.cleaner then
            local eater
            for _, child in ipairs(EntityGetAllChildren(entity) or {}) do
                eater = first(child, "CellEaterComponent")
                if eater then break end
            end
            apply(assert(eater, "Cleaner missing from wand template"), data.cleaner)
        end
        for _, card in ipairs(data.cards) do add_card(entity, card, x, y) end
        assert(EntityAddComponent2(entity, "VariableStorageComponent",
            {_tags = source_marker, name = source_marker, value_string = data.template}), "Could not mark wand template")
        -- Some setters report engine errors without raising a Lua error.
        -- Re-read the actual clone before the transfer retires its stash entry.
        verify_values(data, capture(entity), "wand")
    end)
end

function NHWand.sample(x, y)
    return build(broom, x, y, function(entity, ability)
        set(ability, "mana_max", 120)
        set(ability, "mana", 120)
        ComponentObjectSetValue2(ability, "gun_config", "deck_capacity", 4)
        ComponentObjectSetValue2(ability, "gun_config", "shuffle_deck_when_empty", false)
        add_card(entity, {id = "SPEED", x = 0, y = 0, item = {permanently_attached = true}}, x, y)
        add_card(entity, {id = "LIGHT_BULLET", x = 1, y = 0, item = {}}, x, y)
        add_card(entity, {id = "BOMB", x = 2, y = 0, item = {uses_remaining = 2}}, x, y)
    end)
end
