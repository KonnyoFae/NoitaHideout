-- Run the actual entity update at each relationship tier. The profile clock has
-- its own suite; here the value returned to each pet tick is controlled.
function dofile_once(path) dofile(path) end
dofile("mods/noita_hideout/files/companions/behavior.lua")
local points,earned=0,0
local entities,nextId,gifts={},0,0
local function spawn(tags)
    nextId=nextId+1
    entities[nextId]={x=0,y=0,scaleX=1,scaleY=1,parent=0,tags=tags or {},parts={}}
    return nextId
end
local function part(id,kind,data,tag)
    entities[id].parts[kind..(tag or "")]=data
    return data
end
function EntityAddComponent2(id,kind,c) return part(id,kind,c,c._tags) end
function EntityRemoveComponent(id,c)
    for key,v in pairs(entities[id].parts) do if v==c then entities[id].parts[key]=nil end end
end
function ComponentObjectGetValue2(c,_,key) return c[key] end
function ComponentObjectSetValue2(c,_,key,v) c[key]=v end
function GameGetFrameNum() return earned end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetParent(id) return entities[id].parent end
function EntityAddChild(parent,id) entities[id].parent=parent end
function EntityRemoveFromParent(id) entities[id].parent=0 end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityRemoveTag(id,tag) entities[id].tags[tag]=nil end
function EntityCreateNew() return spawn() end
function EntityHasTag(id,tag) return entities[id].tags[tag] end
function EntityGetAllChildren(id,tag)
    local list={}
    for child,e in pairs(entities) do if e.parent==id and e.tags[tag] then list[#list+1]=child end end
    return list
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return entities[id].parts[kind..(tag or "")] end
function ComponentGetValue2(c,key) return c[key] end
function ComponentSetValue2(c,key,value) c[key]=value end
function EntityGetTransform(id)
    local e=entities[id]
    return e.x,e.y,0,e.scaleX,e.scaleY
end
function EntitySetTransform(id,x,y,rotation,scaleX,scaleY)
    local e=entities[id]
    e.x,e.y,e.scaleX,e.scaleY=x,y,scaleX or 1,scaleY or 1
end
function EntityGetInRadiusWithTag() return {} end
function EntityKill(id) entities[id]=nil end
function EntityLoad(path,x,y)
    local id=spawn()
    entities[id].x,entities[id].y=x,y
    if path:match("effect_") or path:match("/shield%.xml$") then
        part(id,"GameEffectComponent",{frames=0})
        if path:match("/shield%.xml$") then part(id,"EnergyShieldComponent",{recharge_speed=0.22}) end
    else gifts=gifts+1 end
    return id
end
function GamePrint() end
function GameTextGetTranslatedOrNot(key) return key end
local active
local actualFollow=NHAffinity.follow
NHAffinity.follow=function(id,frames)
    assert(id==active and frames==6)
    earned=earned+frames
    return points
end
local player=spawn({player_unit=true})
local health=part(player,"DamageModelComponent",{hp=1,max_hp=5,melee=0.8,ice=0.5,poison=0.75,curse=2,slice=1,air_needed=true,
    materials_that_damage="acid,lava,poison,rock_static_cursed,blood_cold",
    materials_how_much_damage="0.005,0.003,0.001,0.005,0.0009"})
function EntitySetDamageFromMaterial(who,material,damage)
    assert(who==player)
    local parts={}
    local nextAmount=health.materials_how_much_damage:gmatch("[^,]+")
    for name in health.materials_that_damage:gmatch("[^,]+") do
        local current=nextAmount()
        parts[#parts+1]=name==material and tostring(damage) or current
    end
    health.materials_how_much_damage=table.concat(parts,",")
end
local flight=part(player,"CharacterDataComponent",{mFlyingTimeLeft=0,fly_time_max=4})
local platform=part(player,"CharacterPlatformingComponent",{run_velocity=150,fly_velocity_x=60,velocity_min_x=-200,velocity_max_x=200,
    fly_speed_max_up=100,velocity_min_y=-200})
local wand=spawn({wand=true})
local magic=part(wand,"AbilityComponent",{mana=0,mana_max=80})
local gun=spawn({wand=true,nh_firearm=true})
local ammo=part(gun,"AbilityComponent",{mana=0,mana_max=36})
function GameGetAllInventoryItems() return {wand,gun} end
local outsider=spawn({energy_shield=true})
EntityAddChild(player,outsider)
local native=part(outsider,"EnergyShieldComponent",{recharge_speed=0.22})
local function companion(id)
    active=id
    local pet=spawn({noita_hideout_companion=true})
    EntityAddChild(player,pet)
    local clock=part(pet,"VariableStorageComponent",{value_int=0,value_string=id},"nh_companion_clock")
    return pet,clock
end
local function expire(pet,clock)
    local before=earned
    clock.value_int=15*60*60
    NHCompanions.update(pet)
    assert(not EntityGetIsAlive(pet) and #EntityGetAllChildren(player,"noita_hideout_companion_aura")==0)
    assert(earned==before and EntityGetIsAlive(outsider) and native.recharge_speed==0.22)
end
-- Follow from the summon scale for a whole horizontal bob (2*pi*65 game frames).
do
    local function sizeAndFacing(pet,x,y)
        local _,_,_,scaleX,scaleY=EntityGetTransform(pet)
        assert(scaleX==x and scaleY==y,
            ("%s expected scale (%g,%g), got (%g,%g)"):format(active,x,y,scaleX,scaleY))
    end
    for _,id in ipairs(NHCompanions.order) do
        local pet,clock=companion(id)
        EntitySetTransform(pet,0,0,0,0.5,0.5)
        local function movePlayer(offset,expected)
            entities[player].x=entities[pet].x+offset
            NHCompanions.update(pet)
            sizeAndFacing(pet,expected,0.5)
        end
        movePlayer(-16,0.5)
        movePlayer(-17,-0.5)
        movePlayer(16,-0.5)
        movePlayer(17,0.5)
        movePlayer(-17,-0.5)
        entities[player].x=entities[pet].x
        for _=1,70 do
            NHCompanions.update(pet)
            sizeAndFacing(pet,-0.5,0.5)
        end
        -- Continue an already active summon past the old three-minute limit.
        clock.value_int=3*60*60
        NHCompanions.update(pet)
        assert(EntityGetIsAlive(pet) and clock.value_int==3*60*60+6)
        clock.value_int=15*60*60-6
        NHCompanions.update(pet)
        assert(EntityGetIsAlive(pet) and clock.value_int==15*60*60)
        expire(pet,clock)
        local queued=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_companion_gift")
        if queued then EntityRemoveComponent(player,queued) end
    end
end
local function near(a,b) assert(math.abs(a-b)<0.00001,("expected %g, got %g"):format(b,a)) end
local ally,enemy,charmed=spawn(),spawn(),spawn()
for _,id in ipairs({ally,enemy,charmed}) do part(id,"GenomeDataComponent",{}) end
local hits={}
function EntityGetInRadiusWithTag(_,_,radius,tag)
    if tag=="mortal" then assert(radius==NHCompanions.species[active].radius); return {player,ally,enemy,charmed} end
    return {}
end
function EntityGetHerdRelation(_,id) return id==ally and 100 or 0 end
function GameGetGameEffectCount(id) return id==charmed and 1 or 0 end
function EntityInflictDamage(id,amount,kind,_,_,_,_,owner)
    assert(id==enemy and owner==player and kind=="DAMAGE_MELEE")
    hits[#hits+1]=amount
end
local immunities={
    cat={typed="curse",material=4},dog={typed="ice",effect="PROTECTION_FREEZE",material=5},
    griffin={effect="PROTECTION_ELECTRICITY"},bee={typed="poison",effect="PROTECTION_RADIOACTIVITY",material=3},
    dragon={effect="PROTECTION_FIRE"},dryad={typed="slice"},flower_fairy={material=1},
    slime={},minotaur={effect="PROTECTION_POLYMORPH"},
}
local originalMaterials=health.materials_how_much_damage
for rank,threshold in ipairs({0,100,400,1000}) do
    points=threshold
    local bonus=NHCompanions.bonuses[rank-1]
    for _,id in ipairs(NHCompanions.order) do
        local spec=NHCompanions.species[id]
        local pet,clock=companion(id)
        flight.mFlyingTimeLeft,health.hp,magic.mana=0,1,0
        local before=#hits
        for _=1,10 do NHCompanions.update(pet) end
        local expected=immunities[id]
        local tag=id=="minotaur" and "nh_shield_poly" or "nh_companion_immunity"
        local aura=assert(EntityGetAllChildren(player,tag)[1])
        if expected.effect then assert(entities[aura].parts.GameEffectComponent.effect==expected.effect) end
        assert((not health.air_needed)==(id=="slime") and (EntityHasTag(player,"polymorphable_NOT")==true)==(id=="minotaur"))
        for kind,original in pairs({ice=0.5,poison=0.75,slice=1,curse=2}) do
            near(health[kind],kind==expected.typed and 0 or original)
        end
        local amounts=health.materials_how_much_damage:gmatch("[^,]+")
        for j,v in ipairs({0.005,0.003,0.001,0.005,0.0009}) do near(tonumber(amounts()),j==expected.material and 0 or v) end
        if spec.role=="support" then
            near(health.hp,1+5*bonus.heal/100)
            near(platform.run_velocity,150*(1+bonus.speed/100))
            assert(magic.mana==bonus.mana and ammo.mana==0 and #EntityGetAllChildren(player,"nh_companion_mana")==1)
            health.hp,magic.mana=4.999,79
            for _=1,10 do NHCompanions.update(pet) end
            assert(health.hp==5 and magic.mana==80)
        elseif spec.role=="melee" then
            near(health.melee,0.8*(1-bonus.meleeResist/100))
            assert(#hits==before+2 and hits[#hits]==bonus.fieldDamage/25 and #EntityGetAllChildren(player,"nh_companion_knockback")==1)
        else
            near(platform.fly_speed_max_up,100+spec.lift+bonus.lift)
            near(flight.mFlyingTimeLeft,4*(spec.fuel+bonus.fuel)/100)
            flight.mFlyingTimeLeft=3.999
            for _=1,10 do NHCompanions.update(pet) end
            assert(flight.mFlyingTimeLeft==4)
        end
        local shield=EntityGetAllChildren(player,"nh_companion_shield")[1]
        if spec.shield and rank>1 then near(entities[shield].parts.EnergyShieldComponent.recharge_speed,bonus.shieldRecharge)
        else assert(not shield) end
        if spec.effect then assert(#EntityGetAllChildren(player,"nh_companion_"..spec.effect)==1) end
        -- Jump across every due time, including the final regular gift at 15 min.
        local period=NHCompanions.giftMinutes(spec)*3600
        for age=period,15*3600,period do
            clock.value_int=age-12
            NHCompanions.update(pet)
            assert(not EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_companion_gift"))
            NHCompanions.update(pet)
            local gift=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_companion_gift")
            assert(gift.value_string==id and gift.value_float==bonus.giftLevel)
            EntityRemoveComponent(player,gift)
        end
        expire(pet,clock)
        assert(not EntityGetIsAlive(aura) and not EntityHasTag(player,"polymorphable_NOT") and health.air_needed)
        assert(health.materials_how_much_damage==originalMaterials)
        assert(health.slice==1 and health.ice==0.5 and health.poison==0.75 and health.curse==2)
        near(platform.run_velocity,150); near(platform.fly_speed_max_up,100); near(health.melee,0.8)
    end
end
NHAffinity.follow=actualFollow
local world={noita_hideout_run_v1="1/1"}
function GlobalsGetValue(key,default) return world[key] or default end
function GlobalsSetValue(key,value) world[key]=value end
local state={profile=1,runSerial=1}
NHAffinity.bind(state)
local pet,clock=companion("flower_fairy")
for _=1,599 do NHCompanions.update(pet) end
assert(NHAffinity.points(state,"flower_fairy")==99)
health.hp=1
NHCompanions.update(pet)
near(health.hp,1.05); near(platform.run_velocity,172.5)
platform.run_velocity=platform.run_velocity*1.25
expire(pet,clock)
near(platform.run_velocity,187.5)
function ModIsEnabled(id) return id=="quant.ew" end
NHEW.reset()
local remote=companion("cat")
EntityAddTag(player,"ew_client")
NHCompanions.update(remote)
assert(GlobalsGetValue("noita_hideout_affinity_cat","0")=="0")
EntityRemoveTag(player,"ew_client")
NHCompanions.update(remote)
assert(GlobalsGetValue("noita_hideout_affinity_cat","0")=="6")
print("All nine roles, four ranks, timed gifts, ally filtering, regen caps and independent modifiers passed.")
