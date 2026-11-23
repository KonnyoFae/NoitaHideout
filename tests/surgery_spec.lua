NHSurgeryKits=dofile("mods/noita_hideout/files/surgery_kits.lua")
local cast=dofile("mods/noita_hideout/files/surgery.lua")
local player,item,frame=10,20,0
local health={hp=1,max_hp=4}
local slot={uses_remaining=1}
local carried_parent,slot_x,slot_y
local kind,held,alive,open,negative,curseMaximum,hook
local used,cleanses=0,0
function GameGetFrameNum() return frame end
function GameIsInventoryOpen() return open end
function EntityHasTag(id,tag) return id==item and tag=="noita_hideout_"..kind end
function EntityGetIsAlive(id) return id==player and alive or id==item and (held==item or carried_parent~=nil) end
function EntityGetParent(id) assert(id==item); return carried_parent or 0 end
function EntityGetRootEntity(id) return carried_parent and player or id end
NHNative={held=function(p) assert(p==player); return held end}
function EntityGetFirstComponentIncludingDisabled(id,component,tag)
    if component=="DamageModelComponent" then assert(id==player); return health end
    if component=="ItemComponent" then assert(id==item); return slot end
    assert(id==player and component=="LuaComponent" and tag=="noita_hideout_surgery_damage")
    return hook
end
function EntityRemoveComponent(id,component) assert(id==player and component==hook); hook=nil end
function ComponentGetValue2(component,key)
    if key=="inventory_slot" then assert(component==slot);return slot_x,slot_y end
    return component[key]
end
function ComponentSetValue2(component,key,value) component[key]=value end
function GameKillInventoryItem(p,id)
    assert(p==player and id==item and (held==item or carried_parent) and not hook)
    used=used+1
    if held==id then held=nil end
    carried_parent=nil
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
    kind,held,alive,open,negative,curseMaximum=id,item,true,false,false,nil
    health.hp,health.max_hp,slot.uses_remaining=1,40,1
    used,cleanses=0,0
    carried_parent,slot_x,slot_y=nil,nil,nil
end
local function assertInterrupted(current)
    assert(cast.update(current)=="interrupted" and not cast.view() and not hook)
    assert(not cast.update(current) and used==0 and cleanses==0)
end

for _,tier in ipairs({{"field_surgery_kit",180,.2},{"tactical_surgery_kit",240,.35},{"advanced_surgery_kit",300,.5}}) do
    setup(tier[1])
    assert(not cast.start(player,nil) and not cast.start(player,999))
    health.hp,negative=20,true
    assert(cast.start(player,item) and cast.view())
    local start=frame
    for elapsed=1,tier[2]-1 do
        frame=start+elapsed
        if elapsed%15==0 then health.hp=health.hp-0.25 end
        assert(not cast.update(player) and cast.view().elapsed==elapsed and negative and used==0)
    end
    assert(not cast.update(player) and cast.view().total==tier[2] and cast.view().elapsed==tier[2]-1)
    assert(cast.start(player,item) and not cast.update(player) and cast.view().elapsed==tier[2]-1)
    frame=frame+1
    health.hp=health.hp-4 -- A direct hit on the completion frame.
    local beforeHeal=health.hp
    assert(cast.update(player)=="completed" and not cast.view() and not hook)
    assert(used==1 and cleanses==1 and not negative and health.hp==beforeHeal+40*tier[3] and not cast.update(player))
end

setup("field_surgery_kit")
negative=true
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
frame=frame+179
assert(cast.update(player)=="completed" and health.hp==14)

setup("tactical_surgery_kit")
assert(cast.start(player,item))
local restored=dofile("mods/noita_hideout/files/surgery.lua") -- World reloaded during a cast.
hook={} -- A player saved by a version that used a damage listener.
dofile("mods/noita_hideout/files/surgery_damage.lua")
damage_received(1)
restored.reset(player)
assert(not hook and not restored.view() and not restored.update(player) and used==0)
assert(restored.start(player,item) and restored.view())
restored.reset()
assert(not hook and not restored.view() and used==0)
print("Surgery: three durations and percentages, damage, clean interrupt, charge handling, health cap and reload passed.")

-- A right-clicked physical kit stays bound to the original inventory slot even
-- when a different item is held. Moving it halfway through cancels the cast.
setup("field_surgery_kit")
open,negative,held=true,true,81
local location={parent=30,xslot=2,yslot=0}
carried_parent,slot_x,slot_y=location.parent,location.xslot,location.yslot
assert(cast.start(player,item,location) and cast.view())
slot_x=1
frame=frame+80
assertInterrupted(player)
assert(held==81 and carried_parent and negative and health.hp==1)
slot_x=2
assert(cast.start(player,item,location) and cast.view())
frame=frame+180
assert(cast.update(player)=="completed" and open and held==81 and not carried_parent)
assert(used==1 and cleanses==1 and not negative and health.hp==9)

-- Stored surgery keeps the record until payment succeeds on the final frame.
setup("tactical_surgery_kit")
open,negative,held=true,true,81
local present,accept,attempts,quantity=true,false,0,1
local function available() return present and quantity>0 end
local function pay()
    attempts=attempts+1
    assert(not hook and negative and health.hp==1)
    if not accept then return false end
    quantity=quantity-1
    return true
end
assert(cast.begin(player,kind,available,pay) and cast.view())
frame=frame+239
assert(not cast.update(player) and attempts==0 and cast.view().elapsed==239)
frame=frame+1
assertInterrupted(player)
assert(attempts==1 and quantity==1 and negative and health.hp==1)
assert(cast.begin(player,kind,available,pay) and cast.view())
present=false
frame=frame+1
assertInterrupted(player)
assert(attempts==1 and quantity==1 and negative and health.hp==1)
present,accept=true,true
assert(cast.begin(player,kind,available,pay) and cast.view())
frame=frame+240
assert(cast.update(player)=="completed" and not cast.update(player))
assert(attempts==2 and quantity==0 and cleanses==1 and not negative and health.hp==15 and used==0 and held==81)
print("Inventory surgery: open inventory, exact slot, lost source, failed payment and single successful treatment.")
