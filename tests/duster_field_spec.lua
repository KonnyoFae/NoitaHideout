local files="mods/noita_hideout/files/"
local entities={}
local frame=100
function GameGetFrameNum() return frame end
local function entity(x,y,tags,components)
    local id=#entities+1
    entities[id]={x=x,y=y,tags=tags or {},components=components or {},parent=0}
    return id
end
local function component(id,kind) return entities[id].components[kind] end
EntityGetFirstComponent=component
EntityGetFirstComponentIncludingDisabled=component
function ComponentGetValue2(comp,name)
    if name=="mVelocity" then return comp.vx,comp.vy end
    return comp[name]
end
function ComponentSetValue2(comp,name,vx,vy)
    if name=="mVelocity" then comp.vx,comp.vy=vx,vy else comp[name]=vx end
end
function EntityHasTag(id,tag) return entities[id].tags[tag] end
function EntityGetTransform(id) local e=entities[id]; return e.x,e.y,0,1,1 end
function EntityGetIsAlive(id) return entities[id] and not entities[id].dead end
function EntityGetParent(id) return entities[id].parent end
function EntityAddChild(parent,id) entities[id].parent=parent end
function EntityGetAllChildren(parent,tag)
    local children={}
    for id,e in ipairs(entities) do
        if not e.dead and e.parent==parent and EntityHasTag(id,tag) then children[#children+1]=id end
    end
    return children
end
function EntityKill(id) entities[id].dead=true end
function EntityLoad(path,x,y)
    assert(path==files.."duster_field.xml")
    return entity(x,y,{nh_duster_field=true},{VariableStorageComponent={value_int=0},LifetimeComponent={kill_frame=0}})
end
function EntityApplyTransform(id,x,y) entities[id].x,entities[id].y=x,y end
local wall
function RaytracePlatforms() if wall then return true,wall,0 end; return false end
function ModIsEnabled(name) assert(name=="quant.ew"); return false end
function dofile_once(path)
    if path==files.."ew.lua" then return {localBody=function(id) return not EntityHasTag(id,"ew_client") end} end
    assert(path==files.."field_targets.lua")
    return {canAffect=function(id,ew)
        assert(ew==false)
        return entities[id].parent==0 and not EntityHasTag(id,"player_unit") and not EntityHasTag(id,"ew_notplayer")
    end}
end
function EntityGetInRadius(x,y,r)
    assert(r==90)
    local result={}
    for id,e in ipairs(entities) do
        if not e.dead and (e.x-x)^2+(e.y-y)^2<=r^2 then result[#result+1]=id end
    end
    return result
end
local body={}
function PhysicsBodyIDGetFromEntity(_,comp) assert(comp==body); return {101} end
function PhysicsBodyIDGetTransform(id) assert(id==101); return 11,22,1.5,0,-1,5 end
function GameVecToPhysicsVec(speed) return speed/16 end
function PhysicsBodyIDSetTransform(id,x,y,angle,vx,vy,spin)
    assert(id==101 and x==11 and y==22 and angle==1.5 and spin==5)
    assert(vx>0 and vy==-1)
    body.pushed=true
end
local M=dofile(files.."duster_field.lua")
local player=entity(0,0,{player_unit=true,mortal=true},{CharacterDataComponent={vx=0,vy=0}})
assert(not M.activate(0))
assert(not M.activate(entity(0,0,{ew_client=true,player_unit=true})))
assert(not M.activate(player,function() return false end))
assert(entities[#entities].dead and #EntityGetAllChildren(player,"nh_duster_field")==0)
assert(M.activate(player))
local field=EntityGetAllChildren(player,"nh_duster_field")[1]
assert(component(field,"VariableStorageComponent").value_int==3700)
local ok,reason=M.activate(player)
assert(not ok and reason=="Field already active.")
local shot=entity(50,0,{},{ProjectileComponent={},VelocityComponent={vx=-1000,vy=10}})
local fast=entity(85,0,{projectile=true},{VelocityComponent={vx=900,vy=10}})
local enemy=entity(0,0,{enemy=true},{CharacterDataComponent={vx=0,vy=10}})
local far=entity(91,0,{enemy=true},{CharacterDataComponent={vx=0,vy=0}})
local frozen=entity(17,0,{mortal=true,nh_hourglass_still=true},{CharacterDataComponent={vx=0,vy=0}})
local ally=entity(12,0,{mortal=true,ew_notplayer=true},{CharacterDataComponent={vx=0,vy=0}})
local held=entity(12,0,{},{ItemComponent={is_pickable=true}}); EntityAddChild(player,held)
local shop=entity(13,0,{},{ItemComponent={is_pickable=true},ItemCostComponent={}})
local bag=entity(22,0,{},{ItemComponent={is_pickable=true}})
local unpickable=entity(17,0,{},{ItemComponent={is_pickable=false}})
entity(16,0,{},{PhysicsBody2Component=body})
entity(18,0,{mortal=true},{PhysicsBody2Component={is_static=true}})
entity(19,0,{mortal=true},{PhysicsBodyComponent={is_static=true}})
entity(21,0,{mortal=true},{PhysicsBodyComponent={},PhysicsJointComponent={}})
wall=26
M.update(field)
assert(component(field,"LifetimeComponent").kill_frame==3700)
assert(component(shot,"VelocityComponent").vx>0 and component(shot,"VelocityComponent").vy==10)
assert(component(fast,"VelocityComponent").vx==900 and component(enemy,"CharacterDataComponent").vy<0)
assert(component(far,"CharacterDataComponent").vx==0 and body.pushed)
assert(component(frozen,"CharacterDataComponent").vx==0 and component(ally,"CharacterDataComponent").vx==0)
assert(component(player,"CharacterDataComponent").vy==0)
assert(entities[held].x==12 and entities[shop].x==13 and entities[unpickable].x==17)
assert(entities[bag].x==24)
entities[player].x=150
frame=3699
component(field,"LifetimeComponent").kill_frame=7299
M.update(field)
assert(component(field,"LifetimeComponent").kill_frame==3700)
assert(component(far,"CharacterDataComponent").vx<0 and entities[bag].x==24)
frame=3700
M.update(field)
assert(entities[field].dead and M.activate(player))
field=EntityGetAllChildren(player,"nh_duster_field")[1]
entities[field].parent=0
M.update(field)
assert(entities[field].dead and M.activate(player))
local xml=assert(io.open(files.."duster_field.xml","rb")):read("*a")
assert(xml:find('lifetime="3600"') and xml:find('use_material_inventory="1"') and xml:find('execute_on_removed="1"'))
for kind=0,2 do
    local rects={}
    for bounds in xml:gmatch('<MaterialSuckerComponent material_type="'..kind..'" suck_static_materials="0"([^>]+)/>') do
        local minx,maxx,miny,maxy=bounds:match('min_x="(%-?%d+)".-max_x="(%-?%d+)".-min_y="(%-?%d+)".-max_y="(%-?%d+)"')
        minx,maxx,miny,maxy=tonumber(minx),tonumber(maxx),tonumber(miny),tonumber(maxy)
        assert(minx<0 and miny<0 and maxx==-minx and maxy==-miny and maxx^2+maxy^2<=90^2)
        rects[maxx..","..maxy]=true
    end
    assert(rects["63,63"] and rects["83,32"] and rects["32,83"])
end
assert(not xml:find("BlackHoleComponent") and not xml:find("CellEaterComponent") and not xml:find("LooseGroundComponent"))
-- A blocked outlet holds the original mixture. After an opening is made,
-- every cell is emitted at the former rim, once, and the outlet disappears.
local store={count_per_material_type={0,91,3}}
local outlet=entity(0,0,{nh_duster_outlet=true},{MaterialInventoryComponent=store})
function GetUpdatedEntityID() return outlet end
function GetMaterialInventoryMainMaterial() return store.empty and 0 or 1 end
function CellFactory_GetName(n) return ({[1]="sand",[2]="water"})[n] end
function RemoveMaterialInventoryMaterial(e,kind) assert(e==outlet and kind==""); store.empty=true end
local sealed=true
function RaytraceSurfacesAndLiquiform() return sealed end
local emitted={}
function GameCreateParticle(name,x,y,count,vx,vy,visual)
    assert(math.abs(x*x+y*y-87^2)<0.01 and x*vx+y*vy>0 and not visual)
    emitted[name]=(emitted[name] or 0)+count
end
dofile(files.."duster_outlet_tick.lua")
assert(not entities[outlet].dead and not next(emitted) and not store.empty)
sealed=false
dofile(files.."duster_outlet_tick.lua")
assert(entities[outlet].dead and store.empty and emitted.sand==91 and emitted.water==3)
print("Duster field: ownership, movable objects, projectile deflection, protected targets, walls and recasting passed.")
