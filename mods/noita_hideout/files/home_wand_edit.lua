NHHomeWandEdit={}
local tag="noita_hideout_home_wand_edit"
local path="mods/noita_hideout/files/home_wand_edit.xml"
local previous_player,previous_inside

local function apply(player,inside)
    if not player or player==0 or not EntityGetIsAlive(player) then return end
    local kept=false
    for _,child in ipairs(EntityGetAllChildren(player,tag) or {}) do
        if EntityHasTag(child,tag) then
            local effect=EntityGetFirstComponentIncludingDisabled(child,"GameEffectComponent")
            if inside and not kept and effect and effect~=0 then
                -- A short lease also expires if the mod is disabled between saves.
                ComponentSetValue2(effect,"frames",3)
                kept=true
            else
                EntityRemoveFromParent(child)
                EntityKill(child)
            end
        end
    end
    if inside and not kept then
        local x,y=EntityGetTransform(player)
        local child=EntityLoad(path,x,y)
        if child and child~=0 then EntityAddChild(player,child) end
    end
end

function NHHomeWandEdit.update(player,inside)
    if previous_player~=player then
        if previous_inside then apply(previous_player,false) end
        previous_inside=nil
    end
    inside=not not inside
    if inside or previous_inside~=inside then apply(player,inside) end
    previous_player,previous_inside=player,inside
end

-- Entity IDs belong to the world. On continue, update adopts or removes the
-- effect that was serialized with the player, using its private entity tag.
function NHHomeWandEdit.reset()
    previous_player,previous_inside=nil,nil
end
