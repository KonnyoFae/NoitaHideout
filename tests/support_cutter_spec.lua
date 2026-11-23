local root="mods/noita_hideout/files/projectiles/"
local missile,owner,cutter,move,shot=1,2,3,{},{}
local current=missile
local x,y,angle=14,18,0.2
local loaded,parent,placed,wall
local shields={}
function GetUpdatedEntityID() return current end
function EntityGetFirstComponentIncludingDisabled(id,kind)
    if id==missile then return kind=="ProjectileComponent" and shot or move end
end
function ComponentGetValue2(c,k)
    local v=c[k]
    if type(v)=="table" then return unpack(v) end
    return v
end
function ComponentSetValue2(c,k,v) c[k]=v end
local artillery=false
function EntityHasTag(id,tag) return id==missile and tag=="nh_strike_missile" and artillery end
function EntityGetIsAlive(id) return id==owner end
function DoesWorldExistAt() return true end
function EntityGetTransform(id)
    if shields[id] then local s=shields[id];return s.x,s.y,s.facing or 0,1,1 end
    if id==cutter then return unpack(placed) end
    return x,y,angle
end
function EntityLoad(path,ax,ay)
    assert(path==root.."missile_cutter.xml" and ax==x and ay==y)
    loaded=(loaded or 0)+1;return cutter
end
function EntityAddChild(id,child) assert(child==cutter);parent=id end
function EntitySetTransform(id,ax,ay,a) assert(id==cutter);placed={ax,ay,a} end
shot={lifetime=100,mWhoShot=owner}
move={mVelocity={-30,40},mPrevVelocity={30,0}}
dofile(root.."missile_impact.lua")
assert(parent==owner and loaded==1 and math.abs(placed[3]-math.atan2(40,-30))<0.00001)
move.mVelocity={0,0};move.mPrevVelocity={0,-70}
dofile(root.."missile_impact.lua")
assert(loaded==2 and math.abs(placed[3]+math.pi/2)<0.00001)
shot.lifetime=0;dofile(root.."missile_impact.lua")
assert(loaded==2)
artillery=true;dofile(root.."missile_impact.lua");assert(loaded==3 and parent==owner)
shot.lifetime=10;shot.mWhoShot=0;dofile(root.."missile_impact.lua");assert(loaded==3)

current=cutter;placed={0,0,0}
function EntityGetFirstComponent(id,kind)
    if id==cutter and kind=="LaserEmitterComponent" then return 71 end
    if kind=="EnergyShieldComponent" then return shields[id] end
    if kind=="GenomeDataComponent" then return 1 end
end
function ComponentObjectGetValue2(id,obj,k) assert(id==71 and obj=="laser" and k=="max_length"); return 64 end
function EntityGetRootEntity(id) return id==cutter and parent or shields[id].host end
function EntityGetHerdRelationSafe(a,b) return b==5 and 10 or 100 end
function RaytraceSurfaces() if wall then return true,wall,0 end;return false end
function EntityGetInRadiusWithTag(_,_,_,tag)
    assert(tag=="energy_shield")
    local list={};for id in pairs(shields) do list[#list+1]=id end;return list
end
local function add(id,ax,ay,host,sector)
    shields[id]={x=ax,y=ay,host=host,radius=6,energy=1.5,sector_degrees=sector or 360}
end
add(11,26,0,5);add(12,-20,0,5);add(13,25,20,5);add(14,40,0,owner);add(15,40,0,6)
add(16,58,0,5);add(17,51,0,5,90)
wall=50;dofile(root.."cutter_shields.lua")
assert(shields[11].energy==1)
for i=12,17 do assert(shields[i].energy==1.5) end
shields[17].facing=math.pi;dofile(root.."cutter_shields.lua");assert(shields[17].energy==1)
wall=nil;dofile(root.."cutter_shields.lua");assert(shields[16].energy==1)
