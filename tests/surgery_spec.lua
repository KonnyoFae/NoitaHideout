NHSurgeryKits=dofile("mods/noita_hideout/files/surgery_kits.lua")
local cast=dofile("mods/noita_hideout/files/surgery.lua")
local player,item,frame=10,20,0
local health={hp=1,max_hp=4}
local slot={uses_remaining=1}
local kind,held,alive,open,negative,curseMaximum,hook,failHook
local used,cleanses=0,0
function GameGetFrameNum() return frame end
function GameIsInventoryOpen() return open end
function EntityHasTag(id,tag) return id==item and tag=="noita_hideout_"..kind end
function EntityGetIsAlive(id) return id==player and alive or id==item and held==item end
NHNative={held=function(p) assert(p==player); return held end}
function EntityGetFirstComponentIncludingDisabled(id,component,tag)
    if component=="DamageModelComponent" then assert(id==player); return health end
    if component=="ItemComponent" then assert(id==item); return slot end
    assert(id==player and component=="LuaComponent" and tag=="noita_hideout_surgery_damage")
    return hook
end
function EntityGetFirstComponent(id,component,tag)
    local result=EntityGetFirstComponentIncludingDisabled(id,component,tag)
    return result and result.enabled and result or nil
end
function EntityAddComponent2(id,component,data)
    assert(id==player and component=="LuaComponent" and not hook and data.execute_every_n_frame==-1)
    if failHook then return nil end
    data.enabled=true
    hook=data
    return hook
end
function EntityRemoveComponent(id,component) assert(id==player and component==hook); hook=nil end
function ComponentGetValue2(component,key) return component[key] end
function ComponentSetValue2(component,key,value) component[key]=value end
function GetUpdatedEntityID() return player end
function GetUpdatedComponentID() return hook end
function EntitySetComponentIsEnabled(id,component,enabled)
    assert(id==player and component==hook)
    hook.enabled=enabled
end
function GameKillInventoryItem(p,id)
    assert(p==player and id==item and held==item and not hook)
    used=used+1
    held=nil
end
NHSurgeryCleanse={
    has=function(p) assert(p==player); return negative end,
    cleanse=function(p)
        assert(p==player)
        if not negative then return false end
        cleanses=cleanses+1
        negative=false
        if curseMaximum then health.max_hp=curseMaximum end
        return true
    end,
}
local function setup(id)
    cast.reset()
    kind,held,alive,open,negative,curseMaximum,failHook=id,item,true,false,false,nil,false
    health.hp,health.max_hp,slot.uses_remaining=1,40,1
    used,cleanses=0,0
end
local function hit(amount)
    dofile(hook.script_damage_received)
    damage_received(amount,"damage",0,false,0)
end
local function assertInterrupted(current)
    assert(cast.update(current)=="interrupted" and not cast.view() and not hook)
    assert(not cast.update(current) and used==0 and cleanses==0)
end

for _,tier in ipairs({{"field_surgery_kit",180,.2},{"tactical_surgery_kit",240,.35},{"advanced_surgery_kit",300,.5}}) do
    setup(tier[1])
    assert(not cast.start(player,nil) and not cast.start(player,999))
    assert(cast.start(player,item) and hook)
    local start=frame
    hit(0); hit(-4) -- Absorbed hits and healing do not interrupt.
    assert(not cast.update(player) and cast.view().elapsed==0)
    frame=start+tier[2]-1
    assert(not cast.update(player) and cast.view().total==tier[2] and cast.view().elapsed==tier[2]-1)
    assert(cast.start(player,item) and not cast.update(player) and cast.view().elapsed==tier[2]-1)
    frame=frame+1
    assert(cast.update(player)=="completed" and not cast.view() and not hook)
    assert(used==1 and health.hp==1+40*tier[3] and not cast.update(player))
end

setup("field_surgery_kit")
negative=true
assert(cast.start(player,item))
frame=frame+180
hit(1)
health.hp=health.hp+3 -- Damage followed by a greater heal in the last frame still cancels.
assertInterrupted(player)
assert(negative and health.hp==4)
assert(cast.start(player,item))
health.hp=3 -- Direct HP loss that did not send a damage message.
assertInterrupted(player)
assert(cast.start(player,item)); held=nil; assertInterrupted(player)
held=item
assert(cast.start(player,item)); open=true; assertInterrupted(player)
open=false
assert(cast.start(player,item)); assertInterrupted(nil) -- Polymorph switched player entities.
assert(cast.start(player,item)); health.hp=0; assertInterrupted(player)
health.hp=3
assert(cast.start(player,item)); frame=frame-1; assertInterrupted(player)
slot.uses_remaining=0
assert(cast.start(player,item) and not cast.view() and used==0)
slot.uses_remaining=1
assert(cast.start(player,item)); slot.uses_remaining=0; frame=frame+180; assertInterrupted(player)
assert(negative and health.hp==3)

setup("advanced_surgery_kit")
health.hp=health.max_hp
local handled,reason=cast.start(player,item)
assert(handled and reason=="unneeded" and not hook and used==0)
negative=true
assert(cast.start(player,item)); frame=frame+300
assert(cast.update(player)=="completed" and not negative and cleanses==1 and used==1 and health.hp==40)
setup("advanced_surgery_kit")
health.hp,health.max_hp,negative,curseMaximum=2,3,true,8
assert(cast.start(player,item)); frame=frame+300
assert(cast.update(player)=="completed" and health.hp==6 and cleanses==1 and used==1)
setup("tactical_surgery_kit")
health.hp=39; assert(cast.start(player,item)); frame=frame+240
assert(cast.update(player)=="completed" and health.hp==40 and used==1)
setup("field_surgery_kit")
assert(cast.start(player,item)); health.hp=40; frame=frame+180
assert(cast.update(player)=="unneeded" and used==0 and not hook)

setup("field_surgery_kit")
health.hp=20
assert(cast.start(player,item))
health.hp,health.max_hp=10,20 -- Hearty rescales HP without dealing damage.
frame=frame+1
assert(not cast.update(player) and cast.view().elapsed==1)
hit(0.1)
assertInterrupted(player)

setup("tactical_surgery_kit")
failHook=true
handled,reason=cast.start(player,item)
assert(handled and reason=="interrupted" and not cast.view() and used==0)
failHook=false
assert(cast.start(player,item))
local restored=dofile("mods/noita_hideout/files/surgery.lua") -- World reloaded during a cast.
restored.reset(player)
assert(not hook and not restored.view() and not restored.update(player) and used==0)
assert(restored.start(player,item) and hook)
restored.reset()
assert(not hook and not restored.view() and used==0)
print("Surgery: three durations and percentages, damage, clean interrupt, charge handling, health cap and reload passed.")
