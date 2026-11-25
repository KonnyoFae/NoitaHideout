local field=GetUpdatedEntityID()
local inv=EntityGetFirstComponentIncludingDisabled(field,"MaterialInventoryComponent")
if not inv or GetMaterialInventoryMainMaterial(field,false)==0 then return end
local x,y=EntityGetTransform(field)
local outlet=EntityLoad("mods/noita_hideout/files/duster_outlet.xml",x,y)
if not outlet or outlet==0 then return end
-- The emitter draws only from the transferred stock. If the boundary is
-- obstructed, it can finish emptying at this location after the field expires.
for slot,amount in ipairs(ComponentGetValue2(inv,"count_per_material_type")) do
    if amount>0 then AddMaterialInventoryMaterial(outlet,CellFactory_GetName(slot-1),amount) end
end
RemoveMaterialInventoryMaterial(field,"")
