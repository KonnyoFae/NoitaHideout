local A={}
local tag="nh_turret_ammo"
function A.counter(id)
    return EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent",tag)
end

-- Older deployed machine guns have neither a counter nor the new durability.
function A.upgradeMachineGun(id)
    local counter=A.counter(id)
    if counter then return counter end
    local hp=EntityGetFirstComponentIncludingDisabled(id,"DamageModelComponent")
    if not hp then return end
    local previous=ComponentGetValue2(hp,"max_hp")
    local fraction=previous>0 and ComponentGetValue2(hp,"hp")/previous or 0
    counter=EntityAddComponent2(id,"VariableStorageComponent",{_tags=tag,value_int=3000,value_float=3000})
    if counter and counter~=0 then
        ComponentSetValue2(hp,"max_hp",12)
        ComponentSetValue2(hp,"hp",12*math.min(1,fraction))
        return counter
    end
end

function A.set(id,counter,amount)
    ComponentSetValue2(counter,"value_int",amount)
    if amount==0 then
        local attack=EntityGetFirstComponentIncludingDisabled(id,"AIAttackComponent")
        if attack then EntitySetComponentIsEnabled(id,attack,false) end
        local ai=EntityGetFirstComponentIncludingDisabled(id,"AnimalAIComponent")
        if ai then ComponentSetValue2(ai,"attack_ranged_enabled",false) end
    end
end

-- Returns nil if the gun cannot pay, otherwise the number left after this round.
function A.spend(id)
    local counter=A.counter(id)
    if not counter and EntityHasTag(id,"nh_mg_turret") then counter=A.upgradeMachineGun(id) end
    local left=counter and ComponentGetValue2(counter,"value_int")
    if not left or left<=0 then return end
    A.set(id,counter,left-1)
    return left-1
end
return A
