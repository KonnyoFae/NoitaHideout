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

local function inputAmounts(recipe)
    local inputs={}
    for _,input in ipairs(recipe.inputs) do
        assert(input.amount>0 and input.amount==math.floor(input.amount),recipe.id)
        inputs[input.name]=(inputs[input.name] or 0)+input.amount
    end
    return inputs
end

local function sameStock(actual,expected,id)
    for name,amount in pairs(expected) do assert(actual[name]==amount,id.." missing "..name) end
    for name in pairs(actual) do assert(expected[name],id.." unexpected "..name) end
end

local function completeBatch(recipe)
    assert(NHStore.canStartBatch(s,recipe) and NHStore.startOrder(s,recipe.id),recipe.id)
    sameStock(s.materials,{},recipe.id)
    local order=assert(s.order)
    assert(order.recipe==recipe.id and order.required==NHStore.productionFrames(recipe))
    sameStock(order.output.materials,recipe.materials,recipe.id)
    local changed,delivered=NHStore.advanceProduction(s,{run=run,orderId=order.id,progress=order.required-1})
    assert(changed and not delivered and not next(s.materials),recipe.id)
    persist()
    assert(s.order.progress==order.required-1 and s.order.recipe==recipe.id)
    local before=s.finished
    finish()
    assert(s.finished==before+1,recipe.id)
    sameStock(s.materials,recipe.materials,recipe.id)
end

local synthesis,decomposition={},{}
local ids={}
for _,recipe in ipairs(NHStore.recipes) do
    assert(not ids[recipe.id],"Duplicate recipe: "..recipe.id)
    ids[recipe.id]=true
    if recipe.category=="alchemy" then
        if recipe.reverseOf then
            assert(not decomposition[recipe.reverseOf],recipe.id)
            decomposition[recipe.reverseOf]=recipe
        else
            synthesis[recipe.id]=recipe
        end
    end
end
-- Fixed batches for the vanilla reactions offered by the workshop.
local knownBatches={
    flummoxium={{magic_liquid_worm_attractor=250,blood_worm=250},{material_confusion=500}},
    pheromone={{material_confusion=250,magic_liquid_berserk=250},{magic_liquid_charm=500}},
    hastium={{magic_liquid_faster_levitation=250,magic_liquid_movement_faster=250},{magic_liquid_faster_levitation_and_movement=500}},
    unstable_polymorphine={{material_confusion=250,blood=250,oil=250},{magic_liquid_unstable_polymorph=750}},
    levitatium={{material_confusion=250,copper=250},{magic_liquid_faster_levitation=500}},
    diminution={{vomit=250,bone=250},{magic_liquid_weakness=500}},
}
for id,batch in pairs(knownBatches) do
    local recipe=assert(synthesis[id],id)
    sameStock(inputAmounts(recipe),batch[1],id)
    sameStock(recipe.materials,batch[2],id)
end
local pairsTested=0
for id,recipe in pairs(synthesis) do
    local split=assert(decomposition[id],"No reverse for "..id)
    local original=inputAmounts(recipe)
    sameStock(inputAmounts(split),recipe.materials,split.id)
    sameStock(split.materials,original,id)

    -- One missing unit prevents payment. A filled stockroom must have space
    -- for all new types after subtracting the actual batch of ingredients.
    for _,direction in ipairs({recipe,split}) do
        local costs=inputAmounts(direction)
        local firstName,firstAmount=next(costs)
        s.materials=inputAmounts(direction)
        s.materials[firstName]=firstAmount-1
        assert(not NHStore.startOrder(s,direction.id) and not s.order,direction.id)
        costs[firstName]=firstAmount-1
        sameStock(s.materials,costs,direction.id)
        local occupied=0
        for name,amount in pairs(inputAmounts(direction)) do
            s.materials[name]=amount+1
            occupied=occupied+1
        end
        for i=occupied+1,NHStore.warehouseCapacity(s,"materials") do s.materials["filler_"..i]=1 end
        assert(not NHStore.canStartBatch(s,direction) and not NHStore.startOrder(s,direction.id),direction.id)
        assert(not s.order and s.materials[firstName]==firstAmount+1,direction.id)
    end

    s.materials=inputAmounts(recipe)
    completeBatch(recipe)
    completeBatch(split)
    sameStock(s.materials,original,id)
    assert(s.docks[1].item.materials[stable]==500)
    pairsTested=pairsTested+1
end
for id in pairs(decomposition) do assert(synthesis[id],"Orphan reverse for "..id) end
print(("Reverse alchemy: %d recipe pairs paid from stock, reserved capacity, reloaded and round-tripped exactly."):format(pairsTested))
