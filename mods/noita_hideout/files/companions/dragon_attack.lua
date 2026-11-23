local shoot=dofile("mods/noita_hideout/files/companions/projectile.lua")
return function(player,dx,dy)
    local hook=EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_dragon_shot")
    if not hook then return end
    local pet=(EntityGetAllChildren(player,"nh_companion_dragon") or {})[1]
    if not pet then return end
    local clock=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_companion_clock")
    local frame=GameGetFrameNum()
    if not clock or frame<(ComponentGetValue2(clock,"value_float") or 0) then return end
    local length=math.sqrt(dx*dx+dy*dy)
    if length<0.001 then return end
    dx,dy=dx/length,dy/length
    ComponentSetValue2(clock,"value_float",frame+24)
    local x,y=EntityGetTransform(pet)
    return shoot(player,"mods/noita_hideout/files/companions/matter_field.xml",x+dx*9,y+dy*9,dx,dy,240,22)
end
