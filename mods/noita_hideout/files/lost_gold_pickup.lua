-- Returning carried money must not multiply it through EXTRA_MONEY.
local ew=NHEW or dofile("mods/noita_hideout/files/ew.lua")
function item_pickup(entity,player)
    if not ew.walletAllowed() or not ew.localBody(player) then return end
    local wallet=EntityGetFirstComponentIncludingDisabled(player,"WalletComponent")
    local value=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent","nh_lost_gold")
    if not wallet or not value then return end
    local amount=tonumber(ComponentGetValue2(value,"value_string"))
    if not amount then return end
    ComponentSetValue2(wallet,"money",ComponentGetValue2(wallet,"money")+amount)
    if ComponentGetValue2(value,"value_bool") then ComponentSetValue2(wallet,"mHasReachedInf",true) end
    ComponentSetValue2(value,"value_string","")
    EntityKill(entity)
end
