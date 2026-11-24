-- The downed player's client authorizes the opening. Every loaded view,
-- including that client's, animates an unsaved sprite at the chosen point.
local api=dofile_once("mods/quant.ew/files/api/ew_api.lua")
local rpc=api.new_rpc_namespace("nh_podfx1")
local M={}
local root="mods/noita_hideout/files/"
local room,localBoot,flight,serial=nil,nil,nil,0
local live,latest={},{}
local function pixel(n) return type(n)=="number" and n==math.floor(n) and math.abs(n)<1073741824 end
local function remove(peer)
    local p=live[peer]
    if p and p.entity and EntityGetIsAlive(p.entity) then EntityKill(p.entity) end
    live[peer]=nil
end
local function reset(world,boot)
    for peer in pairs(live) do remove(peer) end
    room,localBoot,flight=world,boot,nil
end
local function supported(world)
    return world and nh_ew_session and nh_ew_session.world()==world and GlobalsGetValue("nh_ew.reinforce_mode","")==world
end
local function sender(world,boot,id)
    if room~=world or not supported(world) or type(boot)~="string" or not pixel(id) or id<1 then return end
    local p=api.rpc_player_data()
    if p and p.peer_id~=ctx.my_id and nh_ew_session.challenge(p.peer_id)==boot then return p.peer_id end
end

local function begin(peer,boot,id,x,y,bottom)
    if not peer or not pixel(x) or not pixel(y) or not pixel(bottom) or y>=bottom or bottom-y>170 then return end
    local last=latest[peer]
    if last and last.boot==boot and last.id>=id then return end
    remove(peer)
    latest[peer]={boot=boot,id=id}
    live[peer]={boot=boot,id=id,x=x,y=y,bottom=bottom,speed=1,since=GameGetFrameNum()}
end
rpc.opts_reliable()
function rpc.begin(world,boot,id,x,y,bottom)
    begin(sender(world,boot,id),boot,id,x,y,bottom)
end
local function finish(peer,boot,id,kind,y)
    local p=peer and live[peer]
    if not p or p.boot~=boot or p.id~=id then return end
    if kind=="cancel" then remove(peer)
    elseif kind=="open" and not p.open and pixel(y) and math.abs(p.bottom-y)<=4 then
        p.bottom,p.open=y,true
    end
end
rpc.opts_reliable()
function rpc.finish(world,boot,id,kind,y)
    finish(sender(world,boot,id),boot,id,kind,y)
end

local function visual(path,x,y,tag)
    local id=util.load_ephemerial(root..path,x,y)
    if not id or id==0 then return end
    EntityAddTag(id,"ew_no_enemy_sync")
    EntityAddTag(id,tag)
    return id
end
local function animate(f)
    for peer,p in pairs(live) do
        if nh_ew_session.challenge(peer)~=p.boot or f-p.since>120 then
            remove(peer)
        else
            local loaded=DoesWorldExistAt(p.x-8,math.floor(p.y)-8,p.x+8,math.ceil(p.y)+8)
            if loaded and not p.entity then
                p.entity=visual("supply_pod.xml",p.x,p.y,"nh_ew_reinforce_pod_fx")
                if p.entity then EntityRemoveTag(p.entity,"nh_supply_pod") end
            end
            p.speed=math.min(5,p.speed+0.18)
            p.y=math.min(p.bottom,p.y+p.speed)
            if p.entity and EntityGetIsAlive(p.entity) then EntitySetTransform(p.entity,p.x,p.y) end
            if p.open and p.y==p.bottom then
                if DoesWorldExistAt(p.x-8,p.y-8,p.x+8,p.y+8) then
                    visual("pod_open_fx.xml",p.x,p.y,"nh_ew_reinforce_open_fx")
                end
                remove(peer)
            end
        end
    end
end
local function take(key)
    local v=GlobalsGetValue(key,"")
    if v~="" then GlobalsSetValue(key,"");return v end
end
local function recent(f,stamp) return stamp and f>=tonumber(stamp) and f-tonumber(stamp)<=32 end
function M.on_world_initialized()
    serial,latest=0,{}
    reset(nil,nil)
    GlobalsSetValue("nh_ew.pod_start","");GlobalsSetValue("nh_ew.pod_end","")
end
function M.on_world_update()
    local f=GameGetFrameNum()
    if f%3~=0 and not next(live) then return end
    local world=nh_ew_session and nh_ew_session.world()
    local boot=world and nh_ew_session.challenge(ctx.my_id)
    if room~=world or localBoot~=boot then reset(world,boot) end
    if not boot or not supported(world) then
        if next(live) then reset(nil,nil) end
        return
    end
    if f%3==0 then
        local start=take("nh_ew.pod_start")
        if start then
            local w,ng,key,stamp,x,y,bottom=start:match("^([%w_-]+)|(%d+)|(%d+%.%d+)|(%d+)|(-?%d+)|(-?%d+)|(-?%d+)$")
            if w==world and tonumber(ng)==tonumber(SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) and recent(f,stamp) then
                serial=serial+1;flight=key
                begin(ctx.my_id,boot,serial,tonumber(x),tonumber(y),tonumber(bottom))
                rpc.begin(world,boot,serial,tonumber(x),tonumber(y),tonumber(bottom))
            end
        end
        local ended=take("nh_ew.pod_end")
        if ended then
            local w,ng,key,stamp,kind,y=ended:match("^([%w_-]+)|(%d+)|(%d+%.%d+)|(%d+)|(%a+)|(-?%d+)$")
            if w==world and flight==key and tonumber(ng)==tonumber(SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) and recent(f,stamp) then
                finish(ctx.my_id,boot,serial,kind,tonumber(y))
                rpc.finish(world,boot,serial,kind,tonumber(y));flight=nil
            end
        end
    end
    if next(live) then animate(f) end
end
return M
