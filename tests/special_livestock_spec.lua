local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local state=assert(NHStore.load())
NHStore.newRun(state)
local function buy(id,slot) return NHStore.buyGood(state,{id=id,pen=slot},state.farm.time) end
local function build(id) return NHStore.buyUpgrade(state,{id=id,level=0}) end
local function persist()
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
end
local function find(rows,id)
    for _,row in ipairs(rows) do if row.id==id then return row end end
end

assert(NHStore.creditGold(state,3479))
assert(not buy("queen_bee",7) and not buy("dragon_egg",8))
state.materials={sand=175,sandstone=225,slime=75,gunpowder=100,oil=150}
state.resources={fiber=12,sugar=7}
assert(not build("beehive") and state.resources.fiber==12 and state.materials.slime==75)
state.resources.sugar=8
local menu=NHStore.progressMenu(state,"zh").expansion
assert(find(menu,"beehive").canBuy and find(menu,"dragon_nest").canBuy)
assert(build("beehive") and build("dragon_nest") and not build("beehive") and not build("dragon_nest"))
assert(not next(state.resources) and not next(state.materials))
assert(not NHFarm.sync(state,100000) and not state.dragonLoot and state.bankGold==3479)
local pens=NHFarm.view(state,"zh",0).pens
assert(#pens==2 and pens[1].id==7 and pens[2].id==8 and not pens[1].name and not pens[2].name)
assert(pens[1].yieldLabel=="糖分 / 香料" and pens[1].yieldValue=="5 / 2" and pens[2].yieldValue=="150 / 1")
assert(not buy("queen_bee",8) and buy("queen_bee",7) and not buy("queen_bee",7))
assert(state.bankGold==2999 and not buy("dragon_egg",8))
assert(NHStore.creditGold(state,1) and buy("dragon_egg",8) and state.bankGold==0)
local function projected(i) return NHLivestock.view(state,"en",state.farm.time)[i] end
local firstHoney,firstHoard=projected(1).nextAt,projected(2).nextAt
local cycle=NHLivestock.species.dragon_egg.period
assert(firstHoney==180*60 and firstHoard==(480+300)*60)
assert(NHFarm.view(state,"en",0).pens[1].grown and not NHFarm.view(state,"en",480*60-1).pens[2].grown)
assert(NHFarm.view(state,"en",480*60).pens[2].grown)
state.summons={beehive=100,pending={}}
persist()
assert(NHFarm.sync(state,firstHoney-1) and not state.resources.sugar)
local _,produced,cards=NHFarm.sync(state,firstHoney)
assert(produced and #cards==1 and cards[1]=="bee" and state.warehouse[1].item.species=="bee")
assert(state.resources.sugar==5 and state.resources.spice==2 and not state.summons.livestock)
assert(not NHFarm.sync(state,firstHoney))

-- Both harvests stay together if the spice stock cannot receive its share.
state.resources.spice=NHStore.maxResourceAmount-1
assert(NHFarm.sync(state,2*firstHoney) and not NHFarm.due(state,2*firstHoney))
assert(state.farm.herds.queen_bee.owed==1 and state.resources.sugar==5)
state.resources.spice=NHStore.maxResourceAmount-2
assert(NHFarm.due(state,2*firstHoney) and NHFarm.sync(state,2*firstHoney))
assert(state.resources.spice==NHStore.maxResourceAmount and state.resources.sugar==10)

-- The farm and livestock views show the same combined field/hive earnings.
state.levels.farmland=1
assert(NHFarm.plant(state,{plot=1,token=0,crop="sugar"},state.farm.time))
local farm=NHFarm.view(state,"zh",state.farm.time)
local sugarRate=4*60/150+5*60/180
assert(math.abs(find(farm.crops,"sugar").perMinute-sugarRate)<1e-9)
assert(math.abs(find(farm.produce,"sugar").perMinute-sugarRate)<1e-9)
assert(math.abs(find(farm.crops,"spice").perMinute-2/3)<1e-9)
assert(find(farm.produce,"gold").perMinute==0)

-- With insufficient bank headroom neither the date nor the reward seed moves.
state.resources.sugar=NHStore.maxResourceAmount
state.bankGold=NHStore.maxGold-149
state.dragonLoot={seed=100,pending={}}
assert(NHFarm.sync(state,firstHoard) and state.bankGold==NHStore.maxGold-149)
assert(state.dragonLoot.seed==100 and state.farm.herds.dragon_egg.owed==1)
farm=NHFarm.view(state,"en",firstHoard)
assert(farm.pens[2].blocked and find(farm.produce,"gold").perMinute==30)
assert(NHStore.spendGold(state,1))
for slot=2,NHStore.warehouseCapacity(state,"collection") do
    state.warehouse[#state.warehouse+1]={id=state.nextItemId,slot=slot,
        item=NHCompanions.withCount({species="griffin",remaining=1},1)}
    state.nextItemId=state.nextItemId+1
end
persist()
local stale=assert(NHStore.load())
local before=#state.warehouse
_,produced,cards=NHFarm.sync(state,firstHoard)
assert(produced and #cards==1 and cards[1]=="dragon")
assert(state.bankGold==NHStore.maxGold and state.bankWalletNet==0 and #state.warehouse==before)
assert(NHFarm.view(state,"en",firstHoard).dragonPending==1)
persist()
assert(NHFarm.sync(stale,firstHoard) and not NHStore.commit(stale))
assert(not NHFarm.sync(state,firstHoard) and state.dragonLoot.pending.dragon==1)
table.remove(state.warehouse)
persist()
assert(not next(state.dragonLoot.pending) and state.warehouse[before].item.species=="dragon")
assert(state.warehouse[before].item.remaining==80 and projected(2).nextAt==firstHoard+cycle)
assert(not NHFarm.sync(state,firstHoard))

-- Each overdue cycle grants one item (possibly queued) and the same gold payment.
local function itemCount(s)
    local n=NHDragonLoot.pendingCount(s)
    for _,row in ipairs(s.warehouse) do n=n+(row.item.count or 1) end
    return n
end
local oldCount=itemCount(state)
assert(NHStore.spendGold(state,450) and NHFarm.sync(state,firstHoard+3*cycle))
persist()
assert(itemCount(state)==oldCount+3 and state.bankGold==NHStore.maxGold)
assert(not NHFarm.sync(state,firstHoard+3*cycle))

local function mixedHerds()
    local s=assert(NHStore.load())
    s.levels={beehive=3,dragon_nest=3,gel_pool=3}
    s.farm={time=0,plots={},passive=true}
    s.bankGold,s.resources,s.warehouse,s.nextItemId=0,{},{},1
    s.gelBonus,s.dragonLoot,s.summons=nil,nil,nil
    local function add(species,now,adult)
        assert(NHLivestock.deliver(s,species,assert(NHLivestock.freePen(s,species)),now,adult))
    end
    add("gel_pool",0,true)
    add("gel_pool",0)
    add("dragon_egg",0)
    add("dragon_egg",600)
    add("queen_bee",600)
    add("queen_bee",1200)
    return s
end
local single=mixedHerds()
local ticks=mixedHerds()
local firstGel=NHFarm.view(single,"en",1200).pens[3]
assert(firstGel.adults==1 and firstGel.juveniles==1 and firstGel.nextAt==10800)
local firstCredits=NHFarm.view(single,"en",1200).pens[2].nextAt
assert(firstCredits==38100)
local firstSugar=NHFarm.view(single,"en",1200).pens[1]
assert(firstSugar.nextAt==6300 and firstSugar.effectivePeriod==90)
local ending=1200+120000
assert(NHFarm.sync(single,ending))
for at=1230,ending,30 do NHFarm.sync(ticks,at) end
for _,name in ipairs({"herb","fiber","sugar","spice"}) do assert(single.resources[name]==ticks.resources[name]) end
assert(single.bankGold==ticks.bankGold and single.dragonLoot.seed==ticks.dragonLoot.seed and single.gelBonus.seed==ticks.gelBonus.seed)
assert(single.summons.beehive==ticks.summons.beehive and single.summons.gel_pool==ticks.summons.gel_pool)
for species,herd in pairs(single.farm.herds) do
    local other=ticks.farm.herds[species]
    assert(herd.adults==other.adults and herd.owed==other.owed and herd.progress==other.progress)
end
print("Special livestock: independent buildings, purchases, passive rates, capped and replay-safe gold and item deliveries passed.")
