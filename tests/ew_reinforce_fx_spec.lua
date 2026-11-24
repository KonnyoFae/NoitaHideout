local root="mods/noita_hideout/files/"
local frame,room,ng=0,"world_a",0
local boots={host="host_a",guest="guest_a"}
local messages={}
local function client(id)
    local c={save={},entities={},handlers={},loaded=true,opens=0,pods=0}
    local e=setmetatable({},{__index=_G})
    e.ctx={my_id=id}
    e.nh_ew_session={world=function() return room end,challenge=function(peer) return boots[peer] end}
    e.GlobalsGetValue=function(k,d) return c.save[k] or d end
    e.GlobalsSetValue=function(k,v) c.save[k]=v end
    e.GameGetFrameNum=function() return frame end
    e.SessionNumbersGetValue=function() return tostring(ng) end
    e.DoesWorldExistAt=function() return c.loaded end
    e.EntityAddTag=function(p,t) p[t]=true end
    e.EntityRemoveTag=function(p,t) p[t]=nil end
    e.EntityGetIsAlive=function(p) return not p.dead end
    e.EntityKill=function(p) assert(not p.dead);p.dead=true end
    e.EntitySetTransform=function(p,x,y) assert(not p.dead);p.x,p.y=x,y end
    e.util={load_ephemerial=function(path,x,y)
        assert(c.loaded and (path==root.."supply_pod.xml" or path==root.."pod_open_fx.xml"))
        local p={path=path,x=x,y=y}
        if path==root.."supply_pod.xml" then c.pods=c.pods+1;p.nh_supply_pod=true;c.pod=p
        else c.opens=c.opens+1;c.open=p end
        c.entities[#c.entities+1]=p
        return p
    end}
    local api={rpc_player_data=function() return {peer_id=c.sender} end}
    function api.new_rpc_namespace(name)
        assert(name=="nh_podfx1")
        local reliable=false
        return setmetatable({opts_reliable=function() reliable=true end},{__newindex=function(t,k,v)
            assert(reliable);reliable=false;c.handlers[k]=v
            rawset(t,k,function(...) messages[#messages+1]={id,k,{...}} end)
        end})
    end
    e.dofile_once=function(path) assert(path:find("ew_api.lua",1,true));return api end
    c.hook=setfenv(assert(loadfile(root.."ew_reinforce_fx.lua")),e)()
    c.hook.on_world_initialized();c.save["nh_ew.reinforce_mode"]=room
    return c
end
local host,guest=client("host"),client("guest")
local function tick(n)
    for i=1,n do frame=frame+1;host.hook.on_world_update();guest.hook.on_world_update() end
end
local function receive(c,m)
    c.sender=m[1];c.handlers[m[2]](unpack(m[3]))
end
local function begin(n)
    local key=frame.."."..n
    host.save["nh_ew.pod_start"]=table.concat({room,ng,key,frame,20,10,69},"|")
    tick(3)
    return key,messages[#messages]
end
local function finish(key,kind)
    host.save["nh_ew.pod_end"]=table.concat({room,ng,key,frame,kind,69},"|")
    tick(3)
    return messages[#messages]
end
tick(93);assert(#messages==0)
local key,start=begin(1);assert(#messages==1 and start[2]=="begin")
receive(host,start);receive(guest,start);receive(guest,start);tick(6)
assert(host.pods==1 and guest.pods==1 and guest.pod.y>10 and guest.pod.y<69)
assert(guest.pod.nh_ew_reinforce_pod_fx and guest.pod.ew_no_enemy_sync and not guest.pod.nh_supply_pod)
local close=finish(key,"open");receive(guest,close);receive(guest,close);tick(30)
assert(host.pod.dead and host.opens==1 and guest.pod.dead and guest.opens==1 and guest.open.nh_ew_reinforce_open_fx and guest.open.y==69)
receive(guest,start);receive(guest,close);tick(50);assert(guest.pods==1 and guest.opens==1 and #messages==2)

key,start=begin(2);receive(guest,start);tick(3);assert(guest.pods==2)
close=finish(key,"cancel");receive(guest,close);tick(40);assert(guest.pod.dead and guest.opens==1)
guest.loaded=false;key,start=begin(3);receive(guest,start);receive(guest,finish(key,"open"));tick(50)
assert(guest.pods==2 and guest.opens==1)
guest.loaded=true;key,start=begin(4);receive(guest,start);tick(3);assert(guest.pods==3)
local before=#messages
room=nil;tick(3);assert(guest.pod.dead)
room="world_a";tick(3);receive(guest,start);tick(4);assert(guest.pods==3)
key,start=begin(5);assert(start[3][3]==5);receive(guest,start);tick(3);assert(guest.pods==4)
room="world_b";boots.host="host_b";host.save["nh_ew.reinforce_mode"]=room;guest.save["nh_ew.reinforce_mode"]=room
tick(3);assert(guest.pod.dead)
receive(guest,start);tick(3);assert(guest.pods==4)
local forged={"host","begin",{room,"host_a",888,20,10,69}};receive(guest,forged);tick(3);assert(guest.pods==4)
-- A saved one-shot from a former NG+ must not become a fresh animation.
host.save["nh_ew.pod_start"]=table.concat({room,ng,"99.1",frame,20,10,69},"|");ng=1;tick(60)
assert(#messages==before+1 and host.pods==5 and host.opens==2)
print("EW pod FX: one visible descent, open/cancel, unloaded area, duplicate suppression, room/NG+/session replay guards and idle silence passed.")
