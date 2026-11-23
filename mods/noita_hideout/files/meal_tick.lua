local entity=GetUpdatedEntityID()
local player=EntityGetParent(entity)
local timer=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent")
if not player or player==0 or not timer then EntityKill(entity); return end
local left=ComponentGetValue2(timer,"value_int")-1
local amount=ComponentGetValue2(timer,"value_float")
local key=ComponentGetValue2(timer,"name")
if key=="sugar" or (key=="grain" and left%4==0) then
    local model=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if model then
        local hp=ComponentGetValue2(model,"hp")
        local maximum=ComponentGetValue2(model,"max_hp")
        if hp>0 and hp<maximum then ComponentSetValue2(model,"hp",math.min(maximum,hp+maximum*amount/100)) end
    end
elseif key=="spice" then
    local character=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
    if character then
        local fuel=ComponentGetValue2(character,"mFlyingTimeLeft")
        local capacity=ComponentGetValue2(character,"fly_time_max")
        if fuel<capacity then ComponentSetValue2(character,"mFlyingTimeLeft",math.min(capacity,fuel+capacity*0.05*amount)) end
    end
    local inv=EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    local wand=inv and ComponentGetValue2(inv,"mActiveItem")
    if wand and wand~=0 and EntityHasTag(wand,"wand") then
        local ability=EntityGetFirstComponentIncludingDisabled(wand,"AbilityComponent")
        if ability then
            local mana=ComponentGetValue2(ability,"mana")
            local cap=ComponentGetValue2(ability,"mana_max")
            if mana<cap then ComponentSetValue2(ability,"mana",math.min(cap,mana+10*amount)) end
        end
    end
end
if left<=0 then EntityKill(entity)
else ComponentSetValue2(timer,"value_int",left) end
