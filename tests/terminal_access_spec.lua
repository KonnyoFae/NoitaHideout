local access=dofile("mods/noita_hideout/files/terminals/access.lua")
local station=dofile("mods/noita_hideout/files/terminals/access.lua")
local x,y=10,20
function EntityGetTransform() return x,y end
local visits=0
local function resolve(player,px,py,hx,hy)
    visits=visits+1
    return px==hx and py==hy,player==1,"landmark",false
end
local function at(player,hx,hy) return access.access(player,hx,hy,resolve) end

access.duringUpdate(function()
    local near,atStation,name,remote=at(1,10,20)
    assert(near and atStation and name=="landmark" and not remote)
    assert(at(1,10,20) and visits==1)
    x=11;assert(not at(1,10,20) and visits==2)
    assert(at(1,11,20) and visits==3)
    assert(at(2,11,20) and visits==4)
    station.invalidateAccess();at(2,11,20);assert(visits==5)
    access.duringUpdate(function() at(2,11,20);assert(visits==6) end)()
    at(2,11,20);assert(visits==7)
end)()

-- Pre- and post-update can see different terminals even in the same frame.
access.duringUpdate(function() at(2,11,20);assert(visits==8) end)()
assert(not pcall(access.duringUpdate(function() at(2,11,20);error("probe") end)))
at(2,11,20);at(2,11,20);assert(visits==11)
print("Terminal access: repeated queries, deployment, movement, nested updates and error cleanup passed.")
