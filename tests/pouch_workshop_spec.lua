-- Craft with scrap while retaining independent container records and contents.
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
    s.warehouse[#s.warehouse+1]={slot=slot,id=id,item={kind="potion",capacity=1000,materials=materials}}
end
local run=NHStore.newRun(s)
s.materials={water=250,oil=100,slime=150}
local starter=s.starterPouchId
add_flask(1,{water=1})
add_flask(2,{})
s.resources.container_scrap=1
assert(not NHStore.craft(s,"pouch"))
assert(NHStore.buyUpgrade(s,{id="injector",level=0}))
s.resources.container_scrap=nil
assert(not NHStore.craft(s,"pouch") and NHStore.emptyContainerCount(s)==1)
s.resources.container_scrap=1
persist()
assert(NHStore.craft(s,"pouch") and not s.order)
assert(#s.warehouse==2 and s.warehouse[1].item.materials.water==1 and s.materials.slime==125)
assert(not s.resources.container_scrap and NHStore.emptyContainerCount(s)==1)
persist()
local first=NHPouches.at(s,"warehouse",1)
assert(first.id~=starter and first.doses==0 and not next(first.cells))
local first_id=first.id
assert(NHStore.putPouchDose(first,2,4))
assert(s.pouches[starter].cells[1].count==2 and s.pouches[starter].doses==2)
run=NHStore.newRun(s)
assert(not NHStore.craft(s,"pouch") and s.materials.slime==125)
s.resources.container_scrap=1
persist()
assert(NHStore.craft(s,"pouch"))
reject_snapshot=true
assert(not NHStore.commit(s))
reject_snapshot=false
s=assert(NHStore.load())
assert(not s.order and s.materials.slime==125 and s.resources.container_scrap==1 and not NHPouches.at(s,"warehouse",2))
assert(NHStore.craft(s,"pouch"))
persist()
local second=NHPouches.at(s,"warehouse",2)
assert(second.id~=first_id and second.doses==0 and next(second.cells)==nil)
assert(s.pouches[first_id].cells[4].remaining==2 and s.materials.slime==100)
assert(NHStore.putPouchDose(second,1,1))
assert(NHStore.endRun(s,run))
persist()
assert(s.pouches[second.id].cells[1].remaining==1 and s.pouches[first_id].cells[4].remaining==2)
assert(NHStore.restock(s) and s.pouches[first_id] and s.pouches[second.id])
assert(#s.warehouse==2 and s.warehouse[1].item.materials.water==1 and NHStore.emptyContainerCount(s)==1)
run=NHStore.newRun(s)
s.resources.fiber=4
assert(not NHStore.craft(s,"card_wallet"))
s.materials={soil=150,sand=200,water=200}
assert(NHStore.buyUpgrade(s,{id="farmland",level=0}))
assert(not NHStore.craft(s,"card_wallet") and s.resources.fiber==4)
s.resources.container_scrap=1
assert(NHStore.craft(s,"card_wallet") and not s.order)
assert(not s.resources.fiber and not s.resources.container_scrap and NHStore.emptyContainerCount(s)==1)
assert(NHStore.grantTestWallet(s))
persist()
local crafted=s.warehouse[NHStore.slotIndex(s,"warehouse",3,"card_wallet")]
local granted=s.warehouse[NHStore.slotIndex(s,"warehouse",4,"card_wallet")]
assert(crafted.id~=granted.id and crafted.item.cells~=granted.item.cells)
assert(not next(crafted.item.cells) and not next(granted.item.cells))
assert(NHStore.warehouseCapacity(s,"collection")==48 and NHStore.buyUpgrade(s,{id="warehouse_collection",level=0}))
assert(NHStore.warehouseCapacity(s,"collection")==72 and NHStore.warehouseCapacity(s,"equipment")==48)
for _,entry in ipairs({{"pouch_2","pouch",2,8,50},{"pouch_3","pouch",3,12,100},
    {"card_wallet_2","card_wallet",2,8,8},{"card_wallet_3","card_wallet",3,12,12}}) do
    local id,kind,tier,capacity,cost=unpack(entry)
    if kind=="pouch" then s.materials.slime=cost else s.resources.fiber=cost end
    s.resources.container_scrap=tier-1
    assert(not NHStore.craft(s,id) and s.resources.container_scrap==tier-1)
    s.resources.container_scrap=tier
    local slot=assert(NHStore.freeSlot(s,"warehouse",nil,kind))
    assert(NHStore.craft(s,id) and not s.order)
    assert(not s.materials.slime and not s.resources.fiber and not s.resources.container_scrap and NHStore.emptyContainerCount(s)==1)
    persist()
    local item=kind=="pouch" and NHPouches.at(s,"warehouse",slot) or s.warehouse[NHStore.slotIndex(s,"warehouse",slot,kind)].item
    assert(item.tier==tier and not next(item.cells) and NHEquipment.get(kind,item.tier).capacity==capacity)
    if kind=="pouch" then
        assert(NHStore.putPouchDose(item,1,capacity) and not NHStore.putPouchDose(item,1,capacity+1))
    else
        item.cells[capacity]=NHCompanions.withCount({species="dryad",remaining=40},1)
        assert(NHCardWallets.valid(item))
        item.cells[capacity+1]=item.cells[capacity]
        assert(not NHCardWallets.valid(item))
        item.cells[capacity+1]=nil
    end
    persist()
end
print("Container recipes: exact tier scrap costs, intact flasks, instant delivery, failed-save rollback and independent contents passed.")
