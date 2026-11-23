function damage_about_to_be_received(damage,x,y,responsible,critical)
    if damage>0 then
        local player=GetUpdatedEntityID()
        for _,key in ipairs({"egg","meat"}) do
            local child=(EntityGetAllChildren(player,"noita_hideout_meal_"..key) or {})[1]
            local timer=child and EntityGetFirstComponentIncludingDisabled(child,"VariableStorageComponent")
            if timer then damage=damage*(1-ComponentGetValue2(timer,"value_float")/100) end
        end
    end
    return damage,critical
end
