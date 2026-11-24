local root="mods/noita_hideout/files/bow/"
local shoot=dofile(root.."shoot.lua")
local targets=dofile("mods/noita_hideout/files/companions/targets.lua")
local bow={}
local started,wasDown,lastMode
local function pose(gun,clock,name,frame)
    ComponentSetValue2(clock,"value_float",frame)
    local sprite=EntityGetFirstComponentIncludingDisabled(gun,"SpriteComponent","enabled_in_hand")
    if sprite and ComponentGetValue2(sprite,"rect_animation")~=name then
        ComponentSetValue2(sprite,"rect_animation",name)
        ComponentSetValue2(sprite,"next_rect_animation",name)
        EntityRefreshSprite(gun,sprite)
    end
end

function bow.reset()
    started,wasDown,lastMode=nil,false,nil
end

local function arrow(player,mode,level,x,y,dx,dy)
    local tier=level+1
    if mode.id=="fire" then
        if level==3 then return shoot.volley(player,"cluster",x,y,dx,dy,550,1,0,nil,true) end
        local enemy=targets.nearest(player,x,y,140)
        return shoot.volley(player,"rapid",x,y,dx,dy,640,tier,math.rad(7),function(id)
            local h=EntityGetFirstComponentIncludingDisabled(id,"HomingComponent")
            ComponentSetValue2(h,"predefined_target",enemy or 0)
        end,true)
    elseif mode.id=="move" then
        local long=level==0
        return shoot.volley(player,long and "teleport_long" or "teleport_short",x,y,dx,dy,long and 1600 or 960,1,0,nil,true)
    end
    local scan=mode.id=="scout"
    local function configure(id,p)
        local data=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_bow_field")
        ComponentSetValue2(data,"value_int",player)
        ComponentSetValue2(data,"value_float",tier)
        if scan then
            ComponentSetValue2(p,"lifetime",mode.life[tier])
            ComponentSetValue2(p,"bounces_left",mode.bounces[tier])
            local ring=EntityGetFirstComponentIncludingDisabled(id,"SpriteComponent","nh_bow_ring")
            ComponentSetValue2(ring,"special_scale_x",mode.radius[tier]/32)
            ComponentSetValue2(ring,"special_scale_y",mode.radius[tier]/32)
        end
    end
    return shoot.volley(player,scan and "scan" or "support",x,y,dx,dy,scan and (level==3 and 90 or 210) or 480,1,0,configure,true)
end

function bow.update(player,gun,mag,index,points,frame,blocked)
    local clock=EntityGetFirstComponentIncludingDisabled(gun,"VariableStorageComponent","nh_bow_clock")
    local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    if not clock or not controls then bow.reset(); return points end
    local down=ComponentGetValue2(controls,"mButtonDownFire")
    local pressed=down and not wasDown
    wasDown=down
    if blocked or (lastMode and lastMode~=index) then
        started,lastMode=nil,index
        pose(gun,clock,"default",frame)
        return points
    end
    lastMode=index
    local ready=ComponentGetValue2(clock,"value_int")
    if pressed and frame>=ready then started=frame end
    if not started then
        pose(gun,clock,frame<ready and "release" or "default",frame)
        return points
    end
    local mode=NHFirearms.bowModes[index]
    local elapsed=frame-started
    local level=math.min(#mode.costs-1,math.floor(elapsed/30))
    local cost=mode.costs[level+1]
    local x,y=EntityGetTransform(player)
    local dx,dy=NHProducts.aim(player,x,y)
    if dx and not RaytracePlatforms(x,y,x+dx*7,y+dy*7) then x,y=x+dx*7,y+dy*7 end
    if down then
        pose(gun,clock,"draw_"..level,frame)
        if dx and mode.id=="move" and points>=1 and elapsed>0 and elapsed%6==0 then
            shoot.volley(player,"drill",x,y,dx,dy,1400,1,0,nil,false)
        end
        return points,level
    end
    started=nil
    if cost>points or not dx then
        pose(gun,clock,"default",frame)
        return points,nil,cost>points
    end
    if arrow(player,mode,level,x,y,dx,dy) then
        points=points-cost
        ComponentSetValue2(mag,"value_int",points)
        ComponentSetValue2(clock,"value_int",frame+8)
        pose(gun,clock,"release",frame)
    else pose(gun,clock,"default",frame) end
    return points
end
return bow
