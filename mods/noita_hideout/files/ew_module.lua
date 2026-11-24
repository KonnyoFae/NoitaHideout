-- Loaded by EW in its own Lua state via its extra_modules API.
local api=dofile_once("mods/quant.ew/files/api/ew_api.lua")
local rpc=api.new_rpc_namespace("nh_mp")
local hook={}
local cabin=dofile_once("mods/noita_hideout/files/travel/cabin.lua")
local versionPath="mods/quant.ew/files/version.lua"
local release=dofile_once("mods/noita_hideout/files/ew_version.lua")
local supported=release and ModDoesFileExist(versionPath) and dofile_once(versionPath)=="1.6.8"
local protocol="1"
local room,ng,issuer,boot,ready,roomSeen,hostOK
local hostPreference,rescuePolicy
local lastPodParty
local peers={}
local grant,serial,repair,complete=nil,0,"-",false
local sentRequest,lastHello,lastAnnounce,lastStatus
local function get(k) return GlobalsGetValue("nh_ew."..k,"") end
local function put(k,v) GlobalsSetValue("nh_ew."..k,v) end
local function valid(s,n) return type(s)=="string" and #s>0 and #s<=n and not s:find("[^%w_%-]") end
local function online(id) return ctx.players[id] and not ctx.players[id].dc end
local function sender() return api.rpc_player_data().peer_id end
local function now() return GameGetFrameNum() end
local function nonce()
    return string.format("%04d%02d%02d%02d%02d%02d",GameGetDateAndTimeUTC()).."-"..
        tostring(math.floor(GameGetRealWorldTimeSinceStarted()*1000000))
end
local function cycle() return tostring(tonumber(SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) or 0) end
local function key() return room.."."..ng.."."..cabin.revision end
local function supportsPod()
    local options,health=ctx.proxy_opt,ctx.cap and ctx.cap.health
    return health~=nil and type(health.nh_reinforce_restore)=="function" and type(health.nh_reinforce_hold)=="function"
        and type(health.nh_reinforce_wait)=="function"
        and options.game_mode=="local_health"
        and not (options.no_notplayer or options.perma_death or options.pvp)
end
local function fullRoster()
    local owners={}
    local canRescue=true
    for id,p in pairs(ctx.players) do
        if not p.dc then
            local member=peers[id]
            if not member or member.ng~=ng or now()-member.seen>330 or owners[member.issuer] then return false end
            owners[member.issuer]=true
            if not member.pod then canRescue=false end
        end
    end
    return peers[ctx.my_id]~=nil and (ctx.is_host or online(ctx.host_id)),canRescue
end
-- The last complete pod vote can cover one missed hello for *death only*.
-- EW reuses the player_data table when projecting a polymorph, but replaces
-- it on a fresh connection. Retain the confirmed boot and issuer as well.
local function sameParty()
    if not lastPodParty or lastPodParty.room~=room or lastPodParty.host~=ctx.host_id then return false end
    local n=0
    for id,p in pairs(ctx.players) do
        if not p.dc then
            local old,member=lastPodParty.members[id],peers[id]
            if not old or old.player~=p or (member and
                (member.boot~=old.boot or member.issuer~=old.issuer or not member.pod)) then return false end
            n=n+1
        end
    end
    return n==lastPodParty.count and online(ctx.host_id)
end
local function waitOnDeath()
    local f=now()
    return lastPodParty~=nil and f>=lastPodParty.frame and f-lastPodParty.frame<=90
        and ctx.ready and not ctx.run_ended and not net.connect_failed and supportsPod()
        and ng==cycle() and issuer==get("issuer") and sameParty()
end
local function confirmPod(f)
    if not sameParty() then
        lastPodParty={room=room,host=ctx.host_id,members={},count=0}
        for id,p in pairs(ctx.players) do
            if not p.dc then
                lastPodParty.members[id]={player=p,boot=peers[id].boot,issuer=peers[id].issuer}
                lastPodParty.count=lastPodParty.count+1
            end
        end
    end
    lastPodParty.frame=f
end
-- Other Hideout EW modules use this authenticated view. Local save state and
-- item payloads never pass through the session handshake.
nh_ew_session={
    world=function() if ready and not ctx.run_ended then return room end end,
    rescue_policy=function() if ready and not ctx.run_ended then return rescuePolicy end end,
    wait_on_death=waitOnDeath,
    issuer=function(id)
        local p=peers[id]
        if ready and not ctx.run_ended and online(id) and p then return p.issuer end
    end,
    challenge=function(id)
        local p=peers[id]
        if ready and not ctx.run_ended and online(id) and p then return p.boot end
    end,
}

rpc.opts_reliable()
function rpc.hello(wire,build,owner,challenge,count,pod)
    local id=sender()
    if wire~=protocol or build~=release or not valid(owner,96) or not valid(challenge,80) or count~=ng or type(pod)~="boolean" then
        peers[id],ready,lastAnnounce,lastPodParty=nil,false,nil,nil
        put("status",""); lastStatus=""
        return
    end
    if lastPodParty then
        local old=lastPodParty.members[id]
        if not old or old.boot~=challenge or old.issuer~=owner or not pod then lastPodParty=nil end
    end
    if not peers[id] or peers[id].boot~=challenge then
        lastAnnounce=nil
        if not ctx.is_host and id==ctx.host_id then
            -- A reprojected avatar can request a fresh hello for the very
            -- same EW connection. Its previous room is still identifiable
            -- for the bounded death wait, pending the next host snapshot.
            if not lastPodParty then room=nil end
            roomSeen,hostOK,ready=nil,false,false
            put("status",""); put("ship_state",""); lastStatus=""
        end
    end
    peers[id]={issuer=owner,boot=challenge,ng=count,seen=now(),pod=pod}
end

local function publishShip(id)
    local member=peers[id]
    if not room or not member then return end
    local mode="wait"
    if grant and grant.id==id and grant.boot==member.boot then mode=grant.mode
    elseif complete then mode="done" end
    local token=grant and tostring(grant.serial) or "0"
    if id==ctx.my_id then
        put("ship_state",table.concat({key(),repair,mode,token},"|"))
        if mode=="done" and get("ship_request"):find("|ack|",1,true) then put("ship_request","") end
    else
        rpc.snapshot(id,member.boot,boot,room,ng,ready==true,repair,mode,token,rescuePolicy or "native")
    end
end

rpc.opts_reliable()
function rpc.snapshot(id,challenge,hostBoot,world,count,all,round,mode,token,policy)
    if ctx.is_host or sender()~=ctx.host_id or id~=ctx.my_id or challenge~=boot or count~=ng then return end
    if not peers[ctx.host_id] or peers[ctx.host_id].boot~=hostBoot then return end
    if not valid(world,170) or not valid(round,28) or not valid(token,35)
        or (mode~="build" and mode~="copy" and mode~="done" and mode~="wait")
        or (policy~="pod" and policy~="native") then return end
    if room~=world or policy~="pod" then lastPodParty=nil end
    room,roomSeen,hostOK=world,now(),all==true
    rescuePolicy=policy
    if not hostOK then ready=false; put("status",""); lastStatus="" end
    put("ship_state",table.concat({key(),round,mode,token},"|"))
    if mode=="done" and get("ship_request"):find("|ack|",1,true) then put("ship_request","") end
end

local function decide(id,world,count,round,action,token)
    if not ctx.is_host or not ready or not peers[id] or not online(id)
        or world~=room or count~=ng or round~=repair then return end
    if action=="ack" and grant and grant.id==id and grant.boot==peers[id].boot and tostring(grant.serial)==token then
        put("cabin_complete."..key(),repair)
        complete,grant,lastAnnounce=true,nil,nil
    elseif not grant and ((action=="ask" and not complete) or (action=="copy" and complete)) then
        serial=serial+1
        grant={id=id,boot=peers[id].boot,serial=serial,since=now(),mode=complete and "copy" or "build"}
    end
    publishShip(id)
end
rpc.opts_reliable()
function rpc.ship(world,count,round,action,token) decide(sender(),world,count,round,action,token) end

local function clear()
    room,ready,hostOK,roomSeen,ng,boot,issuer=nil,false,nil,nil,nil,nil,nil
    rescuePolicy,lastPodParty=nil,nil
    peers,grant,sentRequest,lastHello,lastAnnounce={},nil,nil,nil,nil
    put("status",""); put("ship_state",""); put("ship_request",""); put("ship_repair","")
    lastStatus=""
end
-- Saved Globals can contain the last heartbeat of an earlier process.
function hook.on_world_initialized() hostPreference=nil; clear() end
function hook.on_client_spawned(id)
    if lastPodParty then
        local old=lastPodParty.members[id]
        if not old or old.player~=ctx.players[id] then lastPodParty=nil end
    end
    peers[id]=nil; lastHello=nil; lastAnnounce=nil
end

function hook.on_world_update()
    local f=now()
    if f%5~=0 then return end
    if type(ctx.my_id)=="string" and get("local_peer")~=ctx.my_id then put("local_peer",ctx.my_id) end
    local owner=get("issuer")
    if not supported or not ctx.ready or ctx.run_ended or net.connect_failed or type(ctx.proxy_opt.share_gold)~="boolean"
        or not valid(owner,96) or not online(ctx.my_id) then
        if lastStatus~="" then clear() end
        return
    end
    local count=cycle()
    if ng~=count or issuer~=owner then
        clear()
        ng,issuer,boot=count,owner,nonce()
        if ctx.is_host then
            room=get("host_world."..issuer)
            if not valid(room,170) then
                room=issuer.."-"..boot
                put("host_world."..issuer,room)
            end
            repair=get("cabin_round."..key()); if repair=="" then repair="-" end
            complete=get("cabin_complete."..key())==repair
            put("world_mark",room)
        end
    end
    local pod=supportsPod()
    if peers[ctx.my_id] and peers[ctx.my_id].pod~=pod then lastHello=nil end
    peers[ctx.my_id]={issuer=issuer,boot=boot,ng=ng,seen=f,pod=pod}
    for id in pairs(peers) do if not online(id) then peers[id]=nil end end
    if not lastHello or f-lastHello>=90 then rpc.hello(protocol,release,issuer,boot,ng,pod); lastHello=f end
    local previous=ready
    local roster,allSupportPod=fullRoster()
    ready=roster and (ctx.is_host or (hostOK and roomSeen and f-roomSeen<=150)) or false
    if previous~=ready then lastAnnounce=nil end
    if ctx.is_host then
        if not hostPreference then
            hostPreference=ModSettingGet("noita_hideout.ew_rescue_mode")=="native" and "native" or "pod"
        end
        -- A partial snapshot can describe a same-party grace period without
        -- granting the full roster's authority to spend or revive.
        local policy=(allSupportPod and hostPreference) or (not roster and waitOnDeath() and "pod") or "native"
        if policy~=rescuePolicy then rescuePolicy,lastAnnounce=policy,nil end
        local marker,round=get("ship_repair"):match("^([^|]+)|(%d+)$")
        if marker==key() and round~=repair then
            put("cabin_round."..key(),round)
            repair,complete,grant,lastAnnounce=round,false,nil,nil
        end
        if grant and (not peers[grant.id] or grant.boot~=peers[grant.id].boot or f-grant.since>=180) then
            grant,lastAnnounce=nil,nil
        end
        if not lastAnnounce or f-lastAnnounce>=45 then
            for id in pairs(peers) do publishShip(id) end
            lastAnnounce=f
        end
    end
    if ready then
        if rescuePolicy=="pod" and allSupportPod then confirmPod(f) else lastPodParty=nil end
    end
    if ready then
        local pending=get("ship_request")
        if pending~="" and (not sentRequest or sentRequest.data~=pending or f-sentRequest.at>=30) then
            local marker,round,action,token=pending:match("^([^|]+)|([^|]+)|(%a+)|(%d+)$")
            local age=f-(tonumber(get("ship_touch")) or -1000)
            if marker==key() and (action=="ack" or ((action=="ask" or action=="copy") and age>=0 and age<=45)) then
                if ctx.is_host then decide(ctx.my_id,room,ng,round,action,token)
                else rpc.ship(room,ng,round,action,token) end
            end
            sentRequest={data=pending,at=f}
        end
        if get("world_mark")~=room then put("world_mark",room) end
        if f%15==0 or not previous then
            lastStatus=table.concat({protocol,room,ctx.proxy_opt.share_gold and "1" or "0",ctx.is_host and "h" or "g",ng,f},"|")
            put("status",lastStatus)
        end
    elseif lastStatus~="" then put("status",""); lastStatus="" end
end
return hook
