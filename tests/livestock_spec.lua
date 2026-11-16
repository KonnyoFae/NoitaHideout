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
assert(NHStore.creditGold(s,1000) and not buy("chick",1,0) and s.bankGold==1000)
s.materials={sandstone=1200,water=900}
assert(expand() and s.materials.sandstone==1000 and s.materials.water==750)
assert(#view(0)==2 and view(0)[2].title=="Cowshed 1")
assert(NHFarm.observe(s,70)==0 and buy("chick",1,0) and s.bankGold==880)
assert(not buy("chick",1,0) and s.bankGold==880 and not next(s.warehouse))
local at=NHFarm.observe(s,370)
assert(at==300 and buy("calf",2,at) and s.farm.pens[2].born==300)
assert(expand() and expand() and not expand() and #view(at)==6 and not s.materials.sandstone)
assert(not buy("chick",1,at) and not s.farm.pens[3] and s.bankGold==640)
persist()
NHFarm.resetClock()
assert(NHFarm.observe(s,370)==at and #view(at)==6)
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
assert(view(hen.growth)[1].remaining==hen.period/60)
assert(NHFarm.observe(s,first+69)==first-1 and NHFarm.sync(s,first-1) and not s.resources.egg and rewards==0)
NHFarm.resetClock()
assert(NHFarm.observe(s,first+69)==first-1)
at=NHFarm.observe(s,first+70)
assert(at==first and NHFarm.due(s,at) and not view(at)[2].grown)
s.resources.meat=NHStore.maxResourceAmount
local changed,produced=NHFarm.sync(s,at)
assert(changed and not produced and not s.resources.egg and s.farm.pens[1].nextAt==first and rewards==0)
assert(view(at)[1].blocked and not NHFarm.due(s,at))
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
local hens=1+math.floor((at-first)/hen.period)
assert(s.resources.milk==12 and s.resources.meat==hens+12 and s.farm.pens[2].nextAt==at+cow.period)
assert(s.resources.egg==hens*2 and s.farm.pens[1].nextAt==first+hens*hen.period)
assert(not view(at)[2].blocked and not NHFarm.sync(s,at) and not s.materials.milk and #s.warehouse==0)
assert(NHStore.endRun(s,s.runSerial))
persist()
NHStore.newRun(s)
assert(NHFarm.observe(s,1)==at and NHFarm.observe(s,61)==at+60)
assert(view(at+60)[1].remaining==math.ceil((s.farm.pens[1].nextAt-at-60)/60) and view(at+60)[2].grown)
-- Older pens that had paused at their four stored cycles resume from here.
s.farm.passive=nil
s.farm.pens[1].nextAt=first
persist()
assert(s.farm.pens[1].nextAt==at-3*hen.period)
assert(NHFarm.sync(s,at) and s.resources.egg==(hens+4)*2 and s.farm.pens[1].nextAt==at+hen.period)
print("Livestock: timed automatic deposits, independent pens, caps, old pending batches and replay-safe rewards passed.")
