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
local powderSeparation
local ids={}
local secondsPerBatch={philosopher_stone=1,rubedo_midas=1,rubedo_immortality=1,supply_logistics=1,strike_logistics=1,
    reinforcement_logistics=1,intel_logistics=1,
    stable=8, diminution=8, mana=8, flummoxium=10,
    pheromone=15, levitatium=15, levitatium_metals=15,
    hastium=30, unstable_polymorphine=30, guiding_powder=30,
    chaotic_polymorphine=45, purifying_powder=45, purifying_powder_silver=60,
    ambrosia=90, separate_gunpowder=90, void_diamond=120, void_fungus=120, midas=180,
}
for _,recipe in ipairs(NHStore.recipes) do
    assert(not ids[recipe.id],"Duplicate recipe: "..recipe.id)
    ids[recipe.id]=recipe
    if recipe.category=="alchemy" then
        local seconds=assert(secondsPerBatch[recipe.reverseOf or recipe.id],recipe.id)
        assert(NHStore.productionFrames(recipe)==seconds*60,recipe.id)
        local outputs=recipe.materials or recipe.resourceYield
        assert(not outputs.magic_liquid_hp_regeneration_unstable,recipe.id)
        assert(not outputs.gold and not outputs.midas_precursor,recipe.id)
        for _,input in ipairs(recipe.inputs) do assert(input.name~="magic_liquid_hp_regeneration_unstable",recipe.id) end
        if recipe.reverseOf then
            assert(not decomposition[recipe.reverseOf],recipe.id)
            decomposition[recipe.reverseOf]=recipe
        elseif recipe.reversible then
            synthesis[recipe.id]=recipe
        elseif recipe.id=="separate_gunpowder" then
            powderSeparation=recipe
        end
        if recipe.alchemyMode=="synthesis" and (recipe.materials.gunpowder or recipe.materials.gunpowder_unstable) then
            local costs=inputAmounts(recipe)
            assert(not (costs.magic_liquid_hp_regeneration and costs.purifying_powder),recipe.id)
        end
    end
end
-- Fixed batches for the vanilla reactions offered by the workshop.
local knownBatches={
    flummoxium={{magic_liquid_worm_attractor=100,blood_worm=100},{material_confusion=200}},
    pheromone={{material_confusion=100,magic_liquid_berserk=100},{magic_liquid_charm=200}},
    hastium={{magic_liquid_faster_levitation=100,magic_liquid_movement_faster=100},{magic_liquid_faster_levitation_and_movement=200}},
    unstable_polymorphine={{material_confusion=100,blood=100,oil=100},{magic_liquid_unstable_polymorph=300}},
    levitatium={{material_confusion=100,copper=100},{magic_liquid_faster_levitation=200}},
    diminution={{vomit=100,bone=100},{magic_liquid_weakness=200}},
    ambrosia={{honey=50,diamond=50},{magic_liquid_protection_all=50,poison=50}},
    purifying_powder={{brass=50,diamond=50},{purifying_powder=100}},
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

local split=assert(powderSeparation,"Missing one-way powder separation")
assert(split.alchemyMode=="decomposition" and not split.reversible and not split.reverseOf)
assert(not ids["reverse_"..split.id] and #split.inputs==1 and split.inputs[1].amount==200)
local yield={magic_liquid_hp_regeneration=100,purifying_powder=100}
sameStock(split.materials,yield,split.id)

for _,name in ipairs({"gunpowder","gunpowder_unstable"}) do
    s.materials={[name]=200}
    completeBatch(split)
end

-- Either material ID on a recipe uses the same pool. A catalyst still has
-- to exist as its own material and cannot also pay for an ingredient.
local powderBatch={
    inputs={{name="gunpowder_unstable",amount=100},{name="gunpowder",amount=100}},
    catalysts={{name="gunpowder_unstable",amount=1}},materials={gunpowder=50},
}
s.materials={gunpowder=201}
assert(NHStore.ingredientStock(s,powderBatch.inputs[1])==201)
local ready,reason=NHStore.canStartBatch(s,powderBatch)
assert(not ready and reason=="Missing catalyst.")
s.materials={gunpowder=120,gunpowder_unstable=80}
assert(not NHStore.canStartBatch(s,powderBatch))
s.materials.gunpowder_unstable=81
local paid,_,payment,delivery,held=NHStore.canStartBatch(s,powderBatch)
assert(paid)
sameStock(payment,{gunpowder=120,gunpowder_unstable=81},"powder payment")
sameStock(held,{gunpowder_unstable=1},"powder catalyst")
sameStock(delivery,{gunpowder=50,gunpowder_unstable=1},"powder delivery")

-- Visually similar explosives are not substitutes for the final missing unit.
local short={gunpowder=100,gunpowder_unstable=99,gunpowder_explosive=500,gunpowder_tnt=500,gunpowder_unstable_big=500}
s.materials={}
for name,amount in pairs(short) do s.materials[name]=amount end
assert(NHStore.ingredientStock(s,split.inputs[1])==199)
assert(not NHStore.canStartBatch(s,split) and not NHStore.startOrder(s,split.id))
sameStock(s.materials,short,split.id)

s.materials={gunpowder_unstable=85,gunpowder=189,gunpowder_tnt=32}
assert(NHStore.ingredientStock(s,split.inputs[1])==274)
assert(NHStore.startOrder(s,split.id))
sameStock(s.materials,{gunpowder=74,gunpowder_tnt=32},split.id)
persist()
sameStock(s.order.output.materials,yield,split.id)
local before=s.finished
finish()
sameStock(s.materials,{gunpowder=74,gunpowder_tnt=32,magic_liquid_hp_regeneration=100,purifying_powder=100},split.id)
assert(s.finished==before+1)

-- In a full warehouse, keeping even one grain of the ordinary powder leaves
-- only one slot free. Spending the last grain frees the second product slot.
local fillers=NHStore.warehouseCapacity(s,"materials")-2
s.materials={gunpowder=101,gunpowder_unstable=100}
for i=1,fillers do s.materials["filler_"..i]=1 end
local ok,reason=NHStore.startOrder(s,split.id)
assert(not ok and reason=="Material storage is full." and not s.order)
assert(s.materials.gunpowder==101 and s.materials.gunpowder_unstable==100)
s.materials.gunpowder=100
assert(NHStore.canStartBatch(s,split) and NHStore.startOrder(s,split.id))
assert(not s.materials.gunpowder and not s.materials.gunpowder_unstable)
assert(not NHStore.canStockMaterials(s,{foreign=1}) and NHStore.canStockMaterials(s,yield))
persist()
finish()
assert(s.materials.magic_liquid_hp_regeneration==100 and s.materials.purifying_powder==100)
for i=1,fillers do assert(s.materials["filler_"..i]==1) end

-- An existing Healthium stack needs no new slot. Burn through the ordinary
-- powder instead when the preferred powder stack is too large to empty.
s.materials={gunpowder=200,gunpowder_unstable=300,magic_liquid_hp_regeneration=17}
for i=1,fillers-1 do s.materials["filler_"..i]=1 end
assert(NHStore.canStartBatch(s,split) and NHStore.startOrder(s,split.id))
assert(not s.materials.gunpowder and s.materials.gunpowder_unstable==300)
assert(not NHStore.canStockMaterials(s,{foreign=1}))
persist()
finish()
assert(s.materials.magic_liquid_hp_regeneration==117 and s.materials.purifying_powder==100)
assert(not s.materials.gunpowder and s.materials.gunpowder_unstable==300)
for i=1,fillers-1 do assert(s.materials["filler_"..i]==1) end
print("One-way powder separation: both powder types, mixed payment, excluded explosives, capacity and single delivery passed.")

for _,name in ipairs({"magic_liquid_protection_all","poison"}) do
    s.materials={[name]=200}
    assert(not NHStore.startOrder(s,"reverse_ambrosia") and not s.order)
    sameStock(s.materials,{[name]=200},name)
end

local singleRoutes={
    purifying_powder_silver={{silver=50,diamond=50,blood_worm=50},{purifying_powder=50}},
    guiding_powder={{material_confusion=100,magic_liquid_unstable_teleportation=100},{orb_powder=100}},
    void_diamond={{diamond=50,magic_liquid_random_polymorph=50,radioactive_liquid=50},{void_liquid=150}},
    void_fungus={{radioactive_liquid=50,blood_worm=50,fungi=50},{void_liquid=100}},
}
for id,batch in pairs(singleRoutes) do
    local r=assert(ids[id])
    sameStock(inputAmounts(r),batch[1],id)
    sameStock(r.materials,batch[2],id)
    assert(r.alchemyMode=="synthesis" and not r.reversible and not ids["reverse_"..id])
    s.materials=inputAmounts(r)
    completeBatch(r)
end

local metals=assert(ids.levitatium_metals)
assert(not metals.reversible and not ids.reverse_levitatium_metals)
local alternatives={"metal_sand","steel_sand","brass","silver","gold_radioactive","gold","diamond"}
assert(#metals.inputs[2].alternatives==#alternatives)
for i,name in ipairs(alternatives) do
    assert(metals.inputs[2].alternatives[i]==name)
    s.materials={material_confusion=100,[name]=100}
    completeBatch(metals)
end
s.materials={material_confusion=100,copper=100}
assert(not NHStore.startOrder(s,metals.id) and NHStore.canStartBatch(s,synthesis.levitatium))
s.materials={material_confusion=100,brass=60,silver=60}
assert(NHStore.startOrder(s,metals.id) and not s.materials.brass and s.materials.silver==20)
finish()
assert(NHStore.startOrder(s,decomposition.levitatium.id))
finish()
sameStock(s.materials,{copper=100,material_confusion=100,silver=20},metals.id)

s.materials={material_confusion=101,metal_sand=120,brass=40,silver=70}
for i=1,NHStore.warehouseCapacity(s,"materials")-4 do s.materials["filler_"..i]=1 end
assert(NHStore.startOrder(s,metals.id) and s.materials.metal_sand==120 and not s.materials.brass)
assert(s.materials.silver==10 and s.materials.material_confusion==1)
finish()
assert(s.materials.magic_liquid_faster_levitation==200)

local mana="magic_liquid_mana_regeneration"
local function testCatalyst(id,feed,sample,product)
    local r=assert(ids[id])
    assert(not r.reversible and not ids["reverse_"..id] and r.alchemyMode=="synthesis")
    sameStock(inputAmounts(r),{[feed]=100},id)
    sameStock(r.materials,{[product]=100},id)
    assert(#r.catalysts==1 and r.catalysts[1].name==sample and r.catalysts[1].amount==1)
    s.materials={[feed]=100}
    local ok,reason=NHStore.startOrder(s,id)
    assert(not ok and reason=="Missing catalyst." and not s.order)
    s.materials={[sample]=1,[feed]=99}
    assert(not NHStore.startOrder(s,id) and s.materials[sample]==1 and s.materials[feed]==99)
    s.materials[feed]=100
    assert(NHStore.startOrder(s,id) and not next(s.materials))
    persist()
    sameStock(s.order.catalysts,{[sample]=1},id)
    local expected={[product]=100}
    expected[sample]=(expected[sample] or 0)+1
    sameStock(s.order.output.materials,expected,id)
    if id=="midas" then
        run=NHStore.newRun(s)
        persist()
        sameStock(s.order.catalysts,{midas=1},id)
    end
    finish()
    sameStock(s.materials,expected,id)
end
testCatalyst("mana","water",mana,mana)
testCatalyst("chaotic_polymorphine","magic_liquid_polymorph","radioactive_liquid","magic_liquid_random_polymorph")
testCatalyst("midas","midas_precursor","midas","midas")

-- Returning a different catalyst occupies a second type. The held sample and
-- its product are reserved against flask deposits until the order finishes.
s.materials={magic_liquid_polymorph=101,radioactive_liquid=1}
for i=1,fillers do s.materials["filler_"..i]=1 end
assert(not NHStore.startOrder(s,"chaotic_polymorphine") and s.materials.radioactive_liquid==1)
s.materials.magic_liquid_polymorph=100
assert(NHStore.startOrder(s,"chaotic_polymorphine") and not s.materials.radioactive_liquid)
assert(not NHStore.canStockMaterials(s,{foreign=1}) and NHStore.canStockMaterials(s,{radioactive_liquid=1}))
finish()
assert(s.materials.radioactive_liquid==1 and s.materials.magic_liquid_random_polymorph==100)

-- The reservation includes the original sample when catalyst and product match.
local limit=NHStore.maxMaterialAmount
s.materials={water=100,[mana]=limit-99}
assert(not NHStore.startOrder(s,"mana") and s.materials.water==100)
s.materials[mana]=limit-100
assert(NHStore.startOrder(s,"mana") and s.order.output.materials[mana]==101)
local flask=s.docks[1]
flask.item.materials={[mana]=1}
assert(not NHPotion.transferMaterial(s,{slot=1,storedId=flask.id,unload=true}))
assert(flask.item.materials[mana]==1 and s.materials[mana]==limit-101)
persist()
finish()
assert(s.materials[mana]==limit)
print("Catalytic batches and one-way alchemy: samples reserved and returned once, excess deliveries rejected, side products handled.")

-- A batch paid before the smaller recipe went live keeps both promised
-- products and its original remaining time when reloaded.
s.materials={}
s.order={id=s.finished+1,recipe="ambrosia",progress=7200-2,required=7200,
    output={materials={magic_liquid_protection_all=250,poison=250}}}
persist()
assert(s.order.required==7200 and s.order.progress==7198)
local changed,delivered=NHStore.advanceProduction(s,{run=run,orderId=s.order.id,progress=7199})
assert(changed and not delivered and not next(s.materials))
finish()
sameStock(s.materials,{magic_liquid_protection_all=250,poison=250},"pre-rebalance ambrosia")
