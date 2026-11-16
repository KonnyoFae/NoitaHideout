local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local s=assert(NHStore.load())
local run=NHStore.newRun(s)
s.levels.farmland,s.levels.medical=1,1
s.resources={fiber=2,sugar=3,grain=2,herb=2}
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
s.resources.fiber=1
assert(not NHStore.startOrder(s,"bandage") and s.resources.sugar==3)
s.resources.fiber=2
assert(NHStore.startOrder(s,"bandage") and not s.resources.fiber and s.resources.sugar==2)
finish()
assert(s.warehouse[1].item.kind=="bandage")

-- Fill the supply grid, then convert the real bandage in-place. The slot
-- remains reserved while the medkit is being produced.
local limit=NHStore.warehouseCapacity(s,"supplies")
for slot=2,limit do
    s.warehouse[slot]={slot=slot,id=s.nextItemId,item={kind="grenade"}}
    s.nextItemId=s.nextItemId+1
end
local consumedId=s.warehouse[1].id
assert(NHStore.commit(s))
local old=assert(NHStore.load())
assert(NHStore.startOrder(s,"field_medkit") and s.order.output.slot==1)
assert(not s.resources.herb and #s.warehouse==limit-1 and not NHStore.freeSlot(s,"warehouse",1,"dose"))
assert(NHStore.commit(s))
assert(NHStore.startOrder(old,"field_medkit") and not NHStore.commit(old))
s=assert(NHStore.load())
assert(not NHStore.startOrder(s,"field_medkit") and s.order.output.slot==1)
finish()
local medkit=s.warehouse[NHStore.slotIndex(s,"warehouse",1,"medkit")]
assert(medkit.item.kind=="medkit" and medkit.item.remaining==3 and medkit.id~=consumedId)
assert(#s.warehouse==limit and s.safe[1].item.kind=="bandage" and s.materials.blood==50)

-- A full warehouse rejects a food order before taking the harvest.
assert(not NHStore.startOrder(s,"bread") and s.resources.grain==2)
table.remove(s.warehouse,1)
table.remove(s.warehouse,1)
assert(NHStore.startOrder(s,"bread") and not s.resources.grain)
finish()
assert(s.warehouse[#s.warehouse].item.kind=="bread")
assert(NHStore.startOrder(s,"sugar_cube") and not s.resources.sugar)
finish()
assert(s.warehouse[#s.warehouse].item.kind=="sugar_cube")
assert(s.materials.water==100 and s.materials.blood==50 and s.materials.fiber==1000)
print("Farm crafting: all four products, warehouse-only bandage payment, full slots, stale commits and single delivery passed.")
