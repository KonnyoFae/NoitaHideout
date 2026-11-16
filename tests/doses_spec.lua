local player, frame = 1, 200
local entities, next_id, selected = {}, 20, nil
local settings, flags, globals = {}, {}, {}
local world_loaded, reject_spawn, reject_marker, reject_commit = true, false, false, false
entities[player] = {x = 25, y = 40, alive = true}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key, value) if not reject_commit then settings[key] = value end end
function HasFlagPersistent(key) return flags[key] == true end
function AddFlagPersistent(key) flags[key] = true end
function GlobalsGetValue(key, default) return globals[key] or default end
function GlobalsSetValue(key, value) globals[key] = value end
function GameGetFrameNum() return frame end
function EntityGetTransform(id) return entities[id].x, entities[id].y end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive end
function EntityGetRootEntity(id) return entities[id].root end
function EntityKill(id) entities[id].alive = false end
function GameKillInventoryItem(owner, id)
    assert(EntityGetRootEntity(id) == owner)
    if selected == id then selected = nil end
    EntityKill(id)
end
function DoesWorldExistAt() return world_loaded end
function EntityAddComponent2(id, kind, fields)
    assert(kind == "VariableStorageComponent")
    if reject_marker then return nil end
    entities[id].marker = fields
    return fields
end
function EntityGetFirstComponentIncludingDisabled(id, kind, tag)
    if kind == "VariableStorageComponent" and tag == "noita_hideout_dose_token" then return entities[id].marker end
end
function ComponentGetValue2(c, k) return c[k] end
function GameGetAllInventoryItems(owner)
    local found = {}
    for id, item in pairs(entities) do
        if item.root == owner and item.alive then found[#found + 1] = id end
    end
    return found
end
function EntityGetWithTag(tag)
    assert(tag == "noita_hideout_dose" or tag == "noita_hideout_pouch")
    local found = {}
    for id, item in pairs(entities) do
        if item.kind and tag == "noita_hideout_" .. item.kind and item.alive then found[#found + 1] = id end
    end
    return found
end
NHNative = {}
function NHNative.kind(id) return entities[id].kind end
function NHNative.held(owner) return selected end
function NHNative.spawn(kind,x,y)
    if reject_spawn then return nil, "spawn failed" end
    next_id = next_id + 1
    entities[next_id] = {kind = kind, x = x, y = y, root = next_id, alive = true}
    return next_id
end
local function pick(id) entities[id].root = player; selected = id end

dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/doses.lua")
local s = assert(NHStore.load()) -- earlier archive without an issued-dose ledger
NHStore.newRun(s)
assert(NHStore.commit(s) and s.pouch.doses == 2 and not s.issuedDoses)
reject_spawn = true
assert(not NHDoses.withdraw(s,player) and s.pouch.doses == 2)
reject_spawn, reject_marker = false, true
assert(not NHDoses.withdraw(s,player) and not EntityGetIsAlive(next_id) and s.pouch.doses == 2)
reject_marker, reject_commit = false, true
assert(not NHDoses.withdraw(s,player) and not EntityGetIsAlive(next_id) and s.pouch.doses == 2)
reject_commit = false
local ok, id = NHDoses.withdraw(s,player)
assert(ok and EntityGetIsAlive(id) and s.pouch.doses == 1)
assert(not NHDoses.consume(s,player,id) and not NHDoses.deposit(s,player,id))
pick(id)
selected = nil
assert(not NHDoses.consume(s,player,id))
selected = id
reject_commit = true
assert(not NHDoses.consume(s,player,id) and EntityGetIsAlive(id))
assert(not NHDoses.deposit(s,player,id) and EntityGetIsAlive(id) and s.pouch.doses == 1)
reject_commit = false
local ok2, duplicate = NHDoses.withdraw(s,player)
assert(ok2 and s.pouch.doses == 0)
assert(not NHDoses.withdraw(s,player))
local extra = NHNative.spawn("dose",25,40)
entities[extra].marker = entities[id].marker
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(extra) and EntityGetIsAlive(id))
assert(NHDoses.consume(s,player,id) and NHDoses.remaining(s,id)==2)
assert(NHDoses.consume(s,player,id) and NHDoses.remaining(s,id)==1)
assert(NHDoses.consume(s,player,id) and not EntityGetIsAlive(id))
assert(not NHDoses.consume(s,player,id))
-- An engine world rollback restores an already-used syringe. A fresh profile
-- load must reject both injecting and returning it to the case.
s = assert(NHStore.load())
entities[id].alive = true
pick(id)
assert(not NHDoses.consume(s,player,id) and not NHDoses.deposit(s,player,id) and s.pouch.doses == 0)
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(id))
assert(not NHDoses.deposit(s,player,duplicate))
pick(duplicate)
assert(NHDoses.deposit(s,player,duplicate) and s.pouch.doses == 1)
assert(not EntityGetIsAlive(duplicate))
entities[duplicate].alive, globals = true, {}
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(duplicate) and s.pouch.doses == 1)

-- Normal drop/destruction is not refunded; lost world-side receipt as well
-- as physical entity permits one refund after the delivery area is loaded.
local ok3, missing = NHDoses.withdraw(s,player)
assert(ok3 and s.pouch.doses == 0)
EntityKill(missing)
assert(NHDoses.reconcile(s,player) and s.pouch.doses == 0)
globals, world_loaded = {}, false
assert(NHDoses.reconcile(s,player) and s.pouch.doses == 0)
world_loaded = true
reject_commit = true
assert(not NHDoses.reconcile(s,player) and s.pouch.doses == 0)
reject_commit = false
assert(NHDoses.reconcile(s,player) and s.pouch.doses == 1)
assert(NHDoses.reconcile(s,player) and s.pouch.doses == 1)
entities[missing].alive = true
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(missing))

-- Debug restock replaces the pouch, not an independently issued dose.
local ok4, outside = NHDoses.withdraw(s,player)
assert(ok4)
assert(NHStore.restock(s)); assert(NHStore.commit(s))
pick(outside)
assert(NHDoses.deposit(s,player,outside) and s.pouch.doses == 3)
local ok5, lost = NHDoses.withdraw(s,player)
assert(ok5 and s.pouch.doses == 2)
assert(NHStore.endRun(s,s.runSerial)); assert(NHStore.commit(s))
assert(not NHDoses.withdraw(s,player) and s.pouch.doses == 2)
NHStore.newRun(s); assert(NHStore.commit(s))
pick(lost)
assert(not NHDoses.consume(s,player,lost))
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(lost) and s.pouch.doses == 2)
print("Doses: native ownership, deposit/consume, duplicate and old-run rejection, commit failures and replay passed.")

local room=assert(NHStore.load())
NHStore.newRun(room)
assert(NHStore.restock(room))
assert(NHStore.commit(room))
local free=assert(NHStore.freeSafeSlot(room))
assert(not NHDoses.moveDose(room,room.pouch.slot,true))
assert(NHDoses.moveDose(room,free,true))
assert(room.pouch.doses==1 and room.safe[1].slot==free)
assert(NHDoses.moveDose(room,free,false))
assert(room.pouch.doses==2 and #room.safe==0)

-- Both full injectors can share a cell. Equal wear still cannot merge.
assert(NHDoses.moveCell(room,1,4))
assert(room.pouch.cells[4].count==1 and room.pouch.cells[1].count==1)
assert(NHDoses.moveCell(room,4,1) and room.pouch.cells[1].count==2)
local _,used=NHDoses.withdraw(room,player,nil,nil,nil,1)
pick(used)
assert(NHDoses.consume(room,player,used))
assert(NHDoses.remaining(room,used)==2 and EntityGetIsAlive(used))
assert(not NHDoses.deposit(room,player,used,nil,1) and EntityGetIsAlive(used))
assert(NHDoses.deposit(room,player,used,nil,4))
assert(room.pouch.cells[4].remaining==2 and room.pouch.cells[1].remaining==3)
local _,other=NHDoses.withdraw(room,player,nil,nil,nil,1)
pick(other)
assert(NHDoses.consume(room,player,other))
assert(not NHDoses.deposit(room,player,other,nil,4))
assert(NHDoses.deposit(room,player,other,nil,2))
room=assert(NHStore.load())
assert(not NHDoses.moveCell(room,2,4) and room.pouch.cells[4].count==1)
assert(NHDoses.moveDose(room,free,true,4))
assert(room.safe[1].item.remaining==2)
assert(not NHDoses.moveDose(room,free,true,2))
local _,returned=NHDoses.withdraw(room,player,nil,nil,free)
pick(returned)
assert(NHDoses.remaining(room,returned)==2)
assert(NHDoses.consume(room,player,returned))
assert(NHDoses.remaining(room,returned)==1)
assert(NHDoses.consume(room,player,returned) and not EntityGetIsAlive(returned))
assert(NHStore.restock(room) and NHStore.commit(room))
assert(NHDoses.moveDose(room,free,true,1) and NHDoses.moveDose(room,free,true,1))
assert(room.safe[1].item.count==2)
assert(NHDoses.moveDose(room,free,false,3))
assert(room.safe[1].item.count==1 and room.pouch.cells[3].remaining==3)
