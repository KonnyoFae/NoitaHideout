-- Start with money and construction materials, then grow every cooking ingredient.
local settings,flags,globals={},{},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
function GlobalsGetValue(key,fallback) return globals[key] or fallback end
function GlobalsSetValue(key,value) globals[key]=value end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
local state=assert(NHStore.load())
local run=NHStore.newRun(state)
state.bankGold=360
state.materials={soil=1500,sand=500,water=1350}
for level=0,3 do assert(NHStore.buyUpgrade(state,{id="farmland",level=level})) end
assert(not NHStore.startOrder(state,"herb_flatbread"))
assert(NHStore.buyUpgrade(state,{id="agri_equipment",level=0}))
assert(NHStore.buyUpgrade(state,{id="livestock",level=0}))
assert(not next(state.materials))
local now=NHFarm.observe(state,0)
assert(NHStore.buyGood(state,{id="chick"},now))
assert(NHStore.buyGood(state,{id="calf"},now) and state.bankGold==0)
local function plant(slot,crop)
    assert(NHFarm.plant(state,{plot=slot,token=(state.farm.plots[slot] or {}).token or 0,crop=crop},now))
end
plant(1,"grain")
plant(2,"spice")
plant(3,"herb")
plant(4,"sugar")
now=NHFarm.observe(state,600*60)
assert(NHFarm.sync(state,now) and not NHFarm.sync(state,now))
assert(state.resources.egg==6 and state.resources.milk==2 and state.resources.meat==5)
assert(NHStore.commit(state))
state=assert(NHStore.load())
for _,dish in ipairs({{"herb_flatbread",15},{"spice_cake",20},{"milk_omelet",30},{"spiced_stew",45}}) do
    local food,seconds=dish[1],dish[2]
    assert(NHStore.startOrder(state,food))
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    local order=state.order
    assert(order.required==seconds*60)
    local ok,done=NHStore.advanceProduction(state,{run=run,orderId=order.id,progress=order.required})
    assert(ok and done)
    local found=0
    for _,row in ipairs(state.warehouse) do
        if row.item.kind==food then
            assert(NHStore.category(food)=="supplies" and row.item.icon:find(food,1,true))
            found=found+1
        end
    end
    assert(found==1)
end
assert(state.resources.spice==1 and state.resources.herb==10 and state.resources.grain==13 and state.resources.sugar==14)
assert(state.resources.egg==5 and not state.resources.milk and state.resources.meat==3)
assert(not NHStore.startOrder(state,"milk_omelet") and state.resources.egg==5)
assert(NHStore.commit(state))
print("Farm and ranch produce paid for all four advanced dishes across order reloads.")

-- Repeat an order into a partly eaten stack across commits, even at capacity.
state.resources.grain=10
local function cook(id)
    assert(NHStore.startOrder(state,id))
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    local order=state.order
    assert(NHStore.advanceProduction(state,{run=run,orderId=order.id,progress=order.required}))
end
cook("bread")
local index=NHStore.slotIndex(state,"warehouse",state.warehouse[#state.warehouse].slot,"bread")
state.warehouse[index].item.remaining=1
while true do
    local slot=NHStore.freeSlot(state,"warehouse",nil,"bandage")
    if not slot then break end
    table.insert(state.warehouse,{id=state.nextItemId,slot=slot,item={kind="bandage"}})
    state.nextItemId=state.nextItemId+1
end
cook("bread")
assert(state.warehouse[index].item.count==2 and state.warehouse[index].item.remaining==1)
local use=dofile("mods/noita_hideout/files/inventory_use.lua")
local row=state.warehouse[index]
assert(use.spend(state,1,{container="warehouse",slot=row.slot,kind="bread",storedId=row.id,count=2,remaining=1}))
assert(row.item.count==1 and row.item.remaining==2)
assert(NHStore.commit(state))
