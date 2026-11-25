local api=dofile_once("mods/quant.ew/files/api/ew_api.lua")
local bonuses=dofile_once("mods/noita_hideout/files/loot_bonuses.lua")
local rpc=api.new_rpc_namespace("nh_loot_bonuses")
local M={}
local serial,received=0,{}
local published,wasActive

rpc.opts_reliable()
function rpc.status(world,boot,sequence,snapshot)
    if not world or not boot or not nh_ew_session or nh_ew_session.world()~=world
        or type(sequence)~="number" or sequence<1 or sequence>=math.huge or sequence~=math.floor(sequence) then return end
    local peer=api.rpc_player_data()
    if not peer or peer.dc or peer.peer_id==ctx.my_id or boot~=nh_ew_session.challenge(peer.peer_id) then return end
    local last=received[peer.peer_id]
    if last and last.world==world and last.boot==boot and sequence<=last.sequence then return end
    if bonuses.applyRemote(peer.entity,snapshot) then received[peer.peer_id]={world=world,boot=boot,sequence=sequence} end
end

function M.on_world_initialized()
    published,wasActive,received=nil,false,{}
end

function M.on_world_update()
    local frame=GameGetFrameNum()
    if frame%5~=0 then return end
    local dirty=GlobalsGetValue(bonuses.dirtyField,"")=="1"
    if published and not dirty and frame%120~=0 then return end
    local world=ctx.my_player and nh_ew_session and nh_ew_session.world()
    local boot=world and nh_ew_session.challenge(ctx.my_id)
    if not boot then published=nil; return end
    local scope=world.."|"..boot
    local snapshot=bonuses.snapshot(ctx.my_player.entity)
    local active=next(snapshot)~=nil
    -- Publish changes promptly. The heartbeat restores a short lease for
    -- late joiners and replicas replaced by EW without repeating item use.
    if active or wasActive or published~=scope then
        serial=serial+1
        rpc.status(world,boot,serial,snapshot)
    end
    published,wasActive=scope,active
    if dirty then GlobalsSetValue(bonuses.dirtyField,"") end
end
return M
