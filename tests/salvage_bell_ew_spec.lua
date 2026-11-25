local root="mods/noita_hideout/files/"
local rx,sent,sweeps={},{},{}
local source,world,own,frame=nil,"run","bootA",0
local sender={peer_id="B",entity=22}
local rpc=setmetatable({opts_reliable=function() end},{
    __newindex=function(t,k,v)
        rx[k]=v
        rawset(t,k,function(...) sent[#sent+1]={k,...} end)
    end,
})
ctx={my_id="A",my_player={entity=11}}
nh_ew_session={world=function() return world end,challenge=function(id) return id=="A" and own or id=="B" and "bootB" end}
local audio,globals=0,{}
function GlobalsSetValue(key,v) globals[key]=v end
function GlobalsGetValue(key,default) return globals[key] or default end
function EntityGetTransform(p) assert(p==11); return 45,-202 end
function GameGetFrameNum() return frame end
function dofile_once(path)
    if path==root.."salvage_bell.lua" then
        return {bridgeField="bridge",requestField="request",
            pull=function(x,y,ew) assert(ew); sweeps[#sweeps+1]={x,y} end,
            sound=function() audio=audio+1 end}
    end
    return {new_rpc_namespace=function() return rpc end,rpc_player_data=function() return source end}
end
local module=dofile(root.."salvage_bell_ew.lua")
globals.request="previous|boot|0|45|-202"
module.on_world_initialized()
assert(globals.request=="" and globals.bridge=="")
frame=5
module.on_world_update()
assert(globals.bridge=="run|bootA|5" and #sent==0)
globals.request="run|bootA|6|45|-202"
frame=10
module.on_world_update()
assert(globals.request=="" and #sent==1 and table.concat(sent[1],",")=="ring,run,bootA,1,45,-202")
frame=120
module.on_world_update()
assert(#sent==1)
frame=240
module.on_world_update()
assert(#sent==1)
source=sender
local function receive(w,b,seq,x) rx.ring(w,b,seq,x or 10,20) end
receive("old run","bootB",30)
receive("run","old boot",30)
receive("run","bootB",0)
receive("run","bootB",1,0/0)
assert(#sweeps==0)
receive("run","bootB",1)
receive("run","bootB",1)
assert(#sweeps==1 and audio==1)
sender.dc=true
receive("run","bootB",2)
assert(#sweeps==1)
sender.dc=false
world="next"
receive("next","bootB",1)
assert(#sweeps==2)
globals.request="run|bootA|241|1|1"
frame=245
module.on_world_update()
assert(globals.request=="" and globals.bridge=="next|bootA|245" and #sent==1)
globals.request="next|bootA|246|1|1"
world=nil
frame=250
module.on_world_update()
assert(globals.bridge=="" and globals.request~="" and #sent==1)
world="next"
frame=255
module.on_world_update()
assert(globals.request=="" and globals.bridge=="next|bootA|255" and #sent==2)
print("EW bell sweeps authenticate session and sender, deduplicate each ring, and resume pending casts on reconnect.")
