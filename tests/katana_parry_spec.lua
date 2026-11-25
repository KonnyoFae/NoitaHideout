local root="mods/noita_hideout/files/"
local entities,components={},{}
local multiplayer,redirectFail=false,false
local sparks,redirects={},0
local function entity(tags)
    local id=#entities+1
    local e={alive=true,tags={},components={},x=12,y=18,r=0.4,sx=-1.25,sy=0.75}
    e.parent=id
    for tag in (tags or ""):gmatch("[^,]+") do e.tags[tag]=true end
    entities[id]=e
    return id
end
function EntityAddComponent2(id,kind,fields)
    local c=fields or {}
    c.kind,c.enabled,c.tags=kind,c.enabled~=false,{}
    for tag in (c._tags or ""):gmatch("[^,]+") do c.tags[tag]=true end
    components[#components+1]=c
    entities[id].components[#entities[id].components+1]=#components
    return #components
end
function EntityGetComponentIncludingDisabled(id,kind,tag)
    local result={}
    for _,c in ipairs(entities[id].components) do
        if components[c].kind==kind and (not tag or components[c].tags[tag]) then result[#result+1]=c end
    end
    return result
end
function EntityGetFirstComponentIncludingDisabled(id,kind,...)
    assert(select("#",...)==0 or select(1,...)~=nil,"Noita rejects explicit nil tags")
    return EntityGetComponentIncludingDisabled(id,kind,...)[1]
end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive or false end
function EntityGetRootEntity(id) return entities[id].parent end
function EntityHasTag(id,tag) return entities[id].tags[tag]==true end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function ComponentGetValue2(c,key)
    local value=components[c][key]
    if type(value)=="table" then return unpack(value) end
    return value
end
function ComponentSetValue2(c,key,a,b) components[c][key]=b~=nil and {a,b} or a end
function ComponentGetIsEnabled(c) return components[c].enabled end
function ComponentHasTag(c,tag) return components[c].tags[tag]==true end
function EntityGetTransform(id)
    local e=entities[id];return e.x,e.y,e.r,e.sx,e.sy
end
function EntitySetTransform(id,x,y,r,sx,sy)
    local e=entities[id];e.x,e.y,e.r,e.sx,e.sy=x,y,r,sx,sy
end
function ModIsEnabled() return multiplayer end
function GameGetGameEffectCount(id) return entities[id].charmed and 1 or 0 end
function GetHerdRelation(a,b) return a==b and 100 or 0 end
function EntityGetHerdRelationSafe(a,b)
    local ga=EntityGetFirstComponentIncludingDisabled(a,"GenomeDataComponent")
    local gb=EntityGetFirstComponentIncludingDisabled(b,"GenomeDataComponent")
    return ga and gb and GetHerdRelation(components[ga].herd_id,components[gb].herd_id) or 0
end
function GameCreateCosmeticParticle(...) sparks[#sparks+1]={...} end
function GameShootProjectile() error("Parry must not reinitialize or respawn the projectile") end
NHEWItems={gid=function(id)
    local e=entities[id];return e.gid,e.invalid,e.owned
end}
local targets=dofile(root.."field_targets.lua")
local freeze={
    getVelocity=function(id)
        local c=EntityGetFirstComponentIncludingDisabled(id,"VelocityComponent")
        if c then return ComponentGetValue2(c,"mVelocity") end
    end,
    redirect=function(id,vx,vy)
        redirects=redirects+1
        if redirectFail then return false end
        assert(not targets.hostileProjectile(1,id),"stasis was checked before changing projectile allegiance")
        local c=EntityGetFirstComponentIncludingDisabled(id,"VelocityComponent")
        ComponentSetValue2(c,"mVelocity",vx,vy)
        return true
    end,
}
function dofile_once(path)
    if path==root.."field_targets.lua" then return targets end
    if path==root.."stasis.lua" then return freeze end
    if path==root.."ew_items.lua" then return NHEWItems end
    error(path)
end
local parry=dofile(root.."katana_parry.lua")
local player=entity("player_unit")
EntityAddComponent2(player,"GenomeDataComponent",{herd_id=1})
local enemy=entity("enemy")
EntityAddComponent2(enemy,"GenomeDataComponent",{herd_id=2})
local function bullet(owner,vx,vy)
    local id=entity("projectile")
    local shot=EntityAddComponent2(id,"ProjectileComponent",{mWhoShot=owner or enemy,mEntityThatShot=owner or enemy,
        mShooterHerdId=2,collide_with_entities=true,collide_with_tag="prey",dont_collide_with_tag="enemy",
        friendly_fire=true,never_hit_player=false,collide_with_shooter_frames=8,explosion_dont_damage_shooter=false,
        velocity_sets_rotation=true,damage=2.5,lifetime=37,mStartingLifetime=80,mInitialSpeed=500,mLastFrameDamaged=21,
        damage_by_type={fire=0.8},config_explosion={damage=4},mDamagedEntities={enemy}})
    local vel=EntityAddComponent2(id,"VelocityComponent",{mVelocity={vx or -300,vy or 400}})
    return id,shot,vel
end
local id,shot,vel=bullet()
local homing=EntityAddComponent2(id,"HomingComponent",{target_tag="prey",target_who_shot=true,predefined_target=player,
    homing_targeting_coeff=9,homing_velocity_multiplier=1})
local area=EntityAddComponent2(id,"AreaDamageComponent",{entities_with_tag="prey",entity_responsible=enemy,damage_per_frame=0.3,update_every_n_frame=4})
local saved=components[shot]
assert(parry.reflect(player,id,shot,vel,0,-7))
local vx,vy=ComponentGetValue2(vel,"mVelocity")
assert(vx==0 and vy==-500 and entities[id].x==12 and entities[id].y==18)
assert(math.abs(entities[id].r+math.pi/2)<1e-9 and entities[id].sx==-1.25 and entities[id].sy==0.75)
assert(components[shot]==saved and saved.damage==2.5 and saved.lifetime==37 and saved.mStartingLifetime==80)
assert(saved.mInitialSpeed==500 and saved.mLastFrameDamaged==21 and saved.damage_by_type.fire==0.8 and saved.config_explosion.damage==4)
assert(saved.mDamagedEntities[1]==enemy and saved.mWhoShot==player and saved.mEntityThatShot==player and saved.mShooterHerdId==1)
assert(saved.collide_with_entities and saved.collide_with_tag=="hittable" and saved.dont_collide_with_tag=="")
assert(not saved.friendly_fire and saved.never_hit_player and saved.collide_with_shooter_frames==-1 and saved.explosion_dont_damage_shooter)
assert(components[homing].target_tag=="enemy" and not components[homing].target_who_shot and components[homing].predefined_target==0)
assert(components[homing].enabled and components[homing].homing_targeting_coeff==9)
assert(components[area].entities_with_tag=="enemy" and components[area].entity_responsible==player and components[area].damage_per_frame==0.3)
assert(components[area].update_every_n_frame==4 and EntityHasTag(id,"nh_katana_reflected"))
assert(#sparks==1 and sparks[1][1]=="spark_white" and sparks[1][4]==5 and sparks[1][8]==0.08 and sparks[1][9]==0.16)
assert(not parry.reflect(player,id,shot,vel,1,0) and #sparks==1,"reflected friendly fire was reflected a second time")

-- Timed/terrain-only explosive shells keep ignoring entity collisions; normal
-- impact projectiles retain them. Both still acquire enemy-targeting filters.
for _,collides in ipairs({false,true}) do
    id,shot,vel=bullet()
    components[shot].collide_with_entities=collides
    assert(parry.reflect(player,id,shot,vel,1,0))
    assert(components[shot].collide_with_entities==collides,"parry changed the native impact trigger")
    assert(components[shot].collide_with_tag=="hittable" and components[shot].dont_collide_with_tag=="")
    assert(components[shot].config_explosion.damage==4 and components[shot].lifetime==37)
end

-- Contact correction preserves the original entity and visual scale; bullets
-- that deliberately spin keep their angle instead of snapping to velocity.
id,shot,vel=bullet();components[shot].velocity_sets_rotation=false
assert(parry.reflect(player,id,shot,vel,3,4,21,22))
assert(entities[id].x==21 and entities[id].y==22 and entities[id].r==0.4 and entities[id].sx==-1.25)
vx,vy=ComponentGetValue2(vel,"mVelocity");assert(vx==300 and vy==400)
assert(sparks[#sparks][2]==21 and sparks[#sparks][3]==22)

-- Stasis pauses the integrators, not their saved velocity. Reflecting must
-- never force-enable components belonging to a second, independent field.
id,shot,vel=bullet()
components[shot].enabled,components[vel].enabled=false,false
components[shot].tags.nh_hourglass_paused,components[vel].tags.nh_hourglass_paused=true,true
assert(parry.reflect(player,id,shot,vel,-1,0))
assert(not components[shot].enabled and not components[vel].enabled)
vx,vy=ComponentGetValue2(vel,"mVelocity");assert(vx==-500 and vy==0)

local function refused(config,nx,ny,cx,cy)
    local e,s,v=bullet()
    if config then config(e,s,v) end
    local owner=components[s].mWhoShot
    local x,y=EntityGetTransform(e)
    local before=#sparks
    assert(not parry.reflect(player,e,s,v,nx or 1,ny or 0,cx,cy))
    assert(components[s].mWhoShot==owner and entities[e].x==x and entities[e].y==y and #sparks==before)
    assert(not EntityHasTag(e,"nh_katana_reflected"))
end
refused(function(e,s,v) components[v].mVelocity={0,0} end)
refused(function(e,s,v) components[v].mVelocity={0/0,1} end)
refused(function(e,s,v) components[v].enabled=false end)
refused(function(e,s) components[s].enabled=false end)
refused(nil,0,0)
refused(nil,math.huge,1)
refused(nil,1,0,20,nil)
for _,kind in ipairs({"ItemComponent","PhysicsBodyComponent","PhysicsBody2Component","PhysicsBodyCollisionDamageComponent",
        "VerletWeaponComponent","VerletPhysicsComponent"}) do
    refused(function(e) EntityAddComponent2(e,kind,{}) end)
end
refused(function(e) EntityAddComponent2(e,"LightningComponent",{is_projectile=true}) end)
refused(function(e) entities[e].parent=enemy end)
refused(function(e,s) components[s].mWhoShot=player end)
local ally=entity("enemy,noita_hideout_companion")
EntityAddComponent2(ally,"GenomeDataComponent",{herd_id=2})
refused(function(e,s) components[s].mWhoShot=ally end)
entities[ally].tags.noita_hideout_companion=nil;entities[ally].charmed=true
refused(function(e,s) components[s].mWhoShot=ally end)
refused(function(e,s) components[s].mWhoShot=0;components[s].mShooterHerdId=0 end)
refused(function(e,s) components[s].mWhoShot=0;components[s].mShooterHerdId=1 end)
id,shot,vel=bullet(0);components[shot].mWhoShot=0
assert(parry.reflect(player,id,shot,vel,1,0),"dead shooter's hostile herd should remain eligible")

-- DES replicas and ambiguous ownership never acquire projectile authority.
multiplayer=true
refused(function(e) entities[e].tags.ew_des=true;entities[e].gid="42";entities[e].owned=false end)
refused(function(e) entities[e].tags.ew_des=true end)
refused(function(e) entities[e].invalid=true end)
id,shot,vel=bullet();entities[id].gid,entities[id].owned="43",true
assert(parry.reflect(player,id,shot,vel,1,0))
multiplayer=false

-- A refused shared redirect rolls back ownership/filters and target changes.
redirectFail=true
id,shot,vel=bullet()
homing=EntityAddComponent2(id,"HomingComponent",{target_tag="prey",target_who_shot=true,predefined_target=player})
assert(not parry.reflect(player,id,shot,vel,1,0,99,88))
assert(components[shot].mWhoShot==enemy and components[shot].collide_with_tag=="prey" and components[shot].friendly_fire)
assert(components[homing].target_tag=="prey" and components[homing].target_who_shot and components[homing].predefined_target==player)
vx,vy=ComponentGetValue2(vel,"mVelocity");assert(vx==-300 and vy==400 and entities[id].x==12)
print("Katana parry: original projectile, speed, credit, homing, moving aura, stasis, contact, rollback and EW ownership passed.")
