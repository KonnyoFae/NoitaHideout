local M={}
local items="mods/noita_hideout/files/items/"
local groundTag="nh_support_ground_art"

-- Physics image cells also paint the world. Upgrade the image used on the
-- next native body build without recreating a live, possibly moving body.
function M.repair(entity,kind)
    local gun=NHGuns.types[kind]
    if not gun or not gun.displaySprite then return false end
    local overlay=EntityGetFirstComponentIncludingDisabled(entity,"SpriteComponent",groundTag)
    if overlay then return false end
    local shape=EntityGetFirstComponentIncludingDisabled(entity,"PhysicsImageShapeComponent")
    local prefix=items..kind
    if not shape or ComponentGetValue2(shape,"image_file")~=prefix.."_world.png" then return false end
    local inWorld=EntityGetRootEntity(entity)==entity
    local pivot=gun.groundPivot or 12
    overlay=EntityAddComponent2(entity,"SpriteComponent",{_tags="enabled_in_world,"..groundTag,
        _enabled=inWorld,image_file=gun.displaySprite,offset_x=pivot,offset_y=pivot,
        has_special_scale=true,special_scale_x=0.5,special_scale_y=0.5,z_index=-1})
    if not overlay or overlay==0 then return false end
    ComponentSetValue2(shape,"image_file",prefix.."_shape.png")
    return true
end

-- Only needed in worlds that may stream the old templates. Newly produced
-- weapons already have the ground sprite, including warehouse withdrawals.
function M.near(player)
    local x,y=EntityGetTransform(player)
    local converted=0
    for _,entity in ipairs(EntityGetInRadiusWithTag(x,y,320,"nh_support_weapon") or {}) do
        if EntityGetRootEntity(entity)==entity
            and not EntityGetFirstComponentIncludingDisabled(entity,"SpriteComponent",groundTag) then
            local item=EntityGetFirstComponent(entity,"ItemComponent")
            local name=item and ComponentGetValue2(item,"item_name")
            local kind=name and name:match("^%$nh_hideout_(.+)$")
            if kind and EntityHasTag(entity,"noita_hideout_"..kind) and M.repair(entity,kind) then
                converted=converted+1
                if converted==8 then break end
            end
        end
    end
end
return M
