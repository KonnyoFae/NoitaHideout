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
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetParent(id) return entities[id].parent end
function EntityAddChild(parent,id) entities[id].parent=parent end
function EntityRemoveFromParent(id) entities[id].parent=0 end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
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
local health=part(player,"DamageModelComponent",{hp=1,max_hp=5})
local flight=part(player,"CharacterDataComponent",{mFlyingTimeLeft=0,fly_time_max=4})
local outsider=spawn({energy_shield=true})
EntityAddChild(player,outsider)
local native=part(outsider,"EnergyShieldComponent",{recharge_speed=0.22})
local function companion(id)
    active=id
    local pet=spawn({noita_hideout_companion=true})
    EntityAddChild(player,pet)
    local clock=part(pet,"VariableStorageComponent",{value_int=0,value_string=id},"nh_companion_clock")
    part(pet,"VariableStorageComponent",{value_int=0},"nh_trip")
    part(pet,"VariableStorageComponent",{value_int=0,value_float=0},"nh_position")
    local rewards=part(pet,"VariableStorageComponent",{value_int=4,value_float=0},"nh_gifts")
    return pet,clock,rewards
end
local function expire(pet,clock)
    local before=earned
    clock.value_int=10800
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
        expire(pet,clock)
    end
end
for tier,threshold in ipairs({0,10,40,100}) do
    points=threshold
    local pet,clock
    for _,id in ipairs({"minotaur","dragon"}) do
        pet,clock=companion(id)
        NHCompanions.update(pet)
        local shield=EntityGetAllChildren(player,"nh_companion_shield")[1]
        if tier==1 then assert(not shield)
        else
            assert(shield and entities[shield].parts.EnergyShieldComponent.recharge_speed==({0,0.08,0.15,0.22})[tier])
            assert(entities[shield].parts.GameEffectComponent.frames==70)
        end
        local effect=id=="dragon" and "effect_protection_fire" or "effect_protection_melee"
        assert(#EntityGetAllChildren(player,"nh_companion_"..effect)==1)
        expire(pet,clock)
    end

    for _,id in ipairs({"dryad","flower_fairy"}) do
        pet,clock=companion(id)
        local period=(id=="dryad" and {0,12,9,6} or {5,4,3,2})[tier]
        local ticks=math.max(period,12)*10
        health.hp=1
        for _=1,ticks do NHCompanions.update(pet) end
        local pulses=period>0 and math.floor(ticks/(period*10)) or 0
        assert(math.abs(health.hp-1-0.04*pulses)<0.00001)
        if id=="dryad" then assert(#EntityGetAllChildren(player,"nh_companion_effect_protection_radioactivity")==1) end
        expire(pet,clock)
    end
    for _,id in ipairs({"griffin","bee"}) do
        pet,clock=companion(id)
        flight.mFlyingTimeLeft=0
        for _=1,10 do NHCompanions.update(pet) end
        assert(math.abs(flight.mFlyingTimeLeft-4*({0,0.05,0.10,0.15})[tier])<0.00001)
        local effect=id=="bee" and "effect_movement_faster" or "effect_faster_levitation"
        assert(#EntityGetAllChildren(player,"nh_companion_"..effect)==1)
        flight.mFlyingTimeLeft=3.99
        for _=1,10 do NHCompanions.update(pet) end
        assert(flight.mFlyingTimeLeft==(tier==1 and 3.99 or 4))
        expire(pet,clock)
    end

    local rewards
    pet,clock,rewards=companion("flower_fairy")
    NHCompanions.update(pet)
    local before=gifts
    local ticks=({30,25,20,15})[tier]*10
    for cycle=1,3 do
        rewards.value_int=4 -- first roll is divisible by four
        for tick=1,ticks do
            entities[player].x=entities[player].x+1
            NHCompanions.update(pet)
            local delivered=cycle-(tick<ticks and 1 or 0)
            assert(gifts==before+math.min(delivered,2))
        end
    end
    expire(pet,clock)
end
-- Cross the first threshold while the same flower fairy is still following.
-- Standing together builds affinity but supplies no travel time for gifts.
NHAffinity.follow=actualFollow
local world={noita_hideout_run_v1="1/1"}
function GlobalsGetValue(key,default) return world[key] or default end
function GlobalsSetValue(key,value) world[key]=value end
local state={profile=1,runSerial=1}
NHAffinity.bind(state)
local pet,clock=companion("flower_fairy")
local beforeGifts=gifts
for _=1,599 do NHCompanions.update(pet) end
assert(NHAffinity.points(state,"flower_fairy")==9)
health.hp=1
NHCompanions.update(pet)
assert(NHAffinity.points(state,"flower_fairy")==10 and math.abs(health.hp-1.04)<0.00001)
for _=1,40 do NHCompanions.update(pet) end
assert(math.abs(health.hp-1.08)<0.00001 and gifts==beforeGifts)
expire(pet,clock)
pet=companion("dryad")
for _=1,60 do NHCompanions.update(pet) end
assert(NHAffinity.points(state,"dryad")==1 and NHAffinity.points(state,"flower_fairy")==10)
print("All four affinity tiers scale buffs and travel gift timing, respect caps, and leave independent shields intact.")
