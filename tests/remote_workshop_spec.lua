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
assert(recipe.resources.arcane_scrap==1 and recipe.durationFrames==30*60)

s.resources.arcane_scrap=1
s.bankGold=99
assert(not NHStore.startOrder(s,id))
assert(s.bankGold==99 and s.resources.arcane_scrap==1 and not s.order)
s.bankGold=105
s.resources.arcane_scrap=0
assert(not NHStore.startOrder(s,id))
assert(s.bankGold==105 and s.resources.arcane_scrap==0 and not s.order)

s.resources.arcane_scrap=3
for slot=1,NHStore.warehouseCapacity(s,"equipment") do
    s.warehouse[slot]={id=s.nextItemId,slot=slot,item=NHCardWallets.empty()}
    s.nextItemId=s.nextItemId+1
end
assert(not NHStore.startOrder(s,id))
assert(s.bankGold==105 and s.resources.arcane_scrap==3 and not s.order)
table.remove(s.warehouse,3)
assert(NHStore.commit(s))
assert(NHStore.startOrder(s,id))
reject_snapshot=true
assert(not NHStore.commit(s))
reject_snapshot=false
s=assert(NHStore.load())
assert(s.bankGold==105 and s.resources.arcane_scrap==3 and not s.order)

assert(NHStore.startOrder(s,id))
assert(s.bankGold==5 and s.resources.arcane_scrap==2 and s.bankWalletNet==0)
assert(s.order.output.slot==3 and not NHStore.freeSlot(s,"warehouse",3,"card_wallet"))
assert(not NHStore.startOrder(s,id) and s.bankGold==5 and s.resources.arcane_scrap==2)
assert(NHStore.commit(s))
s=assert(NHStore.load())
local complete={run=run,orderId=s.order.id,progress=s.order.required}
assert(NHStore.advanceProduction(s,complete))
assert(not NHStore.advanceProduction(s,complete))
assert(NHStore.commit(s))
s=assert(NHStore.load())
local item=s.warehouse[NHStore.slotIndex(s,"warehouse",3,id)].item
assert(item.kind==id and item.remaining==20 and s.bankGold==5 and s.resources.arcane_scrap==2)
print("Remote terminal workshop: costs, rejected payment, reserved equipment slot and one fully charged delivery passed.")

for tier,kind in ipairs({"data_link_2","data_link_3"}) do
    local stock=assert(NHStore.load())
    stock.warehouse={}
    stock.resources={arcane_scrap=5,container_scrap=tier==1 and 3 or 2}
    stock.materials={}
    stock.bankGold=tier==1 and 499 or 0
    assert(not NHStore.craft(stock,kind) and stock.resources.arcane_scrap==5)
    if tier==1 then stock.bankGold=500 else stock.resources.nh_philosopher_stone=1 end
    assert(NHStore.craft(stock,kind))
    local row=stock.warehouse[1]
    assert(row.item.kind==kind and row.item.remaining==(tier==1 and 40 or 80))
    assert(stock.bankGold==0 and not next(stock.materials) and not next(stock.resources))
    assert(NHShields.move(stock,{kind=kind,source="warehouse",destination="gear",from=row.slot,entity=row.id}))
    assert(NHStore.commit(stock) and NHStore.load().gearLink.item.remaining==row.item.remaining)
end
