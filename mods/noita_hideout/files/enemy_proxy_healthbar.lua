-- Runs on the proxy's second and final frame, after the boss registry fills it.
local proxy = GetUpdatedEntityID()
local damage = EntityGetFirstComponentIncludingDisabled(proxy, "DamageModelComponent")
if damage and ComponentGetValue2(damage, "max_hp") > 0 then
    local bar = EntityGetFirstComponentIncludingDisabled(proxy, "BossHealthBarComponent")
    if bar then
        ComponentSetValue2(bar, "gui", true)
        ComponentSetValue2(bar, "in_world", true)
        EntitySetComponentIsEnabled(proxy, bar, true)
    end
end
