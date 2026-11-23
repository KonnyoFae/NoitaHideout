local root="mods/noita_hideout/files/terminals/"
local entities,nextID={},0
local loaded=true
local function spawn(x,y,tags,components)
    nextID=nextID+1
    entities[nextID]={x=x,y=y,tags=tags or {},components=components or {}}
    return nextID
end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityHasTag(id,tag) return entities[id].tags[tag] or false end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityGetWithTag(tag)
    local ids={}
    for id in pairs(entities) do if EntityHasTag(id,tag) then ids[#ids+1]=id end end
    return ids
end
function EntityGetInRadiusWithTag(x,y,r,tag)
    local ids={}
    for _,id in ipairs(EntityGetWithTag(tag)) do
        local e=entities[id]
        if (x-e.x)^2+(y-e.y)^2<=r*r then ids[#ids+1]=id end
    end
    return ids
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return entities[id].components[kind..(tag or "")] end
function EntityAddComponent2(id,kind,values) entities[id].components[kind..(values._tags or "")]=values; return values end
function ComponentSetValue2(c,k,v,w) c[k]=w and {v,w} or v end
function ComponentGetValue2(c,k) if k=="mVelocity" then return unpack(c[k]) end; return c[k] end
function EntityRefreshSprite() end
function DoesWorldExistAt() return loaded end
function RaytraceSurfaces(x) return true,x,10 end
function EntityLoad(path,x,y) assert(path==root.."station.xml"); return spawn(x,y,{nh_home_terminal=true}) end
function EntityGetHerdRelationSafe(_,id) return entities[id].relation or 0 end
function PhysicsApplyForce(id,x,y) entities[id].force={x,y} end
local player=spawn(0,0,{player_unit=true})
local T=dofile(root.."station.lua")
loaded=false; T.home(player,0,0)
assert(#EntityGetWithTag("nh_home_terminal")==0)
loaded=true; T.home(player,0,0)
local home=EntityGetWithTag("nh_home_terminal")[1]
assert(entities[home].x==24 and entities[home].y==3)
for i=1,3 do T.reset(); T.home(player,0,0) end
assert(#EntityGetWithTag("nh_home_terminal")==1)
assert(EntityGetFirstComponentIncludingDisabled(home,"LuaComponent","nh_terminal_field"))
local sprite=EntityGetFirstComponentIncludingDisabled(home,"SpriteComponent")
assert(sprite.image_file==root.."comms_big.png" and sprite.special_scale_x==0.5)
local old=spawn(200,0,{}, {SpriteComponent={image_file="data/buildings_gfx/chest_steel.png"}})
T.upgrade(old); T.upgrade(old)
assert(entities[old].x==200 and EntityHasTag(old,"nh_terminal_v1"))
local function checkRing(ring)
    assert(ring.area_circle_radius[1]==96 and ring.area_circle_radius[2]==96)
    assert(ring.gravity[1]==0 and ring.gravity[2]==0)
end
checkRing(EntityGetFirstComponentIncludingDisabled(old,"ParticleEmitterComponent","nh_terminal_ring"))
local savedRing={area_circle_radius={0,0},gravity={0,100}}
local previous=spawn(100,0,{nh_terminal_v1=true},{ParticleEmitterComponentnh_terminal_ring=savedRing})
T.upgrade(previous); T.upgrade(previous)
assert(EntityGetFirstComponentIncludingDisabled(previous,"ParticleEmitterComponent","nh_terminal_ring")==savedRing)
checkRing(savedRing)
local F=dofile(root.."field.lua")
local station=spawn(0,0)
local function projectile(x,y,vx,vy)
    return spawn(x,y,{projectile=true},{VelocityComponent={mVelocity={vx,vy}}})
end
local incoming=projectile(80,0,-600,20)
local outgoing=projectile(80,0,600,20)
local outside=projectile(120,0,-600,0)
local center=projectile(0,0,0,0)
local enemy=spawn(-70,0,{enemy=true},{CharacterDataComponent={mVelocity={90,0}}})
local friend=spawn(-70,0,{enemy=true},{CharacterDataComponent={mVelocity={90,0}}})
entities[friend].relation=100
local pet=spawn(-70,0,{enemy=true,noita_hideout_companion=true},{CharacterDataComponent={mVelocity={90,0}}})
local turret=spawn(-70,0,{enemy=true,nh_deployed_turret=true},{CharacterDataComponent={mVelocity={90,0}}})
local physics=spawn(0,70,{enemy=true},{PhysicsBody2Component={}})
F.update(station)
local function velocity(id,kind) return unpack(entities[id].components[kind or "VelocityComponent"].mVelocity) end
assert(velocity(incoming)>600)
local vx,vy=velocity(outgoing); assert(vx==600 and vy==20)
assert(velocity(outside)==-600)
vx,vy=velocity(center); assert(vx==0 and vy==-240)
assert(velocity(enemy,"CharacterDataComponent")==-180)
for _,id in ipairs({friend,pet,turret}) do assert(velocity(id,"CharacterDataComponent")==90) end
assert(entities[physics].force[1]==0 and entities[physics].force[2]==30)
print("Terminals: loaded-area spawning, ground placement, reload deduplication, old locker migration, projectile deflection and friendly-safe enemy repulsion passed.")

entities[incoming].components.VelocityComponent.mVelocity={-600,20}
local close=projectile(30,0,-600,0)
F.update(station,48)
assert(velocity(incoming)==-600 and velocity(close)>=600)
print("Small terminal field uses half the fixed terminal radius.")
