local entity=GetUpdatedEntityID()
local sprite=EntityGetFirstComponentIncludingDisabled(entity,"SpriteComponent","enabled_in_hand")
if not sprite or not ComponentGetValue2(sprite,"has_special_scale") then return end
local _,_,_,scaleX,scaleY=EntityGetTransform(entity)
local function mirror(field,axis)
    local value=ComponentGetValue2(sprite,field)
    if axis~=0 and ((value<0)~=(axis<0)) then ComponentSetValue2(sprite,field,-value) end
end
mirror("special_scale_x",scaleX)
mirror("special_scale_y",scaleY)

-- The held weapon renews its pose each frame. Restore the idle sprite
-- when a staff or bow is dropped or reloaded during its animation.
local staff=EntityHasTag(entity,"noita_hideout_battle_staff")
if staff or EntityHasTag(entity,"noita_hideout_hunting_bow") then
    local clock=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",staff and "nh_staff_clock" or "nh_bow_clock")
    if clock then
        local age=GameGetFrameNum()-ComponentGetValue2(clock,"value_float")
        if age<0 or age>1 then
            local idle="default"
            if staff then
                local mag=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent","nh_magazine")
                local mode=mag and ComponentGetValue2(mag,"value_float")
                if mode and mode>=1 and mode<=4 then idle="charge_"..mode.."_0" end
            end
            if ComponentGetValue2(sprite,"rect_animation")~=idle then
                ComponentSetValue2(sprite,"rect_animation",idle)
                ComponentSetValue2(sprite,"next_rect_animation",idle)
                EntityRefreshSprite(entity,sprite)
            end
        end
    end
end
