-- Grow the ingredients and use the real workshop orders against one saved profile.
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
state.materials={soil=350,soil_lush=1150,water=1250,slime=100}
for level=0,3 do assert(NHStore.buyUpgrade(state,{id="farmland",level=level})) end
assert(NHStore.buyUpgrade(state,{id="medical",level=0}))
assert(not next(state.materials))

local plots={"fiber","herb","grain","sugar"}
local now=NHFarm.observe(state,0)
for slot,crop in ipairs(plots) do
    assert(NHFarm.plant(state,{plot=slot,token=0,crop=crop},now))
end
assert(NHStore.commit(state))
state=assert(NHStore.load())
now=NHFarm.observe(state,180*60)
assert(NHFarm.sync(state,now) and not NHFarm.sync(state,now))
for slot,crop in ipairs(plots) do
    assert(state.farm.plots[slot].crop==crop and state.farm.plots[slot].readyAt>now)
    assert(state.resources[crop]==NHFarm.crops[crop].amount and not state.materials[crop])
end
assert(#state.warehouse==0)

local function finish(recipe)
    assert(NHStore.startOrder(state,recipe))
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    local order=state.order
    local request={run=run,orderId=order.id,progress=order.required}
    local changed,done=NHStore.advanceProduction(state,request)
    assert(changed and done)
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    assert(not NHStore.advanceProduction(state,request))
end
assert(not NHStore.startOrder(state,"field_medkit") and state.resources.herb==4)
finish("bandage")
assert(#state.warehouse==1 and state.warehouse[1].item.kind=="bandage" and state.warehouse[1].item.count==8)
local bandageId=state.warehouse[1].id
finish("field_medkit")
assert(#state.warehouse==2 and state.warehouse[1].id==bandageId and state.warehouse[1].item.count==7)
assert(state.warehouse[2].id~=bandageId and state.warehouse[2].item.kind=="medkit" and state.warehouse[2].item.remaining==3)
finish("bread")
finish("sugar_cube")
assert(#state.warehouse==4 and state.warehouse[3].item.kind=="bread" and state.warehouse[4].item.kind=="sugar_cube")
assert(state.resources.fiber==2 and state.resources.herb==2 and state.resources.grain==4 and state.resources.sugar==1)
print("Four parallel crops harvested once, then turned into actual warehouse supplies across reloads.")
