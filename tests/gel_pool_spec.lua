local settings,flags,failHead={},{},false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v)
    if failHead and k:match("_revision$") then error("failed to save") end
    settings[k]=v
end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
local function load() return assert(NHStore.load()) end
local function viewRow(rows,id)
    for _,row in ipairs(rows) do if row.id==id then return row end end
    error(id)
end

local start=499
local s=load()
NHStore.newRun(s)
s.materials={slime=249,water=150,soil_lush=70,soil=30}
local upgrade={id="gel_pool",level=0}
assert(not NHStore.buyUpgrade(s,upgrade,start) and s.materials.water==150 and not s.farm.pens)
s.materials.slime=250
assert(NHStore.buyUpgrade(s,upgrade,start) and not next(s.materials) and not NHStore.buyUpgrade(s,upgrade,start))
local pen=s.farm.pens[9]
local period=NHLivestock.species.gel_pool.period
assert(period==4*60*60 and pen.kind=="gel_pool" and pen.born==start and pen.nextAt==start+period)
assert(not NHLivestock.freePen(s,"gel_pool") and not NHStore.buyGood(s,{id="gel_pool"}))
s.gelBonus={seed=100,pending={}}
s.summons={gel_pool=100,pending={}}
assert(NHStore.commit(s))
local _,produced=NHFarm.sync(s,pen.nextAt-1)
assert(not produced and not s.resources.herb and s.gelBonus.seed==100 and s.summons.gel_pool==100)
local checkpoint=load()
local stale=load()
local _,did,awards=NHFarm.sync(s,start+period)
assert(did and #awards==1 and awards[1]=="slime" and s.resources.herb==4 and s.resources.fiber==6 and s.resources.spice==1)
local function warehouseItem(state,slot,kind)
    return state.warehouse[assert(NHStore.slotIndex(state,"warehouse",slot,kind))].item
end
local dose=warehouseItem(s,1,"dose")
assert(dose.subtype=="fire" and dose.remaining==3 and dose.count==1)
assert(warehouseItem(s,1,"summon_card").species=="slime" and NHStore.commit(s))
assert(NHFarm.sync(stale,start+period) and not NHStore.commit(stale))
s=load()
assert(not NHFarm.sync(s,start+period) and not NHFarm.sync(s,start+period-1))

-- The two 30% products share a roll; the 3% card uses a separate saved stream.
local hits,types=0,{}
for seed=1,100 do
    local trial=load()
    trial.gelBonus.seed=seed
    trial.warehouse,trial.resources={},{}
    NHGelPool.award(trial,1)
    local give=trial.resources.spice or 0
    assert(give==#trial.warehouse and (give==0 or give==1))
    hits=hits+give
    if give==1 then
        local medicine=warehouseItem(trial,1,"dose")
        assert(NHInjectors.types[medicine.subtype] and medicine.remaining==3 and medicine.count==1)
        types[medicine.subtype]=true
    end
end
assert(hits==30)
for _,id in ipairs(NHInjectors.order) do assert(types[id]) end
for _,rolls in ipairs({{100,1},{1,100},{1,1}}) do
    local replay=checkpoint
    replay.gelBonus={seed=rolls[1],pending={}}
    replay.summons={gel_pool=rolls[2],pending={}}
    replay.warehouse,replay.resources={},{}
    replay.farm.pens[9].nextAt=start+period
    local _,ok,cards=NHFarm.sync(replay,start+period)
    assert(ok and (replay.resources.spice==1)==(rolls[1]==100) and (#cards==1)==(rolls[2]==100))
end

-- A full supplies grid and capped spice ledger remember the original payout.
-- Releasing a slot in a failed commit must not change any previous row, ledger or RNG.
s.resources.spice=NHStore.maxResourceAmount
local original=s.warehouse[assert(NHStore.slotIndex(s,"warehouse",1,"dose"))]
original.item.remaining=2
local capacity=NHStore.warehouseCapacity(s,"supplies")
for slot=2,capacity do
    s.warehouse[#s.warehouse+1]={id=s.nextItemId,slot=slot,item={kind="medkit",remaining=1}}
    s.nextItemId=s.nextItemId+1
end
s.gelBonus.seed=100
NHFarm.sync(s,start+2*period)
assert(s.resources.herb==8 and s.resources.fiber==12 and s.gelBonus.spice==1
    and s.gelBonus.pending.fire==1 and original.item.remaining==2)
assert(NHStore.commit(s))
s=load()
local consumedSeed=s.gelBonus.seed
local farm=NHFarm.view(s,"en",s.farm.time)
assert(farm.gelPending==1 and farm.gelSpicePending==1)
assert(viewRow(farm.produce,"spice").perMinute==0.075 and viewRow(farm.produce,"herb").perMinute==1)
assert(viewRow(farm.crops,"fiber").perMinute==1.5)
s.resources.spice=s.resources.spice-1
table.remove(s.warehouse,NHStore.slotIndex(s,"warehouse",2,"dose"))
failHead=true
assert(not NHStore.commit(s) and s.gelBonus.spice==1 and s.gelBonus.pending.fire==1)
assert(not NHStore.slotIndex(s,"warehouse",2,"dose") and s.resources.spice==NHStore.maxResourceAmount-1)
failHead=false
assert(NHStore.commit(s))
s=load()
assert(warehouseItem(s,2,"dose").remaining==3 and warehouseItem(s,2,"dose").subtype=="fire")
assert(warehouseItem(s,1,"dose").remaining==2 and not next(s.gelBonus.pending) and not s.gelBonus.spice)
assert(s.resources.spice==NHStore.maxResourceAmount and s.gelBonus.seed==consumedSeed)
local dest=NHFarm.view(s,"zh",s.farm.time)
assert(dest.gelPending==0 and dest.gelSpicePending==0)
s.gelBonus.seed=100
NHFarm.sync(s,start+3*period)
assert(warehouseItem(s,2,"dose").count==2 and not next(s.gelBonus.pending))

-- Guaranteed harvests wait together if either primary resource is capped.
s.resources.herb=NHStore.maxResourceAmount-3
local before,cardStream=s.gelBonus.seed,s.summons.gel_pool
NHFarm.sync(s,start+4*period)
assert(s.farm.pens[9].nextAt==start+4*period and s.gelBonus.seed==before and s.summons.gel_pool==cardStream)
s.resources.herb=NHStore.maxResourceAmount-4
assert(NHFarm.due(s,s.farm.time) and NHFarm.sync(s,s.farm.time))
assert(s.resources.herb==NHStore.maxResourceAmount and s.resources.fiber==24)

-- Catch-up produces the same permanent rewards as individual live cycles.
local sequential,batched=load(),load()
for i=3,32 do NHFarm.sync(sequential,start+i*period) end
NHFarm.sync(batched,start+32*period)
assert(sequential.gelBonus.seed==batched.gelBonus.seed and sequential.summons.gel_pool==batched.summons.gel_pool)
for _,key in ipairs({"fiber","herb","spice"}) do assert(sequential.resources[key]==batched.resources[key]) end
assert(sequential.gelBonus.spice==batched.gelBonus.spice)
for _,id in ipairs(NHInjectors.order) do assert(sequential.gelBonus.pending[id]==batched.gelBonus.pending[id]) end
print("Gel pool: construction clock, guaranteed crops, independent rolls, four full-charge injectors, delayed deposits and replay passed.")
