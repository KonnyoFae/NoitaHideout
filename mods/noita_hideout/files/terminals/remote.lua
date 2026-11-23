local R={duration=36000,radius=48}
local tag="nh_remote_station"
local shelterMask="mods/noita_hideout/files/terminals/shelter_materials.png"
local shelterBackground="mods/noita_hideout/files/terminals/shelter_background.png"
local shelterWidth,shelterHeight,floorRow=72,40,36
-- The central 48x29 pixels (columns 12..59, rows 7..35) are air in shelterLv1.
local interiorHalfWidth,interiorHeight=24,29
local function clock(id) return EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_remote_deadline") end
function R.remaining(id)
    local c=clock(id)
    return c and math.max(0,ComponentGetValue2(c,"value_int")-GameGetFrameNum()) or 0
end
function R.expire(id)
    if R.remaining(id)>0 then return false end
    EntityKill(id)
    return true
end
function R.update()
    for _,id in ipairs(EntityGetWithTag(tag) or {}) do R.expire(id) end
end
function R.inRange(player,x,y)
    if not player then return false end
    if not x then x,y=EntityGetTransform(player) end
    for _,id in ipairs(EntityGetInRadiusWithTag(x,y,R.radius,tag) or {}) do
        if R.remaining(id)>0 then return true end
    end
    return false
end
local function playerBounds(player)
    local px,py,_,sx,sy=EntityGetTransform(player)
    local box=EntityGetFirstComponent(player,"HitboxComponent")
    if not box then return px,py-4,3,8 end -- Vanilla standing bounds.
    local cx,cy=EntityGetFirstHitboxCenter(player)
    local width=ComponentGetValue2(box,"aabb_max_x")-ComponentGetValue2(box,"aabb_min_x")
    local height=ComponentGetValue2(box,"aabb_max_y")-ComponentGetValue2(box,"aabb_min_y")
    return cx,cy,width*math.abs(sx)/2,height*math.abs(sy)/2
end

function R.preview(player,blocked)
    local cx,cy,halfWidth,halfHeight=playerBounds(player)
    local x=math.floor(cx+0.5)
    local hit,_,ground=RaytracePlatforms(x,cy,x,cy+48)
    local belowFeet=math.ceil(cy+halfHeight)+1
    local floorY=math.max(belowFeet,math.floor((hit and ground or belowFeet)+0.5))
    local left,top=x-shelterWidth/2,floorY-floorRow
    local y=floorY-5.25
    local view={x=x,y=y,sceneX=left,sceneY=top,kind="remote_terminal",valid=false,
        icon="mods/noita_hideout/files/terminals/comms_small.png",width=shelterWidth,height=shelterHeight,
        offsetX=x-left,offsetY=y-top,iconWidth=24,iconHeight=24,iconOffsetX=12,iconOffsetY=18.75}
    if blocked or not hit or not ground or math.abs(cx-x)+halfWidth+1>interiorHalfWidth
        or cy-halfHeight-1<floorY-interiorHeight then return view end
    for _,other in ipairs({"nh_remote_station","nh_home_terminal","nh_landmark_terminal","noita_hideout_mountain_storage","nh_deployed_turret"}) do
        for _,id in ipairs(EntityGetInRadiusWithTag(x,y,84,other) or {}) do
            local ox,oy=EntityGetTransform(id)
            local clearance=other==tag and shelterWidth or shelterWidth/2+12
            if math.abs(ox-x)<clearance and math.abs(oy-y)<shelterHeight then return view end
        end
    end
    view.valid=true
    return view
end
function R.heldPreview(player,blocked)
    local held=NHNative.held(player)
    if held and NHProducts.linkKind(held) then return R.preview(player,blocked) end
end
function R.deploy(player,pay)
    local preview=R.preview(player)
    if not preview or not preview.valid then return false,"blocked" end
    local x,y=preview.x,preview.y
    local id=EntityLoad("mods/noita_hideout/files/terminals/remote.xml",x,y)
    if not id or id==0 then return false,"spawn" end
    local c=clock(id)
    if not c then EntityKill(id); return false,"spawn" end
    ComponentSetValue2(c,"value_int",GameGetFrameNum()+R.duration)
    -- Create first so failed spawning never consumes a charge; failed payment removes it.
    if not pay() then EntityKill(id); return false,"payment" end
    LoadPixelScene(shelterMask,"",preview.sceneX,preview.sceneY,shelterBackground,true,false,{},50,true)
    return true
end
function R.view()
    local views={}
    for _,id in ipairs(EntityGetWithTag(tag) or {}) do
        local left=R.remaining(id)
        if left>0 then
            local x,y=EntityGetTransform(id)
            local seconds=math.ceil(left/60)
            views[#views+1]={x=x,y=y-23,text=("%d:%02d"):format(math.floor(seconds/60),seconds%60),
                warning=left<10800,alpha=left<10800 and (math.floor(GameGetFrameNum()/20)%2==0 and 1 or 0.25) or 1}
        end
    end
    return views
end
return R
