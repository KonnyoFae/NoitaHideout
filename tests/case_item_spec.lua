local player = 100
local s = {profile = 1, runSerial = 7, pouch = {location = "safe", doses = 2}, safe = {}}
local objects, globals = {}, {}
local px, py, id, held = 0, 0, 0, nil
local streamed, fail_stamp, fail_global, fail_spawn = true, false, false, false
local ticket_tag = "noita_hideout_case_ticket"

function GlobalsGetValue(key, default) return globals[key] or default end
function GlobalsSetValue(key, value) if not fail_global then globals[key] = value end end
function DoesWorldExistAt() return streamed end
function EntityGetIsAlive(e) return objects[e] and objects[e].alive end
function EntityGetRootEntity(e) return objects[e].root end
function EntityGetTransform(e)
    if e == player then return px, py end
    return objects[e].x, objects[e].y
end
function EntityHasTag(e, tag) return objects[e] and objects[e].tags[tag] end
function EntityAddTag(e, tag) objects[e].tags[tag] = true end
function EntityGetFirstComponentIncludingDisabled(e, kind, tag)
    assert(kind == "VariableStorageComponent" and tag == ticket_tag)
    return objects[e].comp
end
function EntityAddComponent2(e, kind, fields)
    assert(kind == "VariableStorageComponent")
    if fail_stamp then return nil end
    objects[e].comp = fields
    return fields
end
function ComponentGetValue2(comp, name) return comp[name] end
function EntityKill(e) objects[e].alive = false end
function GameKillInventoryItem(p, e)
    assert(p == player and objects[e].root == player)
    EntityKill(e)
    if held == e then held = nil end
end
function GameGetAllInventoryItems()
    local list = {}
    for e, o in pairs(objects) do
        if o.root == player and o.alive then list[#list+1] = e end
    end
    return list
end
function EntityGetWithTag(tag)
    local list = {}
    for e, o in pairs(objects) do
        if o.loaded and o.tags[tag] and o.alive and o.root == e then list[#list+1] = e end
    end
    return list
end
function EntityGetInRadiusWithTag(x, y, radius, tag)
    local list = {}
    for _, e in ipairs(EntityGetWithTag(tag)) do
        local o = objects[e]
        if (x-o.x)^2+(y-o.y)^2 <= radius^2 then list[#list+1] = e end
    end
    return list
end
NHNative = {
    spawn = function(kind, x, y)
        assert(kind == "case")
        if fail_spawn then return nil, "failed to load" end
        id = id + 1
        objects[id] = {alive = true, root = id, x = x, y = y, tags = {}, kind = kind, loaded = true}
        return id
    end,
    kind = function(e) return objects[e] and objects[e].kind end,
    held = function() return held end,
}

dofile("mods/noita_hideout/files/case_item.lua")
streamed = false
assert(NHCase.ensure(s, player, 0, 0))
assert(id == 0)
streamed = true
local function ensure() return NHCase.ensure(s, player, 0, 0) end
local function recall() return NHCase.recall(s, player, 0, 0) end
local ok, initial = ensure()
assert(ok and initial == 1 and NHCase.nearby(s, player) == initial)
assert(NHCase.accessible(s, player, initial))
assert(ensure() and id == 1)

-- Reload without any lua cache, including while the dropped case is far away.
objects[initial].x, objects[initial].loaded = 1500, false
dofile("mods/noita_hideout/files/case_item.lua")
assert(ensure() and id == 1 and not NHCase.nearby(s, player))
assert(not NHCase.accessible(s, player, initial))
px = 1500
objects[initial].loaded = true
assert(NHCase.nearby(s, player) == initial)
assert(not recall() and objects[initial].alive)
objects[initial].root = player
assert(not NHCase.accessible(s, player, initial))
held = initial
assert(NHCase.accessible(s, player, initial) and not NHCase.nearby(s, player))
px = 0
assert(not recall() and id == 1)

-- Drop it and recall at spawn. Failed replacement must leave it valid.
held = nil
objects[initial].root, objects[initial].loaded = initial, false
fail_spawn = true
assert(not recall() and objects[initial].alive)
fail_spawn = false
fail_stamp = true
assert(not recall() and not objects[id].alive and objects[initial].alive)
fail_stamp = false
fail_global = true
assert(not recall() and not objects[id].alive and objects[initial].alive)
fail_global = false
local issued, replacement = recall()
assert(issued and replacement and replacement ~= initial)
assert(NHCase.accessible(s, player, replacement) and objects[initial].alive)
objects[initial].x, objects[initial].loaded = 3, true
assert(not NHCase.accessible(s, player, initial))
assert(ensure() and not objects[initial].alive and objects[replacement].alive)

-- If the world counter was rewound while the entity was saved, adopt it.
globals = {}
local count = id
assert(ensure() and id == count and NHCase.accessible(s, player, replacement))
-- Deduplicate while retaining the held copy, even if world queries omit it.
local dupe = NHNative.spawn("case", 5, 0)
objects[dupe].comp = objects[replacement].comp
objects[dupe].tags[ticket_tag], objects[dupe].root, held = true, player, dupe
assert(ensure() and not objects[replacement].alive and NHCase.accessible(s, player, dupe))
local other = NHNative.spawn("case", 2, 0)
objects[other].kind, objects[other].tags[ticket_tag] = "unrelated", true
assert(ensure() and objects[other].alive)
-- New run: fresh case even if last run's box survived outside the current chunk.
held, s.runSerial = nil, 8
local ok_next, next_case = ensure()
assert(ok_next and next_case and NHCase.accessible(s, player, next_case))
assert(ensure() and not objects[dupe].alive and objects[other].alive)
assert(s.pouch.doses == 2 and s.pouch.location == "safe" and #s.safe == 0)
print("Case: issue, native carry/drop, same-world resume, manual recall, safe failure and new-run recovery passed.")
