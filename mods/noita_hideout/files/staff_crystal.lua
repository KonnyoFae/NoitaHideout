local x,y=EntityGetTransform(GetUpdatedEntityID())
for _,player in ipairs(EntityGetInRadiusWithTag(x,y,96,"player_unit") or {}) do
    local health=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if health then
        local hp=ComponentGetValue2(health,"hp")
        local maximum=ComponentGetValue2(health,"max_hp")
        if hp>0 and hp<maximum then
            ComponentSetValue2(health,"hp",math.min(maximum,hp+maximum*0.04))
            local px,py=EntityGetTransform(player)
            GameCreateParticle("spark_green",px,py,4,0,-12,true)
        end
    end
end
