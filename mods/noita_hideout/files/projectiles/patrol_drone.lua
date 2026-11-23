local id=GetUpdatedEntityID()
local shot=EntityGetFirstComponent(id,"ProjectileComponent")
local anchor=EntityGetFirstComponent(id,"VariableStorageComponent","nh_patrol_anchor")
if not shot or not anchor then return end
local owner=ComponentGetValue2(shot,"mWhoShot")
if owner==0 or not EntityGetIsAlive(owner) then EntityKill(id);return end
local x,y=EntityGetTransform(id)
local hx,hy=ComponentGetValue2(anchor,"value_int"),ComponentGetValue2(anchor,"value_float")
local targets=dofile_once("mods/noita_hideout/files/companions/targets.lua")
local target,tx,ty=targets.nearest(owner,hx,hy,88)
if target and (tx-x)^2+(ty-y)^2<=88^2 and not RaytracePlatforms(x,y,tx,ty) then
    local dx,dy=tx-x,ty-y
    local distance=math.max(1,math.sqrt(dx*dx+dy*dy))
    local launch=dofile_once("mods/noita_hideout/files/companions/projectile.lua")
    if launch(owner,"mods/noita_hideout/files/projectiles/patrol_dive.xml",x,y,dx/distance,dy/distance,420,60,target) then
        EntityKill(id);return
    end
end

local phase=GameGetFrameNum()*0.055+id
local ox,oy=hx+18*math.cos(phase),hy+10*math.sin(phase)
if RaytracePlatforms(hx,hy,ox,oy) or RaytracePlatforms(x,y,ox,oy) then ox,oy=hx,hy end
local dx,dy=ox-x,oy-y
local distance=math.max(1,math.sqrt(dx*dx+dy*dy))
local step=math.min(distance,6)
local nx,ny=x+dx/distance*step,y+dy/distance*step
ComponentSetValue2(EntityGetFirstComponent(id,"VelocityComponent"),"mVelocity",0,0)
if not RaytracePlatforms(x,y,nx,ny) then EntitySetTransform(id,nx,ny,math.atan2(dy,dx)) end
