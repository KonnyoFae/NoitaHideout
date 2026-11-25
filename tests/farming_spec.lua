local settings,flags,globals={},{},{}
local failHead=false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) if not (failHead and k:match("_revision$")) then settings[k]=v end end
function HasFlagPersistent(k) return flags[k]==true end
function AddFlagPersistent(k) flags[k]=true end
function GlobalsGetValue(k,default) return globals[k] or default end
function GlobalsSetValue(k,value) globals[k]=value end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local s=assert(NHStore.load())
NHStore.newRun(s)
local function build(id)
    return NHStore.buyUpgrade(s,{id=id,level=NHStore.level(s,id)})
end
local function expansion(id)
    for _,row in ipairs(NHStore.progressMenu(s,"en").expansion) do if row.id==id then return row end end
end
local function request(plot,crop)
    return {plot=plot,crop=crop,token=(s.farm.plots[plot] or {}).token or 0}
end
local function commit()
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
end
local function cropRates(now)
    local rates={}
    for _,row in ipairs(NHFarm.view(s,"en",now).crops) do rates[row.id]=row.perMinute end
    return rates
end

assert(#NHFarm.view(s,"zh",0).plots==0)
assert(not NHFarm.plant(s,request(1,"fiber"),0))
s.materials={sand=40,sandstone=70,sandstone_surface=200,water=500,mud=500,soil_dead=500,soil_dark=500}
local project=expansion("farmland")
assert(project.costs[1].name=="Soil (total)" and project.costs[1].available==0 and project.costs[1].amount==150)
assert(not project.canBuy and not build("farmland") and s.materials.water==500)
s.materials.soil,s.materials.soil_lush,s.materials.soil_lush_dark=100,30,320
s.materials.water=99
project=expansion("farmland")
assert(project.costs[1].available==450 and not project.canBuy)
assert(not build("farmland") and s.materials.soil==100 and s.materials.soil_lush==30)
s.materials.water=500
assert(not build("agri_equipment") and not expansion("agri_equipment").canBuy)
assert(build("farmland") and not s.materials.soil and not s.materials.soil_lush and s.materials.soil_lush_dark==300)
assert(build("farmland") and s.materials.water==200 and not s.materials.soil_lush_dark)
assert(s.materials.sand==40 and s.materials.sandstone==70 and s.materials.sandstone_surface==200)
assert(s.materials.mud==500 and s.materials.soil_dead==500 and s.materials.soil_dark==500)
assert(not NHFarm.plant(s,request(1,"spice"),0))
assert(build("agri_equipment") and not s.materials.water and s.materials.sandstone_surface==10)
assert(not build("agri_equipment"))
local menu=NHFarm.view(s,"en",0)
assert(#menu.crops==6 and #menu.plots==2 and menu.equipment and menu.crops[6].unlocked)

local sow=request(1,"fiber")
assert(NHFarm.observe(s,999)==0 and NHFarm.plant(s,sow,0))
assert(not NHFarm.plant(s,sow,0))
assert(NHFarm.observe(s,1299)==300 and not NHFarm.due(s,300))
-- Restore the sub-checkpoint progress from the world save, without counting
-- menu/real time between sessions. A suspended frame interval does not grow crops.
commit()
NHFarm.resetClock()
assert(NHFarm.observe(s,1299)==300)
NHFarm.suspendClock()
assert(NHFarm.observe(s,1500)==300 and NHFarm.observe(s,1800)==600 and not NHFarm.due(s,600))
assert(NHFarm.plant(s,request(2,"active_herb"),600))
assert(s.farm.time==600 and s.farm.plots[2].readyAt==18600)
s.summons={farm=31,pending={}}
local first=3600
assert(not NHFarm.due(s,first-1) and NHFarm.due(s,first))
assert(NHFarm.sync(s,first) and s.resources.fiber==3 and s.summons.farm==31)
assert(not s.resources.active_herb and not NHFarm.sync(s,first))
-- Fill the fiber ledger. The earned balance and the independently due card
-- survive a failed write and enter the committed profile exactly once.
s.resources.fiber=NHStore.maxResourceAmount
commit()
local stale=assert(NHStore.load())
local function settleFull(draft)
    local changed,_,awards=NHFarm.sync(draft,7200)
    assert(changed and #awards==1 and awards[1]=="dryad")
    assert(draft.resources.fiber==NHStore.maxResourceAmount)
end
settleFull(s)
failHead=true
assert(not NHStore.commit(s))
failHead=false
s=assert(NHStore.load())
assert(s.summons.farm==31 and #s.warehouse==0)
settleFull(s)
commit()
settleFull(stale)
assert(not NHStore.commit(stale))
assert(s.summons.farm~=31 and #s.warehouse==1)
assert(NHFarm.view(s,"zh",7200).plots[1].blocked and not NHFarm.due(s,7200))
s.resources.fiber=NHStore.maxResourceAmount-3
assert(NHFarm.due(s,7200) and NHFarm.sync(s,7200) and not NHFarm.sync(s,7200))
assert(s.resources.fiber==NHStore.maxResourceAmount and #s.warehouse==1)

-- Preserve already worked fiber on a switch; sugar starts earning at the switch.
s.resources.fiber=nil
local switch=request(1,"sugar")
assert(NHFarm.plant(s,switch,9000) and not NHFarm.plant(s,switch,9001))
assert(not NHFarm.plant(s,request(1,"sugar"),9001))
assert(NHFarm.sync(s,10800) and s.resources.fiber==1 and not s.resources.sugar)
local sugarRate=cropRates(10800).sugar
assert(math.abs(sugarRate-1.6*1.06)<1e-9)
assert(NHFarm.sync(s,11500) and NHStore.endRun(s,s.runSerial))
commit()
NHStore.newRun(s)
assert(NHFarm.observe(s,100)==11500)
assert(NHFarm.observe(s,10200)==21600 and NHFarm.sync(s,21600))
assert(s.resources.sugar==5 and s.resources.active_herb==3 and not s.materials.sugar)
assert(not NHFarm.sync(s,21600) and not NHFarm.due(s,21600))
globals.noita_hideout_farm_clock=s.profile.."/"..s.runSerial.."/21000"
NHFarm.resetClock()
assert(NHFarm.observe(s,0)==21600 and NHFarm.observe(s,600)==21600)
assert(not NHFarm.due(s,21600) and NHFarm.observe(s,601)==21601)

s.materials.soil,s.materials.water=1050,700
assert(build("farmland") and build("farmland") and #NHFarm.view(s,"en",s.farm.time).plots==4)
assert(not build("farmland") and not s.materials.soil and not s.materials.water)
assert(NHFarm.plant(s,request(1,"grain"),21600))
assert(NHFarm.plant(s,request(3,"grain"),21600))
local rates=cropRates(21600)
assert(math.abs(rates.grain-4.4)<1e-9 and math.abs(rates.active_herb-0.66)<1e-9 and rates.fiber==0)
local deadline=s.farm.plots[3].readyAt
assert(NHFarm.plant(s,request(3,"herb"),21600) and s.farm.plots[3].readyAt==deadline)
rates=cropRates(21600)
assert(math.abs(rates.grain-2.2)<1e-9 and math.abs(rates.herb-4.4/3)<1e-9)
assert(not s.farm.plots[4])

-- Serialize a pre-passive snapshot: a long-overdue manual field held one harvest.
s.farm={time=21600,plots={[1]={token=1,crop="grain",readyAt=7200}}}
local validateFarm=NHFarm.validate
NHFarm.validate=function() end
assert(NHStore.commit(s))
NHFarm.validate=validateFarm
s=assert(NHStore.load())
assert(s.farm.passive and not s.resources.grain)
assert(NHFarm.sync(s,21600) and s.resources.grain==6)
commit()
assert(not NHFarm.sync(s,21600) and s.resources.grain==6)
s.farm,s.levels.farmland,s.levels.agri_equipment=nil,nil,nil
NHFarm.validate=function() end
assert(NHStore.commit(s))
NHFarm.validate=validateFarm
s=assert(NHStore.load())
assert(s.farm.time==0 and not next(s.farm.plots) and s.resources.grain==6)
print("Farming: minute balances, crop switching, reloads, full stock, manual-save adoption and atomic card rewards passed.")
