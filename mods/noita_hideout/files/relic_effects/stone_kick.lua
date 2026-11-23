local player=EntityGetRootEntity(GetUpdatedEntityID())
local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
if controls and ComponentGetValue2(controls,"mButtonFrameKick")==GameGetFrameNum() then
    dofile_once("data/scripts/items/stonestone.lua")
    kick()
end
