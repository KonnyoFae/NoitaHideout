local runtime=dofile("mods/noita_hideout/files/shield_runtime.lua")
local ew=NHEW or dofile("mods/noita_hideout/files/ew.lua")

dofile_once("mods/noita_hideout/files/companions.lua")
dofile_once("mods/noita_hideout/files/affinity.lua")
local rescue=dofile("mods/noita_hideout/files/rescue.lua")

-- Settle the actual hit inside the damage message, including fatal hits.
-- The earlier food callback sees damage before typed multipliers and crits.
function damage_about_to_be_received(damage,x,y,responsible,critical)
    local player=GetUpdatedEntityID()
    local dash=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_katana_dash_guard")
    if damage>0 and dash and ComponentGetValue2(dash,"value_int")>GameGetFrameNum() then return 0,0 end
    if damage>0 and EntityHasTag(player,"nh_rewind_armed")
        and dofile_once("mods/noita_hideout/files/rewind_watch.lua").blockHit(player,damage) then return 0,0 end
    if ew.localBody(player) then rescue.lifePriority(player) end
    return damage,critical
end

function damage_received(damage)
    if damage<=0 then return end
    local player=GetUpdatedEntityID()
    if not ew.localBody(player) then return end
    local spill,before,after=runtime.hit(player,damage)
    local model=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not model then return end
    if spill<damage then
        ComponentSetValue2(model,"hp",ComponentGetValue2(model,"hp")+(damage-spill))
    end
    local reactor
    if EntityHasTag(player,"nh_reactor_active") then
        reactor=dofile_once("mods/noita_hideout/files/mana_reactor.lua")
        reactor.hit(player,before,after)
    end
    if ComponentGetValue2(model,"hp")<=0 then
        rescue.intercept(player,model)
        if reactor and EntityHasTag(player,"nh_reactor_active") and ComponentGetValue2(model,"hp")<=0 then reactor.cancel(player) end
    end
end
