local runtime=dofile("mods/noita_hideout/files/shield_runtime.lua")

dofile_once("mods/noita_hideout/files/companions.lua")
dofile_once("mods/noita_hideout/files/affinity.lua")
local rescue=dofile("mods/noita_hideout/files/rescue.lua")

-- Settle the actual hit inside the damage message, including fatal hits.
-- The earlier food callback sees damage before typed multipliers and crits.
function damage_about_to_be_received(damage,x,y,responsible,critical)
    rescue.lifePriority(GetUpdatedEntityID())
    return damage,critical
end

function damage_received(damage)
    if damage<=0 then return end
    local player=GetUpdatedEntityID()
    local spill=runtime.hit(player,damage)
    local model=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not model then return end
    if spill<damage then
        ComponentSetValue2(model,"hp",ComponentGetValue2(model,"hp")+(damage-spill))
    end
    if ComponentGetValue2(model,"hp")<=0 then rescue.intercept(player,model) end
end
