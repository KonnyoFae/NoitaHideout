local P={}
local function aura(player) return (EntityGetAllChildren(player,"nh_shield_poly") or {})[1] end
local function remove(player,child)
    if EntityHasTag(child,"nh_owns_poly_tag") then EntityRemoveTag(player,"polymorphable_NOT") end
    EntityRemoveFromParent(child)
    EntityKill(child)
end

-- Both sources share one bypassable effect. Older saves have an unmarked
-- shield aura with the same entity tag.
function P.set(player,source,enabled)
    local child=aura(player)
    if child and not EntityHasTag(child,"nh_poly_shield") and not EntityHasTag(child,"nh_poly_companion") then
        EntityAddTag(child,"nh_poly_shield")
    end
    if enabled then
        if not child then
            child=EntityCreateNew("nh_polymorph_protection")
            EntityAddTag(child,"nh_shield_poly")
            EntityAddComponent2(child,"InheritTransformComponent",{})
            EntityAddComponent2(child,"GameEffectComponent",{effect="PROTECTION_POLYMORPH",frames=-1,exclusivity_group=0})
            EntityAddChild(player,child)
            if not EntityHasTag(player,"polymorphable_NOT") then
                EntityAddTag(player,"polymorphable_NOT")
                EntityAddTag(child,"nh_owns_poly_tag")
            end
        end
        if not EntityHasTag(child,source) then EntityAddTag(child,source) end
    elseif child and EntityHasTag(child,source) then
        EntityRemoveTag(child,source)
        if not EntityHasTag(child,"nh_poly_shield") and not EntityHasTag(child,"nh_poly_companion") then remove(player,child) end
    end
end

function P.canMimic(player)
    local child=aura(player)
    if EntityHasTag(player,"polymorphable_NOT") and not (child and EntityHasTag(child,"nh_owns_poly_tag")) then return false end
    if GameGetGameEffectCount(player,"PROTECTION_POLYMORPH")>(child and 1 or 0) then return false end
    return true,child
end

function P.allowMimic(player)
    local allowed,child=P.canMimic(player)
    if allowed and child then remove(player,child) end
    return allowed
end
return P
