local files="mods/noita_hideout/files/"
local entities,time={},0
local wall,attached,network,remote
local owner,dart=1,2
local function spawn(id,x,y,tags)
    local e={x=x,y=y,tags=tags or {},components={},alive=true}
    entities[id]=e
    return e
end
local function enemy(id,x,y,tags)
    local e=spawn(id,x,y,tags)
    e.tags.homing_target=true;e.herd=0
    e.components.GenomeDataComponent={}
    e.components.DamageModelComponent={hp=5}
    e.components.HitboxComponent={aabb_min_x=-1,aabb_max_x=1,aabb_min_y=-2,aabb_max_y=2}
    return e
end
function EntityGetRootEntity(id) return id end
function EntityGetFirstComponent(id,kind) return entities[id].components[kind] end
function EntityGetComponent(id,kind)
    local first=entities[id].components[kind]
    if first then return {first,entities[id].secondary} end
end
EntityGetFirstComponentIncludingDisabled=EntityGetFirstComponent
function EntityGetIsAlive(id) return entities[id] and entities[id].alive end
function EntityHasTag(id,tag) return entities[id].tags[tag] end
function EntityGetHerdRelation(p,e) assert(p==owner);return entities[e].herd end
function GameGetGameEffectCount(id,kind) assert(kind=="CHARM");return entities[id].charm and 1 or 0 end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
EntityGetFirstHitboxCenter=EntityGetTransform
function EntityGetInRadiusWithTag(x,y,r,tag)
    local result={}
    for id,e in pairs(entities) do
        if e.alive and e.tags[tag] and (e.x-x)^2+(e.y-y)^2<=r^2 then result[#result+1]=id end
    end
    return result
end
function EntityKill(id) entities[id].alive=false end
function ComponentGetValue2(c,k)
    if k=="mVelocity" then return c.vx,c.vy end
    if k=="offset" then return c.ox or 0,c.oy or 0 end
    return c[k]
end
function ComponentSetValue2(c,k,x,y) assert(k=="mVelocity");c.vx,c.vy=x,y end
function RaytraceSurfaces(x,y,tx,ty)
    if wall and x<=wall and wall<=tx and x~=tx then return true,wall,y+(ty-y)*(wall-x)/(tx-x) end
    return false
end
function GameGetFrameNum() return time end
function ModIsEnabled(name) assert(name=="quant.ew");return network end
local status={
    attach=function(...) assert(not attached);attached={...};return true end,
    has=function(id,kind) return entities[id].drug==kind end,
}
local factions=dofile(files.."companions/targets.lua")
local authority=dofile(files.."field_targets.lua")
function dofile_once(path)
    if path==files.."ew_items.lua" then NHEWItems={gid=function(id) return tostring(id),false,id~=remote end};return end
    return assert(({[files.."dart_status.lua"]=status,[files.."companions/targets.lua"]=factions,
        [files.."field_targets.lua"]=authority})[path])
end
local flight=dofile(files.."projectiles/smart_dart.lua")
local function start(kind,vx,vy)
    time=time+10
    entities={};wall,attached,network,remote=nil,nil,false,nil
    spawn(owner,-20,0,{player_unit=true})
    local e=spawn(dart,0,0,{nh_sedative_dart=kind=="sedative"})
    e.components.VelocityComponent={vx=vx or 300,vy=vy or 0}
    e.components.ProjectileComponent={mWhoShot=0}
    local state={}
    flight.update(dart,state)
    e.components.ProjectileComponent.mWhoShot=owner
    return e,state
end

local e,s=start("sedative")
enemy(3,18,-3,{player_unit=true});enemy(4,20,-4,{ew_client=true});enemy(5,22,-4,{polymorphed_player=true})
enemy(6,18,-4,{noita_hideout_companion=true});enemy(7,20,-5).herd=70;enemy(8,20,-4).charm=true
enemy(9,20,-4).drug="sedative";enemy(10,-4,-5);enemy(11,60,21)
flight.update(dart,s)
assert(s.target==11 and e.components.VelocityComponent.vy>0,"select untreated hostile in the firing cone")
assert(e.components.VelocityComponent.vy<70,"turn is limited")
entities[11].charm=true;time=time+1;flight.update(dart,s)
assert(not s.target,"release newly friendly lock")
time=time+6;flight.update(dart,s)
assert(s.target==9,"already sedated hostile can be targeted when alone")

e,s=start("sedative");enemy(3,35,0);wall=20;flight.update(dart,s)
assert(not s.target and e.alive,"hidden enemy must not attract shot")
e.x=40;flight.update(dart,s);assert(not e.alive and not attached,"segment crosses terrain before enemy")
e,s=start("pheromone");enemy(13,23,0);enemy(14,12,0);enemy(15,5,0,{nh_reinforcement=true})
enemy(16,6,0).charm=true;wall=20;e.x=30
flight.update(dart,s)
assert(not e.alive and attached[1]==14 and attached[2]=="pheromone","first eligible hit precedes wall and farther hit")
assert(attached[3]==11 and attached[4]==0 and attached[5]==0,"needle tip lands on the first surface")
assert(entities[14].components.DamageModelComponent.hp==5)

e,s=start("sedative");enemy(4,0,20);wall=nil;e.y=30
flight.update(dart,s);assert(attached[1]==4 and attached[2]=="sedative","vertical segment hits thin target")
assert(attached[3]==0 and attached[4]==18 and math.abs(attached[5]-math.pi/2)<0.00001)
e,s=start("sedative");enemy(4,12,10).secondary={aabb_min_x=-2,aabb_max_x=2,aabb_min_y=-2,aabb_max_y=2,oy=-10}
e.x=20;flight.update(dart,s);assert(attached[1]==4,"contacts the secondary offset hitbox")
e,s=start("sedative");enemy(4,5,0,{ew_des=true});enemy(5,10,0)
network=true;remote=4;e.x=12
flight.update(dart,s);assert(not attached and not e.alive,"EW replica consumes shot without local status")
e,s=start("sedative");enemy(4,5,0);entities[owner].alive=false;flight.update(dart,s)
assert(not e.alive and not attached,"expired shooter")
print("Smart dart guidance, friendly exclusions, swept contacts, solid walls and EW authority passed.")
