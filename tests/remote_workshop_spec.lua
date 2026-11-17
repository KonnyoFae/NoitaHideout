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
local run=NHStore.newRun(s)
local id="remote_terminal"
local recipe
for _,entry in ipairs(NHStore.recipes) do if entry.id==id then recipe=entry end end
assert(recipe and recipe.category=="equipment" and NHStore.category(id)=="equipment")
assert(recipe.item.remaining==20 and recipe.item.icon and recipe.goldCost==100)
assert(recipe.resources.essence_displacement==10 and recipe.durationFrames==30*60)

s.resources.essence_displacement=10
s.bankGold=99
assert(not NHStore.startOrder(s,id))
assert(s.bankGold==99 and s.resources.essence_displacement==10 and not s.order)
s.bankGold=105
s.resources.essence_displacement=9
assert(not NHStore.startOrder(s,id))
assert(s.bankGold==105 and s.resources.essence_displacement==9 and not s.order)

s.resources.essence_displacement=12
for slot=1,NHStore.warehouseCapacity(s,"equipment") do
    s.warehouse[slot]={id=s.nextItemId,slot=slot,item=NHCardWallets.empty()}
    s.nextItemId=s.nextItemId+1
end
assert(not NHStore.startOrder(s,id))
assert(s.bankGold==105 and s.resources.essence_displacement==12 and not s.order)
table.remove(s.warehouse,3)
assert(NHStore.commit(s))
assert(NHStore.startOrder(s,id))
reject_snapshot=true
assert(not NHStore.commit(s))
reject_snapshot=false
s=assert(NHStore.load())
assert(s.bankGold==105 and s.resources.essence_displacement==12 and not s.order)

assert(NHStore.startOrder(s,id))
assert(s.bankGold==5 and s.resources.essence_displacement==2 and s.bankWalletNet==0)
assert(s.order.output.slot==3 and not NHStore.freeSlot(s,"warehouse",3,"card_wallet"))
assert(not NHStore.startOrder(s,id) and s.bankGold==5 and s.resources.essence_displacement==2)
assert(NHStore.commit(s))
s=assert(NHStore.load())
local complete={run=run,orderId=s.order.id,progress=s.order.required}
assert(NHStore.advanceProduction(s,complete))
assert(not NHStore.advanceProduction(s,complete))
assert(NHStore.commit(s))
s=assert(NHStore.load())
local item=s.warehouse[NHStore.slotIndex(s,"warehouse",3,id)].item
assert(item.kind==id and item.remaining==20 and s.bankGold==5 and s.resources.essence_displacement==2)
print("Remote terminal workshop: costs, rejected payment, reserved equipment slot and one fully charged delivery passed.")
