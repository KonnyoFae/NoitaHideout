-- The AI fires round one. Finish the burst from the gun's current bearing.
local turret=GetUpdatedEntityID()
local role=EntityGetFirstComponentIncludingDisabled(turret,"VariableStorageComponent","nh_reinforcement_role")
local elapsed=role and GameGetFrameNum()-ComponentGetValue2(role,"value_int") or -1
if elapsed<0 or elapsed>=16 then EntityRemoveComponent(turret,GetUpdatedComponentID()) end
if elapsed<=0 or elapsed>16 or elapsed%4~=0 then return end

local attack=EntityGetFirstComponent(turret,"AIAttackComponent")
local player=(EntityGetWithTag("player_unit") or {})[1]
if not attack or not player then return end
local angle=ComponentGetValue2(attack,"mRangedAttackCurrentAimAngle")
local dx,dy=math.cos(angle),math.sin(angle)
local x,y=EntityGetTransform(turret)
local reach=ComponentGetValue2(attack,"attack_ranged_offset_x")
x=x+ComponentGetValue2(attack,"attack_ranged_root_offset_x")+reach*dx
y=y+ComponentGetValue2(attack,"attack_ranged_root_offset_y")+reach*dy
local round=EntityLoad(ComponentGetValue2(attack,"attack_ranged_entity_file"),x,y)
if not round or round==0 then return end
local ammo=dofile("mods/noita_hideout/files/turrets/ammo.lua")
if not ammo.spend(turret) then EntityKill(round); return end
-- Suppress the shot message so a follow-up cannot start another burst.
GameShootProjectile(turret,x,y,x+dx*100,y+dy*100,round,false)
GameEntityPlaySound(turret,"shoot_bullet")
local shot=EntityGetFirstComponentIncludingDisabled(round,"ProjectileComponent")
local velocity=EntityGetFirstComponentIncludingDisabled(round,"VelocityComponent")
local owner=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
if shot and velocity and owner then
    ComponentSetValue2(shot,"mWhoShot",player)
    ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(owner,"herd_id"))
    local speed=ComponentGetValue2(shot,"speed_min")
    ComponentSetValue2(velocity,"mVelocity",dx*speed,dy*speed)
end
