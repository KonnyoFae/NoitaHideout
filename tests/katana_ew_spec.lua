local root="mods/noita_hideout/files/"
local originalDofileOnce=dofile_once
local cross,rpc,hooks={},{},{}
local frame,source=1,{peer_id="peer",entity=2}
local calls={attack=0,credit=0,field=0,cancel=0,fx=0,follow=0}
local activeItem,px,py=20,0,0
local weapons={[20]="hf_blade",[21]="hf_murasama",[22]="dragon_king"}
local alive={[1]=true,[2]=true,[20]=true,[21]=true,[22]=true}
local lastField,lastFx,lastAttack
local K=dofile(root.."katanas.lua")
K.kind=function(entity) return weapons[entity] end
ctx={my_id="me",my_player={entity=1},players={},player_data_by_local_entity={[2]={peer_id="peer",entity=2}}}
nh_ew_session={world=function() return "world" end,challenge=function(peer) return peer.."boot" end}
util={add_cross_call=function(name,fn) cross[name]=fn end}
function rpc.opts_reliable() end
local modules={
    ["mods/quant.ew/files/api/ew_api.lua"]={new_rpc_namespace=function() return rpc end,rpc_player_data=function() return source end},
    [root.."katanas.lua"]=K,
    [root.."katana_combat.lua"]={apply=function(player,a,hit)
        assert(player==2)
        lastAttack=a
        if not hit[99] then calls.attack=calls.attack+1;hit[99]=true end
    end},
    [root.."katana_field.lua"]={applyRemote=function(player,token,x,y,radius,remaining)
        calls.field=calls.field+1;assert(player==2 and token:match("^peer/peerboot/nh_katana/") and radius==160)
        lastField={token=token,x=x,y=y,remaining=remaining}
        return 100+calls.field
    end,cancelRemote=function(token) calls.cancel=calls.cancel+1 end},
    [root.."katana_rewards.lua"]={credit=function(player) assert(player==1);calls.credit=calls.credit+1 end},
    [root.."katana_visual.lua"]={reset=function() end,pose=function() end},
    [root.."katana_fx.lua"]={
        spawn=function(x,y,angle,kind,scale,flip)
            calls.fx=calls.fx+1;lastFx={x=x,y=y,angle=angle,kind=kind,scale=scale,flip=flip,id=700+calls.fx}
            return lastFx.id
        end,
        follow=function(id,x,y,angle,scale,flip)
            calls.follow=calls.follow+1;lastFx={id=id,x=x,y=y,angle=angle,scale=scale,flip=flip}
        end,
    },
}
function dofile_once(path) return assert(modules[path],path) end
function EntityGetIsAlive(entity) return alive[entity]==true end
function EntityGetTransform() return px,py end
function EntityGetRootEntity(entity) return weapons[entity] and 2 or entity end
function EntityGetFirstComponentIncludingDisabled(entity,kind,...)
    assert(select("#",...)==0 or select(1,...)~=nil,"Noita rejects explicitly nil component tags")
    if select(1,...)=="" then return nil end
    if entity==2 and kind=="Inventory2Component" then return 10 end
end
function ComponentGetValue2(component,key) assert(component==10 and key=="mActiveItem");return activeItem end
function GameGetFrameNum() return frame end
local module=dofile(root.."katana_ew.lua")
local a={kind="hf_blade",token="nh_katana/2/1/1",x1=0,y1=0,x2=36,y2=0,
    fxX=0,fxY=0,fxReach=30,width=12,damage=2,showFx=true,plunder=true}
rpc.attack("world","peerboot",1,a)
assert(calls.attack==1 and calls.fx==1)
assert(lastFx.x==0 and lastFx.scale==30/64)
rpc.attack("world","peerboot",1,a)
assert(calls.attack==1 and calls.fx==1)
a.showFx=false
rpc.attack("world","peerboot",2,a)
assert(calls.attack==1)
assert(calls.fx==1 and calls.follow==1,"later attack frames follow their one cached image")
a.token="nh_katana/2/1/2"
rpc.attack("world","peerboot",3,a)
assert(calls.attack==2)
rpc.attack("world","stale",4,a)
rpc.attack("otherworld","peerboot",5,a)
a.damage=0/0;rpc.attack("world","peerboot",6,a);a.damage=2
a.x2=1000;rpc.attack("world","peerboot",7,a);a.x2=36
assert(calls.attack==2)
rpc.field("world","peerboot",8,"nh_katana/2/1/1",0,0,160,360)
rpc.field("world","peerboot",8,"nh_katana/2/1/1",0,0,160,360)
assert(calls.field==1)
rpc.field("world","peerboot",9,"nh_katana/2/1/1",0,0,160,0)
assert(calls.cancel==1)
rpc.credit("world","peerboot",10,"me","meboot")
rpc.credit("world","peerboot",10,"me","meboot")
rpc.credit("world","peerboot",11,"me","oldboot")
assert(calls.credit==1)
-- The peer simulating the killed enemy can be spectating without a live body.
source={peer_id="peer"}
rpc.credit("world","peerboot",12,"me","meboot")
assert(calls.credit==2)
source={peer_id="me",entity=1}
rpc.credit("world","meboot",12,"me","meboot")
assert(calls.credit==2)
source={peer_id="peer",entity=2}
frame=200;module.on_world_update()
a.token="nh_katana/2/200/3"
rpc.attack("world","peerboot",13,a)
assert(calls.attack==3)

-- All three weapon kinds dispatch through the same damage/segment limits.
a.kind="dragon_king";a.token="nh_katana/2/200/4";a.x2=100;a.fxX=20;a.fxReach=68;a.width=20;a.damage=8
rpc.attack("world","peerboot",14,a)
assert(calls.attack==4)
a.token="nh_katana/2/200/5";a.damage=8.01;rpc.attack("world","peerboot",15,a)
a.damage=8;a.kind="unknown";rpc.attack("world","peerboot",16,a)
assert(calls.attack==4,"adding Dragon King must not widen attack validation")

-- Every frame carries one swept capsule and an independent image origin and
-- length. All six attacks render exactly one image, then follow the new hand.
local attackSequence=40
local function sendAttack(event)
    attackSequence=attackSequence+1
    rpc.attack("world","peerboot",attackSequence,event)
end
local function packet(kind,prefix,x,y,step,dx,dy,index)
    local def=K.types[kind]
    return {kind=kind,token="nh_katana/2/200/"..index,x1=x,y1=y,
        x2=x+dx*(step+def[prefix.."Reach"]),y2=y+dy*(step+def[prefix.."Reach"]),
        fxX=x+dx*step,fxY=y+dy*step,fxReach=def[prefix.."FxReach"],
        width=def[prefix.."Width"],damage=def[prefix.."Damage"],showFx=true,plunder=false}
end
for index,variant in ipairs({{"hf_blade","quick"},{"hf_blade","heavy"},{"hf_murasama","quick"},
    {"hf_murasama","dash"},{"dragon_king","quick"},{"dragon_king","dash"}}) do
    local kind,prefix=unpack(variant)
    local def=K.types[kind]
    local distance=def[prefix.."Lunge"] or def[prefix.."Distance"]
    local steps=def[prefix.."LungeFrames"] or def[prefix.."Frames"]
    local duration=def[prefix.."Frames"]
    local x,y,dx,dy=0,-4,-0.6,0.8
    local attacksBefore,fxBefore,followsBefore=calls.attack,calls.fx,calls.follow
    local fxId
    for tick=1,duration do
        local moved=tick<=steps and distance*2*tick/(steps*(steps+1)) or 0
        local event=packet(kind,prefix,x,y,moved,dx,dy,100+index)
        event.showFx=tick==1
        sendAttack(event)
        assert(lastAttack==event,"valid accelerated capsule was rejected")
        x,y=event.fxX,event.fxY
        assert(math.abs(lastFx.x-x)<0.000001 and math.abs(lastFx.y-y)<0.000001)
        assert(lastFx.scale==def[prefix.."FxReach"]/64 and lastFx.flip==-1)
        assert(math.abs(lastFx.angle-math.atan2(dy,dx))<0.000001)
        fxId=fxId or lastFx.id;assert(lastFx.id==fxId)
    end
    assert(calls.attack==attacksBefore+1,"multi-frame sweep damaged the same target repeatedly")
    assert(calls.fx==fxBefore+1 and calls.follow==followsBefore+duration-1,"one attack stacked multiple slash images")
end

-- A shallow downward attack may move partly along its aim and then slide
-- horizontally along the floor. Its image and pose retain the blade's angle,
-- rather than tilting to the old-hand-to-tip sweep's diagonal.
local projectionToken=400
local function projectedPacket(kind,prefix,ny,sign,fraction,distance)
    projectionToken=projectionToken+1
    local def=K.types[kind]
    local nx=sign*math.sqrt(1-ny*ny)
    local e=packet(kind,prefix,0,-4,distance,nx,ny,projectionToken)
    e.fxY=-4+ny*distance*fraction
    e.y2=e.fxY+ny*def[prefix.."Reach"]
    return e,nx,ny
end
for _,variant in ipairs({{"hf_blade","quick"},{"hf_blade","heavy"},{"hf_murasama","quick"},
    {"hf_murasama","dash"},{"dragon_king","quick"},{"dragon_king","dash"}}) do
    local kind,prefix=unpack(variant)
    local def=K.types[kind]
    local step=2*(def[prefix.."Lunge"] or def[prefix.."Distance"])/(1+(def[prefix.."LungeFrames"] or def[prefix.."Frames"]))
    for _,sign in ipairs({-1,1}) do
        for _,fraction in ipairs({0,0.4,1}) do
            local e,nx,ny=projectedPacket(kind,prefix,0.35,sign,fraction,step)
            local before=calls.attack
            sendAttack(e)
            assert(calls.attack==before+1 and lastAttack==e,"valid grounded projected step rejected: "..kind..prefix)
            assert(math.abs(lastFx.angle-math.atan2(ny,nx))<0.000001,"projected movement changed the blade/pose angle")
            assert(lastFx.x==e.fxX and lastFx.y==e.fxY and lastFx.flip==sign)
            local image=lastFx.id
            e.showFx=false;sendAttack(e)
            assert(calls.attack==before+1 and lastFx.id==image,"projected step lost per-token damage/FX deduplication")
        end
    end
end
local projectionInvalid={
    function(e) e.fxY=e.y1-3;e.y2=e.fxY+0.3*80 end,
    function(e) e.fxY=e.y1+18;e.y2=e.fxY+0.3*80 end,
    function(e) e.fxX=-5;e.x2=e.fxX+math.sqrt(1-0.3^2)*80 end,
    function(e) e.fxX=e.fxX+8;e.x2=e.x2+8 end,
    function(e) e.y2=e.y2+8 end,
}
for index,mutate in ipairs(projectionInvalid) do
    local e=projectedPacket("dragon_king","dash",0.3,1,0.4,320/9)
    mutate(e)
    local before,beforeFx,beforeFollow=calls.attack,calls.fx,calls.follow
    sendAttack(e)
    assert(calls.attack==before and calls.fx==beforeFx and calls.follow==beforeFollow,
        "projected step accepted reverse/excess movement or wrong blade reach: "..index)
end
for _,ny in ipairs({-0.3,0.36,0.8}) do
    local e=projectedPacket("dragon_king","dash",ny,1,0,320/9)
    local before=calls.attack
    sendAttack(e)
    assert(calls.attack==before,"horizontal projection accepted for upward or steep downward aim")
end

local invalid={
    function(p) p.fxX=nil end,
    function(p) p.fxY=0/0 end,
    function(p) p.fxReach=math.huge end,
    function(p) p.fxReach=p.fxReach+5 end,
    function(p) p.fxY=p.fxY+4 end,
    function(p) p.x2=p.x2+8 end,
    function(p) p.fxX=p.fxX+10;p.x2=p.x2+10 end,
    function(p) p.fxX=p.fxX-10;p.x2=p.x2-10 end,
    function(p) p.damage=7 end,
    function(p) p.width=24 end,
}
for index,mutate in ipairs(invalid) do
    local event=packet("dragon_king","dash",0,-4,20,1,0,150+index)
    if index==8 then event=packet("hf_blade","quick",0,-4,0,1,0,150+index) end
    if index==7 then event=packet("hf_blade","quick",0,-4,5,1,0,150+index) end
    mutate(event)
    local beforeAttack,beforeFx,beforeFollow=calls.attack,calls.fx,calls.follow
    sendAttack(event)
    assert(calls.attack==beforeAttack and calls.fx==beforeFx and calls.follow==beforeFollow,"malformed sweep/FX packet accepted: "..index)
end
local altered=packet("dragon_king","quick",0,-4,7,1,0,106)
local unchanged=calls.attack
sendAttack(altered)
assert(calls.attack==unchanged,"one attack token changed its damage/geometry profile")
local missed=packet("hf_murasama","dash",0,-4,20,1,0,180)
missed.showFx=false
local beforeFx,beforeFollow=calls.fx,calls.follow
sendAttack(missed)
assert(calls.fx==beforeFx and calls.follow==beforeFollow,"missing initial image must not spawn a replacement each later frame")

local sequence=20
local function token(n) return "nh_katana/2/200/"..n end
local function field(n,remaining,x,y,radius)
    sequence=sequence+1
    rpc.field("world","peerboot",sequence,token(n),x or 0,y or 0,radius or 160,remaining)
end
local before=calls.field
for _,weapon in ipairs({20,21}) do
    activeItem=weapon
    local previous=calls.field
    field(weapon,7200)
    assert(calls.field==previous+1 and lastField.remaining==7200,"paid shield points may exceed the old six/sixty-second caps")
    field(weapon,0)
    field(weapon+100,2147483647-frame+1)
    assert(calls.field==previous+1,"absolute expiry must remain representable by the engine")
end
before=calls.field
activeItem=0;field(12,120)
activeItem=22;alive[22]=false;field(12,1800);alive[22]=true
assert(calls.field==before,"unheld or destroyed weapons cannot cast remote fields")
field(12,1801);field(12,0/0);field(12,119.5);field(12,1800,0,0,161)
assert(calls.field==before)
field(12,1800)
assert(calls.field==before+1 and lastField.remaining==1800,"Dragon King supports a full thirty-second field")
frame=frame+15;field(12,1785)
assert(lastField.remaining==1785)
local accepted=calls.field
field(12,1800);field(12,1770,1,0)
assert(calls.field==accepted,"heartbeats cannot extend the original duration or move the fixed origin")

-- Dragon King can move freely; origin proximity is only checked on creation.
px=1000;frame=frame+15;field(12,1770)
assert(calls.field==accepted+1)
field(13,120)
assert(calls.field==accepted+1,"a fresh field still has to start beside its caster")
px=0
activeItem=20;field(12,300)
assert(calls.field==accepted+1,"switching to another katana cannot continue the original field")
local cancelled=calls.cancel
module.on_world_update()
assert(calls.cancel==cancelled+1,"weapon loss closes the token without waiting for a heartbeat")
activeItem=22;field(12,1700)
assert(calls.field==accepted+1,"switching back cannot revive the cancelled token")

-- The free two-second field shares the protocol without gaining a long lease.
field(14,120);local shortStart=frame
frame=frame+20;field(14,105)
assert(lastField.remaining==100,"network delay must not push out the first receipt's deadline")
frame=frame+5;field(14,102)
assert(lastField.remaining==95,"raw remaining may decrease despite transit-delay changes")
accepted=calls.field
frame=shortStart+120;field(14,1)
assert(calls.field==accepted,"a newer sequence cannot resurrect an expired short field")
field(15,1800);field(15,0);accepted=calls.field
field(15,1785)
assert(calls.field==accepted,"explicit cancel wins over later token heartbeats")
rpc.field("world","peerboot",sequence-2,token(15),0,0,160,1800)
rpc.field("world","oldboot",sequence+1,token(16),0,0,160,1800)
assert(calls.field==accepted,"old sequence/session packets remain rejected")

-- A thirty-second cast also expires without a cancellation packet.
field(17,1800);local longStart=frame
frame=longStart+1799;field(17,2)
assert(lastField.remaining==1)
accepted=calls.field
frame=longStart+1800;field(17,1)
assert(calls.field==accepted)

-- Dynamic shield-derived fields can be shorter than a heartbeat or a second.
-- They retain the original deadline rather than acquiring a minimum 30-frame life.
activeItem=20
for n,duration in ipairs({1,30,300,7200}) do
    field(200+n,duration)
    assert(lastField.remaining==duration)
    local start=frame
    if duration>1 then
        frame=start+duration-1;field(200+n,1)
        assert(lastField.remaining==1)
    end
    local count=calls.field
    frame=start+duration;field(200+n,1)
    assert(calls.field==count,"new packet sequence extended a paid field past its original snapshot")
end
frame=2147483646
field(300,1)
assert(lastField.remaining==1)
accepted=calls.field
field(301,2)
assert(calls.field==accepted)
frame=2147483647;field(302,1)
assert(calls.field==accepted,"no positive duration fits beyond native absolute-frame range")
module.on_world_initialized()
dofile_once=originalDofileOnce
print("Katana EW: three weapon kinds, held-weapon field bounds, transport leases, fixed origins, credit and replay rejection passed.")
