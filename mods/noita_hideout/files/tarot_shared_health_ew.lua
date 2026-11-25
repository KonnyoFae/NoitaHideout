local api = dofile_once("mods/quant.ew/files/api/ew_api.lua")
local rpc = api.new_rpc_namespace("nh_tarot_shared_health")
local M = {}
local serial, received = 0, {}
local maximumSteps = dofile_once("mods/noita_hideout/files/tarot.lua").duration / 60

local function shared()
    return ctx.proxy_opt.game_mode == "shared_health" and ctx.cap.health ~= nil
end

local function publishMode()
    GlobalsSetValue("nh_ew.tarot_shared_health", shared() and "1" or "")
    GlobalsSetValue("nh_ew.rewind_health",ctx.proxy_opt.game_mode or "")
end

function M.on_world_initialized()
    serial, received = 0, {}
    publishMode()
end
M.on_local_player_spawn = publishMode

local function validSteps(steps)
    return type(steps) == "number" and steps >= 1 and steps <= maximumSteps and steps == math.floor(steps)
end

-- Only the host mutates the shared health value. Overlapping requests are
-- capped against the current pool at application time, not the sender's HUD.
local function drain(steps)
    local health = ctx.cap.health
    local current, maximum = health.health(), health.max_health()
    if maximum > 0 and current > maximum / 2 then
        health.set_health(math.max(maximum / 2, current - maximum * 0.01 * steps))
    end
end

util.add_cross_call("ew_hideout_tarot_drain", function(player, steps)
    if not shared() or ctx.run_ended or not ctx.ready or not ctx.my_player
        or ctx.my_player.entity ~= player or ctx.my_player.currently_polymorphed or not validSteps(steps) then return end
    if ctx.is_host then drain(steps); return end
    local world = nh_ew_session and nh_ew_session.world()
    local sourceBoot = world and nh_ew_session.challenge(ctx.my_id)
    local hostBoot = world and nh_ew_session.challenge(ctx.host_id)
    if sourceBoot and hostBoot then
        serial = serial + 1
        rpc.drain(world, sourceBoot, hostBoot, serial, steps)
    end
end)

rpc.opts_reliable()
function rpc.drain(world, sourceBoot, hostBoot, sequence, steps)
    if not ctx.is_host or not ctx.ready or ctx.run_ended or not shared() or not validSteps(steps)
        or not nh_ew_session or not world or world ~= nh_ew_session.world()
        or not hostBoot or hostBoot ~= nh_ew_session.challenge(ctx.my_id) then return end
    local source = api.rpc_player_data()
    if not source or source.dc or source.peer_id == ctx.my_id or not sourceBoot
        or sourceBoot ~= nh_ew_session.challenge(source.peer_id)
        or type(sequence) ~= "number" or sequence < 1 or sequence ~= math.floor(sequence) then return end
    local last = received[source.peer_id]
    if last and last.world == world and last.boot == sourceBoot and sequence <= last.sequence then return end
    received[source.peer_id] = {world=world, boot=sourceBoot, sequence=sequence}
    drain(steps)
end

return M
