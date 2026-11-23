-- Both native hands fire through the monk. Keep the slow exclusive to their green orbs.
function shot(projectile)
    if EntityGetFilename(projectile)~="data/entities/projectiles/orb_green_accelerating.xml" then return end
    local bolt=EntityGetFirstComponentIncludingDisabled(projectile,"ProjectileComponent")
    if not bolt then return end
    ComponentSetValue2(bolt,"friendly_fire",false)
    EntityLoadToEntity("mods/noita_hideout/files/escort_monk_orb_hit.xml",projectile)
end
