local M={}

function M.canAffect(entity,multiplayer)
    if EntityGetRootEntity(entity)~=entity or EntityHasTag(entity,"player_unit")
        or EntityHasTag(entity,"polymorphed_player") or EntityHasTag(entity,"ew_peer")
        or EntityHasTag(entity,"ew_client") or EntityHasTag(entity,"ew_notplayer")
        or EntityHasTag(entity,"nh_ew_waiting") or EntityHasTag(entity,"nh_hourglass_field")
        or EntityHasTag(entity,"nh_duster_field") or EntityHasTag(entity,"nh_reactor_meltdown")
        or EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent","nh_ew_deposit_lock") then return false end
    local tracked=EntityHasTag(entity,"ew_des")
    if multiplayer or tracked then
        dofile_once("mods/noita_hideout/files/ew_items.lua")
        local gid,invalid,owned=NHEWItems.gid(entity)
        if gid then return owned==true end
        if invalid or tracked then return false end
    end
    return true
end

function M.friendly(player,entity)
    if not entity or entity==0 or not EntityGetIsAlive(entity) then return false end
    return entity==player or EntityHasTag(entity,"player_unit") or EntityHasTag(entity,"polymorphed_player")
        or EntityHasTag(entity,"ew_peer") or EntityHasTag(entity,"ew_client") or EntityHasTag(entity,"ew_notplayer")
        or EntityHasTag(entity,"noita_hideout_companion") or EntityHasTag(entity,"nh_deployed_turret")
        or EntityHasTag(entity,"nh_reinforcement") or GameGetGameEffectCount(entity,"CHARM")>0
        or EntityGetHerdRelationSafe(player,entity)>=40
end

-- The same owner/faction check is used by katana stasis and projectile parries.
-- Read disabled projectile components too: stasis suspends their simulation.
function M.hostileProjectile(player,entity,shot)
    if not player or player==0 or not EntityGetIsAlive(player) or not entity or entity==0 or not EntityGetIsAlive(entity)
        or not M.canAffect(entity,ModIsEnabled("quant.ew")) or EntityHasTag(entity,"nh_katana_field")
        or EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent") then return false end
    shot=shot or EntityGetFirstComponentIncludingDisabled(entity,"ProjectileComponent")
    if not shot or shot==0 then return false end
    local shooter=ComponentGetValue2(shot,"mWhoShot")
    if shooter and shooter~=0 and EntityGetIsAlive(shooter) then
        return not M.friendly(player,EntityGetRootEntity(shooter))
    end
    local genome=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
    local shotHerd=ComponentGetValue2(shot,"mShooterHerdId")
    -- A dead shooter's stored herd retains its allegiance. An effect without
    -- either a live shooter or a known firing herd is not proven hostile.
    return genome and type(shotHerd)=="number" and shotHerd>0
        and GetHerdRelation(ComponentGetValue2(genome,"herd_id"),shotHerd)<40 or false
end

return M
