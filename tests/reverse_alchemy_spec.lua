local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key]==true end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local stable="magic_liquid_teleportation"
local unstable="magic_liquid_unstable_teleportation"
local reverse
for _,recipe in ipairs(NHStore.recipes) do
    if recipe.reverseOf=="stable" then reverse=recipe end
end
assert(reverse and reverse.category=="alchemy" and #reverse.inputs==1)
assert(reverse.inputs[1].name==stable and reverse.inputs[1].amount==500)
assert(reverse.materials[unstable]==250 and reverse.materials.slime==250)

local s=assert(NHStore.load())
local run=NHStore.newRun(s)
local function persist()
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
end
local function finish()
    local request={run=run,orderId=s.order.id,progress=s.order.required}
    assert(NHStore.advanceProduction(s,request))
    assert(not s.order)
    NHStore.advanceProduction(s,request)
end

local dock={id=s.nextItemId,slot=1,item={kind="potion",materials={[stable]=500},capacity=1000}}
s.nextItemId=s.nextItemId+1
s.docks[1]=dock
s.materials[stable]=499
assert(not NHStore.startOrder(s,reverse.id))
assert(s.materials[stable]==499 and dock.item.materials[stable]==500 and not s.order)

-- Both outputs need a type slot; completely spending an input frees one.
s.materials[stable]=501
for i=1,14 do s.materials["filler_"..i]=1 end
assert(not NHStore.canStartBatch(s,reverse) and not NHStore.startOrder(s,reverse.id))
assert(s.materials[stable]==501 and not s.order)
s.materials[stable]=500
assert(NHStore.canStartBatch(s,reverse) and NHStore.startOrder(s,reverse.id))
assert(s.materials[stable]==nil and not NHStore.startOrder(s,reverse.id))
assert(not NHPotion.transferMaterial(s,{slot=1,storedId=dock.id,unload=true}))
assert(s.docks[1].item.materials[stable]==500)
assert(NHStore.canStockMaterials(s,{[unstable]=1}) and not NHStore.canStockMaterials(s,{foreign=1}))
persist()
assert(s.order.output.materials[unstable]==250 and s.order.output.materials.slime==250)
finish()
assert(s.materials[unstable]==250 and s.materials.slime==250 and not s.materials[stable])
assert(s.finished==1)

-- Refine and split the same batch again. Stock in other types and intact
-- containers stays untouched, including after saving the paid order.
assert(NHStore.startOrder(s,"stable"))
finish()
assert(s.materials[stable]==500 and not s.materials[unstable] and not s.materials.slime)
assert(NHStore.startOrder(s,reverse.id))
persist()
finish()
assert(s.finished==3 and s.materials[unstable]==250 and s.materials.slime==250)
assert(s.docks[1].item.materials[stable]==500)
for i=1,14 do assert(s.materials["filler_"..i]==1) end
print("Reverse alchemy: exact payment, reserved type slots, reload, single delivery and lossless round trip passed.")
