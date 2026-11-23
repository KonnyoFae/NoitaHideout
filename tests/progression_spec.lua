local settings,flags={},{}
local fail=false
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,v)
    if not (fail and key:match("_revision$")) then settings[key]=v end
end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local s=assert(NHStore.load())
local function buy(id,lv) return NHStore.buyUpgrade(s,{id=id,level=lv or 0}) end
local function quote(id)
    local menu=NHStore.progressMenu(s,"en")
    for _,group in pairs(menu) do
        for _,entry in ipairs(group) do if entry.id==id then return entry end end
    end
    error("missing "..id)
end
s.materials={sand=2000,slime=149,water=3000,oil=500}
assert(not quote("safe").canBuy and not buy("safe"))
assert(s.materials.sand==2000 and s.materials.slime==149 and s.safeCapacity==2)
s.materials.slime=1000
assert(NHStore.commit(s))
local stale=assert(NHStore.load())
assert(quote("safe").canBuy and buy("safe") and not buy("safe"))
assert(s.safeCapacity==3 and s.materials.sand==1750 and s.materials.slime==850)
assert(quote("safe").costs[1].amount==500)
fail=true
assert(not NHStore.commit(s))
s=assert(NHStore.load())
assert(s.safeCapacity==2 and s.materials.sand==2000 and NHStore.level(s,"safe")==0)
fail=false
assert(buy("safe") and NHStore.commit(s))
assert(NHStore.buyUpgrade(stale,{id="safe",level=0}) and not NHStore.commit(stale))
s=assert(NHStore.load())
assert(s.safeCapacity==3 and s.materials.sand==1750)

assert(not NHStore.freeSlot(s,"warehouse",49,"wand"))
assert(buy("warehouse_wand"))
assert(NHStore.freeSlot(s,"warehouse",72,"wand")==72 and not NHStore.freeSlot(s,"warehouse",73,"wand"))
assert(not NHStore.freeSlot(s,"warehouse",49,"spell"))
assert(not NHStore.freeSlot(s,"warehouse",49,"pouch") and buy("warehouse_equipment"))
assert(NHStore.freeSlot(s,"warehouse",72,"pouch")==72 and not NHStore.freeSlot(s,"warehouse",49,"dose"))
assert(NHStore.level(s,"warehouse_containers")==0 and not buy("support"))
assert(not quote("support").planned and not quote("support").canBuy)
assert(not buy("perk_pack") and s.materials.slime==850)
s.resources.arcane_scrap=1
assert(not buy("perk_pack") and NHRelics.capacity(s)==1)
NHPerks={enabled=true} -- exercise the dormant purchase path
assert(buy("perk_pack") and s.resources.arcane_scrap==nil and quote("perk_pack").maxed)
assert(buy("perk_slots") and NHStore.level(s,"perk_slots")==1)
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(NHStore.level(s,"warehouse_wand")==1 and NHStore.level(s,"perk_pack")==1)

-- Unloading mixed contents is all-or-nothing. Existing material types can grow at the limit.
s.materials={sand=250,slime=100}
for i=1,14 do s.materials["test"..i]=2 end
s.docks={{id=11,slot=1,item={kind="potion",materials={water=12,sand=4}}}}
local req={storedId=11,slot=1,unload=true}
assert(not NHPotion.transferMaterial(s,req))
assert(s.materials.water==nil and s.materials.sand==250 and s.docks[1].item.materials.water==12)
assert(NHStore.canStockMaterials(s,{sand=20}) and not NHStore.canStockMaterials(s,{water=1}))
assert(NHStore.canStockMaterials(s,{water=1},{slime=100}))
assert(buy("warehouse_materials") and NHStore.warehouseCapacity(s,"materials")==24)
assert(NHPotion.transferMaterial(s,req) and s.materials.water==12 and s.materials.sand==4)

-- Reservations participate in capacity tests before their order completes.
s.order={output={item={kind="dose"},slot=5}}
assert(not NHStore.freeSlot(s,"warehouse",5,"medkit") and NHStore.freeSlot(s,"warehouse",5,"pouch")==5)
s.pouches[s.starterPouchId].location,s.pouches[s.starterPouchId].slot="warehouse",5
s.order.id,s.order.progress,s.order.required=s.finished+1,0,NHStore.productionFrames()
assert(NHStore.commit(s) and not NHStore.freeSlot(s,"warehouse",5,"pouch"))
s.order={output={materials={product=20}}}
for i=1,7 do s.materials["extra"..i]=1 end
assert(not NHStore.canStockMaterials(s,{foreign=1}) and NHStore.canStockMaterials(s,{product=1}))

-- Profiles created with the old unlimited warehouse keep their occupied high slots.
local legacy={warehouse={{id=1,item={kind="wand"},slot=111}},pouches={[2]={id=2,location="warehouse",slot=51}},materials={}}
for i=1,21 do legacy.materials["m"..i]=1 end
local progression=dofile("mods/noita_hideout/files/progression.lua")
progression.adopt(legacy)
assert(NHStore.warehouseCapacity(legacy,"wand")==111 and NHStore.warehouseCapacity(legacy,"equipment")==51)
assert(NHStore.warehouseCapacity(legacy,"materials")==21 and NHStore.warehouseCapacity(legacy,"spell")==48)
assert(not NHStore.freeSlot(legacy,"warehouse",112,"wand"))
-- An existing 0.10.0 supply-grid pouch above the equipment limit keeps its contents.
local current={levels={warehouse_supplies=1},storageBase={},warehouse={{id=9,item={kind="dose"},slot=1}},
    pouches={[10]={id=10,location="warehouse",slot=60,doses=1,cells={{remaining=2,count=1}}}}}
progression.adopt(current)
assert(current.pouches[10].slot==1 and current.pouches[10].cells[1].remaining==2 and current.warehouse[1].slot==1)
assert(not NHStore.freeSlot(current,"warehouse",1,"pouch") and not NHStore.freeSlot(current,"warehouse",1,"dose"))

-- Upgrades quote and charge the target level. Raising an occupied facility's
-- capacity keeps its residents; only the initial gel pool includes an adult.
local function testLivestockCapacity()
    settings,flags={},{}
    s=assert(NHStore.load())
    NHStore.newRun(s)
    s.resources={fiber=12*6,sugar=8*6}
    s.materials={sand=(200+400)*6,water=(150+150)*6,slime=(75+250)*6,oil=150*6,gunpowder=100*6,soil=100*6}
    for _,facility in ipairs({"livestock","beehive","dragon_nest","gel_pool"}) do
        for level=0,2 do
            local offer=quote(facility)
            assert(offer.level==level and offer.canBuy and not offer.maxed)
            assert(offer.current:find(tostring(2*level),1,true) and offer.next:find(tostring(2*(level+1)),1,true))
            assert(offer.costs[1].amount==({livestock=200,beehive=12,dragon_nest=400,gel_pool=250})[facility]*(level+1))
            assert(buy(facility,level) and not buy(facility,level) and NHStore.commit(s))
            s=assert(NHStore.load())
            if facility=="gel_pool" then
                local pens=NHLivestock.view(s,"en",s.farm.time)
                local gel=pens[#pens]
                assert(gel.species=="gel_pool" and gel.count==1 and gel.adults==1 and gel.juveniles==0 and gel.capacity==2*(level+1))
            end
        end
        local full=quote(facility)
        assert(full.maxed and not full.canBuy and #full.costs==0 and not buy(facility,3))
    end
    assert(not next(s.materials) and not next(s.resources))
end
testLivestockCapacity()

settings,flags={},{}
s=assert(NHStore.load())
s.materials={oil=100,gunpowder_unstable=149,gunpowder_tnt=500}
local station=quote("grenade")
local powder=station.costs[1]
assert(powder.key=="gunpowder" and powder.name=="Gunpowder (total)" and powder.available==149)
assert(#powder.alternatives==2 and powder.alternatives[1]=="gunpowder_unstable" and powder.alternatives[2]=="gunpowder")
assert(not station.canBuy and not buy("grenade") and s.materials.oil==100 and s.materials.gunpowder_unstable==149)
s.materials.gunpowder_unstable=150
assert(quote("grenade").canBuy and buy("grenade"))
assert(not s.materials.gunpowder_unstable and not s.materials.oil and s.materials.gunpowder_tnt==500)

s.materials={sand=1200,oil=149,gunpowder=210,gunpowder_unstable=90,gunpowder_explosive=500}
assert(not quote("dragon_nest").canBuy and not buy("dragon_nest"))
assert(s.materials.sand==1200 and s.materials.gunpowder==210 and s.materials.gunpowder_unstable==90)
s.materials.oil=450
local nest=quote("dragon_nest")
assert(nest.canBuy and nest.costs[2].amount==100 and nest.costs[2].available==300)
assert(buy("dragon_nest") and NHStore.commit(s))
s=assert(NHStore.load())
assert(not s.materials.gunpowder_unstable and s.materials.gunpowder==200 and s.materials.gunpowder_explosive==500)
nest=quote("dragon_nest")
assert(nest.canBuy and nest.costs[2].amount==200 and nest.costs[2].available==200)
assert(buy("dragon_nest",1) and not s.materials.gunpowder and s.materials.gunpowder_explosive==500)
print("Progression costs, stale confirmations, independent capacities, order reservations and legacy stock passed.")

-- Existing six-slot cases can continue through six more paid ranks to 12 slots.
do
    settings,flags={},{}
    fail=false
    s=assert(NHStore.load())
    NHStore.newRun(s)
    s.materials={sand=13750,slime=8250}
    for rank=0,3 do assert(buy("safe",rank)) end
    assert(s.safeCapacity==6 and NHStore.level(s,"safe")==4)
    s.safe[#s.safe+1]={id=s.nextItemId,slot=6,item={kind="medkit",remaining=8,count=1}}
    s.nextItemId=s.nextItemId+1
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
    assert(not quote("safe").maxed and not quote("safe").canBuy)
    assert(not buy("safe",4) and s.safeCapacity==6 and s.materials.sand==11250)
    s.resources.container_scrap=21
    assert(NHStore.commit(s))
    for rank=4,9 do
        local offer=quote("safe")
        assert(offer.next==(rank+3).." slots" and offer.costs[3].key=="container_scrap" and offer.costs[3].amount==rank-3)
        assert(buy("safe",rank) and not buy("safe",rank) and NHStore.commit(s))
        s=assert(NHStore.load())
        assert(s.safeCapacity==rank+3 and s.safe[1].slot==6 and s.safe[1].item.remaining==8)
    end
    assert(s.safeCapacity==12 and quote("safe").maxed and not quote("safe").canBuy and not buy("safe",10))
    assert(not next(s.materials) and not s.resources.container_scrap)
    local used=NHStore.freeSlot(s,"safe",12,"medkit")
    assert(used==12 and not NHStore.freeSlot(s,"safe",13,"medkit"))
    -- Preserve unusually enlarged legacy cases without offering a 13th slot.
    s.levels.safe=0
    assert(quote("safe").maxed and not buy("safe",0))
end
print("Secure case: six-slot save resumes to 12, exact 1-6 scrap costs, preserved contents and hard purchase cap passed.")
