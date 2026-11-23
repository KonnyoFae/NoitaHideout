local targets=dofile_once("mods/noita_hideout/files/companions/targets.lua")
local insect=GetUpdatedEntityID()
local homing=EntityGetFirstComponentIncludingDisabled(insect,"HomingComponent")
local shot=EntityGetFirstComponentIncludingDisabled(insect,"ProjectileComponent")
if not shot or not homing then return end
local player=ComponentGetValue2(shot,"mWhoShot")
if player==0 or not EntityGetIsAlive(player) then EntityKill(insect); return end
local target=ComponentGetValue2(homing,"predefined_target")
if target~=0 and EntityGetIsAlive(target) and targets.hostile(player,target) then return end
local x,y=EntityGetTransform(insect)
ComponentSetValue2(homing,"predefined_target",targets.nearest(player,x,y,100) or 0)
