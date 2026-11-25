local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")

local byId={}
for _,recipe in ipairs(NHStore.recipes) do byId[recipe.id]=recipe end
local expected={
    {id="grenade",seconds=10,materials={sand=16,sandstone=48,slime_green=12,slime_yellow=20}},
    {id="grenade_essence",seconds=10,cost=4,essence="essence_high_energy",spell="BOMB"},
    {id="fire_grenade",seconds=10,cost=6,essence="essence_fire",spell="FIREBALL"},
    {id="frost_grenade",seconds=10,cost=6,essence="essence_frost",spell="ICEBALL"},
    {id="shock_grenade",seconds=10,cost=6,essence="essence_lightning",spell="LIGHTNING"},
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
    local expectedKind=({grenade="magic_tube",grenade_essence="magic_tube",fire_grenade="fire_tube",frost_grenade="frost_tube",shock_grenade="shock_tube"})[test.id]
    assert(kind==expectedKind)
    assert(recipe.category=="weapons" and recipe.facility=="grenade")
    local quantity=test.essence and 4 or 1
    assert(recipe.count==quantity and recipe.item.remaining==6 and recipe.item.count==quantity and NHStore.category(kind)=="supplies")
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
    assert(s.order.output.item.count==quantity and s.order.output.item.remaining==6 and not NHStore.freeSlot(s,"warehouse",reserved,kind))
    finish()
    persist()
    local row=s.warehouse[assert(NHStore.slotIndex(s,"warehouse",reserved,kind))]
    assert(row.item.kind==kind and row.item.count==(test.id=="grenade_essence" and 5 or quantity) and row.item.remaining==6)
end

-- A partly fired tube and a new four-pack can share the same cell in either direction.
local partial={kind="fire_tube",remaining=3,count=1}
local slot,index=NHStore.stackSlot(s,"warehouse",partial)
assert(slot and index)
local tubes=s.warehouse[index].item
NHStore.mergeStack(tubes,partial)
assert(tubes.count==5 and tubes.remaining==3 and NHGuns.rounds(tubes)==27)
assert(not NHStore.stackSlot(s,"warehouse",partial))
assert(NHStore.stackSlot(s,"warehouse",byId.fire_grenade.item)==slot)
persist()

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
assert(NHStore.creditGold(s,130))
for _,id in ipairs({"medkit","injector"}) do
    assert(NHStore.buyGood(s,{id=id}))
    assert((s.warehouse[#s.warehouse].item.count or 1)==1)
end
assert(s.bankGold==0)
print("Throwable workshop: seven batch recipes, atomic costs, mixed metal powders, legacy deliveries and partial bundles passed.")
for _,cost in ipairs({
    {kind="derringer",powder=10,gold=10,rounds=4},
    {kind="flare_gun",powder=20,resource="spice",units=10,gold=200,rounds=20},
    {kind="sedative_launcher",powder=20,resource="herb",units=10,gold=50,rounds=20},
}) do
    local kind=cost.kind
    local fresh=load()
    fresh.warehouse={}
    fresh.levels.grenade=1
    fresh.materials={gunpowder=cost.powder}
    fresh.resources={}
    if cost.resource then fresh.resources[cost.resource]=cost.units end
    fresh.bankGold=cost.gold
    local function checkShortage(stock,key)
        stock[key]=stock[key]-1
        assert(not NHStore.craft(fresh,kind) and not fresh.order and #fresh.warehouse==0,kind)
        stock[key]=stock[key]+1
        assert(fresh.materials.gunpowder==cost.powder and fresh.bankGold==cost.gold,kind)
        if cost.resource then assert(fresh.resources[cost.resource]==cost.units,kind) end
    end
    checkShortage(fresh.materials,"gunpowder")
    checkShortage(fresh,"bankGold")
    if cost.resource then checkShortage(fresh.resources,cost.resource) end
    for i=1,2 do
        fresh.materials.gunpowder=cost.powder
        if cost.resource then fresh.resources[cost.resource]=cost.units end
        fresh.bankGold=cost.gold
        assert(NHStore.craft(fresh,kind))
        assert(not fresh.order and not next(fresh.materials) and not next(fresh.resources) and fresh.bankGold==0)
        local item=fresh.warehouse[1].item
        assert(#fresh.warehouse==1 and item.kind==kind and item.remaining==cost.rounds and item.count==i)
    end
    if kind=="derringer" then
        assert(not NHStore.stackSlot(fresh,"warehouse",{kind=kind,remaining=3}))
    end
end
