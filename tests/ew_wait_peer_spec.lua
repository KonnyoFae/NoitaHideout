local root = "mods/noita_hideout/files/"
local base = "mods/quant.ew/files/"
local sources = {
    ["system/player_sync.lua"] = [=[
local last_money
local was_polied = false
function sampleWallet(wallet)
        if was_polied ~= ctx.my_player.currently_polymorphed then
            ComponentSetValue2(wallet, "money", last_money)
        end
        was_polied = ctx.my_player.currently_polymorphed
        local delta = last_money and wallet.money - last_money or 0
        last_money = wallet.money
        return delta
end
local function undc(ent)
    showAvatar(ent)
end
function onInput(player_data, input_data, pos_data)
    if input_data ~= nil then
        moveAvatar(player_data)
    end
end
function render(ent)
    for i=1,1 do
            local children = EntityGetAllChildren(ent) or {}
            drawCape(ent)
        ::continue::
    end
end
return undc]=],
    ["system/notplayer_ai/notplayer_ai.lua"] = [=[
return function(active)
    if active and EntityGetIsAlive(ctx.my_player.entity) and EntityHasTag(ctx.my_player.entity, "ew_notplayer") then
        return "autoplay"
    end
end]=],
    ["system/spectate/spectate.lua"] = [=[
local re_cam, camera_player_id, camera_player
local function cant_spectate(ent, peer_id)
    return false
end
local function disable_throwing(inv, entity)
    for _, item in ipairs(EntityGetAllChildren(inv) or {}) do
        lock(item)
    end
end
local function get_me()
    local alive = {-1,-1}
    local i = 0
    for peer_id, p in pairs(ctx.players) do
        if cant_spectate(p.entity, peer_id) then goto continue end
        i = i + 1
        alive = { peer_id, i }
        if peer_id == ctx.my_id then
            return peer_id, i
        end
        ::continue::
    end
    return unpack(alive)
end
local function update_i()
    camera_player_id, camera_player = get_me()
end

local function number_of_players()
end
local function attach(cam_target)
        if ctx.my_player.entity ~= cam_target.entity then
            inventory_target = EntityAddComponent2(cam_target.entity, "InventoryGuiComponent")
        end
        if inv_spec ~= nil then
            openInventory()
        end
end
local function at_cursor(ent)
            camera_player = player_fns.get_player_data_by_local_entity_id(ent)
            camera_player_id = camera_player.peer_id
            update_i()
            re_cam = true
end
local function none()
    if camera_player == -1 then
        return
    end
end
return {get=get_me, excluded=cant_spectate, attach=attach, disable=disable_throwing, cursor=at_cursor}
]=],
    ["system/spectator_helps/spectator_helps.lua"] = [=[
local shield_entities, rpc, module = {}, {}, {}
local function remove_shield(peer) shield_entities[peer]=nil end
function rpc.add_shield(target, rgbc)
    shield_entities[ctx.rpc_peer_id]=target
end
function rpc.del_shield() remove_shield(ctx.my_id) end
function module.on_world_update()
    rpc.add_shield(2)
end
return {rpc=rpc,shields=shield_entities,tick=module.on_world_update}]=],
    ["system/map/map.lua"] = [=[
return function(data)
    if true and not EntityHasTag(data.entity, "polymorphed_cessation") and not data.dc then return true end
end]=],
}

local writes, version, calls = 0, "1.6.8", 0
local names, original = {}, {}
for path, s in pairs(sources) do names[#names+1]=path; original[path]=s end
local ctx = {players={}, player_data_by_local_entity={}, my_id=1, host_id=2}
local env = setmetatable({ctx=ctx}, {__index=_G})
env.player_fns={get_player_data_by_local_entity_id=function(ent) return ctx.player_data_by_local_entity[ent] end}
env.EntityHasTag=function(ent,tag) return ent[tag] == true end
env.EntityGetIsAlive=function(ent) return ent and not ent.dead end
env.EntitySetTransform=function(ent,x,y) ent.x,ent.y=x,y end
env.EntityAddTag=function(ent,tag) ent[tag]=true end
env.EntityRemoveTag=function(ent,tag) ent[tag]=nil end
env.ComponentSetValue2=function(comp,field,n)
    assert(field=="money" and type(n)=="number","wallet requires a number");comp[field]=n
end
env.EntityGetAllChildren=function(ent) assert(ent,"nil inventory");return {} end
local function called() calls=calls+1 end
env.EntityAddComponent2,env.openInventory,env.showAvatar,env.moveAvatar,env.drawCape=called,called,called,called,called
env.net={net_handling={proxy={dc=called,leave=function(_,peer) ctx.players[peer]=nil end}}}
local hooks = setfenv(assert(loadfile(root.."ew_wait_peer_hooks.lua")),env)()
env.ModDoesFileExist=function() return true end
env.dofile_once=function(path)
    if path == base.."version.lua" then return version end
    assert(path==root.."ew_wait_peer_hooks.lua")
    return hooks
end
env.ModTextFileGetContent=function(path) return sources[path:sub(#base+1)] end
env.ModTextFileSetContent=function(path,s) sources[path:sub(#base+1)]=s; writes=writes+1 end
local installer = setfenv(assert(loadfile(root.."ew_wait_peer.lua")),env)()
version="1.7"; assert(not installer.install() and writes==0); version="1.6.8"
for _,path in ipairs(names) do
    sources[path]="upstream changed"; assert(not installer.install() and writes==0)
    sources[path]=original[path]
end
assert(installer.install() and writes==5 and installer.install() and writes==5)
local function system(path)
    return setfenv(assert(loadstring(sources["system/"..path])),env)()
end
local undc=system("player_sync.lua")
local ai=system("notplayer_ai/notplayer_ai.lua")
local cam=system("spectate/spectate.lua")
local shields=system("spectator_helps/spectator_helps.lua")
local map=system("map/map.lua")
local function player(peer, waiting)
    local ent={nh_ew_waiting=waiting,ew_notplayer=waiting}
    local p={peer_id=peer,entity=ent}
    ctx.players[peer],ctx.player_data_by_local_entity[ent]=p,p
    return p
end
local me, host, last = player(1,true), player(2,false), player(3,false)
ctx.my_player,ctx.rpc_player_data,ctx.rpc_peer_id=me,me,me.peer_id
-- Loaded waiting body already owns the saved wallet. Money acquired just
-- before death or during spectating must still produce EW's normal delta.
me.currently_polymorphed=true
local wallet={money=52};assert(env.sampleWallet(wallet)==0 and wallet.money==52)
me.entity.nh_ew_waiting=false;me.currently_polymorphed=false
wallet.money=66;assert(env.sampleWallet(wallet)==14 and wallet.money==66)
me.entity.nh_ew_waiting=true;me.currently_polymorphed=true
wallet.money=75;assert(env.sampleWallet(wallet)==9 and wallet.money==75)
assert(cam.get()==2 and not ai(true) and not map(me) and map(host))
assert(cam.excluded(me.entity) and not cam.excluded(last.entity))
host.dc=true; assert(cam.get()==3); host.dc=nil
ctx.spectating_over_peer_id=2;env.net.net_handling.proxy.leave(nil,2)
assert(not ctx.spectating_over_peer_id and cam.get()==3);ctx.players[2]=host
host.status={is_alive=false};assert(cam.get()==3);host.status.is_alive=true
host.entity.ew_notplayer=true;assert(cam.get()==3);host.entity.ew_notplayer=false
last.entity.nh_ew_waiting=true; host.dc=true; assert(cam.get()==-1);host.dc=nil
env.inv_spec=true;cam.attach(host);cam.disable(nil,me.entity); cam.cursor(nil);cam.cursor(me.entity)
assert(calls==0)
shields.shields[1]=2;shields.tick();assert(not shields.shields[1])
shields.rpc.add_shield(2);assert(not shields.shields[1])
env.net.net_handling.proxy.dc(nil,1);assert(me.dc and not me.entity.ew_client and calls==0)
undc(me.entity);assert(me.entity.ew_client and not me.entity.ew_peer)
env.render(me.entity);env.onInput(me,{host_frame_num=77},{x=90,y=2})
assert(me.pos_x==90 and me.entity.y==2 and not ctx.host_frame_num and calls==0)
host.entity.nh_ew_waiting=true
env.onInput(host,{host_frame_num=183},{x=1,y=2});assert(ctx.host_frame_num==183 and calls==0)
-- Genuine EW notplayers keep their avatar, AI, inventory view, and shield.
me.entity.nh_ew_waiting=false;host.entity.nh_ew_waiting=false;me.dc=nil
assert(cam.get()==1 and ai(true)=="autoplay" and map(me))
me.entity.nh_ew_wait_upgrade=true;assert(not ai(true));me.entity.nh_ew_wait_upgrade=nil
shields.tick();assert(shields.shields[1]==2)
cam.attach(host);env.net.net_handling.proxy.dc(nil,2);undc(me.entity);env.render(me.entity);env.onInput(me,{},{})
assert(calls==6)
me.currently_polymorphed=false
assert(env.sampleWallet(wallet)==0 and wallet.money==75)
me.currently_polymorphed=true;wallet.money=5
assert(env.sampleWallet(wallet)==0 and wallet.money==75) -- ordinary EW polymorph
-- A cold load of a marked 0.42.24 fighting substitute may reach frame
-- 9 mod 37 before the first migration tick. EW has no previous wallet yet.
system("player_sync.lua")
me.entity.nh_ew_wait_upgrade=true
wallet.money=183
assert(env.sampleWallet(wallet)==0 and wallet.money==183)
me.entity.nh_ew_wait_upgrade=nil;me.entity.nh_ew_waiting=true
wallet.money=186;assert(env.sampleWallet(wallet)==3 and wallet.money==186)
me.entity.nh_ew_waiting=false;me.currently_polymorphed=false
assert(env.sampleWallet(wallet)==0 and wallet.money==186)
local saved=sources["system/map/map.lua"]
sources["system/map/map.lua"]=saved:gsub("data%.dc","data.changed")
assert(not installer.install() and writes==5)

-- Optional integration against an unmodified official release checkout.
local official=os.getenv("NOITA_EW_168_DIR")
if official and official~="" then
    for _,path in ipairs(names) do
        local f=assert(io.open(official.."/files/"..path,"rb"));sources[path]=f:read("*a");f:close()
    end
    assert(installer.install() and writes==10)
    for _,path in ipairs(names) do assert(loadstring(sources[path],path)) end
    assert(installer.install() and writes==10)
end
print("EW waiting: spectator selection, disconnects, input, map, capes, shields and staged source compatibility passed.")
