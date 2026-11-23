dofile_once("data/scripts/lib/utilities.lua")

local charge=GetUpdatedEntityID()
local x,y=EntityGetTransform(charge)
local vx,vy=GameGetVelocityCompVelocity(charge)
local speed=math.sqrt(vx*vx+vy*vy)
if speed<0.001 then return end
local dx,dy=vx/speed,vy/speed

-- Keep the native seven-beam silhouette and carry the charge's shooter into each beam.
for offset=-3,3 do
    local launchSpeed=120*(1-math.abs(offset)*0.12)
    shoot_projectile_from_projectile(charge,"mods/noita_hideout/files/escort_laser_beam.xml",
        x-dy*offset,y+dx*offset,dx*launchSpeed,dy*launchSpeed)
end
GamePlaySound("data/audio/Desktop/projectiles.bank","projectiles/megalaser_blue/launch",x,y)
