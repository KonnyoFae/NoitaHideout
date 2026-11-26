local root="mods/noita_hideout/files/"
local objects={}
local wall,unloaded,crate,beam,shelf,floorY
local hitCalls,marked,parryCalls={},{},{}
local taggedQueries={}
local bodyQueries={}
function ModIsEnabled() return false end
function EntityGetIsAlive(id) return objects[id]~=nil end
function EntityGetRootEntity(id) return objects[id].parent or id end
function EntityHasTag(id,tag) return objects[id] and objects[id].tags[tag] or false end
function EntityGetHerdRelationSafe(_,id) return objects[id].relation or 0 end
function GameGetGameEffectCount(id,effect) return objects[id].effects[effect] or 0 end
function EntityGetFirstComponentIncludingDisabled(id,kind,...)
    local tag=select(1,...)
    assert(select("#",...)==0 or tag~=nil,"Noita rejects an explicitly nil component tag")
    if tag=="" then return nil end
    if kind=="DamageModelComponent" then return objects[id].dm end
    if kind=="ProjectileComponent" then return objects[id].shot end
    if kind=="VelocityComponent" then return objects[id].velocity end
    if kind=="ItemComponent" then return objects[id].item end
    if kind=="GenomeDataComponent" then return objects[id].genome end
    if tag=="nh_ew_deposit_lock" then return objects[id].lock end
end
function EntityGetFirstComponent(id,kind,...)
    local c=EntityGetFirstComponentIncludingDisabled(id,kind,...)
    if c and c.enabled~=false then return c end
end
function EntityGetComponentIncludingDisabled(id,kind,...)
    local tag=select(1,...)
    assert(select("#",...)==0 or tag~=nil,"Noita rejects an explicitly nil component tag")
    if kind=="HitboxComponent" and tag==nil then return objects[id].boxes or {} end
    return {}
end
function ComponentGetIsEnabled(c) return c.enabled~=false end
function ComponentGetValue2(c,k)
    if type(c[k])=="table" then return unpack(c[k]) end
    return c[k]
end
function EntityGetFirstHitboxCenter(id) return objects[id].x,objects[id].y end
function EntityGetTransform(id)
    local o=objects[id];return o.x,o.y,o.rotation or 0,o.sx or 1,o.sy or 1
end
function EntityGetInRadius(x,y,radius)
    local found={}
    for id,o in pairs(objects) do if (o.x-x)^2+(o.y-y)^2<=radius*radius then found[#found+1]=id end end
    return found
end
function EntityGetInRadiusWithTag(x,y,radius,tag)
    assert(type(tag)=="string" and radius<1200,"parry scans must stay bounded and use native collision tags")
    local queries=tag=="projectile" and taggedQueries or bodyQueries
    queries[#queries+1]={radius=radius,tag=tag}
    local found={}
    for _,id in ipairs(EntityGetInRadius(x,y,radius)) do if EntityHasTag(id,tag) then found[#found+1]=id end end
    return found
end
function RaytracePlatforms(x1,y1,x2,y2)
    if floorY and math.max(y1,y2)>=floorY then return true,x2,floorY end
    if wall and math.min(x1,x2)<=wall and math.max(x1,x2)>=wall then return true,wall,y2 end
    -- One terrain pixel row between the older hull's even-numbered probes.
    if shelf and y1==shelf.y and y2==shelf.y
        and math.max(x1,x2)>=shelf.left and math.min(x1,x2)<=shelf.right then return true,shelf.left,shelf.y end
    return false
end
function DoesWorldExistAt(x1) return not unloaded or x1<unloaded end
function PhysicsBodyIDQueryBodies(x1,y1,x2,y2,includeStatic)
    assert(includeStatic==true,"Dash collision query omitted static physics bodies")
    -- A long beam intersects the player hull even when its centre lies far
    -- beyond the requested movement. Body intersection is the authority.
    if beam and x2>=beam.left and x1<=beam.right and y2>=beam.top and y1<=beam.bottom then return {101} end
    if crate and crate.x>=x1 and crate.x<=x2 and crate.y>=y1 and crate.y<=y2 then return {100} end
    return {}
end
function PhysicsBodyIDGetWorldCenter(id)
    if id==101 then return (beam.left+beam.right)/2,(beam.top+beam.bottom)/2 end
    return crate.x,crate.y
end
function PhysicsPosToGamePos(x,y) return x,y end
function EntityInflictDamage(id,damage,kind,message,_,ix,iy,owner,x,y)
    assert(kind=="DAMAGE_MELEE" and owner==1 and damage>0)
    hitCalls[#hitCalls+1]={id=id,damage=damage,message=message,x=x,y=y}
end
function dofile_once(path)
    if path==root.."katana_rewards.lua" then return {mark=function(id,owner,message) marked[#marked+1]={id=id,owner=owner,message=message} end} end
    return dofile(path)
end
-- Record each contact without moving the bullet so repeated callbacks are visible.
local originalDofile=dofile
function dofile(path)
    if path==root.."katana_parry.lua" then return {reflect=function(player,id,shot,velocity,nx,ny,x,y)
        assert(player==1 and objects[id].shot==shot and objects[id].velocity==velocity)
        if objects[id].rejectParry then return false end
        parryCalls[#parryCalls+1]={id=id,nx=nx,ny=ny,x=x,y=y}
        return true
    end} end
    return originalDofile(path)
end
local combat=dofile(root.."katana_combat.lua")
dofile=originalDofile
local function mob(id,x,y,tags)
    objects[id]={x=x,y=y,tags=tags or {enemy=true},effects={},dm={hp=5,max_hp=5}}
end
mob(1,0,0,{player_unit=true})
mob(2,4,0)
mob(3,18,0)
mob(4,31,0)
mob(5,10,8)
mob(6,12,0,{enemy=true,noita_hideout_companion=true})
mob(7,12,0);objects[7].effects.CHARM=1
mob(8,12,0);objects[8].relation=40
mob(9,12,0);objects[9].parent=1
mob(10,12,0);objects[10].lock={}
mob(11,12,0);objects[11].dm.hp=0
mob(12,12,0,{enemy=true,nh_reinforcement=true})
mob(13,12,0,{enemy=true,nh_deployed_turret=true})
local event={x1=0,y1=0,x2=24,y2=0,width=10,damage=3,token="attack/1",plunder=true}
local count,hits=combat.apply(1,event)
assert(count==2 and hits[2] and hits[3] and #hitCalls==2 and #marked==2)
assert(combat.apply(1,event,hits)==0 and #hitCalls==2)
-- A second frame travelled past the first endpoint, retaining one-hit scope.
event.x1,event.x2=24,40
assert(combat.apply(1,event,hits)==1 and hits[4] and #marked==3)
event={x1=0,y1=0,x2=24,y2=0,width=10,damage=1,token="ordinary",plunder=false}
assert(combat.apply(1,event)==2 and #marked==3)
wall=10
assert(combat.apply(1,event)==1)
wall=nil
local distance,x,y=combat.distanceToSegment(5,3,0,0,10,0)
assert(distance==3 and x==5 and y==0)
distance,x,y=combat.distanceToSegment(5,0,0,0,0,0)
assert(distance==5 and x==0 and y==0)
local tx,ty,moved=combat.safeStep(0,0,1,0,120)
assert(tx==120 and ty==0 and moved==120)
floorY=2.001
for _,degrees in ipairs({1,3,15}) do
    local dx,dy=math.cos(math.rad(degrees)),math.sin(math.rad(degrees))
    tx,ty,moved=combat.safeStep(0,0,dx,dy,10)
    assert(math.abs(tx-dx*10)<0.00001 and ty==0 and moved==10)
end
tx,ty,moved=combat.safeStep(0,0,math.cos(math.rad(50)),math.sin(math.rad(50)),10)
assert(tx==0 and ty==0 and moved==0,"a steep downward attack must stop at the floor")
wall=8
tx,ty,moved=combat.safeStep(0,0,math.cos(math.rad(3)),math.sin(math.rad(3)),10)
assert(tx>0 and tx+3<8 and ty==0 and moved<10,"floor projection cannot cross a wall")
floorY=nil
wall=20
tx,ty,moved=combat.safeStep(0,0,1,0,120)
assert(tx<=16 and moved==tx and tx+3<wall)
wall=3
assert(select(3,combat.safeStep(0,0,1,0,120))==0)
wall=nil;unloaded=20
assert(select(3,combat.safeStep(0,0,1,0,120))<30)
unloaded=nil;crate={x=12,y=-2}
assert(select(3,combat.safeStep(0,0,1,0,120))<=8)
crate=nil;beam={left=12,right=600,top=-4,bottom=0}
assert(select(3,combat.safeStep(0,0,1,0,120))<=8,"Dash passed through a long beam with a distant centre")
beam=nil
shelf={left=12,right=16,y=-3}
assert(select(3,combat.safeStep(0,0,1,0,120))<=8,"Dash crossed a one-pixel terrain ledge between hull probe rows")
shelf=nil

local function box(minx,maxx,miny,maxy,enabled,offset)
    return {aabb_min_x=minx,aabb_max_x=maxx,aabb_min_y=miny,aabb_max_y=maxy,enabled=enabled,offset=offset or {0,0}}
end
local function scene(x,y,boxes)
    objects={};hitCalls={};marked={}
    mob(1,0,0,{player_unit=true});mob(2,x,y);objects[2].boxes=boxes
end
local flat={x1=0,y1=-4,x2=30,y2=-4,width=12,damage=2,token="shape",plunder=true}
scene(20,0,{box(-3,3,-6,3)})
assert(combat.apply(1,flat)==1,"ordinary shotgunner body should still be hit")
assert(hitCalls[1].x==17 and hitCalls[1].y==-4,"damage uses the near contact, not the hitbox centroid")
scene(25,0,{box(-16,16,-50,12)})
count,hits=combat.apply(1,flat)
assert(count==1 and hitCalls[1].x==9 and hitCalls[1].y==-4,"the alchemist's abdomen intersects even though its centre is above the blade")
assert(combat.apply(1,flat,hits)==0 and #marked==1,"multiple contact frames must not reward or damage twice")
scene(20,13,{box(-3,3,-2,2)})
assert(combat.apply(1,flat)==0,"candidate padding must not widen the blade")
scene(25,0,{box(-16,16,-50,12)})
wall=8
assert(combat.apply(1,flat)==0,"large hitboxes must not bypass a wall before their near face")
wall=nil
scene(20,0,{box(-3,3,16,24),box(-3,3,-6,3)})
assert(combat.apply(1,flat)==1,"a secondary enabled hitbox must be reachable")
scene(20,0,{box(-3,3,-6,3,false),box(-3,3,16,24)})
assert(combat.apply(1,flat)==0,"disabled first hitbox cannot be replaced by a centroid fallback")
scene(20,0,{box(-3,3,-6,3),box(-5,5,-8,5)})
assert(combat.apply(1,flat)==1 and #hitCalls==1,"overlapping hitboxes still receive one hit per entity")
scene(20,0,{box(-2,2,-1,1,true,{0,-4})})
assert(combat.apply(1,flat)==1,"hitbox local offsets must affect the contact")

-- Rotation turns this tall remote rectangle into a horizontal body reaching
-- the blade; its unrotated origin lies well outside the former query padding.
scene(80,-4,{box(-1,1,0,20)})
objects[2].rotation=math.pi/2;objects[2].sx=1;objects[2].sy=3
assert(combat.apply(1,flat)==1,"rotated nonuniformly scaled body edge must be hittable")
objects[2].rotation=-math.pi/2
assert(combat.apply(1,flat)==0,"rotation in the other direction must not hit through an enclosing world AABB")
scene(65,-4,{box(0,20,-1,1)})
objects[2].sx=-2;objects[2].sy=3
assert(combat.apply(1,flat)==1,"negative scale mirrors the collision shape")
objects[2].sx=2
assert(combat.apply(1,flat)==0,"the nonmirrored body remains outside reach")
scene(20,-4,{box(-1,1,-1,1)})
objects[2].rotation=math.pi/4;objects[2].sx=2;objects[2].sy=0.5
assert(combat.apply(1,flat)==1,"diagonal nonuniform transform remains hittable")

-- A nearby corner inside the world AABB is not necessarily inside an OBB.
scene(24,9,{box(-12,12,-1,1)})
objects[2].rotation=math.pi/4
local point={x1=31,y1=1,x2=31,y2=1,width=2,damage=2,token="point"}
assert(combat.apply(1,point)==0,"a rotated shape must not expand to its enclosing AABB")
point.x1,point.x2,point.y1,point.y2=24,24,9,9
assert(combat.apply(1,point)==1,"a zero-length capsule inside the hitbox must hit")

scene(25,0,{box(-16,16,-50,12)})
assert(EntityGetFirstComponentIncludingDisabled(2,"DamageModelComponent","")==nil)
assert(not pcall(EntityGetFirstComponentIncludingDisabled,2,"DamageModelComponent",nil))
assert(EntityGetFirstComponentIncludingDisabled(2,"DamageModelComponent")==objects[2].dm)

-- A moved hand and its blade tip form one continuous capsule. The visual
-- reach is cosmetic and cannot add hits beyond the explicit collision tip.
scene(10,-4,{box(-1,1,-1,1)})
mob(3,55,-4);objects[3].boxes={box(-1,1,-1,1)}
mob(4,120,-4);objects[4].boxes={box(-1,1,-1,1)}
local swept={x1=0,y1=-4,x2=90,y2=-4,fxX=20,fxY=-4,fxReach=200,
    width=12,damage=6,token="moving-hand",plunder=true}
count,hits=combat.apply(1,swept)
assert(count==2 and hits[2] and hits[3] and not hits[4],"gap between movement path and blade or visual art enlarged collision")
assert(#marked==2)
swept.x1,swept.fxX,swept.x2=20,40,110
assert(combat.apply(1,swept,hits)==0 and #hitCalls==2,"overlapping attack frames must retain entity deduplication")
swept.x1,swept.fxX,swept.x2=40,60,130
assert(combat.apply(1,swept,hits)==1 and hits[4] and #marked==3,"new endpoint did not hit a newly reached enemy")

scene(10,-4,{box(-1,1,-1,1)})
mob(3,55,-4);objects[3].boxes={box(-1,1,-1,1)}
swept.x1,swept.fxX,swept.x2=0,20,90
wall=40
count,hits=combat.apply(1,swept)
assert(count==1 and hits[2] and not hits[3],"forward blade extension hit through a wall")
wall=nil
-- Event endpoints name the complete forward reach, including the capsule's
-- rounded tip. Art has a modest allowance; width must not add extra reach.
local K=dofile(root.."katanas.lua")
for _,variant in ipairs({{"hf_blade","quick"},{"hf_blade","heavy"},{"hf_murasama","quick"},
    {"hf_murasama","dash"},{"dragon_king","quick"},{"dragon_king","dash"}}) do
    local kind,prefix=unpack(variant)
    local def=K.types[kind]
    local handX,handY=20,-4
    local reach,visual=def[prefix.."Reach"],def[prefix.."FxReach"]
    local e={x1=0,y1=handY,x2=handX+reach,y2=handY,fxX=handX,fxY=handY,fxReach=visual,
        width=def[prefix.."Width"],damage=def[prefix.."Damage"],token=kind..prefix,plunder=true}
    scene(handX+visual+2,handY,{box(-0.01,0.01,-0.01,0.01)})
    count,hits=combat.apply(1,e)
    assert(count==1,"small target just beyond the visible slash should lie within reach: "..e.token)
    assert(combat.apply(1,e,hits)==0 and #hitCalls==1 and #marked==1,"same swing hit/rewarded tiny target twice")
    scene(handX+reach-0.05,handY,{box(-0.01,0.01,-0.01,0.01)})
    assert(combat.apply(1,e)==1,"rounded tip fell short of the declared reach: "..e.token)
    scene(handX+reach+1,handY,{box(-0.01,0.01,-0.01,0.01)})
    assert(combat.apply(1,e)==0,"capsule half-width extended damage past declared reach: "..e.token)
    scene(handX+visual+2,handY,{box(-0.01,0.01,-0.01,0.01)})
    wall=handX+5
    assert(combat.apply(1,e)==0,"extended reach pierced intervening terrain: "..e.token)
    wall=nil
end
local function projectileScene()
    objects={};hitCalls={};marked={};parryCalls={};taggedQueries={};bodyQueries={}
    mob(1,0,0,{player_unit=true});objects[1].genome={herd_id=1}
    objects[1].boxes={box(-3,3,-7,4)}
    mob(90,10000,10000) -- The original shooter is outside every combat query.
end
local function bullet(id,x,y,vx,vy,owner)
    mob(id,x,y,{projectile=true});objects[id].dm=nil
    objects[id].shot={mWhoShot=owner or 90,mShooterHerdId=owner==1 and 1 or 2,
        collide_with_entities=true,collide_with_tag="hittable",dont_collide_with_tag="",never_hit_player=false,friendly_fire=false}
    objects[id].velocity={mVelocity={vx or -120,vy or 0}}
    return objects[id]
end
local function reflected(id)
    for _,entry in ipairs(parryCalls) do if entry.id==id then return entry end end
end
local function attack(kind,prefix,plunder)
    local def=K.types[kind]
    return {x1=0,y1=-4,fxX=4,fxY=-4,x2=4+def[prefix.."Reach"],y2=-4,
        fxReach=def[prefix.."FxReach"],width=def[prefix.."Width"],damage=def[prefix.."Damage"],
        kind=kind,token=kind..prefix..tostring(plunder),plunder=plunder}
end
local variants={{"hf_blade","quick"},{"hf_blade","heavy"},{"hf_murasama","quick"},
    {"hf_murasama","dash"},{"dragon_king","quick"},{"dragon_king","dash"}}
for _,variant in ipairs(variants) do
    for _,plunder in ipairs({false,true}) do
        -- Blade Mode uses quick slashes; every ordinary charge/dash shares its geometry.
        if not plunder or variant[2]=="quick" then
            projectileScene()
            local e=attack(variant[1],variant[2],plunder)
            bullet(2,8,-4);bullet(3,e.x2/2,-4);bullet(4,e.x2-1,-4)
            bullet(5,12,-4,-120,0,1) -- Friendly shot inside the same blade.
            bullet(6,e.x2+2,-4,120,0) -- Past the rounded tip and flying away.
            mob(7,20,-4)
            count,hits=combat.apply(1,e)
            assert(count==5 and #parryCalls==4 and #hitCalls==1,"one swing must reflect all touching bullets and still hit its enemy: "..e.token)
            assert(reflected(2) and reflected(3) and reflected(4) and reflected(5) and not reflected(6))
            assert(#marked==(plunder and 1 or 0),"parrying a projectile must not award a kill refill")
            for _,entry in ipairs(parryCalls) do
                assert(entry.nx==1 and entry.ny==0 and entry.x==nil,"inside bullets reflect in place toward the blade tip")
            end
            assert(combat.apply(1,e,hits)==0 and #parryCalls==4 and #hitCalls==1,"same attack repeated a projectile rewrite")
            bullet(8,15,-4)
            assert(combat.apply(1,e,hits)==1 and #parryCalls==5 and reflected(8),"a later new bullet must remain parryable")
        end
    end
end

local e=attack("hf_blade","quick",false)
e.fxX=0;e.x2=36
projectileScene();bullet(2,10,-4);bullet(3,25,-4)
wall=20
count,hits=combat.apply(1,e)
assert(count==1 and reflected(2) and not reflected(3),"blade parried through intervening terrain")
wall=nil
projectileScene();bullet(2,100,-4,-6000,0)
wall=50
assert(combat.apply(1,e)==0 and #parryCalls==0,"predicted incoming bullet crossed a wall before reaching the blade")
wall=nil
assert(combat.apply(1,e)==1 and reflected(2),"unobstructed one-frame crossing was lost")
assert(reflected(2).x<=36 and reflected(2).x>35.9 and reflected(2).y==-4,
    "fast incoming bullet must reflect at the blade's first near face")

-- Paused velocity/shot integrators do not move during the next native step.
-- An already touching paused projectile still reaches the reflection callback.
projectileScene()
bullet(2,20,-30,0,2400).velocity.enabled=false
bullet(3,25,-30,0,2400).shot.enabled=false
bullet(4,16,-4,-6000,0).velocity.enabled=false
objects[4].shot.enabled=false
count,hits=combat.apply(1,e)
assert(count==1 and reflected(4) and not reflected(2) and not reflected(3),"stasis bullet predicted motion or lost its actual contact")
assert(reflected(4).x==nil,"frozen contact must not be moved to a future position")

-- The endpoints both miss: only the native one-frame flight segment crosses.
projectileScene();bullet(2,18,-30,0,3600)
assert(combat.apply(1,e)==1)
assert(reflected(2).x==18 and reflected(2).y>=-10 and reflected(2).y< -9.98,"vertical crossing missed the near side of the blade")
projectileScene();bullet(2,18,-30,0,600)
assert(combat.apply(1,e)==0,"a future crossing more than one physics tick away was parried early")
projectileScene();bullet(2,18,-30,0,-3600)
assert(combat.apply(1,e)==0,"fast projectile moving away was reflected")

-- Do not transport a future interception through the wielder's hitbox.
projectileScene();bullet(2,-30,6,3600,-360)
assert(combat.apply(1,e)==0 and #parryCalls==0,"bullet arriving from behind crossed the wielder before its future blade contact")
objects[1].boxes[1].enabled=false
assert(combat.apply(1,e)==1,"only an enabled native player hitbox may block the predicted interception")

-- A companion, peer or ordinary enemy struck earlier by the original round
-- must remain a native hit, regardless of whether that body is friendly to us.
for _,tags in ipairs({{hittable=true,noita_hideout_companion=true},
    {hittable=true,player_unit=true,ew_client=true},{hittable=true,enemy=true}}) do
    projectileScene()
    local incoming=bullet(2,100,-4,-6000,0)
    mob(3,60,-4,tags);objects[3].boxes={box(-3,3,-5,5)};objects[3].genome={herd_id=1}
    assert(combat.apply(1,e)==0 and #parryCalls==0,"predicted parry crossed a prior hittable body")
    assert(#bodyQueries>0 and bodyQueries[1].tag=="hittable" and #taggedQueries>0)
    objects[3].tags.parry_exempt=true;incoming.shot.dont_collide_with_tag="parry_exempt"
    assert(combat.apply(1,e)==1,"native dont_collide_with_tag exclusion incorrectly blocked the incoming round")
    incoming.shot.dont_collide_with_tag="";incoming.shot.collide_with_entities=false
    assert(combat.apply(1,e)==1,"terrain-only projectile was blocked by a body it cannot collide with")
    incoming.shot.collide_with_entities=true;objects[3].boxes[1].enabled=false
    assert(combat.apply(1,e)==1,"disabled intervening hitbox blocked a predicted parry")
end
projectileScene()
local incoming=bullet(2,100,-4,-6000,0)
mob(3,60,-4,{hittable=true,ew_client=true,player_unit=true});objects[3].boxes={box(-3,3,-5,5)}
incoming.shot.never_hit_player=true
assert(combat.apply(1,e)==1,"native player exclusion must cover other player bodies")
incoming.shot.never_hit_player=false;incoming.shot.collide_with_tag="custom_projectile_target"
assert(combat.apply(1,e)==1,"unmatched original collide_with_tag blocked the incoming round")
objects[3].tags.custom_projectile_target=true
assert(combat.apply(1,e)==0,"matching custom collision tag failed to protect its earlier body hit")
objects[3].genome={herd_id=2}
assert(combat.apply(1,e)==1,"original non-friendly-fire shot cannot hit its own herd")
incoming.shot.friendly_fire=true
assert(combat.apply(1,e)==0,"friendly-fire projectile bypassed an earlier same-herd body collision")
projectileScene()
incoming=bullet(2,100,-4,-6000,0)
objects[90].x,objects[90].y=60,-4;objects[90].tags.hittable=true
objects[90].boxes={box(-3,3,-5,5)};objects[90].genome={herd_id=2}
incoming.shot.friendly_fire=true;incoming.shot.collide_with_shooter_frames=8
incoming.shot.mStartingLifetime=40;incoming.shot.lifetime=35
assert(combat.apply(1,e)==1,"original shooter must remain excluded during its finite immunity")
incoming.shot.lifetime=32
assert(combat.apply(1,e)==0,"expired shooter immunity allowed prediction through a prior native shooter hit")
incoming.shot.collide_with_shooter_frames=-1
assert(combat.apply(1,e)==1,"permanent original shooter immunity should permit the predicted interception")
incoming.shot.collide_with_shooter_frames=0;incoming.shot.friendly_fire=false
assert(combat.apply(1,e)==1,"original non-friendly-fire round must not collide with its shooter")

-- Horizontal ground projection and the old/new blade poses use the true blade
-- direction, even when it differs from the motion-to-tip connecting segment.
projectileScene()
local nx,ny=math.sqrt(1-0.35^2),0.35
local tilt={x1=0,y1=-4,fxX=12,fxY=-4,x2=12+nx*70,y2=-4+ny*70,
    width=18,damage=6,token="tilted-ground",plunder=false}
bullet(2,nx*45-ny*8.9,-4+ny*45+nx*8.9)
bullet(3,12+nx*45+ny*8.9,-4+ny*45-nx*8.9)
count,hits=combat.apply(1,tilt)
assert(count==2 and reflected(2) and reflected(3),"floor-projected step omitted an old or new blade pose")
for _,entry in ipairs(parryCalls) do
    assert(math.abs(entry.nx-nx)<1e-10 and math.abs(entry.ny-ny)<1e-10,"reflected direction used sweep motion instead of blade angle")
end

-- Tagged high-speed shots outside the padded local candidate query are still
-- considered, but only if their very next native step actually reaches steel.
projectileScene();bullet(2,400,-4,-60*(400-36),0)
assert(combat.apply(1,e)==1 and reflected(2),"far fast projectile crossed the tip outside the ordinary candidate radius")
assert(reflected(2).x==36 and #taggedQueries>0)
projectileScene();bullet(2,400,-4,-60*(400-37),0)
assert(combat.apply(1,e)==0,"far shot stopping one pixel short was reflected early")
projectileScene();bullet(2,400,-4,60000,0)
assert(combat.apply(1,e)==0,"outer scan accepted a fast shot travelling away from the blade")
projectileScene();bullet(2,18,-400,0,25200)
assert(combat.apply(1,e)==1 and reflected(2),"far transverse high-speed crossing was missed")
assert(reflected(2).y>=-10 and reflected(2).y< -9.9)
projectileScene();bullet(2,400,-4,-30000,0).velocity.enabled=false
assert(combat.apply(1,e)==0,"outer query projected a disabled velocity component")
projectileScene();bullet(2,400,-4,-30000,0,1)
assert(combat.apply(1,e)==1 and reflected(2),"outer query missed a friendly high-speed shot crossing the blade")
projectileScene();bullet(2,400,-4,-30000,0)
wall=200
assert(combat.apply(1,e)==0,"outer predicted path crossed intervening terrain")
wall=nil

print("Katana combat: six attacks, Blade Mode, multi-projectile parries, paused/high-speed flight, terrain/body occlusion, hitbox sweeps and safe movement passed.")
