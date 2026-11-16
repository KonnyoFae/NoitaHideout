local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key]==true end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local recipes={}
for _,entry in ipairs(NHStore.recipes) do
    recipes[entry.id]=entry
end
local recipe=recipes.medkit_essence
assert(recipe and recipe.category=="medical" and recipe.facility=="medical")
local cost=recipe.resources.essence_healing
assert(cost==30 and recipe.item.kind=="medkit" and recipe.item.remaining==3)

local s=assert(NHStore.load())
local run=NHStore.newRun(s)
s.resources.essence_healing=2*cost
assert(not NHStore.startOrder(s,recipe.id) and not s.order)
s.levels.medical=1
-- The workshop spends only the corresponding hideout resource. A material
-- or unrelated essence of the same amount cannot pay for a missing unit.
s.materials={essence_healing=cost,water=100,blood=50}
s.resources.essence_high_energy=cost
s.resources.essence_healing=cost-1
local started,reason=NHStore.startOrder(s,recipe.id)
assert(not started and reason=="Not enough workshop resources." and not s.order)
assert(s.resources.essence_healing==cost-1 and s.materials.essence_healing==cost)

s.resources.essence_healing=2*cost
assert(NHStore.commit(s))
for slot=1,NHStore.warehouseCapacity(s,"supplies") do
    s.warehouse[slot]={slot=slot,id=s.nextItemId,item={kind="medkit",remaining=3}}
    s.nextItemId=s.nextItemId+1
end
started,reason=NHStore.startOrder(s,recipe.id)
assert(not started and reason=="Product storage is full." and s.resources.essence_healing==2*cost)

s=assert(NHStore.load())
local stale=assert(NHStore.load())
assert(NHStore.startOrder(s,recipe.id) and NHStore.commit(s))
assert(s.resources.essence_healing==cost and s.resources.essence_high_energy==cost)
assert(not NHStore.freeSlot(s,"warehouse",s.order.output.slot,"medkit"))
assert(NHStore.startOrder(stale,recipe.id) and not NHStore.commit(stale))
s=assert(NHStore.load())
assert(not NHStore.startOrder(s,recipe.id) and s.resources.essence_healing==cost)

local function deliver()
    assert(s.order and NHStore.commit(s))
    s=assert(NHStore.load())
    local request={run=run,orderId=s.order.id,progress=s.order.required}
    local changed,finished=NHStore.advanceProduction(s,request)
    assert(changed and finished and not s.order)
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
    assert(not NHStore.advanceProduction(s,request))
end
deliver()
assert(#s.warehouse==1 and s.warehouse[1].item.kind=="medkit" and s.warehouse[1].item.remaining==3)
assert(NHStore.startOrder(s,recipe.id) and not s.resources.essence_healing)
deliver()
assert(#s.warehouse==2 and s.warehouse[1].id~=s.warehouse[2].id)
assert(s.materials.water==100 and s.materials.blood==50 and s.materials.essence_healing==cost)
assert(NHStore.startOrder(s,"medical") and not s.materials.water and not s.materials.blood)
deliver()
assert(#s.warehouse==3 and s.finished==3 and s.resources.essence_high_energy==cost)

for _,example in ipairs({
    {id="injector_essence",base="injector",category="medical",key="essence_fire",cost=180,kind="dose"},
    {id="grenade_essence",base="grenade",category="weapons",key="essence_high_energy",cost=30,kind="grenade"},
}) do
    local entry,original=recipes[example.id],recipes[example.base]
    assert(entry.category==example.category and entry.facility==original.facility and entry.item==original.item)
    assert(entry.resources[example.key]==example.cost and #entry.inputs==0)
    s.resources[example.key]=example.cost
    local ok,reason=NHStore.startOrder(s,entry.id)
    assert(not ok and reason=="Facility is locked." and s.resources[example.key]==example.cost)
    s.levels[entry.facility]=1
    s.resources[example.key]=example.cost-1
    ok,reason=NHStore.startOrder(s,entry.id)
    assert(not ok and reason=="Not enough workshop resources." and not s.order)
    s.resources[example.key]=example.cost
    for _,part in ipairs(original.inputs) do s.materials[part.name]=part.amount end
    assert(NHStore.startOrder(s,entry.id) and not s.resources[example.key])
    assert(not NHStore.startOrder(s,entry.id))
    deliver()
    local item=s.warehouse[#s.warehouse].item
    assert(item.kind==example.kind and NHStore.category(item.kind)=="supplies")
    if item.kind=="dose" then assert(item.remaining==3 and item.count==1) end
    for _,part in ipairs(original.inputs) do assert(s.materials[part.name]==part.amount) end
    assert(NHStore.startOrder(s,original.id))
    deliver()
    assert(s.warehouse[#s.warehouse].item.kind==example.kind)
end
assert(s.finished==7 and #s.warehouse==7)

-- A spent healing bolt must fund the same five complete medkits as a fresh
-- card. Saving after each delivery preserves the 25 HP of unused buying power.
s.levels.salvage=1
local spellId=s.nextItemId
s.nextItemId=spellId+1
s.warehouse[#s.warehouse+1]={slot=1,id=spellId,item={
    kind="spell",card={id="HEAL_BULLET",item={uses_remaining=0}},
}}
assert(NHStore.salvage(s,{kind="spell",slot=1,id=spellId,mode="essence"}))
assert(s.resources.essence_healing==175)
for i=1,5 do
    assert(NHStore.startOrder(s,"medkit_essence"))
    deliver()
    local kit=s.warehouse[#s.warehouse].item
    assert(kit.kind=="medkit" and kit.remaining==3)
    assert(s.resources.essence_healing==175-30*i)
end
assert(not NHStore.startOrder(s,"medkit_essence") and s.resources.essence_healing==25)
print("Workshop essences: exact payment for medkits, fire injectors and grenades, source isolation, reserved storage and single delivery passed.")
