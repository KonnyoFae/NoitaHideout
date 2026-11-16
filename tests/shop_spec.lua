local settings,flags={},{}
local reject_snapshot=false
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value)
    if not (reject_snapshot and key:match("^noita_hideout%.p%d+_[ab]$")) then settings[key]=value end
end
function HasFlagPersistent(key) return flags[key]==true end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")

local s=assert(NHStore.load())
local run=NHStore.newRun(s)
local goods={}
for _,good in ipairs(NHStore.shopGoods) do
    assert(not goods[good.id] and good.price>0 and good.quantity>0)
    goods[good.id]=good
end
local function buy(id)
    return NHStore.buyGood(s,{id=id})
end
local function persist()
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
end
local function finish()
    local changed,delivered=NHStore.advanceProduction(s,{run=run,orderId=s.order.id,progress=s.order.required})
    assert(changed and delivered)
end
assert(not NHStore.canBuyGood(s,goods.water))
assert(not buy("water") and not buy("unknown") and not NHStore.buyGood(s,nil))
assert(s.bankGold==0 and not next(s.materials) and #s.warehouse==0)
assert(NHStore.creditGold(s,3000))
s.bankWalletNet=-135
persist()

local cost=0
for name,price in pairs({water=20,sand=25,oil=40,slime=50}) do
    local good=assert(goods[name])
    assert(good.material==name and good.category=="materials" and good.price==price and good.quantity==250)
    -- Extra request fields cannot lower the price or redirect/inflate delivery.
    assert(NHStore.buyGood(s,{id=name,price=0,quantity=9999,material="gold"}))
    cost=cost+price
    assert(s.bankGold==3000-cost and s.materials[name]==250 and not s.materials.gold)
end
assert(goods.medkit.price==120 and goods.injector.price==160)
assert(buy("medkit") and buy("medkit"))
assert(s.warehouse[1].item.kind=="medkit" and s.warehouse[1].item.remaining==3)
s.warehouse[1].item.remaining=1
assert(s.warehouse[2].item.remaining==3 and s.warehouse[1].id~=s.warehouse[2].id)
assert(buy("injector"))
s.warehouse[3].item.remaining=2
assert(buy("injector") and buy("injector"))
assert(#s.warehouse==4 and s.warehouse[3].item.count==1)
assert(s.warehouse[4].item.remaining==NHStore.doseDurability and s.warehouse[4].item.count==2)
persist()
assert(s.bankGold==3000-cost-2*120-3*160 and s.bankWalletNet==-135)

-- Failed or competing writes cannot commit payment without its delivery.
local gold,water=s.bankGold,s.materials.water
assert(buy("water"))
reject_snapshot=true
assert(not NHStore.commit(s))
reject_snapshot=false
s=assert(NHStore.load())
assert(s.bankGold==gold and s.materials.water==water)
local stale=assert(NHStore.load())
assert(NHStore.buyGood(stale,{id="water"}) and buy("water"))
persist()
assert(not NHStore.commit(stale))
assert(s.bankGold==gold-20 and s.materials.water==water+250 and s.bankWalletNet==-135)

-- A funded batch owns its future material type even before any output exists.
local unstable,stable="magic_liquid_unstable_teleportation","magic_liquid_teleportation"
s.materials={oil=10,[unstable]=250,slime=250}
assert(NHStore.startOrder(s,"stable"))
for i=1,NHStore.warehouseCapacity(s,"materials")-2 do s.materials["filler_"..i]=1 end
persist()
gold=s.bankGold
local ok,reason=buy("sand")
assert(not ok and reason=="Material storage is full." and s.bankGold==gold and not s.materials.sand)
assert(buy("oil") and s.materials.oil==260)
finish()
assert(s.materials[stable]==500)
persist()

-- Reserve the last supplies slot for a medkit. A partial injector cannot
-- absorb a new one. A legacy full injector without a count accepts one.
s.materials={water=100,blood=50}
s.levels.medical=1
s.warehouse={}
local slots=NHStore.warehouseCapacity(s,"supplies")
for i=1,slots-1 do
    s.warehouse[i]={id=s.nextItemId,slot=i,item={kind="medkit",remaining=3}}
    s.nextItemId=s.nextItemId+1
end
s.warehouse[1].item={kind="dose",remaining=2,count=1}
assert(NHStore.startOrder(s,"medical") and s.order.output.slot==slots)
gold=s.bankGold
ok,reason=buy("medkit")
assert(not ok and reason=="Supplies storage is full.")
assert(not buy("injector") and s.bankGold==gold and #s.warehouse==slots-1)
s.warehouse[2].item={kind="dose"}
persist()
assert(buy("injector") and s.warehouse[2].item.count==2 and s.warehouse[1].item.remaining==2)
finish()
assert(#s.warehouse==slots and s.warehouse[slots].item.kind=="medkit")
assert(not buy("medkit") and s.bankGold==gold-160)
persist()
-- Check the last exact representable stock amount as well as distinct types.
s.materials={water=9007199254740991-250}
assert(buy("water") and s.materials.water==9007199254740991)
gold=s.bankGold
assert(not buy("water") and s.bankGold==gold)
persist()
assert(s.bankWalletNet==-135 and s.bankGold==gold)
print("Shop: material and supply offers, exact savings debits, warehouse reservations, full-dose stacks and atomic purchase recovery passed.")
