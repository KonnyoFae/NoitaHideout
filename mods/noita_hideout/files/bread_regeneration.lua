-- The timer is saved on the food effect so a continued game resumes its pulses.
local effect=GetUpdatedEntityID()
local owner=EntityGetParent(effect)
local timer=EntityGetFirstComponentIncludingDisabled(effect,"VariableStorageComponent")
if not owner or owner==0 or not timer then EntityKill(effect); return end
local seconds=ComponentGetValue2(timer,"value_int")-1
if seconds>=0 and seconds%4==0 then
    local damage=EntityGetFirstComponentIncludingDisabled(owner,"DamageModelComponent")
    if damage then
        local hp=ComponentGetValue2(damage,"hp")
        local maximum=ComponentGetValue2(damage,"max_hp")
        if hp>0 and hp<maximum then ComponentSetValue2(damage,"hp",math.min(maximum,hp+0.04)) end
    end
end
if seconds<=0 then EntityKill(effect)
else ComponentSetValue2(timer,"value_int",seconds) end
