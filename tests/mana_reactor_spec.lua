local files="mods/noita_hideout/files/"
local now,alarms,notices,blasts=100,0,0,{}
local function entity(tag,x,y)
    return {tags={[tag]=true},x=x or 0,y=y or 0,components={},children={}}
end
function EntityAddComponent2(e,kind,c)
    c.kind=kind
    if kind=="VariableStorageComponent" then
        c.value_int=c.value_int or 0; c.value_float=c.value_float or 0; c.value_bool=c.value_bool or false
    end
    e.components[#e.components+1]=c
    return c
end
function EntityGetFirstComponentIncludingDisabled(e,kind,tag)
    for _,c in ipairs(e.components) do if c.kind==kind and (not tag or c._tags==tag) then return c end end
end
local function drop(list,value)
    for i,v in ipairs(list) do if v==value then table.remove(list,i); return end end
end
function EntityRemoveComponent(e,c) drop(e.components,c) end
function EntityAddChild(p,c) p.children[#p.children+1]=c; c.parent=p end
function EntityGetAllChildren(e,tag)
    local t={}
    for _,child in ipairs(e.children) do if not tag or child.tags[tag] then t[#t+1]=child end end
    return t
end
function EntityRemoveFromParent(e) drop(e.parent.children,e); e.parent=nil end
function EntityGetRootEntity(e) return e.parent and EntityGetRootEntity(e.parent) or e end
function EntityGetParent(e) return e.parent or 0 end
function EntityGetTransform(e) return e.x,e.y end
function EntityGetIsAlive(e) return not e.dead end
function EntityKill(e) e.dead=true end
function EntityHasTag(e,tag) return e.tags[tag] end
function EntityAddTag(e,tag) e.tags[tag]=true end
function EntityRemoveTag(e,tag) e.tags[tag]=nil end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function GameGetFrameNum() return now end
function GamePrint(s) assert(s=="$nh_hideout_reactor_critical"); notices=notices+1 end
function GameTextGetTranslatedOrNot(s) return s end
function GlobalsSetValue() end
function EntityLoad(path,x,y)
    if path==files.."mana_reactor_effect.xml" then
        local e=entity("nh_reactor_effect",x,y)
        EntityAddComponent2(e,"UIIconComponent",{name="$nh_hideout_reactor_direct"})
        return e
    end
    assert(path==files.."mana_reactor_blast.xml")
    local e=entity("nh_reactor_meltdown",x,y)
    EntityAddComponent2(e,"ProjectileComponent",{})
    blasts[#blasts+1]=e
    return e
end
local p=entity("player_unit",20,40)
function GetUpdatedEntityID() return p end
NHEW={localBody=function(player) return not (player.tags.ew_client or player.tags.nh_ew_waiting) end}
local rescue,rewind=false,false
local modules={}
local nativeDofile=dofile
function dofile(path)
    if path==files.."rescue.lua" then return {
        lifePriority=function() end,
        intercept=function(e,dm) if rescue then e.x,e.y=1000,2000; dm.hp=dm.max_hp/2 end end,
    } end
    return nativeDofile(path)
end
function dofile_once(path)
    if path==files.."affinity.lua" or path==files.."companions.lua" then return end
    if path==files.."ew.lua" then return NHEW end
    if path==files.."reactor_alarm.lua" then return {play=function(x,y) assert(x==p.x and y==p.y); alarms=alarms+1 end} end
    if path==files.."rewind_watch.lua" then return {blockHit=function() return rewind end} end
    modules[path]=modules[path] or dofile(path)
    return modules[path]
end

local dm=EntityAddComponent2(p,"DamageModelComponent",{hp=4,max_hp=4})
local inv=EntityAddComponent2(p,"Inventory2Component",{})
local wand=entity("wand")
EntityAddChild(p,wand)
inv.mActiveItem=wand
local ability=EntityAddComponent2(wand,"AbilityComponent",{mana=12,mana_max=100,use_gun_script=true})
local R=dofile_once(files.."mana_reactor.lua")
dofile(files.."shield_damage.lua")
local function hit(dmg)
    local actual=damage_about_to_be_received(dmg,p.x,p.y,0,0)
    dm.hp=dm.hp-actual
    damage_received(actual)
end
local function state() return EntityGetFirstComponentIncludingDisabled(p,"VariableStorageComponent","nh_reactor_active") end
local function fx() return (EntityGetAllChildren(p,"nh_reactor_effect") or {})[1] end
assert(not R.activate(p,function() return false end) and not state() and not fx() and alarms==0 and notices==0)
assert(R.activate(p) and alarms==1 and notices==1 and state().value_bool)
assert(state().value_int==5500 and R.active(p) and not R.activate(p))
local hook=EntityGetFirstComponentIncludingDisabled(p,"LuaComponent","nh_shield_damage")
assert(hook.script_damage_received==files.."shield_damage.lua" and hook.script_damage_about_to_be_received==hook.script_damage_received)
for t=106,160,6 do now=t; R.update(fx()) end
assert(math.abs(ability.mana-27)<0.00001)
modules[files.."mana_reactor.lua"]=nil
R=dofile_once(files.."mana_reactor.lua")
R.update(fx())
assert(alarms==1 and ability.mana==27 and state().value_int==5500)
wand.tags.nh_firearm=true; now=166; R.update(fx()); assert(ability.mana==27)
wand.tags.nh_firearm=nil
local lock=EntityAddComponent2(wand,"VariableStorageComponent",{_tags="nh_ew_deposit_lock"})
now=172; R.update(fx()); assert(ability.mana==27)
EntityRemoveComponent(wand,lock)
ability.mana=99.9; now=178; R.update(fx()); assert(ability.mana==100)
p.tags.nh_rewind_armed=true; rewind=true; hit(42); rewind=false; p.tags.nh_rewind_armed=nil
hit(0); assert(#blasts==0 and alarms==1 and dm.hp==4)

local meter=EntityAddComponent2(p,"VariableStorageComponent",{_tags="nh_equipped_shield",name="shield_basic",value_int=60000,value_string="qa"})
EntityAddComponent2(p,"VariableStorageComponent",{_tags="nh_shield_clock"})
now=184; R.update(fx()); assert(not state().value_bool)
hit(3); assert(#blasts==0 and state().value_bool and alarms==2 and meter.value_int==0 and dm.hp>3)
-- Recharge and break again between two scheduled status updates.
meter.value_int=1; hit(0.01); assert(alarms==3 and #blasts==0)
rescue=true; hit(15)
assert(#blasts==1 and blasts[1].x==20 and blasts[1].y==40 and p.x==1000 and not R.active(p) and not state() and not fx())
assert(EntityGetFirstComponentIncludingDisabled(blasts[1],"ProjectileComponent").mWhoShot==p)
local targets=dofile(files.."field_targets.lua")
assert(not targets.canAffect(blasts[1],false))
hit(0.1); assert(#blasts==1)

-- Natural timeout is strict even when the six-frame housekeeping hasn't run.
assert(R.activate(p)); now=state().value_int-1; assert(R.active(p))
now=now+1; assert(not R.active(p)); hit(0.1); assert(#blasts==1 and not state() and not fx())
-- A reloaded effect wakes on its first frame. Ordinary updates stay six
-- frames apart, including when that cadence does not divide the deadline.
assert(R.activate(p))
local deadline,child=state().value_int,fx()
local function reloadTick()
    local vm=setmetatable({GetUpdatedEntityID=function() return child end},{__index=_G})
    return setfenv(assert(loadfile(files.."mana_reactor_tick.lua")),vm)
end
local icon=EntityGetFirstComponentIncludingDisabled(child,"UIIconComponent")
local legacy=files.."items/mana_reactor_icon.png"
icon.icon_sprite_file=legacy
local tick=reloadTick()
now=deadline-15; tick(); assert(state().value_float==R.duration-15)
assert(icon.icon_sprite_file==files.."items/mana_reactor_status.png")
icon.icon_sprite_file=legacy
now=deadline-14; tick(); assert(state().value_float==R.duration-15)
now=deadline-9; tick(); assert(state().value_float==R.duration-9 and icon.icon_sprite_file==legacy)
icon.icon_sprite_file="mods/custom/current_reactor.png"
now=deadline-5; tick=reloadTick(); tick(); assert(state().value_float==R.duration-5)
assert(icon.icon_sprite_file=="mods/custom/current_reactor.png")
now=deadline-1; tick(); assert(state().value_float==R.duration-5 and R.active(p))
now=deadline; tick(); assert(not p.tags.nh_reactor_active and not state() and not fx() and #blasts==1)
assert(R.activate(p)); p.tags.nh_ew_waiting=true; assert(not R.active(p)); R.update(fx())
assert(not state() and not fx() and not R.activate(p))
p.tags.nh_ew_waiting=nil; meter.value_int=1; assert(R.activate(p)); rescue=false
hit(100); assert(dm.hp<=0 and not state() and #blasts==1)
print("Mana reactor: 90-second clock, held-wand regeneration, shield transitions, immunity, rescue and single meltdown passed.")
