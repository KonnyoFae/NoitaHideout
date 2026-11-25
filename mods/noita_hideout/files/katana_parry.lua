-- Redirect the original projectile; shooting it again would initialize its
-- damage, lifetime and trigger chain a second time.
local root="mods/noita_hideout/files/"
local targets=dofile_once(root.."field_targets.lua")
local freeze=dofile_once(root.."stasis.lua")
local M={}
local paused="nh_hourglass_paused"
local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end
local function first(entity,kind)
    return EntityGetFirstComponentIncludingDisabled(entity,kind)
end
local function running(component)
    return ComponentGetIsEnabled(component) or ComponentHasTag(component,paused)
end
-- These use a different motion integrator. A VelocityComponent alongside a
-- Box2D/Verlet body is not enough to redirect the actual projectile safely.
local otherMotion={"ItemComponent","PhysicsBodyComponent","PhysicsBody2Component",
    "PhysicsBodyCollisionDamageComponent","VerletWeaponComponent","VerletPhysicsComponent"}

function M.reflect(player,id,shot,vel,nx,ny,contactX,contactY)
    if not shot or not vel or not finite(nx) or not finite(ny)
        or not targets.hostileProjectile(player,id,shot) then return false end
    if first(id,"ProjectileComponent")~=shot or first(id,"VelocityComponent")~=vel
        or not running(shot) or not running(vel) then return false end
    for _,kind in ipairs(otherMotion) do if first(id,kind) then return false end end
    -- Native lightning traces an arc from its previous position rather than
    -- flying an ordinary bullet. Moving laser bullets without this component
    -- remain eligible, as do flying explosive/area-damage shells.
    local lightning=first(id,"LightningComponent")
    if lightning and ComponentGetValue2(lightning,"is_projectile") then return false end
    local genome=first(player,"GenomeDataComponent")
    local herd=genome and ComponentGetValue2(genome,"herd_id")
    if not finite(herd) then return false end
    local vx,vy=freeze.getVelocity(id)
    if not finite(vx) or not finite(vy) then return false end
    local speed,direction=math.sqrt(vx*vx+vy*vy),math.sqrt(nx*nx+ny*ny)
    if not finite(speed) or speed<=0.000001 or not finite(direction) or direction<=0.000001 then return false end
    local relocating=contactX~=nil or contactY~=nil
    if relocating and (not finite(contactX) or not finite(contactY)) then return false end
    local x,y,angle,sx,sy=EntityGetTransform(id)
    if not finite(x) or not finite(y) then return false end
    nx,ny=nx/direction,ny/direction

    local changes={}
    local function set(component,key,value)
        changes[#changes+1]={component,key,ComponentGetValue2(component,key)}
        ComponentSetValue2(component,key,value)
    end
    set(shot,"mWhoShot",player)
    set(shot,"mEntityThatShot",player)
    set(shot,"mShooterHerdId",herd)
    -- Keep the original impact trigger: timed/terrain-only shells must not
    -- start detonating on creatures merely because their allegiance changed.
    set(shot,"collide_with_tag","hittable")
    set(shot,"dont_collide_with_tag","")
    set(shot,"friendly_fire",false)
    set(shot,"never_hit_player",true)
    set(shot,"collide_with_shooter_frames",-1)
    set(shot,"explosion_dont_damage_shooter",true)
    for _,homing in ipairs(EntityGetComponentIncludingDisabled(id,"HomingComponent") or {}) do
        set(homing,"target_tag","enemy")
        set(homing,"target_who_shot",false)
        set(homing,"predefined_target",0)
    end
    -- Native travelling damage auras have their own target filter and credit.
    -- Preserve their damage, timing and shape while removing player targeting.
    for _,area in ipairs(EntityGetComponentIncludingDisabled(id,"AreaDamageComponent") or {}) do
        set(area,"entity_responsible",player)
        set(area,"entities_with_tag","enemy")
    end
    -- Re-evaluate all stasis owners after changing allegiance. This does not
    -- force-enable a projectile still covered by an independent hourglass.
    if not freeze.redirect(id,nx*speed,ny*speed) then
        for i=#changes,1,-1 do
            local prior=changes[i]
            ComponentSetValue2(prior[1],prior[2],prior[3])
        end
        return false
    end
    if relocating then x,y=contactX,contactY end
    if ComponentGetValue2(shot,"velocity_sets_rotation") then angle=math.atan2(ny,nx) end
    if relocating or ComponentGetValue2(shot,"velocity_sets_rotation") then
        EntitySetTransform(id,x,y,angle or 0,sx or 1,sy or 1)
    end
    EntityAddTag(id,"nh_katana_reflected")
    GameCreateCosmeticParticle("spark_white",x,y,5,nx*22,ny*22,0,0.08,0.16,true,true,false,true,0,0)
    return true
end

return M
