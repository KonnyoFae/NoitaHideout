local root = "mods/noita_hideout/files/"
local rpc, cross, sender, sent = {}, {}, nil, {}
local handlers, reliable = {}, false
function rpc.opts_reliable() reliable=true end
setmetatable(rpc, {__newindex=function(t, k, v)
    assert(reliable); reliable=false
    handlers[k]=v
    rawset(t,k,function(...) sent[#sent+1]={...} end)
end})
local api = {
    new_rpc_namespace=function(name) assert(name=="nh_tarot_shared_health"); return rpc end,
    rpc_player_data=function() return sender end,
}
function dofile_once(path)
    if path == "mods/quant.ew/files/api/ew_api.lua" then return api end
    return dofile(path)
end
util={add_cross_call=function(name,fn) cross[name]=fn end}
function CrossCall(name,...) return cross[name](...) end
local globals, enabled = {}, true
function ModIsEnabled(id) assert(id=="quant.ew"); return enabled end
function GlobalsGetValue(key, fallback) return globals[key] or fallback end
function GlobalsSetValue(key, value) globals[key]=value end
local hp, maximum, writes = 51,100,0
local health={health=function() return hp end, max_health=function() return maximum end,
    set_health=function(amount) writes=writes+1; hp=amount end}
ctx={proxy_opt={game_mode="shared_health"},cap={health=health},is_host=false,ready=true,
    my_id="guest",host_id="host",my_player={entity=1}}
local boots={host="h1",guest="g1",second="s1"}
local world="world-1"
nh_ew_session={world=function() return world end,challenge=function(peer) return boots[peer] end}
local hooks=dofile(root.."tarot_shared_health_ew.lua")
local client=dofile(root.."tarot_shared_health.lua")
hooks.on_world_initialized()
-- Positive changes go through the native HP-difference path exactly once.
for _,kind in ipairs({"sun_use","sun_tick","devil_kill"}) do assert(not client.change(1,kind,1)) end
assert(client.change(1,"devil_tick",1))
assert(hp==51 and #sent==1 and writes==0)
ctx.my_id="second"
assert(client.change(1,"devil_tick",1))
assert(#sent==2 and hp==51)

ctx.is_host=true; ctx.my_id="host"; sender={peer_id="guest"}
handlers.drain(unpack(sent[1]))
sender={peer_id="second"}
handlers.drain(unpack(sent[2]))
assert(hp==50 and writes==1, "two casters at 51% cannot cross the shared floor")
assert(client.change(1,"devil_tick",1) and hp==50 and writes==1)
-- Native incoming combat and other real health changes remain unrestricted.
health.set_health(34)
assert(client.change(1,"devil_tick",2) and hp==34)
hp=97
handlers.drain(unpack(sent[2]))
assert(hp==97, "duplicate sequence must not charge the shared pool again")
assert(client.change(1,"devil_tick",3) and hp==94, "host pulse has no RPC echo")
assert(#sent==2)
boots.second="s2"
handlers.drain(unpack(sent[2]))
handlers.drain("world-1","s2","wrong-host",1,2)
handlers.drain("world-2","s2","h1",1,2)
handlers.drain("world-1","s2","h1",1,-1)
assert(hp==94, "ignore expired rooms, expired connections and invalid counts")
handlers.drain("world-1","s2","h1",1,100)
assert(hp==50)
ctx.proxy_opt.game_mode="local_health"
hooks.on_local_player_spawn()
assert(not client.change(1,"devil_tick",1))
ctx.proxy_opt.game_mode="shared_health"; hooks.on_local_player_spawn(); enabled=false
assert(not client.change(1,"devil_tick",1), "an EW save opened without EW uses the ordinary player HP")
print("EW native local healing and host-serialized Devil health floor, concurrent casts, room checks and ordinary damage passed.")
