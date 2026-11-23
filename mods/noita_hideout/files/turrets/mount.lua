local root="mods/noita_hideout/files/"
local turret=GetUpdatedEntityID()
local weapons=dofile_once(root.."turrets/mount_weapons.lua")
local weapon=weapons.mg
if EntityHasTag(turret,"nh_missile_turret") then weapon=weapons.missile
elseif EntityHasTag(turret,"nh_chaingun_turret") then weapon=weapons.chaingun end
local x,y=EntityGetTransform(turret)
y=y-3 -- The bearing stays at the top of the common pedestal.
-- Run on a normal tick so a restored turret's saved child is attached first.
local head=(EntityGetAllChildren(turret,"nh_mount_head") or {})[1]
if not head then
    head=EntityCreateNew("nh_mount_head")
    EntityAddTag(head,"nh_mount_head")
    EntityAddComponent2(head,"SpriteComponent",{_tags="character",rect_animation="stand",z_index=-1.1,
        image_file=root.."turrets/"..weapon.head})
    EntityAddComponent2(head,"SpriteAnimatorComponent",{})
    EntityAddComponent2(head,"VariableStorageComponent",{_tags="nh_mount_cycle",value_int=-1000})
    EntityAddChild(turret,head)
    EntitySetTransform(head,x,y)
end

local ammo=dofile_once(root.."turrets/ammo.lua")
local counter=ammo.counter(turret)
if not counter or ComponentGetValue2(counter,"value_int")<=0 then return end
local cycle=EntityGetFirstComponent(head,"VariableStorageComponent","nh_mount_cycle")
local left=ComponentGetValue2(cycle,"value_float")
local player=(EntityGetWithTag("player_unit") or {})[1] or (EntityGetWithTag("polymorphed_player") or {})[1]
local targets=dofile_once(root.."companions/targets.lua")
local target,tx,ty
if GameGetGameEffectCount(turret,"FROZEN")==0 and GameGetGameEffectCount(turret,"ELECTROCUTION")==0 then
    target,tx,ty=targets.nearest(turret,x,y,260,player)
end
if not target then
    if left>0 then ComponentSetValue2(cycle,"value_float",0) end
    return
end

local dx,dy=tx-x,ty-y
local distance=math.sqrt(dx*dx+dy*dy)
local flip=dx<0 and -1 or 1
local bore=math.min(weapon.bore,distance)*flip
local angle=math.atan2(dy,dx)-math.asin(bore/math.max(distance,0.001))
EntitySetTransform(head,x,y,angle,1,flip)

local frame=GameGetFrameNum()
local elapsed=frame-ComponentGetValue2(cycle,"value_int")
local first=elapsed<0 or elapsed>=weapon.period
local index=first and 1 or weapon.count-left+1
if not first and (left<=0 or elapsed<(index-1)*weapon.spacing or elapsed>=weapon.count*weapon.spacing) then return end

-- If an enemy gets inside the barrel, start the shot on its near side.
local reach=math.min(weapon.reach,math.max(0,distance-5))
local ux,uy=math.cos(angle),math.sin(angle)
if weapon.ports then bore=weapon.ports[index]*flip end
local sx,sy=x+ux*reach-uy*bore,y+uy*reach+ux*bore
if RaytracePlatforms(x,y,sx,sy) or RaytracePlatforms(sx,sy,tx,ty) then return end
local round=EntityLoad(root.."turrets/"..weapon.round,sx,sy)
if not round or round==0 then return end
local shot=EntityGetFirstComponent(round,"ProjectileComponent")
local velocity=EntityGetFirstComponent(round,"VelocityComponent")
if not shot or not velocity or not ammo.spend(turret) then EntityKill(round); return end
GameShootProjectile(turret,sx,sy,sx+100*ux,sy+100*uy,round,false)
ComponentSetValue2(shot,"mWhoShot",player or turret)
ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(EntityGetFirstComponent(turret,"GenomeDataComponent"),"herd_id"))
local homing=EntityGetFirstComponent(round,"HomingComponent")
if homing then ComponentSetValue2(homing,"predefined_target",target) end
local speed=ComponentGetValue2(shot,"speed_min")
ComponentSetValue2(velocity,"mVelocity",speed*ux,speed*uy)
GameEntityPlaySound(turret,"shoot_bullet")
if weapon.animations then
    GamePlayAnimation(head,weapon.animations[index],2,"stand",0)
elseif first then GamePlayAnimation(head,"attack_ranged",2,"stand",0) end
if first then
    ComponentSetValue2(cycle,"value_int",frame)
    left=weapon.count
end
ComponentSetValue2(cycle,"value_float",left-1)
