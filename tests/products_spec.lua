local medpath="mods/noita_hideout/files/items/medkit.xml"
local shotpath="data/entities/projectiles/deck/grenade_small.xml"
local adapters,entities={},{}
local player,selected,new_id=1,nil,10
local mouse_x,mouse_y,pad,inventory_open=100,20,false,false
local last_shot,failed_path,omit_component
local shiftDuringRegistration=false
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
        e.supportWeapon=NHGuns and NHGuns.types[kind] and NHGuns.types[kind].muzzle~=nil
        e.loadedGun=NHGuns and NHGuns.types[kind]~=nil
        e.pheromone=kind=="flare_gun"
        e.tag="noita_hideout_"..kind
        e.ItemComponent={uses_remaining=path==medpath and 3 or kind=="bandage" and 1 or -1}
    elseif path:match("/meal_%w+.xml$") then
        local key=path:match("/meal_(%w+).xml$")
        e.tag="noita_hideout_meal_"..key
        e.VariableStorageComponent={name=key,value_int=0,value_float=0}
    elseif path=="mods/noita_hideout/files/effect_bread.xml" then
        e.tag="noita_hideout_effect_bread"
        e.VariableStorageComponent={value_int=120}
    elseif path=="mods/noita_hideout/files/effect_sugar_cube.xml"
        or path=="mods/noita_hideout/files/effect_food_mana.xml" or path=="mods/noita_hideout/files/effect_food_levitation.xml" then
        e.tag="noita_hideout_effect_"..path:match("effect_(.+)%.xml")
        e.GameEffectComponent={frames=7200}
    elseif path:find("/muzzle_flashes/",1,true) then
        e.flash=true
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
function EntityHasTag(id,tag)
    local e=entities[id]
    return e.tag==tag or (tag=="nh_support_weapon" and e.supportWeapon) or (tag=="nh_loaded_gun" and e.loadedGun)
        or (tag=="nh_pheromone_launcher" and e.pheromone)
end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
function RaytraceSurfaces() return false end
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
function EntityAddComponent2(id,kind,fields)
    entities[id][kind]=fields
    return fields
end
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
    if shiftDuringRegistration then entities[entity].x,entities[entity].y=18,20 end
    -- The game returns no value.
end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/products.lua")
NHSurgery=dofile("mods/noita_hideout/files/surgery.lua")
local frame=0
function GameGetFrameNum() return frame end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetRootEntity(id) return selected==id and player or entities[id].owner or id end
local function finishTreatment()
    local cast=assert(NHSurgery.view())
    frame=frame+cast.total-1
    local before=health.hp
    assert(not NHSurgery.update(player) and health.hp==before)
    frame=frame+1
    return NHSurgery.update(player)
end
local function treat(id)
    return NHProducts.use(player,id) and finishTreatment()=="completed"
end
local medical=adapters.medkit.adapter
selected=assert(medical.restore({kind="medkit"},0,0))
local kit=selected
assert(adapters.medkit.match(kit))
assert(not NHProducts.use(player,kit) and medical.capture(kit).remaining==8)
health.hp=0.2
inventory_open=true
assert(not NHProducts.use(player,kit))
inventory_open=false
selected=nil
assert(not NHProducts.use(player,kit))
selected=kit
assert(treat(kit) and math.abs(health.hp-0.35)<0.00001)
local record=assert(medical.capture(kit))
assert(record.remaining==7 and record.kind=="medkit")
record.remaining=2 -- also exercise the last two uses
EntityKill(kit)
kit=assert(medical.restore(record,3,4))
selected=kit
health.hp=0.9
assert(treat(kit) and health.hp==1)
assert(not NHProducts.use(player,kit) and medical.capture(kit).remaining==1)
health.hp=0.95
assert(treat(kit) and health.hp==1 and not entities[kit])
for _,bad in ipairs({0,9,1.5,"2"}) do
    assert(not medical.restore({kind="medkit",remaining=bad},0,0))
end
omit_component="ItemComponent"
assert(not medical.restore({kind="medkit",remaining=3},0,0) and not entities[new_id])
omit_component=nil

for _,test in ipairs({{kind="tactical_medkit",charges=6,fraction=0.25},
        {kind="advanced_medkit",charges=6,fraction=0.40}}) do
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
    assert(treat(pack) and math.abs(health.hp-(2+40*test.fraction))<1e-8)
    local worn=adapter.capture(pack)
    assert(worn.kind==test.kind and worn.remaining==test.charges-1)
    EntityKill(pack)
    pack=assert(adapter.restore(worn,0,0))
    selected=pack
    health.hp,health.max_hp=1,4 -- maximum HP can change between uses of the same item
    assert(treat(pack) and math.abs(health.hp-(1+4*test.fraction))<1e-8)
    for uses=test.charges-2,1,-1 do
        assert(adapter.capture(pack).remaining==uses)
        health.hp=3.99
        assert(treat(pack) and health.hp==4)
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
assert(treat(bandage) and math.abs(health.hp-0.7)<1e-8 and not entities[bandage])

local bundle=assert(rolls.restore({kind="bandage",count=1},1,2))
selected=bundle
health.hp=health.max_hp
assert(not NHProducts.use(player,bundle) and rolls.capture(bundle).remaining==8)
health.hp,health.max_hp=1,10
assert(NHProducts.use(player,bundle))
selected=nil
assert(NHSurgery.update(player)=="interrupted" and rolls.capture(bundle).remaining==8 and health.hp==1)
selected=bundle
assert(treat(bundle) and math.abs(health.hp-1.5)<1e-8)
local partial=assert(rolls.capture(bundle))
assert(partial.count==1 and partial.remaining==7 and entities[bundle].ItemComponent.uses_remaining==7)
EntityKill(bundle)
bundle=assert(rolls.restore(partial,3,4))
selected=bundle
for n=7,1,-1 do
    assert(rolls.capture(bundle).remaining==n and treat(bundle))
end
assert(not entities[bundle] and math.abs(health.hp-5)<1e-8)
for _,bad in ipairs({0,-1,1.5,2147483648,"8",false}) do
    assert(not rolls.restore({kind="bandage",count=bad},0,0))
end

local function buff(key)
    return (EntityGetAllChildren(player,"noita_hideout_meal_"..key) or {})[1]
end
local updated
function GetUpdatedEntityID() return updated end
local second=assert(loadfile("mods/noita_hideout/files/meal_tick.lua"))
local bread=select_product("bread")
failed_path="mods/noita_hideout/files/meal_grain.xml"
assert(not NHProducts.use(player,bread) and entities[bread])
failed_path=nil
health.hp,health.max_hp=1,10
assert(NHProducts.use(player,bread) and adapters.bread.adapter.capture(bread).remaining==1)
updated=buff("grain")
for i=1,4 do second() end
assert(math.abs(health.hp-1.2)<1e-8)
assert(NHProducts.use(player,bread) and not entities[bread])
for i=1,120 do second() end
assert(not buff("grain") and math.abs(health.hp-7.2)<1e-8)
local function eat(id) assert(NHProducts.use(player,select_product(id))) end
eat("sandwich")
assert(buff("grain") and buff("egg") and buff("meat") and math.abs(health.hp-7.6)<1e-8)
updated=player
dofile("mods/noita_hideout/files/meal_damage.lua")
local damage,crit=damage_about_to_be_received(100,0,0,0,7)
assert(math.abs(damage-76)<1e-8 and crit==7)
updated=buff("meat")
for i=1,25 do second() end
updated=player
assert(not buff("meat") and damage_about_to_be_received(100,0,0,0,0)==95)
eat("sugar_cube")
updated=buff("sugar")
for i=1,4 do second() end
assert(not buff("sugar") and buff("speed") and math.abs(health.hp-8.0)<1e-8)
eat("spiced_stew")
entities[2]={tag="wand",AbilityComponent={mana=5,mana_max=50}}
entities[player].Inventory2Component={mActiveItem=2}
updated=buff("spice")
second()
assert(entities[2].AbilityComponent.mana==25)
local stack=adapters.cake.adapter.restore({kind="cake",count=3,remaining=1},0,0)
selected=stack
assert(NHProducts.use(player,stack))
local stored=adapters.cake.adapter.capture(stack)
assert(stored.count==2 and stored.remaining==4)
print("Food effects, duration, resistance, mana and packed bites passed.")

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
    assert(NHProducts.apply(player,"advanced_medkit",reject) and finishTreatment()=="interrupted" and health.hp==2 and payments==2)

    local timer=entities[buff("spice")].VariableStorageComponent
    timer.value_int=9
    EntityKill(buff("meat"))
    assert(not NHProducts.apply(player,"spiced_stew",reject))
    assert(payments==3 and timer.value_int==9 and health.hp==2 and not buff("meat"))

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

do
    function EntityGetIsAlive(id) return entities[id]~=nil end
    local adapter=adapters.remote_terminal.adapter
    local fresh=NHEquipment.remoteItem()
    assert(adapter.warehouseCategory=="equipment" and fresh.remaining==20)
    local terminal=assert(adapter.restore(fresh,2,5))
    assert(adapters.remote_terminal.match(terminal) and not NHProducts.spendRemoteCharge(player,terminal))
    EntityAddChild(player,terminal)
    assert(NHProducts.spendRemoteCharge(player,terminal))
    local worn=assert(adapter.capture(terminal))
    assert(worn.remaining==19 and worn.kind==fresh.kind and worn.icon==fresh.icon and worn.name==fresh.name)
    EntityKill(terminal)
    terminal=assert(adapter.restore(worn,10,-5))
    assert(adapter.capture(terminal).remaining==19)
    EntityAddChild(player,terminal)
    selected=terminal
    for uses=19,1,-1 do
        assert(adapter.capture(terminal).remaining==uses and NHProducts.spendRemoteCharge(player,terminal))
    end
    assert(not NHProducts.spendRemoteCharge(player,terminal))
    for _,invalid in ipairs({-1,0,21,0.5,"2"}) do
        assert(not adapter.restore({kind=fresh.kind,remaining=invalid},0,0))
    end
    for kind,maximum in pairs({data_link=20,data_link_2=40,data_link_3=80}) do
        local link=adapters[kind].adapter
        local id=assert(link.restore({kind=kind,remaining=maximum},0,0))
        EntityAddChild(player,id)
        if kind=="data_link" then entities[id].ItemComponent.uses_remaining=-1 end
        assert(link.capture(id).remaining==maximum and NHProducts.spendRemoteCharge(player,id))
        local worn=assert(link.capture(id))
        local restored=assert(link.restore(worn,0,0))
        assert(worn.kind==kind and link.capture(restored).remaining==maximum-1)
        assert(not link.restore({kind=kind,remaining=maximum+1},0,0))
    end
end
local chargeParticles=0
local blockedMuzzle=false
local arm=8
entities[arm]={x=14,y=18,owner=player,tag="player_arm_r"}
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityApplyTransform(id,x,y,angle,sx,sy)
    local e=entities[id]
    assert(id==selected or e.ProjectileComponent)
    e.x,e.y,e.angle,e.sx,e.sy=x,y,angle,sx,sy
end
function EntityGetHotspot(id,tag,transformed)
    assert(transformed)
    if id==arm then assert(tag=="hand"); return EntityGetTransform(arm) end
    assert(id==selected and tag=="shoot_pos")
    return 18,20 -- A stale weapon hotspot must not determine the shot origin.
end
function RaytraceSurfaces() return blockedMuzzle,19,20 end
function GameCreateCosmeticParticle(material)
    assert(material=="spark_blue")
    chargeParticles=chargeParticles+1
end
for _,kind in ipairs({"derringer","flare_gun"}) do
    local gun=adapters[kind].adapter
    selected=assert(gun.restore({kind=kind,remaining=4,count=2},0,0))
    inventory_open=true
    assert(not NHProducts.fireHeld(player))
    inventory_open=false
    for n=8,1,-1 do
        local record=gun.capture(selected)
        assert(NHGuns.rounds(record)==n and record.remaining==(n-1)%4+1)
        if n==7 then
            EntityKill(selected)
            selected=assert(gun.restore(record,0,0))
            assert(gun.capture(selected).remaining==3)
        end
        assert(NHProducts.fireHeld(player))
    end
    assert(not selected and not gun.restore({kind=kind,remaining=5},0,0))
end
mouse_x,mouse_y,pad=114,18,false
for _,kind in ipairs({"magic_tube","fire_tube","frost_tube","shock_tube"}) do
    local adapter=adapters[kind].adapter
    selected=assert(adapter.restore({kind=kind,count=2,remaining=6},0,0))
    assert(not NHProducts.use(player,selected)) -- opening a stack with the old throw binding cannot fire it
    for n=12,1,-1 do
        local saved=assert(adapter.capture(selected))
        assert(NHGuns.rounds(saved)==n and saved.remaining==(n-1)%6+1)
        if n==11 then
            EntityKill(selected)
            selected=assert(adapter.restore(saved,0,0))
        end
        assert(NHProducts.fireHeld(player))
        assert(entities[last_shot.id].path==NHGuns.types[kind].projectile)
        assert(last_shot.x==24 and last_shot.y==13.5,"launcher barrel and firing origin agree")
    end
    assert(not selected)
end

for kind,capacity in pairs({heavy_mg=320,auto_grenade=36,missile_launcher=12,railgun=20,heavy_plasma=24,bfg=4}) do
    assert(NHGuns.types[kind].capacity==capacity)
    local adapter=adapters[kind].adapter
    selected=assert(adapter.restore({kind=kind,count=1,remaining=capacity},0,0))
    entities[selected].supportWeapon=true
    mouse_x,mouse_y,pad=114,18,false
    entities[arm].x,entities[arm].y=14,18
    local function trigger(edge,frame)
        if NHGuns.trigger(selected,edge,frame) then return NHProducts.fireHeld(player) end
    end
    local interval=NHGuns.types[kind].interval
    if interval then
        assert(trigger(true,1) and not trigger(false,interval) and trigger(false,interval+1))
        assert(adapter.capture(selected).remaining==capacity-2)
    elseif kind=="railgun" then
        assert(not trigger(true,1) and not trigger(false,36))
        assert(chargeParticles>0)
        NHGuns.trigger(nil,false,37)
        assert(not trigger(false,38) and adapter.capture(selected).remaining==capacity)
        assert(not trigger(true,40) and trigger(false,76) and not trigger(false,115))
    else
        assert(trigger(true,1) and not trigger(false,2))
    end
    assert(entities[new_id].flash and entities[new_id].path==NHGuns.types[kind].muzzle)
    assert(entities[new_id].x==last_shot.x and entities[new_id].y==last_shot.y)
    local ox,oy=unpack(entities[selected].HotspotComponent.offset)
    assert(last_shot.x==14+ox and last_shot.y==18+oy)
    assert(entities[new_id].owner==selected and entities[new_id].InheritTransformComponent.parent_hotspot_tag=="shoot_pos")
    blockedMuzzle=true
    assert(NHProducts.fireHeld(player) and last_shot.x<20 and last_shot.y<22)
    blockedMuzzle=false
    local saved=adapter.capture(selected)
    assert(saved.remaining<capacity and saved.remaining>0)
    EntityKill(selected)
    selected=assert(adapter.restore(saved,0,0))
    assert(adapter.capture(selected).remaining==saved.remaining)
    for _=1,saved.remaining do assert(NHProducts.fireHeld(player)) end
    assert(not selected)
    shiftDuringRegistration=true
    for i,v in ipairs({{-1,0},{0,-1},{0,1},{0.6,-0.8}}) do
        local hx,hy=20+i,15-i
        entities[arm].x,entities[arm].y=hx,hy
        mouse_x,mouse_y=hx+100*v[1],hy+100*v[2]
        selected=assert(adapter.restore({kind=kind,count=1,remaining=1},0,0))
        assert(NHProducts.fireHeld(player) and not selected)
        local flip=v[1]<0 and -1 or 1
        local expectedX,expectedY=hx+ox*v[1]-oy*flip*v[2],hy+ox*v[2]+oy*flip*v[1]
        local px,py=EntityGetTransform(last_shot.id)
        assert(math.abs(px-expectedX)<0.0001 and math.abs(py-expectedY)<0.0001)
        assert(px==last_shot.x and py==last_shot.y and entities[new_id].x==px and entities[new_id].y==py)
    end
    shiftDuringRegistration=false
end
