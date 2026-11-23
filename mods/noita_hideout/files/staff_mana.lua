local owner=EntityGetParent(GetUpdatedEntityID())
if owner~=0 then
    for _,item in ipairs(GameGetAllInventoryItems(owner) or {}) do
        if EntityHasTag(item,"wand") and not EntityHasTag(item,"nh_firearm") then
            local ability=EntityGetFirstComponentIncludingDisabled(item,"AbilityComponent")
            if ability then
                local mana=ComponentGetValue2(ability,"mana")
                local cap=ComponentGetValue2(ability,"mana_max")
                if mana<cap then ComponentSetValue2(ability,"mana",math.min(cap,mana+2)) end
            end
        end
    end
end
