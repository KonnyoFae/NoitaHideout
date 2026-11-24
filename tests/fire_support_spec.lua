-- Exercise the same Ctrl, mapped direction, wheel and fire path as the hooks.
dofile("mods/noita_hideout/files/store.lua")
local support=dofile("mods/noita_hideout/files/fire_support.lua")
local frame,held=100,8
local ctrl,pressCtrl,click,pressed,wheel=false,false,false,false,nil
local enemy,alive,loaded=true,true,true
local targetX,targetY=60,0
local normalX,normalY=-1,0
local gap,rocketAlive=nil,true
local lastShot,velocity,projectile
local c,box={enabled=true,input_latency_frames=0,mButtonFrameDown=-1}, {aabb_min_x=-4,aabb_max_x=4,aabb_min_y=-4,aabb_max_y=4}
local rawKeys={}
local body,platform,shooter={is_on_ground=true,mVelocity={70,12}},{mShouldCrouch=false},{eating_cells_per_frame=4,eating_delay_frames=30}
local lowCeiling=false
local rocket,shots,killed,paid=0,0,0,0
local failCommit,failSpawn=false,false
local state={levels={support=1},materials={gunpowder=100},resources={strike_logistics=100},gearLink={id=10,item={kind="data_link"}}}
local abilities={{mNextFrameUsable=0},{mNextFrameUsable=100000}}
function GameGetAllInventoryItems() return {1,2,8} end
function GameGetFrameNum() return frame end
function GlobalsGetValue(_,default) return default end
function EntityGetFirstComponentIncludingDisabled(id,kind)
    assert(id~=100 or kind~="SpriteComponent","support must leave player rendering to the native animator")
    if kind=="ControlsComponent" then return c end
    if id==100 and kind=="CharacterDataComponent" then return body end
    if id==100 and kind=="CharacterPlatformingComponent" then return platform end
    if id==100 and kind=="PlatformShooterPlayerComponent" then return shooter end
    if kind=="AbilityComponent" then return abilities[id] end
    if kind=="ItemComponent" then return {inventory_slot=(id-1)%4} end
    if id==rocket and kind=="ProjectileComponent" then return projectile end
    if id==rocket and kind=="VelocityComponent" then return velocity end
end
function EntityGetFirstComponent(id,kind)
    assert(id~=100 or kind~="SpriteComponent","support must leave player rendering to the native animator")
    if kind=="HitboxComponent" then return box end
end
function EntityGetAllChildren(id,tag)
    if tag then return {} end
    if id==100 then return {101} end
    return {1,2,3,4,5,6,7,8}
end
function EntityGetName() return "inventory_quick" end
function ComponentGetValue2(component,field)
    if component==body and field=="mVelocity" then return unpack(body.mVelocity) end
    return component[field]
end
function ComponentSetValue2(component,field,value,second)
    assert(component~=c or field~="enabled","support must never toggle the player's input switch")
    component[field]=second and {value,second} or value
end
function ComponentObjectSetValue2(component,object,field,value) component[field]=value end
function GameGetIsGamepadConnected() return false end
function DEBUG_GetMouseWorld() return -normalX*90,-normalY*90 end
local shellX,shellY
local playerX,playerY=0,0
function EntityGetTransform(id)
    if id==rocket then return shellX,shellY,0,1,1 end
    if id==100 then return playerX,playerY end
    return 0,0
end
function EntityApplyTransform(id,x,y) assert(id==rocket); shellX,shellY=x,y end
function EntityGetFirstHitboxCenter() return targetX,targetY end
function EntityGetInRadiusWithTag() return enemy and {77} or {} end
function EntityHasTag(id,tag)
    return (tag=="enemy" and id==77) or (tag=="wand" and abilities[id]~=nil)
end
function EntityGetIsAlive(id)
    return (id~=77 or alive) and (id~=rocket or rocketAlive)
end
function RaytraceSurfaces(x,y,tx,ty)
    local a,b=90+normalX*x+normalY*y,90+normalX*tx+normalY*ty
    if gap and (a>=gap or b>=gap) then
        if a>=gap then return true,x,y end
        local t=(gap-a)/(b-a)
        return true,x+t*(tx-x),y+t*(ty-y)
    end
    if a<=0 then return true,x,y end
    if b>0 then return false end
    local t=a/(a-b)
    return true,x+t*(tx-x),y+t*(ty-y)
end
function GetSurfaceNormal() return true,normalX,normalY end
function DoesWorldExistAt() return loaded end
function EntityLoad()
    if failSpawn then return 0 end
    rocket=rocket+1
    rocketAlive=true
    projectile,velocity={},{}
    return rocket
end
function GameShootProjectile(player,x,y,tx,ty,id)
    assert(player==100 and id==rocket)
    shellX,shellY=6,0 -- emulate registration displacing the entity beside the player
    lastShot={x=x,y=y,tx=tx,ty=ty}
    shots=shots+1
end
function EntityRemoveComponent() end
function EntityKill(id) killed=killed+1 end
function InputIsKeyJustDown(code) return code==224 and pressCtrl end
function InputIsKeyDown(code) return (code==224 and ctrl) or rawKeys[code] or false end
function InputIsMouseButtonJustDown(code) return (code==1 and click) or code==wheel end
function InputIsMouseButtonDown(code) return code==1 and pressed end
NHNative={held=function() return held end,kind=function() end}
NHTransfers={item_kind=function(id) return id<=4 and "wand" or "other" end}
NHProducts={aim=function() return 1,0 end}
local function step(direction,nativeUpdate,blocked)
    frame=frame+1
    for _,key in ipairs({"Up","Down","Left","Right"}) do c["mButtonDown"..key]=key==direction end
    local owned=support.input(state,100,blocked or false)
    if nativeUpdate then nativeUpdate() end
    platform.mShouldCrouch=lowCeiling or (body.is_on_ground and c.mButtonDownDown)
    support.finishInput()
    pressCtrl,click,wheel=false,false,nil
    return owned
end
local function view() return support.view(state,100) end
local function open()
    ctrl,pressCtrl=true,true
    assert(step() and view().menu.category==2)
end
do
    local steps,eaten=0,0
    local function resample()
        -- A held movement binding and Eat can be sampled again after the Lua pre-hook.
        local samples=((c.mButtonDownDelayLineJump or 0)*2+1)%2^32
        c.mButtonDownDelayLineJump=samples
        if c.enabled and math.floor(samples/2^c.input_latency_frames)%2==1 then steps=steps+1 end
        local downLine=((c.mButtonDownDelayLineDown or 0)*2+(rawKeys[22] and 1 or 0))%2^32
        c.mButtonDownDelayLineDown=downLine
        c.mButtonDownDown=math.floor(downLine/2^c.input_latency_frames)%2==1
        -- Model one edible pixel that passes the native random check. A zero
        -- quota still admits the first pixel once the crouch delay has elapsed.
        if c.mButtonDownDown and frame-c.mButtonFrameDown>shooter.eating_delay_frames
            and 0<=shooter.eating_cells_per_frame then eaten=eaten+1 end
    end
    -- Holding only Ctrl must not feed a phantom Down into the command menu.
    open()
    for _=1,90 do
        assert(step(nil,resample) and view().menu.level==1)
        assert(platform.mShouldCrouch and not c.mButtonDownDown and c.mButtonDownDelayLineDown==0)
        assert(eaten==0,"holding Ctrl alone crossed the native eating delay")
    end
    ctrl=false; step()
    assert(not platform.mShouldCrouch and c.enabled and eaten==0 and steps==0)
    body.mVelocity={70,12}
    open()
    assert(platform.mShouldCrouch and c.input_latency_frames==0)
    assert(body.mVelocity[1]==0 and body.mVelocity[2]==12)
    rawKeys[22]=true
    c.mButtonDownEat,c.mButtonDownJump,c.mButtonDownFly=true,true,true
    assert(step("Down",function()
        assert(c.mButtonDownDown and c.mButtonFrameDown==frame-1 and not c.mButtonDownEat and c.mButtonFrameEat==-1)
        assert(not c.mButtonDownJump and not c.mButtonDownFly and c.mButtonDownDelayLineFly==0)
        resample()
    end))
    assert(view().menu.level==2 and steps==0 and eaten==0 and shooter.eating_cells_per_frame==4)
    assert(step(nil,resample) and view().menu.project==1)
    for _=1,180 do assert(step(nil,resample)) end
    assert(platform.mShouldCrouch and eaten==0 and steps==0)
    ctrl=false
    assert(not step(nil,resample) and c.enabled and platform.mShouldCrouch)
    assert(steps==1 and eaten==0) -- release Ctrl first, keep holding S
    for _=1,90 do assert(not step(nil,resample) and eaten==0) end
    rawKeys[22]=nil
    step()
    assert(not platform.mShouldCrouch)
    rawKeys[22],c.mButtonDownEat,c.mButtonFrameDown=true,true,frame+1
    for _=0,shooter.eating_delay_frames do assert(not step("Down",resample) and eaten==0) end
    assert(not step("Down",resample) and c.mButtonDownEat and eaten==1)
    rawKeys[22],c.mButtonDownEat=nil,false
    step()

    -- Release S before Ctrl. Only the synthetic crouch should remain until Ctrl is up.
    open()
    rawKeys[22]=true; step("Down",resample)
    rawKeys[22]=nil
    for _=1,90 do assert(step(nil,resample) and platform.mShouldCrouch and eaten==1) end
    ctrl=false
    assert(not step(nil,resample) and not platform.mShouldCrouch and eaten==1)

    -- A rebound Down may only be present in the delay line on the Ctrl-release tick.
    open()
    ctrl=false
    c.mButtonDownDelayLineDown=1
    assert(not step(nil,function()
        assert(c.mButtonFrameDown==frame-1 and shooter.eating_cells_per_frame==0)
    end))
    assert(not step("Down",function() assert(c.mButtonFrameDown==frame-1) end))
    assert(not step(nil,function() assert(shooter.eating_cells_per_frame==4) end))

    -- Preserve a player's instant-eating setting outside support.
    shooter.eating_delay_frames=0
    open()
    assert(step(nil,function()
        assert((frame+1)-c.mButtonFrameDown<=shooter.eating_delay_frames)
        resample()
    end) and eaten==1 and shooter.eating_delay_frames==0)
    assert(step(nil,function() shooter.eating_delay_frames=30 end))
    ctrl=false; step()
    assert(shooter.eating_delay_frames==30)

    body.is_on_ground=false
    open()
    assert(not platform.mShouldCrouch)
    body.is_on_ground=true
    step("Right")
    assert(platform.mShouldCrouch)
    body.is_on_ground=false
    step(); step()
    assert(not platform.mShouldCrouch)
    body.is_on_ground=true
    step(); step()
    assert(platform.mShouldCrouch)
    assert(not step(nil,nil,true) and not platform.mShouldCrouch)
    assert(shooter.eating_cells_per_frame==4)
    ctrl=false; step()

    lowCeiling=true
    open()
    rawKeys[22]=true
    assert(step() and view().menu.level==2 and not c.mButtonDownDown)
    rawKeys[22]=nil
    local link=state.gearLink
    state.gearLink=nil
    assert(not step() and platform.mShouldCrouch)
    lowCeiling=false
    state.gearLink=link
    ctrl=false; step()

    -- An interrupted hook restores only the latency we borrowed.
    ctrl,pressCtrl=true,true
    assert(support.input(state,100,false) and c.input_latency_frames==1)
    support.reset()
    assert(c.input_latency_frames==0 and not platform.mShouldCrouch and shooter.eating_cells_per_frame==4)
    open()
    c.enabled=false
    assert(not step() and not platform.mShouldCrouch)
    ctrl=false; step()
    assert(c.enabled==false)
    c.enabled=true
    -- Non-default movement bindings remain usable in the menu after native sampling.
    open()
    c.mButtonDownDelayLineDown=1
    assert(step() and view().menu.level==2)
    ctrl=false; step()
    c.input_latency_frames=6
    open()
    assert(step(nil,function()
        assert(c.input_latency_frames==6 and c.mButtonDownDelayLineDown==32)
        resample()
    end) and platform.mShouldCrouch and view().menu.level==1)
    assert(c.input_latency_frames==6)
    ctrl=false; step()
    assert(c.input_latency_frames==6)
    c.input_latency_frames=0
    open()
    assert(step(nil,function() c.input_latency_frames=3 end))
    ctrl=false; step()
    assert(c.input_latency_frames==3)
    c.input_latency_frames=0
end
local function order(tracking)
    open(); step("Down")
    if not tracking then
        while view().projects[view().menu.project]~="rail_snipe" do step(); step("Down") end
    end
    step("Right")
    assert(view().menu.level==3)
    step("Right"); assert(view().menu.level==3) -- a held direction cannot also submit
    step(); step("Right")
    local call=view().call
    assert(call.tracking==tracking)
    local duration=NHEquipment.links[state.gearLink.item.kind].seconds*60
    assert(call.phase=="connecting" and call.connectedAt==frame+duration)
    assert(step("Right") and not view().menu and platform.mShouldCrouch)
    ctrl=false
    frame=call.connectedAt-2
    wheel,click,pressed=5,true,true
    assert(not step() and not platform.mShouldCrouch and call.phase=="connecting" and not call.marker and not call.beam)
    pressed=false
    step()
    assert(view().call.phase=="aim" and not view().menu)
end
local function designate()
    click,pressed=true,true
    assert(step() and view().call.phase=="queued")
    assert(step()) -- holding the same click may not discharge the wand
    pressed=false; assert(step() and view().call.selected and not view().call.beam)
end
local function update()
    support.update(state,100,function(edit)
        if failCommit then return false end
        assert(shots>paid and edit(state))
        paid=paid+1
        return true
    end,function(err) assert(err:find("strike logistics")) end)
end
local function scroll(button)
    wheel=button; step()
    return view().call.phase
end
do
    local cabin=dofile("mods/noita_hideout/files/travel/cabin.lua")
    local notices=0
    function GameTextGetTranslatedOrNot(key) return key end
    function GamePrint(message)
        assert(message=="$nh_support_disabled_aboard")
        notices=notices+1
    end
    local positions={{48,54},{173,54},{320,54},{213,81},{224,138},{91,138},{150,-6}}
    for _,p in ipairs(positions) do
        playerX,playerY=cabin.left+p[1],cabin.top+p[2]
        ctrl,pressCtrl=true,true
        assert(not step("Left") and c.mButtonDownLeft and not platform.mShouldCrouch)
        assert(not step() and not view() and shooter.eating_cells_per_frame==4)
    end
    assert(notices==#positions)
    -- Empty space below the stern is outside. Exiting with Ctrl held needs a new press.
    playerX,playerY=cabin.left+316,cabin.top+135
    assert(not step() and not view())
    open()
    playerX,playerY=cabin.point(cabin.infirmary)
    assert(not step("Right") and not view() and c.input_latency_frames==0 and c.mButtonDownRight)
    ctrl=false; playerX,playerY=0,0; step()
    -- Board between input and payment on the exact frame a marked strike would fire.
    order(true); designate(); frame=view().call.due
    playerX,playerY=cabin.point(cabin.terminal)
    update()
    playerX,playerY=0,0
    assert(not view() and shots==0 and paid==0 and state.resources.strike_logistics==100)
    open(); ctrl=false; step(); support.reset()
end
local draw=dofile("mods/noita_hideout/files/fire_support_hud.lua")
do
    local rects,labels,group,noTween
    function GameGetCameraBounds() return 0,0,320,180 end
    function GuiIdPushString(_,key) assert(not group); group=key end
    function GuiIdPop() assert(group); group=nil end
    function GuiColorSetForNextWidget() end
    local widgetZ=-80
    function GuiZSetForNextWidget(_,z) widgetZ=z end
    GUI_OPTION={NoPositionTween=6}
    function GuiOptionsAddForNextWidget(_,option) noTween=option==GUI_OPTION.NoPositionTween end
    function GuiGetImageDimensions(_,path)
        local file=assert(io.open(path,"rb"))
        local header=file:read(24)
        file:close()
        assert(header:sub(13,16)=="IHDR")
        local function dimension(offset)
            local a,b,c,d=header:byte(offset,offset+3)
            return ((a*256+b)*256+c)*256+d
        end
        return dimension(17),dimension(21)
    end
    function GuiImage(_,id,x,y,path,a,w,h,rotation,play,animation)
        assert(group and not rects[id] and noTween)
        noTween=false
        rects[id]={x=x,y=y,w=w,h=h,alpha=a,animation=animation,z=widgetZ,path=path}
        widgetZ=-80
        if path:find("/support_labels/",1,true) then
            local tw,th=GuiGetImageDimensions(nil,path)
            assert(w==h)
            labels[#labels+1]={x=x,y=y,w=tw*w,h=th*h,path=path,scale=w}
        end
    end
    for selected=1,4 do
        for _,pos in ipairs({{160,90,320,"zh"},{160,90,320,"en"},{0,0,320,"zh"},{320,180,144,"en"}}) do
            rects,labels={},{}
            draw({}, {x=pos[1],y=pos[2],menu={level=1,category=selected}},pos[3],180,function(zh,en) return pos[4]=="zh" and zh or en end)
            assert(#labels==4 and not group)
            local active=rects[selected*20+1]
            assert(active.alpha==1 and labels[2].path:find("strike_"..pos[4]..".png",1,true))
            assert(labels[3].path:find("reinforcements_"..pos[4]..".png",1,true))
            if pos[1]==160 then
                local center=active.x+active.w/2
                assert(math.abs(center-160)<=1 or rects[21].x<=3 or rects[81].x+rects[81].w>=pos[3]-3)
            end
            for i,label in ipairs(labels) do
                local id=i*20
                local box=rects[id+1]
                assert(math.abs(label.x+label.w/2-box.x-box.w/2)<0.001)
                assert(math.abs(label.y+label.h/2-box.y-box.h/2)<0.001)
                assert(label.w<box.w and label.h<box.h)
                assert(box.x>=1 and box.x+box.w<=pos[3]-1 and box.y>=1 and box.y+box.h<=179)
                if i>1 then assert(rects[id-19].x+rects[id-19].w<box.x) end
                if i==selected then
                    local l,r=rects[id+6],rects[id+7]
                    assert(l.x+5*l.w<=label.x and r.x>=label.x+label.w and l.y==r.y)
                    assert(l.path:match("arrow_down%.png$") and r.path==l.path and l.z<box.z and r.z<box.z)
                else
                    assert(math.abs(labels[selected].scale/label.scale-1.2)<0.001)
                    assert(box.w<active.w and box.h<active.h and box.alpha>=0.9 and box.alpha<1)
                    assert(rects[id+2].alpha>=0.9 and rects[id+16].alpha>=0.9)
                    assert(not rects[id+6])
                end
            end
        end
    end
    -- Exercise the actual mapped inputs with enough fixture entries to scroll in both directions.
    local original=support.projects[2]
    support.projects[2]={"tracking_strike","resupply","tracking_strike","resupply","tracking_strike","resupply"}
    open(); step("Down"); step("Up")
    assert(view().menu.project==1)
    for i=2,3 do
        step(); step("Down")
        local v=view()
        assert(v.menu.project==i and v.menu.level==2)
        assert(v.payment.resource==(i==2 and "supply_logistics" or "strike_logistics"))
        assert(v.payment.cost==(i==2 and 5 or 3))
    end
    for _,lang in ipairs({"zh","en"}) do
        for _,pos in ipairs({{160,90,320,180},{320,180,144,76},{0,0,320,180}}) do
            rects,labels={},{}
            local v=view()
            v.x,v.y=pos[1],pos[2]
            draw({},v,pos[3],pos[4],function(zh,en) return lang=="zh" and zh or en end)
            assert(#labels==10 and labels[10].path:find("strike_logistics_"..lang,1,true) and not group and not rects[226])
            local category=rects[41]
            local current=rects[161]
            assert(current.y>category.y+category.h and rects[166])
            local boxes={rects[121],rects[141],category,current,rects[181],rects[201]}
            for i,box in ipairs(boxes) do
                assert(math.abs(box.x+box.w/2-current.x-current.w/2)<0.001)
                if i>1 then assert(box.y>boxes[i-1].y+boxes[i-1].h) end
                assert(box.y>=1 and box.y+box.h<=pos[4]-1 and box.x>=1 and box.x+box.w<=pos[3]-1)
            end
            assert(current.w>rects[141].w and current.h>rects[141].h and current.alpha>rects[141].alpha)
            assert(math.abs(labels[7].scale/labels[6].scale-1.2)<0.001)
            assert(rects[146].path:match("arrow_up%.png$") and rects[186].path:match("arrow_down%.png$"))
            for _,base in ipairs({140,180}) do
                assert(rects[base+6].z<rects[base+16].z and rects[base+6].z<rects[base+1].z)
            end
            assert(not rects[126] and not rects[206])
        end
    end
    step("Right"); assert(view().menu.level==3); step("Left"); assert(view().menu.project==3 and view().menu.level==2)
    for i=4,6 do step(); step("Down"); assert(view().menu.project==i) end
    step(); step("Down"); assert(view().menu.project==6 and view().projectStatus=="need_station_1")
    step("Right"); assert(view().menu.level==2)
    step("Left"); step("Right"); step("Down")
    assert(view().menu.category==3 and view().projectStatus=="need_station_1")
    rects,labels={},{}
    draw({},view(),320,180,function(zh) return zh end)
    assert(#labels==9 and labels[5].path:find("gun_drone_zh",1,true) and labels[6].path:find("robot_soldier_zh",1,true))
    assert(labels[7].path:find("mg_turret_zh",1,true) and labels[9].path:find("reinforcement_logistics_zh",1,true))
    step("Right"); assert(view().menu.level==2)
    support.projects[2]=original
    ctrl=false; step(); open(); step("Down")
    rects,labels={},{}
    draw({},view(),320,180,function(zh) return zh end)
    assert(#labels==8 and labels[5].path:find("tracking_strike_zh",1,true) and rects[126])
    assert(labels[6].path:find("strafe_zh",1,true) and rects[146])
    step(); step("Down"); step("Right")
    state.resources.strike_logistics=107
    assert(view().menu.project==2 and view().payment.cost==5 and view().payment.stock==107)
    for _,lang in ipairs({"en","zh"}) do
        for _,x in ipairs({0,320}) do
            rects,labels={},{}
            local v=view()
            v.x,v.y=x,180
            draw({},v,144,76,function(zh,en) return lang=="zh" and zh or en end)
            assert(#labels==10 and labels[9].path:find("confirm_"..lang,1,true))
            assert(labels[10].path:find("strike_logistics_"..lang,1,true))
            local left,project,right=rects[301],rects[141],rects[281]
            assert(left.x>=1 and left.x+left.w<project.x and project.x+project.w<right.x and right.x+right.w<=143)
            assert(left.y==project.y and right.y==project.y and right.y+right.h<=75)
            assert(rects[286].path:match("arrow_right%.png$") and not rects[287])
            for i,glyph in ipairs({"5","slash","1","0","7"}) do
                assert(rects[316+i].animation==glyph)
            end
        end
    end
    step("Left"); step("Right"); assert(view().menu.level==3 and view().menu.project==2)
    step("Down"); assert(view().menu.level==2 and view().menu.project==3 and not view().projectStatus and view().payment.cost==4)
    step("Up"); step()
    step("Up"); assert(view().menu.level==2 and view().menu.project==1 and not view().call)
    rects,labels={},{}
    draw({},view(),320,180,function(zh) return zh end)
    assert(#labels==8 and labels[8].path:find("strike_logistics_zh",1,true) and not rects[201])
    step("Right"); assert(view().menu.level==3 and not view().call)
    step("Down"); assert(view().menu.level==2 and view().menu.project==2 and not view().call)
    step("Right"); assert(view().menu.level==3 and not view().call)
    state.resources.strike_logistics=100
    assert(view().payment.stock==100)
    state.resources.strike_logistics=0
    step("Right")
    assert(view().menu.level==2 and view().projectStatus=="insufficient_packs" and not view().call)
    for _,lang in ipairs({"zh","en"}) do
        rects,labels={},{}
        draw({},view(),144,76,function(zh,en) return lang=="zh" and zh or en end)
        assert(labels[9].path:find("insufficient_packs_"..lang,1,true) and labels[10].path:find("strike_logistics_"..lang,1,true))
        assert(not rects[146])
    end
    state.resources.strike_logistics=100
    ctrl=false; step()
    assert(not view() and state.materials.gunpowder==100)
end
local function hud()
    local shown={}
    function GameGetCameraBounds() return 0,0,320,180 end
    function GuiGetImageDimensions() return 16,16 end
    function GuiGetTextDimensions(_,text) return #text*5,9 end
    function MagicNumbersGetValue() return "0" end
    function GuiColorSetForNextWidget() end
    function GuiImage(_,id) shown[id]=true end
    function GuiText(_,_,_,label) shown[label]=true end
    draw({},view(),320,180,function(_,en) return en end)
    return shown
end
state.levels.support=3
local link=state.gearLink
state.gearLink=nil; ctrl,pressCtrl=true,true
assert(not step() and not view())
state.gearLink=link
for _,tier in ipairs({{"data_link_2",3},{"data_link_3",1}}) do
    state.gearLink={id=11,item={kind=tier[1],remaining=1}}
    assert(NHEquipment.links[tier[1]].seconds==tier[2])
    order(false)
    assert(state.gearLink.item.remaining==1)
    state.gearLink=link
    assert(not step() and not view())
end
open(); step("Left"); assert(view().menu.category==1)
step("Down"); step("Left"); assert(view().menu.level==1)
ctrl=false; step(); assert(not view())
order(true); designate()
targetX=67; update(); assert(view().call.marker.x==67 and paid==0)
wheel=4; step(); assert(not view().call.selected)
alive=false; update()
assert(view().call.phase=="ready" and not view().call.marker and paid==0)
-- Full native ring: interior scrolls pass through, seam is inserted both ways.
held=4; assert(scroll(5)=="ready")
held=8; assert(scroll(5)=="aim" and c.mButtonCountChangeItemR==0)
assert(scroll(4)=="ready" and c.mButtonCountChangeItemL==0)
held=1; assert(scroll(4)=="aim")
assert(scroll(5)=="ready")
-- The native mapped action also works without a raw mouse pulse: continuing
-- through the virtual slot forwards the next tick for the ordinary wrap.
held=8
c.mButtonFrameChangeItemR,c.mButtonCountChangeItemR=frame+1,1
step(); assert(view().call.phase=="aim" and c.mButtonCountChangeItemR==0)
c.mButtonFrameChangeItemR,c.mButtonCountChangeItemR=frame+1,1
step(); assert(view().call.phase=="ready" and c.mButtonCountChangeItemR==1)
held=8; assert(scroll(5)=="aim")
alive=true; enemy=false
click=true; step(); assert(view().call.phase=="aim") -- a tracking call needs an enemy
enemy=true; designate()
wheel=5; step(); assert(view().call.phase=="queued")
frame=frame+support.delay; update(); update()
assert(not view().call and view().airborne and paid==1 and shots==1 and state.resources.strike_logistics==97 and state.materials.gunpowder==100)
order(false); designate(); targetX=80; alive=false; update()
assert(view().call.marker.x==67) -- fixed enemy coordinate survives death
frame=frame+support.delay; failCommit=true; update(); failCommit=false
assert(killed==1 and paid==1 and view().call.phase=="aim")
support.reset(); enemy=false; order(false); designate()
assert(view().call.marker.x==90) -- fixed terrain
frame=frame+support.delay; failSpawn=true; update(); failSpawn=false
assert(paid==1 and view().call.phase=="aim")
support.reset(); order(false); designate(); frame=frame+support.delay
state.resources={}; update()
assert(shots==2 and paid==1 and not view())
open(); step("Down"); step("Right")
assert(view().menu.level==2 and view().projectStatus=="insufficient_packs" and not view().call)
ctrl=false; step()
-- An expended designator still owns every click until the player leaves it.
state.resources={strike_logistics=56}
support.reset(); order(false); designate()
local mark=view().call.marker
local locked=hud()
assert(locked[5963] and locked["+"] and not locked[5962] and locked[6000] and locked[6010])
click,pressed=true,true
assert(step() and view().call.marker==mark and not view().call.beam)
frame=frame+support.delay; update(); update()
assert(view().call.phase=="finished" and view().call.selected and not view().call.marker and paid==2)
local spent=hud()
assert(spent[5963] and spent[5960] and not spent["+"] and not spent[5962])
pressed=false; assert(step())
click,pressed=true,true
c.mButtonDownFire=true
assert(step() and not c.mButtonDownFire and abilities[1].mNextFrameUsable>frame and abilities[2].mNextFrameUsable==100000)
wheel=5; assert(step() and not view().call and hud()[6010])
frame=frame+30; assert(not view())
held=1; assert(step() and abilities[1].mNextFrameUsable>frame)
pressed=false; assert(not step())
click,pressed=true,true
assert(not step() and abilities[1].mNextFrameUsable<=frame)
pressed=false
-- A native item selection can also leave the locked slot before launch.
order(false); designate(); held=2; step()
assert(not view().call.selected and scroll(4)=="queued" and not view().call.selected)
frame=frame+support.delay; update(); assert(not view().call and paid==3)
-- Stock in the detached payment draft can differ from the pre-launch snapshot.
state.resources.strike_logistics=28
order(false); designate()
frame=frame+support.delay
local before=killed
support.update(state,100,function(edit)
    local ok,err=edit({gearLink=state.gearLink,levels=state.levels,resources={}})
    assert(not ok and err=="Not enough strike logistics packs.")
    return false
end,function(err) error(err) end)
assert(killed==before+1 and paid==3 and not view())
open(); step("Down"); step("Right"); assert(view().menu.level==3 and not view().projectStatus)
ctrl=false; step()
print("Fire support: full native scroll ring, input ownership, fixed and tracked marks, reacquisition and launch payment passed.")

-- The preview, live velocity, fuse and blast radius share world coordinates.
state.resources.strike_logistics=140
for _,normal in ipairs({{0,1},{0,-1},{1,0},{0.6,-0.8}}) do
    support.reset()
    normalX,normalY=normal[1],normal[2]
    order(false)
    assert(hud()[6000] and hud()[6010])
    designate()
    local path=view().call.path
    assert(math.abs(path.sx-path.x-72*normalX)<0.001 and math.abs(path.sy-path.y-72*normalY)<0.001)
    frame=frame+support.delay; update()
    assert(shellX==path.sx and shellY==path.sy)
    assert(lastShot.x==path.sx and lastShot.y==path.sy and lastShot.tx==path.endX and lastShot.ty==path.endY)
    assert(math.abs(lastShot.x+velocity.mVelocity[1]*projectile.lifetime/60-path.endX)<0.001)
    assert(math.abs(lastShot.y+velocity.mVelocity[2]*projectile.lifetime/60-path.endY)<0.001)
    assert(velocity.gravity_y==0 and projectile.explosion_radius==path.radius and path.radius==34 and math.abs((path.endX-path.x)^2+(path.endY-path.y)^2-90^2)<0.01)
end
support.reset(); order(false); designate()
loaded=false; frame=frame+support.delay
local message
support.update(state,100,function() error("blocked path charged") end,function(reason) message=reason end)
assert(message=="No clear strike path." and view().call.phase=="aim" and not view().call.path)
assert(state.resources.strike_logistics==28 and not hud()[6010])
loaded=true; support.reset()
normalX,normalY=0,1
order(false); designate()
gap=26; frame=frame+6; update()
assert(math.abs(view().call.path.sy-view().call.marker.y-22)<0.001,"a low opposing surface shortens an upward approach")
gap=7; frame=frame+support.delay; message=nil
support.update(state,100,function() error("sealed path charged") end,function(reason) message=reason end)
assert(message=="No clear strike path." and view().call.phase=="aim")
gap=nil; designate(); frame=frame+support.delay; update()
assert(hud()[6010]); rocketAlive=false
assert(not hud()[6010],"the danger area clears on an early collision")
support.reset()

-- Use the real aiming and payment path for a full volley, including a link
-- unequipped after launch. A short ledge must reflect rather than skip shots.
do
    local oldRay=RaytraceSurfaces
    local oldMouse=DEBUG_GetMouseWorld
    local ledge=true
    function RaytraceSurfaces(x,y,tx,ty)
        local hit,hx,hy=oldRay(x,y,tx,ty)
        if hit and ledge and hx>48 then return false end
        return hit,hx,hy
    end
    normalX,normalY=0,-1
    function DEBUG_GetMouseWorld() return 30,90 end
    state.levels.support=3
    for _,trial in ipairs({{"strafe",2,6,5},{"barrage",4,8,12},{"missile_strafe",5,6,10},{"plasma_strafe",6,6,15},{"missile_barrage",7,8,24}}) do
        local kind,index,count,cost=unpack(trial)
        state.resources.strike_logistics=cost
        open(); step("Down")
        for i=2,index do step(); step("Down") end
        step("Right"); step(); step("Right"); ctrl=false
        frame=view().call.connectedAt; step()
        local route=view().call.route
        local sweep=kind:find("strafe",1,true)~=nil
        if sweep then assert(#route==2 and route.dx>0)
        else assert(#route==count and view().call.center.radius>=73 and route[1].x==view().call.center.x) end
        designate()
        local before,oldPaid=shots,paid
        frame=view().call.due; update()
        local sequence={lastShot.tx}
        local link=state.gearLink
        if kind=="strafe" then
            local cabin=dofile("mods/noita_hideout/files/travel/cabin.lua")
            playerX,playerY=cabin.point(cabin.infirmary)
        else state.gearLink=nil end
        for i=1,130 do
            step()
            local previous=shots
            update()
            if shots>previous then sequence[#sequence+1]=lastShot.tx end
        end
        playerX,playerY=0,0
        state.gearLink=link
        assert(shots==before+count and paid==oldPaid+1 and not state.resources.strike_logistics)
        if sweep then
            assert(sequence[1]<sequence[2] and sequence[3]==sequence[1] and sequence[4]==sequence[2])
        end
        support.reset()
        ledge=true
    end
    RaytraceSurfaces,DEBUG_GetMouseWorld=oldRay,oldMouse
end

-- A speck in the designator ray and a second one in the incoming shell lane
-- must not move the mark, bend the preview or reject the first paid shot.
do
    local oldRay,oldMouse=RaytraceSurfaces,DEBUG_GetMouseWorld
    function DEBUG_GetMouseWorld() return 30,90 end
    function RaytraceSurfaces(x,y,tx,ty)
        local steps=math.max(1,math.ceil(math.max(math.abs(tx-x),math.abs(ty-y))*4))
        for i=0,steps do
            local hx,hy=x+(tx-x)*i/steps,y+(ty-y)*i/steps
            local cx,cy=math.floor(hx),math.floor(hy)
            if cy>=90 or (cx==15 and cy==45) or (cx>=29 and cx<=31 and cy>=78 and cy<=80) then
                return true,hx,hy
            end
        end
        return false
    end
    state.resources.strike_logistics=5
    open(); step("Down"); step(); step("Down"); step("Right"); step(); step("Right")
    ctrl=false; frame=view().call.connectedAt; step()
    local preview=view().call
    assert(#preview.route==6 and preview.beam.y>=90 and preview.path.sy<25)
    designate()
    local before=shots
    frame=preview.due; update()
    assert(shots==before+1 and lastShot.y<25 and lastShot.ty>=90 and not state.resources.strike_logistics)
    support.reset()
    RaytraceSurfaces,DEBUG_GetMouseWorld=oldRay,oldMouse
end

-- A minelayer designates terrain through a creature. A destroyed landing
-- surface returns the caller to aiming without spending the four packs.
do
    local oldRay=RaytraceSurfaces
    state.levels.support=1
    state.resources.strike_logistics=4
    enemy=true
    open(); step("Down"); step(); step("Down"); step(); step("Down")
    step("Right"); step(); step("Right")
    ctrl=false; frame=view().call.connectedAt; step()
    local call=view().call
    assert(call.project=="minelayer" and call.path.danger==156 and not call.beam.target)
    designate()
    RaytraceSurfaces=function() return false end
    frame=call.due
    support.update(state,100,function() error("paid for missing surface") end,function() end)
    assert(call.phase=="aim" and state.resources.strike_logistics==4)
    RaytraceSurfaces=oldRay
    designate()
    frame=call.due
    local before=shots
    update()
    assert(shots==before+1 and not state.resources.strike_logistics)
    support.reset()
end

-- Approach a flat surface from outside the burst range, then integrate the
-- actual ejection velocities until impact, including shortened cave approaches.
do
    local scatter=assert(loadfile("mods/noita_hideout/files/projectiles/mine_dispenser_open.lua"))
    for _,normal in ipairs({{0,-1},{-1,0},{0,1},{0.6,-0.8}}) do
        local nx,ny=unpack(normal)
        for _,height in ipairs({40,12}) do
            local distance=60
            local mines={}
            local bursts,kills=0,0
            local env={
                GetUpdatedEntityID=function() return 99 end,
                EntityGetTransform=function() return nx*distance,ny*distance end,
                EntityGetFirstComponentIncludingDisabled=function(id) return id end,
                ComponentGetValue2=function() return -320*nx,-320*ny end,
                GetSurfaceNormal=function() return true,nx,ny end,
                RaytraceSurfaces=function(x,y,tx,ty)
                    if tx*nx+ty*ny<=0 then return true,0,0 end
                    return false
                end,
                EntityLoad=function(file,x,y)
                    assert(math.abs(x*nx+y*ny-height)<0.001)
                    if file:match("pod_open_fx%.xml$") then bursts=bursts+1; return 100 end
                    assert(file:match("/mine_scatter%.xml$"))
                    mines[#mines+1]={x=x,y=y}
                    return #mines
                end,
                ComponentSetValue2=function(id,key,vx,vy)
                    assert(key=="mVelocity")
                    mines[id].vx,mines[id].vy=vx,vy
                end,
                EntityKill=function(id) assert(id==99); kills=kills+1 end
            }
            setfenv(scatter,setmetatable(env,{__index=_G}))
            scatter()
            assert(#mines==0 and kills==0)
            distance=height
            scatter()
            assert(#mines==6 and bursts==1 and kills==1)
            local previous
            for _,mine in ipairs(mines) do
                local t=0
                local x,y=mine.x,mine.y
                repeat
                    t=t+0.001
                    x=mine.x+mine.vx*t
                    y=mine.y+mine.vy*t+110*t*t
                until x*nx+y*ny<0.000001 or t>=1
                assert(t<1)
                local landing=-ny*x+nx*y
                if previous then assert(landing-previous>46 and landing-previous<50) end
                previous=landing
            end
        end
    end
end

-- Drive all six designated intelligence calls, plus the player-centred vitality ring.
do
    function EntityGetComponent() return {} end
    local originalLoad=EntityLoad
    local lastLoad
    function EntityLoad(file,x,y)
        lastLoad={file=file,x=x,y=y}
        return originalLoad(file,x,y)
    end
    local function runUpdate()
        support.update(state,100,function(edit) return edit(state) end,function(message) error(message) end)
    end
    state.levels.intel=3
    for _,trial in ipairs({
        {2,"berserk_field",90,28,5},{4,"regeneration_field",0,28,12},{5,"polymorph_field",180,28,10},
        {7,"black_hole_big",300,150,20},{8,"white_hole_big",300,150,20},
        {9,"nuke",480,250,26},{10,"nuke_giga",720,400,30}
    }) do
        local index,project,delay,radius,cost=unpack(trial)
        state.resources.intel_logistics=cost
        open(); step("Right"); step(); step("Right"); step("Down")
        for i=2,index do step(); step("Down") end
        step("Right"); step(); step("Right"); ctrl=false
        local call=view().call
        assert(call.project==project and call.targeted==(delay>0))
        frame=call.connectedAt; step()
        local markX,markY=0,0
        if delay>0 then
            designate()
            markX,markY=call.marker.x,call.marker.y
            assert(call.path.radius==radius and (markX~=0 or markY~=0))
            assert(call.due-frame==delay-2)
            frame=call.due-1;runUpdate()
            assert(state.resources.intel_logistics==cost)
            if radius>=150 then
                local shown=hud()
                local notice=false
                for key in pairs(shown) do if type(key)=="string" and key:find("DANGER",1,true) then notice=true end end
                assert(notice)
            end
            frame=call.due
        end
        runUpdate()
        assert(lastLoad.file=="data/entities/projectiles/deck/"..project..".xml" and not state.resources.intel_logistics)
        if project=="nuke" or project=="nuke_giga" then
            assert(lastShot.tx==markX and lastShot.ty==markY and projectile.explosion_radius==radius)
        else
            assert(lastLoad.x==markX and lastLoad.y==markY)
        end
        if radius>=150 then assert(#view().activeZones==1) end
        support.reset()
    end
    EntityLoad=originalLoad
end

-- Use the production workshop, gear move and profile readback with a legacy empty link slot.
local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] or false end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/potion.lua")
local profile=assert(NHStore.load())
NHStore.newRun(profile)
profile.resources.arcane_scrap,profile.bankGold=2,100
profile.resources.nh_philosopher_stone,profile.resources.strike_logistics=1,3
profile.resources.essence_high_energy=100
profile.resources.container_scrap=4
assert(not NHStore.buyUpgrade(profile,{id="support",level=0}) and profile.resources.essence_high_energy==100)
profile.resources.container_scrap=5
assert(NHStore.buyUpgrade(profile,{id="support",level=0}))
assert(not profile.resources.nh_philosopher_stone and not profile.resources.essence_high_energy and profile.resources.arcane_scrap==1)
assert(NHStore.craft(profile,"remote_terminal"))
local index=assert(NHStore.slotIndex(profile,"warehouse",1,"remote_terminal"))
local row=profile.warehouse[index]
assert(NHStore.category(row.item.kind)=="equipment" and NHShields.slot(row.item.kind)==5)
assert(NHShields.move(profile,{kind=row.item.kind,source="warehouse",destination="gear",from=1,entity=row.id}))
assert(NHStore.commit(profile))
profile=assert(NHStore.load())
assert(profile.gearLink.id==row.id and not profile.resources.arcane_scrap and profile.bankGold==0)
assert(support.pay(profile) and not profile.resources.strike_logistics and profile.gearLink.item.remaining==20)
assert(NHShields.move(profile,{kind=row.item.kind,source="gear",destination="warehouse",safeSlot=1,entity=row.id}))
assert(not profile.gearLink and NHStore.commit(profile))
print("Data link: facility, crafting, equip, payment, unequip and profile reload passed.")

-- Check every menu project against its unlock tier, exact price and currency.
local tariffs={
    {"resupply","supply_logistics",{{1,5},{1,3},{2,6},{2,12},{3,18},{3,28},{3,30}}},
    {"support","strike_logistics",{{1,3},{1,5},{1,4},{2,12},{2,10},{2,15},{3,24},{3,28}}},
    {"reinforcement","reinforcement_logistics",{{1,4},{1,5},{1,5},{2,10},{2,9},{2,14},{2,10},{3,20},{3,24},{3,22},{3,21},{3,30},{3,18}}},
    {"intel","intel_logistics",{{1,1},{1,5},{2,6},{2,12},{2,10},{3,15},{3,20},{3,20},{3,26},{3,30}}},
}
for category,tariff in ipairs(tariffs) do
    local station,resource,entries=unpack(tariff)
    assert(#support.projects[category]==#entries)
    for i,id in ipairs(support.projects[category]) do
        local level,cost=unpack(entries[i])
        local draft={gearLink={id=1},levels={[station]=level-1},resources={[resource]=cost}}
        assert(not support.pay(draft,1,id) and draft.resources[resource]==cost,id)
        draft.levels[station]=level
        draft.resources[resource]=cost-1
        assert(not support.pay(draft,1,id) and draft.resources[resource]==cost-1,id)
        draft.resources[resource]=cost
        assert(support.pay(draft,1,id) and not draft.resources[resource],id)
        draft.levels[station]=3
        draft.resources[resource]=cost+1
        assert(support.pay(draft,1,id) and draft.resources[resource]==1,id)
    end
end

-- The data link selects one episode. Only the recipient checks the death
-- terrain and opens the pod, even when the caller is far away or in midair.
do
    support.reset()
    local show,eligible,obstructed,occupied=true,true,false,false
    local selects,requests,pods,fx,errors=0,0,0,0,{}
    local capsule,token=nil,{world="world_fx",x=600,y=-50}
    local fxEvents={}
    function GlobalsSetValue(key,value) fxEvents[#fxEvents+1]={key,value} end
    function SessionNumbersGetValue(key) assert(key=="NEW_GAME_PLUS_COUNT");return "0" end
    playerX,playerY=0,0
    state.resources.supply_logistics=5
    NHEWReinforce={visible=function() return show end,available=function() return eligible end,
        redirectAvailable=function() return token.redirect end,
        select=function(p,x,y) assert(p==100 and x==0 and y==0);selects=selects+1;return token end,
        request=function(p,x,y,t)
            assert(p==100 and t==token)
            if t.redirect then assert(x==22 and y==0) else assert(x==600 and y==-50) end
            requests=requests+1;return true
        end}
    function RaytracePlatforms(x,y,tx,ty)
        if not obstructed and ty>y and y<=10 and ty>=10 then return true,tx,10 end
        return false
    end
    function RaytraceSurfacesAndLiquiform() return false end
    function EntityGetInRadiusWithTag(_,_,_,tag) return occupied==tag and {41} or {} end
    function DoesWorldExistAt() return true end
    function EntityLoad(path)
        if path:match("/supply_pod.xml$") then pods=pods+1;capsule={};return capsule end
        assert(path:match("/pod_open_fx.xml$"),path);fx=fx+1;return 91
    end
    local waiting=false
    function EntityHasTag(id,tag) return (id==capsule and tag=="nh_supply_pod") or (id==41 and waiting and tag=="nh_ew_waiting") end
    function EntityAddTag(id,tag) assert((id==capsule or id==91) and tag=="ew_no_enemy_sync") end
    function EntityGetIsAlive(id) return id==100 or id==capsule end
    function EntityKill(id) assert(id==capsule);capsule=nil end
    function EntitySetTransform(id) assert(id==capsule) end
    local function choosePlayers()
        open();step("Left");step();step("Left");assert(view().menu.category==5)
        step("Down");assert(view().menu.level==2 and view().projects[1]=="ew_player_drop" and view().payment.cost==(token.redirect and 0 or 5))
    end
    local function code()
        for _,dir in ipairs({"Up","Down","Right","Left","Up"}) do step();step(dir) end
    end
    local function update()
        support.update(state,100,function() error("support charged before host receipt") end,function(s) errors[#errors+1]=s end)
    end
    local function launch()
        local order=view().call
        assert(order.ticket==token and not order.targeted and not order.marker and not order.selected)
        ctrl=false;step();frame=order.connectedAt;update()
    end
    choosePlayers();eligible=false;step("Up");assert(selects==0 and view().projectStatus=="ew_player_unavailable")
    eligible=true;state.resources.supply_logistics=4;step();step("Up");assert(selects==0 and view().projectStatus=="insufficient_packs")
    state.resources.supply_logistics=5;step();step("Right");assert(view().menu.entered==0)
    obstructed=true;occupied="ew_peer";code();assert(selects==1);launch()
    assert(pods==0 and fx==0 and #fxEvents==0 and requests==1 and #errors==0 and state.resources.supply_logistics==5)
    token.redirect=true;state.resources.supply_logistics=0
    choosePlayers();code();launch();assert(requests==1 and #errors==1)
    occupied=false;choosePlayers();code();launch();assert(requests==2 and #errors==1 and state.resources.supply_logistics==0)
    occupied="ew_client"
    local landing=dofile("mods/noita_hideout/files/resupply.lua")
    assert(landing.playerDropClear(22,2,41) and not landing.playerDropClear(22,2,100),"Ignore only the restored player's own body")
    waiting=true
    assert(landing.playerDropClear(22,2,100),"A teammate waiting for a drop has no physical body at the landing site")
    ctrl=false;step();show=false;open();step("Left");step();step("Left");assert(view().menu.category==4 and not view().playerCategory)
    support.reset();NHEWReinforce=nil
end
print("EW player support: data link sequence, death-site request, free alternate, crowd checks and single-player menu passed.")
