-- Charged summons follow their owner's transform like the vanilla ghost perks.
-- Runtime state belongs to the entity, so continuing a world resumes its trip.
local root="mods/noita_hideout/files/"
dofile_once(root.."companions.lua")
dofile_once(root.."affinity.lua")
local interval=6
local durationFrames=15*60*60

local combat=dofile(root.."companions/combat.lua")

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

local function pulseField(player,spec,bonus,x,y)
    for _,target in ipairs(EntityGetInRadiusWithTag(x,y,spec.radius,"mortal") or {}) do
        if combat.hostile(player,target) then
            EntityInflictDamage(target,bonus.fieldDamage/25,"DAMAGE_MELEE","$nh_companion_field","NONE",0,0,player,x,y)
        end
    end
end

local function support(player,spec,bonus,x,y,pulse)
    NHCompanions.applyModifier(player,spec,bonus)
    if spec.effect then
        refreshAura(player,"nh_companion_"..spec.effect,"data/entities/misc/"..spec.effect..".xml",x,y)
    end
    if spec.shield and bonus.shieldRecharge>0 then
        local aura=refreshAura(player,"nh_companion_shield",root.."companions/shield.xml",x,y)
        local shield=aura and EntityGetFirstComponentIncludingDisabled(aura,"EnergyShieldComponent")
        if shield then ComponentSetValue2(shield,"recharge_speed",bonus.shieldRecharge) end
    end
    if spec.role=="melee" then
        refreshAura(player,"nh_companion_knockback","data/entities/misc/effect_knockback_immunity.xml",x,y)
        local aura=refreshAura(player,"nh_companion_field",root.."companions/field.xml",x,y)
        local sprite=aura and EntityGetFirstComponentIncludingDisabled(aura,"SpriteComponent")
        if sprite then
            ComponentSetValue2(sprite,"special_scale_x",spec.radius/16)
            ComponentSetValue2(sprite,"special_scale_y",spec.radius/16)
        end
    elseif spec.role=="support" then
        refreshAura(player,"nh_companion_mana","data/entities/misc/effect_mana_regeneration.xml",x,y)
        if not pulse then return end
        local model=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
        if model then
            local hp,maximum=ComponentGetValue2(model,"hp"),ComponentGetValue2(model,"max_hp")
            if hp>0 and hp<maximum then ComponentSetValue2(model,"hp",math.min(maximum,hp+maximum*bonus.heal/100)) end
        end
        for _,item in ipairs(GameGetAllInventoryItems(player) or {}) do
            if EntityHasTag(item,"wand") and not EntityHasTag(item,"nh_firearm") then
                local ability=EntityGetFirstComponentIncludingDisabled(item,"AbilityComponent")
                if ability then
                    local mana,cap=ComponentGetValue2(ability,"mana"),ComponentGetValue2(ability,"mana_max")
                    if mana<cap then ComponentSetValue2(ability,"mana",math.min(cap,mana+bonus.mana)) end
                end
            end
        end
    elseif pulse then
        local character=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
        if character then
            local fuel,maximum=ComponentGetValue2(character,"mFlyingTimeLeft"),ComponentGetValue2(character,"fly_time_max")
            if fuel<maximum then ComponentSetValue2(character,"mFlyingTimeLeft",math.min(maximum,fuel+maximum*(spec.fuel+bonus.fuel)/100)) end
        end
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
    if age>durationFrames then NHCompanions.clearSupport(player); EntityKill(pet); return end
    if not EntityHasTag(pet,"nh_companion_roles") then
        NHCompanions.clearSupport(player)
        EntityAddTag(pet,"nh_companion_roles")
    end
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
    combat.update(id,pet,player,age,x,y,px,py)
    if age%60==0 or age==interval then
        NHCompanions.immunities.apply(player,id)
        support(player,spec,bonus,x,y,age%60==0)
    end
    if spec.role=="melee" and age%30==0 then pulseField(player,spec,bonus,x,y) end
    if age%(NHCompanions.giftMinutes(spec)*3600)==0 then
        -- The main Lua state owns the secure case. A queued gift survives
        -- companion expiry or replacement before the controller settles it.
        EntityAddComponent2(player,"VariableStorageComponent",{_tags="nh_companion_gift",value_string=id,
            value_float=bonus.giftLevel,value_int=GameGetFrameNum()})
    end
end
