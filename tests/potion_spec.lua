-- Tiny engine stand-in checks material IDs, one-indexed vectors, and spawn rollback.
dofile("mods/noita_hideout/files/potion.lua")
local ids = {water = 2, slime = 6, magic_liquid_unstable_teleportation = 8, magic_liquid_teleportation = 9}
local next_id, last, entities = 1, nil, {}
local kinds = {"MaterialInventoryComponent", "MaterialSuckerComponent", "PotionComponent",
    "DamageModelComponent", "ItemComponent", "LuaComponent", "ExplodeOnDamageComponent"}
local missing_on_add

function EntityLoad(path)
    local e = next_id
    last, next_id = e, e + 1
    entities[e] = {path = path, tags = {}, components = {}}
    for i, kind in ipairs(kinds) do
        entities[e].components[kind] = {
            id = 100 * e + i, barrel_size = 1000, max_capacity = -1, do_reactions = 20,
            hp = 0.5, has_been_picked_by_player = false, on_death_spill = true,
            count_per_material_type = {},
        }
    end
    return e
end
function EntityGetFirstComponentIncludingDisabled(e, kind)
    local c = entities[e].components[kind]
    return c and c.id
end
function EntityGetComponentIncludingDisabled(e, kind)
    local id = EntityGetFirstComponentIncludingDisabled(e, kind)
    return id and {id}
end
local function comp(id)
    return entities[math.floor(id / 100)].components[kinds[id % 100]]
end
function ComponentGetValue2(id, f) return comp(id)[f] end
function ComponentSetValue2(id, f, v) comp(id)[f] = v end
function EntityGetFilename(e) return entities[e].path end
function EntityHasTag(e, tag) return entities[e].tags[tag] or false end
function EntityAddTag(e, tag) entities[e].tags[tag] = true end
function EntityGetAllChildren(e) return entities[e].children end
function EntityRemoveComponent(e, id) entities[e].components[kinds[id % 100]] = nil end
function CellFactory_GetType(s) return ids[s] or -1 end
function CellFactory_GetName(id)
    for name, n in pairs(ids) do if n == id then return name end end
end
function AddMaterialInventoryMaterial(e, name, n)
    local contents = entities[e].components.MaterialInventoryComponent.count_per_material_type
    local key = ids[name] + 1
    if missing_on_add ~= name then contents[key] = (contents[key] or 0) + n end
end
function RemoveMaterialInventoryMaterial(e, name)
    assert(name == "")
    entities[e].components.MaterialInventoryComponent.count_per_material_type = {}
end
function EntityKill(e)
    assert(not entities[e].components.MaterialInventoryComponent.on_death_spill)
    assert(not entities[e].components.LuaComponent)
    assert(not entities[e].components.ExplodeOnDamageComponent)
    entities[e].killed = true
end
function GameKillInventoryItem(owner, e)
    entities[e].removed_from = owner
    EntityKill(e)
end

local sample = assert(NHPotion.sample(0, 0))
local data = assert(NHPotion.capture(sample))
assert(data.materials.slime == 250 and data.materials.magic_liquid_unstable_teleportation == 250)
assert(data.capacity == 1000 and data.reactions == 0)
assert(NHPotion.label(data, "zh"):find("250", 1, true))
local restored = assert(NHPotion.restore(data, 0, 0))
local again = assert(NHPotion.capture(restored))
assert(again.materials.slime == 250 and again.materials.magic_liquid_unstable_teleportation == 250)
assert(again.reactions == 0)
NHPotion.discard(restored, 77)
assert(entities[restored].killed and entities[restored].removed_from == 77)

data.materials.water = 25
assert(NHPotion.can_refine(data))
local product = assert(NHPotion.recipe(data))
assert(not NHPotion.can_refine(data) and not NHPotion.recipe(data))
assert(data.materials.water == 25 and data.materials.slime == nil)
assert(product.materials.magic_liquid_teleportation == 500)
assert(not NHPotion.pour(data, "water", 26) and data.materials.water == 25)
assert(NHPotion.pour(data, "water", 10) == 10 and data.materials.water == 15)
local produced = assert(NHPotion.restore(product, 0, 0))
local normal = assert(NHPotion.capture(produced))
assert(normal.materials.magic_liquid_teleportation == 500 and normal.reactions == 20)

local unknown = {kind = "potion", materials = {missing_mod_liquid = 500}}
local before = next_id
assert(not NHPotion.restore(unknown, 0, 0) and next_id == before)
missing_on_add = "slime"
assert(not NHPotion.restore(again, 0, 0) and entities[last].killed)
local mimic = EntityLoad("data/entities/items/pickup/potion_mimic.xml")
assert(not NHPotion.capture(mimic) and not entities[mimic].killed)
entities[sample].components.MaterialInventoryComponent.count_per_material_type[3] = 2.5
assert(not NHPotion.capture(sample) and not entities[sample].killed)
print("Potion round-trip, recipe quantities, unsupported flasks and failed spawn rollback passed")

local water = EntityLoad("??sav/player.xml")
function ComponentGetMembers(id) return comp(id) end
entities[water].components.ItemComponent.ui_sprite="data/ui_gfx/items/potion.png"
AddMaterialInventoryMaterial(water,"water",683)
local flask=assert(NHPotion.capture(water))
assert(assert(NHPotion.capture(assert(NHPotion.restore(flask,0,0)))).materials.water==683)
