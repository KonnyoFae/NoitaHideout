local id=GetUpdatedEntityID()
local x,y=EntityGetTransform(id)
local eyeY=y-6
local flight=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_decoy_flight")
local anchor=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_decoy_anchor")
local homeX,homeY=ComponentGetValue2(anchor,"value_int"),ComponentGetValue2(anchor,"value_float")
local nearest,best=0,math.huge
for _,enemy in ipairs(EntityGetInRadiusWithTag(x,eyeY,96,"mortal") or {}) do
    local ai=EntityGetFirstComponent(enemy,"AnimalAIComponent")
    if ai and EntityGetFirstComponent(enemy,"GenomeDataComponent") and EntityGetHerdRelation(enemy,id)<40
        and GameGetGameEffectCount(enemy,"CHARM")==0 then
        local ex,ey=EntityGetFirstHitboxCenter(enemy)
        if ex and not RaytracePlatforms(x,eyeY,ex,ey) then
            local distance=(ex-x)^2+(ey-eyeY)^2
            local current=ComponentGetValue2(ai,"mGreatestPrey")
            local preferred=true
            if current~=0 and current~=id and EntityGetIsAlive(current) and EntityHasTag(current,"nh_decoy") then
                local cx,cy=EntityGetFirstHitboxCenter(current)
                if cx then
                    local other=(ex-cx)^2+(ey-cy)^2
                    preferred=distance<other or (distance==other and id<current) or RaytracePlatforms(ex,ey,cx,cy)
                end
            end
            if preferred then
                ComponentSetValue2(ai,"mGreatestPrey",id)
                ComponentSetValue2(ai,"mGreatestThreat",id)
                ComponentSetValue2(ai,"mHasFoundPrey",true)
            end
            if flight and distance<best and (ex-homeX)^2+(ey+6-homeY)^2<=72^2 then
                nearest,best=enemy,distance
            end
        end
    end
end
if flight then ComponentSetValue2(flight,"value_int",nearest) end
