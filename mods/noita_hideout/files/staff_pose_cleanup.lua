-- The controller poses this child in OnWorldPostUpdate, after entity scripts run.
-- Keep the cleanup with the item so it also works after a drop or a save reload.
local visual=GetUpdatedEntityID()
local gun=EntityGetParent(visual)
local stamp=EntityGetFirstComponent(visual,"VariableStorageComponent","nh_pose_frame")
local age=GameGetFrameNum()-ComponentGetValue2(stamp,"value_int")
if gun~=0 and age>=0 and age<=1 then return end
if gun~=0 then
    local sprite=EntityGetFirstComponentIncludingDisabled(gun,"SpriteComponent","enabled_in_hand")
    if sprite then
        ComponentSetValue2(sprite,"visible",true)
        EntityRefreshSprite(gun,sprite)
    end
end
EntityKill(visual)
