local root="mods/noita_hideout/files/"
local cabin=dofile(root.."travel/cabin.lua")
local package=assert(io.open("mods/noita_hideout/mod.xml","rb"))
assert(package:read("*a"):match('description="(%d+%.%d+%.%d+)')==dofile(root.."ew_version.lua"),"Hideout release/handshake version mismatch")
package:close()
local frame,count=0,0
local clients,queue={},{}
local function install(id,save,release,preference)
    local c={save=save or {},handlers={},ng=0,preference=preference}
    local env=setmetatable({},{__index=_G})
    env.ctx={is_host=id=="host",my_id=id,host_id="host",ready=true,proxy_opt={share_gold=false,game_mode="local_health"},
        players={},cap={health={nh_reinforce_restore=function() end,nh_reinforce_hold=function() end,nh_reinforce_wait=function() end}}}
    env.ModSettingGet=function(key)
        assert(id=="host" and key=="noita_hideout.ew_rescue_mode")
        return c.preference
    end
    env.net={connect_failed=false}
    env.ModDoesFileExist=function() return true end
    env.GameGetFrameNum=function() return frame end
    env.SessionNumbersGetValue=function() return tostring(c.ng) end
    env.GameGetDateAndTimeUTC=function() return 2026,11,23,14,35,26 end
    count=count+1; local process=count
    env.GameGetRealWorldTimeSinceStarted=function() return frame/60+process end
    env.GlobalsGetValue=function(k,d) return c.save[k] or d end
    env.GlobalsSetValue=function(k,v) c.save[k]=v end
    local api={rpc_player_data=function() return {peer_id=c.sender} end}
    function api.new_rpc_namespace()
        return setmetatable({opts_reliable=function() end},{__newindex=function(t,k,handler)
            c.handlers[k]=handler
            rawset(t,k,function(...)
                for target in pairs(clients) do
                    if target~=id then queue[#queue+1]={id,target,k,{...}} end
                end
            end)
        end})
    end
    env.dofile_once=function(path)
        if path:find("ew_api.lua",1,true) then return api end
        if path:find("ew_version.lua",1,true) then return release or dofile(path) end
        if path:find("version.lua",1,true) then return "1.6.8" end
        return dofile(path)
    end
    c.env=env
    c.hook=setfenv(assert(loadfile(root.."ew_module.lua")),env)()
    clients[id]=c
    for peer,p in pairs(clients) do
        p.env.ctx.players[id]={}; env.ctx.players[peer]={}
        if peer~=id then p.hook.on_client_spawned(id) end
    end
    c.hook.on_world_initialized()
    c.save["nh_ew.issuer"]=id.."_install"
    return c
end
local function advance(n,drop)
    for _=1,n do
        frame=frame+1
        for _,p in pairs(clients) do p.hook.on_world_update() end
        local outgoing=queue; queue={}
        for _,m in ipairs(outgoing) do
            local c=clients[m[2]]
            if c and not (drop and drop(m)) then c.sender=m[1]; c.handlers[m[3]](unpack(m[4])); c.sender=nil end
        end
    end
end
local host=install("host"); local guest=install("guest",nil,nil,"native")
local P="nh_ew."
assert(not host.env.nh_ew_session.wait_on_death() and not guest.env.nh_ew_session.wait_on_death())
advance(100)
local room=assert(host.env.nh_ew_session.world())
assert(guest.env.nh_ew_session.world()==room and host.env.nh_ew_session.issuer("guest")=="guest_install")
assert(host.env.nh_ew_session.rescue_policy()=="pod" and guest.env.nh_ew_session.rescue_policy()=="pod")
-- Only incoming host snapshots are missing. The authenticated party remains
-- the same; for one hello interval we may enter a wait, but never transact.
local function missSnapshot(m) return m[1]=="host" and m[3]=="snapshot" end
local function missGuestHello(m) return m[1]=="guest" and m[3]=="hello" end
local function gap(c,drop,maxFrames)
    for _=1,maxFrames do
        advance(1,drop)
        if not c.env.nh_ew_session.world() then break end
    end
    local s=c.env.nh_ew_session
    assert(not s.world() and not s.rescue_policy() and not s.issuer("host") and not s.challenge("guest"))
    assert(s.wait_on_death())
end
gap(guest,missSnapshot,200)
advance(95,missSnapshot);assert(not guest.env.nh_ew_session.wait_on_death())
advance(110);assert(guest.env.nh_ew_session.wait_on_death())
gap(host,missGuestHello,350)
assert(not guest.env.nh_ew_session.rescue_policy() and guest.env.nh_ew_session.wait_on_death())
advance(95,missGuestHello);assert(not host.env.nh_ew_session.wait_on_death())
advance(110);assert(host.env.nh_ew_session.wait_on_death() and guest.env.nh_ew_session.wait_on_death())
local hostBoot=host.env.nh_ew_session.challenge("host")
local function hostHello(challenge)
    guest.sender="host"
    guest.handlers.hello("1",dofile(root.."ew_version.lua"),"host_install",challenge,"0",true)
    guest.sender=nil
end
guest.hook.on_client_spawned("host") -- the same player_data after an EW polymorph
hostHello(hostBoot)
assert(not guest.env.nh_ew_session.world() and guest.env.nh_ew_session.wait_on_death())
hostHello(hostBoot.."-new")
assert(not guest.env.nh_ew_session.world() and not guest.env.nh_ew_session.wait_on_death())
advance(150);assert(guest.env.nh_ew_session.wait_on_death())
-- An EW-only peer cannot grant a vote; even the frames before the next
-- handshake tick must no longer inherit the old party's answer.
for _,c in ipairs({host,guest}) do
    c.env.ctx.players.ew_only={};assert(not c.env.nh_ew_session.wait_on_death())
    c.hook.on_client_spawned("ew_only")
end
advance(350)
for _,c in ipairs({host,guest}) do
    assert(not c.env.nh_ew_session.world() and not c.env.nh_ew_session.wait_on_death())
    c.env.ctx.players.ew_only=nil
end
advance(110)
-- NG+, an ending, and loss of the host identity invalidate even before
-- the periodic client machine gets its next tick.
guest.ng=1;assert(not guest.env.nh_ew_session.wait_on_death());guest.ng=0
guest.env.ctx.run_ended=true;assert(not guest.env.nh_ew_session.wait_on_death());guest.env.ctx.run_ended=nil
guest.env.ctx.host_id="new_host";assert(not guest.env.nh_ew_session.wait_on_death());guest.env.ctx.host_id="host"
-- Changing a local preference mid-run, including the host's pending value,
-- cannot change the active rule while a teammate is down.
host.preference="native"
advance(100)
assert(host.env.nh_ew_session.rescue_policy()=="pod" and guest.env.nh_ew_session.rescue_policy()=="pod")
local cap=guest.env.ctx.cap.health.nh_reinforce_restore
guest.env.ctx.cap.health.nh_reinforce_restore=nil;advance(55)
assert(host.env.nh_ew_session.rescue_policy()=="native" and guest.env.nh_ew_session.rescue_policy()=="native")
assert(not host.env.nh_ew_session.wait_on_death() and not guest.env.nh_ew_session.wait_on_death())
guest.env.ctx.cap.health.nh_reinforce_restore=cap;advance(55)
assert(host.env.nh_ew_session.rescue_policy()=="pod" and guest.env.nh_ew_session.rescue_policy()=="pod")
local guard=host.env.ctx.cap.health.nh_reinforce_hold
host.env.ctx.cap.health.nh_reinforce_hold=nil;advance(55)
assert(host.env.nh_ew_session.rescue_policy()=="native" and guest.env.nh_ew_session.rescue_policy()=="native")
host.env.ctx.cap.health.nh_reinforce_hold=guard;advance(55)
local wait=guest.env.ctx.cap.health.nh_reinforce_wait
guest.env.ctx.cap.health.nh_reinforce_wait=nil;advance(55)
assert(host.env.nh_ew_session.rescue_policy()=="native" and guest.env.nh_ew_session.rescue_policy()=="native")
guest.env.ctx.cap.health.nh_reinforce_wait=wait;advance(55)
assert(host.env.nh_ew_session.rescue_policy()=="pod" and guest.env.nh_ew_session.rescue_policy()=="pod")
assert(host.save[P.."local_peer"]=="host" and guest.save[P.."world_mark"]==room)
local key=room..".0."..cabin.revision
local maskWrites,backgrounds,floors=0,0,false
local occupied,loose,notices=nil,false,0
local function visit(c,eligible)
    c.eligible=eligible
    local env=setmetatable({}, {__index=c.env})
    env.DoesWorldExistAt=function() return c.eligible end
    env.RaytracePlatforms=function() return floors end
    env.EntityGetTransform=function() return -500,0 end
    env.RemovePixelSceneBackgroundSprite=function() end
    env.LoadBackgroundSprite=function() backgrounds=backgrounds+1 end
    env.LoadPixelScene=function() maskWrites=maskWrites+1; floors=true end
    env.Raytrace=function(_,y) return occupied==y end
    env.EntityGetInRadius=function() return loose and {9} or {1} end
    env.EntityGetRootEntity=function(id) return id end
    env.EntityGetTransform=function(id) if id==9 then return cabin.left+3,cabin.top+9 end;return -500,0 end
    env.GamePrint=function() notices=notices+1 end
    env.GameTextGetTranslatedOrNot=function(s) return s end
    c.bridge=c.bridge or setfenv(assert(loadfile(root.."travel/ew_cabin.lua")),env)()
    return c.bridge.ensure(key,cabin,1,function(k) return c.save["personal."..k] or "" end,
        function(k,v) c.save["personal."..k]=v end,function() end,function() return true end)
end
-- Only the guest has streamed the ship. The host arbitrates remotely.
assert(not visit(host,false) and not visit(guest,true)); advance(10)
assert(not visit(guest,true) and maskWrites==1); advance(1)
assert(visit(guest,true)); advance(55)
assert(visit(host,true) and maskWrites==1 and backgrounds==1)
-- A missing remote sky chunk may need a local copy after a whole lobby
-- reload. Even one pixel or a loose object prevents the recovery stamp.
host.save["personal.built"]=nil;floors=false;occupied=cabin.top+83
assert(not visit(host,true));advance(50);assert(not visit(host,true) and notices==1 and maskWrites==1)
occupied=nil; loose=true; advance(31);assert(not visit(host,true) and maskWrites==1)
loose=false;advance(31);assert(not visit(host,true));advance(10)
assert(host.save[P.."ship_state"]:find("|copy|",1,true))
occupied=cabin.bottom-2;assert(not visit(host,true) and maskWrites==1)
occupied=nil;advance(31);assert(not visit(host,true) and maskWrites==2)
advance(5);assert(visit(host,true));advance(50);assert(visit(host,true) and maskWrites==2)
-- Both see a local storm at different frames. Only the host round is applied.
local function storm(c,round)
    c.env.GameHasFlagRun=function() return c.env.ctx.is_host end
    setfenv(assert(loadfile(root.."travel/ew_cabin.lua")),c.env)().schedule(key,round)
end
storm(guest,77); storm(host,88); advance(50)
assert(not visit(guest,true) and not visit(host,true)); advance(10)
visit(host,true); visit(guest,true); advance(5); visit(host,true); visit(guest,true); advance(55)
assert(maskWrites==3 and host.save[P.."cabin_complete."..key]=="88")
-- A different release suspends all peers. Removing it permits the same party
-- to continue, without manufacturing a new room or clearing the cabin ledger.
install("other",nil,"0.99.0"); advance(110)
assert(not host.env.nh_ew_session.world() and not guest.env.nh_ew_session.world())
assert(not host.env.nh_ew_session.rescue_policy() and not guest.env.nh_ew_session.rescue_policy())
assert(not host.env.nh_ew_session.wait_on_death() and not guest.env.nh_ew_session.wait_on_death())
clients.other=nil; host.env.ctx.players.other=nil; guest.env.ctx.players.other=nil; advance(100)
assert(host.env.nh_ew_session.world()==room and guest.env.nh_ew_session.world()==room)
local gs=guest.save
clients.guest=nil; host.env.ctx.players.guest=nil; advance(20)
assert(host.env.nh_ew_session.world()==room and not host.env.nh_ew_session.issuer("guest"))
guest=install("guest",gs); advance(100)
assert(guest.env.nh_ew_session.world()==room and visit(guest,true) and maskWrites==3)
host=install("host",host.save,nil,"native")
assert(not host.env.nh_ew_session.wait_on_death() and not guest.env.nh_ew_session.wait_on_death());advance(110)
assert(host.env.nh_ew_session.world()==room and guest.env.nh_ew_session.world()==room)
assert(host.env.nh_ew_session.rescue_policy()=="native" and guest.env.nh_ew_session.rescue_policy()=="native")
assert(host.save[P.."ship_state"]:find("|88|done|",1,true))
-- Host with a genuinely new save, even with the same issuer/seed.
host=install("host"); advance(110)
assert(host.env.nh_ew_session.world()~=room and guest.env.nh_ew_session.world()==host.env.nh_ew_session.world())
assert(host.env.nh_ew_session.rescue_policy()=="pod" and guest.env.nh_ew_session.rescue_policy()=="pod")

-- Local waypoint/trip/gate state remains in its personal world and NG+
-- namespace. A stale outbound trip must not execute while a handshake waits.
local routeRoom,owner,allow,ng,px,py="room_A","owner_A",true,0,400,700
local map={["nh_travel.stations"]="12,34;"}
function GameGetFrameNum() return frame end
function GlobalsGetValue(k,d) return map[k] or d end
function GlobalsSetValue(k,v) map[k]=v end
function SessionNumbersGetValue() return ng end
function EntityGetTransform() return px,py end
function EntityGetWithTag() return {} end
function EntityGetInRadiusWithTag(_,_,_,tag) if tag=="noita_hideout_mountain_storage" then return {11} end end
function GameTextGetTranslatedOrNot(k) return k end
function GamePrint() end
function ModSettingGet() return "10" end
function InputIsKeyDown() return false end
local network=dofile(root.."travel/network.lua")
network.setMultiplayer({enabled=function() return true end,world=function() return routeRoom end,
    ready=function() return allow end,issuer=function() return owner end,rescueAllowed=function() return false end})
local function tick() frame=frame+1; network.update(1,0,0,false) end
local function path() return "nh_travel.ew."..routeRoom.."."..owner..".ng"..ng.."." end
network.reset(); tick(); assert(map[path().."stations"]=="400,700;")
local old=path(); map[old.."trip"]="ship,12,17,46,82,9999"
allow=false; tick(); assert(map[old.."trip"]~="" and network.view()==nil)
allow=true; routeRoom="room_B"; px=500; tick()
assert(map[path().."stations"]=="500,700;" and not map[path().."trip"])
owner="owner_B"; px=600; tick(); assert(map[path().."stations"]=="600,700;")
ng=1; frame=frame+(15-frame%15)-1; px=700; tick()
assert(map[path().."stations"]=="700,700;" and map[old.."stations"]=="400,700;" and map["nh_travel.stations"]=="12,34;")
assert(network.rescue(1,0,0)==false and not map[path().."trip"])
print("EW: trusted handshakes, guest-only ship, storm arbitration, reconnects and per-person/world routes passed.")
