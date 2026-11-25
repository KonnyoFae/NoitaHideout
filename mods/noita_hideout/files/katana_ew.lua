-- Each enemy is hit/frozen only by its simulation owner. The attacking peer
-- pays costs; reliable reward events are credited on the player owner.
local root="mods/noita_hideout/files/"
local api=dofile_once("mods/quant.ew/files/api/ew_api.lua")
local rpc=api.new_rpc_namespace("nh_katana")
local combat=dofile_once(root.."katana_combat.lua")
local fields=dofile_once(root.."katana_field.lua")
local rewards=dofile_once(root.."katana_rewards.lua")
local visual=dofile_once(root.."katana_visual.lua")
local fx=dofile_once(root.."katana_fx.lua")
local K=dofile_once(root.."katanas.lua")
local M={}
local maxFrame=2147483647 -- VariableStorageComponent.value_int stores absolute expiry.
local serial,seen,hits,poses,fieldStates=0,{},{},{},{}
local function finite(n,limit)
    return type(n)=="number" and n==n and math.abs(n)<=limit
end
local function scope()
    local world=nh_ew_session and nh_ew_session.world()
    local boot=world and nh_ew_session.challenge(ctx.my_id)
    if world and boot then serial=serial+1;return world,boot,serial end
end
local function accept(lane,world,boot,number)
    if not nh_ew_session or nh_ew_session.world()~=world or type(boot)~="string"
        or not finite(number,9007199254740991) or number<1 or number~=math.floor(number) then return end
    local peer=api.rpc_player_data()
    if not peer or peer.dc or peer.peer_id==ctx.my_id or nh_ew_session.challenge(peer.peer_id)~=boot then return end
    if lane~="credit" and (not peer.entity or not EntityGetIsAlive(peer.entity)) then return end
    local key=lane.."/"..peer.peer_id
    local prior=seen[key]
    if prior and prior.world==world and prior.boot==boot and number<=prior.number then return end
    seen[key]={world=world,boot=boot,number=number}
    return peer
end
local function heldKatana(player)
    local inv=EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    local weapon=inv and ComponentGetValue2(inv,"mActiveItem")
    if not weapon or weapon==0 or not EntityGetIsAlive(weapon) or EntityGetRootEntity(weapon)~=player then return end
    local kind=K.kind(weapon)
    if kind and K.types[kind] then return weapon,kind end
end
local function attackProfile(a)
    local def=K.types[a.kind]
    for _,prefix in ipairs({"quick","heavy","dash"}) do
        local damage,width,reach,visual=def[prefix.."Damage"],def[prefix.."Width"],def[prefix.."Reach"],def[prefix.."FxReach"]
        if damage and width and reach and visual and math.abs(a.damage-damage)<0.0001
            and math.abs(a.width-width)<0.0001 and math.abs(a.fxReach-visual)<0.0001 then
            local distance=def[prefix.."Lunge"] or def[prefix.."Distance"] or 0
            local frames=def[prefix.."LungeFrames"] or def[prefix.."Frames"] or 1
            return prefix,reach,2*distance/(frames+1)
        end
    end
end
util.add_cross_call("ew_hideout_katana_attack",function(event)
    local world,boot,sequence=scope()
    if world then rpc.attack(world,boot,sequence,event) end
end)
rpc.opts_reliable()
function rpc.attack(world,boot,sequence,a)
    local peer=accept("attack",world,boot,sequence)
    if not peer or type(a)~="table" or not K.types[a.kind] or type(a.token)~="string" or #a.token>100
        or not a.token:match("^nh_katana/%d+/%d+/%d+$") or not finite(a.damage,8) or a.damage<=0
        or not finite(a.width,24) or a.width<=0 or not finite(a.fxReach,150) or a.fxReach<=0 then return end
    for _,key in ipairs({"x1","y1","x2","y2","fxX","fxY"}) do if not finite(a[key],10000000) then return end end
    local dx,dy=a.x2-a.fxX,a.y2-a.fxY
    local length=math.sqrt(dx*dx+dy*dy)
    local px,py=EntityGetTransform(peer.entity)
    if length<0.0001 or length>150 or (a.x1-px)^2+(a.y1-py)^2>256^2 then return end
    local profile,reach,maxStep=attackProfile(a)
    if not profile then return end
    local nx,ny=dx/length,dy/length
    local mx,my=a.fxX-a.x1,a.fxY-a.y1
    local moved=mx*nx+my*ny
    local offAxis=math.abs(mx*ny-my*nx)
    -- Terrain may project a shallow downward step onto the ground. The blade
    -- still points from the new hand to its tip, independently of that motion.
    -- Receipt-time terrain can differ, so validate its bounded projection cone.
    -- Allow one pixel for native float positions at distant world coordinates.
    if math.abs(length-reach)>1 or mx*mx+my*my>(maxStep+1)^2 then return end
    local straight=moved>= -1 and moved<=maxStep+1 and offAxis<=1
    local projected=false
    if ny>0 and ny<=0.350001 then
        local along=mx/nx -- This angle range guarantees |nx| >= 0.93.
        projected=along>= -1 and along<=maxStep+1 and my>= -1 and my<=ny*math.max(0,along)+1
    end
    if not straight and not projected then return end
    local key=peer.peer_id.."/"..boot.."/"..a.token
    local entry=hits[key]
    if entry and (entry.kind~=a.kind or entry.profile~=profile or entry.plunder~=(a.plunder==true)) then return end
    if not entry then
        entry={targets={},expires=GameGetFrameNum()+120,kind=a.kind,profile=profile,plunder=a.plunder==true}
        hits[key]=entry
    end
    combat.apply(peer.entity,a,entry.targets)
    local angle=math.atan2(dy,dx)
    poses[peer.peer_id]={angle=angle,untilFrame=GameGetFrameNum()+6}
    if entry.fx then fx.follow(entry.fx,a.fxX,a.fxY,angle,a.fxReach/64,dx<0 and -1 or 1)
    elseif a.showFx==true then entry.fx=fx.spawn(a.fxX,a.fxY,angle,a.kind,a.fxReach/64,dx<0 and -1 or 1) end
end
util.add_cross_call("ew_hideout_katana_field",function(token,x,y,radius,remaining)
    local world,boot,sequence=scope()
    if world then rpc.field(world,boot,sequence,token,x,y,radius,remaining) end
end)
rpc.opts_reliable()
function rpc.field(world,boot,sequence,token,x,y,radius,remaining)
    local peer=accept("field",world,boot,sequence)
    if not peer or type(token)~="string" or #token>100 or not token:match("^nh_katana/%d+/%d+/%d+$")
        or not finite(remaining,maxFrame) or remaining<0 or remaining~=math.floor(remaining) then return end
    local key=peer.peer_id.."/"..boot.."/"..token
    local now=GameGetFrameNum()
    local prior=fieldStates[key]
    if remaining==0 then
        fields.cancelRemote(key)
        -- A late heartbeat must not resurrect a token that has been cancelled.
        fieldStates[key]={closed=true,expires=prior and prior.expires or now+1830}
        return
    end
    if prior and prior.closed then return end
    local weapon,kind=heldKatana(peer.entity)
    local def=kind and K.types[kind]
    -- Ordinary duration is derived from paid shield points; maximum HP can
    -- grow without a gameplay cap. Only native absolute-frame storage bounds it.
    local limit=def and math.min(def.plunderDurationFrames or maxFrame-now,maxFrame-now)
    if not limit or remaining>limit then return end
    local reportedRemaining=remaining
    if not finite(x,10000000) or not finite(y,10000000) or radius~=K.zandatsu.radius then return end
    if prior then
        if prior.player~=peer.entity or prior.weapon~=weapon or prior.kind~=kind or prior.x~=x or prior.y~=y
            or prior.radius~=radius or remaining>prior.remaining then return end
        -- The first message bounds total lifetime. Heartbeats only maintain
        -- the short transport lease; they cannot keep extending Blade Mode.
        remaining=math.min(remaining,prior.deadline-now)
        if remaining<=0 then
            fields.cancelRemote(key);prior.closed=true;return
        end
    else
        local px,py=EntityGetTransform(peer.entity)
        if (x-px)^2+(y-py)^2>(radius+128)^2 then return end
        prior={player=peer.entity,weapon=weapon,kind=kind,x=x,y=y,radius=radius,
            deadline=now+remaining,expires=now+remaining+30}
    end
    if fields.applyRemote(peer.entity,key,x,y,radius,remaining) then
        prior.remaining=reportedRemaining
        fieldStates[key]=prior
    end
end
util.add_cross_call("ew_hideout_katana_credit",function(replica)
    local target=ctx.player_data_by_local_entity[replica]
    if not target or target.entity~=replica or target.dc or target.peer_id==ctx.my_id then return end
    local world,boot,sequence=scope()
    local targetBoot=world and nh_ew_session.challenge(target.peer_id)
    if targetBoot then rpc.credit(world,boot,sequence,target.peer_id,targetBoot) end
end)
rpc.opts_reliable()
function rpc.credit(world,boot,sequence,target,targetBoot)
    if target~=ctx.my_id or not nh_ew_session or nh_ew_session.challenge(target)~=targetBoot then return end
    if accept("credit",world,boot,sequence) and ctx.my_player then rewards.credit(ctx.my_player.entity) end
end
function M.on_world_initialized()
    for key in pairs(fieldStates) do fields.cancelRemote(key) end
    seen,hits,poses,fieldStates={},{},{},{}
    visual.reset()
end
function M.on_world_update()
    local frame=GameGetFrameNum()
    for key,entry in pairs(hits) do if frame>entry.expires then hits[key]=nil end end
    for key,entry in pairs(fieldStates) do
        if frame>entry.expires then fieldStates[key]=nil
        elseif not entry.closed and (frame>=entry.deadline or not EntityGetIsAlive(entry.player)
            or heldKatana(entry.player)~=entry.weapon) then
            fields.cancelRemote(key);entry.closed=true
        end
    end
    for peerId,peer in pairs(ctx.players or {}) do
        if peerId~=ctx.my_id and peer.entity then
            local player=peer.entity
            local inv=EntityGetIsAlive(player) and EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
            local weapon=inv and ComponentGetValue2(inv,"mActiveItem")
            local kind=weapon and weapon~=0 and K.kind(weapon)
            if not peer.dc and kind then
                local pose=poses[peerId]
                local c=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
                local dx,dy=1,0
                if c then dx,dy=ComponentGetValue2(c,"mAimingVectorNormalized") end
                visual.pose(player,weapon,kind,frame,{angle=pose and frame<=pose.untilFrame and pose.angle or math.atan2(dy,dx)})
            else visual.reset(player) end
        end
    end
end
return M
