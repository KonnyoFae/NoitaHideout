local targets=dofile_once("mods/noita_hideout/files/companions/targets.lua")
local disc=GetUpdatedEntityID()
local shot=EntityGetFirstComponentIncludingDisabled(disc,"ProjectileComponent")
if not shot then return end
local player=ComponentGetValue2(shot,"mWhoShot")
if player==0 or not EntityGetIsAlive(player) then return end
local x,y=EntityGetTransform(disc)
for _,target in ipairs(EntityGetInRadiusWithTag(x,y,15,"hittable") or {}) do
    if targets.hostile(player,target) then
        EntityInflictDamage(target,0.9,"DAMAGE_SLICE","$action_omega_disc_bullet","NONE",0,0,player,x,y)
    end
end
