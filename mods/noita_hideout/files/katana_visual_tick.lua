-- A save can contain a held blade's back-layer depth. Repair its world view
-- without depending on the controller's Lua locals after a drop or reload.
local weapon=GetUpdatedEntityID()
local owner=EntityGetRootEntity(weapon)
local inventory=owner~=weapon and EntityGetFirstComponentIncludingDisabled(owner,"Inventory2Component")
if inventory and ComponentGetValue2(inventory,"mActiveItem")==weapon then return end
local sprite=EntityGetFirstComponentIncludingDisabled(weapon,"SpriteComponent","enabled_in_hand")
if sprite then
    ComponentSetValue2(sprite,"visible",true)
    ComponentSetValue2(sprite,"z_index",-1.5)
end
for _,child in ipairs(EntityGetAllChildren(weapon,"nh_katana_mount") or {}) do EntityKill(child) end
