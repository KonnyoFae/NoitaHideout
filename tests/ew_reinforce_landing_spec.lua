local bounds=true
local material=function() return false end
local bodies={}
function DoesWorldExistAt() return bounds end
function RaytraceSurfacesAndLiquiform(x,y,tx,ty)
    assert(x==tx)
    for n=math.min(y,ty),math.max(y,ty) do
        if material(x,n) then return true,x,n end
    end
    return false
end
function EntityGetInRadiusWithTag(x,y,r,tag)
    local near={}
    for _,b in ipairs(bodies) do
        if b[tag] and (x-b.x)^2+(y-b.y)^2<=r^2 then near[#near+1]=b end
    end
    return near
end
function EntityHasTag(b,t) return b[t] end
local pod=dofile("mods/noita_hideout/files/resupply.lua")
local function origin()
    local s=assert(pod.reviveSite(80,-20))
    assert(s.x==80 and s.y==-20 and s.start<s.y)
    return s
end
-- Open air, a solid floor and disappearing floors all allow opening the
-- capsule at the same height. A close ceiling only shortens the descent.
origin()
material=function(_,y) return y>=-13 end;origin()
material=function(_,y) return y<=-38 end;assert(origin().start> -38)
material=function() return false end;origin()
-- A liquid/solid area covering the body moves the opening to a clear
-- neighbour; search and contact use the full capsule footprint.
material=function(x,y) return x>=74 and x<=86 and y>=-36 and y<=-10 end
local s=assert(pod.reviveSite(80,-20))
assert((s.x~=80 or s.y~=-20) and pod.reviveSpace(s.x,s.y))
material=function() return true end;assert(not pod.reviveSite(80,-20))
material=function() return false end;bounds=false;assert(not pod.reviveSite(80,-20))
bounds=true
local other={x=80,y=-20,ew_client=true};bodies={other}
assert(not pod.reviveSpace(80,-20) and pod.reviveSpace(80,-20,other))
s=assert(pod.reviveSite(80,-20));assert((s.x-80)^2+(s.y+20)^2>13^2)
other.nh_ew_waiting=true;origin()
print("EW player landing: ground and midair opening, clearance, occupied or unloaded areas and alternative sites passed.")
