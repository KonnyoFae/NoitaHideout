-- The virtual slot borrows the fire input, never the player's held entity.
local S={resource="strike_logistics",delay=90,station="support",shortage="Not enough strike logistics packs.",
    projects={}}
local resupply=dofile("mods/noita_hideout/files/resupply.lua")
local reinforcements=dofile("mods/noita_hideout/files/reinforcements.lua")
local locations=dofile("mods/noita_hideout/files/storm/sites/locations.lua")
local cabin=dofile("mods/noita_hideout/files/travel/cabin.lua")
local recon={resource="intel_logistics",station="intel",shortage="Not enough intel logistics packs."}
local pricing,services={},{}
-- Each menu entry carries its unlock tier and its fixed price per call.
local function category(service,entries)
    local order={}
    for i,entry in ipairs(entries) do
        local id,level,cost=unpack(entry)
        order[i]=id
        services[id]=service
        pricing[id]={level=level,cost=cost}
    end
    S.projects[#S.projects+1]=order
end
category(resupply,{
    {"resupply",1,5},{"heavy_mg",1,3},{"auto_grenade",2,6},{"heavy_plasma",2,12},
    {"missile_launcher",3,18},{"railgun",3,28},{"bfg",3,30},
})
category(S,{
    {"tracking_strike",1,3},{"strafe",1,5},{"minelayer",1,4},{"barrage",2,12},{"missile_strafe",2,10},
    {"plasma_strafe",2,15},{"missile_barrage",3,24},{"rail_snipe",3,28},
})
category(reinforcements,{
    {"gun_drone",1,4},{"robot_soldier",1,5},{"mg_turret",1,5},
    {"repair_drone",2,10},{"robot_spy",2,9},{"missile_crab",2,14},{"chaingun_turret",2,10},
    {"shield_drone",3,20},{"laser_drone",3,24},{"robot_assassin",3,22},{"robot_monk",3,21},{"necrobot",3,30},
    {"missile_turret",3,18},
})
category(recon,{
    {"recon",1,1},{"berserk_field",1,5},{"enemy_radar",2,6},{"regeneration_field",2,12},{"polymorph_field",2,10},
    {"site_radar",3,15},{"black_hole_big",3,20},{"white_hole_big",3,20},{"nuke",3,26},{"nuke_giga",3,30},
})
local radarScripts={enemy_radar="data/scripts/perks/radar.lua"}
local function hasRadar(player,project)
    for _,c in ipairs(EntityGetComponent(player,"LuaComponent","perk_component") or {}) do
        if ComponentGetValue2(c,"script_source_file")==radarScripts[project] then return true end
    end
    return #(EntityGetAllChildren(player,"nh_"..project) or {})>0
end
local menu,call,owner,releaseFire
local patterns=dofile("mods/noita_hideout/files/strike_patterns.lua")
local activeZones={}
local airborne,salvo
local directions={"Left","Right","Up","Down"}
local directionKeys={Left={4,80},Right={7,79},Up={26,82},Down={22,81}} -- WASD and arrows
local movementInputs={"Left","Right","Up","Down","Jump","Fly"}
local stageKeys={}
local lastWheelStamp={}
local commandLink,stanceControls,eatingGuard,eatUntilUp
local latencyGuard,crouchInput
local function clear(c,action)
    ComponentSetValue2(c,"mButtonDown"..action,false)
    ComponentSetValue2(c,"mButtonFrame"..action,-1)
end

local function rawDirection(key)
    local keys=directionKeys[key]
    return InputIsKeyDown(keys[1]) or InputIsKeyDown(keys[2])
end

local function mappedDown(c,key)
    if ComponentGetValue2(c,"mButtonDown"..key)==true then return true end
    -- While typing, the latest sample of a rebound key can still be in the delay line.
    return c==stanceControls and (ComponentGetValue2(c,"mButtonDownDelayLine"..key) or 0)%2==1
end

local function restoreMovementInput()
    local c=stanceControls
    local pose,borrowed=crouchInput,latencyGuard
    crouchInput,latencyGuard=nil,nil
    if not (pose or borrowed) or not owner or not EntityGetIsAlive(owner)
        or EntityGetFirstComponentIncludingDisabled(owner,"ControlsComponent")~=c then return end
    if pose then
        -- Keep a real down-key sample taken during the native update. If input
        -- was not resampled, put back the physical state read before our crouch.
        local line=ComponentGetValue2(c,"mButtonDownDelayLineDown")
        if line~=pose.injected then
            pose.sample=line%2
            pose.down=pose.sample==1
        end
        ComponentSetValue2(c,"mButtonDownDown",pose.down)
        ComponentSetValue2(c,"mButtonDownDelayLineDown",pose.sample)
    end
    if borrowed and ComponentGetValue2(c,"input_latency_frames")==1 then
        ComponentSetValue2(c,"input_latency_frames",0)
    end
end

local function restoreEating()
    local guard=eatingGuard
    eatingGuard=nil
    if not guard or not EntityGetIsAlive(guard.player)
        or EntityGetFirstComponentIncludingDisabled(guard.player,"PlatformShooterPlayerComponent")~=guard.component then return end
    if guard.cells and ComponentGetValue2(guard.component,"eating_cells_per_frame")==0 then
        ComponentSetValue2(guard.component,"eating_cells_per_frame",guard.cells)
    end
    if guard.delay and ComponentGetValue2(guard.component,"eating_delay_frames")==2 then
        ComponentSetValue2(guard.component,"eating_delay_frames",guard.delay)
    end
end

local function blockEating(player,c)
    clear(c,"Eat")
    -- Native eating starts when the held Down input ages past eating_delay_frames.
    -- Keep it one frame old so crouching never generates a new press or ages into a bite.
    ComponentSetValue2(c,"mButtonFrameDown",GameGetFrameNum()-1)
    -- Native input can resample Eat during the engine update, after the pre-update hook.
    local shooter=EntityGetFirstComponentIncludingDisabled(player,"PlatformShooterPlayerComponent")
    if not shooter then return end
    eatingGuard={player=player,component=shooter}
    local cells=ComponentGetValue2(shooter,"eating_cells_per_frame")
    if cells and cells>0 then
        eatingGuard.cells=cells
        ComponentSetValue2(shooter,"eating_cells_per_frame",0)
    end
    -- A modded instant bite must also wait out our one-frame crouch, including
    -- the tick between the pre-update hook and native input processing.
    local delay=ComponentGetValue2(shooter,"eating_delay_frames")
    if delay and delay<2 then
        eatingGuard.delay=delay
        ComponentSetValue2(shooter,"eating_delay_frames",2)
    end
end

local function closeCommands()
    commandLink,menu=nil,nil
    restoreMovementInput()
    if stanceControls and owner and EntityGetIsAlive(owner)
        and EntityGetFirstComponentIncludingDisabled(owner,"ControlsComponent")==stanceControls then
        for _,key in ipairs(movementInputs) do
            ComponentSetValue2(stanceControls,"mButtonDownDelayLine"..key,0)
        end
    end
    stanceControls=nil
end

local function holdStance(player,c)
    local entering=stanceControls~=c
    stanceControls=c
    -- Native input may sample the physical key again after this hook. It will read
    -- an empty previous sample for movement, even if the new sample is held.
    local delay=ComponentGetValue2(c,"input_latency_frames")
    if delay==0 then
        latencyGuard=true
        delay=1
        ComponentSetValue2(c,"input_latency_frames",1)
    end
    local body=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
    if body and ComponentGetValue2(body,"is_on_ground") then
        -- Down and Eat are separate engine actions even when bound to the same key.
        -- Seed the delayed Down sample so native movement and animation see a held
        -- crouch. Never synthesize a press edge, which could also drop a platform.
        crouchInput={down=ComponentGetValue2(c,"mButtonDownDown")==true,
            sample=(ComponentGetValue2(c,"mButtonDownDelayLineDown") or 0)%2,
            injected=2^(math.min(31,math.max(1,delay or 1))-1)}
        if entering then
            local vx,vy=ComponentGetValue2(body,"mVelocity")
            if vx~=0 then ComponentSetValue2(body,"mVelocity",0,vy) end
        end
    end
    for _,key in ipairs(movementInputs) do
        clear(c,key)
        ComponentSetValue2(c,"mButtonDownDelayLine"..key,0)
    end
    if crouchInput then
        ComponentSetValue2(c,"mButtonDownDown",true)
        ComponentSetValue2(c,"mButtonDownDelayLineDown",crouchInput.injected)
    end
end

function S.finishInput()
    restoreMovementInput()
    restoreEating()
end

local function closeCall()
    if call and call.pod and EntityGetIsAlive(call.pod) and EntityHasTag(call.pod,"nh_supply_pod") then EntityKill(call.pod) end
    call=nil
end

local function aboard(x,y)
    -- Include a player standing on the outer hull, even on the arrival frame before a refit finishes.
    return cabin.inside(x,y) or cabin.wouldEmbed(x,y+1)
end

local function cancelOnBoard()
    closeCall()
    closeCommands()
    restoreEating()
    eatUntilUp=nil
end

function S.reset(keepZones)
    closeCall()
    closeCommands()
    restoreEating()
    owner,releaseFire,airborne,salvo,eatUntilUp=nil,nil,nil,nil,nil
    if not keepZones then activeZones={} end
    stageKeys={}
    lastWheelStamp={}
end

local function wheel(c)
    local frame=GameGetFrameNum()
    for _,key in ipairs({"ChangeItemR","ChangeItemL"}) do
        local stamp=ComponentGetValue2(c,"mButtonFrame"..key)
        if lastWheelStamp[key]~=stamp and (stamp==frame or
            (stamp==frame+1 and ComponentGetValue2(c,"mButtonDown"..key))) then
            lastWheelStamp[key]=stamp
            return key=="ChangeItemR" and 1 or -1
        end
    end
    if InputIsMouseButtonJustDown(5) then return 1 end
    if InputIsMouseButtonJustDown(4) then return -1 end
end

-- Intercept only the seam of the native ring. Once inside, reversing returns
-- to the anchor; continuing lets the engine wrap to the opposite end.
local function atEdge(player,dir,held)
    if not held then return true end
    local first,last,lo,hi=nil,nil,math.huge,-math.huge
    for _,parent in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityGetName(parent)=="inventory_quick" then
            for _,id in ipairs(EntityGetAllChildren(parent) or {}) do
                local item=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
                if item then
                    local x=ComponentGetValue2(item,"inventory_slot")
                    local kind=NHNative.kind(id) or NHTransfers.item_kind(id)
                    local rank=x+(NHFirearms.lane(kind)=="wand" and 0 or 4)
                    if rank<lo then first,lo=id,rank end
                    if rank>hi then last,hi=id,rank end
                end
            end
            break
        end
    end
    return held==(dir==1 and last or first)
end

local function leaveSlot()
    call.selected,call.anchor,call.enteredFrom,call.beam,call.grip=false,nil,nil,nil,nil
    if call.phase=="finished" then closeCall()
    elseif call.phase=="aim" then call.phase,call.path,call.probe="ready",nil,nil end
end

local function cycle(player,c,dir)
    local held=NHNative.held(player)
    local consume
    if call.selected then
        consume=call.enteredFrom~=dir
        leaveSlot()
    elseif call.phase=="ready" and atEdge(player,dir,held) then
        call.phase,call.anchor,call.enteredFrom,call.selected="aim",held,dir,true
        consume=true
    end
    if consume then
        for _,key in ipairs({"ChangeItemR","ChangeItemL"}) do
            clear(c,key)
            ComponentSetValue2(c,"mButtonCount"..key,0)
        end
    end
end

local function interval(pos,dir,low,high)
    if math.abs(dir)<0.00001 then
        if pos<low or pos>high then return math.huge,-math.huge end
        return -math.huge,math.huge
    end
    local a,b=(low-pos)/dir,(high-pos)/dir
    return math.min(a,b),math.max(a,b)
end

local function handRay(player)
    local arm=(EntityGetAllChildren(player,"player_arm_r") or {})[1]
    local x,y
    if arm then x,y=EntityGetHotspot(arm,"hand",true) end
    if not x then x,y=EntityGetTransform(player) end
    local dx,dy=NHProducts.aim(player)
    if not dx then return end
    if not GameGetIsGamepadConnected() then
        local mx,my=DEBUG_GetMouseWorld()
        local length=math.sqrt((mx-x)^2+(my-y)^2)
        if length>0.01 then dx,dy=(mx-x)/length,(my-y)/length end
    end
    return x,y,dx,dy
end

local function aim(x,y,dx,dy,spec)
    local sweep=spec.pattern=="sweep"
    local trace=sweep and patterns.sweepTrace or RaytraceSurfaces
    local reach=spec.range or 240
    if spec.range and not GameGetIsGamepadConnected() then
        local mx,my=DEBUG_GetMouseWorld()
        reach=math.min(reach,math.sqrt((mx-x)^2+(my-y)^2))
    end
    local hit,tx,ty=trace(x,y,x+dx*reach,y+dy*reach)
    local limit=hit and math.sqrt((tx-x)^2+(ty-y)^2) or reach
    if spec.range then
        if hit then limit=math.max(0,limit-2) end
        return {sx=x,sy=y,x=x+dx*limit,y=y+dy*limit,hit=true}
    end
    if sweep or spec.surfaceOnly then return {sx=x,sy=y,x=x+dx*limit,y=y+dy*limit,hit=hit} end
    local target
    for _,id in ipairs(EntityGetInRadiusWithTag(x,y,260,"enemy") or {}) do
        local box=EntityGetFirstComponent(id,"HitboxComponent")
        local cx,cy=EntityGetFirstHitboxCenter(id)
        if box and cx then
            local hw=(ComponentGetValue2(box,"aabb_max_x")-ComponentGetValue2(box,"aabb_min_x"))/2
            local hh=(ComponentGetValue2(box,"aabb_max_y")-ComponentGetValue2(box,"aabb_min_y"))/2
            local ax,bx=interval(x,dx,cx-hw,cx+hw)
            local ay,by=interval(y,dy,cy-hh,cy+hh)
            local distance=math.max(0,ax,ay)
            if distance<=math.min(bx,by,limit) then
                target,limit=id,distance
            end
        end
    end
    return {sx=x,sy=y,x=x+dx*limit,y=y+dy*limit,target=target,hit=target~=nil or hit}
end

-- Sample around the open side of the mark. A terrain hit can lie one pixel
-- inside the solid, while a locked actor's mark is its hitbox center.
local bearings={}
for i=0,15 do
    local angle=i*math.pi/8
    bearings[#bearings+1]={x=math.sin(angle),y=math.cos(angle)}
end
local function strikePath(x,y,ox,oy,spec)
    if spec.placed then
        if DoesWorldExistAt(math.floor(x)-1,math.floor(y)-1,math.ceil(x)+1,math.ceil(y)+1) then
            return {sx=x,sy=y,x=x,y=y,radius=spec.radius}
        end
        return
    end
    local trace=spec.pattern=="sweep" and patterns.sweepTrace or RaytraceSurfaces
    local px,py=x+ox,y+oy
    if spec.surfaceOnly and not trace(px,py,x-ox,y-oy) then return end
    local nx,ny=0,-1
    local nearest,hx,hy
    for _,d in ipairs(bearings) do
        local hit,tx,ty=trace(px,py,px+d.x*72,py+d.y*72)
        if hit then
            local distance=(tx-px)^2+(ty-py)^2
            if not nearest or distance<nearest then
                nearest,hx,hy,nx,ny=distance,tx,ty,-d.x,-d.y
            end
        end
    end
    if nearest and spec.pattern=="sweep" then
        nx,ny=patterns.sweepNormal(hx,hy,nx,ny)
    elseif nearest then
        local ok,dx,dy=GetSurfaceNormal(hx+nx*2,hy+ny*2,8,12)
        if ok and dx*nx+dy*ny>0.3 then
            local length=math.sqrt(dx*dx+dy*dy)
            nx,ny=dx/length,dy/length
        end
    end
    local function lane(dx,dy)
        local sx,sy=x+dx*72,y+dy*72
        local hit,tx,ty=trace(px,py,sx,sy)
        local length=hit and math.min(72,(tx-x)*dx+(ty-y)*dy-4) or 72
        if length<10 then return end
        sx,sy=x+dx*length,y+dy*length
        if not DoesWorldExistAt(math.floor(math.min(sx,x))-1,math.floor(math.min(sy,y))-1,
            math.ceil(math.max(sx,x))+1,math.ceil(math.max(sy,y))+1) then return end
        -- Trace back to just before impact so the marked solid itself is allowed.
        if trace(sx,sy,x+dx*2,y+dy*2) then return end
        local extra=spec.through or 0
        local endX,endY=x-extra*dx,y-extra*dy
        if extra>0 and not DoesWorldExistAt(math.floor(math.min(x,endX))-1,math.floor(math.min(y,endY))-1,
            math.ceil(math.max(x,endX))+1,math.ceil(math.max(y,endY))+1) then return end
        return {sx=sx,sy=sy,x=x,y=y,endX=endX,endY=endY,frames=math.ceil((length+extra)*60/spec.speed),
            radius=spec.radius,danger=spec.danger,nx=nx,ny=ny}
    end
    local path=lane(nx,ny)
    if path then return path end
    -- At corners try nearby directions on the same exposed side.
    for _,angle in ipairs({math.pi/8,-math.pi/8,math.pi/4,-math.pi/4}) do
        local c,s=math.cos(angle),math.sin(angle)
        path=lane(nx*c-ny*s,nx*s+ny*c)
        if path then return path end
    end
end

local function salvoPath(v)
    for offset=0,#v.route-1 do
        local p=patterns.point(v.route,v.index+offset,v.sweep)
        local path=strikePath(p.x,p.y,p.ox,p.oy,v.spec)
        if path then return path end
        if p.alternatives then
            for _,other in ipairs(p.alternatives) do
                path=strikePath(other.x,other.y,other.ox,other.oy,v.spec)
                if path then return path end
            end
        end
    end
    local m=v.origin
    return strikePath(m.x,m.y,m.ox,m.oy,v.spec)
end

local function refreshPath(x,y,ox,oy,force,px,py)
    local frame=GameGetFrameNum()
    local memo=call.probe
    if not force and memo and frame-memo.frame<6 and memo.x==x and memo.y==y and memo.ox==ox and memo.oy==oy and memo.px==px and memo.py==py then return end
    call.probe={x=x,y=y,ox=ox,oy=oy,frame=frame,px=px,py=py}
    local spec=patterns[call.project]
    if spec.pattern=="area" and call.phase=="aim" then
        call.route=patterns.area(spec,x,y,call.connectedAt%2147483646+1)
        call.center={x=x,y=y,radius=spec.spread+(spec.danger or spec.radius)}
        call.route[1].ox,call.route[1].oy=ox,oy
        call.path=strikePath(x,y,ox,oy,spec)
    else
        call.path=strikePath(x,y,ox,oy,spec)
        if spec.pattern=="sweep" and call.phase=="aim" and call.path then
            call.route=patterns.sweep(spec,call.path,px,py,call.route)
        end
    end
end

local function rearm()
    call.due=nil
    call.phase=call.selected and "aim" or "ready"
    call.target,call.marker,call.beam,call.path,call.probe=nil,nil,nil,nil,nil
end

local function projectStatus(state,project)
    local service=services[project]
    if not service then return "no_projects" end
    if not call and salvo and patterns[project] then return "support_busy" end
    if call then return call.phase=="finished" and "switch_designator" or "support_busy" end
    local required=pricing[project].level
    if NHStore.level(state,service.station)<required then return "need_station_"..required end
    if project=="site_radar" and locations.active(GameGetFrameNum()) then return "radar_active" end
    if radarScripts[project] and hasRadar(owner,project) then return "radar_active" end
    if (state.resources[service.resource] or 0)<pricing[project].cost then return "insufficient_packs" end
end

local function browse(c,state)
    local edge={}
    local mapped=false
    for _,key in ipairs(directions) do
        local down=mappedDown(c,key)
        if key=="Up" then down=down or mappedDown(c,"Fly") end
        edge[key]=down
        mapped=mapped or down
    end
    for _,key in ipairs(directions) do
        -- The movement lock can suppress the mapped fields. Keep command entry live in that case.
        local down=edge[key] or (not mapped and rawDirection(key))
        edge[key]=down and not stageKeys[key] and not menu.fresh
        stageKeys[key]=down
    end
    menu.fresh=false
    if menu.level==1 then
        if edge.Left then menu.category=(menu.category+2)%4+1
        elseif edge.Right then menu.category=menu.category%4+1
        elseif edge.Down then menu.level,menu.project=2,1 end
    elseif edge.Left then
        menu.level=menu.level-1
    else
        local projects=S.projects[menu.category]
        local previous=menu.project
        if edge.Up then menu.project=math.max(1,menu.project-1)
        elseif edge.Down and menu.project<#projects then menu.project=menu.project+1 end
        local project=projects[menu.project]
        if menu.project~=previous or projectStatus(state,project) then
            menu.level=2
        elseif edge.Right and not edge.Up and not edge.Down then
            if menu.level==2 then
                menu.level=3
            else
                local link=state.gearLink
                call={phase="connecting",project=project,targeted=patterns[project]~=nil,tracking=project=="tracking_strike",linkId=link.id,
                    weapon=services[project]==resupply and project~="resupply" and project or nil,
                    tier=project=="resupply" and NHStore.level(state,"resupply") or nil,
                    connectedAt=GameGetFrameNum()+60*NHEquipment.links[link.item.kind].seconds}
                menu=nil
            end
        end
    end
end

function S.input(state,player,blocked)
    restoreMovementInput()
    restoreEating()
    if player and player==owner and state and not state.gearLink and salvo then
        closeCall()
        closeCommands()
        eatUntilUp=nil
        return false
    end
    if not player or not state or not state.gearLink then
        if owner then S.reset(player and owner==player) end
        return false
    end
    if owner~=player then S.reset(owner==nil); owner=player end
    if call and state.gearLink.id~=call.linkId then closeCall() end
    local onBoard=aboard(EntityGetTransform(player))
    if onBoard and (call or commandLink or eatUntilUp) then cancelOnBoard() end
    local c=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    if blocked or not c or ComponentGetValue2(c,"enabled")==false then
        closeCommands(); eatUntilUp=nil; return false
    end
    local opening=InputIsKeyJustDown(224)
    if opening and onBoard then
        GamePrint(GameTextGetTranslatedOrNot("$nh_support_disabled_aboard"))
        opening=false
    end
    -- Read the real Down sample before closing the menu clears its delay line.
    if commandLink or opening or eatUntilUp then
        eatUntilUp=rawDirection("Down") or mappedDown(c,"Down") or ComponentGetValue2(c,"mButtonDownEat")==true
    end
    if commandLink and (not InputIsKeyDown(224) or commandLink~=state.gearLink.id) then closeCommands() end
    if opening then
        commandLink=state.gearLink.id
        menu={level=1,category=2,fresh=true}
    end
    local owned=commandLink~=nil
    if commandLink then
        if menu then browse(c,state) end
        holdStance(player,c)
    elseif call and call.targeted then
        if call.phase=="connecting" and GameGetFrameNum()>=call.connectedAt then
            call.phase,call.anchor,call.selected="aim",NHNative.held(player),true
        end
        owned=call.selected==true
        if call.selected and NHNative.held(player)~=call.anchor then
            leaveSlot()
        elseif call.phase~="connecting" then
            local dir=wheel(c)
            if dir then cycle(player,c,dir) end
        end
        if call and call.selected then
            owned=true
            local x,y,dx,dy=handRay(player)
            if x then call.grip={x=x,y=y,dx=dx,dy=dy} end
            if call.phase=="aim" then call.beam=x and aim(x,y,dx,dy,patterns[call.project]) end
            local b=call.beam
            if b and b.hit and (not call.tracking or b.target) then
                local x,y=b.x,b.y
                local ox,oy=-dx*3,-dy*3
                if b.target then x,y=EntityGetFirstHitboxCenter(b.target); ox,oy=0,0 end
                local px,py=EntityGetTransform(player)
                refreshPath(x,y,ox,oy,false,px,py)
                if InputIsMouseButtonJustDown(1) and call.path then
                    call.phase,call.target,call.marker="queued",b.target,{x=x,y=y,ox=ox,oy=oy}
                    call.due=GameGetFrameNum()+(patterns[call.project].delay or S.delay)
                    call.beam=nil
                end
            elseif call.phase=="aim" then
                call.path,call.probe,call.route,call.center=nil,nil,nil,nil
            end
        end
    end
    if commandLink or eatUntilUp then blockEating(player,c) end
    if owned and InputIsMouseButtonDown(1) then releaseFire=true end
    if not InputIsMouseButtonDown(1) then releaseFire=false end
    if owned or releaseFire then
        -- Native switching can equip another wand later in this same frame.
        -- Keep the held click from casting it even if the engine resamples Fire.
        if releaseFire then
            local untilFrame=GameGetFrameNum()+2
            for _,id in ipairs(GameGetAllInventoryItems(player) or {}) do
                if EntityHasTag(id,"wand") then
                    local a=EntityGetFirstComponentIncludingDisabled(id,"AbilityComponent")
                    if a and ComponentGetValue2(a,"mNextFrameUsable")<untilFrame then
                        ComponentSetValue2(a,"mNextFrameUsable",untilFrame)
                    end
                end
            end
        end
        for _,key in ipairs({"Fire","Fire2","LeftClick","RightClick","Throw"}) do clear(c,key) end
        ComponentSetValue2(c,"mButtonLastFrameFire",-1)
        for _,key in ipairs({"Fire","Fire2","Throw"}) do ComponentSetValue2(c,"mButtonDownDelayLine"..key,0) end
        return true
    end
    return false
end

function S.pay(draft,linkId,project,boxTier)
    project=project or "tracking_strike"
    local service=services[project]
    if not draft.gearLink or (linkId and draft.gearLink.id~=linkId) then return false,"Data link unavailable." end
    if not service then return false,"Unknown support project." end
    if NHStore.level(draft,service.station)<math.max(boxTier or 0,pricing[project].level) then return false,"Support station level too low." end
    local cost=pricing[project].cost
    if (draft.resources[service.resource] or 0)<cost then return false,service.shortage end
    NHStore.deductStock(draft.resources,{[service.resource]=cost})
    return true
end

local function scan(player,project,pay,report)
    if project=="site_radar" then return locations.scan(player,pay,report) end
    local x,y=EntityGetTransform(player)
    local radar=radarScripts[project]
    if radar and hasRadar(player,project) then report("Radar already active."); return end
    local vitality=project=="regeneration_field"
    local file=vitality and "data/entities/projectiles/deck/regeneration_field.xml" or
        ("mods/noita_hideout/files/"..(radar and project or "recon_scan")..".xml")
    local id=EntityLoad(file,x,y)
    if not id or id==0 then report("Recon scan failed."); return end
    if radar then EntityAddChild(player,id)
    elseif not EntityGetFirstComponentIncludingDisabled(id,vitality and "ProjectileComponent" or "MagicXRayComponent") then
        EntityKill(id); report("Recon scan failed."); return
    end
    if not pay() then
        local shot=EntityGetFirstComponentIncludingDisabled(id,"ProjectileComponent")
        if shot then EntityRemoveComponent(id,shot) end
        EntityKill(id)
    end
end

local function launchRound(player,path,spec)
    local id=EntityLoad(spec.projectile,path.sx,path.sy)
    if not id or id==0 then return end
    local shot=EntityGetFirstComponentIncludingDisabled(id,"ProjectileComponent")
    local velocity=EntityGetFirstComponentIncludingDisabled(id,"VelocityComponent")
    if not shot or not velocity then
        if shot then EntityRemoveComponent(id,shot) end
        EntityKill(id)
        return
    end
    if spec.placed then
        ComponentSetValue2(shot,"mWhoShot",player)
        local genome=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
        if genome then ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(genome,"herd_id")) end
        ComponentSetValue2(velocity,"mVelocity",0,0)
        return {id=id,component=shot,path=path}
    end
    GameShootProjectile(player,path.sx,path.sy,path.endX,path.endY,id)
    local x,y,angle,scaleX,scaleY=EntityGetTransform(id)
    if x~=path.sx or y~=path.sy then EntityApplyTransform(id,path.sx,path.sy,angle,scaleX,scaleY) end
    ComponentSetValue2(shot,"mWhoShot",player)
    ComponentSetValue2(velocity,"gravity_y",0)
    ComponentSetValue2(velocity,"air_friction",0)
    ComponentSetValue2(velocity,"mVelocity",(path.endX-path.sx)*60/path.frames,(path.endY-path.sy)*60/path.frames)
    ComponentSetValue2(shot,"lifetime_randomness",0)
    -- A contact payload must cross the marked surface before its flight timer expires.
    ComponentSetValue2(shot,"lifetime",path.frames+(spec.surfaceOnly and 3 or 0))
    ComponentObjectSetValue2(shot,"config_explosion","explosion_radius",path.radius)
    if spec.direct then ComponentSetValue2(shot,"damage",spec.direct) end
    if spec.blast then ComponentObjectSetValue2(shot,"config_explosion","damage",spec.blast) end
    return {id=id,component=shot,path=path,expires=GameGetFrameNum()+path.frames+2}
end

local function advanceSalvo(player)
    if not salvo or GameGetFrameNum()<salvo.due then return end
    if salvo.index>salvo.spec.shots then salvo=nil; return end
    local path=salvoPath(salvo)
    if path then airborne=launchRound(player,path,salvo.spec) or airborne end
    salvo.index=salvo.index+1
    salvo.due=GameGetFrameNum()+salvo.spec.interval
    if salvo.index>salvo.spec.shots and airborne then salvo.due=airborne.expires end
end

function S.update(state,player,commit,report)
    resupply.eject()
    advanceSalvo(player)
    -- Travel or rescue can move the caller between the input and delivery hooks.
    if (call or commandLink) and aboard(EntityGetTransform(player)) then cancelOnBoard() end
    if not call then return end
    if not state.gearLink or state.gearLink.id~=call.linkId or owner~=player then S.reset(); return end
    local service=services[call.project]
    local order=call
    local function pay()
        return commit(function(draft) return S.pay(draft,order.linkId,order.project,order.tier) end)
    end
    if not call.paid and call.phase~="finished" and (state.resources[service.resource] or 0)<pricing[call.project].cost then
        closeCall()
        report(service.shortage)
        return
    end
    if service==recon and not call.targeted then
        if GameGetFrameNum()<call.connectedAt then return end
        closeCall()
        scan(player,order.project,pay,report)
        return
    end
    if service==resupply or service==reinforcements then
        if call.phase=="connecting" then
            if GameGetFrameNum()<call.connectedAt then return end
            if not resupply.launch(call,player) then
                closeCall()
                report(service==resupply and "No clear supply landing site." or "No room for reinforcement.")
            end
        else
            local result=resupply.advance(call)
            if result=="landed" then
                local ok,err
                if service==resupply then ok,err=resupply.deliver(call,pay)
                else ok=reinforcements.deploy(player,call,pay,report) end
                if ok then EntityLoad("mods/noita_hideout/files/pod_open_fx.xml",call.x,call.y) end
                closeCall()
                if err then report(err) end
            elseif result=="failed" then
                closeCall()
                report(service==resupply and "No clear supply landing site." or "No room for reinforcement.")
            end
        end
        return
    end
    if call.phase~="queued" then return end
    local m=call.marker
    if call.tracking then
        local id=call.target
        if not EntityGetIsAlive(id) or not EntityHasTag(id,"enemy") then rearm(); return end
        local damage=EntityGetFirstComponentIncludingDisabled(id,"DamageModelComponent")
        if damage and ComponentGetValue2(damage,"hp")<=0 then rearm(); return end
        local x,y=EntityGetFirstHitboxCenter(id)
        if not x or not DoesWorldExistAt(math.floor(x)-1,math.floor(y)-1,math.ceil(x)+1,math.ceil(y)+1) then rearm(); return end
        m.x,m.y=x,y
    end
    local due=GameGetFrameNum()>=call.due
    local spec=patterns[call.project]
    if spec.shots then
        if not due then return end
        local p=call.route[1]
        call.path=strikePath(p.x,p.y,p.ox,p.oy,spec)
    else refreshPath(m.x,m.y,m.ox,m.oy,due) end
    if not due then return end
    local path=call.path
    if not path then rearm(); report("No clear strike path."); return end
    local shot=launchRound(player,path,spec)
    if not shot then rearm(); return end
    local rejected=false
    if not commit(function(draft)
        local ok,reason=S.pay(draft,call.linkId,call.project)
        rejected=not ok
        return ok,reason
    end) then
        EntityRemoveComponent(shot.id,shot.component)
        EntityKill(shot.id)
        if rejected then closeCall() else rearm() end
        return
    end
    if spec.alert then
        shot.alert=spec.alert
        activeZones[#activeZones+1]=shot
    elseif not spec.placed then
        airborne=shot
    end
    if spec.shots then
        salvo={spec=spec,route=call.route,center=call.center,origin=call.marker,sweep=spec.pattern=="sweep",
            index=2,due=GameGetFrameNum()+spec.interval}
    end
    if call.selected then
        call.phase,call.target,call.marker,call.path,call.route,call.center="finished",nil,nil,nil,nil,nil
    else closeCall() end
end

function S.view(state,player)
    if airborne and (GameGetFrameNum()>airborne.expires or not EntityGetIsAlive(airborne.id)) then airborne=nil end
    for i=#activeZones,1,-1 do
        if not EntityGetIsAlive(activeZones[i].id) then table.remove(activeZones,i) end
    end
    if not menu and not call and not airborne and not salvo and #activeZones==0 then return end
    local x,y=EntityGetTransform(player)
    if aboard(x,y) then return end
    local projects=menu and S.projects[menu.category]
    local project=menu and menu.level>=2 and projects[menu.project]
    local status=menu and menu.level>=2 and projectStatus(state,project)
    local payment
    local service=services[project]
    if service then
        payment={resource=service.resource,cost=pricing[project].cost,stock=state.resources[service.resource] or 0}
    end
    return {menu=menu,projects=projects,projectStatus=status,
        call=call,x=x,y=y,payment=payment,airborne=airborne,salvo=salvo,activeZones=activeZones,
        alert=call and patterns[call.project] and patterns[call.project].alert}
end
return S
