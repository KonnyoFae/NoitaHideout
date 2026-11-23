local settings,flags,world={},{},{}
local fail_head=false
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value)
    if not (fail_head and key:match("_revision$")) then settings[key]=value end
end
function HasFlagPersistent(key) return flags[key]==true end
function AddFlagPersistent(key) flags[key]=true end
function GlobalsGetValue(key,default) return world[key] or default end
function GlobalsSetValue(key,value) world[key]=value end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
local controller=NHAffinity
-- Simulate independently loaded code in the companion behavior's Lua state.
dofile("mods/noita_hideout/files/affinity.lua")
local entity=NHAffinity
assert(controller~=entity and entity.follow("dryad",6)==0)

local state=assert(NHStore.load())
local function start()
    NHStore.newRun(state)
    GlobalsSetValue("noita_hideout_run_v1",state.profile.."/"..state.runSerial)
    controller.bind(state)
end
local function spend(species,frames)
    local points
    for i=6,frames,6 do points=entity.follow(species,6) end
    return points
end
start()
assert(spend("dryad",354)==9 and spend("flower_fairy",360)==10)
assert(controller.points(state,"dryad")==9 and controller.points(state,"flower_fairy")==10)
assert(entity.follow("dryad",6)==10 and controller.changed(state))
controller.sync(state)
assert(state.affinity.dryad==360 and state.affinity.flower_fairy==360)
assert(NHStore.commit(state) and not controller.changed(state))

local function copyWorld()
    local copy={}
    for k,v in pairs(world) do copy[k]=v end
    return copy
end
local earlierWorld=copyWorld()
-- Save and resume between profile checkpoints. The world carries the remainder.
assert(spend("dryad",300)==18)
state=assert(NHStore.load())
controller.bind(state)
assert(spend("dryad",60)==20)
controller.sync(state)
fail_head=true
assert(not NHStore.commit(state))
fail_head=false
state=assert(NHStore.load())
controller.bind(state)
assert(controller.points(state,"dryad")==20 and controller.changed(state))
controller.sync(state)
assert(NHStore.commit(state) and state.affinity.dryad==720)

-- A restored older world must retain the current benefit and not credit the
-- same portion of its world clock again.
world=earlierWorld
controller.bind(state)
assert(controller.points(state,"dryad")==20 and spend("dryad",360)==20)
assert(not controller.changed(state) and entity.follow("dryad",6)==20)
controller.sync(state)
assert(state.affinity.dryad==726)
assert(NHStore.endRun(state,state.runSerial) and NHStore.commit(state))
world={}
state=assert(NHStore.load())
start()
assert(spend("dryad",354)==30 and controller.points(state,"flower_fairy")==10)
assert(spend("dryad",7*360)==100 and controller.tier(100)==1 and controller.tier(99)==0)
assert(spend("dryad",30*360)==400 and controller.tier(400)==2 and controller.tier(399)==1)
assert(spend("dryad",60*360)==1000 and controller.tier(1000)==3 and controller.tier(999)==2)
assert(entity.follow("dryad",6)==1000)
assert(spend("bee",10*360)==100 and spend("dragon",360)==10)
assert(spend("slime",40*360)==400)
controller.sync(state)
assert(NHStore.commit(state) and state.affinity.dryad==36006)
local saved=assert(NHStore.load())
assert(saved.affinity.bee==3600 and saved.affinity.dragon==360 and saved.affinity.slime==14400)
assert(entity.follow("dryad",360000)==10000 and entity.follow("dryad",600)==10000)
assert(entity.tier(10000)==3 and entity.incomeBasisPoints(1000)==0 and entity.incomeBasisPoints(10000)==900)
state.affinity.dryad=360001
assert(not NHStore.commit(state))
print("Companion affinity persists across summons, worlds and failed writes, keeping fractional progress and capped independent ranks.")
