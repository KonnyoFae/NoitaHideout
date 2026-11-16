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
state.materials={sand=2000,water=1350}
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
local function harvest(slot)
    local plot=state.farm.plots[slot]
    assert(NHFarm.harvest(state,{plot=slot,token=plot.token,crop=plot.crop},now))
end
plant(1,"grain")
plant(2,"spice")
plant(3,"herb")
plant(4,"sugar")
now=NHFarm.observe(state,300*60)
for slot=1,4 do harvest(slot) end
plant(1,"grain")
plant(2,"spice")
now=NHFarm.observe(state,600*60)
harvest(1)
harvest(2)
for pen,animal in ipairs(state.farm.pens) do
    assert(NHLivestock.collect(state,{pen=pen,nextAt=animal.nextAt},now))
end
assert(state.resources.egg==6 and state.resources.milk==2 and state.resources.meat==5)
assert(NHStore.commit(state))
state=assert(NHStore.load())
for _,food in ipairs({"herb_flatbread","spice_cake","milk_omelet","spiced_stew"}) do
    assert(NHStore.startOrder(state,food))
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    local order=state.order
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
assert(state.resources.spice==1 and state.resources.herb==2 and state.resources.grain==5 and state.resources.sugar==2)
assert(state.resources.egg==4 and not state.resources.milk and state.resources.meat==3)
assert(not NHStore.startOrder(state,"milk_omelet") and state.resources.egg==4)
assert(NHStore.commit(state))
print("Farm and ranch produce paid for all four advanced dishes across order reloads.")
