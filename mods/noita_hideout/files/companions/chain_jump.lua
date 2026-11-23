local targets=dofile_once("mods/noita_hideout/files/companions/targets.lua")
local shoot=dofile_once("mods/noita_hideout/files/companions/projectile.lua")
local bolt=GetUpdatedEntityID()
local shot=EntityGetFirstComponentIncludingDisabled(bolt,"ProjectileComponent")
local memory=EntityGetFirstComponentIncludingDisabled(bolt,"VariableStorageComponent","nh_chain_memory")
if not shot or not memory then return end
local player=ComponentGetValue2(shot,"mWhoShot")
if player==0 or not EntityGetIsAlive(player) then return end
local x,y,angle=EntityGetTransform(bolt)
local last=ComponentGetValue2(memory,"value_int")
local target,tx,ty=targets.nearest(player,x,y,48,last,ComponentGetValue2(memory,"value_float"))
ComponentSetValue2(memory,"value_float",last)
ComponentSetValue2(memory,"value_int",target or 0)
tx,ty=tx or x+math.cos(angle)*30,ty or y+math.sin(angle)*30
EntitySetTransform(bolt,tx,ty,angle)
shoot(player,"data/entities/projectiles/deck/chain_bolt_explosion.xml",tx,ty,1,0,0)
