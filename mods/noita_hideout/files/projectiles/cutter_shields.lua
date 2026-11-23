local cutter=GetUpdatedEntityID()
local owner=EntityGetRootEntity(cutter)
if owner==cutter or not EntityGetIsAlive(owner) then return end
local x,y,angle=EntityGetTransform(cutter)
local dx,dy=math.cos(angle),math.sin(angle)
local laser=EntityGetFirstComponent(cutter,"LaserEmitterComponent")
if not laser then return end
local length=ComponentObjectGetValue2(laser,"laser","max_length")
local hit,hx,hy=RaytraceSurfaces(x,y,x+dx*length,y+dy*length)
if hit then length=math.max(0,(hx-x)*dx+(hy-y)*dy) end

-- Intersect the exposed part of the beam with the shield's circumference.
-- A partial shield only loses energy on its active arc.
local function crosses(sx,sy,radius,facing,scale,sector)
    local ox,oy=sx-x,sy-y
    local along,across=ox*dx+oy*dy,ox*dy-oy*dx
    local chord=radius*radius-across*across
    if chord<0 then return false end
    local half=math.sqrt(chord)
    local threshold=radius*math.cos(math.rad(sector)*0.5)
    local fx,fy=math.cos(facing),math.sin(facing)
    if scale<0 then fx,fy=-fx,-fy end
    for _,t in ipairs({along-half,along+half}) do
        if t>=-1 and t<=length and (sector>=360 or (t*dx-ox)*fx+(t*dy-oy)*fy>=threshold) then return true end
    end
    return false
end

-- The native EnergyShieldComponent supports radii up to 100 world pixels.
for _,id in ipairs(EntityGetInRadiusWithTag(x,y,length+100,"energy_shield") or {}) do
    local host=EntityGetRootEntity(id)
    local shield=EntityGetFirstComponent(id,"EnergyShieldComponent")
    if shield and host~=owner and EntityGetFirstComponent(host,"GenomeDataComponent")
        and EntityGetHerdRelationSafe(owner,host)<40 then
        local sx,sy,facing,scale=EntityGetTransform(id)
        if crosses(sx,sy,ComponentGetValue2(shield,"radius"),facing,scale,ComponentGetValue2(shield,"sector_degrees")) then
            local energy=ComponentGetValue2(shield,"energy")
            if energy>0 then ComponentSetValue2(shield,"energy",math.max(0,energy-0.5)) end
        end
    end
end
