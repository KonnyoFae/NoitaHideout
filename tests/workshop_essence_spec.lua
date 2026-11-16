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
local recipe=assert(recipes.medical)
assert(recipe.category=="medical" and recipe.facility=="medical" and not recipe.resources)
assert(recipe.item.kind=="medkit" and recipe.item.remaining==3)
assert(not recipes.medkit_essence)
local healingCost={medkit=0}
for _,kind in ipairs({"tactical_medkit","advanced_medkit","field_surgery_kit","tactical_surgery_kit","advanced_surgery_kit"}) do
    local upgrade=assert(recipes[kind])
    healingCost[kind]=healingCost[upgrade.storedIngredient]+upgrade.resources.essence_healing
    assert(healingCost[kind]<=9 and healingCost[kind]*10<=NHEssences.values.HEAL_BULLET)
end
assert(healingCost.advanced_medkit==5 and healingCost.advanced_surgery_kit==9)
for _,entry in ipairs(NHStore.recipes) do
    if entry.item and entry.item.kind=="medkit" then
        assert(not (entry.resources and entry.resources.essence_healing))
    end
end

local s=assert(NHStore.load())
local run=NHStore.newRun(s)
s.resources.essence_healing=175
assert(not NHStore.startOrder(s,recipe.id) and not s.order)
s.levels.medical=1
local ok,reason=NHStore.startOrder(s,"medkit_essence")
assert(not ok and reason=="Unknown recipe." and not s.order and s.resources.essence_healing==175)
s.materials={water=100,blood=49}
local started,reason=NHStore.startOrder(s,recipe.id)
assert(not started and reason=="Not enough bulk ingredients." and not s.order)
assert(s.materials.water==100 and s.materials.blood==49 and s.resources.essence_healing==175)

s.materials.blood=50
assert(NHStore.commit(s))
for slot=1,NHStore.warehouseCapacity(s,"supplies") do
    s.warehouse[slot]={slot=slot,id=s.nextItemId,item={kind="medkit",remaining=3}}
    s.nextItemId=s.nextItemId+1
end
started,reason=NHStore.startOrder(s,recipe.id)
assert(not started and reason=="Product storage is full." and s.materials.water==100 and s.materials.blood==50)

s=assert(NHStore.load())
local stale=assert(NHStore.load())
assert(NHStore.startOrder(s,recipe.id) and NHStore.commit(s))
assert(not s.materials.water and not s.materials.blood and s.resources.essence_healing==175)
assert(not NHStore.freeSlot(s,"warehouse",s.order.output.slot,"medkit"))
assert(NHStore.startOrder(stale,recipe.id) and not NHStore.commit(stale))
s=assert(NHStore.load())
assert(not NHStore.startOrder(s,recipe.id) and s.resources.essence_healing==175)

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

-- A prepaid 0.20.0 order already contains its output and reserved slot.
-- Loading it in the new version must deliver exactly once without another charge.
s.order={id=s.finished+1,recipe="medkit_essence",progress=60,required=7200,output={item={
    kind="medkit",remaining=3,name="$nh_hideout_medkit",icon="mods/noita_hideout/files/items/medkit.png",
},slot=2}}
s.resources.essence_healing=145
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(s.order.progress==60 and not NHStore.freeSlot(s,"warehouse",2,"medkit"))
deliver()
assert(#s.warehouse==2 and s.finished==2 and s.resources.essence_healing==145)
assert(s.warehouse[2].slot==2 and s.warehouse[2].item.kind=="medkit" and s.warehouse[2].item.remaining==3)

-- Previously paid fire-essence orders keep their untyped fire injector.
assert(not recipes.injector_essence)
s.order={id=s.finished+1,recipe="injector_essence",progress=60,required=7200,
    output={item={kind="dose",remaining=3,count=1},slot=3}}
deliver()
assert(NHInjectors.get(s.warehouse[3].item.subtype).id=="fire")
for _,typeId in ipairs(NHInjectors.order) do
    local d=NHInjectors.get(typeId)
    local entry=recipes[typeId=="fire" and "injector" or "injector_"..typeId]
    assert(entry.item.subtype==typeId and entry.category=="medical" and entry.facility=="injector")
    assert(entry.resources.active_herb==2 and entry.resources[d.essence]==d.cost and #entry.inputs==0)
    local original=s.resources[d.essence] or 0
    s.resources[d.essence]=d.cost+original
    s.resources.active_herb=1
    s.levels.injector=1
    assert(not NHStore.startOrder(s,entry.id) and s.resources[d.essence]==d.cost+original)
    s.resources.active_herb=2
    assert(NHStore.startOrder(s,entry.id) and not s.resources.active_herb)
    assert((s.resources[d.essence] or 0)==original)
    deliver()
    local item=s.warehouse[#s.warehouse].item
    assert(item.kind=="dose" and item.subtype==typeId and item.remaining==3 and item.count==1)
end
for _,example in ipairs({
    {id="grenade_essence",base="grenade",category="weapons",key="essence_high_energy",cost=4,kind="grenade"},
}) do
    local entry,original=recipes[example.id],recipes[example.base]
    assert(entry.category==example.category and entry.facility==original.facility and entry.item.kind==original.item.kind and entry.item.count==8 and original.item.count==8)
    assert(entry.resources[example.key]==example.cost and #entry.inputs==0)
    s.resources[example.key]=example.cost
    local ok,reason=NHStore.startOrder(s,entry.id)
    assert(not ok and reason=="Facility is locked." and s.resources[example.key]==example.cost)
    s.levels[entry.facility]=1
    s.resources[example.key]=example.cost-1
    -- A material with a matching name cannot substitute for hideout resources.
    s.materials[example.key]=example.cost
    ok,reason=NHStore.startOrder(s,entry.id)
    assert(not ok and reason=="Not enough workshop resources." and not s.order)
    s.resources[example.key]=example.cost
    for _,part in ipairs(original.inputs) do s.materials[part.name]=part.amount end
    assert(NHStore.startOrder(s,entry.id) and not s.resources[example.key])
    assert(s.materials[example.key]==example.cost)
    assert(not NHStore.startOrder(s,entry.id))
    deliver()
    local item=s.warehouse[#s.warehouse].item
    assert(item.kind==example.kind and NHStore.category(item.kind)=="supplies")
    for _,part in ipairs(original.inputs) do assert(s.materials[part.name]==part.amount) end
    assert(NHStore.startOrder(s,original.id))
    deliver()
    assert(s.warehouse[#s.warehouse].item.kind==example.kind)
end
assert(s.finished==5+#NHInjectors.order and #s.warehouse==s.finished)

-- Healing spells still fund the hideout's healing essence balance.
s.levels.salvage=1
local spellId=s.nextItemId
s.nextItemId=spellId+1
s.warehouse[#s.warehouse+1]={slot=1,id=spellId,item={
    kind="spell",card={id="HEAL_BULLET",item={uses_remaining=0}},
}}
assert(NHStore.salvage(s,{kind="spell",slot=1,id=spellId,mode="essence"}))
assert(s.resources.essence_healing==145+175 and NHStore.commit(s))
s=assert(NHStore.load())
assert(s.resources.essence_healing==320 and not NHStore.startOrder(s,"medkit_essence"))
print("Workshop: material-funded medkits, prepaid kit delivery, healing essence savings, all injector recipes and grenades passed.")
