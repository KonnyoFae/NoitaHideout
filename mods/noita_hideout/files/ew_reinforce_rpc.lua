-- Runs in EW's VM. The host binds one payer to a downed body. Only the
-- machine owning that body can run EW's restore or acknowledge its result.
local version="mods/quant.ew/files/version.lua"
if not ModDoesFileExist(version) or dofile_once(version)~="1.6.8" then return {} end
local api=dofile_once("mods/quant.ew/files/api/ew_api.lua")
local pod=dofile_once("mods/noita_hideout/files/resupply.lua")
local waiting=dofile_once("mods/noita_hideout/files/ew_waiting.lua")
local rpc=api.new_rpc_namespace("nh_reinforce1")
local M={}
local prefix="nh_ew.reinforce_"
local ledger="noita_hideout.ew_reinforce."
local room,seen,lastAdvert,lastRequest,lastFrame,published,publishedMode,lastRollback,boot
local lastUpgrade

local function read(key) return GlobalsGetValue(prefix..key,"") end
local function write(key,value) GlobalsSetValue(prefix..key,value) end
local function save(key,value)
    pcall(ModSettingSet,key,value)
    return ModSettingGet(key)==value
end
local function id(s)
    return type(s)=="string" and #s<=40 and s:match("^%w+$")~=nil
end
local function number(s)
    return type(s)=="string" and #s<=15 and s:match("^[1-9]%d*$")~=nil
end
local function position(n)
    return type(n)=="number" and n==math.floor(n) and math.abs(n)<1073741824
end
local function world()
    -- Authenticated peers may settle an old order even when a resumed
    -- room selects native revival or changes health modes.
    if not nh_ew_session or not nh_ew_session.rescue_policy or not ctx.ready or ctx.run_ended then return end
    if not nh_ew_session.rescue_policy() then return end
    return nh_ew_session.world()
end
local function normalMode()
    return ctx.ready and not ctx.run_ended and ctx.cap.health and ctx.cap.health.nh_reinforce_restore~=nil
        and ctx.proxy_opt.game_mode=="local_health" and not ctx.proxy_opt.no_notplayer
        and not ctx.proxy_opt.perma_death and not ctx.proxy_opt.pvp
        and not GameHasFlagRun("ending_game_completed") and not GameHasFlagRun("ew_kill_player")
end
local function podActive()
    return normalMode() and world()~=nil and nh_ew_session.rescue_policy()=="pod"
end
local function waitOnDeath()
    if not normalMode() or not nh_ew_session then return false end
    if nh_ew_session.wait_on_death then return nh_ew_session.wait_on_death()==true end
    return podActive()
end
local function current(field) return seen and field~=nil and field==room and field==world() end
local function owner(peer) return nh_ew_session.issuer(peer) end
local function peerFor(who)
    for peer,p in pairs(ctx.players) do
        if not p.dc and owner(peer)==who then return peer end
    end
end
local function tag(entity,name)
    return EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",name)
end
local function localBody()
    local p=ctx.my_player and ctx.my_player.entity
    if p and EntityGetIsAlive(p) and GameHasFlagRun("ew_flag_notplayer_active")
        and EntityHasTag(p,"ew_notplayer") and not EntityHasTag(p,"ew_client") then return p end
end
-- EW already sets wait_for_kill_flag_on_death on the local polymorphed
-- body and retains its inventory. Repair the HP on that same body, never
-- remove its effects, change its max HP, or mark the player alive.
local function holdDowned()
    local body=localBody()
    if waiting.isAnchor(body) then return true end
    if not body or not (podActive() or (normalMode() and waiting.pendingLegacy(body)))
        or GlobalsGetValue("ew_local_player_dead","")=="" then return false end
    local dm=EntityGetFirstComponentIncludingDisabled(body,"DamageModelComponent")
    if not dm then return false end
    if ComponentGetValue2(dm,"hp")<=0 then
        ComponentSetValue2(dm,"hp",math.max(2^-20,ComponentGetValue2(dm,"max_hp")))
    end
    return true
end
if ctx.cap.health and ctx.cap.health.nh_reinforce_restore then
    ctx.cap.health.nh_reinforce_hold=holdDowned
    if ctx.cap.health.nh_reinforce_native then ctx.cap.health.nh_reinforce_wait=waitOnDeath end
end
waiting.installSpawnGuard()
function M.on_local_player_spawn(p) waiting.onSpawn(p) end
local function reconcile(f)
    if not GameHasFlagRun("ew_flag_notplayer_active") then return end
    local body=localBody()
    if not body or ctx.run_ended or GameHasFlagRun("ending_game_completed") then return end
    local active=podActive()
    if not waiting.isAnchor(body) then
        if (active or waiting.pendingLegacy(body)) and (not lastUpgrade or lastUpgrade.body~=body or f-lastUpgrade.frame>=60) then
            lastUpgrade={body=body,frame=f}
            if not waiting.upgrade(body) and nh_ew_session and nh_ew_session.rescue_policy
                and nh_ew_session.rescue_policy()=="native" then waiting.releaseLegacy(body) end
        end
        return
    end
    if active then return end
    local policy=nh_ew_session and nh_ew_session.rescue_policy and nh_ew_session.rescue_policy()
    if policy~="native" then return end -- keep an existing wait through any handshake gap
    if ctx.cap.health and ctx.cap.health.nh_reinforce_native then
        ctx.cap.health.nh_reinforce_native()
    else
        -- Shared health has no downed-body mechanic. Its current HP remains
        -- authoritative when restoring the retained body into that mode.
        waiting.restore(body,false)
    end
end
local function callerSite()
    local player=ctx.my_player and ctx.my_player.entity
    return player~=nil and EntityGetIsAlive(player) and not GameHasFlagRun("ew_flag_notplayer_active")
end
local function deathPosition(body)
    local c=tag(body,"nh_ew_death_position")
    local x,y
    if c then x,y=ComponentGetValue2(c,"value_string"):match("^(-?%d+)|(-?%d+)$") end
    if x and position(tonumber(x)) and position(tonumber(y)) then return tonumber(x),tonumber(y) end
    x,y=EntityGetTransform(body); x,y=math.floor(x),math.floor(y)
    EntityAddComponent2(body,"VariableStorageComponent",{_tags="nh_ew_death_position",value_string=x.."|"..y})
    return x,y
end
local function fresh(challenge,stamp)
    local age=type(stamp)=="number" and GameGetFrameNum()-stamp
    return boot and challenge==boot and age and age>=0 and age<=120
end
local function receiptQuery(challenge,stamp,approved)
    -- A query cannot authorize a delivery. The handshake's peer/boot token
    -- remains available in native mode without reinforcement heartbeats.
    return stamp==false and approved==false and not podActive()
        and type(challenge)=="string" and challenge~=""
        and nh_ew_session.challenge(ctx.my_id)==challenge
end
local function episode(who,body)
    if not body then return end
    local c=tag(body,"nh_ew_reinforce_episode")
    local stamp=room.."|"..who.."|"
    local value=c and ComponentGetValue2(c,"value_string") or ""
    if value:sub(1,#stamp)==stamp and number(value:sub(#stamp+1)) then return value:sub(#stamp+1) end
    local counter=ledger..room.."."..who..".seq"
    local n=(tonumber(ModSettingGet(counter)) or 0)+1
    local serial=("%.0f"):format(n)
    if not number(serial) or not save(counter,serial) then return end
    if not c then c=EntityAddComponent2(body,"VariableStorageComponent",{_tags="nh_ew_reinforce_episode"}) end
    if c and c~=0 then
        ComponentSetValue2(c,"value_string",stamp..serial)
        if ComponentGetValue2(c,"value_string")==stamp..serial then return serial end
    end
end
local function scope(who,episodeId) return ledger..room.."."..who..".down."..episodeId end
local function hostKey(caller,tx) return ledger..room.."."..caller..".order."..tx end
local function payload(target,ep,x,y) return table.concat({target,ep,x,y},"|") end
local function result(field,own,tx,status)
    if field==world() and owner(ctx.my_id)==own and number(tx) and (status=="ok" or status=="rejected" or status=="transferred") then
        write("result."..field.."."..own.."."..tx,status)
    end
end
rpc.opts_reliable()
function rpc.result(to,field,tx,status)
    if ctx.rpc_peer_id==ctx.host_id then result(field,to,tx,status) end
end
local function answer(caller,tx,status)
    if owner(ctx.my_id)==caller then result(room,caller,tx,status) else rpc.result(caller,room,tx,status) end
end
local function originalResult(key,status)
    if (ModSettingGet(key..".sponsor") or ""):match("^paid|") then return "transferred" end
    return status
end
local function confirm(peer,field,caller,tx,target,ep,x,y,status)
    if not ctx.is_host or not current(field) or not id(caller) or not number(tx) or not id(target)
        or owner(peer)~=target or not number(ep) or not position(x) or not position(y)
        or (status~="ok" and status~="rejected") then return end
    local key=hostKey(caller,tx)
    local plan=payload(target,ep,x,y)
    local winner=caller.."|"..tx
    if ModSettingGet(scope(target,ep)..".owner")~=winner then return end
    if ModSettingGet(key)==plan.."|pending" and save(key,plan.."|"..status) then
        if status=="rejected" then save(scope(target,ep)..".owner","") end
        answer(caller,tx,originalResult(key,status))
    end
end
rpc.opts_reliable()
function rpc.confirm(...) confirm(ctx.rpc_peer_id,...) end
local function toHost(caller,tx,target,ep,x,y,status)
    if ctx.is_host then confirm(ctx.my_id,room,caller,tx,target,ep,x,y,status)
    else rpc.confirm(room,caller,tx,target,ep,x,y,status) end
end

local function restore(body,x,y)
    -- A natural kill may already be queued. An empty serialization cannot
    -- restore the original inventory, so never enter EW's destructive path.
    local dm=EntityGetFirstComponentIncludingDisabled(body,"DamageModelComponent")
    if not podActive() or GlobalsGetValue("ew_local_player_dead","")=="" then return false end
    if not waiting.isAnchor(body) and (not dm or (ComponentGetValue2(dm,"hp")<=0 and not holdDowned())) then return false end
    local ok=pcall(ctx.cap.health.nh_reinforce_restore)
    local player=ctx.my_player.entity
    if not ok and player==body and EntityGetIsAlive(body) and GameHasFlagRun("ew_flag_notplayer_active") then return false end
    if not player or player==body or not EntityGetIsAlive(player)
        or GameHasFlagRun("ew_flag_notplayer_active") or EntityHasTag(player,"ew_notplayer") then
        if not ok then return nil end -- neither the saved body nor a verified delivery
        return false
    end
    local health=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not health then return false end
    EntitySetTransform(player,x,y)
    local motion=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
    if motion then ComponentSetValue2(motion,"mVelocity",0,0) end
    ComponentSetValue2(health,"hp",ComponentGetValue2(health,"max_hp"))
    return true
end
local flight,blockedAt,flightSerial=nil,nil,0
local function endFlight(opened)
    local f=flight
    if f then
        GlobalsSetValue("nh_ew.pod_end",table.concat({f.room,f.ng,f.effect,GameGetFrameNum(),
            opened and "open" or "cancel",f.site.y},"|"))
    end
    flight=nil
end
local function sealed(caller,tx,target,ep)
    return ModSettingGet(scope(target,ep)..".stop."..caller.."."..tx)=="sealed"
end
local function beginFlight(body,caller,tx,target,ep,x,y,paid,sponsored)
    if flight then return end
    local ox,oy=deathPosition(body)
    local key=scope(target,ep)..".landing"
    local moved=ModSettingGet(key) or ""
    local who,order,sx,sy=moved:match("^(%w+)|(%d+)|(-?%d+)|(-?%d+)$")
    local site
    if who==caller and order==tx then
        sx,sy=tonumber(sx),tonumber(sy)
        if position(sx) and position(sy) then
            site=pod.reviveSite(sx,sy,body)
            if not site and waiting.isAnchor(body) and not DoesWorldExistAt(sx-7,sy-15,sx+7,sy+8) then
                -- This fixed observer carries StreamingKeepAlive even after a reload.
                EntitySetTransform(body,sx,sy)
            end
        end
    end
    if not site then site=pod.reviveSite(ox,oy,body) end
    if not site then
        blockedAt=GameGetFrameNum()
        if read("needs_site")~=ep then
            write("needs_site",ep)
            GamePrint(GameTextGet("$nh_hideout_ew_redirect_pod"))
        end
        return
    end
    blockedAt=nil
    write("needs_site","")
    local now=GameGetFrameNum()
    local ng=tonumber(SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) or 0
    flightSerial=flightSerial+1
    local effect=now.."."..flightSerial
    local height,speed,ticks=site.y-site.start,1,0
    while height>0 do speed=math.min(5,speed+0.18);height=height-speed;ticks=ticks+1 end
    flight={room=room,body=body,caller=caller,tx=tx,target=target,ep=ep,x=x,y=y,site=site,
        ng=ng,effect=effect,opens=now+ticks,paid=paid,sponsored=sponsored}
    GlobalsSetValue("nh_ew.pod_start",table.concat({room,ng,effect,now,site.x,site.start,site.y},"|"))
end
local function landingTick()
    local f=flight
    if not f then return end
    local body=localBody()
    if f.room~=world() or not podActive() or body~=f.body or episode(f.target,body)~=f.ep
        or (not f.paid and not f.sponsored and sealed(f.caller,f.tx,f.target,f.ep)) then
        endFlight(false);return
    end
    if GameGetFrameNum()<f.opens then return end
    if not pod.reviveSpace(f.site.x,f.site.y,body) then endFlight(false);return end
    local key=scope(f.target,f.ep)..".receipt"
    local entry=table.concat({f.caller,f.tx,f.x,f.y},"|")
    if not f.paid then
        local prior=ModSettingGet(key)
        if prior==entry.."|rejected" or (prior and prior~=entry.."|pending" and not prior:match("|rejected$"))
            or not save(key,entry.."|pending") then endFlight(false);return end
    end
    local restored=restore(body,f.site.x,f.site.y)
    endFlight(restored==true)
    if f.paid then return end
    if restored==nil then
        GlobalsSetValue(key,entry.."|uncertain")
        save(key,entry.."|uncertain")
        return
    end
    local status=restored and "ok" or "rejected"
    if restored then GlobalsSetValue(key,entry.."|ok") end
    if save(key,entry.."|"..status) then toHost(f.caller,f.tx,f.target,f.ep,f.x,f.y,status) end
end
local function command(from,field,caller,tx,target,ep,x,y,challenge,stamp,approved,sponsored)
    if from~=ctx.host_id or not current(field) or owner(ctx.my_id)~=target or not id(target)
        or not id(caller) or caller==target or not number(tx) or not number(ep) or not position(x) or not position(y)
        or type(approved)~="boolean" or not (fresh(challenge,stamp) or receiptQuery(challenge,stamp,approved)) then return end
    local key=scope(target,ep)..".receipt"
    local entry=table.concat({caller,tx,x,y},"|")
    local prior=ModSettingGet(key)
    local worldReceipt=GlobalsGetValue(key,"")
    if prior==entry.."|ok" or worldReceipt==entry.."|ok" then
        if prior~=entry.."|ok" and not save(key,entry.."|ok") then return end
        toHost(caller,tx,target,ep,x,y,"ok")
        return
    end
    if prior==entry.."|uncertain" or worldReceipt==entry.."|uncertain" then return end
    if sponsored~=true and sealed(caller,tx,target,ep) then return end
    if prior==entry.."|rejected" then toHost(caller,tx,target,ep,x,y,"rejected"); return end
    if prior and prior~=entry.."|pending" and not prior:match("|rejected$") then
        toHost(caller,tx,target,ep,x,y,"rejected"); return
    end
    local body=localBody()
    if not podActive() or not body or episode(target,body)~=ep or not approved then
        if save(key,entry.."|rejected") then toHost(caller,tx,target,ep,x,y,"rejected") end
        return
    end
    beginFlight(body,caller,tx,target,ep,x,y,false,sponsored==true)
end
rpc.opts_reliable()
function rpc.command(...) command(ctx.rpc_peer_id,...) end
local function sendCommand(peer,caller,tx,target,ep,x,y,challenge,stamp,approved,sponsored)
    if peer==ctx.my_id then command(ctx.host_id,room,caller,tx,target,ep,x,y,challenge,stamp,approved,sponsored)
    else rpc.command(room,caller,tx,target,ep,x,y,challenge,stamp,approved,sponsored) end
end
-- The order and its recipient never change. The host can move the debit to
-- another profile only after the recipient durably fences the old delivery.
local function parseOrder(order)
    if type(order)~="string" then return end
    local field,caller,tx,target,ep,x,y=order:match("^([%w_-]+)|(%w+)|(%d+)|(%w+)|(%d+)|(-?%d+)|(-?%d+)$")
    x,y=tonumber(x),tonumber(y)
    if current(field) and id(caller) and id(target) and caller~=target and number(tx) and number(ep)
        and position(x) and position(y) then return caller,tx,target,ep,x,y end
end
local function hostOwns(caller,tx,target,ep)
    return ModSettingGet(scope(target,ep)..".owner")==caller.."|"..tx
end
local function fenceReport(peer,order,status)
    if not ctx.is_host then return end
    local caller,tx,target,ep,x,y=parseOrder(order)
    if not caller or owner(peer)~=target or not hostOwns(caller,tx,target,ep) then return end
    local key=hostKey(caller,tx)
    local stage=ModSettingGet(key..".sponsor")
    if ModSettingGet(key)~=payload(target,ep,x,y).."|pending" or not stage or stage:match("^paid|") then return end
    if status=="sealed" and podActive() then
        if stage=="sealing" then save(key..".sponsor","choose") end
    elseif status=="ok" or status=="rejected" or (status=="sealed" and not podActive()) then
        confirm(peer,room,caller,tx,target,ep,x,y,status=="ok" and "ok" or "rejected")
    end
end
rpc.opts_reliable()
function rpc.fenceReport(order,status) fenceReport(ctx.rpc_peer_id,order,status) end
local function fence(from,order)
    local caller,tx,target,ep,x,y=parseOrder(order)
    if from~=ctx.host_id or not caller or owner(ctx.my_id)~=target then return end
    local base=scope(target,ep)
    local key=base..".receipt"
    local entry=table.concat({caller,tx,x,y},"|")
    local profile,worldProof=ModSettingGet(key),GlobalsGetValue(key,"")
    local status
    if profile==entry.."|ok" or worldProof==entry.."|ok" then
        if profile~=entry.."|ok" and not save(key,entry.."|ok") then return end
        status="ok"
    elseif profile==entry.."|uncertain" or worldProof==entry.."|uncertain" then return
    elseif profile==entry.."|rejected" then status="rejected"
    else
        local body=localBody()
        if profile==entry.."|pending" and (not body or episode(target,body)~=ep) then return end
        if not save(base..".stop."..caller.."."..tx,"sealed") then return end
        status=body and episode(target,body)==ep and "sealed" or "rejected"
    end
    if ctx.is_host then fenceReport(ctx.my_id,order,status) else rpc.fenceReport(order,status) end
end
rpc.opts_reliable()
function rpc.fence(order) fence(ctx.rpc_peer_id,order) end

local offerAt,lastSponsorReply,sponsorReplyAt
local function offered(from,to,order)
    local caller=parseOrder(order)
    if from~=ctx.host_id or not caller or owner(ctx.my_id)~=to or not podActive() then return end
    write("sponsor_offer",order);offerAt=GameGetFrameNum()
end
rpc.opts_reliable()
function rpc.sponsorOffer(to,order) offered(ctx.rpc_peer_id,to,order) end
local function sponsorResult(from,to,order,debit,status)
    local caller,tx=parseOrder(order)
    if from~=ctx.host_id or not caller or owner(ctx.my_id)~=to or not number(debit)
        or (status~="ok" and status~="rejected") then return end
    write("sponsor_result."..room.."."..caller.."."..tx.."."..to.."."..debit,status)
    if read("sponsor_offer")==order then write("sponsor_offer","");offerAt=nil end
end
rpc.opts_reliable()
function rpc.sponsorResult(...) sponsorResult(ctx.rpc_peer_id,...) end
local function livingParty()
    local waitingForStatus=false
    for _,p in pairs(ctx.players) do
        if not p.dc then
            if p.status and p.status.is_alive==true then return true end
            if not p.status or p.status.is_alive==nil then waitingForStatus=true end
        end
    end
    if not waitingForStatus then return false end
end
local function eligible(peer,target)
    local p=ctx.players[peer]
    if not p or p.dc then return false end
    if owner(peer)==target then return true end
    local row=seen[peer]
    if not p.status or p.status.is_alive==nil or not row or GameGetFrameNum()-row.at>120 then return end
    return p.status.is_alive and row.ep==""
end
local function drivePaid(target,caller,tx,ep,x,y)
    local peer=peerFor(target)
    if not peer then return end
    local row=seen[peer]
    if podActive() then
        local live=livingParty()
        if live~=nil and row and GameGetFrameNum()-row.at<=120 then
            sendCommand(peer,caller,tx,target,ep,x,y,row.boot,row.stamp,live,true)
        end
    else
        local challenge=nh_ew_session.challenge(peer)
        if challenge then sendCommand(peer,caller,tx,target,ep,x,y,challenge,false,false,true) end
    end
end
local function sponsorReply(peer,order,debit)
    if not ctx.is_host or (debit~="none" and not number(debit)) then return end
    local caller,tx,target,ep,x,y=parseOrder(order)
    local payer=owner(peer)
    if not caller or not payer then return end
    local key=hostKey(caller,tx)
    local record=ModSettingGet(key)
    local plan=payload(target,ep,x,y)
    local stage=ModSettingGet(key..".sponsor")
    local locked=record==plan.."|pending" and hostOwns(caller,tx,target,ep)
    local void=key..".void."..payer.."."..debit
    local offered=locked and stage=="offer|"..payer and podActive()
    if offered then
        local live,canPay=livingParty(),eligible(peer,target)
        if live==nil or canPay==nil then return end
        offered=live and canPay
    end
    if offered and not ModSettingGet(void) then
        if debit=="none" then
            if save(key..".declined."..payer,true) then save(key..".sponsor","choose") end
            return
        end
        stage="paid|"..payer.."|"..debit
        if not save(key..".sponsor",stage) then return end
        answer(caller,tx,"transferred")
    end
    if debit=="none" then return end
    local status="rejected"
    if stage=="paid|"..payer.."|"..debit then
        if record==plan.."|pending" then drivePaid(target,caller,tx,ep,x,y);return end
        if record==plan.."|ok" then status="ok"
        elseif record~=plan.."|rejected" then return end
    elseif locked and not (stage and stage:match("^paid|")) then
        -- Once a profile was told to refund this debit, a delayed copy must
        -- never become payable if the host subsequently offers it the order.
        if not ModSettingGet(void) and not save(void,true) then return end
    end
    if peer==ctx.my_id then sponsorResult(ctx.host_id,payer,order,debit,status)
    else rpc.sponsorResult(payer,order,debit,status) end
end
rpc.opts_reliable()
function rpc.sponsorReply(order,debit) sponsorReply(ctx.rpc_peer_id,order,debit) end

local function candidate(key,caller,target,where)
    if peerFor(target) and not ModSettingGet(key..".declined."..target) then return target end
    local nearest,dist
    for peer,p in pairs(ctx.players) do
        if not p.dc then
            local who=owner(peer)
            if not who then return nil end -- roster handshake changing
            if who~=caller and not ModSettingGet(key..".declined."..who) then
                local canPay=eligible(peer,target)
                if canPay==nil then return nil end
                if canPay then
                    local row=seen[peer]
                    local d=(row.x-where.x)^2+(row.y-where.y)^2
                    if not nearest or d<dist or (d==dist and who<nearest) then nearest,dist=who,d end
                end
            end
        end
    end
    return nearest or false
end
local function noticeAck(peer,order)
    local caller,tx,target,ep=parseOrder(order)
    if not ctx.is_host or not caller or owner(peer)~=target then return end
    local key=scope(target,ep)..".no_payer"
    if ModSettingGet(key)==caller.."|"..tx then save(key,"") end
end
rpc.opts_reliable()
function rpc.noticeAck(order) noticeAck(ctx.rpc_peer_id,order) end
local function noPayer(from,order)
    local caller,tx,target,ep=parseOrder(order)
    if from~=ctx.host_id or not caller or owner(ctx.my_id)~=target then return end
    local body=localBody()
    if not body or episode(target,body)~=ep then return end
    local key=scope(target,ep)..".notified."..caller.."."..tx
    if not ModSettingGet(key) then
        if not save(key,true) then return end
        GamePrint(GameTextGet("$nh_hideout_ew_no_sponsor"))
    end
    if ctx.is_host then noticeAck(ctx.my_id,order) else rpc.noticeAck(order) end
end
rpc.opts_reliable()
function rpc.noPayer(order) noPayer(ctx.rpc_peer_id,order) end
local function pendingNotice(row,peer)
    local token=ModSettingGet(scope(row.owner,row.ep)..".no_payer") or ""
    local caller,tx=token:match("^(%w+)|(%d+)$")
    if not caller then return end
    local plan,status=(ModSettingGet(hostKey(caller,tx)) or ""):match("^(.*)|(%a+)$")
    if status~="rejected" then return end
    local order=room.."|"..token.."|"..plan
    if peer==ctx.my_id then noPayer(ctx.host_id,order) else rpc.noPayer(order) end
end
local function handoff(row,targetPeer)
    local target,ep=row.owner,row.ep
    local winner=ModSettingGet(scope(target,ep)..".owner") or ""
    local caller,tx=winner:match("^(%w+)|(%d+)$")
    if not caller then return end
    local key=hostKey(caller,tx)
    local plan,status=(ModSettingGet(key) or ""):match("^(.*)|(%a+)$")
    if status~="pending" then return end
    local stageKey=key..".sponsor"
    local stage=ModSettingGet(stageKey)
    if not stage and peerFor(caller) then return end
    local order=room.."|"..winner.."|"..plan
    local _,_,ownTarget,ownEp,x,y=parseOrder(order)
    if ownTarget~=target or ownEp~=ep then return end
    if not stage then
        if not save(stageKey,"sealing") then return end
        stage="sealing"
    end
    if stage=="sealing" then
        if targetPeer==ctx.my_id then fence(ctx.host_id,order) else rpc.fence(order) end
        return
    end
    if stage:match("^paid|") then drivePaid(target,caller,tx,ep,x,y);return end
    if stage=="unfunded" then
        if save(scope(target,ep)..".no_payer",winner) then confirm(targetPeer,room,caller,tx,target,ep,x,y,"rejected") end
        return
    end
    local live=livingParty()
    if not live then
        if live==false then confirm(targetPeer,room,caller,tx,target,ep,x,y,"rejected") end
        return
    end
    local to=stage:match("^offer|(%w+)$")
    local offeredPeer=to and peerFor(to)
    if to and (not offeredPeer or eligible(offeredPeer,target)==false or ModSettingGet(key..".declined."..to)) then
        if not save(stageKey,"choose") then return end
        to=nil
    end
    if not to then
        to=candidate(key,caller,target,row)
        if to==nil then return end
        if to==false then
            if save(stageKey,"unfunded") and save(scope(target,ep)..".no_payer",winner) then
                confirm(targetPeer,room,caller,tx,target,ep,x,y,"rejected")
            end
            return
        end
        if not save(stageKey,"offer|"..to) then return end
    end
    if owner(ctx.my_id)==to then offered(ctx.host_id,to,order) else rpc.sponsorOffer(to,order) end
end
local function pumpSponsors(f)
    if offerAt and (f<offerAt or f-offerAt>120 or not podActive()) then write("sponsor_offer","");offerAt=nil end
    if ctx.is_host and podActive() and f%36==0 then
        for peer,row in pairs(seen) do
            if row.ep~="" and owner(peer)==row.owner and f-row.at<=120 then
                handoff(row,peer);pendingNotice(row,peer)
            end
        end
    end
    local reply=read("sponsor_reply")
    if reply=="" then lastSponsorReply=nil;return end
    if reply==lastSponsorReply and f-sponsorReplyAt<30 then return end
    local order,debit=reply:match("^(.*)|([^|]+)$")
    if not parseOrder(order) or (debit~="none" and not number(debit)) then return end
    lastSponsorReply,sponsorReplyAt=reply,f
    if ctx.is_host then sponsorReply(ctx.my_id,order,debit) else rpc.sponsorReply(order,debit) end
end

local function decide(peer,field,caller,tx,target,ep,x,y,challenge,stamp,approved)
    if not ctx.is_host or not current(field) or not id(caller) or owner(peer)~=caller or not number(tx)
        or not id(target) or target==caller or not number(ep) or not position(x) or not position(y)
        or type(approved)~="boolean" or not (fresh(challenge,stamp) or receiptQuery(challenge,stamp,approved)) then return end
    local key=hostKey(caller,tx)
    local plan=payload(target,ep,x,y)
    local entry=ModSettingGet(key)
    if entry then
        local stored,status=entry:match("^(.*)|(%a+)$")
        if stored~=plan then return end
        if status=="ok" or status=="rejected" then answer(caller,tx,originalResult(key,status)); return end
    end
    local targetPeer=peerFor(target)
    local reported=targetPeer and seen[targetPeer]
    local lock=scope(target,ep)..".owner"
    local winner=ModSettingGet(lock)
    local order=caller.."|"..tx
    local stage=entry and ModSettingGet(key..".sponsor")
    if winner==order and stage then
        if stage:match("^paid|") then
            answer(caller,tx,"transferred");drivePaid(target,caller,tx,ep,x,y)
        elseif targetPeer and (stage=="sealing" or (reported and reported.ep~=ep)) then
            local full=room.."|"..order.."|"..plan
            if targetPeer==ctx.my_id then fence(ctx.host_id,full) else rpc.fence(full) end
        elseif targetPeer and not podActive() then
            confirm(targetPeer,room,caller,tx,target,ep,x,y,"rejected")
        end
        return
    end
    if not podActive() then
        -- A matching lock means a delivery could have run before reconnect;
        -- ask the recipient for its receipt without granting a new revival.
        if winner~=order then
            if save(key,plan.."|rejected") then answer(caller,tx,"rejected") end
            return
        end
        local recipient=targetPeer and nh_ew_session.challenge(targetPeer)
        if recipient then sendCommand(targetPeer,caller,tx,target,ep,x,y,recipient,false,false) end
        return
    end
    if winner and winner~="" and winner~=order then
        local other,otherTx=winner:match("^(%w+)|(%d+)$")
        local previous=other and ModSettingGet(hostKey(other,otherTx))
        if previous and previous:match("|rejected$") and save(lock,"") then winner="" end
    end
    if winner~=order then
        local p=ctx.players[peer]
        if targetPeer and not reported and (not winner or winner=="") then return end -- wait for first heartbeat
        if not p or not p.status or p.status.is_alive~=true or not reported
            or not approved or reported.owner~=target or reported.ep~=ep or (winner and winner~="") then
            if save(key,plan.."|rejected") then answer(caller,tx,"rejected") end
            return
        end
        if not save(key,plan.."|pending") or not save(lock,order) then return end
    end
    if not reported or reported.owner~=target then return end -- an earlier delivery/ACK may be in flight
    -- Initial admission checked the caller. Keep the accepted order after
    -- their death while someone in the party is still alive.
    local live=livingParty()
    if live~=nil then sendCommand(targetPeer,caller,tx,target,ep,x,y,reported.boot,reported.stamp,live) end
end
rpc.opts_reliable()
function rpc.request(...) decide(ctx.rpc_peer_id,...) end
-- A living teammate can choose another loaded space for the same order.
-- Only the host resolves the episode's winner, and only the target moves its
-- own observer. No new purchase or character snapshot is created here.
local function useAlternate(from,field,target,ep,caller,tx,x,y,challenge,stamp)
    if from~=ctx.host_id or not current(field) or not podActive() or not fresh(challenge,stamp)
        or owner(ctx.my_id)~=target or not number(ep) or not id(caller) or not number(tx)
        or not position(x) or not position(y) or read("needs_site")~=ep then return end
    local body=localBody()
    if not body or episode(target,body)~=ep then return end
    deathPosition(body) -- preserve old anchors' original coordinates before streaming the new area
    if save(scope(target,ep)..".landing",table.concat({caller,tx,x,y},"|")) then
        if waiting.isAnchor(body) and not DoesWorldExistAt(x-7,y-15,x+7,y+8) then
            EntitySetTransform(body,x,y)
        end
        write("needs_site","")
        lastRollback=nil
    end
end
rpc.opts_reliable()
function rpc.alternate(...) useAlternate(ctx.rpc_peer_id,...) end
local function redirectRequest(peer,field,target,ep,x,y,challenge,stamp)
    if not ctx.is_host or not current(field) or not podActive() or not fresh(challenge,stamp)
        or not id(target) or not number(ep) or not position(x) or not position(y) then return end
    local who=owner(peer)
    local member=ctx.players[peer]
    local p=seen[peer]
    if not who or who==target or not member or not member.status or not member.status.is_alive
        or not p or p.owner~=who or (p.x-x)^2+(p.y-y)^2>160^2 then return end
    local receiver=peerFor(target)
    local row=receiver and seen[receiver]
    if not row or not row.redirect or row.ep~=ep then return end
    local order=ModSettingGet(scope(target,ep)..".owner") or ""
    local caller,tx=order:match("^(%w+)|([1-9]%d*)$")
    if not caller then return end
    local record=ModSettingGet(hostKey(caller,tx)) or ""
    local to,episodeId,state=record:match("^(%w+)|(%d+)|%-?%d+|%-?%d+|(%a+)$")
    if to~=target or episodeId~=ep or (state~="ok" and state~="pending") then return end
    if receiver==ctx.my_id then useAlternate(ctx.my_id,field,target,ep,caller,tx,x,y,row.boot,row.stamp)
    else rpc.alternate(field,target,ep,caller,tx,x,y,row.boot,row.stamp) end
end
rpc.opts_reliable()
function rpc.redirect(...) redirectRequest(ctx.rpc_peer_id,...) end
local function sendRedirect()
    local value=read("redirect")
    if value=="" then return end
    local host=seen[ctx.host_id]
    if not host then return end
    write("redirect","")
    local field,target,ep,x,y=value:match("^([%w_-]+)|(%w+)|(%d+)|(-?%d+)|(-?%d+)$")
    x,y=tonumber(x),tonumber(y)
    if field~=room or not position(x) or not position(y) or not callerSite() then return end
    local px,py=EntityGetTransform(ctx.my_player.entity)
    if (px-x)^2+(py-y)^2>160^2 or not pod.reviveSpace(x,y) then return end
    if ctx.is_host then redirectRequest(ctx.my_id,field,target,ep,x,y,host.boot,host.stamp)
    else rpc.redirect(field,target,ep,x,y,host.boot,host.stamp) end
end
local function advertise(peer,field,ep,x,y,challenge,stamp,redirect)
    if not current(field) or (ep~="" and not number(ep)) or not position(x) or not position(y)
        or type(challenge)~="string" or #challenge>60 or not challenge:match("^[%w%-]+$")
        or type(stamp)~="number" or stamp<0 or stamp~=math.floor(stamp) then return end
    local who=owner(peer)
    if who then
        local old=seen[peer]
        if redirect==true and peer~=ctx.my_id and callerSite() and (not old or old.ep~=ep or not old.redirect) then
            GamePrint(GameTextGet("$nh_hideout_ew_redirect_pod"))
        end
        seen[peer]={owner=who,ep=ep,x=x,y=y,at=GameGetFrameNum(),boot=challenge,stamp=stamp,redirect=redirect==true}
    end
end
rpc.opts_reliable()
function rpc.advert(...) advertise(ctx.rpc_peer_id,...) end
local function reset(nextRoom)
    endFlight(false)
    write("needs_site","");write("redirect","")
    room,seen,lastAdvert,lastRequest,published,publishedMode,lastRollback=nextRoom,{},nil,nil,nil,nil,nil
    boot=room and (("%04d%02d%02d%02d%02d%02d"):format(GameGetDateAndTimeUTC()).."-"..math.floor(GameGetRealWorldTimeSinceStarted()*1000000))
    write("mode",""); write("targets","")
    write("sponsor_offer","");write("sponsor_reply","")
    offerAt,lastSponsorReply,sponsorReplyAt=nil,nil,nil
end
function M.on_world_initialized() reset(nil); lastFrame,lastUpgrade=nil,nil end
local function publishRoster(f,me)
    sendRedirect()
    local body=localBody()
    local ep=episode(me,body) or ""
    if read("needs_site")~="" and (read("needs_site")~=ep or not blockedAt or f-blockedAt>150) then
        write("needs_site","")
    end
    -- The settings ledger may have survived a rollback to a world save that
    -- still contains this exact downed body. Reapply the paid delivery only
    -- to that body's episode; a later death has a fresh serial.
    if ep~="" and (not lastRollback or lastRollback.ep~=ep or f-lastRollback.at>=60) then
        lastRollback={ep=ep,at=f}
        local key=scope(me,ep)..".receipt"
        local entry=ModSettingGet(key) or ""
        local caller,tx,x,y=entry:match("^(%w+)|(%d+)|(-?%d+)|(-?%d+)|ok$")
        x,y=tonumber(x),tonumber(y)
        if position(x) and position(y) then beginFlight(body,caller,tx,me,ep,x,y,true,false) end
    end
    if body and ep~="" and (not lastAdvert or lastAdvert.ep~=ep) then
        local marker=tag(body,"nh_ew_reinforce_episode")
        if marker and not ComponentGetValue2(marker,"value_bool") then
            GamePrint(GameTextGet("$nh_hideout_ew_await_pod"))
            ComponentSetValue2(marker,"value_bool",true)
        end
    end
    local redirect=ep~="" and read("needs_site")==ep
    if not lastAdvert or ep~=lastAdvert.ep or redirect~=lastAdvert.redirect or f-lastAdvert.at>=36 then
        local x,y=0,0
        if body then x,y=deathPosition(body)
        elseif ctx.my_player and ctx.my_player.entity and EntityGetIsAlive(ctx.my_player.entity) then
            x,y=EntityGetTransform(ctx.my_player.entity);x,y=math.floor(x),math.floor(y)
        end
        advertise(ctx.my_id,room,ep,x,y,boot,f,redirect);rpc.advert(room,ep,x,y,boot,f,redirect)
        lastAdvert={at=f,ep=ep,redirect=redirect}
    end
    local rows={}
    for peer,row in pairs(seen) do
        local p=ctx.players[peer]
        if not p or p.dc or owner(peer)~=row.owner or f-row.at>120 then seen[peer]=nil
        elseif peer~=ctx.my_id and row.ep~="" then
            local name=tostring(p.name or peer):gsub("[%c|]"," ")
            rows[#rows+1]=table.concat({row.owner,row.ep,row.x,row.y,name},"|")..(row.redirect and "|redirect" or "")
        end
    end
    table.sort(rows)
    local roster=table.concat(rows,"\n")
    if published~=roster or not publishedMode then
        write("targets",roster); write("mode",room); published,publishedMode=roster,true
    end
end
function M.on_world_update()
    local f=GameGetFrameNum()
    landingTick()
    local p=ctx.my_player
    if p and waiting.pendingLegacy(p.entity) and f%6~=0 then reconcile(f) end
    if f%6~=0 then return end
    reconcile(f)
    local here=world()
    if room~=here or not seen or (lastFrame and f<lastFrame) then reset(here) end
    lastFrame=f
    if not room then return end
    local active=podActive()
    local me=owner(ctx.my_id)
    if not me then return end
    if active then publishRoster(f,me)
    elseif publishedMode~=false then
        write("targets",""); write("mode","")
        seen,lastAdvert,published,publishedMode={},nil,"",false
    end
    pumpSponsors(f)
    local request=read("request")
    if request=="" then lastRequest=nil; return end
    if lastRequest and request==lastRequest.value and f-lastRequest.at<30 then return end
    local field,caller,tx,target,n,sx,sy=request:match("^([%w_-]+)|(%w+)|(%d+)|(%w+)|(%d+)|(-?%d+)|(-?%d+)$")
    if field~=room or caller~=me or not number(tx) or not id(target) or not number(n) then return end
    local x,y=tonumber(sx),tonumber(sy)
    if not position(x) or not position(y) or read("result."..room.."."..me.."."..tx)~="" then return end
    local challenge,stamp,approved
    if active then
        local host=seen[ctx.host_id]
        if not host then return end
        challenge,stamp,approved=host.boot,host.stamp,callerSite(x,y)
    else
        challenge,stamp,approved=nh_ew_session.challenge(ctx.host_id),false,false
        if not challenge then return end
    end
    lastRequest={value=request,at=f}
    if ctx.is_host then decide(ctx.my_id,room,me,tx,target,n,x,y,challenge,stamp,approved)
    else rpc.request(room,me,tx,target,n,x,y,challenge,stamp,approved) end
end
return M
