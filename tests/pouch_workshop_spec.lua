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
assert(s.order.output.slot==1 and not NHStore.freeSlot(s,"warehouse",1,"pouch"))
assert(#s.warehouse==1 and s.warehouse[1].item.materials.water==1 and s.materials.slime==100)
assert(not NHStore.startOrder(s,"pouch") and not NHPouches.at(s,"warehouse",1))
persist()
assert(NHStore.reward(s,run) and not NHStore.reward(s,run))
persist()
local first=NHPouches.at(s,"warehouse",1)
assert(first.id~=starter and first.doses==0 and not next(first.cells))
local first_id=first.id
assert(NHStore.putPouchDose(first,2,4))
assert(s.pouches[starter].cells[1].count==2 and s.pouches[starter].doses==2)

run=NHStore.newRun(s)
assert(not NHStore.startOrder(s,"pouch") and s.materials.slime==100)
add_flask(2,{})
persist()
assert(NHStore.startOrder(s,"pouch") and s.order.output.slot==2)
reject_snapshot=true
assert(not NHStore.commit(s))
reject_snapshot=false
s=assert(NHStore.load())
assert(not s.order and s.materials.slime==100 and NHStore.emptyContainerCount(s)==1)
assert(NHStore.startOrder(s,"pouch"))
assert(NHStore.reward(s,run))
persist()
local second=NHPouches.at(s,"warehouse",2)
assert(second.id~=first_id and second.doses==0 and next(second.cells)==nil)
assert(s.pouches[first_id].cells[4].remaining==2 and s.materials.slime==50)
assert(NHStore.putPouchDose(second,1,1))
assert(NHStore.endRun(s,run))
persist()
assert(s.pouches[second.id].cells[1].remaining==1 and s.pouches[first_id].cells[4].remaining==2)
assert(NHStore.restock(s) and s.pouches[first_id] and s.pouches[second.id])
assert(#s.warehouse==1 and s.warehouse[1].item.materials.water==1)
print("Workshop: empty-container payment, reserved delivery, retries, multiple independent pouches and protected durability passed.")
