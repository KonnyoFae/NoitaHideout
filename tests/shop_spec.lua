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
    assert(not goods[good.id] and (good.insurance or good.resource or good.price>0) and good.quantity>0)
    goods[good.id]=good
end
local function buy(id)
    return NHStore.buyGood(s,{id=id})
end
local offer=assert(goods.rescue_policy)
do
    local account={bankGold=0,resources={arcane_scrap=1}}
    assert(NHStore.buyGood(account,{id=offer.id}) and account.bankGold==0 and account.resources.arcane_scrap==0)
    assert(account.insuranceActive and account.insuranceSerial==1)
    assert(not NHStore.buyGood(account,{id=offer.id}))
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
for name,price in pairs({water=5,sand=10,oil=10,slime=15}) do
    local good=assert(goods[name])
    assert(good.material==name and good.category=="materials" and good.price==price and good.quantity==250)
    -- Extra request fields cannot lower the price or redirect/inflate delivery.
    assert(NHStore.buyGood(s,{id=name,price=0,quantity=9999,material="gold"}))
    cost=cost+price
    assert(s.bankGold==3000-cost and s.materials[name]==250 and not s.materials.gold)
end
assert(goods.medkit.price==50 and goods.injector.price==80)
assert(buy("medkit"))
assert(s.warehouse[1].item.kind=="medkit" and s.warehouse[1].item.remaining==8)
s.warehouse[1].item.remaining=1
assert(buy("medkit") and s.warehouse[1].item.count==2 and s.warehouse[1].item.remaining==1)
assert(buy("injector"))
s.warehouse[2].item.remaining=2
assert(buy("injector") and buy("injector"))
assert(#s.warehouse==3 and s.warehouse[2].item.count==1)
assert(s.warehouse[3].item.remaining==NHStore.doseDurability and s.warehouse[3].item.count==2)
persist()
assert(s.bankGold==3000-cost-2*50-3*80 and s.bankWalletNet==-135)

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
assert(s.bankGold==gold-5 and s.materials.water==water+250 and s.bankWalletNet==-135)

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
    s.warehouse[i]={id=s.nextItemId,slot=i,item={kind="medkit",remaining=3,count=4}}
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
assert(not buy("medkit") and s.bankGold==gold-80)
persist()
-- Check the last exact representable stock amount as well as distinct types.
s.materials={water=9007199254740991-250}
assert(buy("water") and s.materials.water==9007199254740991)
gold=s.bankGold
assert(not buy("water") and s.bankGold==gold)
persist()
assert(s.bankWalletNet==-135 and s.bankGold==gold)

local function testAnimalOffers()
    settings,flags={},{}
    s=assert(NHStore.load())
    NHStore.newRun(s)
    assert(NHStore.creditGold(s,20000))
    s.materials={sand=(200+400),water=(150+150),oil=150,gunpowder=100,slime=(75+250),soil=100}
    s.resources={fiber=12,sugar=8}
    for _,id in ipairs({"chick","calf","queen_bee","dragon_egg","gel_pool"}) do assert(not NHStore.canBuyGood(s,goods[id])) end
    for _,id in ipairs({"livestock","beehive","dragon_nest","gel_pool"}) do assert(NHStore.buyUpgrade(s,{id=id,level=0},0)) end
    local ready,gelSlot=NHStore.canBuyGood(s,goods.gel_pool)
    assert(ready)
    s.bankGold=319
    assert(not NHStore.buyGood(s,{id="gel_pool",pen=gelSlot},60) and s.bankGold==319)
    s.bankGold=20000
    local deliver=NHLivestock.deliver
    NHLivestock.deliver=function() return false end
    assert(not NHStore.buyGood(s,{id="gel_pool",pen=gelSlot},60) and s.bankGold==20000)
    NHLivestock.deliver=deliver
    for _,entry in ipairs({{"chick",120},{"calf",240},{"queen_bee",480},{"dragon_egg",3000},{"gel_pool",320}}) do
        local id,price=unpack(entry)
        assert(goods[id].price==price and goods[id].quantity==1)
        local count=id=="gel_pool" and 1 or 2
        for _=1,count do
            local ready,slot=NHStore.canBuyGood(s,goods[id])
            assert(ready and type(slot)=="number")
            local previous=s.bankGold
            local request={id=id,pen=slot}
            assert(NHStore.buyGood(s,request,60) and s.bankGold==previous-price)
            assert(not NHStore.buyGood(s,request,60) and s.bankGold==previous-price)
            persist()
        end
        assert(not NHStore.canBuyGood(s,goods[id]))
    end
    local pens=NHLivestock.view(s,"en",s.farm.time)
    local gel=pens[#pens]
    assert(gel.count==2 and gel.juveniles==1 and gel.adults==1)
    pens=NHLivestock.view(s,"en",s.farm.time+120*60)
    assert(pens[#pens].adults==2 and pens[#pens].juveniles==0)
end
testAnimalOffers()
local stock={warehouse={},resources={},materials={},bankGold=0}
for kind in pairs(NHStormProducts.types) do table.insert(stock.warehouse,{item={kind=kind,count=8}}) end
assert(#NHStormProducts.offers==2)
for _,offer in ipairs(NHStormProducts.offers) do
    assert(not NHStore.buyGood(stock,{id=offer.id}))
    stock.resources[offer.resource]=1
    stock.bankGold=NHStore.maxGold-499
    assert(not NHStore.buyGood(stock,{id=offer.id}) and stock.resources[offer.resource]==1)
    stock.bankGold=0
    assert(NHStore.buyGood(stock,{id=offer.id}) and stock.bankGold==500 and not stock.resources[offer.resource])
    assert(not NHStore.buyGood(stock,{id=offer.id}) and stock.bankGold==500)
end
for _,row in ipairs(stock.warehouse) do assert(row.item.count==8) end
assert(#stock.warehouse==4)
for _,id in ipairs({"storm_mercury_sell","storm_mercury_pressure_sell","storm_mana_sell","storm_mana_pure_sell",
    "storm_mercury_distill","storm_mercury_pressure_distill","storm_mana_arcane",
    "storm_mana_container","storm_mana_pure_arcane","storm_mana_pure_container"}) do
    local ok,reason=NHStore.buyGood(stock,{id=id})
    assert(not ok and reason=="Unknown shop item.")
end
print("Shop: material and supply offers, exact savings debits, warehouse reservations, full-dose stacks and atomic purchase recovery passed.")

do
    local t=assert(NHStore.load())
    t.warehouse,t.resources,t.materials,t.order,t.bankGold={},{},{},false,1000
    local trade=NHStore.supplyTrade
    local function use(row,mode,all)
        local q=assert(trade.quote(row.item))
        return trade.apply(t,{id=row.id,kind=row.item.kind,slot=row.slot,mode=mode,
            quantity=all and q.count or 1,count=q.count,remaining=q.remaining})
    end
    for _,id in ipairs({"medkit","injector","bandage","hard_bread","cheese","injector_quick_heal"}) do
        local balance=t.bankGold
        assert(NHStore.buyGood(t,{id=id}) and #t.warehouse==1)
        local row=t.warehouse[1]
        assert((row.item.count or 1)==1 and trade.quote(row.item).oneGold*2==goods[id].price)
        assert(use(row,"sell") and #t.warehouse==0 and t.bankGold==balance-goods[id].price/2)
    end
    assert(goods.medkit.price==50 and goods.injector.price==80)
    local function add(kind,count,remaining)
        local row={item={kind=kind,count=count,remaining=remaining},slot=#t.warehouse+1,id=t.nextItemId}
        t.nextItemId=t.nextItemId+1
        table.insert(t.warehouse,row)
        return row
    end
    local row=add("medkit",3,4)
    assert(trade.quote(row.item).allGold==62 and trade.quote(row.item).oneGold==12)
    local before=t.bankGold
    assert(use(row,"sell") and row.item.count==2 and row.item.remaining==8)
    assert(not trade.apply(t,{kind="medkit",slot=1,id=row.id,count=3,remaining=4,quantity=3,mode="sell"}))
    assert(use(row,"sell",true) and t.bankGold==before+62)
    assert(trade.quote({kind="fire_grenade",count=8}).allGold==8*trade.quote({kind="fire_grenade",count=1}).oneGold)
    assert(trade.quote({kind="cake",remaining=1,count=2}).oneGold<trade.quote({kind="cake"}).oneGold)
    assert(not trade.quote({kind="wand"}))
    for kind in pairs(NHLootBags.types) do
        local box=add(kind,3)
        assert(not trade.quote(box.item))
        for _,quantity in ipairs({1,3}) do
            assert(not trade.apply(t,{kind=kind,slot=1,id=box.id,count=3,remaining=1,quantity=quantity,mode="sell"}))
        end
        assert(t.warehouse[1]==box and box.item.count==3 and t.bankGold==before+62)
        table.remove(t.warehouse,1)
    end
    add("storm_mercury_pressure",1)
    add("storm_mana_pure",1)
    for _,recipe in ipairs(NHStormProducts.recipes) do
        local ok,reason=NHStore.startOrder(t,recipe.id)
        assert(not ok and reason=="Not enough workshop resources." and #t.warehouse==2)
    end
    t.warehouse={}
    for _,kind in ipairs({"storm_mercury","storm_mercury_pressure","storm_mana","storm_mana_pure"}) do
        local p=NHStormProducts.types[kind]
        row=add(kind,8)
        local start=t.resources[p.resource] or 0
        local gold=t.bankGold
        assert(not trade.quote(row.item).oneGold and not use(row,"sell") and not use(row,"sell",true))
        assert(row.item.count==8 and t.bankGold==gold and (t.resources[p.resource] or 0)==start)
        assert(use(row,"convert",true) and #t.warehouse==0 and t.resources[p.resource]==start+8*p.units)
    end
    assert(t.resources.nh_red_mercury==408 and t.resources.nh_crystallized_mana==408)
    add("storm_mercury_pressure",2)
    assert(NHStore.commit(t))
    t=assert(NHStore.load())
    assert(NHStore.startOrder(t,"refine_red_mercury") and NHStore.commit(t))
    t=assert(NHStore.load())
    assert(NHStore.advanceProduction(t,{run=t.runSerial,orderId=t.order.id,progress=t.order.required}))
    assert(t.materials.midas==20 and t.resources.nh_elixir_of_immortality==20 and t.resources.nh_red_mercury==407)
    assert(t.warehouse[1].item.kind=="storm_mercury_pressure" and t.warehouse[1].item.count==2)
    assert(NHStore.craft(t,"refine_mana_arcane") and NHStore.craft(t,"refine_mana_container"))
    assert(t.resources.arcane_scrap==20 and t.resources.container_scrap==20 and t.resources.nh_crystallized_mana==406)
    assert(NHStore.buyGood(t,{id="sell_red_mercury"}) and t.resources.nh_red_mercury==406)
    assert(t.warehouse[1].item.count==2 and not use(t.warehouse[1],"sell",true))
    t.materials.midas=NHStore.maxMaterialAmount
    assert(not NHStore.craft(t,"refine_red_mercury") and t.resources.nh_red_mercury==406)
    row=add("storm_mercury_pressure",8)
    t.resources.nh_red_mercury=NHStore.maxResourceAmount-399
    assert(not use(row,"convert",true) and row.item.count==8 and t.resources.nh_red_mercury==NHStore.maxResourceAmount-399)
    t.bankGold=NHStore.maxGold
    assert(not use(row,"sell") and row.item.count==8)
end
