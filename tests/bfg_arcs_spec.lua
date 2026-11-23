-- Exercise the same per-frame script that is attached to the shipped BFG projectile.
local script = assert(loadfile("mods/noita_hideout/files/projectiles/bfg_arcs.lua"))
local orb, owner = 40, 1
local entities, shots, damage, frame = {}, {}, {}, 0
local function target(id,x,y)
    entities[id]={x=x,y=y,model={hp=1000},genome={},relation=0}
    return id
end
local function newShot()
    shots={state={name="flight",value_int=0,value_float=0,value_string=""},host={value_int=0,value_float=0},
        projectile={mWhoShot=owner},velocity={},ring={}}
    entities[orb]={x=0,y=0}
    damage={}
end
function GetUpdatedEntityID() return orb end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    if id==orb then
        if kind=="VariableStorageComponent" then return tag=="nh_bfg_state" and shots.state or shots.host end
        if kind=="ProjectileComponent" then return shots.projectile end
        if kind=="VelocityComponent" then return shots.velocity end
        if kind=="SpriteComponent" then return shots.ring end
    else
        if kind=="GenomeDataComponent" then return entities[id].genome end
        if kind=="DamageModelComponent" then return entities[id].model end
        if kind=="HitboxComponent" then return entities[id].box end
    end
end
EntityGetFirstComponent=EntityGetFirstComponentIncludingDisabled
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
EntityGetFirstHitboxCenter=EntityGetTransform
function EntitySetTransform(id,x,y) entities[id].x,entities[id].y=x,y end
function EntityGetInRadiusWithTag(x,y,r,tag)
    assert(tag=="mortal")
    local list={}
    for id,e in pairs(entities) do
        if e.model and (e.x-x)^2+(e.y-y)^2<=r*r then list[#list+1]=id end
    end
    return list
end
function EntityGetHerdRelation(shooter,id) assert(shooter==owner) return entities[id].relation end
function GameGetGameEffectCount(id,kind) assert(kind=="CHARM") return entities[id].charmed and 1 or 0 end
local wall=false
function RaytraceSurfaces(_,_,x) return wall or x==24 end
function GameGetFrameNum() return frame end
function GameCreateCosmeticParticle() end
function EntityRefreshSprite() end
function EntitySetComponentsWithTagEnabled() end
function EntitySetComponentIsEnabled() end
function EntityInflictDamage(id,amount,kind,_,_,_,_,source)
    assert(source==owner)
    local record=damage[id] or {}
    record[kind]=(record[kind] or 0)+amount
    damage[id]=record
end
local function ticks(n)
    for i=1,n do frame=frame+1; script() end
end
local function five(id,each)
    local r=assert(damage[id])
    for _,kind in ipairs({"PROJECTILE","FIRE","SLICE","RADIOACTIVE","EXPLOSION"}) do
        assert(math.abs((r["DAMAGE_"..kind] or 0)-each)<0.00001,kind.." for entity "..id)
    end
end

newShot()
target(owner,0,0)
entities[target(2,15,0)].relation=100
entities[target(3,20,0)].charmed=true
target(4,24,0) -- across a wall
for i=5,8 do target(i,6*i,0) end
ticks(12)
for i=5,7 do five(i,0.4) end
for _,i in ipairs({owner,2,3,4,8}) do assert(not damage[i]) end

entities={}
newShot()
target(owner,0,0)
target(10,7,0)
target(11,150,0)
target(12,200,0)
target(13,201,0)
ticks(1)
assert(shots.state.name=="attached" and shots.host.value_int==10)
-- Move the host and the orbit should preserve the impact offset.
EntitySetTransform(10,7,3)
ticks(12)
assert(entities[orb].x==0 and entities[orb].y==3)
EntitySetTransform(10,7,0)
ticks(60)
assert(shots.state.name=="out" and damage[10].DAMAGE_ELECTRICITY==12)
assert(not damage[10].DAMAGE_FIRE and not shots.projectile.on_death_explode)
ticks(24)
assert(shots.state.name=="in" and shots.ring.special_scale_x==1)
for _,id in ipairs({10,11,12}) do five(id,4) end
assert(not damage[13])
ticks(23)
assert(shots.state.name=="in" and not shots.projectile.on_lifetime_out_explode)
ticks(1)
for _,id in ipairs({10,11,12}) do five(id,8) end
assert(not damage[13] and shots.state.name=="spent" and shots.projectile.lifetime==1)

newShot()
ticks(1)
entities[10]=nil
ticks(1)
assert(shots.state.name=="out")
entities={}
newShot()
ticks(149)
assert(shots.state.name=="flight")
ticks(1)
assert(shots.state.name=="out")
newShot()
ticks(1)
wall=true
EntitySetTransform(orb,2,0)
ticks(1)
assert(shots.state.name=="out" and entities[orb].x==0)
