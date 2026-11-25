local settings,flags,globals={},{},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k]==true end
function AddFlagPersistent(k) flags[k]=true end
function GlobalsGetValue(k,def) return globals[k] or def end
function GlobalsSetValue(k,v) globals[k]=v end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local s=assert(NHStore.load())
NHStore.newRun(s)
local function persist()
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
end
local function buy(id,slot,now)
    return NHStore.buyGood(s,{id=id,pen=slot},now)
end
local function expand() return NHStore.buyUpgrade(s,{id="livestock",level=NHStore.level(s,"livestock")}) end
local function view(now) return NHLivestock.view(s,"en",now) end
local function checkRates(now,eggs,milk,meat)
    local expected={egg=eggs,milk=milk,meat=meat}
    local produce=NHFarm.view(s,"zh",now).produce
    assert(#produce==3)
    for _,row in ipairs(produce) do
        assert(math.abs(row.perMinute-1.10*expected[row.id])<1e-9)
        assert(row.stock==(s.resources[row.id] or 0))
    end
end
assert(NHStore.creditGold(s,1000) and not buy("chick",1,0) and s.bankGold==1000)
s.materials={sandstone=1200,water=900}
assert(expand() and s.materials.sandstone==1000 and s.materials.water==750)
assert(#view(0)==2 and view(0)[2].title=="Cowshed" and view(0)[2].capacity==2)
assert(NHFarm.observe(s,70)==0 and buy("chick",1,0) and s.bankGold==880)
assert(not buy("chick",1,0) and s.bankGold==880 and not next(s.warehouse))
local at=NHFarm.observe(s,370)
assert(at==300 and buy("calf",2,at) and s.farm.herds.calf.young[1]==300+NHLivestock.species.calf.growth)
assert(expand() and expand() and not expand() and #view(at)==2 and view(at)[2].capacity==6 and not s.materials.sandstone)
assert(not buy("chick",1,at) and view(at)[1].count==1 and s.bankGold==640)
persist()
NHFarm.resetClock()
assert(NHFarm.observe(s,370)==at and #view(at)==2)
local hen,cow=NHLivestock.species.chick,NHLivestock.species.calf
local first=hen.growth+hen.period
local rewards=0
NHCompanions=NHCompanions or {}
NHCompanions.reward=function(_,source,cycles)
    assert(source=="livestock")
    rewards=rewards+cycles
    return {}
end
assert(not view(hen.growth-1)[1].grown and view(hen.growth)[1].grown)
checkRates(hen.growth-1,0,0,0)
checkRates(hen.growth,1,0,0.5)
assert(view(hen.growth)[1].remaining==hen.period/60)
assert(NHFarm.observe(s,first+69)==first-1 and NHFarm.sync(s,first-1) and s.resources.egg==1 and rewards==0)
NHFarm.resetClock()
assert(NHFarm.observe(s,first+69)==first-1)
at=NHFarm.observe(s,first+70)
assert(at==first and NHFarm.due(s,at) and not view(at)[2].grown)
s.resources.meat=NHStore.maxResourceAmount
local changed,produced=NHFarm.sync(s,at)
assert(changed and produced and s.resources.egg==2 and rewards==1)
assert(view(at)[1].blocked and not NHFarm.due(s,at))
checkRates(at,1,0,0.5)
s.resources.meat=nil
assert(NHFarm.due(s,at) and NHFarm.sync(s,at) and not NHFarm.sync(s,at))
assert(s.resources.egg==2 and s.resources.meat==1 and rewards==1 and not next(s.materials))
-- A single long tick pays all complete periods, beyond the old four-batch limit.
local lastCow=300+cow.growth+6*cow.period
at=NHFarm.observe(s,lastCow+70)
assert(at==lastCow)
persist()
local stale=assert(NHStore.load())
assert(NHFarm.sync(s,at) and NHStore.commit(s))
assert(NHFarm.sync(stale,at) and not NHStore.commit(stale))
s=assert(NHStore.load())
local lastPaid=at-at%3600
local henMinutes=(lastPaid-hen.growth)/3600
local cowMinutes=(lastPaid-300-cow.growth)/3600
assert(s.resources.milk==math.floor(cowMinutes*2/3*1.10) and s.resources.meat==math.floor((henMinutes/2+cowMinutes*2/3)*1.10) and view(at)[2].nextAt==at+cow.period)
assert(s.resources.egg==math.floor(henMinutes*1.10) and view(at)[1].nextAt==first+(1+math.floor((at-first)/hen.period))*hen.period)
assert(not view(at)[2].blocked and not NHFarm.sync(s,at) and not s.materials.milk and #s.warehouse==0)
assert(NHStore.endRun(s,s.runSerial))
persist()
NHStore.newRun(s)
assert(NHFarm.observe(s,1)==at and NHFarm.observe(s,61)==at+60)
assert(view(at+60)[1].remaining==math.ceil((view(at)[1].nextAt-at-60)/60) and view(at+60)[2].grown)
assert(buy("chick",assert(NHLivestock.freePen(s,"chick")),at) and buy("calf",assert(NHLivestock.freePen(s,"calf")),at))
checkRates(at,1,2/3,0.5+2/3)
checkRates(at+hen.growth,2,2/3,1+2/3)
checkRates(at+cow.growth,2,4/3,1+4/3)
print("Livestock: integrated herd production, caps, maturity, projected group rates and replay-safe awards passed.")

local function testGroupedWork()
    local state=assert(NHStore.load())
    state.farm={time=0,plots={},passive=true}
    state.resources={}
    state.levels.livestock=3
    local function add(now,adult)
        return NHLivestock.deliver(state,"chick",assert(NHLivestock.freePen(state,"chick")),now,adult)
    end
    local function group(now) return NHLivestock.view(state,"en",now)[1] end
    assert(add(0,true) and add(0) and add(0))
    assert(add(1200) and add(1200) and add(1200))
    assert(not NHLivestock.freePen(state,"chick") and NHLivestock.freePen(state,"calf"))
    assert(group(1200).count==6 and group(1200).adults==1 and group(1200).juveniles==5)
    NHFarm.sync(state,hen.period)
    assert(state.resources.egg==2 and group(hen.period).nextAt==12000)
    -- Two simultaneous maturities at 10800 frames accelerate without a jump
    -- in work. Three more mature at 12000, exactly as the next batch arrives.
    local before=group(hen.growth-1)
    local after=group(hen.growth)
    assert(before.adults==1 and after.adults==3 and before.nextAt==12000 and after.nextAt==12000)
    assert(before.growthRemaining==1 and after.growthRemaining==20)
    assert(math.abs(after.progress-before.progress-1/hen.period)<1e-9)
    assert(state.farm.herds.chick.adults==1,"looking at a future view must not settle it")
    assert(NHFarm.sync(state,12000) and state.resources.egg==3)
    assert(group(12000).adults==6 and group(12000).juveniles==0 and group(12000).period==120
        and group(12000).effectivePeriod==20 and group(12000).remaining==20 and group(12000).progress==0)
    local untilFrame=12000+300*hen.period/6+25
    local beforeAwards=rewards
    NHFarm.sync(state,untilFrame)
    assert(NHFarm.due(state,untilFrame),"large restored rare backlogs are drained in bounded steps")
    local calls=1
    while NHFarm.due(state,untilFrame) do
        assert(NHFarm.sync(state,untilFrame))
        calls=calls+1
        assert(calls<=4)
    end
    assert(calls>=2 and not NHFarm.sync(state,untilFrame))
    assert(rewards-beforeAwards==300 and state.resources.egg==662)
end
testGroupedWork()

local function testLegacyPens()
    local state=assert(NHStore.load())
    local now=120000
    state.levels.livestock,state.levels.gel_pool=3,1
    local gel=NHLivestock.species.gel_pool
    state.farm={time=now,plots={},passive=true,pens={
        [1]={kind="chick",born=0,nextAt=now-3*hen.period/4},
        [3]={kind="chick",born=0,nextAt=now+hen.period/4},
        [5]={kind="chick",born=now-60,nextAt=now-60+hen.growth+hen.period},
        -- The 0.33 pool started with a mature producer even when just built.
        [9]={kind="gel_pool",born=now-32,nextAt=now+gel.period-32},
    }}
    state.resources={}
    -- Save a real 0.33-shaped payload with the production serializer.
    local currentValidation=NHFarm.validate
    NHFarm.validate=function() end
    assert(NHStore.commit(state))
    NHFarm.validate=currentValidation
    state=assert(NHStore.load())
    local chickens=state.farm.herds.chick
    assert(not state.farm.pens and chickens.adults==2 and #chickens.young==1)
    assert(chickens.progress==hen.period/2 and chickens.young[1]==now-60+hen.growth)
    assert(state.farm.herds.gel_pool.adults==1 and state.farm.herds.gel_pool.progress==32)
    assert(NHFarm.sync(state,now) and state.resources.egg==4 and state.resources.meat==2)
    assert(NHLivestock.view(state,"en",now)[1].nextAt==now+hen.period/4)
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    assert(not NHFarm.sync(state,now) and state.resources.egg==4)

    -- Manual pre-passive pens could bank four cycles at most. Apply that
    -- limit before conversion even if they had been left alone for longer.
    local farm={time=now,plots={},pens={[1]={kind="chick",born=0,nextAt=hen.growth+hen.period}}}
    NHFarm.adopt(farm)
    state.farm,state.resources=farm,{}
    assert(farm.passive and farm.herds.chick.progress==0)
    assert(NHFarm.sync(state,now) and state.resources.egg==8 and state.resources.meat==4)
end
testLegacyPens()
print("Shared housing: capacity, simultaneous maturities, live ETA, capped catch-up and exact migration from old independent deadlines passed.")
