-- Native AI aims and fires; assign friendly projectiles to the current player.
-- Resolve the player on every shot so loading a save never retains a stale ID.
local ammo=dofile("mods/noita_hideout/files/turrets/ammo.lua")
function shot(projectile)
    local turret=GetUpdatedEntityID()
    local machineGun=EntityHasTag(turret,"nh_mg_turret")
    local remaining
    if machineGun or EntityHasTag(turret,"nh_chaingun_turret") then
        remaining=ammo.spend(turret)
        if not remaining then EntityKill(projectile); return end
    end
    if machineGun and remaining>0 and EntityHasTag(projectile,"nh_mg_round") then
        local role=EntityGetFirstComponentIncludingDisabled(turret,"VariableStorageComponent","nh_reinforcement_role")
        if role and not EntityGetFirstComponentIncludingDisabled(turret,"LuaComponent","nh_mg_burst_tick") then
            ComponentSetValue2(role,"value_int",GameGetFrameNum())
            EntityAddComponent2(turret,"LuaComponent",{_tags="nh_mg_burst_tick",execute_every_n_frame=1,
                script_source_file="mods/noita_hideout/files/turrets/mg_burst.lua"})
        end
    end
    local player=(EntityGetWithTag("player_unit") or {})[1]
    if not player then return end
    local p=EntityGetFirstComponentIncludingDisabled(projectile,"ProjectileComponent")
    local g=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
    if p and g then
        ComponentSetValue2(p,"mWhoShot",player)
        ComponentSetValue2(p,"mShooterHerdId",ComponentGetValue2(g,"herd_id"))
    end
    local h=EntityGetFirstComponentIncludingDisabled(projectile,"HomingComponent")
    if h then
        local ai=EntityGetFirstComponentIncludingDisabled(GetUpdatedEntityID(),"AnimalAIComponent")
        local target=ai and ComponentGetValue2(ai,"mGreatestThreat")
        if target and target~=0 and EntityGetIsAlive(target) and EntityGetHerdRelation(player,target)<40
            and GameGetGameEffectCount(target,"CHARM")==0 then
            ComponentSetValue2(h,"predefined_target",target)
        else EntityRemoveComponent(projectile,h) end
    end
end
