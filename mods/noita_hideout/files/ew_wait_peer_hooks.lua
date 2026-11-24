-- Runs inside the EW Lua state. An invisible waiting entity carries the
-- peer's identity for EW, but cannot act or be selected as a teammate.
local M = {}

function M.waiting(entity)
    return entity ~= nil and entity ~= 0 and EntityHasTag(entity, "nh_ew_waiting")
end

function M.installPeerEvents(proxy)
    local original = proxy.dc
    proxy.dc = function(message, peer)
        local player = ctx.players[peer]
        if not player or not M.waiting(player.entity) then return original(message, peer) end
        player.dc = true
        EntityRemoveTag(player.entity, "ew_client")
        EntityRemoveTag(player.entity, "ew_peer")
    end
    local leave = proxy.leave
    proxy.leave = function(message, peer)
        -- EW reads the target's entity when sampling gamepad input, before
        -- the spectate system gets a chance to choose a replacement.
        if ctx.spectating_over_peer_id == peer and ctx.my_player and M.waiting(ctx.my_player.entity) then
            ctx.spectating_over_peer_id = nil
        end
        return leave(message, peer)
    end
end

function M.receiveState(player, inputs, position)
    -- The host clock also travels in the input packet, even while dead.
    if player.peer_id == ctx.host_id and inputs and inputs.host_frame_num ~= nil then
        ctx.host_frame_num = inputs.host_frame_num
    end
    if position then
        player.pos_x, player.pos_y = position.x, position.y
        EntitySetTransform(player.entity, position.x, position.y)
    end
end

function M.excludeCamera(entity, peer)
    if M.waiting(entity) then return true end
    if not M.waiting(ctx.my_player.entity) then return false end
    local player = ctx.players[peer] or ctx.player_data_by_local_entity[entity]
    return not player or not entity or entity == 0 or player.dc or not EntityGetIsAlive(entity)
        or EntityHasTag(entity, "ew_notplayer") or (player.status and player.status.is_alive == false)
end

return M
