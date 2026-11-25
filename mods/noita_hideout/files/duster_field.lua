local files="mods/noita_hideout/files/"
local targets=dofile_once(files.."field_targets.lua")
local M={radius=90}

function M.activate(player,pay)
    if not player or player==0 or not EntityGetIsAlive(player) or not EntityHasTag(player,"player_unit")
        or not dofile_once(files.."ew.lua").localBody(player) then return false,"Item unavailable." end
    if (EntityGetAllChildren(player,"nh_duster_field") or {})[1] then return false,"Field already active." end
    local x,y=EntityGetTransform(player)
    local field=EntityLoad(files.."duster_field.xml",x,y)
    if not field or field==0 then return false,"Item unavailable." end
    local clock=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent","nh_duster_until")
    if not clock then EntityKill(field); return false,"Item unavailable." end
    if pay and not pay() then EntityKill(field); return false,"Item unavailable." end
    ComponentSetValue2(clock,"value_int",GameGetFrameNum()+3600)
    EntityAddChild(player,field)
    return true
end

local function repel(entity,x,y,item,body)
    local px,py,angle,sx,sy=EntityGetTransform(entity)
    local dx,dy=px-x,py-y
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance>M.radius then return end
    if distance>0 then dx,dy=dx/distance,dy/distance else dx,dy=0,-1 end
    if body then
        -- Work on the bodies of this component only. Linked machinery and the
        -- static world must not receive an impulse through a shared joint.
        for _,id in ipairs(PhysicsBodyIDGetFromEntity(entity,body) or {}) do
            local bx,by,rot,vx,vy,spin=PhysicsBodyIDGetTransform(id)
            if bx then
                local speed=GameVecToPhysicsVec(35+55*(1-distance/M.radius))
                local impulse=math.max(0,speed-vx*dx-vy*dy)
                if impulse>0 then PhysicsBodyIDSetTransform(id,bx,by,rot,vx+dx*impulse,vy+dy*impulse,spin) end
            end
        end
        return
    end
    local motion=EntityGetFirstComponent(entity,"CharacterDataComponent") or EntityGetFirstComponent(entity,"VelocityComponent")
    if motion then
        -- Only correct the inward radial speed. A fast outbound shot keeps
        -- its original speed, while a glancing one retains its tangent.
        local vx,vy=ComponentGetValue2(motion,"mVelocity")
        local impulse=math.max(0,160+120*(1-distance/M.radius)-vx*dx-vy*dy)
        if impulse>0 then ComponentSetValue2(motion,"mVelocity",vx+dx*impulse,vy+dy*impulse) end
    elseif item then
        -- Floating loot has no physics body. Sweep a short segment and stop
        -- before the wall rather than carrying the item into the terrain.
        local step=math.min(7,M.radius-distance+1)
        local tx,ty=px+dx*step,py+dy*step
        local hit,hx,hy=RaytracePlatforms(px,py,tx,ty)
        if hit then
            step=math.max(0,(hx-px)*dx+(hy-py)*dy-2)
            tx,ty=px+dx*step,py+dy*step
        end
        if step>0 then EntityApplyTransform(entity,tx,ty,angle,sx,sy) end
    end
end

function M.update(field)
    local owner=EntityGetParent(field)
    if not owner or owner==0 or not EntityHasTag(owner,"player_unit") then EntityKill(field); return end
    local clock=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent","nh_duster_until")
    local life=EntityGetFirstComponentIncludingDisabled(field,"LifetimeComponent")
    local now=GameGetFrameNum()
    local untilFrame=clock and ComponentGetValue2(clock,"value_int")
    if not untilFrame or now>=untilFrame then EntityKill(field); return end
    -- Noita rebuilds a fresh kill_frame from lifetime when the field reloads.
    if life and ComponentGetValue2(life,"kill_frame")~=untilFrame then ComponentSetValue2(life,"kill_frame",untilFrame) end
    local x,y=EntityGetTransform(owner)
    local ew=ModIsEnabled("quant.ew")
    for _,entity in ipairs(EntityGetInRadius(x,y,M.radius) or {}) do
        local item=EntityGetFirstComponent(entity,"ItemComponent")
        local body=EntityGetFirstComponent(entity,"PhysicsBody2Component") or EntityGetFirstComponent(entity,"PhysicsBodyComponent")
        if (item or EntityHasTag(entity,"mortal") or EntityHasTag(entity,"enemy") or EntityHasTag(entity,"projectile")
            or EntityGetFirstComponent(entity,"ProjectileComponent") or body)
            and not EntityHasTag(entity,"nh_hourglass_still") and targets.canAffect(entity,ew)
            and (not body or not ComponentGetValue2(body,"is_static"))
            and (not body or not (EntityGetFirstComponentIncludingDisabled(entity,"PhysicsJointComponent")
                or EntityGetFirstComponentIncludingDisabled(entity,"PhysicsJoint2Component") or EntityHasTag(entity,"hanging")))
            and (not item or (ComponentGetValue2(item,"is_pickable") and not EntityGetFirstComponentIncludingDisabled(entity,"ItemCostComponent"))) then
            repel(entity,x,y,item,body)
        end
    end
end

return M
