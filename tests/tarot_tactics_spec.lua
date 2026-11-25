local root = "mods/noita_hideout/files/"
dofile(root .. "store.lua")
local products = {}
NHTransfers = {registerItem = function(kind, matches, codec)
    products[kind] = {matches = matches, capture = codec.capture, restore = codec.restore}
end}
dofile(root .. "products.lua")
local tactics = dofile(root .. "tarot_tactics.lua")

local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end
local effects = read(tactics.paths.tarot_moon[1])
for _, name in ipairs({"MANA_REGENERATION", "PROTECTION_FREEZE", "HOVER_BOOST"}) do
    assert(effects:find('effect="' .. name .. '" frames="-1"', 1, true))
end
assert(tactics.paths.tarot_magician[1] == "data/entities/misc/effect_edit_wands_everywhere.xml")

local player, items = 1, {}
local model = {kind="CharacterPlatformingComponent", pixel_gravity=350, tags={}}
local platforms = {model}
function EntityGetComponentIncludingDisabled(entity, kind, tag)
    assert(entity == player and kind == "CharacterPlatformingComponent")
    local out = {}
    for _, component in ipairs(platforms) do
        if not tag or component.tags[tag] then out[#out+1] = component end
    end
    return out
end
function EntityGetFirstComponentIncludingDisabled(entity, kind)
    if kind == "CharacterPlatformingComponent" then return platforms[1] end
    if kind == "ItemComponent" then return items[entity].item end
end
function ComponentGetValue2(component, key) return component[key] end
function ComponentSetValue2(component, key, value) component[key] = value end
function ComponentAddTag(component, tag) component.tags[tag] = true end
function ComponentHasTag(component, tag) return component.tags[tag] end
function ComponentRemoveTag(component, tag) component.tags[tag] = nil end
function EntityGetTransform(entity) assert(entity == player); return 75, 45 end
function EntityHasTag(id, tag) return items[id].tags:find("," .. tag .. ",", 1, true) ~= nil end
function EntityLoad(path, x, y)
    local xml = read(path)
    local item = {uses_remaining = assert(tonumber(xml:match('uses_remaining="(%d+)"')))}
    local id = #items + 1
    items[id] = {name = path:match("items/([^/]+)%.xml"), x=x, y=y, item=item,
        tags="," .. assert(xml:match('tags="([^"]+)"')) .. ","}
    return id
end
-- Idle bodies should never appear on the far side of this simulated wall.
function RaytracePlatforms(x, y, tx, ty) return math.max(x, tx) >= 89 end

assert(tactics.prepare(player, "tarot_moon"))
assert(model.pixel_gravity == 350, "staging must not charge gravity to an unpaid card")
tactics.commit(player, "tarot_moon", {}, false)
assert(model.pixel_gravity == 210)
tactics.commit(player, "tarot_moon", {}, true)
assert(model.pixel_gravity == 210)
model.pixel_gravity = model.pixel_gravity * .5
platforms[2] = {pixel_gravity=500, tags={}}
dofile(root .. "tarot_tactics.lua").expire(player, "tarot_moon")
assert(model.pixel_gravity == 175 and platforms[2].pixel_gravity == 500)
tactics.expire(player, "tarot_moon")
assert(model.pixel_gravity == 175)

local function stage(path, tag, attach, x, y)
    assert(not tag and not attach and x < 89, "spawn a free pickable on the player's side")
    return EntityLoad(path, x, y)
end
local expected = {magic_tube=24, fire_tube=24, frost_tube=24, shock_tube=24,
    derringer=4, flare_gun=20, sedative_launcher=20, turret_pack=4, rocket_turret_pack=4, shield_turret_pack=4}
assert(tactics.prepare(player, "tarot_magician", false, stage))
local batchSize=#items
assert(batchSize == 10)
assert(tactics.prepare(player, "tarot_magician", true, stage))
assert(#items == batchSize*2, "refresh must still deliver this use's batch")
local seen = {}
for i = 1, batchSize do
    local entity = items[i]
    local uses = assert(expected[entity.name])
    assert(not seen[entity.name] and entity.item.uses_remaining == uses)
    assert(items[i+batchSize].item.uses_remaining == uses)
    seen[entity.name] = true
    local codec = products[entity.name]
    assert(codec.matches(i))
    local record = assert(codec.capture(i))
    assert(record.count == (NHGuns.types[entity.name] and uses / NHGuns.types[entity.name].capacity or uses))
    local restored = assert(codec.restore(record, 10, 20))
    assert(items[restored].item.uses_remaining == uses, "physical warehouse round trip")
end
local spawned = 0
assert(not tactics.prepare(player, "tarot_magician", true, function(...)
    spawned = spawned + 1
    if spawned == 4 then return nil end
    return stage(...)
end))
assert(spawned == 4, "must abort staging on a missing world item")
print("Moon ownership, expiry and refresh; Magician workshop batches, terrain and physical warehouse round trips passed.")
