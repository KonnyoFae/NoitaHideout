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
assert(quote("support").planned and not quote("support").canBuy)
assert(not buy("perk_pack") and s.materials.slime==850)
s.resources.arcane_scrap=1
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
s.order.progress,s.order.required=0,1
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
print("Progression costs, stale confirmations, independent capacities, order reservations and legacy stock passed.")
