local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local recipes={}
for _,r in ipairs(NHStore.recipes) do recipes[r.id]=r end
local tactical,advanced=recipes.tactical_medkit,recipes.advanced_medkit
assert(tactical.storedIngredient=="medkit" and tactical.resources.herb==4 and tactical.resources.essence_healing==2)
assert(advanced.storedIngredient=="tactical_medkit" and advanced.resources.herb==8 and advanced.resources.essence_healing==3)
assert(tactical.item.remaining==6 and advanced.item.remaining==6)
assert(NHStore.productionFrames(tactical)==60*60 and NHStore.productionFrames(advanced)==180*60)

local s=assert(NHStore.load())
local run=NHStore.newRun(s)
local function add(slot,kind,remaining)
    local row={id=s.nextItemId,slot=slot,item={kind=kind,remaining=remaining}}
    s.nextItemId=s.nextItemId+1
    s.warehouse[#s.warehouse+1]=row
    return row
end
local function deliver(slot,required)
    local order=s.order
    assert(order.output.slot==slot and order.required==required and NHStore.commit(s))
    s=assert(NHStore.load())
    assert(not NHStore.freeSlot(s,"warehouse",slot,order.output.item.kind))
    local request={orderId=order.id,run=run,progress=required-1}
    local changed,done=NHStore.advanceProduction(s,request)
    assert(changed and not done and NHStore.commit(s))
    s=assert(NHStore.load())
    request.progress=required
    changed,done=NHStore.advanceProduction(s,request)
    assert(changed and done and NHStore.commit(s))
    s=assert(NHStore.load())
    assert(not NHStore.advanceProduction(s,request))
    return s.warehouse[assert(NHStore.slotIndex(s,"warehouse",slot,order.output.item.kind))].item
end

s.resources={essence_healing=1000,herb=50}
s.safe[1]={id=s.nextItemId,slot=1,item={kind="medkit",remaining=3}}
s.nextItemId=s.nextItemId+1
assert(not NHStore.canStartBatch(s,tactical))
s.levels.medical=1
assert(not NHStore.canStartBatch(s,tactical) and NHStore.warehouseIngredientCount(s,"medkit")==0)
local other=add(5,"medkit",1)
local oldest=add(3,"medkit",1)
local full=add(4,"medkit") -- Legacy kits without a recorded charge count were full.
assert(NHMedkits.remaining(full.item)==8)
local count,index=NHStore.warehouseIngredientCount(s,"medkit")
assert(count==3 and s.warehouse[index]==oldest)
oldest.item.remaining=2
count,index=NHStore.warehouseIngredientCount(s,"medkit")
assert(count==3 and s.warehouse[index]==other)
oldest.item.remaining=1
s.resources.herb=3
assert(not NHStore.startOrder(s,tactical.id) and #s.warehouse==3 and s.resources.essence_healing==1000)
s.resources.herb=50
s.resources.essence_healing=1
assert(not NHStore.startOrder(s,tactical.id) and #s.warehouse==3 and s.resources.herb==50)
s.resources.essence_healing=1000
for slot=1,NHStore.warehouseCapacity(s,"supplies") do
    if not NHStore.slotIndex(s,"warehouse",slot,"grenade") then add(slot,"grenade") end
end
assert(not NHStore.freeSlot(s,"warehouse",nil,"medkit"))
assert(NHStore.startOrder(s,tactical.id) and not NHStore.startOrder(s,tactical.id))
assert(s.order.output.slot==3 and s.resources.essence_healing==998 and s.resources.herb==46)
local first=deliver(3,3600)
assert(first.kind=="tactical_medkit" and first.remaining==6 and first.count==4 and s.safe[1].item.remaining==3)

first.remaining=0
assert(not NHStore.startOrder(s,advanced.id) and not s.order and s.resources.herb==46)
first.remaining=1
assert(not NHStore.startOrder(s,advanced.id)) -- The other three kits still occupy this slot.
first.count=1
assert(NHStore.startOrder(s,advanced.id))
local second=deliver(3,10800)
assert(second.kind=="advanced_medkit" and second.remaining==6 and second.count==4)
assert(s.resources.herb==38 and s.resources.essence_healing==995)
assert(not NHStore.canStartBatch(s,advanced))

second.remaining=0
assert(not NHStore.commit(s))
second.remaining=13
assert(not NHStore.commit(s))
second.remaining=6
second.count=5
assert(not NHStore.commit(s))
assert(assert(NHStore.load()).finished==2)
print("Medkit workshop: two upgrades, fixed costs, worn kits first, full warehouse, reload and exact delivery passed.")
