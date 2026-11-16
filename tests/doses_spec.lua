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
    if reject_marker=="zero" then return 0 end
    if reject_marker then return nil end
    entities[id].marker = fields
    return fields
end
function EntityGetFirstComponentIncludingDisabled(id, kind, tag)
    local marker=entities[id].marker
    if kind=="VariableStorageComponent" and marker and tag==marker._tags then return marker end
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
function NHNative.spawn(kind,x,y,subtype)
    if reject_spawn then return nil, "spawn failed" end
    next_id = next_id + 1
    entities[next_id] = {kind = kind, subtype=subtype, x = x, y = y, root = next_id, alive = true}
    return next_id
end
local function pick(id) entities[id].root = player; selected = id end

dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/doses.lua")
local function starter(s) return s.pouches[s.starterPouchId] end
local function withdrawStarter(s,cell)
    return NHDoses.withdraw(s,player,nil,nil,nil,cell,nil,s.starterPouchId)
end
local function depositStarter(s,id,cell)
    return NHDoses.deposit(s,player,id,nil,cell,nil,s.starterPouchId)
end
local s = assert(NHStore.load()) -- earlier archive without an issued-dose ledger
NHStore.newRun(s)
assert(NHStore.commit(s) and starter(s).doses == 2 and not s.issuedDoses)
reject_spawn = true
assert(not withdrawStarter(s) and starter(s).doses == 2)
reject_spawn, reject_marker = false, true
assert(not withdrawStarter(s) and not EntityGetIsAlive(next_id) and starter(s).doses == 2)
reject_marker, reject_commit = false, true
assert(not withdrawStarter(s) and not EntityGetIsAlive(next_id) and starter(s).doses == 2)
reject_commit = false
local ok, id = withdrawStarter(s)
assert(ok and EntityGetIsAlive(id) and starter(s).doses == 1)
assert(not NHDoses.consume(s,player,id) and not depositStarter(s,id))
pick(id)
selected = nil
assert(not NHDoses.consume(s,player,id))
selected = id
reject_commit = true
assert(not NHDoses.consume(s,player,id) and EntityGetIsAlive(id))
assert(not depositStarter(s,id) and EntityGetIsAlive(id) and starter(s).doses == 1)
reject_commit = false
local ok2, duplicate = withdrawStarter(s)
assert(ok2 and starter(s).doses == 0)
assert(not withdrawStarter(s))
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
assert(not NHDoses.consume(s,player,id) and not depositStarter(s,id) and starter(s).doses == 0)
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(id))
assert(not depositStarter(s,duplicate))
pick(duplicate)
assert(depositStarter(s,duplicate) and starter(s).doses == 1)
assert(not EntityGetIsAlive(duplicate))
entities[duplicate].alive, globals = true, {}
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(duplicate) and starter(s).doses == 1)

-- Normal drop/destruction is not refunded; lost world-side receipt as well
-- as physical entity permits one refund after the delivery area is loaded.
local ok3, missing = withdrawStarter(s)
assert(ok3 and starter(s).doses == 0)
EntityKill(missing)
assert(NHDoses.reconcile(s,player) and starter(s).doses == 0)
globals, world_loaded = {}, false
assert(NHDoses.reconcile(s,player) and starter(s).doses == 0)
world_loaded = true
reject_commit = true
assert(not NHDoses.reconcile(s,player) and starter(s).doses == 0)
reject_commit = false
assert(NHDoses.reconcile(s,player) and starter(s).doses == 1)
assert(NHDoses.reconcile(s,player) and starter(s).doses == 1)
entities[missing].alive = true
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(missing))

-- Debug restock replaces the pouch, not an independently issued dose.
local ok4, outside = withdrawStarter(s)
assert(ok4)
assert(NHStore.restock(s)); assert(NHStore.commit(s))
pick(outside)
assert(depositStarter(s,outside) and starter(s).doses == 3)
local ok5, lost = withdrawStarter(s)
assert(ok5 and starter(s).doses == 2)
assert(NHStore.endRun(s,s.runSerial)); assert(NHStore.commit(s))
assert(not withdrawStarter(s) and starter(s).doses == 2)
NHStore.newRun(s); assert(NHStore.commit(s))
pick(lost)
assert(not NHDoses.consume(s,player,lost))
assert(NHDoses.reconcile(s,player) and not EntityGetIsAlive(lost) and starter(s).doses == 2)
print("Doses: native ownership, deposit/consume, duplicate and old-run rejection, commit failures and replay passed.")

local room=assert(NHStore.load())
NHStore.newRun(room)
assert(NHStore.restock(room))
assert(NHStore.commit(room))
local free=assert(NHStore.freeSafeSlot(room))
assert(not NHDoses.moveDose(room,starter(room).slot,true,nil,nil,room.starterPouchId))
assert(NHDoses.moveDose(room,free,true,nil,nil,room.starterPouchId))
assert(starter(room).doses==1 and room.safe[1].slot==free)
assert(NHDoses.moveDose(room,free,false,nil,nil,room.starterPouchId))
assert(starter(room).doses==2 and #room.safe==0)

-- Both full injectors can share a cell. Equal wear still cannot merge.
assert(NHDoses.moveCell(room,1,4,room.starterPouchId))
assert(starter(room).cells[4].count==1 and starter(room).cells[1].count==1)
assert(NHDoses.moveCell(room,4,1,room.starterPouchId) and starter(room).cells[1].count==2)
local _,used=withdrawStarter(room,1)
pick(used)
assert(NHDoses.consume(room,player,used))
assert(NHDoses.remaining(room,used)==2 and EntityGetIsAlive(used))
assert(not depositStarter(room,used,1) and EntityGetIsAlive(used))
assert(depositStarter(room,used,4))
assert(starter(room).cells[4].remaining==2 and starter(room).cells[1].remaining==3)
local _,other=withdrawStarter(room,1)
pick(other)
assert(NHDoses.consume(room,player,other))
assert(not depositStarter(room,other,4))
assert(depositStarter(room,other,2))
room=assert(NHStore.load())
assert(not NHDoses.moveCell(room,2,4,room.starterPouchId) and starter(room).cells[4].count==1)
assert(NHDoses.moveDose(room,free,true,4,nil,room.starterPouchId))
assert(room.safe[1].item.remaining==2)
assert(not NHDoses.moveDose(room,free,true,2,nil,room.starterPouchId))
local _,returned=NHDoses.withdraw(room,player,nil,nil,free)
pick(returned)
assert(NHDoses.remaining(room,returned)==2)
assert(NHDoses.consume(room,player,returned))
assert(NHDoses.remaining(room,returned)==1)
assert(NHDoses.consume(room,player,returned) and not EntityGetIsAlive(returned))
assert(NHStore.restock(room) and NHStore.commit(room))
assert(NHDoses.moveDose(room,free,true,1,nil,room.starterPouchId) and NHDoses.moveDose(room,free,true,1,nil,room.starterPouchId))
assert(room.safe[1].item.count==2)
assert(NHDoses.moveDose(room,free,false,3,nil,room.starterPouchId))
assert(room.safe[1].item.count==1 and starter(room).cells[3].remaining==3)

assert(NHStore.restock(room) and NHStore.commit(room))
local safe_count=room.safe[1].item.count
for i=1,2 do
    local ok,id=withdrawStarter(room,1)
    assert(ok)
    pick(id)
    assert(NHDoses.deposit(room,player,id,3,nil,"warehouse"))
end
room=assert(NHStore.load())
assert(room.warehouse[1].item.count==2)
assert(not NHDoses.withdraw(room,player,function() return false end,nil,3,nil,"warehouse"))
local ok,id=NHDoses.withdraw(room,player,nil,nil,3,nil,"warehouse")
assert(ok and room.warehouse[1].item.count==1 and room.safe[1].item.count==safe_count)
pick(id)
assert(NHDoses.consume(room,player,id))
assert(not NHDoses.deposit(room,player,id,3,nil,"warehouse") and EntityGetIsAlive(id))
assert(NHDoses.deposit(room,player,id,4,nil,"warehouse"))
room=assert(NHStore.load())
assert(room.warehouse[2].item.remaining==2)
local ok,worn=NHDoses.withdraw(room,player,nil,nil,4,nil,"warehouse")
assert(ok and NHDoses.remaining(room,worn)==2)

-- Two crafted bags can contain different durability at the same cell.
settings,flags,globals={},{},{}
local bags=assert(NHStore.load())
NHStore.newRun(bags)
local a=NHPouches.create(bags,"warehouse",1)
local b=NHPouches.create(bags,"warehouse",2,0,3)
assert(a~=b and NHStore.commit(bags))
assert(bags.pouches[a].doses==0 and bags.pouches[b].doses==0)
assert(NHDoses.moveCell(bags,1,1,bags.starterPouchId,a))
local _,syringe=withdrawStarter(bags,1)
pick(syringe)
assert(NHDoses.consume(bags,player,syringe))
assert(NHDoses.deposit(bags,player,syringe,nil,1,nil,b))
reject_commit=true
assert(not NHDoses.moveCell(bags,1,2,b,a))
reject_commit=false
bags=assert(NHStore.load())
assert(bags.pouches[a].cells[1].remaining==3 and bags.pouches[b].cells[1].remaining==2)
assert(not NHDoses.moveCell(bags,1,1,b,a))
assert(NHDoses.moveCell(bags,1,2,b,a) and bags.pouches[b].doses==0)
assert(NHDoses.moveCell(bags,2,1,a,b))
local function collect(id) pick(id); return true end
local okA,itemA=NHDoses.takePouch(bags,player,collect,a)
local okB,itemB=NHDoses.takePouch(bags,player,collect,b)
assert(okA and okB and NHDoses.isPouch(bags,itemA)==a and NHDoses.isPouch(bags,itemB)==b)
assert(entities[itemB].subtype==3 and bags.pouches[b].tier==3)
assert(NHDoses.moveCell(bags,1,12,b) and not NHDoses.moveCell(bags,12,5,b,a))
assert(NHDoses.moveCell(bags,12,1,b))
assert(not NHDoses.withdraw(bags,player,nil,itemA,nil,1,nil,b))
local shadow=NHNative.spawn("pouch",25,40)
entities[shadow].marker=entities[itemB].marker
assert(NHDoses.reconcile(bags,player) and not EntityGetIsAlive(shadow))
assert(EntityGetIsAlive(itemA) and EntityGetIsAlive(itemB))
local drawn,rollbackDose=NHDoses.withdraw(bags,player,nil,itemB,nil,1,nil,b)
assert(drawn and NHDoses.remaining(bags,rollbackDose)==2)
EntityKill(rollbackDose)
globals={}
assert(NHDoses.reconcile(bags,player))
assert(bags.pouches[b].cells[1].remaining==2 and bags.pouches[a].cells[1].remaining==3)
assert(NHDoses.storePouch(bags,player,itemB,2,"warehouse"))
assert(NHStore.restock(bags) and NHStore.commit(bags))
assert(bags.pouches[b].doses==1 and bags.pouches[a].doses==1)
assert(NHStore.endRun(bags,bags.runSerial) and NHStore.commit(bags))
bags=assert(NHStore.load())
assert(not bags.pouches[a] and bags.pouches[b].cells[1].remaining==2 and starter(bags).doses==2)
assert(NHPouches.at(bags,"warehouse",2).id==b)

-- Two missing deliveries that last occupied the same slot must refund separately.
NHStore.newRun(bags)
assert(NHStore.commit(bags))
local took,first=NHDoses.takePouch(bags,player,collect,b)
assert(took)
local c=NHPouches.create(bags,"warehouse",2)
assert(NHStore.commit(bags))
local took2,second=NHDoses.takePouch(bags,player,collect,c)
assert(took2)
EntityKill(first)
EntityKill(second)
globals={}
assert(NHDoses.reconcile(bags,player))
bags=assert(NHStore.load())
assert(bags.pouches[b].location=="warehouse" and bags.pouches[c].location=="warehouse")
assert(bags.pouches[b].tier==3 and bags.pouches[c].tier==1)
assert(bags.pouches[b].slot~=bags.pouches[c].slot and bags.pouches[b].cells[1].remaining==2)
assert(bags.pouches[c].doses==0)

-- Failed native marker creation can return zero. The provisional entity is
-- discarded, its bag stays stored, and a subsequent delivery can succeed.
local original=bags.starterPouchId
local revision=bags.revision
reject_marker="zero"
assert(not NHDoses.takePouch(bags,player,collect,original))
assert(not EntityGetIsAlive(next_id) and bags.revision==revision and starter(bags).location=="safe")
reject_marker=false
local delivered,groundBag=NHDoses.takePouch(bags,player,collect,original)
assert(delivered)
entities[groundBag].root=groundBag
selected=nil
assert(not NHDoses.storePouch(bags,player,groundBag,1,"safe"))
assert(NHDoses.reconcile(bags,player) and EntityGetIsAlive(groundBag))
assert(NHDoses.isPouch(bags,groundBag)==original and starter(bags).location=="bag")
pick(groundBag)
local issued,loose=NHDoses.withdraw(bags,player,collect,groundBag,nil,1,nil,original)
assert(issued and NHDoses.consume(bags,player,loose))
assert(NHStore.restock(bags) and NHStore.commit(bags))
assert(bags.starterPouchId~=original and not bags.pouches[original])
assert(NHDoses.reconcile(bags,player) and not EntityGetIsAlive(groundBag) and EntityGetIsAlive(loose))
reject_commit=true
assert(not NHDoses.deposit(bags,player,loose,nil,1,nil,c))
assert(bags.pouches[c].doses==0 and NHDoses.remaining(bags,loose)==2)
reject_commit=false
assert(NHDoses.deposit(bags,player,loose,nil,1,nil,c))
assert(not EntityGetIsAlive(loose) and bags.pouches[c].cells[1].remaining==2)

local older={nextItemId=47,pouch={location="bag",token="1/1/45",slot=2,doses=1,cells={{remaining=1,count=1}}},
    issuedDoses={before={cell=2,remaining=2},loose={safeSlot=1,remaining=1}}}
NHPouches.adopt(older)
assert(older.pouches[47].token=="1/1/45" and older.pouches[47].cells[1].remaining==1)
assert(older.starterPouchId==47 and older.nextItemId==48 and older.issuedDoses.before.pouchId==47)
assert(not older.pouch and not older.issuedDoses.loose.pouchId)
NHPouches.adopt(older)
assert(older.nextItemId==48)
print("Doses: independent bag identity, durability, issued entities, recovery and death passed.")

-- Shop, pouch, physical item and rollback must all retain the chemical subtype.
local mixed=assert(NHStore.load())
local typed=NHPouches.create(mixed,"warehouse",NHStore.freeSlot(mixed,"warehouse",nil,"pouch"))
local function put(kind,cell)
    return NHStore.putPouchDose(mixed.pouches[typed],3,cell,kind)
end
assert(put("lightning",1) and put("lightning",1) and not put("fire",1))
assert(put("frost",2) and put("healing",3) and put(nil,4) and put("fire",4))
assert(NHStore.commit(mixed))
mixed=assert(NHStore.load())
assert(mixed.pouches[typed].cells[1].subtype=="lightning" and mixed.pouches[typed].cells[1].count==2)
assert(not NHDoses.moveCell(mixed,2,1,typed) and not NHDoses.moveCell(mixed,4,3,typed))
local occupied=assert(NHStore.freeSlot(mixed,"warehouse",nil,"dose"))
assert(NHDoses.moveDose(mixed,occupied,true,1,"warehouse",typed))
assert(not NHDoses.moveDose(mixed,occupied,true,2,"warehouse",typed))
assert(NHDoses.moveDose(mixed,occupied,true,1,"warehouse",typed))
mixed.bankGold=160
dofile("mods/noita_hideout/files/bank.lua")
assert(NHStore.buyGood(mixed,{id="injector"}))
assert(NHStore.commit(mixed))
local stack=mixed.warehouse[NHStore.slotIndex(mixed,"warehouse",occupied,"dose")]
assert(stack.item.subtype=="lightning" and stack.item.count==2)
assert(NHDoses.moveDose(mixed,occupied,false,1,"warehouse",typed))
local okTyped,physical=NHDoses.withdraw(mixed,player,collect,nil,nil,1,nil,typed)
assert(okTyped and select(2,NHDoses.remaining(mixed,physical))=="lightning")
assert(NHDoses.consume(mixed,player,physical) and NHDoses.remaining(mixed,physical)==2)
assert(not NHDoses.deposit(mixed,player,physical,occupied,nil,"warehouse"))
assert(NHDoses.deposit(mixed,player,physical,nil,1,nil,typed))
mixed=assert(NHStore.load())
assert(mixed.pouches[typed].cells[1].remaining==2 and mixed.pouches[typed].cells[1].subtype=="lightning")
local okMissing,lostTyped=NHDoses.withdraw(mixed,player,nil,nil,nil,1,nil,typed)
assert(okMissing)
EntityKill(lostTyped)
globals={}
assert(NHDoses.reconcile(mixed,player))
assert(mixed.pouches[typed].cells[1].subtype=="lightning" and mixed.pouches[typed].cells[1].remaining==2)
print("Doses: mixed typed stacks, legacy fire, shop isolation, use and rollback passed.")
