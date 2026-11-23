-- Tiny engine stand-in checks material IDs, one-indexed vectors, and spawn rollback.
dofile("mods/noita_hideout/files/potion.lua")
function ModDoesFileExist(path) return path=="data/entities/items/pickup/potion.xml" end
function ModTextFileGetContent()
    return [[<Entity>
        <LuaComponent script_item_picked_up="data/scripts/items/potion_effect.lua" />
        <LuaComponent script_source_file="data/scripts/items/example_mod_tick.lua" />
        <VariableStorageComponent name="example_charges" />
    </Entity>]]
end
NHPotion.readTemplates()
local ids = {water = 2, slime = 6, magic_liquid_unstable_teleportation = 8, magic_liquid_teleportation = 9}
local next_id, last, entities = 1, nil, {}
local kinds = {"MaterialInventoryComponent", "MaterialSuckerComponent", "PotionComponent",
    "DamageModelComponent", "ItemComponent", "LuaComponent", "ExplodeOnDamageComponent",
    "VariableStorageComponent", "GameEffectComponent"}
local missing_on_add

function EntityLoad(path)
    local e = next_id
    last, next_id = e, e + 1
    entities[e] = {path = path, tags = {}, components = {}}
    for i = 1, 7 do
        local kind = kinds[i]
        entities[e].components[kind] = {
            id = 100 * e + i, barrel_size = 1000, max_capacity = -1, do_reactions = 20,
            hp = 0.5, has_been_picked_by_player = false, on_death_spill = true,
            count_per_material_type = {},
        }
    end
    entities[e].components.LuaComponent.script_item_picked_up = "data/scripts/items/potion_effect.lua"
    entities[e].components.LuaComponent.remove_after_executed = true
    return e
end
function EntityGetFirstComponentIncludingDisabled(e, kind, tag)
    local c = entities[e].components[kind]
    if c and (not tag or c._tags == tag) then return c.id end
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
function ComponentGetMembers(id) return comp(id) end
function ComponentGetTypeName(id) return kinds[id % 100] end
function ComponentHasTag(id,tag) return comp(id)._tags==tag end
function ComponentGetIsEnabled(id) return not comp(id).disabled end
function EntityGetAllComponents(e)
    local result = {}
    for _, c in pairs(entities[e].components) do result[#result+1] = c.id end
    return result
end
function EntityAddComponent2(e, kind, fields)
    for i, name in ipairs(kinds) do
        if name == kind then
            fields.id = 100 * e + i
            entities[e].components[kind] = fields
            return fields.id
        end
    end
    error("Unknown fixture component: " .. kind)
end
function GameGetPotionColorUint() return 0xff0011ff end
function EntityGetFilename(e) return entities[e].path end
function EntityGetName(e) return entities[e].name or "" end
function EntityHasTag(e, tag) return entities[e].tags[tag] or false end
function EntityAddTag(e, tag) entities[e].tags[tag] = true end
function EntityGetTags(e)
    local result = {}
    for tag in pairs(entities[e].tags) do result[#result+1] = tag end
    return table.concat(result, ",")
end
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

assert(data.color==0xff0011ff and NHPotion.contentsColor(data)==data.color)
assert(not NHPotion.contentsColor({materials={},color=data.color}))

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
entities[water].components.ItemComponent.ui_sprite="data/ui_gfx/items/potion.png"
AddMaterialInventoryMaterial(water,"water",683)
local flask=assert(NHPotion.capture(water))
assert(assert(NHPotion.capture(assert(NHPotion.restore(flask,0,0)))).materials.water==683)

missing_on_add=nil
for _,variant in ipairs({"powder_stash","jar","jar_of_urine","potion_aggressive"}) do
    local path="data/entities/items/pickup/"..variant..".xml"
    local container=EntityLoad(path)
    AddMaterialInventoryMaterial(container,"slime",37)
    local record=assert(NHPotion.capture(container))
    assert(record.variant==variant and record.materials.slime==37)
    local rebuilt=assert(NHPotion.restore(record,0,0))
    assert(entities[rebuilt].path==path)
    entities[rebuilt].path="??sav/player.xml"
    local saved=assert(NHPotion.capture(rebuilt))
    assert(saved.variant==variant and saved.materials.slime==37)
end

-- Full discovery rewards keep both capacity and contents after a physical round trip.
for _,reward in ipairs({
    {kind="potion",materials={water=1000},capacity=1000},
    {kind="potion",variant="powder_stash",materials={slime=1500},capacity=1500},
}) do
    local rebuilt=assert(NHPotion.restore(reward,0,0))
    local saved=assert(NHPotion.capture(rebuilt))
    assert(saved.capacity==reward.capacity and NHPotion.fillLevel(saved)==reward.capacity)
end

-- Exercise the public transfer path, including ownership, journaling and the restored flask.
do
    dofile("mods/noita_hideout/files/store.lua")
    dofile("mods/noita_hideout/files/transfers.lua")
    local player, held = EntityLoad("data/entities/player.xml"), nil
    entities[player].components = {}
    function EntityGetIsAlive(e) return entities[e] and not entities[e].killed end
    function EntityGetParent(e) return entities[e].parent or 0 end
    function EntityGetRootEntity(e) return entities[e].parent or e end
    function GameGetAllInventoryItems() return {held} end
    function EntityGetTransform() return 0, 0 end
    function GameGetFrameNum() return 42 end
    local settings,flags,globals = {},{},{}
    function ModSettingGet(k) return settings[k] end
    function ModSettingSet(k,v) settings[k]=v end
    function HasFlagPersistent(k) return flags[k] end
    function AddFlagPersistent(k) flags[k]=true end
    function GlobalsGetValue(k,v) return globals[k] or v end
    function GlobalsSetValue(k,v) globals[k]=v end
    local state = assert(NHStore.load())
    NHStore.newRun(state)
    assert(NHStore.commit(state))
    local originalRevision, originalId = state.revision, state.nextItemId
    local function bottle(path)
        held = EntityLoad(path)
        entities[held].parent = player
        entities[held].components.ItemComponent.ui_sprite = "data/ui_gfx/items/potion.png"
        AddMaterialInventoryMaterial(held, "water", 683)
        return held
    end
    local function refused(reason, detail)
        for _,dest in ipairs({"warehouse","safe","docks"}) do
            local ok, why = NHTransfers.deposit(state, player, dest, held)
            assert(not ok, dest.." accepted a flask with "..detail)
            assert(why:find(reason,1,true) and why:find(detail,1,true), why)
        end
        assert(EntityGetIsAlive(held) and EntityGetParent(held)==player and not entities[held].removed_from)
        assert(entities[held].components.MaterialInventoryComponent.count_per_material_type[3]==683)
        assert(not EntityHasTag(held,"noita_hideout_transfer_item"))
        assert(#state.warehouse==0 and state.revision==originalRevision and state.nextItemId==originalId)
    end
    local script = "mods/example/flask_tick.lua"
    for _,path in ipairs({"data/entities/items/pickup/potion_water.xml","??sav/player.xml",
        "data/entities/items/pickup/jar.xml","data/entities/items/pickup/powder_stash.xml"}) do
        local e = bottle(path)
        entities[e].components.LuaComponent.script_source_file = script
        refused("script",script)
        assert(entities[e].components.LuaComponent.script_source_file==script)
    end
    local e = bottle("data/entities/items/pickup/potion_empty.xml")
    local patched = "data/scripts/items/example_mod_tick.lua"
    entities[e].components.LuaComponent.script_throw_item = patched
    refused("script",patched)
    e = bottle("data/entities/items/pickup/potion_water.xml")
    entities[e].components.LuaComponent.remove_after_executed = false
    refused("script","remove_after_executed")
    e = bottle("data/entities/items/pickup/potion.xml")
    entities[e].components.LuaComponent.disabled=true
    refused("script","disabled")
    e = bottle("data/entities/items/pickup/potion_empty.xml")
    EntityAddComponent2(e,"VariableStorageComponent",{name="example_charges",value_int=3})
    refused("state","example_charges")
    assert(entities[e].components.VariableStorageComponent.value_int==3)
    e = bottle("data/entities/items/pickup/potion_milk.xml")
    EntityAddComponent2(e,"VariableStorageComponent",{name="potion_material",value_string="milk",value_int=9})
    refused("state","potion_material")
    entities[e].components.VariableStorageComponent.value_int=0
    entities[e].components.VariableStorageComponent.value_string="quest_stage"
    refused("state","potion_material")
    e = bottle("data/entities/items/pickup/potion.xml")
    EntityAddComponent2(e,"GameEffectComponent",{effect="CUSTOM"})
    refused("component","GameEffectComponent")
    e = bottle("data/entities/items/pickup/potion.xml")
    EntityAddTag(e,"example_quest_item")
    refused("tag","example_quest_item")

    e = bottle("data/entities/items/pickup/potion_water.xml")
    AddMaterialInventoryMaterial(e,"slime",17)
    entities[e].components.MaterialSuckerComponent.barrel_size=1500
    entities[e].components.MaterialInventoryComponent.do_reactions=0
    entities[e].components.DamageModelComponent.hp=0.25
    EntityAddTag(e,"extra_potion_capacity")
    assert(NHTransfers.deposit(state,player,"warehouse",e))
    assert(not EntityGetIsAlive(e) and #state.warehouse==1)
    local ok, restored = NHTransfers.withdraw(state,player,1,"warehouse")
    assert(ok and restored~=e and EntityGetIsAlive(restored) and #state.warehouse==0)
    local record = assert(NHPotion.capture(restored))
    assert(record.materials.water==683 and record.materials.slime==17 and record.capacity==1500)
    assert(record.reactions==0 and record.hp==0.25 and record.extra_capacity)
    print("Warehouse refused modified flasks intact and round-tripped a native mixed flask including its transfer receipt.")
end

-- Recolour an older stored mix and a reloaded pouch using an inert native inventory.
local probe,probes,observed=nil,0,nil
function EntityCreateNew()
    probes=probes+1
    probe=100000+probes
    return probe
end
function EntityAddComponent2(entity,kind,settings)
    assert(entity==probe)
    if kind=="MaterialInventoryComponent" then assert(settings.on_death_spill==false and settings.do_reactions==0) end
    return 2
end
function AddMaterialInventoryMaterial(entity,name,n)
    assert(entity==probe)
    observed=observed or {}
    observed[name]=n
end
function GameGetPotionColorUint(entity)
    assert(entity==probe)
    return 0xffa02010
end
function EntityKill(entity) assert(entity==probe); probe=nil end
local legacy={materials={slime=21,water=47}}
assert(NHPotion.contentsColor(legacy)==0xffa02010 and observed.slime==21 and observed.water==47 and not probe)
local powder={variant="powder_stash",materials={slime=5}}
assert(NHPotion.contentsColor(powder)==0xffa02010)
assert(NHPotion.contentsColor(powder)==0xffa02010 and probes==2 and not probe)
