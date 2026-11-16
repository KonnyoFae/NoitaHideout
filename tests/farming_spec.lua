local settings,flags,globals={},{},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
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

assert(#NHFarm.view(s,"zh",0).plots==0)
assert(not NHFarm.plant(s,request(1,"fiber"),0))
s.materials={sand=40,sandstone=70,sandstone_surface=650,water=99,rock_static=500}
local project=expansion("farmland")
assert(project.costs[1].available==760 and project.costs[1].amount==150 and not project.canBuy)
assert(not build("farmland") and s.materials.sand==40 and s.materials.sandstone==70)
s.materials.water=500
assert(not build("agri_equipment") and not expansion("agri_equipment").canBuy)
assert(build("farmland") and not s.materials.sand and not s.materials.sandstone and s.materials.sandstone_surface==610)
assert(build("farmland") and s.materials.water==200 and s.materials.sandstone_surface==310)
assert(s.materials.rock_static==500)
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
local harvest=request(1,"fiber")
assert(not NHFarm.harvest(s,harvest,7199) and not s.resources.fiber)
assert(NHFarm.observe(s,8400)==7200 and NHFarm.view(s,"zh",7200).plots[1].ready)
s.resources.fiber=NHStore.maxResourceAmount-5
assert(not NHFarm.harvest(s,harvest,7200) and s.farm.plots[1].crop=="fiber")
s.resources.fiber=nil
assert(NHFarm.harvest(s,harvest,7200) and s.resources.fiber==6 and not s.materials.fiber)
assert(not NHFarm.harvest(s,harvest,7200) and not NHFarm.plant(s,sow,7200))
assert(NHFarm.plant(s,request(1,"sugar"),7200) and not NHFarm.harvest(s,harvest,7200))

-- Death checkpoints elapsed gameplay, leaving each field's deadline intact.
assert(NHFarm.sync(s,8000) and NHStore.endRun(s,s.runSerial))
commit()
NHStore.newRun(s)
assert(NHFarm.observe(s,100)==8000)
assert(NHFarm.observe(s,10700)==18600 and NHFarm.sync(s,18600))
assert(NHFarm.view(s,"zh",18600).plots[2].ready)
local second=request(2,"active_herb")
local first=request(1,"sugar")
commit()
local stale=assert(NHStore.load())
assert(NHFarm.harvest(s,second,18600) and NHStore.commit(s))
assert(NHFarm.harvest(stale,second,18600) and not NHStore.commit(stale))
s=assert(NHStore.load())
assert(s.resources.active_herb==3 and not s.materials.active_herb)
assert(NHFarm.harvest(s,first,18600) and s.resources.sugar==4)
assert(NHFarm.observe(s,999999)==18600) -- idle time is not banked
assert(NHFarm.plant(s,request(1,"grain"),18600))
assert(NHFarm.observe(s,1000000)==18601 and not NHFarm.view(s,"en",18601).plots[1].ready)

s.materials.sand,s.materials.water=1050,700
assert(build("farmland") and build("farmland") and #NHFarm.view(s,"en",s.farm.time).plots==4)
assert(not build("farmland") and not s.materials.sand and not s.materials.water)

-- Write a pre-farm shaped payload with the real snapshot serializer.
local validateFarm=NHFarm.validate
s.farm,s.levels.farmland,s.levels.agri_equipment=nil,nil,nil
NHFarm.validate=function() end
assert(NHStore.commit(s))
NHFarm.validate=validateFarm
s=assert(NHStore.load())
assert(s.farm.time==0 and not next(s.farm.plots) and s.resources.fiber==6)
print("Farming: mixed sand costs, expansion gates, concurrent fields, active time, save/continue, limits and single harvest passed.")
