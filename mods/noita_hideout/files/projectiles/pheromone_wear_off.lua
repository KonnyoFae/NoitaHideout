local effect=GetUpdatedEntityID()
local charm=EntityGetFirstComponent(effect,"GameEffectComponent")
if not charm or ComponentGetValue2(charm,"frames")>5 then return end
local target=EntityGetParent(effect)
if target and target~=0 then
    -- Release the splash stain with the timed hit. Standing in the puddle can stain the creature again.
    EntityRemoveStainStatusEffect(target,"CHARM",0)
end
