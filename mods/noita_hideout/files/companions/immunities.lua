local poly=dofile("mods/noita_hideout/files/polymorph_protection.lua")
local I={types={
    dragon={zh="火焰免疫",en="Fire immunity",effect="PROTECTION_FIRE"},
    bee={zh="毒素免疫",en="Poison immunity",typed="poison",effect="PROTECTION_RADIOACTIVITY",
        materials={"poison","rock_static_poison"}},
    griffin={zh="电击免疫",en="Electricity immunity",effect="PROTECTION_ELECTRICITY"},
    cat={zh="诅咒免疫",en="Curse immunity",typed="curse",materials={"cursed_liquid","rock_static_cursed","rock_static_cursed_green"}},
    dog={zh="冰冻免疫",en="Ice immunity",typed="ice",effect="PROTECTION_FREEZE",materials={"blood_cold","blood_cold_vapour"}},
    slime={zh="窒息免疫",en="Suffocation immunity"},
    flower_fairy={zh="酸液免疫",en="Acid immunity",materials={"acid","ice_acid_static","ice_acid_glass"}},
    minotaur={zh="变形免疫",en="Polymorph immunity"},
    dryad={zh="切割免疫",en="Slice immunity",typed="slice"},
}}
local tag="nh_companion_immunity"

-- The frost shield temporarily owns the live ice/poison multiplier. Change
-- its saved underlying value while it is equipped, in either equip order.
local function resistance(player,dm,kind,value)
    local field=kind=="ice" and "value_float" or kind=="poison" and "value_string"
    local shield=field and (EntityGetAllChildren(player,"nh_shield_elements") or {})[1]
    local prior=shield and EntityGetFirstComponentIncludingDisabled(shield,"VariableStorageComponent","nh_shield_resists")
    if prior then
        if value~=nil then ComponentSetValue2(prior,field,kind=="poison" and tostring(value) or value) end
        return tonumber(ComponentGetValue2(prior,field))
    end
    if value~=nil then ComponentObjectSetValue2(dm,"damage_multipliers",kind,value) end
    return ComponentObjectGetValue2(dm,"damage_multipliers",kind)
end

local function materialDamage(dm)
    local amounts=(ComponentGetValue2(dm,"materials_how_much_damage") or ""):gmatch("[^,]+")
    local result={}
    for name in (ComponentGetValue2(dm,"materials_that_damage") or ""):gmatch("[^,%s]+") do
        local amount=amounts()
        result[name]=tonumber(amount)
    end
    return result
end

local function clearDamage(player,child)
    local saved=EntityGetFirstComponentIncludingDisabled(child,"VariableStorageComponent",tag)
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if saved and dm then
        local id=ComponentGetValue2(saved,"name")
        local kind=I.types[id].typed
        if kind and resistance(player,dm,kind)==0 then resistance(player,dm,kind,ComponentGetValue2(saved,"value_float")) end
        if id=="slime" and not ComponentGetValue2(dm,"air_needed") then
            ComponentSetValue2(dm,"air_needed",ComponentGetValue2(saved,"value_bool"))
        end
        local materials=ComponentGetValue2(saved,"value_string")
        if materials~="" then
            local current=materialDamage(dm)
            for name,amount in materials:gmatch("([%w_]+)=([^,]+)") do
                if (current[name] or 0)==0 then EntitySetDamageFromMaterial(player,name,tonumber(amount)) end
            end
        end
    end
    EntityRemoveFromParent(child)
    EntityKill(child)
end

function I.apply(player,id)
    poly.set(player,"nh_poly_companion",id=="minotaur")
    local child=(EntityGetAllChildren(player,tag) or {})[1]
    if child then
        if id and EntityHasTag(child,"nh_immune_"..id) then return end
        clearDamage(player,child)
    end
    if not id or id=="minotaur" then return end
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not dm then return end
    local spec=I.types[id]
    child=EntityCreateNew(tag)
    EntityAddTag(child,tag)
    EntityAddTag(child,"nh_immune_"..id)
    EntityAddComponent2(child,"InheritTransformComponent",{})
    EntityAddChild(player,child)
    local saved=EntityAddComponent2(child,"VariableStorageComponent",{_tags=tag,name=id,value_string=""})
    if spec.effect then
        EntityAddComponent2(child,"GameEffectComponent",{effect=spec.effect,frames=-1,exclusivity_group=0})
    end
    if spec.typed then
        ComponentSetValue2(saved,"value_float",resistance(player,dm,spec.typed))
        resistance(player,dm,spec.typed,0)
    end
    if spec.materials then
        local current,original=materialDamage(dm),{}
        for _,name in ipairs(spec.materials) do
            local amount=current[name]
            if amount and amount>0 then
                original[#original+1]=name.."="..amount
                EntitySetDamageFromMaterial(player,name,0)
            end
        end
        ComponentSetValue2(saved,"value_string",table.concat(original,","))
    end
    if id=="slime" then
        ComponentSetValue2(saved,"value_bool",ComponentGetValue2(dm,"air_needed"))
        ComponentSetValue2(dm,"air_needed",false)
    elseif id=="bee" then
        EntityAddComponent2(child,"LuaComponent",{script_source_file="mods/noita_hideout/files/injector_antitoxin.lua",execute_every_n_frame=1})
    end
end
return I
