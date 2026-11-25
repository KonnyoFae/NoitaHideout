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
assert(advance(state,sixth,20,"mountain-1") and not state.order) -- One checkpoint finishes a new eight-second batch.
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
-- A stable batch paid for on 0.34 still has its original two-minute timer.
state.order.required=120*60
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
assert(state.order.required==8*60)
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

-- Shop spending and vault transfers share the same profile commit boundary.
selected=6
profiles[6]={}
local bank=load()
assert(bank.bankGold==0 and not NHStore.spendGold(bank,1))
for _,amount in ipairs({0,-1,0.5,"1",math.huge,0/0,NHStore.maxGold+1}) do
    assert(not NHStore.creditGold(bank,amount) and not NHStore.spendGold(bank,amount))
    assert(bank.bankGold==0)
end
assert(NHStore.creditGold(bank,NHStore.maxGold) and not NHStore.creditGold(bank,1))
bank=save(bank)
assert(bank.bankGold==NHStore.maxGold)
assert(NHStore.spendGold(bank,NHStore.maxGold-1000))
bank=save(bank)
local spend=load()
assert(NHStore.spendGold(bank,600) and NHStore.spendGold(spend,500))
assert(not NHStore.spendGold(bank,401) and bank.bankGold==400)
bank=save(bank)
assert(not NHStore.commit(spend) and load().bankGold==400)
local bankRun=NHStore.newRun(bank)
assert(NHStore.endRun(bank,bankRun))
NHStore.newRun(bank)
bank=save(bank)
assert(bank.bankGold==400)
for _,invalid in ipairs({-5,0.1,"0",false,NHStore.maxGold+1}) do
    bank.bankGold=invalid
    assert(not NHStore.commit(bank) and load().bankGold==400)
end
selected=5
assert(load().bankGold==0)
print("Store: piggy bank persistence, precision, isolated balances and concurrent spending passed.")

do
    selected=7
    profiles[selected]={}
    local legacy=load()
    legacy.supportAmmoExpanded=nil
    legacy.pheromoneMagazines=nil
    legacy.safe={{id=legacy.nextItemId+1,slot=1,item={kind="flare_gun",count=3,remaining=1}}}
    legacy.warehouse={{id=legacy.nextItemId,slot=1,item={kind="heavy_mg",count=6,remaining=13}}}
    legacy.nextItemId=legacy.nextItemId+2
    local upgraded=save(legacy)
    for i=1,2 do
        local gun=upgraded.warehouse[1].item
        assert(upgraded.supportAmmoExpanded and gun.count==2 and gun.remaining==93 and NHGuns.rounds(gun)==413)
        local flare=upgraded.safe[1].item
        assert(upgraded.pheromoneMagazines==20 and flare.count==1 and flare.remaining==12 and NHGuns.rounds(flare)==12)
        upgraded=save(upgraded)
    end
    -- A profile from the previous release already has the other support-weapon capacities.
    upgraded.railgunAmmoExpanded=nil
    upgraded.warehouse[2]={id=upgraded.nextItemId,slot=2,item={kind="railgun",count=5,remaining=3}}
    upgraded.nextItemId=upgraded.nextItemId+1
    for i=1,2 do
        upgraded=save(upgraded)
        local rail=upgraded.warehouse[2].item
        assert(upgraded.railgunAmmoExpanded and rail.count==2 and rail.remaining==3 and NHGuns.rounds(rail)==23)
        assert(NHGuns.rounds(upgraded.warehouse[1].item)==413)
    end
end

do
    selected=8
    profiles[selected]={}
    local old=save(load())
    assert(old.ewDepositPending==nil and old.ewActive==nil)
    old.ewActive="ROOM_A-1"
    old.ewDepositPending={world=old.ewActive,issuer="PLAYER1",tx="2",phase="prepare",run=old.runSerial,
        keys={"g/123","t/ew/PLAYER1/r/1/2/3/4/5/6"},intent={route="item",dest="warehouse"},record={kind="potion"},
        original=false,hadItem=true,slot={bag="inventory_quick",x=1,y=0}}
    local held=save(old)
    assert(held.ewDepositPending.tx=="2" and held.ewDepositPending.slot.x==1)
    local function refuses(change)
        local draft=load()
        change(draft)
        local ok,why=NHStore.commit(draft)
        assert(not ok and why:find("Invalid pending multiplayer deposit",1,true))
        local durable=load()
        assert(durable.revision==held.revision and durable.ewDepositPending.tx=="2")
    end
    refuses(function(s) s.ewDepositPending=false end)
    refuses(function(s) s.ewDepositPending.tx=nil end)
    refuses(function(s) s.ewDepositPending.tx=2 end)
    refuses(function(s) s.ewDepositPending.keys={"g/123","g/123"} end)
    refuses(function(s) s.ewDepositPending.world="ROOM_B" end)
    refuses(function(s) s.ewDepositPending.slot.x="1" end)
    refuses(function(s) s.ewDepositPending.reserved="yes" end)
    refuses(function(s) s.ewDepositPending={world=s.ewActive,issuer="PLAYER1",tx="2",phase="prepare",keys={"g/123"}} end)
    refuses(function(s) s.ewDepositPending={world=s.ewActive,issuer="PLAYER1",tx="2",phase="cancel"} end)
    held.ewDepositPending.slot=nil -- Order saved before the native inventory slot was recorded.
    held.ewDepositPending.phase="return"
    held.ewDepositPending.outcome="cancelled"
    held=save(held)
    assert(held.ewDepositPending.phase=="return")
    held.ewDepositPending={world=held.ewActive,issuer="PLAYER1",tx="2",phase="cancel",keys={"g/123"},reserved=true}
    held=save(held)
    held.ewDepositPending.phase,held.ewDepositPending.outcome,held.ewDepositPending.keys="return","cancelled",nil
    assert(save(held).ewDepositPending.phase=="return")
end
print("Store: missing legacy deposit fields, valid pending orders and atomic rejection of damaged orders passed.")

do
    selected=9
    profiles[selected]={}
    local draft=load()
    local bottleId=draft.nextItemId
    draft.warehouse={
        {id=bottleId,slot=1,item={kind="potion",name="ccc",materials={water=8,slime=1}}},
        {slot=1,item={kind="wand",name="Legacy wand"}}, -- An older row with no item ID.
    }
    draft.nextItemId=bottleId+1
    assert(NHStore.commit(draft))
    local untouched=load()
    draft.warehouse[1].item.materials.water=5
    draft.warehouse[1].item.materials.slime=nil
    draft.warehouse[1].slot=2
    assert(untouched.warehouse[1].item.materials.water==8 and load().warehouse[1].slot==1)
    untouched.warehouse[2].item.name="Uncommitted"
    assert(load().warehouse[2].item.name=="Legacy wand")

    -- Fail after staging the edited row, then retry with another edit to the same bottle.
    blocked_key,blocked_value,fail_after="noita_hideout.p9_revision",2,false
    assert(not NHStore.commit(draft))
    assert(load().warehouse[1].item.materials.slime==1)
    blocked_key=nil
    draft.warehouse[1].item.materials.water=3
    assert(NHStore.commit(draft))
    draft.warehouse[1].item.materials.water=99
    local function checkBottle(s,name,revision)
        local row=s.warehouse[1]
        assert(s.revision==(revision or 2) and row.id==bottleId and row.slot==2 and row.item.name==name)
        assert(row.item.materials.water==3 and row.item.materials.slime==nil)
        assert(s.warehouse[2].item.name=="Legacy wand")
    end
    local function shallowCopy(source)
        local copy={}
        for key,value in pairs(source) do copy[key]=value end
        return copy
    end
    local beforeRestore=load()
    checkBottle(beforeRestore,"ccc")

    local current,older="noita_hideout.p9_b","noita_hideout.p9_a"
    local committed,backup=settings[current],settings[older]
    -- These two names have the same length and Adler-32. A restored slot can share
    -- its head and checksum with a cached snapshot while containing different data.
    local replacement,n=committed:gsub("s3:ccc","s3:dad",1)
    assert(n==1)
    settings[current]=replacement
    checkBottle(load(),"dad")
    assert(not NHStore.commit(beforeRestore))
    assert(not NHStore.commit(shallowCopy(beforeRestore),nil,beforeRestore))
    settings[current]=replacement:gsub("s3:dad","s3:bad",1)
    assert(not NHStore.load() and not NHStore.commit(draft))
    settings[current]=replacement
    settings[older]=backup:gsub("^NH1:","NH2:",1)
    assert(not NHStore.load() and not NHStore.commit(draft))
    assert(settings[current]==replacement and settings["noita_hideout.p9_revision"]==2)
    settings[older]=backup
    checkBottle(load(),"dad")
    settings["noita_hideout.p9_revision"]=1
    local rolledBack=load()
    assert(rolledBack.revision==1 and rolledBack.warehouse[1].slot==1)
    assert(rolledBack.warehouse[1].item.name=="ccc" and rolledBack.warehouse[1].item.materials.water==8)
    settings["noita_hideout.p9_revision"]=2
    assert(not NHStore.commit(rolledBack))
    checkBottle(load(),"dad")

    -- After receipt recovery the controller keeps its original table; item
    -- transfers commit a shallow copy, then copy the changed fields back.
    NHStore.adoptSnapshot(beforeRestore,load())
    checkBottle(beforeRestore,"dad")
    local transfer=shallowCopy(beforeRestore)
    assert(NHStore.creditGold(transfer,1) and NHStore.commit(transfer,nil,beforeRestore))
    beforeRestore.revision,beforeRestore.bankGold=transfer.revision,transfer.bankGold
    assert(NHStore.creditGold(beforeRestore,1) and NHStore.commit(beforeRestore))
    dofile("mods/noita_hideout/files/store.lua")
    local reloaded=load()
    checkBottle(reloaded,"dad",4)
    assert(reloaded.bankGold==2)
end
print("Store: detached snapshots, warehouse edits, staged-write retries, same-head restores and cold reload passed.")

-- Write an actual four-round-format snapshot, including a reserved stack and
-- the two multiplayer places that can be parked when a different world loads.
do
    selected=19
    profiles[selected]={}
    local s=load()
    NHStore.newRun(s)
    s.ewActive="ACTIVE"
    local function gun(count,remaining) return {kind="flare_gun",count=count,remaining=remaining} end
    local function ticket(count,remaining) return {row={id=14,slot=1,item=gun(count,remaining)},container="warehouse"} end
    local function pending(world,count,remaining)
        return {world=world,issuer="PLAYER1",tx="11",phase="prepare",run=s.runSerial,
            keys={"g/123"},intent={route="item",dest="safe"},record=gun(count,remaining),
            original=false,hadItem=true,slot={bag="inventory_quick",x=1,y=0}}
    end
    s.transit={run=s.runSerial,issued={a=ticket(6,3)},retired={}}
    s.ewDepositPending=pending("ACTIVE",5,1)
    s.ewExpeditions={PARKED={ewDepositPending=pending("PARKED",3,2),
        transit={run=2,issued={b=ticket(1,4)},retired={}}}}
    s.warehouse={{id=2,slot=1,item=gun(2,4)}}
    s.safe={{id=3,slot=1,item=gun(3,2)}}
    s.order={id=s.finished+1,progress=0,required=100,output={slot=1,item=gun(1,4)}}
    s.nextItemId=15
    s.pheromoneMagazines=true
    NHGuns.types.flare_gun.capacity=4
    assert(NHStore.commit(s))
    NHGuns.types.flare_gun.capacity=20
    local function check(record,rounds)
        assert(NHGuns.rounds(record)==rounds and record.count==math.ceil(rounds/20) and record.remaining==(rounds-1)%20+1)
    end
    for i=1,2 do
        s=load()
        assert(s.pheromoneMagazines==20)
        check(s.warehouse[1].item,8); check(s.safe[1].item,10)
        check(s.order.output.item,4); check(s.transit.issued.a.row.item,23)
        check(s.ewDepositPending.record,17); check(s.ewExpeditions.PARKED.ewDepositPending.record,10)
        check(s.ewExpeditions.PARKED.transit.issued.b.row.item,4)
        assert(NHStore.commit(s))
    end
    assert(NHStore.advanceProduction(s,{run=s.runSerial,orderId=s.order.id,progress=100}))
    s=save(s);assert(not s.order and #s.warehouse==1 and s.warehouse[1].id==2)
    check(s.warehouse[1].item,12)

    local function physical(rounds,tagged)
        local item={uses_remaining=rounds}
        local entity={nh_pheromone_launcher=tagged}
        function EntityHasTag(e,tag) return e[tag] end
        function EntityAddTag(e,tag) e[tag]=true end
        function ComponentGetValue2(c,key) return c[key] end
        function ComponentSetValue2(c,key,v) c[key]=v end
        local n=NHGuns.physicalRounds("flare_gun",entity,item)
        assert(entity.nh_pheromone_launcher and NHGuns.physicalRounds("flare_gun",entity,item)==n)
        return n
    end
    assert(physical(3,false)==12 and physical(2,true)==2 and physical(22,true)==22)
end
