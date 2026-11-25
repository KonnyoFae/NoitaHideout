local root="mods/noita_hideout/files/"
local targets=dofile(root.."field_targets.lua")
local parry=dofile(root.."katana_parry.lua")
local M={}

function M.hostile(player,entity)
    if entity==player or not EntityGetIsAlive(entity) or not EntityHasTag(entity,"enemy")
        or EntityHasTag(entity,"nh_reinforcement") or EntityHasTag(entity,"noita_hideout_companion")
        or EntityHasTag(entity,"nh_deployed_turret") or EntityHasTag(entity,"nh_decoy")
        or EntityGetHerdRelationSafe(player,entity)>=40 or GameGetGameEffectCount(entity,"CHARM")>0 then return false end
    return targets.canAffect(entity,ModIsEnabled("quant.ew"))
end

function M.distanceToSegment(px,py,x1,y1,x2,y2)
    local dx,dy=x2-x1,y2-y1
    local square=dx*dx+dy*dy
    local t=square>0 and math.max(0,math.min(1,((px-x1)*dx+(py-y1)*dy)/square)) or 0
    local x,y=x1+dx*t,y1+dy*t
    return math.sqrt((px-x)^2+(py-y)^2),x,y
end

local function closestSegments(ax,ay,bx,by,cx,cy,dx,dy)
    local rx,ry,sx,sy=bx-ax,by-ay,dx-cx,dy-cy
    local denominator=rx*sy-ry*sx
    if math.abs(denominator)>0.000000001 then
        local qx,qy=cx-ax,cy-ay
        local t,u=(qx*sy-qy*sx)/denominator,(qx*ry-qy*rx)/denominator
        if t>=0 and t<=1 and u>=0 and u<=1 then
            local x,y=ax+t*rx,ay+t*ry
            return 0,x,y,x,y
        end
    end
    local best,px,py,hx,hy,along
    local function consider(distance,x,y,tx,ty)
        local travel=(x-ax)^2+(y-ay)^2
        if not best or distance<best-0.000000001 or (math.abs(distance-best)<0.000000001 and travel<along) then
            best,px,py,hx,hy,along=distance,x,y,tx,ty,travel
        end
    end
    local distance,x,y=M.distanceToSegment(cx,cy,ax,ay,bx,by)
    consider(distance,x,y,cx,cy)
    distance,x,y=M.distanceToSegment(dx,dy,ax,ay,bx,by)
    consider(distance,x,y,dx,dy)
    distance,x,y=M.distanceToSegment(ax,ay,cx,cy,dx,dy)
    consider(distance,ax,ay,x,y)
    distance,x,y=M.distanceToSegment(bx,by,cx,cy,dx,dy)
    consider(distance,bx,by,x,y)
    return best,px,py,hx,hy
end

local function closestHitbox(entity,box,a)
    local ex,ey,rotation,scaleX,scaleY=EntityGetTransform(entity)
    rotation,scaleX,scaleY=rotation or 0,scaleX or 1,scaleY or 1
    local minx,maxx=ComponentGetValue2(box,"aabb_min_x"),ComponentGetValue2(box,"aabb_max_x")
    local miny,maxy=ComponentGetValue2(box,"aabb_min_y"),ComponentGetValue2(box,"aabb_max_y")
    if type(minx)~="number" or type(maxx)~="number" or type(miny)~="number" or type(maxy)~="number" then return end
    local ox,oy=ComponentGetValue2(box,"offset")
    minx,maxx,miny,maxy=minx+(ox or 0),maxx+(ox or 0),miny+(oy or 0),maxy+(oy or 0)
    local cosine,sine=math.cos(rotation),math.sin(rotation)
    local function world(x,y)
        x,y=x*scaleX,y*scaleY
        return {ex+x*cosine-y*sine,ey+x*sine+y*cosine}
    end
    -- If the attack begins inside the target, it already touches its volume.
    if math.abs(scaleX)>0.000000001 and math.abs(scaleY)>0.000000001 then
        local dx,dy=a.x1-ex,a.y1-ey
        local lx,ly=(dx*cosine+dy*sine)/scaleX,(-dx*sine+dy*cosine)/scaleY
        if lx>=minx and lx<=maxx and ly>=miny and ly<=maxy then return 0,a.x1,a.y1,a.x1,a.y1 end
    end
    local corners={world(minx,miny),world(maxx,miny),world(maxx,maxy),world(minx,maxy)}
    local best,px,py,hx,hy,along
    for i=1,4 do
        local from,to=corners[i],corners[i%4+1]
        local distance,x,y,tx,ty=closestSegments(a.x1,a.y1,a.x2,a.y2,from[1],from[2],to[1],to[2])
        local travel=(x-a.x1)^2+(y-a.y1)^2
        if not best or distance<best-0.000000001 or (math.abs(distance-best)<0.000000001 and travel<along) then
            best,px,py,hx,hy,along=distance,x,y,tx,ty,travel
        end
    end
    return best,px,py,hx,hy
end

local function contact(entity,a,pointX,pointY)
    local boxes=EntityGetComponentIncludingDisabled(entity,"HitboxComponent") or {}
    for _,box in ipairs(boxes) do
        if ComponentGetIsEnabled(box) then
            local distance,px,py,x,y=closestHitbox(entity,box,a)
            if distance and distance<=a.width/2 and not RaytracePlatforms(a.x1,a.y1,px,py)
                and not RaytracePlatforms(px,py,x,y) then return x,y end
        end
    end
    -- Some native enemies (e.g. custom worm bodies) expose no normal hitbox.
    -- An intentionally disabled hitbox is different and must remain unhittable.
    if #boxes==0 then
        local x,y=pointX,pointY
        if not x then x,y=EntityGetFirstHitboxCenter(entity) end
        if not x then x,y=EntityGetTransform(entity) end
        if x then
            local distance,px,py=M.distanceToSegment(x,y,a.x1,a.y1,a.x2,a.y2)
            if distance<=a.width/2 and not RaytracePlatforms(a.x1,a.y1,px,py)
                and not RaytracePlatforms(px,py,x,y) then return x,y end
        end
    end
end

-- Find first entry into the capsule during one native physics step. This
-- catches a fast bullet before it can pass the blade and hit the player.
local function flightContact(shape,x,y,tx,ty)
    local radius=shape.width/2
    if math.min(x,tx)>math.max(shape.x1,shape.x2)+radius or math.max(x,tx)<math.min(shape.x1,shape.x2)-radius
        or math.min(y,ty)>math.max(shape.y1,shape.y2)+radius or math.max(y,ty)<math.min(shape.y1,shape.y2)-radius then return end
    local distance,_,_,bx,by=closestSegments(shape.x1,shape.y1,shape.x2,shape.y2,x,y,tx,ty)
    if distance>radius then return end
    -- Along the incoming path the distance decreases up to its closest
    -- point. Bisect only on that interval to find the near face of the blade.
    local lo,hi=0,1
    for _=1,12 do
        local t=(lo+hi)/2
        local d=M.distanceToSegment(x+(bx-x)*t,y+(by-y)*t,shape.x1,shape.y1,shape.x2,shape.y2)
        if d<=radius then hi=t else lo=t end
    end
    bx,by=x+(bx-x)*hi,y+(by-y)*hi
    local _,px,py=M.distanceToSegment(bx,by,shape.x1,shape.y1,shape.x2,shape.y2)
    if not RaytracePlatforms(x,y,bx,by) and not RaytracePlatforms(shape.x1,shape.y1,px,py)
        and not RaytracePlatforms(px,py,bx,by) then return bx,by end
end

local function strikeEnemy(player,id,a,nx,ny,shape,oldBlade,newBlade)
    if not M.hostile(player,id) then return false end
    local dm=EntityGetFirstComponentIncludingDisabled(id,"DamageModelComponent")
    if not dm or ComponentGetValue2(dm,"hp")<=0 then return false end
    local x,y=contact(id,shape)
    if not x and oldBlade then x,y=contact(id,oldBlade) end
    if not x and newBlade then x,y=contact(id,newBlade) end
    if not x then return false end
    if a.plunder then dofile_once(root.."katana_rewards.lua").mark(id,player,a.token) end
    EntityInflictDamage(id,a.damage,"DAMAGE_MELEE",a.token,"NORMAL",nx*45,ny*45,player,x,y,1)
    return true
end

local function flightStep(velocity)
    local vx,vy=ComponentGetValue2(velocity,"mVelocity")
    if type(vx)=="number" and type(vy)=="number" and math.abs(vx)<math.huge and math.abs(vy)<math.huge then
        return vx/60,vy/60
    end
end

local function bodyBeforeContact(id,path)
    for _,box in ipairs(EntityGetComponentIncludingDisabled(id,"HitboxComponent") or {}) do
        if ComponentGetIsEnabled(box) then
            local d,hx,hy=closestHitbox(id,box,path)
            if d and d<0.001 and (hx-path.x2)^2+(hy-path.y2)^2>0.01 then return true end
        end
    end
    return false
end

-- The incoming round must be able to reach the blade under its original
-- collision rules. Let native simulation resolve an earlier body hit.
local function blockedFlight(player,id,shot,path)
    if ComponentGetValue2(shot,"collide_with_entities")==false then return false end
    local wanted=ComponentGetValue2(shot,"collide_with_tag") or "hittable"
    local excluded=ComponentGetValue2(shot,"dont_collide_with_tag")
    local skipPlayers=ComponentGetValue2(shot,"never_hit_player")
    local shooter=ComponentGetValue2(shot,"mWhoShot")
    local friendlyFire=ComponentGetValue2(shot,"friendly_fire")
    local herd=not friendlyFire and ComponentGetValue2(shot,"mShooterHerdId")
    local immunity=ComponentGetValue2(shot,"collide_with_shooter_frames") or -1
    local skipShooter=not friendlyFire or immunity<0
    if not skipShooter and immunity>0 then
        local start,remaining=ComponentGetValue2(shot,"mStartingLifetime"),ComponentGetValue2(shot,"lifetime")
        skipShooter=start and remaining and remaining>=0 and start>=remaining and start-remaining<immunity
    end
    local function blocks(body)
        if body==id or (body==shooter and skipShooter) or (excluded and excluded~="" and EntityHasTag(body,excluded))
            or (skipPlayers and (body==player or EntityHasTag(body,"player_unit") or EntityHasTag(body,"ew_client"))) then return false end
        local genome=herd and EntityGetFirstComponentIncludingDisabled(body,"GenomeDataComponent")
        if genome and ComponentGetValue2(genome,"herd_id")==herd then return false end
        return bodyBeforeContact(body,path)
    end
    if (wanted=="hittable" or EntityHasTag(player,wanted)) and blocks(player) then return true end
    local dx,dy=path.x2-path.x1,path.y2-path.y1
    local radius=math.sqrt(dx*dx+dy*dy)/2+128
    for _,body in ipairs(EntityGetInRadiusWithTag((path.x1+path.x2)/2,(path.y1+path.y2)/2,radius,wanted) or {}) do
        if body~=player and blocks(body) then return true end
    end
    return false
end

local function tryParry(player,id,nx,ny,shape,oldBlade,newBlade)
    local shot=EntityGetFirstComponentIncludingDisabled(id,"ProjectileComponent")
    if not shot or not targets.hostileProjectile(player,id,shot) then return false end
    local velocity=EntityGetFirstComponentIncludingDisabled(id,"VelocityComponent")
    if not velocity then return false end
    local x,y=EntityGetTransform(id)
    if contact(id,shape,x,y) or (oldBlade and (contact(id,oldBlade,x,y) or contact(id,newBlade,x,y))) then
        return parry.reflect(player,id,shot,velocity,nx,ny)
    end
    -- A stasis snapshot retains velocity, but a paused bullet occupies only
    -- its actual position. It cannot enter a blade from outside the field.
    if not ComponentGetIsEnabled(velocity) or not ComponentGetIsEnabled(shot) then return false end
    local dx,dy=flightStep(velocity)
    if not dx or (dx==0 and dy==0) then return false end
    local tx,ty=x+dx,y+dy
    local bx,by=flightContact(shape,x,y,tx,ty)
    if oldBlade then
        for _,pose in ipairs({oldBlade,newBlade}) do
            local cx,cy=flightContact(pose,x,y,tx,ty)
            if cx and (not bx or (cx-x)^2+(cy-y)^2<(bx-x)^2+(by-y)^2) then bx,by=cx,cy end
        end
    end
    if not bx then return false end
    if blockedFlight(player,id,shot,{x1=x,y1=y,x2=bx,y2=by}) then return false end
    return parry.reflect(player,id,shot,velocity,nx,ny,bx,by)
end

-- The candidate padding covers large/offset bodies; it never widens the blade.
-- Exact contact still uses the requested capsule against each enabled hitbox.
function M.apply(player,a,hit)
    hit=hit or {}
    local mx,my=(a.x1+a.x2)/2,(a.y1+a.y2)/2
    local dx,dy=a.x2-a.x1,a.y2-a.y1
    local length=math.sqrt(dx*dx+dy*dy)
    local handX,handY=a.fxX or a.x1,a.fxY or a.y1
    local bx,by=a.x2-handX,a.y2-handY
    local bladeLength=math.sqrt(bx*bx+by*by)
    local nx,ny=bladeLength>0 and bx/bladeLength or 1,bladeLength>0 and by/bladeLength or 0
    -- x2/y2 is the actual blade tip. The rounded cap extends a radius
    -- beyond its axis, so end the axis slightly before the advertised reach.
    local cap=math.min(a.width/2,bladeLength)
    local shape={x1=a.x1,y1=a.y1,x2=a.x2-nx*cap,y2=a.y2-ny*cap,width=a.width}
    local oldBlade,newBlade
    local travelX,travelY=handX-a.x1,handY-a.y1
    if math.abs(travelX*ny-travelY*nx)>0.001 then
        -- When the floor redirects movement, the blade still points at the
        -- reticle. Include its two poses as well as the connecting sweep.
        oldBlade={x1=a.x1,y1=a.y1,x2=shape.x2-travelX,y2=shape.y2-travelY,width=a.width}
        newBlade={x1=handX,y1=handY,x2=shape.x2,y2=shape.y2,width=a.width}
    end
    local count=0
    local extent=length/2+a.width/2
    local nearRadius=extent+128
    for _,id in ipairs(EntityGetInRadius(mx,my,nearRadius) or {}) do
        if not hit[id] and (tryParry(player,id,nx,ny,shape,oldBlade,newBlade)
            or strikeEnemy(player,id,a,nx,ny,shape,oldBlade,newBlade)) then
            hit[id]=true
            count=count+1
        end
    end
    -- The native velocity limit is 61440 px/s, or 1024 px per tick. Only
    -- query tagged projectiles in the outer area; ordinary bullets and
    -- callbacks without that tag already pass through the local query.
    for _,id in ipairs(EntityGetInRadiusWithTag(mx,my,extent+1024,"projectile") or {}) do
        local x,y=EntityGetTransform(id)
        local dist2=(x-mx)^2+(y-my)^2
        if not hit[id] and dist2>nearRadius^2 then
            local vel=EntityGetFirstComponent(id,"VelocityComponent")
            if vel then
                local dx,dy=flightStep(vel)
                local gap=math.sqrt(dist2)-extent
                if dx and dx*dx+dy*dy>=gap*gap and tryParry(player,id,nx,ny,shape,oldBlade,newBlade) then
                    hit[id]=true
                    count=count+1
                end
            end
        end
    end
    return count,hit
end

local corners={{-3,-6},{0,-6},{3,-6},{-3,-2},{0,-2},{3,-2},{-3,2},{0,2},{3,2}}
local function clearBody(x,y)
    if not DoesWorldExistAt(math.floor(x)-4,math.floor(y)-7,math.ceil(x)+4,math.ceil(y)+3) then return false end
    for dy=-6,2 do if RaytracePlatforms(x-3,y+dy,x+3,y+dy) then return false end end
    -- RaytracePlatforms also sees many physics objects; query the remaining
    -- bodies explicitly so a movable crate cannot be blinked through.
    if PhysicsBodyIDQueryBodies then
        if #(PhysicsBodyIDQueryBodies(x-3,y-6,x+3,y+2,true) or {})>0 then return false end
    end
    return true
end

local function clearStep(x,y,tx,ty)
    if not clearBody(tx,ty) then return false end
    for _,p in ipairs(corners) do
        if RaytracePlatforms(x+p[1],y+p[2],tx+p[1],ty+p[2]) then return false end
    end
    return true
end

-- Third return is the portion of the requested step completed. On level
-- ground a shallow downward lunge can spend it moving along the surface.
function M.safeStep(x,y,dx,dy,distance)
    local moved=0
    while moved<distance do
        local step=math.min(2,distance-moved)
        local tx,ty=x+dx*step,y+dy*step
        if not clearStep(x,y,tx,ty) then
            if dy<=0 or dy>0.35 or not RaytracePlatforms(x,y+1,x,y+4) or not clearStep(x,y,tx,y) then break end
            ty=y
        end
        x,y,moved=tx,ty,moved+step
    end
    return x,y,moved
end
return M
