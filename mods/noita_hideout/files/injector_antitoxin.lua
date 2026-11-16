-- Toxic sludge is handled by the native protection. The separate POISON
-- status can live on the player or an attached entity alongside other effects.
local player=EntityGetParent(GetUpdatedEntityID())
if not player or player==0 or GameGetGameEffectCount(player,"POISON")==0 then return end
local function expirePoison(entity)
    for _,effect in ipairs(EntityGetComponent(entity,"GameEffectComponent") or {}) do
        if ComponentGetValue2(effect,"effect")=="POISON" and ComponentGetValue2(effect,"frames")>1 then
            ComponentSetValue2(effect,"frames",1)
        end
    end
end
expirePoison(player)
for _,child in ipairs(EntityGetAllChildren(player) or {}) do
    if not EntityGetFirstComponentIncludingDisabled(child,"ItemComponent")
        and not EntityGetFirstComponentIncludingDisabled(child,"DamageModelComponent") then expirePoison(child) end
end
