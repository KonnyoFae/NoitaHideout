function death(damage_type,message,responsible,drop_items)
    local mob=GetUpdatedEntityID()
    if drop_items==false or EntityHasTag(mob,"player_unit") or EntityHasTag(mob,"nh_loot_paid") then return end
    EntityAddTag(mob,"nh_loot_paid")
    local x,y=EntityGetTransform(mob)
    local model=EntityGetFirstComponentIncludingDisabled(mob,"DamageModelComponent")
    local health=model and ComponentGetValue2(model,"max_hp")
    local kind="travel_satchel"
    local count=1 -- An independent template without a health value keeps its former single satchel.
    if health then
        if health<=0 then return end
        if health>=8 then kind="loot_case"
        elseif health>=2 then kind="travel_pack" end

        -- One engine HP is 25 displayed HP. Use hundredths to avoid an extra roll from float noise at 20, 40, ... HP.
        local hpHundredths=math.floor(health*2500+0.5)
        count=math.floor(hpHundredths/2000)
        local remainder=hpHundredths%2000
        if remainder>0 and ProceduralRandomi(x+mob,y+GameGetFrameNum(),1,2000)<=remainder then count=count+1 end
        if count==0 then return end
    end
    local bag=EntityLoad("mods/noita_hideout/files/items/"..kind..".xml",x,y-3)
    if count>1 and bag and bag~=0 then
        local item=EntityGetFirstComponentIncludingDisabled(bag,"ItemComponent")
        if item then ComponentSetValue2(item,"uses_remaining",math.min(count,2147483647)) end
    end
end
