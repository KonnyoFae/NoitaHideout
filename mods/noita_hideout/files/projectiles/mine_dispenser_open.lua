local dispenser=GetUpdatedEntityID()
local x,y=EntityGetTransform(dispenser)
local motion=EntityGetFirstComponentIncludingDisabled(dispenser,"VelocityComponent")
local hx,hy=x,y
local nx,ny=0,-1
if motion then
    local vx,vy=ComponentGetValue2(motion,"mVelocity")
    local speed=math.sqrt(vx*vx+vy*vy)
    if speed<1 then return end
    nx,ny=-vx/speed,-vy/speed
    local hit
    hit,hx,hy=RaytraceSurfaces(x,y,x-42*nx,y-42*ny)
    if not hit then return end
end

local ok,ux,uy=GetSurfaceNormal(hx+2*nx,hy+2*ny,8,12)
if ok then
    local length=math.sqrt(ux*ux+uy*uy)
    if length>0 and (not motion or ux*nx+uy*ny>0.3*length) then nx,ny=ux/length,uy/length end
end
if not motion then
    -- The contact helper also handles a surface that moved into the carrier.
    x,y=hx+3*nx,hy+3*ny
end

-- Aim at six separate points on the marked plane, compensating for the
-- scatter projectile's gravity. Shorten the flight under a low ceiling.
local clearance=math.max(3,(x-hx)*nx+(y-hy)*ny)
local seconds=math.min(0.6,0.8*math.sqrt(2*clearance/220))
local dir="mods/noita_hideout/files/projectiles/"
EntityLoad("mods/noita_hideout/files/pod_open_fx.xml",x,y)
for i=1,6 do
    local offset=(i-3.5)*48
    local id=EntityLoad(dir.."mine_scatter.xml",x,y)
    if id and id~=0 then
        local velocity=EntityGetFirstComponentIncludingDisabled(id,"VelocityComponent")
        if velocity then
            local vx=(hx-ny*offset-x)/seconds
            local vy=(hy+nx*offset-y)/seconds-0.5*220*seconds
            ComponentSetValue2(velocity,"mVelocity",vx,vy)
        end
    end
end
EntityKill(dispenser)
