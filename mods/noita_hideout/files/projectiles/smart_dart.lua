local files="mods/noita_hideout/files/"
local factions=dofile_once(files.."companions/targets.lua")
local authority=dofile_once(files.."field_targets.lua")
local status=dofile_once(files.."dart_status.lua")
local M={}

local function hostile(owner,e)
    if not EntityGetIsAlive(e) or EntityHasTag(e,"player_unit") or EntityHasTag(e,"polymorphed_player")
        or EntityHasTag(e,"ew_peer") or EntityHasTag(e,"ew_client") or EntityHasTag(e,"ew_notplayer")
        or EntityHasTag(e,"nh_ew_waiting") or not factions.hostile(owner,e) then return false end
    local model=EntityGetFirstComponent(e,"DamageModelComponent")
    return model and ComponentGetValue2(model,"hp")>0
end

-- Clip the actual travelled segment to each enabled hitbox in world space.
local function axis(start,delta,low,high)
    if delta==0 then
        if start>=low and start<=high then return -math.huge,math.huge end
        return math.huge,-math.huge
    end
    local a,b=(low-start)/delta,(high-start)/delta
    return math.min(a,b),math.max(a,b)
end

local function contact(e,x,y,dx,dy)
    local tx,ty=EntityGetTransform(e)
    local nearest
    for _,box in ipairs(EntityGetComponent(e,"HitboxComponent") or {}) do
        local ox,oy=ComponentGetValue2(box,"offset")
        local cx,cy=tx+ox,ty+oy
        local x0,x1=axis(x,dx,cx+ComponentGetValue2(box,"aabb_min_x"),cx+ComponentGetValue2(box,"aabb_max_x"))
        local y0,y1=axis(y,dy,cy+ComponentGetValue2(box,"aabb_min_y"),cy+ComponentGetValue2(box,"aabb_max_y"))
        local entry=math.max(0,x0,y0)
        if entry<=math.min(1,x1,y1) and (not nearest or entry<nearest) then nearest=entry end
    end
    return nearest
end

local function collide(dart,state,x,y,owner,rotation)
    local dx,dy=x-state.x,y-state.y
    local len2=dx*dx+dy*dy
    local wall,wx,wy=RaytraceSurfaces(state.x,state.y,x,y)
    local first=wall and (len2==0 and 0 or ((wx-state.x)*dx+(wy-state.y)*dy)/len2) or math.huge
    local hit
    local candidates=EntityGetInRadiusWithTag((x+state.x)*0.5,(y+state.y)*0.5,32+math.sqrt(len2)*0.5,"homing_target") or {}
    -- A very large locked target can intersect the segment outside the local search radius.
    if state.target then candidates[#candidates+1]=state.target end
    for _,e in ipairs(candidates) do
        if hostile(owner,e) then
            local t=contact(e,state.x,state.y,dx,dy)
            if t and (t<first or (hit and t==first and e<hit)) then first,hit=t,e end
        end
    end
    if not hit and not wall then return false end
    if hit and authority.canAffect(hit,ModIsEnabled("quant.ew")) then
        local heading=len2>0 and math.atan2(dy,dx) or rotation
        status.attach(hit,state.kind,state.x+dx*first,state.y+dy*first,heading)
    end
    EntityKill(dart)
    return true
end

local function acquire(owner,kind,x,y,ux,uy)
    local best,score,treated
    for _,e in ipairs(EntityGetInRadiusWithTag(x,y,120,"homing_target") or {}) do
        if hostile(owner,e) then
            local tx,ty=EntityGetFirstHitboxCenter(e)
            if tx then
                local dx,dy=tx-x,ty-y
                local distance=math.max(0.01,math.sqrt(dx*dx+dy*dy))
                local alignment=(ux*dx+uy*dy)/distance
                if alignment>0.35 then
                    local has=status.has(e,kind) and true or false
                    local rank=distance+100*(1-alignment)
                    if (not best or (treated and not has) or (treated==has and rank<score))
                        and not RaytraceSurfaces(x,y,tx,ty) then best,score,treated=e,rank,has end
                end
            end
        end
    end
    return best
end

function M.update(dart,state)
    local x,y,rotation=EntityGetTransform(dart)
    local shot=EntityGetFirstComponent(dart,"ProjectileComponent")
    local velocity=EntityGetFirstComponent(dart,"VelocityComponent")
    if not shot or not velocity then return end
    local owner=ComponentGetValue2(shot,"mWhoShot")
    if owner==0 then state.x,state.y=x,y;return end
    if not EntityGetIsAlive(owner) then EntityKill(dart);return end
    state.kind=state.kind or (EntityHasTag(dart,"nh_sedative_dart") and "sedative" or "pheromone")
    if not state.x then state.x,state.y=x,y end
    if collide(dart,state,x,y,owner,rotation) then return end
    state.x,state.y=x,y

    local vx,vy=ComponentGetValue2(velocity,"mVelocity")
    local speed=math.sqrt(vx*vx+vy*vy)
    if speed<1 then return end
    local now=GameGetFrameNum()
    if not state.nextScan or now>=state.nextScan then
        state.target=acquire(owner,state.kind,x,y,vx/speed,vy/speed)
        state.nextScan=now+6
    end
    if not state.target or not hostile(owner,state.target) then state.target=nil;return end
    local tx,ty=EntityGetFirstHitboxCenter(state.target)
    if not tx then return end
    local dx,dy=tx-x,ty-y
    local turn=math.atan2(vx*dy-vy*dx,vx*dx+vy*dy)
    local angle=math.atan2(vy,vx)+math.max(-0.20,math.min(0.20,turn))
    ComponentSetValue2(velocity,"mVelocity",math.cos(angle)*speed,math.sin(angle)*speed)
end

return M
