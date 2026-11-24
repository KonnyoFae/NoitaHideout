local root="mods/noita_hideout/files/bow/"
local mode=dofile_once(root.."modes.lua")[3]
return function(owner,x,y,tier,angle)
    local anchor=EntityLoad(root.."anchor.xml",x,y)
    if not anchor or anchor==0 then return false end
    if angle then
        EntitySetTransform(anchor,x,y,angle)
    else
        EntitySetComponentsWithTagEnabled(anchor,"nh_planted_arrow",false)
    end
    local field=EntityGetFirstComponentIncludingDisabled(anchor,"VariableStorageComponent","nh_bow_field")
    ComponentSetValue2(field,"value_int",owner)
    ComponentSetValue2(field,"value_float",tier)
    local ring=EntityGetFirstComponentIncludingDisabled(anchor,"SpriteComponent","nh_bow_ring")
    ComponentSetValue2(ring,"special_scale_x",mode.radius[tier]/32)
    ComponentSetValue2(ring,"special_scale_y",mode.radius[tier]/32)
    EntityAddComponent2(anchor,"LifetimeComponent",{lifetime=mode.life[tier]})
    return true
end
