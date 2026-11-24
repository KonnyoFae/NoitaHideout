local path="mods/noita_hideout/files/"
-- Keep the upstream branches surrounding the three optional effects. Altered
-- code must fail closed; ordinary revives still apply EW effects and costs.
local function patchTest()
    local release="1.6.8"
    local native=[=[local function player_died()
    local gold = get_gold()

    rpc.remove_homing(false)
end
die = player_died
local function update_sample(notplayer_active, player_ent)
    local hp, max_hp = util.get_ent_health(player_ent)
    local hp_new=hp
    if not ctx.proxy_opt.no_notplayer and not ctx.proxy_opt.perma_death and notplayer_active and hp_new <= 0 then end
    return hp, max_hp
end
get_sample = update_sample
ctx.cap.health = {
    on_poly_death = function()
            rpc.remove_homing(true)
            restore_inventory()
            rpc.remove_homing(true)
            reduce_hp()
            spectate.disable_throwing(false, ctx.my_player.entity)
    end,
}
]=]
    local writes,clears,charges,restores=0,0,0,0
    local testHp=0
    local shared=[=[local module={}
local function do_health_diff(hp, max_hp) end
function module.on_local_player_spawn(my_player)
    local dm=my_player.entity.damage
    dm.attached=true
end
return module]=]
    local sharedFile="mods/quant.ew/files/system/damage/damage.lua"
    local nativeDeaths,messages,enterOK,reason=0,{},false,nil
    local env=setmetatable({ctx={cap={},my_player={entity=1},proxy_opt={}},rpc={remove_homing=function() clears=clears+1 end},
        util={get_ent_health=function() return testHp,8 end},
        get_gold=function() nativeDeaths=nativeDeaths+1 end,GameRemoveFlagRun=function() end,
        GamePrint=function(s) messages[#messages+1]=s end,GameTextGet=function(k) return k end,
        restore_inventory=function() restores=restores+1 end,reduce_hp=function() charges=charges+1 end,
        spectate={disable_throwing=function() end},ModDoesFileExist=function() return true end,
        dofile_once=function(file)
            if file:find("ew_waiting",1,true) then return {isAnchor=function() return false end,enter=function() return enterOK,reason end} end
            return release
        end,ModTextFileGetContent=function(file) return file==sharedFile and shared or native end,
        EntityHasTag=function(e,t) return e[t] end,
        ModTextFileSetContent=function(file,value)
            if file==sharedFile then shared=value else native=value;writes=writes+1 end
        end},{__index=_G})
    local install=setfenv(assert(loadfile(path.."ew_reinforce_patch.lua")),env)().install
    release="1.6.9"; install(); assert(writes==0)
    release="1.6.8"; local original=native
    native=native:gsub("restore_inventory%(%)","rpc.remove_homing(true)"); install();assert(writes==0)
    native=original:gsub("\n","\r\n"); install();install();assert(writes==1)
    local sharedHealth=setfenv(assert(loadstring(shared)),env)()
    sharedHealth.on_local_player_spawn({entity={nh_ew_waiting=true}})
    local live={entity={damage={}}};sharedHealth.on_local_player_spawn(live);assert(live.entity.damage.attached)
    setfenv(assert(loadstring(native)),env)()
    local cap=env.ctx.cap.health
    cap.on_poly_death()
    assert(clears==2 and charges==1 and restores==1)
    cap.nh_reinforce_restore()
    assert(clears==2 and charges==1 and restores==2)
    cap.nh_reinforce_hold=function() testHp=8; return true end
    assert(env.get_sample(false,1)==0 and env.get_sample(true,1)==8)
    cap.on_poly_death();assert(clears==2 and charges==1 and restores==2)
    cap.nh_reinforce_restore();assert(clears==2 and charges==1 and restores==3)
    cap.nh_reinforce_hold=nil
    cap.nh_reinforce_restore=nil
    cap.on_poly_death()
    assert(clears==4 and charges==2 and restores==4)
    cap.nh_reinforce_wait=function() return true end
    env.die();assert(#messages==1 and messages[1]=="$nh_hideout_ew_wait_failed" and nativeDeaths==0)
    reason="$nh_hideout_ew_wait_carrying_peer"
    env.die();assert(#messages==2 and messages[2]==reason and nativeDeaths==0)
    enterOK=true;env.die();assert(#messages==2 and nativeDeaths==0)
    env.die(true);assert(nativeDeaths==1)
    cap.nh_reinforce_wait=nil;env.die();assert(nativeDeaths==2)
end
patchTest()

local frame,world=0,"testWorld"
local peers,wire={},{}
local sent=0
local owners={h="Host",a="Alice",b="Bob"}
local function reload(p)
    p.connection=(p.connection or 0)+1
    local handlers={}
    local net=setmetatable({opts_reliable=function() end},{
        __newindex=function(_,key,fn) handlers[key]=fn end,
        __index=function(_,key) return function(...)
            sent=sent+1
            wire[#wire+1]={from=p.id,name=key,args={...}}
        end end})
    p.handlers=handlers
    local ctx=p.ctx
    local env=setmetatable({ctx=ctx,
        nh_ew_session={world=function() return world end,rescue_policy=function() return p.policy end,
        wait_on_death=function() if p.waitDuringGap~=nil then return p.waitDuringGap end;return p.policy=="pod" end,
        challenge=function(peer)
            local other=peers[peer]
            return other and ctx.players[peer] and not ctx.players[peer].dc and (peer.."-"..other.connection) or nil
        end,issuer=function(peer)
            return ctx.players[peer] and not ctx.players[peer].dc and owners[peer] or nil
        end},
        ModDoesFileExist=function() return true end,
        dofile_once=function(file)
            if file=="mods/quant.ew/files/version.lua" then return "1.6.8" end
            if file:find("ew_waiting",1,true) then
                return {isAnchor=function(e) return e and e.anchor end,installSpawnGuard=function() end,
                    pendingLegacy=function() return false end,releaseLegacy=function() end,
                    upgrade=function() return false end,restore=function() p.sharedFallback=true end}
            end
            if file:find("resupply",1,true) then
                local function space(x)
                    return not p.unloaded and not p.crowded and (not p.blocked or x==p.alternateX)
                end
                return {reviveSite=function(x,y) if space(x) then return {x=x,y=y,start=y-1} end end,
                    reviveSpace=space}
            end
            return {new_rpc_namespace=function() return net end}
        end,
        DoesWorldExistAt=function() return not p.unloaded end,
        SessionNumbersGetValue=function() return "0" end,
        GameGetDateAndTimeUTC=function() return 2026,11,23,1,1,1 end,
        GameGetRealWorldTimeSinceStarted=function() return frame/60 end,
        GlobalsGetValue=function(k,d) return p.globals[k] or d end,
        GlobalsSetValue=function(k,v) p.globals[k]=v end,
        ModSettingGet=function(k) return p.settings[k] end,
        ModSettingSet=function(k,v)
            if k~=p.failSetting and not (p.failOK and k:match("%.receipt$") and v:match("|ok$")) then p.settings[k]=v end
        end,
        EntityGetFirstComponentIncludingDisabled=function(e,k,t)
            return e and (t and e[t] or e[k])
        end,
        EntityAddComponent2=function(e,k,v) e[v._tags]=v; return v end,
        EntityGetIsAlive=function(e) return e and e.alive end,
        EntityHasTag=function(e,t) return e and e[t] or false end,
        ComponentGetValue2=function(c,k) return c[k] end,
        ComponentSetValue2=function(c,k,v) c[k]=v end,
        EntityGetTransform=function(e) return e.x,e.y end,
        EntitySetTransform=function(e,x,y) e.x,e.y=x,y end,
        GameTextGet=function(key) assert(key=="$nh_hideout_ew_await_pod" or key=="$nh_hideout_ew_redirect_pod" or key=="$nh_hideout_ew_no_sponsor"); return key end,
        GamePrint=function(msg)
            p.notices=p.notices+1
            if msg=="$nh_hideout_ew_no_sponsor" then p.cancellations=(p.cancellations or 0)+1 end
        end,
        GameHasFlagRun=function(k) return (k=="ew_flag_notplayer_active" and p.down) or p.flags[k] end,
        GameGetFrameNum=function() return frame end},{__index=_G})
    p.module=setfenv(assert(loadfile(path.."ew_reinforce_rpc.lua")),env)()
    p.module.on_world_initialized()
end
local function newBody(hp)
    return {alive=true,x=10,y=30,DamageModelComponent={hp=hp,max_hp=7},CharacterDataComponent={}}
end
local function makePeer(id)
    local p={id=id,globals={},settings={},down=false,restores=0,policy="pod",notices=0,flags={}}
    p.ctx={ready=true,is_host=id=="h",host_id="h",my_id=id,cap={health={}},players={},
        my_player={entity=newBody(7)},proxy_opt={game_mode="local_health"}}
    p.ctx.cap.health.nh_reinforce_restore=function()
        assert(p.down)
        p.restores=p.restores+1
        p.ctx.my_player.entity.alive=false
        p.ctx.my_player.entity=newBody(1)
        p.down=false
    end
    p.ctx.cap.health.nh_reinforce_native=function() p.nativeFallback=true end
    peers[id]=p; reload(p)
    return p
end
local host,alice,bob=makePeer("h"),makePeer("a"),makePeer("b")
local offline={}
local packets={}
local function syncStats()
    for _,p in pairs(peers) do
        for id,other in pairs(peers) do
            p.ctx.players[id]={dc=offline[id],name="Player "..id,status={is_alive=not other.down}}
        end
    end
end
local function deliver(drop)
    local queue=wire;wire={}
    for _,packet in ipairs(queue) do
        packets[packet.name]=packet.args
        if packet.name~=drop then
            for id,p in pairs(peers) do
                if id~=packet.from and not offline[id] and not offline[packet.from] then
                    p.ctx.rpc_peer_id=packet.from
                    p.handlers[packet.name](unpack(packet.args))
                end
            end
        end
    end
end
local function tick(drop)
    frame=frame+6; syncStats()
    for _,p in ipairs({host,alice,bob}) do if not offline[p.id] then p.module.on_world_update() end end
    for _=1,6 do deliver(drop) end
end
local function ticks(count,drop) for _=1,count do tick(drop) end end
local function fall(p)
    p.down=true;p.globals.ew_local_player_dead="serialized body"
    local b=newBody(7);b.ew_notplayer=true;p.ctx.my_player.entity=b
    return b
end
local function request(p,tx,ep,target,x,y)
    p.globals["nh_ew.reinforce_request"]=table.concat({world,owners[p.id],tx,owners[target.id],ep,x,y},"|")
end
local function answer(p,tx)
    return p.globals["nh_ew.reinforce_result."..world.."."..owners[p.id].."."..tx]
end
local function entry(p,target)
    return (p.globals["nh_ew.reinforce_targets"] or ""):match(owners[target.id].."|(%d+)|")
end
local firstDown=fall(bob);ticks(8)
assert(bob.notices==1)
reload(bob);ticks(7);assert(bob.notices==1)
local hold=bob.ctx.cap.health.nh_reinforce_hold
local wand,extraLives={mana=42},{stacks=2}
firstDown.wand,firstDown.originalLives=wand,extraLives
for _,damage in ipairs({-1,0,-1000000}) do
    firstDown.DamageModelComponent.hp=damage
    assert(hold() and firstDown.DamageModelComponent.hp==7 and firstDown.DamageModelComponent.max_hp==7)
    assert(bob.ctx.my_player.entity==firstDown and firstDown.alive and bob.down)
    assert(firstDown.wand==wand and firstDown.originalLives==extraLives and extraLives.stacks==2)
end
assert(not host.ctx.players.b.status.is_alive)
firstDown.DamageModelComponent.hp=-2
for _,flag in ipairs({"ending_game_completed","ew_kill_player"}) do
    bob.flags[flag]=true;assert(not hold() and firstDown.DamageModelComponent.hp==-2);bob.flags[flag]=nil
end
bob.ctx.run_ended=true;assert(not hold());bob.ctx.run_ended=false
bob.ctx.ready=false;assert(not hold());bob.ctx.ready=true
bob.policy=nil;assert(not hold());bob.policy="native";assert(not hold());bob.policy="pod"
for _,option in ipairs({"pvp","no_notplayer","perma_death"}) do
    bob.ctx.proxy_opt[option]=true;assert(not hold());bob.ctx.proxy_opt[option]=false
end
bob.ctx.proxy_opt.game_mode="shared_health";assert(not hold());bob.ctx.proxy_opt.game_mode="local_health"
bob.down=false;assert(not hold());bob.down=true
firstDown.ew_notplayer=false;assert(not hold());firstDown.ew_notplayer=true
firstDown.ew_client=true;assert(not hold());firstDown.ew_client=nil
bob.globals.ew_local_player_dead="";assert(not hold());bob.globals.ew_local_player_dead="serialized body"
assert(hold() and firstDown.DamageModelComponent.hp==7)
local e1=assert(entry(host,bob))
assert(entry(alice,bob)==e1 and not entry(bob,bob) and host.globals["nh_ew.reinforce_mode"]==world)
request(host,1,e1,bob,81,-23);request(alice,1,e1,bob,33,70)
ticks(8)
assert(bob.restores==1 and answer(host,1)=="ok" and answer(alice,1)=="rejected")
local body=bob.ctx.my_player.entity
assert(body.x==firstDown.x and body.y==firstDown.y and body.DamageModelComponent.hp==7)
local hp=body.DamageModelComponent;hp.hp=5
ticks(12)
assert(hp.hp==5 and bob.restores==1) -- no repeated full heal on an ACK replay
fall(bob);ticks(8);local e2=assert(entry(alice,bob));assert(e2~=e1)
request(alice,2,e1,bob,30,30);ticks(8)
assert(answer(alice,2)=="rejected" and bob.restores==1)

-- Only the host can command the owner; a guest cannot spoof a reply or
-- spend another local profile's held order.
bob.ctx.rpc_peer_id="a";bob.handlers.command(world,"Alice","3","Bob",e2,8,7)
alice.ctx.rpc_peer_id="b";alice.handlers.result("Alice",world,"3","ok")
host.ctx.rpc_peer_id="b";host.handlers.request(world,"Alice","3","Bob",e2,8,7)
assert(bob.down and not answer(alice,3))
request(alice,3,e2,bob,9,7)
bob.failOK=true
ticks(8)
assert(bob.restores==2 and not answer(alice,3))
offline.b=true; reload(host); reload(alice);ticks(10)
assert(not answer(alice,3))
bob.failOK=false;offline.b=false;reload(bob);ticks(14)
assert(answer(alice,3)=="ok" and bob.restores==2 and bob.ctx.my_player.entity.x==10)

-- Result lost across a checkpoint, followed by another death. The old
-- request must only replay its receipt, never move the new downed body.
alice.globals["nh_ew.reinforce_result."..world..".Alice.3"]=nil
fall(bob);ticks(14)
assert(answer(alice,3)=="ok" and bob.down and bob.restores==2)
local e3=assert(entry(alice,bob));assert(e3~=e2)
request(alice,4,e3,bob,17,28)
ticks(3,"confirm");assert(bob.restores==3 and not answer(alice,4))
ticks(10);assert(answer(alice,4)=="ok" and bob.restores==3)
-- A committed episode's bodily world save can also be older than settings.
local rewound=fall(bob)
rewound.nh_ew_reinforce_episode={value_string=world.."|Bob|"..e3}
ticks(12)
assert(bob.restores==4 and bob.ctx.my_player.entity.x==rewound.x and not bob.down)
-- An unsafe death point holds the same order. A living teammate may specify
-- an alternative near their own position after the recipient asks for one.
fall(bob);ticks(8)
local e4=assert(entry(alice,bob))
bob.blocked=true
request(alice,5,e4,bob,17,28);ticks(10)
assert(not answer(alice,5) and bob.down and bob.restores==4)
assert(host.globals["nh_ew.reinforce_targets"]:find("|redirect",1,true))
bob.blocked=false;bob.crowded=true
ticks(10);assert(not answer(alice,5) and bob.down)
bob.crowded=false;bob.unloaded=true
ticks(5,"command")
local retired=packets.command
offline.b=true;reload(bob);ticks(6)
alice.blocked=true;offline.b=false;tick("command")
bob.ctx.rpc_peer_id="h";bob.handlers.command(unpack(retired))
assert(bob.restores==4 and bob.down)
ticks(12);assert(not answer(alice,5) and bob.down)
bob.unloaded=false;bob.blocked=true;bob.alternateX=42
host.globals["nh_ew.reinforce_redirect"]=table.concat({world,"Bob",e4,42,30},"|")
ticks(14)
assert(answer(alice,5)=="ok" and not bob.down and bob.restores==5 and bob.ctx.my_player.entity.x==42)
bob.blocked=false;alice.blocked=false
fall(bob);ticks(7)
local e5=assert(entry(alice,bob))
alice.ctx.my_player.entity.x=900
request(alice,9,e4,bob,17,28);ticks(10)
assert(answer(alice,9)=="rejected" and bob.down)
for _,p in pairs(peers) do p.ctx.proxy_opt.game_mode="shared_health" end
tick();assert(host.globals["nh_ew.reinforce_mode"]=="" and alice.globals["nh_ew.reinforce_targets"]=="")
for _,p in pairs(peers) do p.ctx.proxy_opt.game_mode="local_health" end
for _,option in ipairs({"perma_death","no_notplayer","pvp"}) do
    for _,p in pairs(peers) do p.ctx.proxy_opt[option]=true end
    tick();assert(host.globals["nh_ew.reinforce_mode"]=="" and alice.globals["nh_ew.reinforce_targets"]=="")
    for _,p in pairs(peers) do p.ctx.proxy_opt[option]=false end
    tick();assert(host.globals["nh_ew.reinforce_mode"]==world)
end

-- Changing policy on a room restart must not spend or duplicate an old
-- delivery, even when its original landing site is gone and nobody is down.
local function restartAs(policy)
    for _,p in pairs(peers) do p.policy=policy; reload(p) end
    ticks(8)
end
local function held(p,tx)
    return host.settings["noita_hideout.ew_reinforce."..world.."."..owners[p.id]..".order."..tx]
end
alice.ctx.my_player.entity.x=10
fall(bob);ticks(8)
local e6=assert(entry(alice,bob))
request(alice,10,e6,bob,15,15); ticks(3,"confirm")
assert(bob.restores==6 and not answer(alice,10) and held(alice,10):match("|pending$"))
offline.b=true;alice.blocked=true;restartAs("native")
assert(not answer(alice,10) and not entry(alice,bob) and alice.globals["nh_ew.reinforce_mode"]=="")
assert(alice.down==false and bob.down==false)
offline.b=false;ticks(14)
assert(answer(alice,10)=="ok" and bob.restores==6)
-- An authorized original order with a lost command has no success receipt.
alice.blocked=false;restartAs("pod");fall(bob);ticks(8)
local e7=assert(entry(alice,bob))
request(alice,11,e7,bob,15,15);ticks(3,"command")
assert(held(alice,11):match("|pending$") and not answer(alice,11) and bob.down)
offline.b=true;alice.crowded=true;restartAs("native");assert(not answer(alice,11))
offline.b=false;ticks(14)
assert(answer(alice,11)=="rejected" and bob.down and bob.restores==6)
-- An unsubmitted reservation can be rejected entirely on the host.
offline.b=true;request(alice,12,e7,bob,15,15);ticks(10)
assert(answer(alice,12)=="rejected" and bob.restores==6)
-- A committed receipt is final even if an older downed entity reappears
-- after reload. Native revival policy must not replay a pod resurrection.
offline.b=false
local rewind=fall(bob);rewind.nh_ew_reinforce_episode={value_string=world.."|Bob|"..e6}
alice.globals["nh_ew.reinforce_result."..world..".Alice.10"]=nil
request(alice,10,e6,bob,15,15);ticks(10)
assert(answer(alice,10)=="ok" and bob.down and bob.restores==6)
-- No roster construction/advertisement in native/unsupported modes.
local quiet=sent;ticks(70);assert(sent==quiet)
for _,p in pairs(peers) do p.ctx.proxy_opt.game_mode="shared_health" end
ticks(70);assert(sent==quiet)
-- An old handshake token or any affirmative "lookup" must do nothing.
local function lookup(challenge,approved)
    host.ctx.rpc_peer_id="a"
    host.handlers.request(world,"Alice","13","Bob",e6,15,15,challenge,false,approved)
end
lookup("h-0",false);lookup("h-"..host.connection,true)
assert(not answer(alice,13) and not held(alice,13) and sent==quiet)
restartAs(nil)
assert(host.globals["nh_ew.reinforce_mode"]=="" and bob.globals["nh_ew.reinforce_targets"]=="")
assert(not bob.ctx.cap.health.nh_reinforce_hold())
local anchor=fall(bob);anchor.DamageModelComponent=nil;anchor.anchor=true
bob.nativeFallback=false;ticks(200)
assert(bob.ctx.cap.health.nh_reinforce_hold() and bob.down and not bob.nativeFallback and not bob.sharedFallback)
bob.policy="native";tick();assert(bob.nativeFallback)
bob.policy=nil;bob.ctx.proxy_opt.game_mode="local_health";bob.waitDuringGap=true
assert(bob.ctx.cap.health.nh_reinforce_wait() and not entry(host,bob))
bob.flags.ew_kill_player=true;assert(not bob.ctx.cap.health.nh_reinforce_wait())
bob.flags.ew_kill_player=nil;bob.policy="pod";bob.waitDuringGap=false
assert(not bob.ctx.cap.health.nh_reinforce_wait())
-- A disconnected caller can no longer drive the mailbox. The target's
-- receipt fences an old in-flight command before another profile is billed.
world="sponsorWorld";offline={};wire={}
host,alice,bob=makePeer("h"),makePeer("a"),makePeer("b")
local sponsorPrefix="nh_ew.reinforce_sponsor_"
local function orphan(tx)
    offline.a=false;reload(alice)
    fall(bob);ticks(10)
    local ep=assert(entry(alice,bob))
    request(alice,tx,ep,bob,10,30);ticks(5,"command")
    local original=alice.globals["nh_ew.reinforce_request"]
    local key="noita_hideout.ew_reinforce."..world..".Alice.order."..tx
    assert(host.settings[key]:match("|pending$") and bob.down)
    offline.a=true;reload(host);ticks(18)
    assert(host.settings[key..".sponsor"]=="offer|Bob" and bob.globals[sponsorPrefix.."offer"]==original)
    return original,key,ep
end
local function respond(p,order,debit) p.globals[sponsorPrefix.."reply"]=order.."|"..debit end
local function outcome(p,origin,debit)
    return p.globals[sponsorPrefix.."result."..world..".Alice."..origin.."."..owners[p.id].."."..debit]
end
local order,key,ep=orphan(20)
-- Even a fresh replay of the original packet cannot revive a fenced body.
local old=packets.command
old[9]=frame
bob.ctx.rpc_peer_id="h";bob.handlers.command(unpack(old));ticks(7)
assert(bob.down and bob.restores==0)
host.failSetting=key..".sponsor"
respond(bob,order,"43");ticks(10)
assert(bob.down and not outcome(bob,20,43))
host.failSetting=nil;ticks(24)
assert(host.settings[key..".sponsor"]=="paid|Bob|43" and outcome(bob,20,43)=="ok" and bob.restores==1)
offline.a=false;reload(alice);ticks(12)
assert(answer(alice,20)=="transferred" and bob.restores==1)
respond(bob,order,"44");ticks(8)
assert(outcome(bob,20,44)=="rejected" and bob.restores==1)

-- An unfunded target can defer to a living peer. A duplicate late debit
-- from the refused target can neither take the order nor trigger a revive.
order,key,ep=orphan(21)
respond(bob,order,"none");ticks(12)
assert(host.globals[sponsorPrefix.."offer"]==order)
respond(bob,order,"45");ticks(7)
assert(outcome(bob,21,45)=="rejected" and bob.down)
respond(host,order,"72");ticks(24)
assert(host.settings[key..".sponsor"]=="paid|Host|72" and outcome(host,21,72)=="ok" and bob.restores==2)
offline.a=false;reload(alice);ticks(12)
assert(answer(alice,21)=="transferred")

-- All eligible peers explicitly declined. A different living player can
-- issue a fresh call for the very same death after the host releases it.
order,key,ep=orphan(22)
respond(bob,order,"none");ticks(12)
respond(host,order,"none");ticks(14)
assert(host.settings[key]:match("|rejected$") and bob.down and bob.restores==2)
assert(host.settings["noita_hideout.ew_reinforce."..world..".Bob.down."..ep..".owner"]=="")
assert(bob.cancellations==1)
bob.ctx.rpc_peer_id="h";bob.handlers.noPayer(order);ticks(12)
assert(bob.cancellations==1 and not host.cancellations)
offline.a=false;reload(alice);ticks(12)
assert(answer(alice,22)=="rejected")
request(host,101,ep,bob,10,30);ticks(14)
assert(answer(host,101)=="ok" and bob.restores==3)
-- A paid receipt can redirect after terrain rollback without another order.
-- The original observation point stays fixed if spectating moves the entity.
local function rewindPaid()
    local observer=fall(bob)
    observer.x,observer.y=810,440
    observer.nh_ew_death_position={value_string="10|30"}
    observer.nh_ew_reinforce_episode={value_string=world.."|Bob|"..ep}
    reload(bob)
end
rewindPaid();bob.blocked=true;bob.alternateX=42;ticks(20)
assert(bob.down and alice.globals["nh_ew.reinforce_targets"]:find("|redirect",1,true))
alice.globals["nh_ew.reinforce_redirect"]=table.concat({world,"Bob",ep,42,30},"|")
ticks(24)
assert(not bob.down and bob.ctx.my_player.entity.x==42 and bob.restores==4)
assert(answer(host,101)=="ok")
-- The selected alternative is gone on a second rewind, but the original
-- death point has opened up again. Reuse the same paid episode there.
rewindPaid();bob.alternateX=10;ticks(24)
assert(not bob.down and bob.ctx.my_player.entity.x==10 and bob.ctx.my_player.entity.y==30 and bob.restores==5)
-- A success ACK missed the host while the payer disconnected. Rewinding
-- the same death can reuse its receipt, never a different player's funds.
bob.blocked=false;bob.alternateX=nil
fall(bob);ticks(9)
ep=assert(entry(alice,bob))
local beforeACK=bob.restores
request(alice,23,ep,bob,10,30);ticks(7,"confirm")
key="noita_hideout.ew_reinforce."..world..".Alice.order.23"
assert(host.settings[key]:match("|pending$") and not bob.down and bob.restores==beforeACK+1)
offline.a=true;reload(host)
local oldBody=fall(bob)
oldBody.nh_ew_reinforce_episode={value_string=world.."|Bob|"..ep}
bob.blocked=true;ticks(28)
assert(host.settings[key]:match("|ok$") and host.settings[key..".sponsor"]=="sealing")
assert(not (bob.globals[sponsorPrefix.."offer"] or ""):find("|Alice|23|",1,true))
offline.a=false;reload(alice);ticks(12)
assert(answer(alice,23)=="ok")
bob.blocked=false;ticks(22)
assert(not bob.down and bob.restores==beforeACK+2)
print("EW reinforcement: mutually exclusive revival, paid rollback, landing safety, fenced takeover, refunds and reconnect passed.")
