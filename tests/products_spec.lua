local medpath="mods/noita_hideout/files/items/medkit.xml"
local shotpath="data/entities/projectiles/deck/grenade_small.xml"
local adapters,entities={},{}
local player,selected,new_id=1,nil,10
local mouse_x,mouse_y,pad,inventory_open=100,20,false,false
local last_shot,failed_path,omit_component
local controls={mAimingVectorNormalized={0,-1}}
local right_mouse=false
function InputIsMouseButtonDown(button) return button==2 and right_mouse end
local health={hp=1,max_hp=1}
entities[player]={x=10,y=20,ControlsComponent=controls,DamageModelComponent=health,GenomeDataComponent={herd_id=7}}
NHNative={held=function() return selected end}
NHTransfers={registerItem=function(kind,match,adapter) adapters[kind]={match=match,adapter=adapter} end}
function EntityLoad(path,x,y)
    if path==failed_path then return 0 end
    local e={path=path,x=x,y=y}
    local kind=path:match("^mods/noita_hideout/files/items/(%w[%w_]*)%.xml$")
    if kind then
        e.tag="noita_hideout_"..kind
        e.ItemComponent={uses_remaining=path==medpath and 3 or kind=="bandage" and 1 or -1}
    elseif path=="mods/noita_hideout/files/effect_bread.xml" then
        e.tag="noita_hideout_effect_bread"
        e.VariableStorageComponent={value_int=120}
    elseif path=="mods/noita_hideout/files/effect_sugar_cube.xml"
        or path=="mods/noita_hideout/files/effect_food_mana.xml" or path=="mods/noita_hideout/files/effect_food_levitation.xml" then
        e.tag="noita_hideout_effect_"..path:match("effect_(.+)%.xml")
        e.GameEffectComponent={frames=7200}
    elseif path==shotpath or path:match("^mods/noita_hideout/files/projectiles/[%w_]+%.xml$") then
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
dofile("mods/noita_hideout/files/store.lua")
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

for _,test in ipairs({{kind="tactical_medkit",charges=9,fraction=0.15},
        {kind="advanced_medkit",charges=12,fraction=0.25}}) do
    local adapter=adapters[test.kind].adapter
    local fresh=NHMedkits.item(test.kind)
    local pack=assert(adapter.restore(fresh,0,0))
    selected=pack
    assert(adapters[test.kind].match(pack) and adapter.capture(pack).remaining==test.charges)
    health.hp,health.max_hp=40,40 -- 1000 displayed HP
    assert(not NHProducts.use(player,pack) and adapter.capture(pack).remaining==test.charges)
    health.hp=0
    assert(not NHProducts.use(player,pack) and adapter.capture(pack).remaining==test.charges)
    health.hp=2
    assert(NHProducts.use(player,pack) and math.abs(health.hp-(2+40*test.fraction))<1e-8)
    local worn=adapter.capture(pack)
    assert(worn.kind==test.kind and worn.remaining==test.charges-1)
    EntityKill(pack)
    pack=assert(adapter.restore(worn,0,0))
    selected=pack
    health.hp,health.max_hp=1,4 -- maximum HP can change between uses of the same item
    assert(NHProducts.use(player,pack) and math.abs(health.hp-(1+4*test.fraction))<1e-8)
    for uses=test.charges-2,1,-1 do
        assert(adapter.capture(pack).remaining==uses)
        health.hp=3.99
        assert(NHProducts.use(player,pack) and health.hp==4)
    end
    assert(not entities[pack])
    for _,bad in ipairs({0,test.charges+1,0.5,"1",false}) do
        assert(not adapter.restore({kind=test.kind,remaining=bad},0,0))
    end
    assert(not adapter.restore({kind=test.kind},0,0))
end

local explosive=adapters.grenade.adapter
local grenade=assert(explosive.restore({kind="grenade"},0,0))
assert(adapters.grenade.match(grenade) and not adapters.medkit.match(grenade))
record=assert(explosive.capture(grenade))
assert(record.kind=="grenade")
EntityKill(grenade)
grenade=assert(explosive.restore(record,1,2))
selected=grenade
pad=true
right_mouse=true
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
right_mouse=false
assert(NHProducts.use(player,grenade))
assert(last_shot.x==10 and last_shot.y==12 and last_shot.target_x==10 and last_shot.target_y==-168)

for _,kind in ipairs(NHThrowables.order) do
    local def=NHThrowables.types[kind]
    local handler=adapters[kind]
    local stack=assert(handler.adapter.restore(def.bundle,10,20))
    selected=stack
    assert(handler.match(stack) and handler.adapter.capture(stack).count==8)
    for _,bad in ipairs({0,9,-1,1.5,"8"}) do assert(not handler.adapter.restore({kind=kind,count=bad},0,0)) end
    for _,slotValue in ipairs({-1,false}) do
        entities[stack].ItemComponent.uses_remaining=slotValue or nil
        if kind=="grenade" then assert(handler.adapter.capture(stack).count==1)
        else assert(not handler.adapter.capture(stack)) end
    end
    entities[stack].ItemComponent.uses_remaining=8
    local last_id=last_shot.id
    failed_path=def.projectile
    assert(not NHProducts.use(player,stack) and handler.adapter.capture(stack).count==8 and last_shot.id==last_id)
    failed_path=nil
    for remaining=8,1,-1 do
        assert(handler.adapter.capture(stack).count==remaining and NHProducts.use(player,stack))
        local shot=entities[last_shot.id]
        assert(shot.path==def.projectile and shot.ProjectileComponent.mWhoShot==player and shot.ProjectileComponent.mShooterHerdId==7)
        assert(last_shot.id~=last_id and shot.VelocityComponent.mVelocity[1]==0 and shot.VelocityComponent.mVelocity[2]==-def.speed)
        last_id=last_shot.id
        if remaining==5 then
            local partial=handler.adapter.capture(stack)
            assert(partial.count==4)
            EntityKill(stack)
            stack=assert(handler.adapter.restore(partial,0,0))
            selected=stack
        end
    end
    assert(not entities[stack] and not selected)
end
print("Throwable stacks: six matching projectiles, legacy counts, failed launches, partial restores and exact depletion passed.")

local function select_product(kind)
    local a=adapters[kind].adapter
    selected=assert(a.restore({kind=kind},0,0))
    assert(adapters[kind].match(selected) and a.capture(selected).kind==kind)
    return selected
end
local bandage=select_product("bandage")
local rolls=adapters.bandage.adapter
assert(rolls.capture(bandage).count==1)
entities[bandage].ItemComponent.uses_remaining=-1
assert(rolls.capture(bandage).count==1,"an old physical bandage represents one roll")
health.hp=health.max_hp
assert(not NHProducts.use(player,bandage) and entities[bandage])
health.hp=0.5
assert(NHProducts.use(player,bandage) and math.abs(health.hp-0.7)<1e-8 and not entities[bandage])

local bundle=assert(rolls.restore({kind="bandage",count=8},1,2))
selected=bundle
health.hp=health.max_hp
assert(not NHProducts.use(player,bundle) and rolls.capture(bundle).count==8)
health.hp,health.max_hp=1,10
assert(NHProducts.use(player,bundle) and math.abs(health.hp-1.2)<1e-8)
local partial=assert(rolls.capture(bundle))
assert(partial.count==7 and entities[bundle].ItemComponent.uses_remaining==7)
EntityKill(bundle)
bundle=assert(rolls.restore(partial,3,4))
selected=bundle
for n=7,1,-1 do
    assert(rolls.capture(bundle).count==n and NHProducts.use(player,bundle))
end
assert(not entities[bundle] and math.abs(health.hp-2.6)<1e-8)
for _,bad in ipairs({0,-1,1.5,2147483648,"8",false}) do
    assert(not rolls.restore({count=bad},0,0))
end

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

local function testInventoryProducts()
    inventory_open=true
    local payments=0
    local function reject()
        payments=payments+1
        return false
    end
    local prior=last_shot.id
    local aim={x=0.6,y=0.8}
    assert(not NHProducts.apply(player,"shock_grenade",reject,aim))
    assert(payments==1 and last_shot.id==prior and not entities[new_id])
    health.hp=2
    assert(not NHProducts.apply(player,"advanced_medkit",reject) and health.hp==2 and payments==2)

    -- A failed debit cannot extend an existing effect or apply the stew's direct heal.
    local timer=entities[regen].VariableStorageComponent
    timer.value_int=9
    assert(not NHProducts.apply(player,"spiced_stew",reject))
    assert(payments==3 and timer.value_int==9 and health.hp==2)
    EntityKill(regen)
    local previousId=new_id
    assert(not NHProducts.apply(player,"spiced_stew",reject))
    assert(payments==4 and new_id==previousId+1 and not entities[new_id] and health.hp==2)
    assert(#EntityGetAllChildren(player,"noita_hideout_effect_bread")==0)

    function EntityGetRootEntity(id) return entities[id].owner or id end
    local frozen=adapters.frost_grenade.adapter
    local stack=assert(frozen.restore({kind="frost_grenade",count=2},0,0))
    assert(not NHProducts.use(player,stack,true,aim) and frozen.capture(stack).count==2)
    EntityAddChild(player,stack)
    selected=nil
    right_mouse=true
    mouse_x,mouse_y=-90,20 -- The inventory cursor is aimed left; the saved world aim is down-right.
    assert(NHProducts.use(player,stack,true,aim) and frozen.capture(stack).count==1)
    local v=entities[last_shot.id].VelocityComponent.mVelocity
    assert(math.abs(v[1]-108)<1e-8 and math.abs(v[2]-144)<1e-8 and not selected)
end
testInventoryProducts()
print("Inventory products: rejected charges have no effect and unheld stacks use the saved world aim.")
