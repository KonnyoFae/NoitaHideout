local settings,flags,world={},{},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k]==true end
function AddFlagPersistent(k) flags[k]=true end
function GlobalsGetValue(k,default) return world[k] or default end
function GlobalsSetValue(k,v) world[k]=v end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local minute=3600
local function fresh()
    settings,flags,world={},{},{}
    local state=assert(NHStore.load())
    NHStore.newRun(state)
    NHCompanions.resetProduction()
    GlobalsSetValue("noita_hideout_run_v1",state.profile.."/"..state.runSerial)
    NHAffinity.bind(state)
    return state
end
local function reload(state)
    assert(NHStore.commit(state))
    local loaded=assert(NHStore.load())
    assert(loaded.revision==state.revision)
    return loaded
end
local function add(state,species,now,adult)
    assert(NHLivestock.deliver(state,species,assert(NHLivestock.freePen(state,species)),now,adult))
end
local function count(state,kind)
    local quantity=0
    for _,row in ipairs(state.warehouse) do
        if row.item.kind==kind then quantity=quantity+(row.item.count or 1) end
    end
    return quantity
end

-- Current farm activity, independent of any menus, counts one payment per minute.
local s=fresh()
s.levels.farmland,s.levels.agri_equipment=1,1
assert(NHFarm.plant(s,{plot=1,token=0,crop="active_herb"},0))
for i,want in ipairs({0,1,1,2,3}) do
    local deadline=i*minute
    assert(not NHFarm.due(s,deadline-1) and NHFarm.due(s,deadline))
    assert(NHFarm.sync(s,deadline))
    assert((s.resources.active_herb or 0)==want)
    s=reload(s)
    assert(not NHFarm.sync(s,deadline))
end

-- 30 minutes spanning a level-up at minute 10.5. At two hens the exact total
-- is 21 + 19.5 * 2.10 = 61.95 eggs and 30.975 meat.
s=fresh()
s.levels.livestock=1
s.materials={sand=400,water=300}
add(s,"chick",0,true)
add(s,"chick",0,true)
assert(NHStore.buyUpgrade(s,{id="livestock",level=1},10.5*minute))
assert(s.resources.egg==20 and s.resources.meat==10)
s=reload(s)
NHFarm.sync(s,30*minute)
assert(s.resources.egg==61 and s.resources.meat==30)
NHFarm.sync(s,31*minute)
assert(s.resources.egg==64 and s.resources.meat==32)

-- A high-affinity pet helps only during its eligible time. A different species,
-- an empty interval and controller reload each split the stream.
s=fresh()
s.levels.dragon_nest,s.levels.livestock=3,3
add(s,"dragon_egg",0,true)
add(s,"chick",0,true)
for _,at in ipairs({{0,0},{100,100},{400,300},{1000,500},{10000,1000}}) do
    assert(NHAffinity.productionBasisPoints(at[1])==at[2])
end
NHCompanions.recordProduction(s,0,"griffin",10000)
NHCompanions.recordProduction(s,5.5*minute,"bee",10000)
NHFarm.sync(s,7*minute)
s=reload(s)
NHCompanions.resetProduction()
NHCompanions.recordProduction(s,8*minute,nil)
NHFarm.sync(s,10*minute)
-- Dragons accept either pet for 8 minutes; chickens receive 5.5 minutes only.
assert(s.bankGold==354 and s.resources.egg==11 and s.resources.meat==5)
NHFarm.sync(s,20*minute)
assert(s.bankGold==684 and s.resources.egg==22 and s.resources.meat==11)

-- A chick completes its old two-minute roll at 2:30. Its qualified griffin
-- leaves before the 3:00 deposit, while the basic facility roll is a miss.
s=fresh()
s.levels.livestock=1
add(s,"chick",minute/2,true)
s.summons={livestock=1,pending={}}
local seed=1
while (seed*48271%2147483647)%10000>=900 do seed=seed+1 end
s.companionIncomeSeed=seed
NHCompanions.recordProduction(s,minute/2,"griffin",10000)
NHCompanions.recordProduction(s,2.5*minute+1,nil)
NHFarm.sync(s,3*minute-1)
assert(count(s,"summon_card")==0 and s.companionIncomeSeed==seed)
s=reload(s)
NHCompanions.resetProduction()
local changed,_,cards=NHFarm.sync(s,3*minute)
assert(changed and #cards==1 and cards[1]=="griffin" and count(s,"summon_card")==1)
assert(s.companionIncomeSeed==seed*48271%2147483647)
assert(not NHFarm.sync(s,3*minute) and count(s,"summon_card")==1)

-- At six adults the kennel banks 0.22 of each bag/minute and the cattery
-- 0.12 cases/minute with its own active companion and level-three housing.
s=fresh()
s.levels.dog_kennel,s.levels.cat_house=3,3
for i=1,6 do add(s,"dog",0,true); add(s,"cat",0,true) end
NHCompanions.recordProduction(s,0,"cat",10000)
NHFarm.sync(s,4*minute)
assert(count(s,"travel_satchel")==0 and count(s,"travel_pack")==0 and count(s,"loot_case")==0)
assert(math.abs(NHFarm.income.petFraction(s,"travel_satchel")-.88)<1e-9)
assert(math.abs(NHFarm.income.petFraction(s,"loot_case")-.48)<1e-9)
local tools=dofile("mods/noita_hideout/files/pet_finds.lua").toolPool(3)
local n=0
for _,id in ipairs(tools) do n=n+count(s,id) end
assert(n==9 and (s.resources.fiber or 0)/3+(s.resources.grain or 0)/2+(s.resources.herb or 0)==24)
assert(s.bankGold==0 and s.bankWalletNet==0)
assert(not NHFarm.sync(s,4*minute))
s=reload(s)
NHFarm.sync(s,5*minute)
assert(count(s,"travel_satchel")==1 and count(s,"travel_pack")==1)

-- Old undelivered batches retain their face value. Partial crop and chicken
-- cycles migrate at their historical rates; only new work earns the level bonus.
s=fresh()
s.levels.farmland,s.levels.livestock=1,3
s.farm={time=minute,passive=true,plots={[1]={token=1,crop="fiber",readyAt=2*minute}},
    pending={grain=2},herds={chick={adults=2,young={},progress=minute,owed=2}}}
s=reload(s)
NHFarm.sync(s,minute)
assert(s.resources.grain==12 and s.resources.egg==4 and s.resources.meat==2)
assert(not s.resources.fiber)
s=reload(s)
NHFarm.sync(s,2*minute)
assert(s.resources.egg==7 and s.resources.meat==3 and s.resources.grain==12 and s.resources.fiber==6)
assert(not NHFarm.sync(s,2*minute))

-- Legacy batches used the active eligible collector when they could first be
-- processed. Only the completed chicken batch gives this griffin a private
-- roll. The blocked crop and the half-finished chicken cycle do not.
s=fresh()
s.levels.farmland,s.levels.livestock=1,1
s.farm={time=minute,passive=true,plots={},pending={grain=1},
    herds={chick={adults=1,young={},progress=minute,owed=1}}}
s.resources.egg=NHStore.maxResourceAmount
s.summons={farm=1,livestock=1,pending={}}
s.companionIncomeSeed=seed
s=reload(s)
NHCompanions.recordProduction(s,minute,"griffin",10000)
local settled,_,legacyCards=NHFarm.sync(s,minute)
local paidSeed=seed*48271%2147483647
assert(settled and #legacyCards==1 and legacyCards[1]=="griffin" and s.companionIncomeSeed==paidSeed)
assert(s.resources.grain==6 and s.resources.meat==1 and s.resources.egg==NHStore.maxResourceAmount)
s=reload(s)
NHCompanions.resetProduction()
assert(not NHFarm.sync(s,minute) and count(s,"summon_card")==1 and s.companionIncomeSeed==paidSeed)
s.resources.egg=NHStore.maxResourceAmount-2
assert(NHFarm.sync(s,minute) and s.resources.egg==NHStore.maxResourceAmount and s.companionIncomeSeed==paidSeed)
assert(not NHFarm.sync(s,minute) and count(s,"summon_card")==1)
print("Minute income: fractional deposits, upgrade and pet timing, pet finds, migration and replay passed.")
