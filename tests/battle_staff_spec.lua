local root="mods/noita_hideout/files/"
local staff=dofile(root.."battle_staff.lua")
NHFirearms=dofile(root.."firearms.lua")
local paths,clock,mag,controls={},{value_int=0},{value_int=120},{mButtonDownFire=false}
local segments,buffs,forms,hits={},{},0,0
local velocity,shot,poly={},{},{frames=3600}
local enemyMotion={}
local pos={[1]={0,0},[3]={8,0},[4]={30,0},[5]={0,30},[6]={8,0}}
local mob=true
local allowed=true
function PolymorphTableGet(rare)
    assert(rare==false)
    return {"data/entities/animals/shotgunner.xml","data/entities/animals/boss_test.xml","data/entities/animals/acidshooter_weak.xml",
        "data/entities/animals/acidshooter.xml","data/entities/animals/slimeshooter.xml","data/entities/animals/scavenger_smg.xml","data/entities/animals/bigzombiehead.xml"}
end
function ModTextFileGetContent(path)
    if path=="data/entities/animals/bigzombiehead.xml" then return '<Entity><GenomeDataComponent herd_id="zombie"/></Entity>' end
    return "<Entity/>"
end
local targetName=""
function EntityGetName() return targetName end
function ModTextFileSetContent(path,xml) paths[path]=xml end
local charmed,boss=false,false
function GameGetGameEffectCount(id,kind) assert(kind=="CHARM");return charmed and 1 or 0 end
staff.register()
local form=root.."staff_forms/shotgunner_effect.xml"
assert(not paths[root.."staff_forms/acidshooter_effect.xml"] and not paths[root.."staff_forms/acidshooter_weak_effect.xml"])
assert(paths[form]:find('frames="3600"') and paths[form]:find('polymorph_target="data/entities/animals/shotgunner.xml"',1,true))
assert(paths[form]:find('_tags="nh_staff_mimic"',1,true) and not paths[root.."staff_forms/shotgunner.xml"] and not paths[root.."staff_forms/boss_test_effect.xml"])
local guard,hitTag
local heldSprite={visible=true,rect_animation="default",has_special_scale=true,special_scale_x=0.5,special_scale_y=0.5}
local frameNow=0
local dragonPresent,dragonClock,fields=false,{value_float=0},0
pos[12]={-6,-6}
function EntityGetAllChildren(_,tag) if dragonPresent and tag=="nh_companion_dragon" then return {12} end end
function EntityAddTag(id,tag) assert(id==13 and tag=="nh_companion_shot") end
pos[2]={1,0,0,1,1}
function EntityGetTransform(id) return unpack(pos[id]) end
function EntityGetFirstHitboxCenter(id) return EntityGetTransform(id) end
function PhysicsBodyIDQueryBodies() return {} end
function GameVecToPhysicsVec(x,y) return x/10,y/10 end
function EntityGetRootEntity(id) return id end
function EntityGetIsAlive() return true end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    if id==1 and tag=="nh_dragon_shot" and dragonPresent then return {} end
    if id==12 and tag=="nh_companion_clock" then return dragonClock end
    if id==13 and (kind=="ProjectileComponent" or kind=="VelocityComponent") then return {} end
    if id==2 and kind=="SpriteComponent" and tag=="enabled_in_hand" then return heldSprite end
    if id==10 and kind=="DamageModelComponent" then return {} end
    if id==10 and tag=="nh_staff_mimic_guard" then return guard end
    if kind=="ControlsComponent" then return controls end
    if tag=="nh_staff_clock" then return clock end
end
function EntityGetFirstComponent(id,kind,tag)
    if id==3 and kind=="CharacterDataComponent" then return enemyMotion end
    if id==2 and kind=="SpriteComponent" and tag=="enabled_in_hand" then return heldSprite end
    if kind=="VelocityComponent" and (id==5 or id==9) then return velocity end
    if id==9 and kind=="ProjectileComponent" then return shot end
end
function ComponentGetValue2(comp,key) if key=="mVelocity" then return 0,0 end; return comp[key] end
function ComponentSetValue2(comp,key,val,other) comp[key]=other and {val,other} or val end
function GameGetIsGamepadConnected() return false end
function DEBUG_GetMouseWorld() return 8,0 end
function EntityGetFilename() return "data/entities/animals/shotgunner.xml" end
function EntityGetInRadius(_,_,radius)
    return radius>=30 and {1,3,4,5,6} or {1,3,6}
end
function EntityGetInRadiusWithTag() return mob and {6,3} or {} end
function EntityHasTag(id,tag)
    if id==2 and tag=="noita_hideout_battle_staff" then return true end
    if id==3 and tag=="boss" then return boss end
    if id==10 and tag=="nh_staff_mimic_hit" then return hitTag end
    return (tag=="enemy" and (id==3 or id==4 or id==6)) or (id==6 and tag=="nh_reinforcement") or
        (tag=="projectile" and id==5) or (tag=="polymorphed_player" and id==10)
end
function EntityGetHerdRelationSafe() return 0 end
function RaytracePlatforms() return false end
local swings,thumps=0,0
function EntityInflictDamage(id,amount,kind,_,_,ix,iy,owner,_,_,knockback)
    assert(id~=6 and amount==1 and kind=="DAMAGE_MELEE" and owner==1 and knockback>0)
    assert(ix~=0 and iy<0)
    hits=hits+1
end
function GameCreateParticle() end
function GamePlaySound(bank,event)
    if event=="player/throw" then assert(bank=="data/audio/Desktop/player.bank"); swings=swings+1
    elseif event=="player/kick" then assert(bank=="data/audio/Desktop/player.bank"); thumps=thumps+1 end
end
local function drawnAngle()
    local index=tonumber(heldSprite.rect_animation:match("^swing_(%d+)$")) or 0
    local localAngle=index*math.pi/32
    return pos[2][3]+math.atan2(heldSprite.special_scale_y*math.sin(localAngle),heldSprite.special_scale_x*math.cos(localAngle))
end
function EntityRefreshSprite(id,sprite) assert(id==2 and sprite==heldSprite) end
function GetUpdatedEntityID() return 2 end
function GameGetFrameNum() return frameNow end
function GameShootProjectile(owner,x,y,tx,ty,id,message)
    assert(owner==1)
    if id==13 then assert(message==false); fields=fields+1 end
    if id==8 then
        local dx,dy=math.cos(drawnAngle()),math.sin(drawnAngle())
        assert(message==false and math.abs(tx-x-18*dx)<0.001 and math.abs(ty-y-18*dy)<0.001)
        assert(math.abs((x-pos[2][1])*dy-(y-pos[2][2])*dx)<0.001)
    end
end
function EntityLoad(path,x,y)
    if path==root.."companions/matter_field.xml" then return 13 end
    if path==root.."projectiles/staff_blade.xml" then segments[#segments+1]=math.sqrt((x-1)^2+y^2);return 8 end
    if path==root.."projectiles/staff_orb.xml" then return 9 end
    assert(path==root.."staff_mana.xml");return 11
end
function EntityAddChild(owner,id)
    assert(owner==1 and id==11); buffs[#buffs+1]=id
end
NHNative={held=function() return 2 end}
NHProducts={aim=function() return 1,0 end}
local function tick(index,down,frame,blocked,reloading,canMimic)
    frameNow=frame
    dofile(root.."equipment_sprite_mirror.lua")
    controls.mButtonDownFire=down
    return staff.update(1,2,mag,index,mag.value_int,frame,blocked,reloading,canMimic)
end
mag.value_int=0
dragonPresent=true
tick(1,true,10); tick(1,false,11);assert(drawnAngle()<0 and hits==0)
for frame=12,17 do tick(1,false,frame) end
assert(drawnAngle()>0 and #segments==0 and hits==1 and mag.value_int==0 and fields==1)
assert(swings==1 and thumps==1)
assert(enemyMotion.mVelocity[1]>0 and enemyMotion.mVelocity[2]<0)
dragonPresent=false
tick(1,false,19);assert(heldSprite.rect_animation=="default" and heldSprite.visible)
mag.value_int=120
tick(1,true,20); tick(1,true,79); assert(mag.value_int==120)
tick(1,true,80);tick(1,true,140);tick(1,true,200);tick(1,true,300);tick(1,false,301)
assert(drawnAngle()<-math.pi/2 and #segments==3)
for frame=302,313 do
    -- Turn the native wand and flip its axes during a locked swing.
    pos[2][3]=frame*0.02
    pos[2][4]=frame%3==0 and -1 or 1
    pos[2][5]=frame%2==0 and -1 or 1
    tick(1,false,frame)
    local t=(frame-301)/12
    local expected=math.rad(96)*(2*t*t*(3-2*t)-1)
    assert(math.cos(drawnAngle()-expected)>=math.cos(math.pi/64)-1e-8)
end
assert(hits==3 and mag.value_int==117 and #segments==21)
assert(swings==2 and thumps==2)
for index,distance in ipairs(segments) do assert(math.abs(distance-(13+18*((index-1)%3)))<0.001) end
tick(1,true,320);tick(1,true,360,true);tick(1,false,361);assert(#segments==21 and mag.value_int==117)
NHProducts.aim=function() return -1,0 end
pos[2]={1,0,0,-1,1}
tick(1,true,370);assert(math.cos(drawnAngle()-math.rad(228))>=math.cos(math.pi/64))
tick(2,false,371);tick(2,false,372);assert(heldSprite.rect_animation=="default" and heldSprite.visible)
tick(1,true,375)
for age=0,6 do
    tick(1,false,376+age)
    local t=age/6
    local expected=math.pi-math.rad(48)*(2*t*t*(3-2*t)-1)
    assert(math.cos(drawnAngle()-expected)>=math.cos(math.pi/64)-1e-8)
end
NHProducts.aim=function() return 1,0 end
tick(2,true,400);assert(mag.value_int==97 and shot.mWhoShot==1)
dragonPresent=true
tick(3,true,436);tick(3,true,495);assert(#buffs==1 and mag.value_int==87 and velocity.mVelocity[2]>0)
tick(3,true,496);assert(#buffs==2 and mag.value_int==77)
assert(fields==3)
dragonPresent=false
do
    local oldQuery,oldComponent,oldRay=EntityGetInRadius,EntityGetFirstComponent,RaytracePlatforms
    local resume=clock.value_int
    pos[14]={21,0}
    local boxes={[101]={11,-2,31,2},[102]={6,5,8,7},[103]={6,-3,8,-1},[104]={5,-1,7,1}}
    function PhysicsBodyIDQueryBodies(x1,y1,x2,y2)
        local list={}
        for id,b in pairs(boxes) do
            if b[1]<=x2 and b[2]<=y2 and b[3]>=x1 and b[4]>=y1 then list[#list+1]=id end
        end
        return list
    end
    function PhysicsBodyIDGetWorldCenter(id)
        local b=boxes[id]
        return (b[1]+b[3])/20,(b[2]+b[4])/20
    end
    function PhysicsPosToGamePos(x,y) return x*10,y*10 end
    function EntityGetInRadius() return {1,6,14} end
    function EntityGetFirstComponent(id,kind,tag)
        if kind=="PhysicsBody2Component" and (id==14 or id==6 or id==1) then return id end
        if id==14 and kind=="DamageModelComponent" then return {} end
        return oldComponent(id,kind,tag)
    end
    function PhysicsBodyIDGetFromEntity(id,comp)
        assert(comp==id)
        return {({[14]=101,[6]=103,[1]=104})[id]}
    end
    local impulses={}
    function PhysicsBodyIDApplyLinearImpulse(body,ix,iy,x,y)
        assert((body==101 or body==102) and not impulses[body] and ix>0 and iy<0)
        impulses[body]={ix=ix,x=x}
    end
    local wall=false
    function RaytracePlatforms(x,y,tx,ty)
        local edge=wall and 3 or 11
        if tx>=edge and (wall or math.abs(ty)<=2) then return true,edge,y+(ty-y)*(edge-x)/(tx-x) end
        return false
    end
    local function sweep(start,charge)
        staff.reset()
        tick(1,true,start)
        if charge then tick(1,true,start+60) end
        local release=start+(charge and 61 or 1)
        for frame=release,release+10 do tick(1,false,frame) end
    end
    local beforeHits,beforeSwings,beforeThumps=hits,swings,thumps
    sweep(700,false)
    assert(impulses[101] and impulses[101].x==11 and impulses[102])
    assert(hits==beforeHits+1 and swings==beforeSwings+1 and thumps==beforeThumps+1)
    local base=impulses[101].ix
    impulses={}
    sweep(720,true)
    assert(impulses[101].ix>base and impulses[102] and thumps==beforeThumps+2)
    wall=true
    impulses={}
    sweep(810,false)
    assert(not next(impulses) and hits==beforeHits+2 and swings==beforeSwings+3 and thumps==beforeThumps+2)
    EntityGetInRadius,EntityGetFirstComponent,RaytracePlatforms=oldQuery,oldComponent,oldRay
    PhysicsBodyIDQueryBodies=function() return {} end
    staff.reset()
    clock.value_int=resume
    mag.value_int=77
end
local shield={allowMimic=function() return allowed end,sync=function() end}
do
    local query,filename,ray=EntityGetInRadiusWithTag,EntityGetFilename,RaytracePlatforms
    local function preview(frame,...)
        local points,charge,cast,target=tick(4,false,frame,...)
        assert(points==mag.value_int and not charge and not cast)
        return target
    end
    assert(preview(555).status=="cooldown" and preview(556).form==form)
    assert(preview(556,false,false,function() return false end).status=="immune")
    mag.value_int=29;assert(preview(556).status=="ammo");mag.value_int=77
    assert(preview(556,true,true).status=="reload" and not preview(556,true,false))
    EntityGetInRadiusWithTag=function() return {3} end
    for _,species in ipairs({"acidshooter","acidshooter_weak","vault/acidshooter","crypt/acidshooter"}) do
        EntityGetFilename=function() return "data/entities/animals/"..species..".xml" end
        assert(preview(556).substitute=="slimeshooter")
        local points,_,cast,target=tick(4,true,556)
        assert(cast and target.status=="ready" and paths[target.form]:find('polymorph_target="data/entities/animals/slimeshooter.xml"',1,true) and points==77 and mag.value_int==77)
    end
    EntityGetFilename=filename;targetName="$animal_acidshooter";assert(preview(556).substitute=="slimeshooter");targetName=""
    EntityGetFilename=function() return "data/entities/animals/vault/scavenger_smg.xml" end
    local vault=preview(556);assert(vault.status=="ready" and vault.substitute=="scavenger_smg")
    EntityGetFilename=function() return "data/entities/animals/rainforest/scavenger_smg.xml" end
    local jungle=preview(556);assert(jungle.status=="ready" and jungle.form==vault.form)
    EntityGetFilename=function() return "data/entities/animals/bigzombiehead.xml" end
    assert(preview(556).status=="ready" and not preview(556).substitute)
    boss=true;assert(preview(556).status=="unsupported")
    EntityGetFilename=function() return "data/entities/animals/boss_arena/scavenger_smg.xml" end
    assert(preview(556).substitute=="scavenger_smg");boss=false;EntityGetFilename=function() return "data/entities/animals/bigzombiehead.xml" end
    charmed=true;assert(preview(556).substitute=="bigzombiehead");charmed=false
    EntityGetFilename=function() return "data/entities/animals/illusions/scavenger_grenade.xml" end
    assert(preview(556).substitute=="scavenger_smg")
    EntityGetFilename=function() return "data/entities/animals/unknown.xml" end
    assert(preview(556).status=="unsupported")
    EntityGetFilename=filename; RaytracePlatforms=function() return true end
    assert(preview(556).status=="ready")
    EntityGetInRadiusWithTag=function() return {3,6} end
    pos[3]={12,0};assert(preview(556).substitute=="shotgunner");pos[3]={8,0}
    EntityGetInRadiusWithTag=function(_,_,_,tag) return tag=="nh_reinforcement" and {6} or {} end;assert(preview(556).substitute=="shotgunner")
    EntityGetInRadiusWithTag=function() return {} end;assert(not preview(556))
    EntityGetInRadiusWithTag,RaytracePlatforms=query,ray
    assert(mag.value_int==77 and clock.value_int==556 and forms==0)
end
function LoadGameEffectEntityTo(owner,path) assert(owner==1 and path==form and mag.value_int==47);forms=forms+1;return 0 end
tick(4,false,555);mob=false;local _,_,cast=tick(4,true,556);assert(not cast and mag.value_int==77)
mob=true;tick(4,false,557); _,_,cast=tick(4,true,558);allowed=false;cast(shield,{});assert(forms==0 and mag.value_int==77)
allowed=true;cast(shield,{});assert(forms==1 and mag.value_int==77 and clock.value_int==556)
function LoadGameEffectEntityTo() assert(mag.value_int==47);return 42 end
cast(shield,{});assert(mag.value_int==47)
function GameGetGameEffect(_,kind) assert(kind=="POLYMORPH");return poly end
function ComponentHasTag(comp,tag) return comp[tag] end
function EntityAddComponent2(id,kind,fields)
    assert(id==10 and kind=="LuaComponent" and fields.script_damage_about_to_be_received==root.."staff_mimic_damage.lua" and not guard)
    guard=fields;return guard
end
function EntityAddTag(id,tag) assert(id==10 and tag=="nh_staff_mimic_hit" and not hitTag); hitTag=true end
assert(not staff.guardMimic(10) and not guard)
poly.nh_staff_mimic=true
assert(staff.guardMimic(10) and staff.guardMimic(10) and guard)
function GetUpdatedEntityID() return 10 end
dofile(root.."staff_mimic_damage.lua")
assert(damage_about_to_be_received(-1,0,0,1,0)==-1 and poly.frames==3600)
local damage,crit=damage_about_to_be_received(10000,0,0,1,100)
assert(damage==0 and crit==0 and hitTag and poly.frames==3600)
assert(damage_about_to_be_received(20,0,0,1,99)==0 and staff.guardMimic(10) and poly.frames==1)
poly.frames=0;assert(staff.guardMimic(10) and poly.frames==0)
function EntityGetParent() return 1 end
function GameGetAllInventoryItems() return {12,13} end
local wand={mana=0,mana_max=3}
function EntityHasTag(id,tag) return tag=="wand" or (id==13 and tag=="nh_firearm") end
function EntityGetFirstComponentIncludingDisabled(id) assert(id==12);return wand end
for _=1,2 do dofile(root.."staff_mana.lua") end
assert(wand.mana==3)
print("Battle staff: free swings, charge, interruption, blast, stacked pulses, mimic costs, refusal, rollback and lethal-hit release passed.")
