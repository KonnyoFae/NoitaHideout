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
    local kind=path:match("^mods/noita_hideout/files/items/(%w[%w_]*)%.xml$")
    if kind then
        e.tag="noita_hideout_"..kind
        e.ItemComponent={uses_remaining=path==medpath and 3 or -1}
    elseif path=="mods/noita_hideout/files/effect_bread.xml" then
        e.tag="noita_hideout_effect_bread"
        e.VariableStorageComponent={value_int=120}
    elseif path=="mods/noita_hideout/files/effect_sugar_cube.xml"
        or path=="mods/noita_hideout/files/effect_food_mana.xml" or path=="mods/noita_hideout/files/effect_food_levitation.xml" then
        e.tag="noita_hideout_effect_"..path:match("effect_(.+)%.xml")
        e.GameEffectComponent={frames=7200}
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
function EntityAddChild(owner,child) entities[child].owner=owner end
function EntityGetParent(id) return entities[id].owner end
function EntityGetAllChildren(owner,tag)
    local result={}
    for id,e in pairs(entities) do
        if e.owner==owner and (not tag or e.tag==tag) then result[#result+1]=id end
    end
    return result
end
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

local function select_product(kind)
    local a=adapters[kind].adapter
    selected=assert(a.restore({kind=kind},0,0))
    assert(adapters[kind].match(selected) and a.capture(selected).kind==kind)
    return selected
end
local bandage=select_product("bandage")
health.hp=health.max_hp
assert(not NHProducts.use(player,bandage) and entities[bandage])
health.hp=0.5
assert(NHProducts.use(player,bandage) and math.abs(health.hp-0.7)<1e-8 and not entities[bandage])

local bread=select_product("bread")
failed_path="mods/noita_hideout/files/effect_bread.xml"
assert(not NHProducts.use(player,bread) and entities[bread])
failed_path=nil
health.hp,health.max_hp=1,4
assert(NHProducts.use(player,bread) and not entities[bread])
local regen=EntityGetAllChildren(player,"noita_hideout_effect_bread")[1]
function GetUpdatedEntityID() return regen end
local second=assert(loadfile("mods/noita_hideout/files/bread_regeneration.lua"))
for i=1,3 do second() end
assert(health.hp==1)
second()
assert(math.abs(health.hp-1.04)<1e-8)
assert(NHProducts.use(player,select_product("bread")))
assert(#EntityGetAllChildren(player,"noita_hideout_effect_bread")==1)
assert(entities[regen].VariableStorageComponent.value_int==120)
for i=1,120 do second() end
assert(not entities[regen] and math.abs(health.hp-2.24)<1e-8)

local native=EntityLoad("mods/noita_hideout/files/effect_sugar_cube.xml",0,0)
entities[native].tag="vanilla_haste"
entities[native].GameEffectComponent.frames=60
EntityAddChild(player,native)
assert(NHProducts.use(player,select_product("sugar_cube")))
local speed=EntityGetAllChildren(player,"noita_hideout_effect_sugar_cube")[1]
entities[speed].GameEffectComponent.frames=7
assert(NHProducts.use(player,select_product("sugar_cube")))
assert(#EntityGetAllChildren(player,"noita_hideout_effect_sugar_cube")==1)
assert(entities[speed].GameEffectComponent.frames==7200 and entities[native].GameEffectComponent.frames==60)
health.hp,health.max_hp=1,10
assert(NHProducts.use(player,select_product("herb_flatbread")))
regen=EntityGetAllChildren(player,"noita_hideout_effect_bread")[1]
assert(entities[regen].VariableStorageComponent.value_int==180)
assert(NHProducts.use(player,select_product("bread")) and entities[regen].VariableStorageComponent.value_int==180)
for i=1,4 do second() end
assert(math.abs(health.hp-1.04)<1e-8)
assert(NHProducts.use(player,select_product("spiced_stew")))
assert(math.abs(health.hp-1.84)<1e-8 and entities[regen].VariableStorageComponent.value_int==180)
assert(#EntityGetAllChildren(player,"noita_hideout_effect_bread")==1)
for _,dish in ipairs({{"spice_cake","food_levitation"},{"milk_omelet","food_mana"}}) do
    assert(NHProducts.use(player,select_product(dish[1])))
    local tag="noita_hideout_effect_"..dish[2]
    local buff=EntityGetAllChildren(player,tag)[1]
    entities[buff].GameEffectComponent.frames=5
    assert(NHProducts.use(player,select_product(dish[1])))
    assert(#EntityGetAllChildren(player,tag)==1 and entities[buff].GameEffectComponent.frames==7200)
end
print("Workshop products: physical items, healing, grenade shots, timed food effects and refresh passed.")
