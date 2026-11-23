local M={}
local tag="nh_companion_stat_modifier"
local movement={flight={"fly_speed_max_up","velocity_min_y"},support={"run_velocity","fly_velocity_x","velocity_min_x","velocity_max_x"}}

-- Save our multiplier on the player so replacement, rescue and reload can
-- remove just this source even if another perk multiplied the same stat.
local function scale(player,role,ratio)
    if role=="melee" then
        local model=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
        if not model then return false end
        local current=ComponentObjectGetValue2(model,"damage_multipliers","melee")
        ComponentObjectSetValue2(model,"damage_multipliers","melee",current*ratio)
    else
        local platform=EntityGetFirstComponentIncludingDisabled(player,"CharacterPlatformingComponent")
        if not platform then return false end
        for _,field in ipairs(movement[role]) do
            ComponentSetValue2(platform,field,ComponentGetValue2(platform,field)*ratio)
        end
    end
    return true
end

function M.clear(player)
    local c=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
    if c then
        scale(player,ComponentGetValue2(c,"value_string"),100/ComponentGetValue2(c,"value_int"))
        EntityRemoveComponent(player,c)
    end
end

function M.apply(player,spec,bonus)
    local percent=100+bonus.speed
    if spec.role=="flight" then percent=100+spec.lift+bonus.lift
    elseif spec.role=="melee" then percent=100-bonus.meleeResist end
    local c=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
    if c and ComponentGetValue2(c,"value_string")~=spec.role then M.clear(player); c=nil end
    local previous=c and ComponentGetValue2(c,"value_int") or 100
    if percent==previous or not scale(player,spec.role,percent/previous) then return end
    if c then ComponentSetValue2(c,"value_int",percent)
    else EntityAddComponent2(player,"VariableStorageComponent",{_tags=tag,value_string=spec.role,value_int=percent}) end
end
return M
