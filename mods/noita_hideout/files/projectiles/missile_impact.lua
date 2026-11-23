-- A shield can absorb the rocket before a world-hit trigger fires. Use the
-- rocket's final heading for both interceptions and ordinary impacts.
local missile=GetUpdatedEntityID()
local shot=EntityGetFirstComponentIncludingDisabled(missile,"ProjectileComponent")
local movement=EntityGetFirstComponentIncludingDisabled(missile,"VelocityComponent")
if not shot or not movement then return end
-- An artillery missile also detonates on reaching its marked airburst point.
if ComponentGetValue2(shot,"lifetime")<=0 and not EntityHasTag(missile,"nh_strike_missile") then return end
local owner=ComponentGetValue2(shot,"mWhoShot")
if owner==0 or not EntityGetIsAlive(owner) then return end
local x,y,heading=EntityGetTransform(missile)
if not x or not DoesWorldExistAt(math.floor(x)-1,math.floor(y)-1,math.ceil(x)+1,math.ceil(y)+1) then return end

local vx,vy=ComponentGetValue2(movement,"mVelocity")
if vx*vx+vy*vy<0.01 then vx,vy=ComponentGetValue2(movement,"mPrevVelocity") end
if vx*vx+vy*vy>=0.01 then heading=math.atan2(vy,vx) end
local cutter=EntityLoad("mods/noita_hideout/files/projectiles/missile_cutter.xml",x,y)
if not cutter or cutter==0 then return end
-- Parenting credits the native laser to the shooter. The emitter has no
-- InheritTransformComponent, so its position remains fixed at the impact.
EntityAddChild(owner,cutter)
EntitySetTransform(cutter,x,y,heading)
