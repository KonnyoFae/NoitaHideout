do
local positions={
    [1]={10,20,0,1,1}, [2]={10,20,0,1,1}, [3]={0,0,0,1,1}, [4]={0,0,0,1,1},
}
local sprites={
    [11]={z_index=0.8,image_file="custom/skin.xml"},
    [12]={z_index=0.79,image_file="custom/arm.xml",alpha=0.4,visible=true},
    [13]={z_index=-1.5,has_special_scale=true,special_scale_x=0.5,special_scale_y=0.5},
}
local direction={1,0}
local mount
local children={}
local function close(a,b) return math.abs(a-b)<0.00001 end
function EntityGetIsAlive(id) return positions[id]~=nil end
function EntityGetTransform(id) return unpack(positions[id]) end
function EntitySetTransform(id,x,y,angle,sx,sy) positions[id]={x,y,angle,sx,sy} end
function EntityRefreshSprite(id) assert(id>=20,"only the sword display can be refreshed") end
function EntityCreateNew() mount=(mount or 20)+1;positions[mount]={0,0,0,1,1};return mount end
function EntityAddTag() end
function EntityAddComponent2(id,kind,data) assert(kind=="SpriteComponent");sprites[id+100]=data;return id+100 end
function EntityAddChild(parent,child) children[parent]={child} end
function EntityKill(id) positions[id]=nil end
function EntityApplyTransform(id,x,y,angle,sx,sy)
    -- The native held-item refresh can replace the requested rotation.
    positions[id]={x,y,id==3 and -2.54 or angle,sx,sy}
end
function EntityGetAllChildren(id,tag)
    if id==1 and tag=="player_arm_r" then return {2} end
    if tag=="nh_katana_mount" then return children[id] or {} end
    return {}
end
function EntityGetFirstComponent(id,kind,tag)
    if kind=="SpriteComponent" then
        if id==1 and tag=="character" then return 11 end
        if id==2 then return 12 end
        if id==3 and tag=="enabled_in_hand" then return 13 end
    end
end
EntityGetFirstComponentIncludingDisabled=EntityGetFirstComponent
function ComponentGetValue2(id,key) return sprites[id][key] end
function ComponentSetValue2(id,key,value)
    assert(id==13 or id>=120,"weapon posing must never change the skin's sprite properties")
    sprites[id][key]=value
end
function EntityGetHotspot(id,tag,transformed)
    assert(tag=="hand" and transformed)
    if id==2 then
        local p=positions[id]
        return p[1]+math.cos(p[3])*5,p[2]+math.sin(p[3])*5
    end
end
NHProducts={aim=function() return direction[1],direction[2] end}
local visual=dofile("mods/noita_hideout/files/katana_visual.lua")

local x,y,a=visual.pose(1,3,"hf_blade",1)
assert(x==14 and y==17 and a==0)
assert(sprites[13].visible==false and positions[mount][3]==0)
assert(close(sprites[13].z_index,0.825))
assert(sprites[13].special_scale_x==0.5 and sprites[13].special_scale_y==0.5)
assert(positions[3][1]-56*sprites[13].special_scale_x<positions[1][1],"blade should extend behind the player")

direction={-1,0}
visual.pose(1,3,"hf_murasama",2)
assert(close(positions[3][3],math.pi))
assert(close(positions[mount][3],math.pi))
assert(sprites[13].special_scale_x==0.5 and sprites[13].special_scale_y==-0.5)
assert(close(positions[3][5],-1))

-- The native hand moves slightly while the sword remains at the waist mount.
visual.pose(1,3,"hf_murasama",3,{angle=0,handKick=0.1})
assert(close(positions[2][3],0.1))
assert(close(positions[3][2],17))
visual.reset(1)
assert(close(positions[2][3],0) and sprites[13].z_index==-1.5)
assert(sprites[13].visible and not EntityGetIsAlive(mount))
assert(sprites[12].image_file=="custom/arm.xml" and sprites[12].alpha==0.4 and sprites[12].visible)

-- Another controller's later update must survive our cleanup.
visual.pose(1,3,"hf_blade",4,{handKick=0.1})
positions[2]={40,50,0.7,1,1}
visual.reset()
assert(positions[2][1]==40 and positions[2][2]==50 and positions[2][3]==0.7)

-- Re-posing in the same frame never accumulates the arm offset.
visual.pose(1,3,"hf_blade",5,{handKick=0.1})
visual.pose(1,3,"hf_blade",5,{handKick=0.1})
assert(close(positions[2][3],0.8))
visual.reset()
assert(close(positions[2][3],0.7))

-- The relic uses the same waist mount and never replaces skin/arm graphics.
direction={1,0}
visual.pose(1,3,"dragon_king",6)
assert(sprites[mount+100].image_file=="mods/noita_hideout/files/items/dragon_king_sprite.xml")
assert(positions[mount][1]==14 and positions[mount][2]==17 and positions[mount][3]==0)
assert(close(sprites[mount+100].z_index,0.825))
direction={-1,0}
visual.pose(1,3,"dragon_king",7)
assert(positions[mount][1]==6 and positions[mount][2]==17 and close(positions[mount][3],math.pi))
assert(sprites[mount+100].special_scale_y==-0.5)
visual.reset()
assert(sprites[13].visible and not EntityGetIsAlive(mount))
assert(sprites[11].image_file=="custom/skin.xml" and sprites[12].image_file=="custom/arm.xml")

local loads=0
local barrier
function RaytracePlatforms(x,y,tx,ty)
    if barrier and x<barrier and tx>=barrier then
        return true,barrier,y+(ty-y)*(barrier-x)/(tx-x)
    end
    return false
end
function EntityLoad(path,lx,ly)
    assert(path=="mods/noita_hideout/files/katana_fx.xml")
    loads=loads+1
    return 4
end
local fx=dofile("mods/noita_hideout/files/katana_fx.lua")
assert(fx.spawn(1,2,0.3,"hf_blade",0.5,-1)==4)
assert(positions[4][1]==1 and positions[4][2]==2 and positions[4][3]==0.3)
assert(positions[4][4]==0.5 and positions[4][5]==-0.5)
assert(fx.spawn(0/0,2,0,"hf_blade",0.5)==nil and loads==1)
assert(fx.spawn(5,6,math.pi,"dragon_king",nil,1)==4 and loads==2)
assert(positions[4][1]==5 and positions[4][2]==6 and positions[4][3]==math.pi)
assert(positions[4][4]==0.75 and positions[4][5]==0.75)
assert(fx.spawn(5,6,0.5,"dragon_king",1,-1)==4 and positions[4][4]==1 and positions[4][5]==-1)
function EntityHasTag(id,tag) return id==4 and tag=="nh_katana_fx" end
fx.follow(4,12,8,0.5,1,-1)
assert(positions[4][1]==12 and positions[4][2]==8 and positions[4][5]==-1 and loads==3)
barrier=22
fx.follow(4,12,8,math.pi/4,1,-1)
local visible=positions[4][4]
assert(visible>0 and visible<1 and 12+visible*(64+15)/math.sqrt(2)<barrier)
barrier=nil
fx.follow(4,12,8,math.pi/4,1,-1)
assert(positions[4][4]==1 and positions[4][5]==-1)
EntityKill(4)
fx.follow(4,20,8,0.5,1,-1)
assert(not EntityGetIsAlive(4) and loads==3)
end
