local medpath="mods/noita_hideout/files/items/medkit.xml"
local grenadepath="mods/noita_hideout/files/items/grenade.xml"
local shotpath="data/entities/projectiles/deck/grenade_small.xml"
local adapters,entities={},{}
local player,selected,new_id=1,nil,10
local mouse_x,mouse_y,pad,inventory_open=100,20,false,false
local last_shot,failed_path,omit_component
local controls={mAimingVectorNormalized={0,-1}}
local health={hp=1,max_hp=1}
entities[player]={x=10,y=20,ControlsComponent=controls,DamageModelComponent=health,GenomeDataComponent={herd_id=7}}
NHNative={held=function() return selected end}
NHTransfers={registerItem=function(kind,match,adapter) adapters[kind]={match=match,adapter=adapter} end}
function EntityLoad(path,x,y)
    if path==failed_path then return 0 end
    local e={x=x,y=y}
    if path==medpath or path==grenadepath then
        e.tag=path==medpath and "noita_hideout_medkit" or "noita_hideout_grenade"
        e.ItemComponent={uses_remaining=path==medpath and 3 or -1}
    elseif path==shotpath then
        e.ProjectileComponent={}
        e.VelocityComponent={}
    else error("unexpected entity "..path) end
    if omit_component then e[omit_component]=nil end
    new_id=new_id+1
    entities[new_id]=e
    return new_id
end
function EntityKill(entity) entities[entity]=nil end
function GameKillInventoryItem(owner,entity)
    assert(owner==player and entity==selected)
    EntityKill(entity)
    selected=nil
end
function EntityHasTag(id,tag) return entities[id].tag==tag end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
function EntityGetFirstComponentIncludingDisabled(id,kind) return entities[id][kind] end
function EntityRemoveComponent(id,component)
    assert(entities[id].ProjectileComponent==component)
    entities[id].ProjectileComponent=nil
end
function ComponentGetValue2(c,key)
    local value=c[key]
    if type(value)=="table" then return unpack(value) end
    return value
end
function ComponentSetValue2(c,key,a,b) c[key]=b and {a,b} or a end
function GameIsInventoryOpen() return inventory_open end
function GameGetIsGamepadConnected() return pad end
function DEBUG_GetMouseWorld() return mouse_x,mouse_y end
function GameShootProjectile(owner,x,y,target_x,target_y,entity)
    assert(owner==player)
    last_shot={x=x,y=y,target_x=target_x,target_y=target_y,id=entity}
    -- The game returns no value.
end
dofile("mods/noita_hideout/files/products.lua")
local medical=adapters.medkit.adapter
selected=assert(medical.restore({kind="medkit"},0,0))
local kit=selected
assert(adapters.medkit.match(kit))
assert(not NHProducts.use(player,kit) and medical.capture(kit).remaining==3)
health.hp=0.2
inventory_open=true
assert(not NHProducts.use(player,kit))
inventory_open=false
selected=nil
assert(not NHProducts.use(player,kit))
selected=kit
assert(NHProducts.use(player,kit) and math.abs(health.hp-0.6)<0.00001)
local record=assert(medical.capture(kit))
assert(record.remaining==2 and record.kind=="medkit")
EntityKill(kit)
kit=assert(medical.restore(record,3,4))
selected=kit
assert(NHProducts.use(player,kit) and health.hp==1)
assert(not NHProducts.use(player,kit) and medical.capture(kit).remaining==1)
health.hp=0.95
assert(NHProducts.use(player,kit) and health.hp==1 and not entities[kit])
for _,bad in ipairs({0,4,1.5,"2"}) do
    assert(not medical.restore({remaining=bad},0,0))
end
omit_component="ItemComponent"
assert(not medical.restore({remaining=3},0,0) and not entities[new_id])
omit_component=nil

local explosive=adapters.grenade.adapter
local grenade=assert(explosive.restore({kind="grenade"},0,0))
assert(adapters.grenade.match(grenade) and not adapters.medkit.match(grenade))
record=assert(explosive.capture(grenade))
assert(record.kind=="grenade")
EntityKill(grenade)
grenade=assert(explosive.restore(record,1,2))
selected=grenade
pad=true
controls.mButtonDownLeftClick=true
mouse_x,mouse_y=10,20
assert(not NHProducts.use(player,grenade) and selected==grenade)
mouse_x,mouse_y=100,20
failed_path=shotpath
assert(not NHProducts.use(player,grenade) and selected==grenade)
failed_path=nil
omit_component="VelocityComponent"
assert(not NHProducts.use(player,grenade) and selected==grenade and not entities[new_id] and not last_shot)
omit_component=nil
assert(NHProducts.use(player,grenade) and not entities[grenade])
local projectile=entities[last_shot.id]
assert(last_shot.x==18 and last_shot.y==20 and last_shot.target_x==198 and last_shot.target_y==20)
assert(projectile.VelocityComponent.mVelocity[1]==180 and projectile.VelocityComponent.mVelocity[2]==0)
assert(projectile.ProjectileComponent.mWhoShot==player and projectile.ProjectileComponent.mShooterHerdId==7)
grenade=assert(explosive.restore(record,0,0))
selected=grenade
controls.mButtonDownLeftClick=false
assert(NHProducts.use(player,grenade))
assert(last_shot.x==10 and last_shot.y==12 and last_shot.target_x==10 and last_shot.target_y==-168)
print("workshop product tests passed")
