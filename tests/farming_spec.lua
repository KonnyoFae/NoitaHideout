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
assert(project.costs[1].name=="Soil" and project.costs[1].available==0 and project.costs[1].amount==150)
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
assert(NHFarm.observe(s,1500)==300 and NHFarm.observe(s,1800)==600 and NHFarm.due(s,600))
assert(NHFarm.plant(s,request(2,"active_herb"),600))
assert(s.farm.time==600 and s.farm.plots[2].readyAt==18600)
local switch=request(1,"sugar")
assert(NHFarm.observe(s,8300)==7100)
assert(NHFarm.plant(s,switch,7100) and s.farm.plots[1].readyAt==7200)
assert(not NHFarm.plant(s,switch,7110) and not NHFarm.plant(s,request(1,"sugar"),7110))
assert(NHFarm.observe(s,8400)==7200 and NHFarm.due(s,7200))
s.resources.sugar=NHStore.maxResourceAmount-3
local changed,produced=NHFarm.sync(s,7200)
assert(changed and not produced and not NHFarm.due(s,7200))
assert(NHFarm.view(s,"zh",7200).plots[1].blocked)
assert(not s.resources.fiber and not s.summons)
assert(NHFarm.plant(s,request(1,"fiber"),7250))
assert(s.farm.pending.sugar==1 and s.farm.plots[1].readyAt==16200)
assert(cropRates(7250).sugar==0 and cropRates(7250).fiber==3)
assert(not NHFarm.plant(s,sow,7250))

-- Death checkpoints elapsed gameplay, leaving each field's deadline intact.
assert(NHFarm.sync(s,8000) and NHStore.endRun(s,s.runSerial))
commit()
NHStore.newRun(s)
assert(NHFarm.observe(s,100)==8000)
assert(NHFarm.observe(s,10700)==18600 and NHFarm.sync(s,18600))
assert(s.farm.plots[1].crop=="fiber" and s.farm.plots[1].readyAt==23400)
assert(s.farm.plots[2].crop=="active_herb" and s.farm.plots[2].readyAt==36600)
assert(s.resources.fiber==6 and s.resources.active_herb==3 and not s.materials.fiber)
assert(not NHFarm.sync(s,18600) and not NHFarm.due(s,18600))
-- Freeing room delivers the old sugar batch once, including its card roll.
s.resources.sugar=nil
s.summons.farm=31
commit()
local stale=assert(NHStore.load())
assert(NHFarm.due(s,18600))
local ok,stock,awards=NHFarm.sync(s,18600)
assert(ok and stock and awards[1]=="dryad" and not s.farm.pending and s.resources.sugar==4)
failHead=true
assert(not NHStore.commit(s))
failHead=false
s=assert(NHStore.load())
assert(s.farm.pending.sugar==1 and not s.resources.sugar and s.summons.farm==31)
assert(NHFarm.sync(s,18600) and NHStore.commit(s))
assert(NHFarm.sync(stale,18600) and not NHStore.commit(stale))
s=assert(NHStore.load())
assert(s.resources.sugar==4 and not NHFarm.sync(s,18600))
-- Restoring an earlier world of the same run replays its clock without
-- doubling payment for the already committed span.
globals.noita_hideout_farm_clock=s.profile.."/"..s.runSerial.."/18000"
NHFarm.resetClock()
assert(NHFarm.observe(s,0)==18600 and NHFarm.observe(s,600)==18600)
assert(not NHFarm.due(s,18600) and NHFarm.observe(s,601)==18601)
assert(NHFarm.sync(s,30600) and s.resources.fiber==18 and s.resources.active_herb==3)
assert(NHFarm.plant(s,request(1,"grain"),30600) and s.farm.plots[1].readyAt==37800)

s.materials.soil,s.materials.water=1050,700
assert(build("farmland") and build("farmland") and #NHFarm.view(s,"en",s.farm.time).plots==4)
assert(not build("farmland") and not s.materials.soil and not s.materials.water)
assert(NHFarm.plant(s,request(3,"grain"),s.farm.time))
local rates=cropRates(s.farm.time)
assert(rates.grain==4 and rates.active_herb==0.6 and rates.fiber==0 and rates.herb==0)
local deadline=s.farm.plots[3].readyAt
assert(NHFarm.plant(s,request(3,"herb"),s.farm.time) and s.farm.plots[3].readyAt==deadline)
rates=cropRates(s.farm.time)
assert(rates.grain==2 and math.abs(rates.herb-4/3)<1e-9)
assert(not s.farm.plots[4])

-- Write a pre-farm shaped payload with the real snapshot serializer.
-- Old manual fields that sat ripe for many cycles held only one earned crop.
s.farm.passive=nil
s.farm.plots[1].readyAt=7200
commit()
assert(s.farm.passive and s.farm.plots[1].readyAt==30600 and not s.resources.grain)
assert(NHFarm.sync(s,30600) and s.resources.grain==6)
local validateFarm=NHFarm.validate
s.farm,s.levels.farmland,s.levels.agri_equipment=nil,nil,nil
NHFarm.validate=function() end
assert(NHStore.commit(s))
NHFarm.validate=validateFarm
s=assert(NHStore.load())
assert(s.farm.time==0 and not next(s.farm.plots) and s.resources.fiber==18)
print("Farming: passive income, switching before maturity and with a full store, legacy schedules and atomic card rewards passed.")
