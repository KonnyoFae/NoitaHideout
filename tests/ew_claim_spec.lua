local settings,globals={},{}
local currentWorld,frame="world-A",4
local failField
local members={host="Host",guest="Guest",third="Third"}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) if key~=failField then settings[key]=value end end
function GlobalsGetValue(key,d) return globals[key] or d end
function GlobalsSetValue(key,value) globals[key]=value end
function GameGetFrameNum() return frame end
local boots={host="hostStart",guest="guestStart",reconnected="newStart",third="thirdStart"}
nh_ew_session={world=function() return currentWorld end,issuer=function(peer) return members[peer] end,
    challenge=function(peer) return boots[peer] end}
ctx={is_host=true,my_id="host",host_id="host"}
local rpc,receive,host,reply
local bridges={}
util={add_cross_call=function(name,callback) bridges[name]=callback end}
local function restart()
    globals={}
    rpc={opts_reliable=function() end}
    function dofile_once()
        return {new_rpc_namespace=function(name) assert(name=="nh_pickup2");return rpc end}
    end
    host=dofile("mods/noita_hideout/files/ew_claim.lua")
    receive=rpc.reply
    rpc.reply=function(...) reply={...} end
end
restart()
local function send(peer,tx,keys,action,as,world)
    ctx.rpc_peer_id=peer
    reply=nil
    rpc.request(world or currentWorld,as or members[peer],tx,table.concat(keys,","),action)
    if reply then
        assert(reply[1]==peer and reply[2]==(world or currentWorld) and reply[3]==(as or members[peer])
            and reply[4]==tx and reply[5]==table.concat(keys,","))
        return reply[6]
    end
end
local gid="g/18446744073709551615"
local ticket="t/ew/Host/r/1/4/3/2/102/234"
local keys={ticket,gid}
assert(not send("guest","1",keys,"prepare","Host"))
assert(not send("guest","1",keys,"prepare",nil,"stale-world"))
assert(not send("absent","1",keys,"prepare","Guest"))
assert(not send("guest","01",keys,"prepare"))
assert(not send("guest","1",{gid,gid},"prepare"))
assert(not send("guest","1",{"g/3",gid,"g/1"},"prepare"))
assert(not send("guest","1",{gid,"g/garbage"},"prepare"))
assert(not send("guest","1",keys,"madeup"))
assert(not send("guest","1",keys,"commit") and not next(settings))

-- Persisted partial prepare. A commit cannot complete a partially written
-- grant, even if the client repeats it after the host process restarts.
failField="noita_hideout.ew_item_tx.world-A.key."..gid
assert(not send("guest","1",keys,"prepare"))
restart()
assert(not send("guest","1",keys,"commit"))
assert(send("third","1",{ticket},"prepare")=="denied")
failField=nil
assert(send("guest","1",keys,"prepare")=="granted")
assert(send("guest","1",{gid,ticket},"cancel")=="denied")
assert(not send("guest","2",keys,"cancel"))
assert(send("host","1",{gid},"prepare")=="denied")
restart()
members.reconnected,members.guest=members.guest,nil
assert(not send("guest","1",keys,"cancel","Guest"))
assert(send("reconnected","1",keys,"prepare")=="granted")
assert(send("reconnected","1",keys,"cancel")=="cancelled")
assert(send("reconnected","1",keys,"commit")=="cancelled")

-- The second player can now claim BOTH keys; neither a delayed prepare nor
-- a cancel from the first player can resurrect or release them.
assert(send("host","2",keys,"prepare")=="granted")
assert(send("reconnected","1",keys,"prepare")=="cancelled")
assert(send("reconnected","1",keys,"cancel")=="cancelled")
assert(send("third","2",{gid},"prepare")=="denied")
assert(send("host","2",keys,"commit")=="done")
restart()
assert(send("host","2",keys,"commit")=="done")
assert(send("host","2",keys,"cancel")=="done")
assert(send("host","3",keys,"prepare")=="denied")
assert(send("reconnected","3",{ticket},"prepare")=="denied")
assert(send("third","3",{gid},"prepare")=="denied")
assert(send("host","2",keys,"prepare")=="done")

-- The reconciliation probe has no reservation side effects. Only the exact
-- release key in a completed transaction is evidence, across holders/GIDs.
do
    local probe,proof=rpc.release_probe,rpc.release_proof
    local answer
    rpc.release_proof=function(...) answer={...} end
    ctx.rpc_peer_id="third"
    local function check(world,holder,boot,hostBoot,key)
        answer=nil;probe(world,holder,boot,hostBoot,key);return answer and answer[7]
    end
    assert(check(currentWorld,"Third",boots.third,boots.host,ticket)=="Host|2")
    assert(not check(currentWorld,"Guest",boots.third,boots.host,ticket))
    assert(not check("world-B","Third",boots.third,boots.host,ticket))
    assert(not check(currentWorld,"Third","older",boots.host,ticket))
    assert(not check(currentWorld,"Third",boots.third,"older",ticket))
    assert(not check(currentWorld,"Third",boots.third,boots.host,gid))
    local other="t/ew/Host/r/1/4/3/2/102/235"
    local base="noita_hideout.ew_item_tx.world-A."
    settings["noita_hideout.ew_claim.world-A."..other]="Host"
    assert(check(currentWorld,"Third",boots.third,boots.host,other)=="")
    settings[base.."key."..other]="Host|2"
    assert(check(currentWorld,"Third",boots.third,boots.host,other)=="") -- stale index
    for _,phase in ipairs({"preparing","granted","denied","cancelled"}) do
        settings[base.."key."..other]="Guest|67";settings[base.."Guest.67"]=phase.."|"..other
        assert(check(currentWorld,"Third",boots.third,boots.host,other)=="")
    end
    local outgoing,count=nil,0
    rpc.release_probe=function(...) outgoing={...};count=count+1 end
    ctx.my_id,ctx.is_host="third",false
    local slot="nh_ew.release_winner"
    local function poll()
        globals[slot]=""
        bridges.ew_hideout_release_winner(currentWorld,"Third",ticket)
        return globals[slot]
    end
    assert(poll()=="" and outgoing[5]==ticket and count==1)
    ctx.rpc_peer_id="reconnected";proof("third",currentWorld,"Third",boots.third,boots.host,ticket,"Host|2")
    ctx.rpc_peer_id="host";proof("third",currentWorld,"Third","older",boots.host,ticket,"Host|2")
    proof("third",currentWorld,"Third",boots.third,boots.host,other,"Host|2")
    assert(poll()=="" and count==1)
    proof("third",currentWorld,"Third",boots.third,boots.host,ticket,"Host|2")
    proof("third",currentWorld,"Third",boots.third,boots.host,ticket,"")
    assert(poll()=="Host|2")
    boots.third="thirdRestart";assert(poll()=="" and count==2)
    proof("third",currentWorld,"Third","thirdStart",boots.host,ticket,"Host|2")
    assert(poll()=="")
    boots.host="hostRestart";assert(poll()=="" and count==3)
    currentWorld="world-B";assert(poll()=="" and count==4)
    ctx.is_host,ctx.my_id,currentWorld=true,"host","world-A"
    rpc.release_probe,rpc.release_proof=probe,proof
end

-- Cancel-before-prepare leaves a durable tombstone, even for the first
-- message of a new transaction. A lower, previously unseen serial is stale.
assert(send("host","8",{"g/700"},"cancel")=="cancelled")
restart()
assert(send("host","8",{"g/700"},"prepare")=="cancelled")
assert(send("host","7",{"g/701"},"prepare")=="denied")
assert(send("third","4",{"g/700"},"prepare")=="granted")
assert(send("third","4",{"g/700"},"commit")=="done")

-- Pre-0.42.26 receipts are permanent. The original winner may resume;
-- cancelling a new reservation cannot release that legacy constraint.
local old="noita_hideout.ew_claim.world-A.g/555"
settings[old]="Guest"
assert(send("host","9",{"g/714","g/555"},"prepare")=="denied")
assert(send("third","5",{"g/714"},"prepare")=="granted")
assert(send("third","5",{"g/714"},"cancel")=="cancelled")
assert(send("reconnected","4",{"g/555"},"prepare")=="granted")
assert(send("reconnected","4",{"g/555"},"cancel")=="cancelled")
assert(settings[old]=="Guest" and send("host","10",{"g/555"},"prepare")=="denied")
assert(send("reconnected","5",{"g/555"},"prepare")=="granted")
assert(send("reconnected","5",{"g/555"},"commit")=="done")

-- Bridge responses are host-only and bound to the current world, issuer,
-- request and serial. An old grant cannot overwrite a terminal result.
ctx.is_host,ctx.my_id=false,"reconnected"
local id="world-A|Guest|5|g/555|"
globals["nh_ew.item_request"]=id.."commit"
ctx.rpc_peer_id="third"
receive("reconnected","world-A","Guest","5","g/555","done")
assert(not globals["nh_ew.item_tx_reply"])
ctx.rpc_peer_id="host"
receive("reconnected","world-A","Guest","4","g/555","done")
receive("third","world-A","Guest","5","g/555","done")
receive("reconnected","world-B","Guest","5","g/555","done")
receive("reconnected","world-A","Host","5","g/555","done")
assert(not globals["nh_ew.item_tx_reply"])
receive("reconnected","world-A","Guest","5","g/555","done")
receive("reconnected","world-A","Guest","5","g/555","granted")
assert(globals["nh_ew.item_tx_reply"]==id.."done")
host.on_world_update()
assert(globals["nh_ew.item_request"]=="")

-- The host's own bridge uses the same state machine. A fresh world has a
-- separate ledger even when both the owner's serial and the GID recur.
ctx.is_host,ctx.my_id,currentWorld=true,"host","world-B"
local own="world-B|Host|1|"..gid.."|"
globals["nh_ew.item_request"]=own.."prepare"
host.on_world_update()
assert(globals["nh_ew.item_tx_reply"]==own.."granted")
frame=8
globals["nh_ew.item_request"]=own.."commit"
host.on_world_update()
assert(globals["nh_ew.item_tx_reply"]==own.."done")
local localPlayer,flask,other=7,41,42
ctx.my_player={entity=localPlayer}
local inv={mThrowItem=flask,mActualActiveItem=flask,mActiveItem=flask}
local hasLock,cleared=true,false
function EntityGetIsAlive(id) return id==localPlayer or id==flask or id==other end
function EntityGetRootEntity(item) return item==flask and localPlayer or other end
function EntityHasTag() return false end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    if id==localPlayer and kind=="Inventory2Component" then return inv end
    if id==flask and tag=="nh_ew_deposit_lock" and hasLock then return 11 end
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
np={SetActiveHeldEntity=function(p,id) assert(p==localPlayer and id==0);cleared=true end}
local unselect=bridges.ew_hideout_deposit_unselect
unselect(other,flask);unselect(localPlayer,other)
hasLock=false;unselect(localPlayer,flask)
assert(not cleared and inv.mThrowItem==flask)
hasLock=true;unselect(localPlayer,flask)
assert(cleared and inv.mThrowItem==0)
print("EW item transactions: atomic keys, cancellation, replay, persistence, handoff, legacy receipts and authenticated replies passed.")
