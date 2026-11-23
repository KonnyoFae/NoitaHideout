local frame=600
local entities,nextID={},0
local failLoad=false
function GameGetFrameNum() return frame end
function EntityGetTransform(id) return entities[id].x,entities[id].y,0,1,1 end
function EntityLoad(_,x,y)
    if failLoad then return 0 end
    nextID=nextID+1
    entities[nextID]={x=x,y=y,c={value_int=0}}
    return nextID
end
function EntityGetFirstComponentIncludingDisabled(id) return entities[id].c end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function EntityKill(id) entities[id]=nil end
function EntityGetWithTag()
    local ids={}
    for id in pairs(entities) do if id~=100 then ids[#ids+1]=id end end
    return ids
end
function EntityGetInRadiusWithTag(x,y,r,tag)
    if tag~="nh_remote_station" then return {} end
    local ids={}
    for _,id in ipairs(EntityGetWithTag()) do local e=entities[id]; if (e.x-x)^2+(e.y-y)^2<=r*r then ids[#ids+1]=id end end
    return ids
end
entities[100]={x=12,y=18}
local body={aabb_min_x=-3,aabb_max_x=3,aabb_min_y=-12,aabb_max_y=4}
function EntityGetFirstComponent(id,kind)
    assert(id==100 and kind=="HitboxComponent")
    return body
end
function EntityGetFirstHitboxCenter(id)
    local x,y=EntityGetTransform(id)
    return x+(body.aabb_min_x+body.aabb_max_x)/2,y+(body.aabb_min_y+body.aabb_max_y)/2
end
local ground=true
local groundY=30
function RaytracePlatforms(x,y,tx,ty)
    assert(tx==x and ty-y==48)
    return ground,x,groundY
end
local R=dofile("mods/noita_hideout/files/terminals/remote.lua")
local charges=20
local shells=0
function LoadPixelScene(mask,visual,left,top,background,skipBiome,skipEdges,colors,z,repeatable)
    assert(mask=="mods/noita_hideout/files/terminals/shelter_materials.png" and visual=="")
    assert(background=="mods/noita_hideout/files/terminals/shelter_background.png" and z==50)
    assert(left==-24 and top==-6 and skipBiome and repeatable and charges==19)
    shells=shells+1
end
local function pay() charges=charges-1; return true end
ground=false; assert(not R.preview(100).valid and not R.deploy(100,pay) and charges==20)
ground=true; groundY=45 -- Landing here would stamp the ceiling through the player.
assert(not R.preview(100).valid and not R.deploy(100,pay) and charges==20 and shells==0)
assert(not R.preview(100,true).valid)
groundY=20 -- A ray can hit a slope above the bottom of the player's hitbox.
entities[100].x=-19.6
local slope=R.preview(100)
assert(slope.valid and slope.sceneX+36==-20 and slope.sceneY+36>18+body.aabb_max_y)
body.aabb_max_x=52
assert(not R.deploy(100,pay) and charges==20 and shells==0)
body.aabb_max_x=3
entities[100].x,groundY=12,30
local preview=R.preview(100); assert(preview.valid and preview.x==12 and preview.y==24.75)
assert(preview.width==72 and preview.height==40 and preview.x-preview.offsetX==-24 and preview.y-preview.offsetY==-6)
assert(preview.sceneX==preview.x-preview.offsetX and preview.sceneY==preview.y-preview.offsetY)
failLoad=true; assert(not R.deploy(100,pay) and charges==20)
failLoad=false; assert(not R.deploy(100,function() return false end) and #EntityGetWithTag()==0)
assert(shells==0)
assert(R.deploy(100,pay) and charges==19)
assert(shells==1)
local id=EntityGetWithTag()[1]
assert(R.inRange(100) and R.view()[1].text=="10:00")
assert(entities[id].x==preview.x and entities[id].y==preview.y)
assert(not R.preview(100).valid)
entities[100].x,entities[100].y=60,24.75; assert(R.inRange(100))
entities[100].x=61; assert(not R.inRange(100))
frame=600+25200
assert(R.view()[1].text=="3:00" and not R.view()[1].warning)
frame=frame+1
assert(R.view()[1].warning)
local a=R.view()[1].alpha; frame=frame+20; assert(R.view()[1].alpha~=a)
R=dofile("mods/noita_hideout/files/terminals/remote.lua")
assert(R.remaining(id)==10779)
frame=36600
assert(not R.inRange(100) and #R.view()==0)
R.update()
assert(#EntityGetWithTag()==0)
assert(shells==1)
print("Remote terminal: spawn/payment rollback, fixed 48px access, 10-minute lifetime, persistent deadline, countdown and red flashing passed.")
