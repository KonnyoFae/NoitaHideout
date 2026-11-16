local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local s=assert(NHStore.load())
local run=NHStore.newRun(s)
assert(NHStore.productionFrames()==120*60)
assert(NHStore.productionFrames({durationFrames=180*60})==180*60)
assert(NHStore.productionFrames({durationFrames=180*60+1})==180*60)
s.levels.farmland,s.levels.medical=1,1
s.resources={fiber=4,sugar=4,grain=2,herb=2}
s.materials={water=100,blood=50}
local function finish()
    assert(s.order and NHStore.commit(s))
    s=assert(NHStore.load())
    local request={run=run,orderId=s.order.id,progress=s.order.required}
    local changed,complete=NHStore.advanceProduction(s,request)
    assert(changed and complete and NHStore.commit(s))
    s=assert(NHStore.load())
    assert(not NHStore.advanceProduction(s,request))
end
-- A bandage in the secure case and an identical bulk-material name are
-- both outside the recipe's supply warehouse input.
s.safe[1]={id=s.nextItemId,slot=1,item={kind="bandage"}}
s.nextItemId=s.nextItemId+1
s.materials.fiber=1000
assert(not NHStore.startOrder(s,"field_medkit") and s.resources.herb==2)
s.resources.fiber=3
assert(not NHStore.startOrder(s,"bandage") and s.resources.sugar==4)
s.resources.fiber,s.resources.sugar=4,1
assert(not NHStore.startOrder(s,"bandage") and s.resources.fiber==4)
s.resources.sugar=4
assert(NHStore.startOrder(s,"bandage") and not s.resources.fiber and s.resources.sugar==2)
finish()
assert(#s.warehouse==1 and s.warehouse[1].item.kind=="bandage" and s.warehouse[1].item.count==8)

-- A partial stack must keep its slot. At full capacity either kind of
-- production must fail before taking any resources or rolls.
local limit=NHStore.warehouseCapacity(s,"supplies")
for slot=2,limit do
    s.warehouse[slot]={slot=slot,id=s.nextItemId,item={kind="grenade"}}
    s.nextItemId=s.nextItemId+1
end
s.resources.fiber=4
assert(not NHStore.startOrder(s,"bandage") and s.resources.fiber==4 and s.resources.sugar==2)
assert(not NHStore.startOrder(s,"field_medkit") and s.resources.herb==2 and s.warehouse[1].item.count==8)
assert(not s.order and NHStore.warehouseIngredientCount(s,"bandage")==8)
-- A separately stored last roll, including a legacy record without count,
-- can pay for a medkit and free up its own slot even with the earlier stack.
s.warehouse[2].item={kind="bandage"}
local consumedId=s.warehouse[2].id
assert(NHStore.warehouseIngredientCount(s,"bandage")==9)
assert(NHStore.commit(s))
local old=assert(NHStore.load())
assert(NHStore.startOrder(s,"field_medkit") and s.order.output.slot==2)
assert(not s.resources.herb and #s.warehouse==limit-1 and not NHStore.freeSlot(s,"warehouse",2,"dose"))
assert(NHStore.commit(s))
assert(NHStore.startOrder(old,"field_medkit") and not NHStore.commit(old))
s=assert(NHStore.load())
assert(not NHStore.startOrder(s,"field_medkit") and s.order.output.slot==2)
finish()
local medkit=s.warehouse[NHStore.slotIndex(s,"warehouse",2,"medkit")]
assert(medkit.item.kind=="medkit" and medkit.item.remaining==3 and medkit.id~=consumedId)
assert(s.warehouse[1].item.count==8)
assert(#s.warehouse==limit and s.safe[1].item.kind=="bandage" and s.materials.blood==50)

-- A full warehouse rejects a food order before taking the harvest.
assert(not NHStore.startOrder(s,"bread") and s.resources.grain==2)
table.remove(s.warehouse,1)
table.remove(s.warehouse,1)
assert(NHStore.startOrder(s,"bread") and not s.resources.grain and s.order.required==5*60)
finish()
assert(s.warehouse[#s.warehouse].item.kind=="bread")
assert(NHStore.startOrder(s,"sugar_cube") and s.resources.sugar==1 and s.order.required==3*60)
finish()
assert(s.warehouse[#s.warehouse].item.kind=="sugar_cube")
assert(s.materials.water==100 and s.materials.blood==50 and s.materials.fiber==1000)

-- The alternate medkit recipe makes the same three-use kit. A mountain visit
-- that is longer than its remaining five seconds credits exactly one kit.
local free=table.remove(s.warehouse)
assert(NHStore.startOrder(s,"medical") and s.order.required==5*60 and s.order.output.slot==free.slot)
local boost={run=run,orderId=s.order.id,checkpoint="first workshop",progress=1}
local changed,delivered=NHStore.advanceProduction(s,boost)
assert(changed and delivered and NHStore.commit(s))
s=assert(NHStore.load())
assert(not s.order and not NHStore.advanceProduction(s,boost) and #s.warehouse==limit)
local quickKit=s.warehouse[NHStore.slotIndex(s,"warehouse",free.slot,"medkit")].item
assert(quickKit.kind=="medkit" and quickKit.remaining==3 and not s.materials.water and not s.materials.blood)
print("Farm crafting: all four products, warehouse-only bandage payment, full slots, stale commits and single delivery passed.")
