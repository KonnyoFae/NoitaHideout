-- Host journal for personal warehouse transfers. A transaction's single
-- phase record controls all of its key reservations, including after restart.
local api=dofile_once("mods/quant.ew/files/api/ew_api.lua")
local rpc=api.new_rpc_namespace("nh_pickup2")
local M={}
local prefix="noita_hideout.ew_item_tx."
local requestField="nh_ew.item_request"
local replyField="nh_ew.item_tx_reply"
local last,at

-- Use EW's native equipment switch when the selected item enters the local
-- deposit pocket. Direct writes to Inventory2's active entity are unsafe.
util.add_cross_call("ew_hideout_deposit_unselect",function(player,item)
    if not ctx.my_player or ctx.my_player.entity~=player or not EntityGetIsAlive(player)
        or not EntityGetIsAlive(item) or EntityGetRootEntity(item)~=player or EntityHasTag(player,"ew_client") then return end
    local marker=EntityGetFirstComponentIncludingDisabled(item,"VariableStorageComponent","nh_ew_deposit_lock")
    local inv=EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    if not marker or not inv then return end
    if ComponentGetValue2(inv,"mThrowItem")==item then ComponentSetValue2(inv,"mThrowItem",0) end
    if ComponentGetValue2(inv,"mActiveItem")==item or ComponentGetValue2(inv,"mActualActiveItem")==item then
        np.SetActiveHeldEntity(player,0,false,false)
    end
end)

local function validIssuer(s)
    return type(s)=="string" and #s<=40 and s:match("^%w+$")
end
local function validSerial(s)
    return type(s)=="string" and #s<=15 and s:match("^[1-9]%d*$")
end
local function validKey(key)
    if type(key)~="string" or #key>156 then return false end
    local gid=key:match("^g/(%d+)$")
    if gid then return #gid<=20 end
    return key:match("^t/ew/[%w_-]+/r/%d+/%d+/%d+/%d+/%d+/%d+$")~=nil
end
local function unpackKeys(packed)
    if type(packed)~="string" or #packed>313 then return end
    if validKey(packed) then return {packed} end
    local first,second=packed:match("^([^,]+),([^,]+)$")
    if first~=second and validKey(first) and validKey(second) then return {first,second} end
end
local function validAction(action) return action=="prepare" or action=="commit" or action=="cancel" end
local function terminal(phase) return phase=="done" or phase=="cancelled" or phase=="denied" end
local function save(field,value)
    pcall(ModSettingSet,field,value)
    return ModSettingGet(field)==value
end
local function phaseOf(field)
    local record=ModSettingGet(field)
    if type(record)=="string" then return record:match("^(%a+)|(.+)$") end
end

-- A release ticket survives EW assigning a new ground GID on each throw.
-- Looking it up must never reserve the ticket or advance the holder's journal.
local function releaseKey(key)
    return validKey(key) and key:match("^t/ew/%w+/r/")~=nil
end
local function completed(world,key)
    local base=prefix..world.."."
    local pointer=ModSettingGet(base.."key."..key)
    if type(pointer)~="string" then return "" end
    local owner,tx=pointer:match("^(%w+)|(%d+)$")
    if not validIssuer(owner) or not validSerial(tx) then return "" end
    local phase,packed=phaseOf(base..owner.."."..tx)
    if phase=="done" then
        for _,saved in ipairs(unpackKeys(packed) or {}) do if saved==key then return pointer end end
    end
    return ""
end
local function current(peer,world,holder,boot,hostBoot)
    return nh_ew_session and world and nh_ew_session.world()==world and validIssuer(holder)
        and nh_ew_session.issuer(peer)==holder and boot and nh_ew_session.challenge(peer)==boot
        and hostBoot and nh_ew_session.challenge(ctx.host_id)==hostBoot
end
local scope,checked,lastPrune=nil,{},0
rpc.opts_reliable()
function rpc.release_proof(peer,world,holder,boot,hostBoot,key,winner)
    if ctx.rpc_peer_id~=ctx.host_id or peer~=ctx.my_id or not current(peer,world,holder,boot,hostBoot)
        or scope~=table.concat({world,holder,boot,hostBoot},"|") or not releaseKey(key) or not checked[key] then return end
    if winner~="" then
        if type(winner)~="string" then return end
        local owner,tx=winner:match("^(%w+)|(%d+)$")
        if not validIssuer(owner) or not validSerial(tx) then return end
    end
    -- A delayed negative from before the commit cannot revoke a done receipt.
    if not checked[key].winner or checked[key].winner=="" then checked[key].winner=winner end
end
rpc.opts_reliable()
function rpc.release_probe(world,holder,boot,hostBoot,key)
    local peer=ctx.rpc_peer_id
    if ctx.is_host and current(peer,world,holder,boot,hostBoot) and releaseKey(key) then
        rpc.release_proof(peer,world,holder,boot,hostBoot,key,completed(world,key))
    end
end
util.add_cross_call("ew_hideout_release_winner",function(world,holder,key)
    if not nh_ew_session or not releaseKey(key) then return end
    local boot,hostBoot=nh_ew_session.challenge(ctx.my_id),nh_ew_session.challenge(ctx.host_id)
    if not current(ctx.my_id,world,holder,boot,hostBoot) then return end
    local session=table.concat({world,holder,boot,hostBoot},"|")
    local frame=GameGetFrameNum()
    if session~=scope or frame<lastPrune then scope,checked,lastPrune=session,{},frame end
    if frame-lastPrune>=600 then
        for k,entry in pairs(checked) do if frame-entry.seen>=600 then checked[k]=nil end end
        lastPrune=frame
    end
    local entry=checked[key]
    if not entry then entry={};checked[key]=entry end
    entry.seen=frame
    if entry.winner and entry.winner~="" then
        GlobalsSetValue("nh_ew.release_winner",entry.winner)
    elseif not entry.sent or frame<entry.sent or frame-entry.sent>=(entry.winner=="" and 300 or 90) then
        entry.sent=frame
        if ctx.is_host then
            entry.winner=completed(world,key)
            if entry.winner~="" then GlobalsSetValue("nh_ew.release_winner",entry.winner) end
        else
            rpc.release_probe(world,holder,boot,hostBoot,key)
        end
    end
end)

-- Key pointers are indexes. A cancelled/denied transaction's pointers are
-- immediately reusable even when the host exited before any further writes.
local function available(base,world,key,holder)
    local oldWinner=ModSettingGet("noita_hideout.ew_claim."..world.."."..key)
    if oldWinner~=nil and oldWinner~=holder:match("^(%w+)|") then return false end
    local pointer=ModSettingGet(base.."key."..key)
    if pointer==nil or pointer==holder then return true end
    if type(pointer)~="string" then return false end
    local owner,number=pointer:match("^(%w+)|(%d+)$")
    if not validIssuer(owner) or not validSerial(number) then return false end
    local phase=phaseOf(base..owner.."."..number)
    return phase=="cancelled" or phase=="denied"
end

local function decide(peer,world,issuer,tx,packed,action)
    if not ctx.is_host or not nh_ew_session or type(world)~="string" or nh_ew_session.world()~=world
        or not validIssuer(issuer) or nh_ew_session.issuer(peer)~=issuer
        or not validSerial(tx) or not validAction(action) then return end
    local keys=unpackKeys(packed)
    if not keys then return end
    local base=prefix..world.."."
    local history=base..issuer.."."
    local entry=history..tx
    local phase,identities=phaseOf(entry)
    if identities and identities~=packed then return "denied" end
    if terminal(phase) then return phase end
    local head=ModSettingGet(history.."latest")
    if head~=tx then
        if head~=nil then
            if not validSerial(head) then return end
            if tonumber(tx)<tonumber(head) then return "denied" end
            if not terminal(phaseOf(history..head)) then return end
        end
        -- An early or reordered commit cannot create a grant.
        if action=="commit" or not save(history.."latest",tx) then return end
    end
    local function setPhase(nextPhase)
        if save(entry,nextPhase.."|"..packed) then return nextPhase end
    end
    if action=="cancel" then return setPhase("cancelled") end
    if phase=="granted" then return action=="prepare" and phase or setPhase("done") end
    if action~="prepare" then return end
    if phase~="preparing" and not setPhase("preparing") then return end
    local holder=issuer.."|"..tx
    for _,key in ipairs(keys) do
        if not available(base,world,key,holder) then return setPhase("denied") end
    end
    for _,key in ipairs(keys) do
        local index=base.."key."..key
        if ModSettingGet(index)~=holder and not save(index,holder) then return end
    end
    return setPhase("granted")
end

local function identity(world,issuer,tx,packed)
    return table.concat({world,issuer,tx,packed},"|")
end
local function receive(world,issuer,tx,packed,phase)
    if not nh_ew_session or nh_ew_session.world()~=world or nh_ew_session.issuer(ctx.my_id)~=issuer
        or not validIssuer(issuer) or not validSerial(tx) or not unpackKeys(packed)
        or (phase~="granted" and not terminal(phase)) then return end
    local id=identity(world,issuer,tx,packed).."|"
    if GlobalsGetValue(requestField,""):sub(1,#id)~=id then return end
    local previous=GlobalsGetValue(replyField,"")
    if previous:sub(1,#id)==id and terminal(previous:sub(#id+1)) then return end
    GlobalsSetValue(replyField,id..phase)
end
rpc.opts_reliable()
function rpc.reply(peer,world,issuer,tx,packed,phase)
    if ctx.rpc_peer_id==ctx.host_id and peer==ctx.my_id then receive(world,issuer,tx,packed,phase) end
end
rpc.opts_reliable()
function rpc.request(world,issuer,tx,packed,action)
    local peer=ctx.rpc_peer_id
    local phase=decide(peer,world,issuer,tx,packed,action)
    if phase then rpc.reply(peer,world,issuer,tx,packed,phase) end
end
function M.on_world_initialized() last,at=nil,nil;scope,checked,lastPrune=nil,{},0 end
function M.on_world_update()
    local f=GameGetFrameNum()
    if f%4~=0 or not nh_ew_session then return end
    local request=GlobalsGetValue(requestField,"")
    if request=="" then last=nil;return end
    local world,issuer,tx,packed,action=request:match("^([%w_-]+)|(%w+)|(%d+)|([^|]+)|(%a+)$")
    if world~=nh_ew_session.world() or issuer~=nh_ew_session.issuer(ctx.my_id) or not validIssuer(issuer)
        or not validSerial(tx) or not validAction(action) or not unpackKeys(packed) then return end
    local id=identity(world,issuer,tx,packed).."|"
    local reply=GlobalsGetValue(replyField,"")
    local result=reply:sub(1,#id)==id and reply:sub(#id+1)
    if terminal(result) or (action=="prepare" and result=="granted") then
        GlobalsSetValue(requestField,"")
        last=nil
    elseif request~=last or f<at or f-at>=60 then
        last,at=request,f
        if ctx.is_host then
            local phase=decide(ctx.my_id,world,issuer,tx,packed,action)
            if phase then receive(world,issuer,tx,packed,phase) end
        else
            rpc.request(world,issuer,tx,packed,action)
        end
    end
end
return M
