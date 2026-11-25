local api=dofile_once("mods/quant.ew/files/api/ew_api.lua")
local bell=dofile_once("mods/noita_hideout/files/salvage_bell.lua")
local rpc=api.new_rpc_namespace("nh_salvage_bell")
local M={}
local serial,lastRing=0,{}
local published

local function source(world,boot)
    if not world or not boot or not nh_ew_session or nh_ew_session.world()~=world then return end
    local peer=api.rpc_player_data()
    if peer and not peer.dc and peer.peer_id~=ctx.my_id and boot==nh_ew_session.challenge(peer.peer_id) then return peer end
end

local function coordinate(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end

rpc.opts_reliable()
function rpc.ring(world,boot,sequence,x,y)
    local peer=source(world,boot)
    if not peer or not coordinate(x) or not coordinate(y) or type(sequence)~="number"
        or sequence<1 or sequence>=math.huge or sequence~=math.floor(sequence) then return end
    local prior=lastRing[peer.peer_id]
    if prior and prior.world==world and prior.boot==boot and sequence<=prior.sequence then return end
    lastRing[peer.peer_id]={world=world,boot=boot,sequence=sequence}
    bell.pull(x,y,true)
    bell.sound(x,y)
end

function M.on_world_initialized()
    published=nil
    GlobalsSetValue(bell.bridgeField,"")
    GlobalsSetValue(bell.requestField,"")
end

function M.on_world_update()
    local frame=GameGetFrameNum()
    if frame%5~=0 then return end
    local world=ctx.my_player and nh_ew_session and nh_ew_session.world()
    local boot=world and nh_ew_session.challenge(ctx.my_id)
    local scope=boot and world.."|"..boot or ""
    if scope~=published or scope~="" and frame%30==0 then
        GlobalsSetValue(bell.bridgeField,scope~="" and scope.."|"..frame or "")
        published=scope
    end
    local request=GlobalsGetValue(bell.requestField,"")
    if request~="" then
        local key,when,x,y=request:match("^([^|]+|[^|]+)|(%d+)|([^|]+)|([^|]+)$")
        when,x,y=tonumber(when),tonumber(x),tonumber(y)
        if scope==key and when and frame>=when and frame-when<=180 and coordinate(x) and coordinate(y) then
            serial=serial+1
            rpc.ring(world,boot,serial,x,y)
        end
        -- A temporary disconnect may recover inside the same session. Keep the
        -- request for up to three seconds until its original handshake returns.
        if scope~="" or not when or when>frame or frame-when>180 then GlobalsSetValue(bell.requestField,"") end
    end
end

return M
