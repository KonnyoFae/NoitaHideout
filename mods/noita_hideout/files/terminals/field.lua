local F={radius=96}
local function direction(id,x,y)
    local px,py=EntityGetTransform(id)
    local dx,dy=px-x,py-y
    local d=math.sqrt(dx*dx+dy*dy)
    if d<0.01 then return 0,-1 end
    return dx/d,dy/d
end
local function repel(c,nx,ny,speed)
    local vx,vy=ComponentGetValue2(c,"mVelocity")
    local radial=vx*nx+vy*ny
    -- Reverse incoming motion while preserving tangential and outgoing speed.
    if radial<speed then
        ComponentSetValue2(c,"mVelocity",vx+nx*(speed-radial),vy+ny*(speed-radial))
    end
end
function F.update(id,radius)
    radius=radius or F.radius
    local x,y=EntityGetTransform(id)
    for _,p in ipairs(EntityGetInRadiusWithTag(x,y,radius,"projectile") or {}) do
        local c=EntityGetFirstComponentIncludingDisabled(p,"VelocityComponent")
        if c then
            local nx,ny=direction(p,x,y)
            local vx,vy=ComponentGetValue2(c,"mVelocity")
            if vx*nx+vy*ny<=0 then repel(c,nx,ny,math.max(240,math.sqrt(vx*vx+vy*vy))) end
        end
    end
    local player=(EntityGetWithTag("player_unit") or {})[1] or (EntityGetWithTag("polymorphed_player") or {})[1]
    if not player then return end
    for _,enemy in ipairs(EntityGetInRadiusWithTag(x,y,radius,"enemy") or {}) do
        if enemy~=player and not EntityHasTag(enemy,"noita_hideout_companion")
            and not EntityHasTag(enemy,"nh_deployed_turret")
            and not EntityHasTag(enemy,"player_unit") and not EntityHasTag(enemy,"polymorphed_player")
            and EntityGetHerdRelationSafe(player,enemy)<40 then
            local nx,ny=direction(enemy,x,y)
            local c=EntityGetFirstComponentIncludingDisabled(enemy,"CharacterDataComponent")
                or EntityGetFirstComponentIncludingDisabled(enemy,"VelocityComponent")
            if c then repel(c,nx,ny,180) end
            if EntityGetFirstComponentIncludingDisabled(enemy,"PhysicsBodyComponent")
                or EntityGetFirstComponentIncludingDisabled(enemy,"PhysicsBody2Component") then
                PhysicsApplyForce(enemy,nx*30,ny*30)
            end
        end
    end
end
return F
