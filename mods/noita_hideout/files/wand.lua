-- Snapshot supported vanilla wands by value. The caller owns the transfer
-- transaction and removes the original only after capture and a durable commit.
NHWand = {}
local items = "data/entities/items/"
local broom = items .. "wand_varpuluuta.xml"
local broom_script = "data/scripts/gun/procedural/wand_varpuluuta.lua"
local source_marker = "noita_hideout_wand_template"
local transfer_marker = "noita_hideout_transfer_id"
local templates = { [broom] = true }
local bases = {}
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

local function supported(path)
    -- Fixed first-biome wands use numbered XMLs, separate from procedural templates.
    return path and (templates[path] or path:match("^data/entities/items/wands/level_%d%d/wand_%d+%.xml$"))
end

function NHWand.registerTemplates()
    -- Noita can serialize an inline wand under its parent's filename. A marker
    -- on the template follows that exact entity through pickup and save/reload.
    for path in pairs(templates) do
        if ModDoesFileExist(path) then
            local xml = ModTextFileGetContent(path) or ""
            local plain = xml:gsub("<!%-%-.-%-%->", "")
            bases[path] = plain:match([[<Base%s+[^>]-file%s*=%s*"([^"]+)"]])
            if not xml:find(source_marker, 1, true) then
                local marker = '<VariableStorageComponent _tags="' .. source_marker .. '" name="' ..
                    source_marker .. '" value_string="' .. path .. '"/>'
                local patched, n = xml:gsub("</Entity>(%s*)$", marker .. "</Entity>%1", 1)
                if n == 1 then ModTextFileSetContent(path, patched) end
            end
        end
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

local function marked_source(entity)
    local markers = {}
    for _, c in ipairs(EntityGetComponentIncludingDisabled(entity, "VariableStorageComponent", source_marker) or {}) do
        local path = get(c, "value_string")
        assert(supported(path), "Unknown stored wand template: " .. tostring(path))
        markers[path] = true
    end
    local leaf
    for path in pairs(markers) do
        local inherited = false
        for other in pairs(markers) do
            local parent = bases[other]
            local seen = {}
            while parent and not seen[parent] do
                if parent == path then inherited = true; break end
                seen[parent] = true
                parent = bases[parent]
            end
        end
        if not inherited then
            assert(not leaf, "Conflicting wand template markers")
            leaf = path
        end
    end
    return leaf
end

local function source(entity, ability, item)
    local path = (EntityGetFilename(entity) or ""):gsub("\\", "/"):lower():gsub("^%./", "")
    if path:match("^%a:/") or path:match("^/") then
        path = path:match("/(mods/.+)$") or path:match("/(data/.+)$") or path
    end
    -- Inventory entities can inherit the virtual filename of the loaded player.
    if path:match("^%W*sav/player%.xml$") then path = "data/entities/player.xml" end
    if supported(path) then return path end
    local inline = path == "" or path == "data/entities/base_wand_pickup.xml" or path == "data/entities/player.xml"
        or path == "data/entities/player_base.xml" or path:match("^data/entities/animals/[%w_/-]+%.xml$")
    if not inline then
        error("Unsupported wand template: " .. path)
    end
    local marked = marked_source(entity)
    if marked then return marked end
    local label = get(item, "item_name")
    if label == "$item_wand_varpuluuta" then
        for _, comp in ipairs(EntityGetComponentIncludingDisabled(entity, "LuaComponent") or {}) do
            if get(comp, "script_source_file") == broom_script then return broom end
        end
        for _, child in ipairs(EntityGetAllChildren(entity) or {}) do
            local eater = first(child, "CellEaterComponent")
            if eater and get(eater, "only_stain") and first(child, "InheritTransformComponent") then return broom end
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
    -- Pre-update saves may contain an ordinary generated wand without any
    -- source identity. Only use a generic tier shell for the numbered vanilla
    -- wand sprites and ordinary components. The snapshot supplies the full
    -- firing configuration, actual sprite, muzzle, tags and ordered deck.
    local sprite = get(ability, "sprite_file") or ""
    if (path == "" or path == "data/entities/base_wand_pickup.xml" or path == "data/entities/player.xml")
        and (label == "$item_wand" or label == "wand" or label == "")
        and sprite:match("^data/items_gfx/wands/wand_%d+%.png$") then
        for _, kind in ipairs({"SpriteComponent", "HotspotComponent"}) do
            assert(#(EntityGetComponentIncludingDisabled(entity, kind) or {}) == 1, "Unidentified wand has extra " .. kind)
        end
        for _, c in ipairs(EntityGetAllComponents(entity)) do
            local t = ComponentGetTypeName(c)
            assert(not t:match("^Physics") and t ~= "ItemAlchemyComponent"
                and t ~= "LightComponent" and t ~= "AudioLoopComponent" and t ~= "SpriteParticleEmitterComponent",
                "Unidentified wand has special component: " .. t)
        end
        return items .. "wand_level_01.xml"
    end
    error("Unknown wand template: " .. (path ~= "" and path or "<inline>") .. " (" .. tostring(label) .. ", " .. sprite .. ")")
end

local function generator(c)
    local src = get(c, "script_source_file") or ""
    return src:match("^data/scripts/gun/procedural/[%w_]+%.lua$")
        and get(c, "execute_on_added") and get(c, "remove_after_executed")
end

local wand_callbacks = {
    script_item_picked_up = "data/scripts/particles/wand_pickup.lua",
    script_material_area_checker_success = "data/scripts/animals/wand_charm.lua",
}

local function check_script(c, path)
    local found = false
    for key in pairs(ComponentGetMembers(c) or {}) do
        if key:match("^script_") then
            local file = get(c, key)
            if type(file) == "string" and file ~= "" then
                found = true
                if key == "script_source_file" and generator(c) then
                    assert(not ComponentGetIsEnabled(c) or (get(c, "mTimesExecuted") or 0) > 0,
                        "Wand is still generating: " .. file)
                else
                    local valid = wand_callbacks[key] == file or (key == "script_source_file" and path == broom and file == broom_script)
                    assert(valid, "Unsupported wand script: " .. file .. " (" .. key .. ")")
                end
            end
        end
    end
    assert(found or not ComponentGetIsEnabled(c), "Unsupported empty wand script")
end

local function check_root(entity, path)
    local editor
    for _, c in ipairs(EntityGetAllComponents(entity)) do
        local t = ComponentGetTypeName(c)
        if t == "LuaComponent" then
            check_script(c, path)
        elseif t == "ItemCostComponent" then
            assert(get(c, "cost") == 0, "Cannot store a wand with an outstanding shop price")
        elseif t == "VariableStorageComponent" then
            local name = get(c, "name")
            if name:match("^spell_lab_shugged_edit_panel") or name:match("^%$spell_lab_shugged_operation_") then
                local values = fields(c, {"name", "value_bool", "value_float", "value_int", "value_string"})
                values._tags = ComponentGetTags(c) or ""
                editor = editor or {}
                editor[#editor + 1] = {values = values, enabled = ComponentGetIsEnabled(c)}
            else
                assert(name == source_marker or name == transfer_marker, "Unsupported wand variable: " .. tostring(name))
            end
        else
            assert(root_types[t], "Unsupported wand component: " .. t)
        end
    end
    return editor
end

local stock_pickups = {}
local shop_pickup = "data/scripts/items/shop_effect.lua"

local function add_shop_pickup(entity)
    return assert(EntityAddComponent2(entity, "LuaComponent", {script_item_picked_up = shop_pickup}),
        "Could not restore the shop pickup effect")
end

local function card_pickup(c, id)
    local file = get(c, "script_item_picked_up") or ""
    assert(file:match("^data/scripts/[%w_/]+%.lua$"), "Unsupported spell script: " .. id .. " " .. file)
    local settings = {}
    for key in pairs(ComponentGetMembers(c) or {}) do
        if key:match("^script_") then
            local callback = get(c, key)
            assert(key == "script_item_picked_up" or not callback or callback == "",
                "Unsupported spell callback: " .. id .. " " .. tostring(callback))
        elseif not key:match("^[m_]") then
            local value = get(c, key)
            if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then settings[key] = value end
        end
    end
    return file, settings
end

local function default_pickups(id, x, y)
    if stock_pickups[id] then return stock_pickups[id] end
    local probe = CreateItemActionEntity(id, x, y)
    assert(probe and probe ~= 0, "Unavailable spell: " .. id)
    local ok, profile = pcall(function()
        local result = {}
        for _, c in ipairs(EntityGetComponentIncludingDisabled(probe, "LuaComponent") or {}) do
            local file, settings = card_pickup(c, id)
            assert(not result[file], "Duplicate spell pickup callback: " .. id)
            result[file] = settings
        end
        -- The shop generator adds this visual callback after the card factory runs.
        if not result[shop_pickup] then
            local file, settings = card_pickup(add_shop_pickup(probe), id)
            result[file] = settings
        end
        return result
    end)
    EntityKill(probe)
    if not ok then error(profile) end
    stock_pickups[id] = profile
    return profile
end

local function pickup_states(entity, id)
    local states
    for _, c in ipairs(EntityGetComponentIncludingDisabled(entity, "LuaComponent") or {}) do
        local file, settings = card_pickup(c, id)
        local expected = default_pickups(id, EntityGetTransform(entity))[file]
        assert(expected, "Nonstandard spell pickup callback: " .. id .. " " .. file)
        assert((get(c, "mTimesExecuted") or 0) == 0 or file == shop_pickup or file:match("^data/scripts/particles/"),
            "Stateful spell pickup callback: " .. id .. " " .. file)
        for key, value in pairs(settings) do
            assert(expected[key] == value, "Modified spell pickup callback: " .. id .. " " .. key)
        end
        states = states or {}
        assert(states[file] == nil, "Duplicate spell pickup callback: " .. id)
        states[file] = ComponentGetIsEnabled(c)
    end
    return states
end

local function capture_card(entity, action)
    assert(not first(entity, "ItemCostComponent"), "Cannot store a shop spell")
    local id = get(action, "action_id")
    assert(type(id) == "string" and id ~= "", "Spell has no action ID")
    assert(not (EntityGetAllChildren(entity) or {})[1], "Unsupported spell attachment: " .. id)
    local stack
    for _, var in ipairs(EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent") or {}) do
        local name = get(var,"name")
        if name == "stackable_spells_count" then
            stack = get(var,"value_int")
            assert(stack >= 1 and stack == math.floor(stack), "Invalid spell stack")
        else assert(name == transfer_marker, "Unsupported spell variable: " .. tostring(name)) end
    end
    local item = required(entity, "ItemComponent")
    local x, y = get(item, "inventory_slot")
    return {id = id, stack = stack, x = x, y = y, item = fields(item, card_fields), pickups = pickup_states(entity, id)}
end

local function capture(entity)
    local ability, item = required(entity, "AbilityComponent"), required(entity, "ItemComponent")
    assert(get(ability, "use_gun_script"), "Hold a wand")
    local path = source(entity, ability, item)
    local editor = check_root(entity, path)
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
                and not (EntityGetAllChildren(child) or {})[1], "Unsupported wand attachment: " ..
                    tostring(EntityGetName(child)) .. " (" .. tostring(EntityGetFilename(child)) .. ")")
            cleaner = fields(eater, {"radius", "eat_probability", "only_stain"})
        end
    end
    assert(path ~= broom or cleaner, "Varpuluuta cleaner is missing")
    local gun = object_fields(ability, "gun_config")
    local cast = object_fields(ability, "gunaction_config")
    assert(gun.deck_capacity ~= nil and cast.fire_rate_wait ~= nil, "Cannot read wand firing settings")
    local frame = GameGetFrameNum()
    local name = get(item, "always_use_item_name_in_ui") and get(item, "item_name") or get(ability, "ui_name")
    -- Native generation can tint the ground light purple on a rare wand.
    local light=path:match("^data/entities/items/wand_level_0[123]%.xml$") and first(entity,"LightComponent")
    return {kind = "wand", name = name, template = path, editor = editor, cards = cards, cleaner = cleaner, tags = wand_tags(entity),
        light=light and fields(light,{"r","g","b"}) or nil,
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
        if generator(c) then
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

local function configure_card(child, card, restoring)
    assert(get(required(child, "ItemActionComponent"), "action_id") == card.id, "Spell unavailable: " .. card.id)
    local item = required(child, "ItemComponent")
    apply(item, card.item)
    if card.stack then assert(EntityAddComponent2(child,"VariableStorageComponent",{name="stackable_spells_count", value_int=card.stack})) end
    set(item, "inventory_slot", card.x, card.y)
    EntitySetComponentsWithTagEnabled(child, "enabled_in_hand", false)
    EntitySetComponentsWithTagEnabled(child, "enabled_in_world", false)
    if restoring then
        local needs_shop = card.pickups and card.pickups[shop_pickup] ~= nil
        for _, c in ipairs(EntityGetComponentIncludingDisabled(child, "LuaComponent") or {}) do
            local file = card_pickup(c, card.id)
            if file == shop_pickup then needs_shop = false end
            local enabled = card.pickups and card.pickups[file]
            if enabled ~= nil then EntitySetComponentIsEnabled(child, c, enabled)
            else
                -- The original card no longer had this stock pickup helper.
                EntityRemoveComponent(child, c)
            end
        end
        if needs_shop then
            EntitySetComponentIsEnabled(child, add_shop_pickup(child), card.pickups[shop_pickup])
        end
    end
end

local function add_card(entity, card, x, y, restoring)
    local child = CreateItemActionEntity(card.id, x, y)
    assert(child and child ~= 0, "Unavailable spell: " .. card.id)
    EntityAddChild(entity, child)
    configure_card(child, card, restoring)
end

NHSpell = {}
function NHSpell.capture(entity)
    local ok, result = pcall(function()
        local card = capture_card(entity, required(entity,"ItemActionComponent"))
        local item = required(entity,"ItemComponent")
        local icon = get(item,"ui_sprite")
        if not icon or icon == "" then
            local sprite = first(entity,"SpriteComponent")
            icon = sprite and get(sprite,"image_file")
        end
        return {kind="spell", name=get(item,"item_name"), icon=icon, card=card}
    end)
    if ok then return result end
    return nil, tostring(result)
end

function NHSpell.restore(record,x,y)
    local child = CreateItemActionEntity(record.card.id,x,y)
    if not child or child == 0 then return nil, "Unavailable spell: " .. record.card.id end
    -- A crafted card uses the factory's pickup scripts. Captured cards replay their saved script state.
    local ok, reason = pcall(configure_card,child,record.card,not record.card.useDefaultPickups)
    if ok then return child end
    EntityKill(child)
    return nil,tostring(reason)
end

local function build(path, x, y, configure)
    local entity
    local ok, err = pcall(function()
        assert(supported(path), "Unsupported wand template: " .. tostring(path))
        entity = EntityLoad(path, x, y)
        assert(entity and entity ~= 0, "Wand template unavailable")
        configure(entity, prepare(entity))
    end)
    if ok then return entity end
    if entity and entity ~= 0 then EntityKill(entity) end
    return nil, tostring(err)
end

-- The vanilla level_01..03 scripts use these budgets and the same three
-- generator calls. Finish generation before capturing the actual wand; an
-- execute_on_added component may not have run yet on this engine tick.
local discoveryBudgets={30,40,60}
function NHWand.generateDiscovery(seed)
    local level=1+seed%#discoveryBudgets
    local path=("data/entities/items/wand_level_%02d.xml"):format(level)
    local x,y=seed%32768,math.floor(seed/32768)
    local record
    local entity,err=build(path,x,y,function(wand)
        dofile_once("data/scripts/gun/procedural/gun_procedural.lua")
        SetRandomSeed(x,y)
        local gun=get_gun_data(discoveryBudgets[level],level,false)
        make_wand_from_gun_data(gun,wand,level)
        wand_add_random_cards(gun,wand,level)
        record=capture(wand)
    end)
    if not entity then return nil,err end
    EntityKill(entity)
    return record
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
    if data.discovery then
        local preset=NHDragonLoot.wandItem(data.discovery)
        if not preset then return nil,"Unknown dragon nest wand." end
        return build(preset.template,x,y,function(entity)
            for _,card in ipairs(preset.cards) do add_card(entity,card,x,y) end
            assert(EntityAddComponent2(entity,"VariableStorageComponent",
                {_tags=source_marker,name=source_marker,value_string=preset.template}))
        end)
    end
    return build(data.template, x, y, function(entity, ability)
        -- Normalize old records on read without modifying the journaled entry.
        local normalized = canonical_sprite(data.sprite)
        if normalized ~= data.sprite then
            local copy = {}
            for k, v in pairs(data) do copy[k] = v end
            copy.sprite = normalized
            data = copy
        end
        if data.light then
            local light=required(entity,"LightComponent")
            apply(light,data.light)
            set(light,"update_properties",true)
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
        for _, record in ipairs(data.editor or {}) do
            local c = assert(EntityAddComponent2(entity, "VariableStorageComponent", record.values))
            EntitySetComponentIsEnabled(entity, c, record.enabled)
        end
        for _, card in ipairs(data.cards) do add_card(entity, card, x, y, true) end
        if marked_source(entity) ~= data.template then
            assert(EntityAddComponent2(entity, "VariableStorageComponent",
                {_tags = source_marker, name = source_marker, value_string = data.template}), "Could not mark wand template")
        end
        -- Some setters report engine errors without raising a Lua error.
        -- Re-read the actual clone before the transfer retires its stash entry.
        local actual=capture(entity)
        if not data.light then actual.light=nil end -- Older records omit the native ground light.
        verify_values(data,actual,"wand")
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
