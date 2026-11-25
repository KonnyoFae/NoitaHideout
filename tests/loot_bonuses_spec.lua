local root="mods/noita_hideout/files/"
local a,b,frame=11,22,100
local tags={[a]={player_unit=true},[b]={ew_client=true}}
local timers={[a]={},[b]={}}
local globals={}
function EntityGetIsAlive(id) return tags[id]~=nil end
function EntityHasTag(id,key) return tags[id][key] end
function GameGetFrameNum() return frame end
function GlobalsGetValue(k,d) return globals[k] or d end
function GlobalsSetValue(k,v) globals[k]=v end
function EntityGetFirstComponentIncludingDisabled(id,kind,key)
    assert(kind=="VariableStorageComponent")
    return timers[id][key]
end
function EntityAddComponent2(id,kind,fields)
    assert(kind=="VariableStorageComponent" and not timers[id][fields._tags])
    timers[id][fields._tags]=fields
    return fields
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end

local function loadBonuses()
    local env=setmetatable({dofile=function(path)
        assert(path==root.."loot_bonus_sources.lua")
        local definitions=dofile(path)
        definitions[#definitions+1]={id="test_charm",duration=600,events={enemy_kill={red=.2},test_event={bag=.5}}}
        return definitions
    end},{__index=_G})
    return setfenv(assert(loadfile(root.."loot_bonuses.lua")),env)()
end

local bonuses=loadBonuses()
assert(not bonuses.rerolls(a,"enemy_kill") and not bonuses.activate(b,"test_charm"))
-- Timers already written to a real player by version 0.42.42.
local old=EntityAddComponent2(a,"VariableStorageComponent",{_tags="nh_salvage_bell",value_int=frame+17})
local base=bonuses.rerolls(a,"enemy_kill")
assert(base.bag==.25 and base.tarot==.25 and base.red==.25 and not bonuses.rerolls(a,"test_event"))
assert(bonuses.activate(a,"test_charm"))
local function mixed(id)
    local r=assert(bonuses.rerolls(id,"enemy_kill"))
    assert(r.bag==.25 and r.tarot==.25 and math.abs(r.red-.4)<1e-12)
end
mixed(a)
assert(bonuses.rerolls(a,"test_event").bag==.5)
frame=115
assert(bonuses.activate(a,"salvage_bell") and bonuses.activate(a,"test_charm"))
assert(old.value_int==frame+54000 and bonuses.remaining(a,"test_charm")==600)
bonuses=loadBonuses()
mixed(a)
-- A source restricted to red never consumes the bag or tarot gate draws.
local drops=dofile(root.."enemy_drops.lua")
local function redOnly(threshold)
    local used={}
    local values={[1]=.88,[2]=.9,[3]=.9,[10]=threshold,[11]=0}
    local _,t,r=drops.roll(4,true,function(n) assert(not used[n]); used[n]=true; return assert(values[n]) end,{red=.2})
    assert(not t)
    return r,used
end
assert(redOnly(.2-1e-8) and not redOnly(.2))
local redRate,tarotRate=.0024,.032
local function effective(p,q) return p+(1-p)*q*p end
assert(math.abs(effective(redRate,base.red)-.00299856)<1e-12)
assert(math.abs(effective(tarotRate,base.tarot)-.039744)<1e-12)

local api,rpc,receive,sent={},nil,nil,{}
local sender={entity=b,peer_id="B"}
local room,boots="room",{A="connA",B="connB"}
ctx={my_id="A",my_player={entity=a}}
nh_ew_session={world=function() return room end,challenge=function(id) return boots[id] end}
function api.rpc_player_data() return sender end
function api.new_rpc_namespace(name)
    assert(name=="nh_loot_bonuses")
    rpc={opts_reliable=function() end}
    return rpc
end
function dofile_once(path)
    if path==root.."loot_bonuses.lua" then return bonuses end
    assert(path=="mods/quant.ew/files/api/ew_api.lua")
    return api
end
local bridge=dofile(root.."loot_bonuses_ew.lua")
receive=rpc.status
rpc.status=function(...) sent[#sent+1]={...} end
bridge.on_world_initialized()
bridge.on_world_update()
assert(#sent==1 and sent[1][4].salvage_bell==54000 and sent[1][4].test_charm==600)
local function receiveAsB(sequence,snapshot)
    receive(room,boots.B,sequence,snapshot)
end
receiveAsB(1,sent[1][4])
mixed(b)
frame=frame+30
receiveAsB(1,sent[1][4])
assert(bonuses.remaining(b,"test_charm")==150)
receiveAsB(2,{test_charm=301,salvage_bell=54001})
receiveAsB(2,{unregistered=50})
receive("different room",boots.B,2,{})
receive(room,"old connection",2,{})
sender.dc=true
receiveAsB(2,{})
sender.dc=false
assert(bonuses.remaining(b,"test_charm")==150)
receiveAsB(2,{test_charm=80})
assert(bonuses.remaining(b,"test_charm")==80 and bonuses.remaining(b,"salvage_bell")==0)
-- A reloaded replica may be reused with a different local frame clock.
local savedFrame=frame
frame=0
assert(bonuses.remaining(b,"test_charm")==0)
frame=savedFrame
frame=frame+80
assert(not bonuses.rerolls(b,"enemy_kill"))
-- Scope changes and reconnects can restart the sequence, retaining the
-- authenticated actor and rejecting old packets for either connection.
boots.B="nextB"
receiveAsB(1,{salvage_bell=75})
assert(bonuses.remaining(b,"salvage_bell")==75)
receive(room,"connB",3,{})
assert(bonuses.remaining(b,"salvage_bell")==75)
tags[b].nh_ew_waiting=true
assert(not bonuses.rerolls(b,"enemy_kill"))
tags[b].nh_ew_waiting=nil
-- Heartbeats only publish live sources or their expiration. Reloading the
-- Lua module must see the original persisted local deadlines.
frame=240
bridge.on_world_update()
assert(#sent==2 and sent[2][4].test_charm==475)
frame=720
bridge.on_world_update()
assert(#sent==3 and not sent[3][4].test_charm and sent[3][4].salvage_bell)
frame=54120
bridge.on_world_update()
assert(#sent==4 and not next(sent[4][4]))
frame=54240
bridge.on_world_update()
assert(#sent==4 and not next(bonuses.snapshot(a)))
print("Per-event source stacking, refresh, legacy saves, independent retry lanes and scoped EW snapshots passed.")
