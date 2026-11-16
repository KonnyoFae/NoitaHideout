local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")

local byId={}
for _,recipe in ipairs(NHStore.recipes) do byId[recipe.id]=recipe end
local expected={
    {id="grenade",seconds=10,materials={sand=64,slime=32}},
    {id="grenade_essence",seconds=10,cost=4,essence="essence_high_energy",spell="BOMB"},
    {id="fire_grenade",seconds=10,cost=6,essence="essence_fire",spell="FIREBALL"},
    {id="frost_grenade",seconds=10,cost=6,essence="essence_frost",spell="ICEBALL"},
    {id="shock_grenade",seconds=10,cost=6,essence="essence_lightning",spell="LIGHTNING"},
    {id="sand_knife",seconds=5,materials={sand=40}},
    {id="metal_knife",seconds=8,materials={metal_sand=1,steel_sand=9,copper=20,brass=20,silver=14}},
}
local function load() return assert(NHStore.load()) end
local s=load()
local run=NHStore.newRun(s)
local function persist()
    assert(NHStore.commit(s))
    s=load()
end
local function finish()
    local request={orderId=s.order.id,run=run,progress=s.order.required}
    local changed,done=NHStore.advanceProduction(s,request)
    assert(changed and done)
    assert(not NHStore.advanceProduction(s,request))
end
for _,test in ipairs(expected) do
    local recipe=assert(byId[test.id])
    local kind=recipe.item.kind
    assert(kind==(test.id=="grenade_essence" and "grenade" or test.id))
    assert(recipe.category=="weapons" and recipe.facility=="grenade")
    assert(recipe.count==8 and recipe.item.count==8 and NHStore.category(kind)=="supplies")
    assert(NHStore.productionFrames(recipe)==test.seconds*60)
    s.levels.grenade=0
    assert(not NHStore.startOrder(s,test.id))
    s.levels.grenade=1
    if test.essence then
        assert(recipe.resources[test.essence]==test.cost and NHEssences.byAction[test.spell]==test.essence)
        assert(recipe.resources[test.essence]*10<=NHEssences.values[test.spell])
        s.resources[test.essence]=test.cost-1
        assert(not NHStore.startOrder(s,test.id) and not s.order and s.resources[test.essence]==test.cost-1)
        s.resources[test.essence]=test.cost
    else
        assert(not recipe.resources)
        for material,amount in pairs(test.materials) do s.materials[material]=amount end
        local scarce=test.id=="metal_knife" and "silver" or "sand"
        s.materials[scarce]=s.materials[scarce]-1
        assert(not NHStore.startOrder(s,test.id) and not s.order)
        s.materials[scarce]=s.materials[scarce]+1
    end
    assert(NHStore.startOrder(s,test.id) and not NHStore.startOrder(s,test.id))
    assert(not next(s.resources) and not next(s.materials))
    persist()
    local reserved=s.order.output.slot
    assert(s.order.output.item.count==8 and not NHStore.freeSlot(s,"warehouse",reserved,kind))
    finish()
    persist()
    local row=s.warehouse[assert(NHStore.slotIndex(s,"warehouse",reserved,kind))]
    assert(row.item.kind==kind and row.item.count==8)
end

-- A previous paid recipe already owned a specific single grenade and duration.
s.order={id=s.finished+1,recipe="grenade_essence",progress=479,required=7200,
    output={slot=8,item={kind="grenade",name="$nh_hideout_grenade"}}}
persist()
assert(s.order.required==7200 and s.order.progress==479 and NHThrowables.count(s.order.output.item)==1)
finish()
persist()
local oldItem=s.warehouse[assert(NHStore.slotIndex(s,"warehouse",8,"grenade"))].item
assert(NHThrowables.count(oldItem)==1)
oldItem.count=0
assert(not NHStore.commit(s))
s=load()
s.warehouse[1].item.count=3
persist()
assert(s.warehouse[1].item.count==3)
for _,bad in ipairs({{kind="frost_grenade"}, {kind="metal_knife",count=9}, {kind="sand_knife",count=1.5}}) do
    s.safe[1]={id=s.nextItemId,slot=1,item=bad}
    s.nextItemId=s.nextItemId+1
    assert(not NHStore.commit(s))
    s=load()
end
-- Adding batch recipes must not change the merchant's single-item supplies.
assert(NHStore.creditGold(s,280))
for _,id in ipairs({"medkit","injector"}) do
    assert(NHStore.buyGood(s,{id=id}))
    assert((s.warehouse[#s.warehouse].item.count or 1)==1)
end
assert(s.bankGold==0)
print("Throwable workshop: seven batch recipes, atomic costs, mixed metal powders, legacy deliveries and partial bundles passed.")
