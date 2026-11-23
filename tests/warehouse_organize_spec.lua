dofile("mods/noita_hideout/files/store.lua")

local charger={id=1,slot=2,item={kind=NHShields.charger,count=5}}
local wallet={id=2,slot=7,item={kind="card_wallet",tier=1,cells={}}}
local first={id=3,slot=5,item={kind="spell",card={id="BOMB",stack=2}}}
local second={id=4,slot=8,item={kind="spell",card={id="BOMB"}}}
local other={id=5,slot=4,item={kind="spell",card={id="LIGHT"}}}
local pouch={location="warehouse",slot=9,tier=1,cells={{subtype="frost"}}}
local safe={location="safe",slot=4}
local state={warehouse={wallet,second,first,other,charger},pouches={[6]=pouch,[7]=safe},
    order={output={item={kind=NHShields.charger},slot=2}}}
local function sort(category) return NHStore.organizeWarehouse(state,{category=category}) end
assert(sort("equipment"))
assert(wallet.slot==1 and charger.slot==2 and charger.item.count==5 and pouch.slot==3)
assert(state.pouches[6]==pouch and pouch.cells[1].subtype=="frost" and safe.slot==4)
assert(first.slot==5 and second.slot==8 and other.slot==4)
assert(sort("spell") and first.slot==1 and second.slot==2 and other.slot==3)
assert(first.item.card.stack==2 and sort("spell") and second.slot==2)
state.order.output.slot=1
state.order.output.item=other.item
other.slot=7
first.slot=nil -- legacy rows can use their array index
assert(sort("spell") and second.slot==2 and first.slot==3 and other.slot==4)
assert(not sort("materials") and not sort("unknown"))
print("Warehouse sorting preserves item identities, stable ties, pouches and order reservations.")
