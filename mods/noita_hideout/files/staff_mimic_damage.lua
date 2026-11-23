function damage_about_to_be_received(damage,velocityX,velocityY,responsible,critical)
    if damage>0 then
        local body=GetUpdatedEntityID()
        if EntityHasTag(body,"polymorphed_player") then
            if not EntityHasTag(body,"nh_staff_mimic_hit") then EntityAddTag(body,"nh_staff_mimic_hit") end
            return 0,0
        end
    end
    return damage,critical
end
