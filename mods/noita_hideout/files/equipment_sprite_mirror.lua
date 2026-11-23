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

-- The staff controller renews a swing frame in OnWorldPostUpdate. Expire
-- it here as well when the staff is dropped or reloaded mid-swing.
if EntityHasTag(entity,"noita_hideout_battle_staff") then
    local clock=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent","nh_staff_clock")
    if clock and ComponentGetValue2(sprite,"rect_animation")~="default" then
        local age=GameGetFrameNum()-ComponentGetValue2(clock,"value_float")
        if age<0 or age>1 then
            ComponentSetValue2(sprite,"rect_animation","default")
            ComponentSetValue2(sprite,"next_rect_animation","default")
            EntityRefreshSprite(entity,sprite)
        end
    end
end
