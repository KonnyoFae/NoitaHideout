local settings,flags,world={},{},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k]==true end
function AddFlagPersistent(k) flags[k]=true end
function GlobalsGetValue(k,default) return world[k] or default end
function GlobalsSetValue(k,v) world[k]=v end
dofile("mods/noita_hideout/files/store.lua")

local function entry(rows,key,value)
    for _,row in ipairs(rows) do
        if row[key]==value then return row end
    end
end
local function near(actual,want)
    assert(math.abs(actual-want)<1e-8,("Expected %g, got %g"):format(want,actual))
end

local s=assert(NHStore.load())
NHStore.newRun(s)
s.levels.dog_kennel,s.levels.cat_house=3,3
local empty=NHFarm.view(s,"zh",0)
assert(entry(empty.pens,"species","dog").petRows[1].rate=="0")
assert(entry(empty.pens,"species","cat").petRows[1].rate=="0")

for _=1,6 do
    for _,species in ipairs({"dog","cat"}) do
        assert(NHLivestock.deliver(s,species,assert(NHLivestock.freePen(s,species)),0,true))
    end
end
local view=NHFarm.view(s,"en",0)
local dog=entry(view.pens,"species","dog")
local cat=entry(view.pens,"species","cat")
assert(dog.petRows[1].id=="dog_find" and dog.petRows[1].rate=="6")
assert(cat.petRows[1].id=="cat_tool" and cat.petRows[1].rate=="2.25")
assert(not entry(view.produce,"id","gold"))
for id,rate in pairs({fiber=6,grain=4,herb=2,travel_satchel=.22,travel_pack=.22,loot_case=.11}) do
    near(entry(view.produce,"id",id).perMinute,rate)
end
for id,rate in pairs({fiber=6,grain=4,herb=2}) do
    near(entry(view.crops,"id",id).perMinute,rate)
end

assert(NHFarm.sync(s,3600))
assert(NHStore.commit(s))
s=assert(NHStore.load())
local after=NHFarm.view(s,"zh",3600)
near(entry(entry(after.pens,"species","dog").petRows,"id","travel_satchel").fraction,.22)
near(entry(entry(after.pens,"species","cat").petRows,"id","loot_case").fraction,.11)
assert(s.bankGold==0)
assert(not NHFarm.sync(s,3600))

s.levels.dragon_nest=1
assert(NHLivestock.deliver(s,"dragon_egg",assert(NHLivestock.freePen(s,"dragon_egg")),3600,true))
local withDragon=NHFarm.view(s,"zh",3600)
assert(entry(withDragon.pens,"species","dragon_egg").rareProgress==0)
near(entry(withDragon.produce,"id","gold").perMinute,30)
