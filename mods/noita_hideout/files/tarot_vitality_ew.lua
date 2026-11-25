-- Enemies may be simulated on a different machine from their killer. Only the
-- enemy owner sends credit; the player owner decides whether their card is active.
local api=dofile_once("mods/quant.ew/files/api/ew_api.lua")
local vitality=dofile_once("mods/noita_hideout/files/tarot_vitality.lua")
local rpc=api.new_rpc_namespace("nh_devil_kill")
local serial,received=0,{}

util.add_cross_call("ew_hideout_devil_kill",function(replica)
    local world=nh_ew_session and nh_ew_session.world()
    local target=ctx.player_data_by_local_entity[replica]
    if not world or not target or target.entity~=replica or target.dc or target.peer_id==ctx.my_id then return end
    local sourceBoot=nh_ew_session.challenge(ctx.my_id)
    local targetBoot=nh_ew_session.challenge(target.peer_id)
    if sourceBoot and targetBoot then
        serial=serial+1
        rpc.credit(world,sourceBoot,target.peer_id,targetBoot,serial)
    end
end)

rpc.opts_reliable()
function rpc.credit(world,sourceBoot,peer,targetBoot,number)
    if peer~=ctx.my_id or not world or not nh_ew_session or nh_ew_session.world()~=world
        or not targetBoot or nh_ew_session.challenge(peer)~=targetBoot or not ctx.my_player then return end
    local source=api.rpc_player_data()
    if not source or source.peer_id==peer or not sourceBoot or nh_ew_session.challenge(source.peer_id)~=sourceBoot
        or type(number)~="number" or number<1 or number~=math.floor(number) then return end
    local last=received[source.peer_id]
    if last and last.world==world and last.boot==sourceBoot and number<=last.number then return end
    received[source.peer_id]={world=world,boot=sourceBoot,number=number}
    vitality.healKill(ctx.my_player.entity)
end
return {}
