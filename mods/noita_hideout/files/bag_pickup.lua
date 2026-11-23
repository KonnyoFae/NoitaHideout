-- GamePickUpInventoryItem can call this while a withdrawal is still staged.
-- Resolve ownership and stack counts after the inventory and profile updates.
function item_pickup(item,owner)
    if EntityHasTag(owner,"player_unit") then
        EntityAddTag(item,"nh_merge_pickup")
        EntityAddTag(owner,"nh_has_merge_pickup")
    end
end
