local attack=dofile_once("mods/noita_hideout/files/companions/dragon_attack.lua")
function shot(projectile)
    local player=GetUpdatedEntityID()
    if EntityHasTag(projectile,"nh_companion_shot") then return end
    local data=EntityGetFirstComponentIncludingDisabled(projectile,"ProjectileComponent")
    if not data then return end
    local source=ComponentGetValue2(data,"mEntityThatShot")
    if source~=0 and source~=player then return end
    local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    if controls then attack(player,ComponentGetValue2(controls,"mAimingVectorNormalized")) end
end
