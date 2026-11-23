-- Special rounds and throwables run their payload once on removal, including expiry.
local entity=GetUpdatedEntityID()
local shot=EntityGetFirstComponentIncludingDisabled(entity,"ProjectileComponent")
local marker=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent","nh_throwable_impact")
if not shot or not marker or ComponentGetValue2(marker,"value_bool") then return end
local owner=ComponentGetValue2(shot,"mWhoShot")
if not owner or owner==0 then return end
local x,y=EntityGetTransform(entity)
if not x or not DoesWorldExistAt(math.floor(x),math.floor(y),math.floor(x)+1,math.floor(y)+1) then return end

local effects={
    fire_grenade={damage=0.60,kind="DAMAGE_FIRE",resist="fire",protection="PROTECTION_FIRE",
        effect="data/entities/misc/effect_on_fire.xml",particles="fire",sound="explosions/fire"},
    frost_grenade={damage=0.48,kind="DAMAGE_ICE",resist="ice",protection="PROTECTION_FREEZE",
        stunProtection="STUN_PROTECTION_FREEZE",effect="data/entities/misc/effect_frozen_short.xml",
        particles="spark_white",sound="explosions/magic_small"},
    shock_grenade={damage=0.72,kind="DAMAGE_ELECTRICITY",resist="electricity",protection="PROTECTION_ELECTRICITY",
        stunProtection="STUN_PROTECTION_ELECTRICITY",effect="data/entities/misc/effect_electricity.xml",
        particles="spark_electric",sound="explosions/electric_small"},
    flare_gun={damage=0.32,kind="DAMAGE_FIRE",effect="mods/noita_hideout/files/projectiles/sand_blindness.xml",
        particles="spark_red",sound="explosions/fire"},
    sand_knife={damage=0.32,kind="DAMAGE_PROJECTILE",effect="mods/noita_hideout/files/projectiles/sand_blindness.xml",
        particles="sand",sound="explosions/magic_grenade_tiny"},
    metal_knife={damage=0.80,kind="DAMAGE_SLICE",particles="steel",sound="explosions/magic_grenade_tiny"},
}
local id=ComponentGetValue2(marker,"value_string")
local burst=effects[id]
if not burst then return end
local definitions=dofile("mods/noita_hideout/files/throwables.lua")
local radius=id=="flare_gun" and 22 or definitions.types[id].radius
ComponentSetValue2(marker,"value_bool",true)

GamePlaySound("data/audio/Desktop/explosion.bank",burst.sound,x,y)
for i=1,16 do
    local angle=i*math.pi/8
    local dx,dy=math.cos(angle),math.sin(angle)
    GameCreateParticle(burst.particles,x+dx*radius*0.5,y+dy*radius*0.5,2,dx*55,dy*55,true,true)
end

local function canApplyStatus(target,model)
    if not burst.effect or GameGetGameEffectCount(target,"PROTECTION_ALL")>0 then return false end
    if burst.protection and GameGetGameEffectCount(target,burst.protection)>0 then return false end
    if burst.stunProtection and GameGetGameEffectCount(target,burst.stunProtection)>0 then return false end
    return not burst.resist or (ComponentObjectGetValue2(model,"damage_multipliers",burst.resist) or 1)>0
end

local ownerAlive=EntityGetIsAlive(owner)
local name=GameTextGetTranslatedOrNot("$nh_hideout_"..id)
for _,target in ipairs(EntityGetInRadiusWithTag(x,y,radius,"mortal") or {}) do
    if target~=owner and not EntityHasTag(target,"noita_hideout_companion")
        and (not ownerAlive or EntityGetHerdRelationSafe(owner,target)<=50)
        and GameGetGameEffectCount(target,"CHARM")==0 then
        local model=EntityGetFirstComponent(target,"DamageModelComponent")
        if model and (ComponentGetValue2(model,"hp") or 0)>0 then
            EntityInflictDamage(target,burst.damage,burst.kind,name,"NONE",0,0,owner,x,y)
            -- A damage callback can kill, polymorph or replace the damage model.
            model=burst.effect and EntityGetIsAlive(target) and EntityGetFirstComponent(target,"DamageModelComponent")
            if model and (ComponentGetValue2(model,"hp") or 0)>0 and canApplyStatus(target,model) then
                LoadGameEffectEntityTo(target,burst.effect)
                if id=="flare_gun" and GameGetGameEffectCount(target,"PROTECTION_FIRE")==0
                    and (ComponentObjectGetValue2(model,"damage_multipliers","fire") or 1)>0 then
                    LoadGameEffectEntityTo(target,"data/entities/misc/effect_on_fire.xml")
                end
            end
        end
    end
end
