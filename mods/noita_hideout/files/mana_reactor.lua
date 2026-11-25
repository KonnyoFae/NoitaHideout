local files="mods/noita_hideout/files/"
local tag,effectTag="nh_reactor_active","nh_reactor_effect"
local R={duration=90*60}

local function clock(player)
    return EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
end

local function timeLeft(record,frame)
    return ComponentGetValue2(record,"value_int")-frame
end

local function body(player)
    return player and player~=0 and EntityGetIsAlive(player) and EntityHasTag(player,"player_unit")
        and not EntityHasTag(player,"polymorphed_player") and dofile_once(files.."ew.lua").localBody(player)
end

function R.active(player,frame)
    if not player or player==0 or not EntityHasTag(player,tag) or not body(player) then return false end
    local record=clock(player)
    local left=record and timeLeft(record,frame or GameGetFrameNum())
    return left~=nil and left>0 and left<=R.duration
end

local function effect(player)
    return (EntityGetAllChildren(player,effectTag) or {})[1]
end

function R.cancel(player)
    EntityRemoveTag(player,tag)
    local record=clock(player)
    if record then EntityRemoveComponent(player,record) end
    local child=effect(player)
    if child then EntityRemoveFromParent(child); EntityKill(child) end
end

local function charged(player)
    local meter=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_equipped_shield")
    return meter and ComponentGetValue2(meter,"value_int")>0 or false
end

local function setCritical(player,record,critical)
    if ComponentGetValue2(record,"value_bool")==critical then return end
    ComponentSetValue2(record,"value_bool",critical)
    local child=effect(player)
    local icon=child and EntityGetFirstComponentIncludingDisabled(child,"UIIconComponent")
    if icon then ComponentSetValue2(icon,"name",critical and "$nh_hideout_reactor_critical" or "$nh_hideout_reactor_direct") end
    if critical then
        local x,y=EntityGetTransform(player)
        dofile_once(files.."reactor_alarm.lua").play(x,y)
        GamePrint(GameTextGetTranslatedOrNot("$nh_hideout_reactor_critical"))
    end
end

function R.activate(player,pay)
    if not body(player) then return false,"Item unavailable." end
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not dm or ComponentGetValue2(dm,"hp")<=0 then return false,"Item unavailable." end
    local now=GameGetFrameNum()
    if R.active(player,now) then return false,"Reactor already active." end
    if clock(player) or effect(player) then R.cancel(player) end
    if not dofile_once(files.."shield_runtime.lua").ensureDamageHook(player) then return false,"Item unavailable." end
    local x,y=EntityGetTransform(player)
    local child=EntityLoad(files.."mana_reactor_effect.xml",x,y)
    if not child or child==0 then return false,"Item unavailable." end
    local record=EntityAddComponent2(player,"VariableStorageComponent",{_tags=tag,value_int=now+R.duration})
    if not record or record==0 then EntityKill(child); return false,"Item unavailable." end
    if pay and not pay() then
        EntityRemoveComponent(player,record)
        EntityKill(child)
        return false,"Item unavailable."
    end
    EntityAddChild(player,child)
    EntityAddTag(player,tag)
    setCritical(player,record,not charged(player))
    return true
end

local function rechargeWand(player,frames)
    local inv=EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    local wand=inv and ComponentGetValue2(inv,"mActiveItem")
    if not wand or wand==0 or not EntityGetIsAlive(wand) or EntityGetRootEntity(wand)~=player
        or not EntityHasTag(wand,"wand") or EntityHasTag(wand,"nh_firearm")
        or EntityGetFirstComponentIncludingDisabled(wand,"VariableStorageComponent","nh_ew_deposit_lock") then return end
    local ability=EntityGetFirstComponentIncludingDisabled(wand,"AbilityComponent")
    if not ability or not ComponentGetValue2(ability,"use_gun_script") then return end
    local mana,max=ComponentGetValue2(ability,"mana"),ComponentGetValue2(ability,"mana_max")
    if mana<max then ComponentSetValue2(ability,"mana",math.min(max,mana+max*0.15*frames/60)) end
end

function R.update(child,frame)
    local player=EntityGetParent(child)
    if not player or player==0 then EntityKill(child); return end
    local record=clock(player)
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not record or not body(player) or not dm or ComponentGetValue2(dm,"hp")<=0 then R.cancel(player); return end
    frame=frame or GameGetFrameNum()
    local left=timeLeft(record,frame)
    if left<=0 or left>R.duration then R.cancel(player); return end
    setCritical(player,record,not charged(player))
    -- Pay for the current six-frame update only. An unloaded body cannot bank
    -- mana to spend later, and re-entering on the same frame cannot pay twice.
    local elapsed=R.duration-left
    local frames=math.min(6,elapsed-ComponentGetValue2(record,"value_float"))
    if frames>0 then
        ComponentSetValue2(record,"value_float",elapsed)
        rechargeWand(player,frames)
    end
    return frame+math.min(6,left)
end

-- Called with the settled charge values before death rescue moves the body.
-- Even a lethal spill from a charged shield is a shield-breaking hit.
function R.hit(player,before,after)
    if not R.active(player) then R.cancel(player); return end
    local record=clock(player)
    if before>0 then
        setCritical(player,record,false)
        if after<=0 then setCritical(player,record,true) end
        return
    end
    local x,y=EntityGetTransform(player)
    R.cancel(player)
    local blast=EntityLoad(files.."mana_reactor_blast.xml",x,y)
    local shot=blast and blast~=0 and EntityGetFirstComponentIncludingDisabled(blast,"ProjectileComponent")
    if shot then ComponentSetValue2(shot,"mWhoShot",player) end
end

return R
