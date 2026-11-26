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

return M
