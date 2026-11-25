local outlet=GetUpdatedEntityID()
local inventory=EntityGetFirstComponentIncludingDisabled(outlet,"MaterialInventoryComponent")
if not inventory or GetMaterialInventoryMainMaterial(outlet,false)==0 then EntityKill(outlet); return end
local x,y=EntityGetTransform(outlet)
local directions={}
for i=0,7 do
    local angle=i*math.pi/4
    local dx,dy=math.cos(angle),math.sin(angle)
    local ox,oy=x+dx*87,y+dy*87
    if not RaytraceSurfacesAndLiquiform(ox,oy,ox+dx*3,oy+dy*3) then
        directions[#directions+1]={ox,oy,dx,dy}
    end
end
-- A sealed rim keeps its bounded material store until an opening exists.
if #directions==0 then return end
local counts=ComponentGetValue2(inventory,"count_per_material_type")
for slot,count in ipairs(counts) do
    if count>0 then
        local material=CellFactory_GetName(slot-1)
        for i,d in ipairs(directions) do
            local n=math.floor(count/#directions)+(i<=count%#directions and 1 or 0)
            if n>0 then GameCreateParticle(material,d[1],d[2],n,d[3]*65,d[4]*65,false,false,true) end
        end
    end
end
RemoveMaterialInventoryMaterial(outlet,"")
EntityKill(outlet)
