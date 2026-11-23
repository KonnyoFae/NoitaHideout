-- The box waits at zero HP if its drop cannot be created this frame.
local box=GetUpdatedEntityID()
local dm=EntityGetFirstComponentIncludingDisabled(box,"DamageModelComponent")
if ComponentGetValue2(dm,"hp")>0 then return end
local value=EntityGetFirstComponentIncludingDisabled(box,"VariableStorageComponent","nh_lost_gold")
local amount=ComponentGetValue2(value,"value_string")
if amount=="" then return end
local x,y=EntityGetTransform(box)
local gold=EntityLoad("mods/noita_hideout/files/items/lost_gold.xml",x,y-2)
local target=gold and gold~=0 and EntityGetFirstComponentIncludingDisabled(gold,"VariableStorageComponent","nh_lost_gold")
if not target then
    if gold and gold~=0 then EntityKill(gold) end
    return
end
ComponentSetValue2(target,"value_string",amount)
ComponentSetValue2(target,"value_bool",ComponentGetValue2(value,"value_bool"))
ComponentSetValue2(value,"value_string","")
EntityKill(box)
