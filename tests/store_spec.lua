local settings, profiles = {}, {{}, {}, {}}
local selected = 1
local blocked_key, blocked_value, fail_after
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k, v)
    if k == blocked_key and v == blocked_value then
        if fail_after then settings[k] = v end
        error("injected write failure")
    end
    settings[k] = v
end
function HasFlagPersistent(k) return profiles[selected][k] == true end
function AddFlagPersistent(k) profiles[selected][k] = true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local function load()
    return assert(NHStore.load())
end
local function save(s)
    assert(NHStore.commit(s))
    return load()
end

local function starter(s) return s.pouches[s.starterPouchId] end
local function advance(s,run,progress,checkpoint)
    return NHStore.advanceProduction(s,{run=run,orderId=s.order and s.order.id or false,progress=progress,checkpoint=checkpoint})
end

local state = load()
assert(state.profile == 1 and state.revision == 0)
local first = NHStore.newRun(state)
assert(first == 1 and starter(state).location == "safe" and starter(state).doses == 2)
state.safe[1] = {id = state.nextItemId, item = {kind = "wand", name = "Varpuluuta"}}
state.nextItemId = state.nextItemId + 1
assert(NHStore.takePouchDose(starter(state),1))
state = save(state)
assert(starter(state).doses == 1)
assert(NHStore.endRun(state, first))
assert(not NHStore.endRun(state, first))
assert(not advance(state,first,100,"mountain-1"))
state = save(state)
assert(state.closedThrough == first and starter(state).doses == 1)
assert(#state.safe == 1 and state.safe[1].item.name == "Varpuluuta")
local second = NHStore.newRun(state)
starter(state).location = "bag"
state = save(state)
assert(starter(state).location == "bag" and starter(state).doses == 1)
-- Starting a fresh world also settles an abandoned run when no death callback ran.
local third = NHStore.newRun(state)
assert(not NHStore.endRun(state, second))
assert(not starter(state))
assert(NHStore.restock(state))
starter(state).location = "bag"
assert(NHStore.endRun(state, third))
assert(not starter(state))
state = save(state)

local fourth = NHStore.newRun(state)
assert(advance(state,fourth,0,"mountain-1"))
assert(not advance(state,fourth,0,"mountain-1"))
assert(not NHStore.startOrder(state))
local potion = {kind = "potion", materials = {
    magic_liquid_unstable_teleportation = 250, slime = 250, water = 20
}}
state.warehouse = {{id = state.nextItemId, item = potion}}
state.nextItemId = state.nextItemId + 1
assert(not NHStore.startOrder(state)) -- Bottled and docked ingredients are not loose stock.
state.materials={magic_liquid_unstable_teleportation=300,slime=250,water=20,magic_liquid_teleportation=12}
assert(NHStore.startOrder(state))
assert(state.materials.magic_liquid_unstable_teleportation==50 and state.materials.slime==nil)
assert(potion.materials.slime==250 and not NHStore.startOrder(state))
assert(not advance(state,fourth,0,"mountain-1")) -- An empty arrival cannot fund a later order.
assert(advance(state,fourth,20) and state.order.progress==20)
assert(not advance(state,fourth,20))
state = save(state)
assert(state.order and state.finished == 0 and #state.warehouse == 1)
local fifth = NHStore.newRun(state)
assert(NHStore.endRun(state, fifth))
assert(not advance(state,fifth,state.order.required) and state.order.progress==20)
local sixth = NHStore.newRun(state)
assert(advance(state,sixth,20,"mountain-1") and state.order.progress==20+NHStore.checkpointFrames)
assert(advance(state,sixth,state.order.required))
state = save(state)
assert(state.finished == 1 and not state.order and #state.warehouse == 1)
assert(state.materials.magic_liquid_teleportation == 512 and state.materials.water==20)
assert(not advance(state,sixth,1))
assert(state.warehouse[1].item.materials.water == 20)

local stale = load()
assert(NHStore.restock(state))
state = save(state)
assert(not NHStore.commit(stale))
selected = 2
local separate = load()
assert(separate.profile == 2 and separate.runSerial == 0 and #separate.warehouse == 0)
assert(not NHStore.commit(state))
assert(NHStore.newRun(separate) == 1)
local unstable = "magic_liquid_unstable_teleportation"
separate.materials={[unstable]=330,slime=249}
assert(not NHStore.canStartBatch(separate) and not NHStore.startOrder(separate))
assert(separate.materials[unstable]==330 and separate.materials.slime==249)
separate.materials.slime=350
assert(NHStore.startOrder(separate))
assert(separate.materials[unstable]==80 and separate.materials.slime==100)
assert(not NHStore.startOrder(separate))
assert(advance(separate,1,separate.order.required) and #separate.warehouse==0)
assert(separate.materials.magic_liquid_teleportation==500)
separate = save(separate)
selected = 1
state = load()
assert(state.runSerial == sixth and #state.warehouse == 1)
assert(not NHStore.commit(separate))

-- A checkpoint receipt, timer progress and delivery share one commit. Retry
-- the same absolute target after a rejected write, reload, and once a new
-- batch is running in the same world.
state.materials[unstable],state.materials.slime=500,500
assert(NHStore.startOrder(state))
state=save(state)
local first_tick={run=sixth,orderId=state.order.id,progress=60,checkpoint="mountain-2"}
assert(NHStore.advanceProduction(state,first_tick))
blocked_key,blocked_value="noita_hideout.p1_revision",state.revision+1
assert(not NHStore.commit(state))
blocked_key=nil
state=load()
assert(not state.checkpoints["mountain-2"] and state.order.progress==0)
assert(NHStore.advanceProduction(state,first_tick))
state=save(state)
assert(state.order.progress==NHStore.checkpointFrames+60 and not NHStore.advanceProduction(state,first_tick))
local delivery={run=sixth,orderId=state.order.id,progress=state.order.progress,checkpoint="mountain-3"}
local before,stock=state.finished,state.materials.magic_liquid_teleportation
local changed,finished=NHStore.advanceProduction(state,delivery)
assert(changed and finished)
blocked_key,blocked_value="noita_hideout.p1_revision",state.revision+1
assert(not NHStore.commit(state))
blocked_key=nil
state=load()
assert(state.order and not state.checkpoints["mountain-3"] and state.materials.magic_liquid_teleportation==stock)
assert(NHStore.advanceProduction(state,delivery))
state=save(state)
assert(state.materials.magic_liquid_teleportation==stock+500 and state.finished==before+1)
assert(NHStore.startOrder(state))
assert(not NHStore.advanceProduction(state,delivery) and state.order.progress==0)
assert(not advance(state,sixth,0,"mountain-3"))
assert(advance(state,sixth,state.order.required) and state.finished==before+2)
state=save(state)

-- One corrupt redundant older copy is harmless. Losing the current committed
-- revision must lock the store instead of reissuing the previous inventory.
local current = state.revision % 2 == 1 and "noita_hideout.p1_a" or "noita_hideout.p1_b"
local old = current == "noita_hideout.p1_a" and "noita_hideout.p1_b" or "noita_hideout.p1_a"
local old_data = settings[old]
settings[old] = "bad snapshot"
assert(load().revision == state.revision)
settings[old] = old_data
settings[current] = "bad snapshot"
assert(not NHStore.load())
selected = 2
assert(load().runSerial == 1)

selected = 3
local trial = load()
local head_key = "noita_hideout.p3_revision"
assert(NHStore.takePouchDose(starter(trial),1))
-- Failing even to initialize a head leaves no staged item at all.
blocked_key, blocked_value = head_key, 0
assert(not NHStore.commit(trial))
assert(not settings["noita_hideout.p3_a"] and load().revision == 0)
-- First snapshot is now staged, yet head zero still represents the empty profile.
blocked_value = 1
assert(not NHStore.commit(trial))
assert(settings["noita_hideout.p3_a"] and settings[head_key] == 0)
assert(load().revision == 0 and starter(load()).doses == 2)
blocked_key = nil
trial = save(trial)
assert(trial.revision == 1 and starter(trial).doses == 1)
-- Established profile: staged removal of the last dose must remain invisible.
assert(NHStore.takePouchDose(starter(trial),1))
blocked_key, blocked_value = head_key, 2
assert(not NHStore.commit(trial))
assert(load().revision == 1 and starter(load()).doses == 1)
blocked_key = nil
trial = save(trial)
assert(trial.revision == 2 and starter(trial).doses == 0)
-- A setter that threw *after* advancing the head is a successful commit.
assert(NHStore.restock(trial))
blocked_key, blocked_value, fail_after = head_key, 3, true
trial = save(trial)
assert(trial.revision == 3 and starter(trial).doses == 2)
assert(NHStore.expandSafe(trial,7))
trial=save(trial)
assert(NHStore.safeCapacity(trial)==7 and not NHStore.expandSafe(trial,6))
assert(NHStore.safeCapacity({safe={}})==1)
settings[head_key] = nil
assert(not NHStore.load())  -- Missing head on established data cannot reset inventory.
print("Store: safe/carry loss, paid production, no double reward, save isolation and recovery passed.")

-- Read the last dedicated-slot format with a full, upgraded case.
selected=4
profiles[4]={}
local old=load()
old.sharedSlots,old.safeCapacity,starter(old).slot=nil,3,nil
for i=1,3 do old.safe[i]={id=i,slot=i,item={kind="wand",name="Wand"}} end
old=save(old)
assert(old.safeCapacity==4 and starter(old).slot==4 and not NHStore.freeSafeSlot(old))
old=save(old)
assert(old.safeCapacity==4 and old.safe[3].slot==3)
starter(old).location="bag"
assert(NHStore.freeSafeSlot(old,4)==4)

function CellFactory_GetAllLiquids() return {"water","slime"} end
function CellFactory_GetAllSands() return {"sand"} end
selected=5
profiles[5]={}
local bulk=load()
bulk.docks={
    {slot=1,id=1,item={kind="potion",capacity=12,max_capacity=10,materials={water=9,slime=4}}},
    {slot=2,id=2,item={kind="potion",variant="powder_stash",capacity=5,materials={sand=8}}},
}
bulk.nextItemId=3
bulk=save(bulk)
local function move(slot,material,count)
    return NHPotion.transferMaterial(bulk,{slot=slot,storedId=slot,material=material,amount=count,unload=not material})
end
assert(move(1) and move(2))
assert(bulk.materials.water==9 and bulk.materials.slime==4 and bulk.materials.sand==8)
assert(not move(2) and not move(1,"sand",1) and not move(2,"water",1))
assert(not NHPotion.transferMaterial(bulk,{slot=1,storedId=17,unload=true}))
assert(move(1,"water",1) and bulk.docks[1].item.materials.water==1)
assert(move(1,"slime",50) and not bulk.materials.slime)
assert(move(1,"water",50) and bulk.materials.water==3 and not move(1,"water",1))
assert(move(2,"sand",50) and bulk.docks[2].item.materials.sand==5 and bulk.materials.sand==3)
bulk=save(bulk)
assert(move(1))
blocked_key,blocked_value,fail_after="noita_hideout.p"..bulk.profile.."_revision",bulk.revision+1,false
assert(not NHStore.commit(bulk))
bulk=load()
assert(bulk.materials.water==3 and bulk.docks[1].item.materials.water==6)
blocked_key=nil
assert(move(1) and move(2))
bulk=save(bulk)
assert(bulk.materials.water==9 and bulk.materials.slime==4 and bulk.materials.sand==8)
