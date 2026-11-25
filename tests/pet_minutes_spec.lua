local files="mods/noita_hideout/files/"
local settings,flags={},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
local reds={}
local read=dofile
function dofile(path)
    if path==files.."red_collectibles.lua" then return reds end
    return read(path)
end
dofile(files.."store.lua")
local find=dofile(files.."pet_finds.lua")
local minute=NHFarm.minute
local function fresh()
    settings,flags={},{}
    local s=assert(NHStore.load())
    NHStore.newRun(s)
    s.levels.dog_kennel,s.levels.cat_house=3,3
    NHCompanions.resetProduction()
    return s
end
local function adult(s,k,n)
    for _=1,n do assert(NHLivestock.deliver(s,k,NHLivestock.freePen(s,k),0,true)) end
end
local function reload(s)
    assert(NHStore.commit(s))
    return assert(NHStore.load())
end
local function qty(s,k)
    local result=0
    for _,r in ipairs(s.warehouse) do if r.item.kind==k then result=result+(r.item.count or 1) end end
    return result
end
local function tools(s)
    local total=0
    for _,id in ipairs(find.toolPool(3)) do total=total+qty(s,id) end
    return total
end
local function resolve(s,time)
    local tries=0
    while NHFarm.due(s,time) do
        assert(NHFarm.sync(s,time))
        tries=tries+1
        assert(tries<1000)
    end
end
local s=fresh()
adult(s,"cat",6); adult(s,"dog",6)
for i,n in ipairs({2,4,6,9}) do
    NHFarm.sync(s,i*minute)
    assert(tools(s)==n)
    assert((s.resources.fiber or 0)/3+(s.resources.grain or 0)/2+(s.resources.herb or 0)==i*6)
    assert(not s.farm.minuteIncome.forage.red and not s.farm.minuteIncome.forage.redOpen)
    s=reload(s)
end

-- Recorded finds are independent of the timing of catch-up and staged
-- transactions, even when a full warehouse cannot deliver all the rewards.
local function sixty(split)
    local t=fresh()
    adult(t,"cat",6); adult(t,"dog",6)
    if split then
        for i=1,60 do
            NHFarm.sync(t,(i-.43)*minute)
            NHFarm.sync(t,i*minute)
            if i%10==0 then t=reload(t) end
        end
    else NHFarm.sync(t,60*minute) end
    resolve(t,60*minute)
    return t
end
local a,b=sixty(false),sixty(true)
for _,key in ipairs({"fiber","grain","herb"}) do assert(a.resources[key]==b.resources[key]) end
for _,key in ipairs({"travel_satchel","travel_pack","loot_case",unpack(find.toolPool(3))}) do
    local function both(t) return qty(t,key)+(t.farm.minuteIncome.forage.pending[key] or 0) end
    assert(both(a)==both(b),key)
end
assert(qty(a,"travel_satchel")==13 and qty(a,"travel_pack")==13 and qty(a,"loot_case")==6)
assert(math.abs(NHFarm.income.petFraction(a,"loot_case")-.6)<1e-9)

-- The identity of dog resources is fixed even when their shared stock is full.
s=fresh()
adult(s,"dog",1)
for _,bundle in ipairs(NHFarm.income.dogBundles) do s.resources[bundle[1]]=NHStore.maxResourceAmount end
NHFarm.sync(s,minute)
local resource,amount=next(s.farm.minuteIncome.owed)
assert(resource and amount>0 and NHFarm.income.petBlocked(s,"dog") and not NHFarm.due(s,minute))
s=reload(s)
s.resources[resource]=s.resources[resource]-amount
assert(NHFarm.due(s,minute) and NHFarm.sync(s,minute))
assert(s.resources[resource]==NHStore.maxResourceAmount and not NHFarm.due(s,minute) and not NHFarm.income.petBlocked(s,"dog"))

-- A tier-one cat rolls the sedative pistol while the supplies grid is full.
-- The saved find can be delivered exactly once after a slot opens.
s=fresh()
s.levels.cat_house=1
adult(s,"cat",1)
NHFarm.income.adopt(s)
s.farm.minuteIncome.forage={seeds={cat1=40000},pending={}}
for slot=1,NHStore.warehouseCapacity(s,"supplies") do
    s.warehouse[slot]={id=s.nextItemId,slot=slot,item={kind="bandage"}}
    s.nextItemId=s.nextItemId+1
end
NHFarm.sync(s,minute)
assert(s.farm.minuteIncome.forage.pending.sedative_launcher==1 and qty(s,"sedative_launcher")==0)
s=reload(s)
assert(s.farm.minuteIncome.forage.pending.sedative_launcher==1 and not NHFarm.due(s,minute))
table.remove(s.warehouse)
assert(NHFarm.sync(s,minute) and qty(s,"sedative_launcher")==1)
assert(s.warehouse[#s.warehouse].item.remaining==20)
s=reload(s)
assert(qty(s,"sedative_launcher")==1 and not NHFarm.due(s,minute))

-- The grid is still full. A backlog of 17 decoys fills the next freed
-- slot with 16; its single outstanding find survives saving and reloading.
s.farm.minuteIncome.forage.pending.turret_pack=17
table.remove(s.warehouse,1)
assert(NHFarm.sync(s,minute) and qty(s,"turret_pack")==16)
s=reload(s)
assert(s.farm.minuteIncome.forage.pending.turret_pack==1 and not NHFarm.due(s,minute))
table.remove(s.warehouse,1)
assert(NHFarm.sync(s,minute) and qty(s,"turret_pack")==17)
s=reload(s)
assert(not s.farm.minuteIncome.forage.pending.turret_pack and not NHFarm.due(s,minute))

-- Legacy closed returns, open returns, partial old-rate bag work and card
-- opportunities each retain their separate meaning; a reload cannot duplicate them.
s=fresh()
adult(s,"dog",1); adult(s,"cat",1)
s.farm.time=minute/2
s.farm.herds.dog.progress=minute/2
s.farm.herds.cat.progress=minute/2
s.farm.minuteIncome={
    remainder={},open={},owed={dog=1},openRare={counts={dog_kennel=2},private={}},
    rare={counts={cat_house=1},private={}}}
s=reload(s)
NHFarm.sync(s,minute/2)
assert(qty(s,"travel_pack")==1 and qty(s,"loot_case")==1)
assert(NHFarm.income.petFraction(s,"travel_pack")==.5 and NHFarm.income.petFraction(s,"loot_case")==.125)
s=reload(s)
assert(not NHFarm.sync(s,minute/2))
NHFarm.sync(s,minute)
assert(qty(s,"travel_pack")==3 and not NHFarm.sync(s,minute))

-- Capture the facility tier before paying a long backlog. Tier-one findings
-- cannot turn into higher-tier loot by upgrading or reloading before delivery.
s=fresh()
s.levels.cat_house=1
adult(s,"cat",2)
NHFarm.sync(s,110*minute)
assert(s.farm.minuteIncome.owed.cat1==9)
s.levels.cat_house=2
s=reload(s)
resolve(s,110*minute)
for i=#find.toolPool(1)+1,#find.toolPool(3) do assert(qty(s,find.toolPool(3)[i])==0) end
assert(tools(s)==137)

-- Exercise the future catalogue without releasing a placeholder. Red has
-- one draw per boundary, proportional to the actual adult-animal frames.
reds[1]={id="probe",file="unused.xml",item={kind="medkit",count=1,remaining=3}}
local function born(seed)
    local t=fresh()
    t.farm.herds={dog={adults=0,young={minute/2},progress=0,owed=0},
        cat={adults=0,young={3*minute/4},progress=0,owed=0}}
    NHFarm.income.adopt(t)
    t.farm.minuteIncome.forage={seeds={red=seed},pending={}}
    return t
end
s=born(2)
NHFarm.sync(s,3*minute/4)
assert(s.farm.minuteIncome.forage.redOpen==minute/4 and not s.farm.minuteIncome.forage.red)
s=reload(s)
NHFarm.sync(s,minute)
assert(s.farm.minuteIncome.forage.seeds.red==2*48271 and qty(s,"medkit")==0)
s=born(1)
NHFarm.sync(s,minute)
assert(qty(s,"medkit")==1 and not NHFarm.sync(s,minute))
s=reload(s)
assert(qty(s,"medkit")==1 and not NHFarm.sync(s,minute))

-- A full supplies warehouse holds the single joint collectible exactly once,
-- across save and reload. Its blockage is visible from either enclosure.
s=born(1)
for slot=1,NHStore.warehouseCapacity(s,"supplies") do
    s.warehouse[#s.warehouse+1]={id=s.nextItemId,slot=slot,item={kind="bandage"}}
    s.nextItemId=s.nextItemId+1
end
NHFarm.sync(s,minute)
assert(NHFarm.income.petSharedPending(s)==1)
assert(NHFarm.income.petPending(s,"dog")==0 and NHFarm.income.petPending(s,"cat")==0)
assert(NHFarm.income.petBlocked(s,"dog") and NHFarm.income.petBlocked(s,"cat"))
s=reload(s)
assert(NHFarm.income.petSharedPending(s)==1 and not NHFarm.due(s,minute))
table.remove(s.warehouse)
assert(NHFarm.sync(s,minute) and qty(s,"medkit")==1 and NHFarm.income.petSharedPending(s)==0)
assert(not NHFarm.income.petBlocked(s,"dog") and not NHFarm.income.petBlocked(s,"cat"))
-- A long restore is one run, processed only up to the per-update budget.
s=fresh(); adult(s,"dog",1)
NHFarm.sync(s,50000*minute)
local backlog=s.farm.minuteIncome.forage.red
assert(#backlog==1 and backlog[1].count==50000-NHFarm.batchLimit and backlog[1].weight==minute)
print("Pet income: exact minutes, guaranteed finds, bounded catch-up, old returns, tier locking and joint red roll passed.")
