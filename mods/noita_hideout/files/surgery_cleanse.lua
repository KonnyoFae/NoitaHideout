local M={}

-- Material status IDs from data/scripts/status_effects/status_list.lua. These
-- are separate from GameEffectComponent.effect (e.g. POISONED vs POISON).
-- Berserk, regeneration, ambrosia, mana, and beneficial coatings remain active.
local materialStatus={
    RADIOACTIVE=true, ALCOHOLIC=true, POISONED=true, TELEPORTATION=true, UNSTABLE_TELEPORTATION=true,
    POLYMORPH=true, POLYMORPH_RANDOM=true, POLYMORPH_UNSTABLE=true, POLYMORPH_CESSATION=true,
    ON_FIRE=true, CONFUSION=true, WORM_ATTRACTOR=true, INGESTION_DRUNK=true, FOOD_POISONING=true,
    INGESTION_MOVEMENT_SLOWER=true, INGESTION_DAMAGE=true, INGESTION_EXPLODING=true, INGESTION_FREEZING=true,
    INGESTION_ON_FIRE=true, FARTS=true, CURSE_CLOUD=true, WEAKNESS=true, JARATE=true, SLIMY=true,
}
local gameEffect={
    POISON=true, RADIOACTIVE=true, DRUNK=true, TELEPORTATION=true, UNSTABLE_TELEPORTATION=true,
    ON_FIRE=true, CONFUSION=true, WORM_ATTRACTOR=true, FOOD_POISONING=true, MOVEMENT_SLOWER=true,
    MOVEMENT_SLOWER_2X=true, INTERNAL_FIRE=true, INTERNAL_ICE=true, FARTS=true, WEAKNESS=true,
    BLINDNESS=true, FROZEN=true, ELECTROCUTION=true, NO_HEAL=true, JARATE=true, SLIMY=true,
}
local curseCloud={CURSE_CLOUD_00=true,CURSE_CLOUD_01=true,CURSE_CLOUD_02=true,CURSE_CLOUD_01_TEMPORARY=true}
local nativeCarriers={
    effect_apply_on_fire=true,effect_apply_poison=true,effect_blindness=true,
    effect_brain_damage=true,effect_confusion=true,effect_confusion_ui=true,effect_curse_rain=true,
    effect_drunk=true,effect_drunk_00=true,effect_drunk_01=true,effect_drunk_ui=true,effect_electricity=true,
    effect_farts=true,effect_food_poisoning=true,effect_frozen=true,effect_frozen_short=true,effect_internal_fire=true,
    effect_internal_ice=true,effect_jarate=true,effect_movement_slower=true,effect_movement_slower_2x=true,
    effect_movement_slower_ui=true,effect_on_fire=true,effect_poison=true,effect_poison_big=true,
    effect_radioactive=true,effect_slimy=true,effect_spirit_confusion=true,effect_spirit_slime=true,
    effect_spirit_weakness=true,effect_teleportation=true,effect_teleportation_enemy=true,
    effect_unstable_teleportation=true,effect_weakness=true,effect_worm_attractor=true,
    effect_curse_cloud_00=true,effect_curse_cloud_01=true,effect_curse_cloud_01_temporary=true,effect_curse_cloud_02=true,
}

-- These vanilla status entities use Lua and a LifetimeComponent. Killing the
-- attached entity runs its original execute_on_removed scripts (Hearty restores
-- max HP, Wither restores damage multipliers, curse variants remove their tag).
local scriptedStatus={
    effect_twitchy=true,effect_hearty=true,effect_weaken=true,effect_wither=true,
    curse=true,curse_strong=true,curse_stronger=true,curse_wither_electricity=true,
    curse_wither_explosion=true,curse_wither_melee=true,curse_wither_projectile=true,
    neutralized=true,gravity_field_enemy_short=true,effect_homing_shooter=true,
}

local statusScripts={
    ["data/scripts/status_effects/effect_curse_cloud.lua"]=true,["data/scripts/status_effects/effect_curse_cloud_thunder.lua"]=true,
    ["data/scripts/status_effects/twitchy.lua"]=true,["data/scripts/status_effects/twitchy_shot.lua"]=true,
    ["data/scripts/status_effects/hearty_start.lua"]=true,["data/scripts/status_effects/hearty_end.lua"]=true,
    ["data/scripts/status_effects/weaken_start.lua"]=true,["data/scripts/status_effects/weaken_end.lua"]=true,
    ["data/scripts/status_effects/wither_start.lua"]=true,["data/scripts/status_effects/wither_end.lua"]=true,
    ["data/scripts/projectiles/curse.lua"]=true,["data/scripts/projectiles/curse_end.lua"]=true,
    ["data/scripts/projectiles/curse_wither_start.lua"]=true,["data/scripts/projectiles/curse_wither_end.lua"]=true,
    ["data/scripts/projectiles/neutralized.lua"]=true,["data/scripts/projectiles/projectile_gravity_small.lua"]=true,
}
local nativeParts={InheritTransformComponent=true,GameEffectComponent=true,AudioComponent=true,UIIconComponent=true,
    SpriteParticleEmitterComponent=true,ParticleEmitterComponent=true,AudioLoopComponent=true,DrugEffectModifierComponent=true,
    LifetimeComponent=true,VariableStorageComponent=true}

-- EntityGetFilename can change across world streaming. Match the original
-- icon/tag AND its gameplay callback before treating a restored child as a curse.
local streamedIcons={
    ["$status_hearty"]={"effect_hearty","data/scripts/status_effects/hearty_end.lua"},
    ["$status_wither"]={"effect_wither","data/scripts/status_effects/wither_end.lua"},
    ["$status_weaken_combined"]={"effect_weaken","data/scripts/status_effects/weaken_end.lua"},
    ["$status_twitchy"]={"effect_twitchy","data/scripts/status_effects/twitchy.lua"},
    ["$effect_neutralized"]={"neutralized","data/scripts/projectiles/neutralized.lua"},
    ["$streamingevent_gravity_player"]={"gravity_field_enemy_short","data/scripts/projectiles/projectile_gravity_small.lua"},
    ["$status_homing_shooter"]={"effect_homing_shooter","projectile_homing_shooter_wizard"},
}
for _,damageType in ipairs({"electricity","explosion","melee","projectile"}) do
    local id="curse_wither_"..damageType
    streamedIcons["$status_"..id]={id,"data/scripts/projectiles/curse_wither_end.lua"}
end
local function streamed_carrier(entity)
    local scripts=EntityGetComponentIncludingDisabled(entity,"LuaComponent") or {}
    if EntityHasTag(entity,"effect_CURSE") then
        for _,script in ipairs(scripts) do
            if ComponentGetValue2(script,"script_source_file")=="data/scripts/projectiles/curse_end.lua" then return "curse" end
        end
    end
    for _,icon in ipairs(EntityGetComponentIncludingDisabled(entity,"UIIconComponent") or {}) do
        local signature=streamedIcons[ComponentGetValue2(icon,"name")]
        if signature then
            for _,script in ipairs(scripts) do
                if ComponentGetValue2(script,"script_source_file")==signature[2] or ComponentGetValue2(script,"script_shot")==signature[2] then
                    return signature[1]
                end
            end
            if signature[1]=="effect_homing_shooter" then
                for _,shot in ipairs(EntityGetComponentIncludingDisabled(entity,"ShotEffectComponent") or {}) do
                    if ComponentGetValue2(shot,"extra_modifier")==signature[2] then return signature[1] end
                end
            end
        end
    end
end

local statusSlots
local function material_status(player,apply,slimeSafe)
    local data=EntityGetFirstComponentIncludingDisabled(player,"StatusEffectDataComponent")
    if not data then return false end
    if not statusSlots then
        dofile_once("data/scripts/status_effects/status_list.lua")
        statusSlots={}
        -- Both native vectors begin with NONE. Repeated threshold definitions
        -- (e.g. the four INGESTION_DRUNK rows) share one entry in each vector.
        local index,seen=1,{}
        for _,definition in ipairs(status_effects) do
            if not seen[definition.id] then
                index=index+1
                seen[definition.id]=true
                if materialStatus[definition.id] then statusSlots[#statusSlots+1]={index=index,id=definition.id} end
            end
        end
    end
    local stains=ComponentGetValue2(data,"stain_effects") or {}
    local ingestion=ComponentGetValue2(data,"ingestion_effects") or {}
    local found=false
    for _,slot in ipairs(statusSlots) do
        local harmful=slot.id~="SLIMY" or not slimeSafe
        if harmful and (stains[slot.index] or 0)>0 then
            if not apply then return true end
            EntityRemoveStainStatusEffect(player,slot.id,0)
            found=true
        end
        if harmful and (ingestion[slot.index] or 0)>0 then
            if not apply then return true end
            EntityRemoveIngestionStatusEffect(player,slot.id)
            found=true
        end
    end
    return found
end

local function protected(tags)
    for tag in (tags or ""):gmatch("[^,]+") do
        if tag=="perk_entity" or tag=="perk" or tag:match("^noita_hideout_") or tag:match("^nh_") then return true end
    end
    return false
end

local function removable(component,slimeSafe)
    if not ComponentGetIsEnabled(component) or protected(ComponentGetTags(component)) then return false end
    local effect=ComponentGetValue2(component,"effect")
    if effect=="CUSTOM" then return curseCloud[ComponentGetValue2(component,"custom_effect_id")] end
    if not gameEffect[effect] or (effect=="SLIMY" and slimeSafe) then return false end
    local frames=ComponentGetValue2(component,"frames")
    -- A permanent perk can share its effect enum with a potion or spell.
    return frames and frames>0 or ComponentGetValue2(component,"caused_by_stains")
        or ComponentGetValue2(component,"caused_by_ingestion_status_effect")
end

local function attached_status(player,entity,apply,slimeSafe)
    local child=entity~=player
    local file
    if child then
        if protected(EntityGetTags(entity)) or EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
            or EntityGetFirstComponentIncludingDisabled(entity,"DamageModelComponent") then return false end
        file=EntityGetFilename(entity) or ""
        if file:match("^mods/noita_hideout/") then return false end
    end
    local effects=EntityGetComponentIncludingDisabled(entity,"GameEffectComponent") or {}
    local active={}
    for _,component in ipairs(effects) do
        if removable(component,slimeSafe) then
            if not apply then return true end
            active[#active+1]=component
        end
    end
    local vanilla=file and file:match("^data/entities/misc/([%w_]+)%.xml$")
    if child and #effects==0 and not scriptedStatus[vanilla] and not nativeCarriers[vanilla] then
        vanilla=streamed_carrier(entity)
    end
    local knownCarrier=child and (nativeCarriers[vanilla] or scriptedStatus[vanilla] or EntityHasTag(entity,"curse_cloud"))
    local scripts={}
    if knownCarrier then
        local dedicated=#active==#effects and not next(EntityGetAllChildren(entity) or {})
        for _,component in ipairs(EntityGetAllComponents(entity) or {}) do
            local kind=ComponentGetTypeName(component)
            if kind=="LuaComponent" then
                if statusScripts[ComponentGetValue2(component,"script_source_file")]
                    or statusScripts[ComponentGetValue2(component,"script_shot")] then
                    scripts[#scripts+1]=component
                else dedicated=false end
            elseif vanilla=="effect_homing_shooter" and kind=="ShotEffectComponent"
                and ComponentGetValue2(component,"extra_modifier")=="projectile_homing_shooter_wizard" then
                scripts[#scripts+1]=component
            elseif not nativeParts[kind] and not (vanilla=="gravity_field_enemy_short"
                and (kind=="ProjectileComponent" or kind=="VelocityComponent" or kind=="SpriteComponent")) then
                dedicated=false
            end
        end
        if dedicated and (#active>0 or #scripts>0) then
            if apply then EntityKill(entity) end
            return true
        end
    end
    -- Mixed carriers (including extreme tripping with food poisoning) retain
    -- their other components, duration, parent, and children.
    if apply then
        for _,component in ipairs(active) do EntityRemoveComponent(entity,component) end
        for _,component in ipairs(scripts) do EntityRemoveComponent(entity,component) end
    end
    return #active>0 or #scripts>0
end

local function visit(player,apply)
    -- Slime blood preserves the protective coating and removes its slowdown.
    -- Oil is deliberately retained: HYDRATED and OILED use the same native effect.
    local slimeSafe=GameGetGameEffectCount(player,"NO_SLIME_SLOWDOWN")>0
    local found=material_status(player,apply,slimeSafe)
    if found and not apply then return true end
    local damage=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if damage and (ComponentGetValue2(damage,"mIsOnFire") or (ComponentGetValue2(damage,"mFireFramesLeft") or 0)>0) then
        if not apply then return true end
        ComponentSetValue2(damage,"mFireFramesLeft",0)
        ComponentSetValue2(damage,"mIsOnFire",false)
        found=true
    end
    if attached_status(player,player,apply,slimeSafe) then found=true end
    for _,child in ipairs(EntityGetAllChildren(player) or {}) do
        if attached_status(player,child,apply,slimeSafe) then found=true end
    end
    return found
end

function M.has(player) return visit(player,false) end
function M.cleanse(player) return visit(player,true) end

return M
