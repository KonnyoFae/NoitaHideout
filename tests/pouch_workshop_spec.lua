-- Exercise paid orders, the reserved equipment slot and independent pouch records
-- across profile commits. Other transfer tests exercise the live item entities.
local settings,flags={},{}
local reject_snapshot=false
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value)
    if not (reject_snapshot and key:match("^noita_hideout%.p%d+_[ab]$")) then settings[key]=value end
end
function HasFlagPersistent(key) return flags[key]==true end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local s=assert(NHStore.load())
local function persist()
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
end
local function add_flask(slot,materials)
    local id=s.nextItemId
    s.nextItemId=id+1
    table.insert(s.warehouse,{slot=slot,id=id,item={kind="potion",capacity=1000,materials=materials}})
end
local run=NHStore.newRun(s)
s.materials={water=250,oil=100,slime=150}
local starter=s.starterPouchId
add_flask(1,{water=1})
add_flask(2,{})
assert(not NHStore.startOrder(s,"pouch"))
assert(NHStore.buyUpgrade(s,{id="injector",level=0}))
persist()
assert(NHStore.startOrder(s,"pouch"))
assert(s.order.required==10*60)
assert(s.order.output.slot==1 and not NHStore.freeSlot(s,"warehouse",1,"pouch"))
assert(#s.warehouse==1 and s.warehouse[1].item.materials.water==1 and s.materials.slime==125)
assert(not NHStore.startOrder(s,"pouch") and not NHPouches.at(s,"warehouse",1))
persist()
local complete={run=run,orderId=s.order.id,progress=s.order.required}
assert(NHStore.advanceProduction(s,complete) and not NHStore.advanceProduction(s,complete))
persist()
local first=NHPouches.at(s,"warehouse",1)
assert(first.id~=starter and first.doses==0 and not next(first.cells))
local first_id=first.id
assert(NHStore.putPouchDose(first,2,4))
assert(s.pouches[starter].cells[1].count==2 and s.pouches[starter].doses==2)

run=NHStore.newRun(s)
assert(not NHStore.startOrder(s,"pouch") and s.materials.slime==125)
add_flask(2,{})
persist()
assert(NHStore.startOrder(s,"pouch") and s.order.output.slot==2)
reject_snapshot=true
assert(not NHStore.commit(s))
reject_snapshot=false
s=assert(NHStore.load())
assert(not s.order and s.materials.slime==125 and NHStore.emptyContainerCount(s)==1)
assert(NHStore.startOrder(s,"pouch"))
assert(NHStore.advanceProduction(s,{run=run,orderId=s.order.id,progress=s.order.required}))
persist()
local second=NHPouches.at(s,"warehouse",2)
assert(second.id~=first_id and second.doses==0 and next(second.cells)==nil)
assert(s.pouches[first_id].cells[4].remaining==2 and s.materials.slime==100)
assert(NHStore.putPouchDose(second,1,1))
assert(NHStore.endRun(s,run))
persist()
assert(s.pouches[second.id].cells[1].remaining==1 and s.pouches[first_id].cells[4].remaining==2)
assert(NHStore.restock(s) and s.pouches[first_id] and s.pouches[second.id])
assert(#s.warehouse==1 and s.warehouse[1].item.materials.water==1)
print("Workshop: empty-container payment, reserved delivery, retries, multiple independent pouches and protected durability passed.")

run=NHStore.newRun(s)
s.resources.fiber=4
assert(not NHStore.startOrder(s,"card_wallet"))
s.materials={soil=150,sand=200,water=200}
assert(NHStore.buyUpgrade(s,{id="farmland",level=0}))
assert(not NHStore.startOrder(s,"card_wallet") and s.resources.fiber==4)
add_flask(2,{})
assert(NHStore.startOrder(s,"card_wallet") and s.order.output.slot==3)
assert(s.order.required==8*60)
assert(not s.resources.fiber and NHStore.emptyContainerCount(s)==0 and s.warehouse[1].item.materials.water==1)
assert(NHStore.grantTestWallet(s))
assert(NHStore.slotIndex(s,"warehouse",4,"card_wallet"))
persist()
local done={run=run,orderId=s.order.id,progress=s.order.required}
assert(NHStore.advanceProduction(s,done) and not NHStore.advanceProduction(s,done))
persist()
local crafted=s.warehouse[NHStore.slotIndex(s,"warehouse",3,"card_wallet")]
local granted=s.warehouse[NHStore.slotIndex(s,"warehouse",4,"card_wallet")]
assert(crafted.id~=granted.id and crafted.item.cells~=granted.item.cells)
assert(not next(crafted.item.cells) and not next(granted.item.cells))
assert(NHStore.warehouseCapacity(s,"collection")==48 and NHStore.buyUpgrade(s,{id="warehouse_collection",level=0}))
assert(NHStore.warehouseCapacity(s,"collection")==72 and NHStore.warehouseCapacity(s,"equipment")==48)
print("Card wallets: craft and test grant have separate equipment slots and independent empty contents.")
