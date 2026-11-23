local targets={}

function targets.hostile(player,target)
    return target~=player and not EntityHasTag(target,"nh_reinforcement")
        and not EntityHasTag(target,"noita_hideout_companion") and not EntityHasTag(target,"summon_player")
        and EntityGetFirstComponentIncludingDisabled(target,"GenomeDataComponent")
        and EntityGetHerdRelation(player,target)<40 and GameGetGameEffectCount(target,"CHARM")==0
end

-- Measure from the caster for attacks and from the player for defensive reactions.
function targets.nearest(player,x,y,radius,last,previous)
    local best,tx,ty
    local limit=radius*radius
    for _,id in ipairs(EntityGetInRadiusWithTag(x,y,radius,"homing_target") or {}) do
        if id~=last and id~=previous and targets.hostile(player,id) then
            local ex,ey=EntityGetFirstHitboxCenter(id)
            if ex then
                local distance=(ex-x)^2+(ey-y)^2
                if distance<=limit and not RaytracePlatforms(x,y,ex,ey) then
                    best,tx,ty,limit=id,ex,ey,distance
                end
            end
        end
    end
    return best,tx,ty
end

return targets
