NHPotion = {}

local empty_flask = "data/entities/items/pickup/potion_empty.xml"
local normal_flask_tag = "noita_hideout_standard_flask"
local unstable = "magic_liquid_unstable_teleportation"
local stable = "magic_liquid_teleportation"
local reagent_units = 250
NHPotion.ingredients = {
    {material = unstable, amount = reagent_units},
    {material = "slime", amount = reagent_units},
}

-- These templates differ from the base flask only by their initial fill.
-- Preserve special containers (e.g. mimic or alchemist flasks) in the world.
local normal_templates = {}
for _, suffix in ipairs({
    "", "_empty", "_starting", "_water", "_alcohol", "_beer", "_milk",
    "_porridge", "_random_material", "_secret", "_slime", "_vomit",
}) do
    normal_templates["data/entities/items/pickup/potion" .. suffix .. ".xml"] = true
end

local function component(entity, kind)
    local id = EntityGetFirstComponentIncludingDisabled(entity, kind)
    return id and id ~= 0 and id or nil
end

local function flask_components(entity)
    local parts = {}
    for _, kind in ipairs({"MaterialInventoryComponent", "MaterialSuckerComponent",
        "PotionComponent", "ItemComponent", "DamageModelComponent"}) do
        parts[kind] = component(entity, kind)
        assert(parts[kind], "Missing flask component: " .. kind)
    end
    return parts
end

local function whole_units(amount)
    return type(amount) == "number" and amount >= 0 and amount <= 2147483647
        and amount == math.floor(amount)
end

local function material_id(name)
    local id = CellFactory_GetType(name)
    assert(type(id) == "number" and id >= 0 and CellFactory_GetName(id) == name,
        "Material unavailable: " .. name)
    return id
end

local function read_materials(inventory)
    local counts = ComponentGetValue2(inventory, "count_per_material_type")
    assert(type(counts) == "table", "Could not read flask contents")
    local materials = {}
    for slot, amount in pairs(counts) do
        -- Noita returns a one-indexed Lua array for its zero-indexed material IDs.
        assert(whole_units(amount), "Flask contains a quantity that cannot be restored exactly")
        if amount > 0 then
            local name = CellFactory_GetName(slot - 1)
            assert(type(name) == "string" and name ~= "" and material_id(name) == slot - 1,
                "Unrecognized flask material")
            materials[name] = amount
        end
    end
    return materials
end

local short_names = {
    [unstable] = {"不稳定传送液", "Unstable teleportatium"},
    [stable] = {"稳定传送液", "Teleportatium"},
    slime = {"黏液", "Slime"},
}

function NHPotion.label(record, lang)
    local names = {}
    for name in pairs(record.materials) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then return lang == "zh" and "空药瓶" or "Empty flask" end
    local parts = {}
    for _, name in ipairs(names) do
        local localized = short_names[name] and short_names[name][lang == "zh" and 1 or 2] or name
        parts[#parts + 1] = localized .. " " .. record.materials[name]
    end
    return table.concat(parts, " + ")
end

local function refresh_name(record)
    record.name = NHPotion.label(record, "en")
    record.label = record.name
    return record
end

local function capture(entity)
    assert(entity and entity ~= 0 and (normal_templates[EntityGetFilename(entity)]
        or EntityHasTag(entity, normal_flask_tag)), "Only a recognized ordinary flask can be stored")
    assert(#(EntityGetAllChildren(entity) or {}) == 0 and not component(entity, "ItemCostComponent"),
        "This flask has attachments or a shop price and cannot be stored")
    local c = flask_components(entity)
    local inv = c.MaterialInventoryComponent
    return refresh_name({
        kind = "potion", materials = read_materials(inv),
        capacity = ComponentGetValue2(c.MaterialSuckerComponent, "barrel_size"),
        max_capacity = ComponentGetValue2(inv, "max_capacity"),
        reactions = ComponentGetValue2(inv, "do_reactions"),
        hp = ComponentGetValue2(c.DamageModelComponent, "hp"),
        picked = ComponentGetValue2(c.ItemComponent, "has_been_picked_by_player"),
        extra_capacity = EntityHasTag(entity, "extra_potion_capacity"),
    })
end

function NHPotion.snapshot(entity)
    local ok, value = pcall(capture, entity)
    if ok then return value end
    return nil, tostring(value)
end

NHPotion.capture = NHPotion.snapshot

-- Called only after the contents have a confirmed new owner or on failed spawn.
function NHPotion.discard(entity, owner)
    local inv = component(entity, "MaterialInventoryComponent")
    if inv then
        ComponentSetValue2(inv, "on_death_spill", false)
        RemoveMaterialInventoryMaterial(entity, "")
    end
    for _, kind in ipairs({"LuaComponent", "ExplodeOnDamageComponent"}) do
        for _, id in ipairs(EntityGetComponentIncludingDisabled(entity, kind) or {}) do
            EntityRemoveComponent(entity, id)
        end
    end
    if owner and owner ~= 0 then
        GameKillInventoryItem(owner, entity)
    else
        EntityKill(entity)
    end
end

function NHPotion.restore(record, x, y)
    local entity
    local ok, err = pcall(function()
        assert(record.kind == "potion" and type(record.materials) == "table", "Invalid flask record")
        for name, amount in pairs(record.materials) do
            assert(type(name) == "string" and whole_units(amount) and amount > 0, "Invalid material quantity")
            material_id(name)
        end
        entity = EntityLoad(empty_flask, x, y)
        assert(entity and entity ~= 0, "Empty flask failed to spawn")
        local c = flask_components(entity)
        local inv = c.MaterialInventoryComponent
        if record.capacity then ComponentSetValue2(c.MaterialSuckerComponent, "barrel_size", record.capacity) end
        if record.max_capacity then ComponentSetValue2(inv, "max_capacity", record.max_capacity) end
        if record.reactions then ComponentSetValue2(inv, "do_reactions", record.reactions) end
        if record.hp then ComponentSetValue2(c.DamageModelComponent, "hp", record.hp) end
        if record.picked then ComponentSetValue2(c.ItemComponent, "has_been_picked_by_player", true) end
        if record.extra_capacity then EntityAddTag(entity, "extra_potion_capacity") end
        EntityAddTag(entity, normal_flask_tag)
        -- Prevent a modified base template from contributing any extra liquid.
        RemoveMaterialInventoryMaterial(entity, "")
        for name, amount in pairs(record.materials) do
            AddMaterialInventoryMaterial(entity, name, amount)
        end
        local actual = read_materials(inv)
        for name, amount in pairs(record.materials) do
            assert(actual[name] == amount, "Failed to restore: " .. name)
            actual[name] = nil
        end
        assert(next(actual) == nil, "Unexpected material in restored flask")
    end)
    if ok then return entity end
    if entity and entity ~= 0 then NHPotion.discard(entity) end
    return nil, tostring(err)
end

function NHPotion.sample(x, y)
    -- Vanilla bottles react while carried. Keep this test fixture stable so the
    -- same 250 + 250 units can be counted on both sides of a storage round-trip.
    return NHPotion.restore({
        kind = "potion", materials = {[unstable] = reagent_units, slime = reagent_units},
        capacity = 1000, reactions = 0,
    }, x, y)
end

local function subtract(materials, name, amount)
    local remaining = materials[name] - amount
    materials[name] = remaining > 0 and remaining or nil
end

function NHPotion.pour(record, name, amount)
    if not whole_units(amount) or amount == 0 or (record.materials[name] or 0) < amount then
        return nil, "Not enough material for that quantity"
    end
    subtract(record.materials, name, amount)
    refresh_name(record)
    return amount
end

function NHPotion.can_refine(record)
    if type(record) ~= "table" or record.kind ~= "potion" or type(record.materials) ~= "table" then
        return false
    end
    for _, input in ipairs(NHPotion.ingredients) do
        if (record.materials[input.material] or 0) < input.amount then return false end
    end
    return true
end

-- The caller commits the paid inputs and the resulting order in one profile update.
function NHPotion.recipe(record)
    if not NHPotion.can_refine(record) then return nil, "Need 250 unstable teleportatium and 250 slime" end
    local output_units = 0
    for _, input in ipairs(NHPotion.ingredients) do
        subtract(record.materials, input.material, input.amount)
        output_units = output_units + input.amount
    end
    refresh_name(record)
    return refresh_name({kind = "potion", capacity = 1000, materials = {[stable] = output_units}})
end
