local files="mods/noita_hideout/files/"
local targets=dofile_once(files.."field_targets.lua")
local freeze=dofile_once(files.."stasis.lua")
local M={duration=1800}
local fieldTag,still="nh_hourglass_field","nh_hourglass_still"
local clock="nh_hourglass_clock"
M.release,M.checkTarget=freeze.release,freeze.checkTarget

function M.activate(player,pay)
    if not player or player==0 or not EntityGetIsAlive(player) or not EntityHasTag(player,"player_unit")
        or not dofile_once(files.."ew.lua").localBody(player) then return false,"Item unavailable." end
    local now=GameGetFrameNum()
    local cast=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_hourglass_cast")
    if cast and ComponentGetValue2(cast,"value_int")>now then return false,"Field already active." end
    for _,field in ipairs(EntityGetWithTag(fieldTag) or {}) do
        local c=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent",clock)
        if c and ComponentGetValue2(c,"value_int")>now then return false,"Field already active." end
    end
    local x,y=EntityGetTransform(player)
    local field=EntityLoad(files.."hourglass_field.xml",x,y)
    if not field or field==0 then return false,"Item unavailable." end
    local c=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent",clock)
    if not c then EntityKill(field); return false,"Item unavailable." end
    -- The fixed field may stream out if its caster teleports. Keep its paid
    -- deadline on that player so another copy cannot start a second field.
    local existing=cast
    cast=cast or EntityAddComponent2(player,"VariableStorageComponent",{_tags="nh_hourglass_cast"})
    if not cast or cast==0 then EntityKill(field); return false,"Item unavailable." end
    local _,_,width=GameGetCameraBounds()
    local radius=math.max(1,(width or 420)*0.5)
    if not freeze.source(field,"hourglass",now+M.duration,radius) then
        if not existing then EntityRemoveComponent(player,cast) end
        EntityKill(field)
        return false,"Item unavailable."
    end
    if pay and not pay() then
        if not existing then EntityRemoveComponent(player,cast) end
        EntityKill(field)
        return false,"Item unavailable."
    end
    ComponentSetValue2(c,"value_int",now+M.duration)
    ComponentSetValue2(c,"value_float",radius)
    ComponentSetValue2(cast,"value_int",now+M.duration)
    M.tick(field,true)
    return true
end

function M.tick(field,fresh)
    local c=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent",clock)
    if not c then EntityKill(field); return end
    local finish=ComponentGetValue2(c,"value_int")
    local x,y=EntityGetTransform(field)
    local radius=ComponentGetValue2(c,"value_float")
    local frame=GameGetFrameNum()
    freeze.source(field,"hourglass",finish,radius)
    if frame>=finish then
        freeze.cancelSource(field)
        EntityKill(field)
        return
    end
    local broad=fresh or frame%8==0
    local nearby
    if broad then nearby=EntityGetInRadius(x,y,radius)
    else nearby=EntityGetInRadiusWithTag(x,y,radius,"projectile") end
    local ew=ModIsEnabled("quant.ew")
    for _,e in ipairs(nearby or {}) do
        if (not broad or EntityHasTag(e,"projectile") or EntityHasTag(e,"mortal")
            or EntityHasTag(e,"enemy") or EntityGetFirstComponent(e,"ProjectileComponent")
            or EntityGetFirstComponent(e,"ItemComponent") or EntityGetFirstComponent(e,"PhysicsThrowableComponent") or freeze.writableBody(e))
            and targets.canAffect(e,ew) then freeze.acquire(e,field) end
    end
    for quadrant=0,3 do
        local a=(frame%12+quadrant*12)*math.pi/24
        GameCreateCosmeticParticle("spark_white",x+radius*math.cos(a),y+radius*math.sin(a),1,
            0,0,0,0.22,0.25,true,true,false,false,0,0)
    end
end

return M
