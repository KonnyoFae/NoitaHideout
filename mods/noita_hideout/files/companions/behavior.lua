-- Charged summons follow their owner's transform like the vanilla ghost perks.
-- Runtime state belongs to the entity, so continuing a world resumes its trip.
local root="mods/noita_hideout/files/"
dofile_once(root.."companions.lua")
dofile_once(root.."affinity.lua")
local interval=6

local function fireAtHostile(player,x,y,damage)
    local best,tx,ty=105^2,nil,nil
    for _,target in ipairs(EntityGetInRadiusWithTag(x,y,105,"homing_target") or {}) do
        if target~=player and EntityGetFirstComponentIncludingDisabled(target,"GenomeDataComponent")
            and EntityGetHerdRelation(player,target)<40 and GameGetGameEffectCount(target,"CHARM")==0 then
            local ex,ey=EntityGetFirstHitboxCenter(target)
            local distance=ex and (ex-x)^2+(ey-y)^2
            if distance and distance>=1 and distance<best and not RaytracePlatforms(x,y,ex,ey) then
                best,tx,ty=distance,ex,ey
            end
        end
    end
    if not tx then return end
    local bolt=EntityLoad(root.."companions/bolt.xml",x,y)
    if not bolt or bolt==0 then return end
    local shot=EntityGetFirstComponentIncludingDisabled(bolt,"ProjectileComponent")
    local velocity=EntityGetFirstComponentIncludingDisabled(bolt,"VelocityComponent")
    if not shot or not velocity then EntityKill(bolt); return end
    local distance=math.sqrt(best)
    local vx,vy=(tx-x)*270/distance,(ty-y)*270/distance
    GameShootProjectile(player,x,y,tx,ty,bolt,false)
    ComponentSetValue2(shot,"mWhoShot",player)
    local genome=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
    if genome then ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(genome,"herd_id")) end
    ComponentSetValue2(shot,"damage",damage)
    ComponentSetValue2(velocity,"mVelocity",vx,vy)
end

local function refreshAura(player,tag,path,x,y)
    local aura=(EntityGetAllChildren(player,tag) or {})[1]
    if not aura then
        aura=EntityLoad(path,x,y)
        if not aura or aura==0 then return end
        EntityAddTag(aura,tag)
        EntityAddTag(aura,"noita_hideout_companion_aura")
        EntityAddChild(player,aura)
    end
    local effect=EntityGetFirstComponentIncludingDisabled(aura,"GameEffectComponent")
    if effect then ComponentSetValue2(effect,"frames",70) end
    return aura
end

local function support(player,id,spec,bonus,x,y,age)
    if spec.effect then
        refreshAura(player,"nh_companion_"..spec.effect,"data/entities/misc/"..spec.effect..".xml",x,y)
    end
    if id=="flower_fairy" or id=="dryad" then
        local seconds=id=="flower_fairy" and bonus.fairySeconds or bonus.dryadSeconds
        if seconds==0 or age%(seconds*60)~=0 then return end
        local model=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
        if model then
            local hp,maximum=ComponentGetValue2(model,"hp"),ComponentGetValue2(model,"max_hp")
            if hp>0 and hp<maximum then ComponentSetValue2(model,"hp",math.min(hp+0.04,maximum)) end
        end
    elseif id=="minotaur" and bonus.shieldRecharge>0 then
        local aura=refreshAura(player,"nh_companion_shield",root.."companions/shield.xml",x,y)
        local shield=aura and EntityGetFirstComponentIncludingDisabled(aura,"EnergyShieldComponent")
        if shield then ComponentSetValue2(shield,"recharge_speed",bonus.shieldRecharge) end
    elseif id=="griffin" and bonus.flightPercent>0 and age%60==0 then
        local character=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
        if character then
            local fuel,maximum=ComponentGetValue2(character,"mFlyingTimeLeft"),ComponentGetValue2(character,"fly_time_max")
            if fuel<maximum then ComponentSetValue2(character,"mFlyingTimeLeft",math.min(maximum,fuel+maximum*bonus.flightPercent/100)) end
        end
    end
end

local function travel(pet,spec,x,y,nearby,age,seconds)
    local trip=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_trip")
    local previous=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_position")
    local gifts=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_gifts")
    if ComponentGetValue2(gifts,"value_float")>=2 then return end
    local dx=x-ComponentGetValue2(previous,"value_int")
    local dy=y-ComponentGetValue2(previous,"value_float")
    ComponentSetValue2(previous,"value_int",math.floor(x+0.5))
    ComponentSetValue2(previous,"value_float",y)
    local distance=dx*dx+dy*dy
    if age==interval or not nearby or distance<1 or distance>48^2 then return end
    local walked=ComponentGetValue2(trip,"value_int")+interval
    if walked<seconds*60 then ComponentSetValue2(trip,"value_int",walked); return end
    ComponentSetValue2(trip,"value_int",0)
    local roll=ComponentGetValue2(gifts,"value_int")*48271%2147483647
    ComponentSetValue2(gifts,"value_int",roll)
    if roll%4~=0 then return end
    local gift=EntityLoad(root.."items/"..spec.gift..".xml",x,y-2)
    if gift and gift~=0 then
        ComponentSetValue2(gifts,"value_float",ComponentGetValue2(gifts,"value_float")+1)
        GamePrint(GameTextGetTranslatedOrNot("$nh_companion_gift").." "..GameTextGetTranslatedOrNot("$nh_hideout_"..spec.gift))
    end
end

function NHCompanions.update(pet)
    local player=EntityGetParent(pet)
    if not player or player==0 or not EntityGetIsAlive(player) then EntityKill(pet); return end
    if not EntityHasTag(player,"player_unit") then return end
    local clock=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_companion_clock")
    local id=ComponentGetValue2(clock,"value_string")
    local spec=NHCompanions.species[id]
    local age=ComponentGetValue2(clock,"value_int")+interval
    if age>10800 then NHCompanions.clearSupport(player); EntityKill(pet); return end
    ComponentSetValue2(clock,"value_int",age)
    local bonus=NHCompanions.bonuses[NHAffinity.tier(NHAffinity.follow(id,interval))]
    local x,y=EntityGetTransform(player)
    local px,py,_,scaleX,scaleY=EntityGetTransform(pet)
    local toPlayer=x-px
    local tx=x+math.sin(age/65)*13
    local ty=y-12+math.sin(age/19)*3
    local distance=(px-x)^2+(py-y)^2
    if distance>100^2 then px,py=tx,ty
    else px,py=px+(tx-px)*0.32,py+(ty-py)*0.32 end
    -- The animated figures turn to follow the player and keep their facing
    -- during the small idle orbit. Mirroring preserves their native art scale.
    if math.abs(toPlayer)>16 then
        scaleX=toPlayer>0 and math.abs(scaleX) or -math.abs(scaleX)
    end
    EntitySetTransform(pet,px,py,0,scaleX,scaleY)
    if age%60==interval then fireAtHostile(player,px,py,spec.damage) end
    if age%60==0 or age==interval then support(player,id,spec,bonus,x,y,age) end
    travel(pet,spec,x,y,distance<=45^2,age,bonus.giftSeconds)
end
