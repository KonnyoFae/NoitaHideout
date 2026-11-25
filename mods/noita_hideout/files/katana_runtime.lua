local root="mods/noita_hideout/files/"
local K=NHKatanas or dofile(root.."katanas.lua")
local combat=dofile(root.."katana_combat.lua")
local fields=dofile(root.."katana_field.lua")
local resources=dofile(root.."katana_resources.lua")
local rewards=dofile(root.."katana_rewards.lua")
local visual=dofile(root.."katana_visual.lua")
local fx=dofile(root.."katana_fx.lua")
local movement=dofile(root.."katana_movement.lua")
local buttons=dofile(root.."katana_input.lua")
local M={}
local current,input,serial=nil,nil,0
local function first(id,kind,tag)
    if tag then return EntityGetFirstComponentIncludingDisabled(id,kind,tag) end
    return EntityGetFirstComponentIncludingDisabled(id,kind)
end
local function network(name,...)
    if CrossCall and ModIsEnabled("quant.ew") and GlobalsGetValue("nh_ew.status","")~="" then CrossCall(name,...) end
end
local function clock(player)
    return first(player,"VariableStorageComponent","nh_katana_clock")
        or EntityAddComponent2(player,"VariableStorageComponent",{_tags="nh_katana_clock"})
end
local function cooldown(player,untilFrame)
    local c=clock(player)
    if c then ComponentSetValue2(c,"value_int",untilFrame) end
end
local function ready(player,frame)
    local c=clock(player)
    return c and frame>=ComponentGetValue2(c,"value_int")
end
local function guard(player,untilFrame)
    if not player or not EntityGetIsAlive(player) then return end
    local c=first(player,"VariableStorageComponent","nh_katana_dash_guard")
    if not c and untilFrame>0 then c=EntityAddComponent2(player,"VariableStorageComponent",{_tags="nh_katana_dash_guard"}) end
    if c then ComponentSetValue2(c,"value_int",untilFrame) end
end
local function leaveField()
    if not current or not current.field then return end
    movement.release(current.player)
    fields.cancel(current.field)
    network("ew_hideout_katana_field",current.fieldToken,0,0,0,0)
    current.field,current.fieldToken,current.fieldEnd=nil,nil,nil
    if current.attack and current.attack.plunder then current.attack=nil end
end
local function leaveShortField()
    if not current or not current.shortField then return end
    fields.cancel(current.shortField)
    network("ew_hideout_katana_field",current.shortToken,0,0,0,0)
    current.shortField,current.shortToken,current.shortEnd=nil,nil,nil
end
local function restricted()
    return current and current.field and not K.types[current.kind].freeMovement
end
local function cancel()
    leaveShortField()
    leaveField()
    if current then guard(current.player,0);visual.reset(current.player) end
    current=nil
end
function M.reset(saved)
    cancel()
    input=nil
    visual.reset()
    movement.reset()
    if saved then
        for _,field in ipairs(EntityGetWithTag("nh_katana_field") or {}) do fields.cancel(field) end
    end
end
local function suppress(c)
    for _,key in ipairs({"Fire","Fire2","Throw","LeftClick","RightClick"}) do
        ComponentSetValue2(c,"mButtonDown"..key,false)
        ComponentSetValue2(c,"mButtonFrame"..key,-1)
    end
    ComponentSetValue2(c,"mButtonDownDelayLineFire",0)
    ComponentSetValue2(c,"mButtonDownDelayLineThrow",0)
    ComponentSetValue2(c,"mButtonDownDelayLineFire2",0)
end
-- Capture before vanilla item use or another UI handler consumes the buttons.
function M.capture(player,blocked)
    -- Polymorph can preserve a slowed original body while replacing the active player.
    -- Clean its serialized multiplier when that body returns without its old field.
    if player and (not current or current.player~=player or not current.field) then movement.release(player) end
    local weapon=player and NHNative.held(player)
    local kind=weapon and K.kind(weapon)
    if not kind then cancel();input=nil;return false end
    local c=first(player,"ControlsComponent")
    if not c then cancel();input=nil;return true end
    local equipped=not current or current.player~=player or current.weapon~=weapon
    if equipped then
        cancel()
        current={player=player,weapon=weapon,kind=kind,buttons={}}
        K.ensureBuiltInAction(weapon,kind)
        guard(player,0)
    end
    input=buttons.sample(current.buttons,c,GameGetFrameNum())
    input.player,input.weapon,input.blocked,input.frame=player,weapon,blocked,GameGetFrameNum()
    if equipped then current.release=input.heldAtEquip end
    if blocked then
        leaveShortField()
        leaveField()
        current.attack,current.charge=nil,nil
        current.release=input.heldAtEquip
        guard(player,0)
    end
    if restricted() and not blocked then movement.apply(player) end
    if not blocked then suppress(c) end
    return true
end

local function aim(player,preferMouse)
    local x,y,_,facing=EntityGetTransform(player)
    local dx,dy=NHProducts.aim(player,x,y-4,preferMouse)
    if not dx or dx*dx+dy*dy<0.0001 then dx,dy=facing and facing<0 and -1 or 1,0 end
    local length=math.sqrt(dx*dx+dy*dy)
    return x,y,dx/length,dy/length
end
local function token(player,frame)
    serial=serial+1
    return "nh_katana/"..player.."/"..frame.."/"..serial
end
local function slash(player,def,frame,heavy,plunder,preferMouse)
    local x,y,dx,dy=aim(player,preferMouse)
    local prefix=heavy and "heavy" or "quick"
    local a={token=token(player,frame),kind=current.kind,damage=def[prefix.."Damage"],width=def[prefix.."Width"],
        reach=def[prefix.."Reach"],fxReach=def[prefix.."FxReach"],distance=def[prefix.."Lunge"],
        lungeFrames=def[prefix.."LungeFrames"],duration=def[prefix.."Frames"],start=frame,dx=dx,dy=dy,hit={},plunder=plunder==true}
    if plunder and not def.freeMovement then a.distance=a.distance*movement.factor end
    current.attack=a
    cooldown(player,frame+(plunder and 6 or def[prefix.."Cooldown"]))
    GamePlaySound("data/audio/Desktop/player.bank","player/throw",x,y)
end
local function apply(player,a,x,y,handX,handY,showFx)
    local tipX,tipY=handX+a.dx*a.reach,handY+a.dy*a.reach
    local event={token=a.token,kind=a.kind,x1=x,y1=y,x2=tipX,y2=tipY,width=a.width,damage=a.damage,
        fxX=handX,fxY=handY,fxReach=a.fxReach,plunder=a.plunder==true,showFx=showFx}
    local hits=combat.apply(player,event,a.hit)
    network("ew_hideout_katana_attack",event)
    local angle,scale,flip=math.atan2(a.dy,a.dx),a.fxReach/64,a.dx<0 and -1 or 1
    if showFx then a.fx=fx.spawn(handX,handY,angle,a.kind,scale,flip)
    elseif a.fx then fx.follow(a.fx,handX,handY,angle,scale,flip) end
    if hits>0 and not a.sounded then
        GamePlaySound("data/audio/Desktop/player.bank","player/kick",tipX,tipY)
        a.sounded=true
    end
end
local function dash(player,def,frame,commit,preferMouse)
    local x,y,dx,dy=aim(player,preferMouse)
    local _,_,travelled=combat.safeStep(x,y,dx,dy,math.min(8,def.dashDistance))
    if travelled<2 then return false end
    if def.ammoCost and not resources.spend(player,current.weapon,commit,nil,def.ammoCost) then return false end
    current.attack={token=token(player,frame),kind=current.kind,start=frame,duration=def.dashFrames,lungeFrames=def.dashFrames,
        distance=def.dashDistance,reach=def.dashReach,fxReach=def.dashFxReach,dx=dx,dy=dy,hit={},
        width=def.dashWidth,damage=def.dashDamage,guarded=true}
    cooldown(player,frame+def.dashFrames+def.dashCooldown)
    guard(player,frame+def.dashFrames)
    GamePlaySound("data/audio/Desktop/player.bank","player/throw",x,y)
    return true
end
-- One ordinary press owns one charge. Its trigger policy belongs to the
-- weapon; the lifetime of an active Blade Mode belongs to the field entity.
local function startField(c,def,frame,fixedDuration,short,pay)
    local field,duration=fields.activate(c.player,{radius=K.zandatsu.radius,duration=fixedDuration,weapon=c.weapon},pay)
    if not field then return end
    local id=token(c.player,frame)
    if short then
        c.shortField,c.shortToken,c.shortEnd=field,id,frame+duration
    else
        c.field,c.fieldToken,c.fieldEnd=field,id,frame+duration
        if not def.freeMovement then movement.apply(c.player) end
    end
    local x,y=EntityGetTransform(field)
    network("ew_hideout_katana_field",id,x,y,K.zandatsu.radius,duration)
    if not short then GamePlaySound("data/audio/Desktop/projectiles.bank","player_projectiles/kantele/a/create",x,y) end
end

local function maintainField(c,field,id,deadline,frame)
    if not fields.active(field) then return false end
    local x,y=EntityGetTransform(field)
    local px,py=EntityGetTransform(c.player)
    if (px-x)^2+(py-y)^2>K.zandatsu.radius^2 then return false end
    if frame%15==0 then network("ew_hideout_katana_field",id,x,y,K.zandatsu.radius,deadline-frame) end
    return true
end

local function bladeMode(c,def,frame)
    if input.rightPress then
        leaveField()
        c.release=true
        return
    end
    if not def.freeMovement then movement.apply(c.player) end
    if input.left and ready(c.player,frame) then slash(c.player,def,frame,false,true) end
end

local function primary(c,def,charge,frame,commit)
    local full=frame-charge.start>=def.chargeFrames
    -- Murasama fires at full charge; the other blades resolve on release.
    if def.chargeAttack=="dash" and full then
        c.charge=nil
        dash(c.player,def,frame,commit,charge.mouse)
    elseif not input.left then
        c.charge=nil
        if def.chargeAttack=="stasis_dash" and full then
            leaveShortField()
            dash(c.player,def,frame,commit,charge.mouse)
        else
            slash(c.player,def,frame,def.chargeAttack=="heavy" and full,false,charge.mouse)
        end
    elseif def.chargeAttack=="stasis_dash" and full and not charge.opened then
        charge.opened=true
        startField(c,def,frame,def.shortStasisFrames,true,function() return true end)
    end
end

local function ordinary(c,def,frame,state,commit)
    if not c.charge then
        if input.leftPress then c.charge={hand="left",start=frame,mouse=input.mouseLeft}
        elseif input.rightPress then c.charge={hand="right",start=frame} end
    end
    local charge=c.charge
    if not charge then return end
    -- A fresh hold may begin during recovery. Releasing it during recovery
    -- discards it, so a tap cannot unexpectedly fire after the cooldown.
    if c.attack or not ready(c.player,frame) then
        if (charge.hand=="left" and not input.left) or (charge.hand=="right" and not input.right) then c.charge=nil end
        return
    end
    if charge.hand=="left" then
        primary(c,def,charge,frame,commit)
    elseif not input.right then
        c.charge=nil
    elseif frame-charge.start>=K.zandatsu.chargeFrames then
        c.charge=nil
        startField(c,def,frame,def.plunderDurationFrames,false,function()
            if def.durability then return resources.spendDurability(state,c.player,c.weapon) end
            local paid,points=resources.spend(c.player,c.weapon,commit,K.zandatsu.shieldCostFraction)
            if not paid then return false end
            return true,math.max(1,math.floor(points*60/K.zandatsu.shieldPointsPerSecond+0.5))
        end)
    end
end

-- Limit only displacement supplied by the swing. Walking out of the fixed
-- field still ends Blade Mode. Leave a subpixel margin for native float transforms.
local function fieldStep(field,x,y,dx,dy,distance)
    local cx,cy=EntityGetTransform(field)
    local ox,oy=x-cx,y-cy
    local radius=K.zandatsu.radius
    if (ox+dx*distance)^2+(oy+dy*distance)^2<=(radius-0.125)^2 then return distance end
    local along=ox*dx+oy*dy
    local exitDistance=math.sqrt(math.max(0,along*along+radius*radius-ox*ox-oy*oy))-along
    return math.min(distance,math.max(0,exitDistance-0.125))
end

local function advanceAttack(c,a,frame)
    local player=c.player
    local x,y,rotation,sx,sy=EntityGetTransform(player)
    local tx,ty=x,y
    local tick=frame-a.start+1
    if tick<=a.lungeFrames and not a.stopped then
        -- Linearly increasing steps sum to the configured travel distance.
        local distance=a.distance*2*tick/(a.lungeFrames*(a.lungeFrames+1))
        local moved
        tx,ty,moved=combat.safeStep(x,y,a.dx,a.dy,distance)
        a.stopped=moved+0.000001<distance
        if c.field and moved>0 then
            local vx,vy=tx-x,ty-y
            local travel=math.sqrt(vx*vx+vy*vy)
            if travel>0 then
                local inside=fieldStep(c.field,x,y,vx/travel,vy/travel,travel)
                tx,ty=x+vx*inside/travel,y+vy*inside/travel
            end
        end
        if moved>0 then EntitySetTransform(player,tx,ty,rotation or 0,sx or 1,sy or 1) end
        if a.guarded then
            local motion=first(player,"CharacterDataComponent")
            if motion then ComponentSetValue2(motion,"mVelocity",0,0) end
        end
    end
    -- The whole path from the previous hand to the new blade tip is one
    -- capsule. Terrain checks and the hit set apply to this one swing.
    apply(player,a,x,y-4,tx,ty-4,tick==1)
    if tick>=a.duration or (a.guarded and a.stopped) then
        c.attack=nil
        if a.guarded then guard(player,0) end
    end
    return math.atan2(a.dy,a.dx),0.08*math.sin(math.pi*tick/(a.duration+1))*(a.dx<0 and -1 or 1)
end

function M.update(state,player,commit,enabled)
    if player then rewards.claim(state,player,commit) end
    if not current or not input then return end
    local c=current
    -- Noita advances GameGetFrameNum between PreUpdate and PostUpdate.
    local inputAge=GameGetFrameNum()-input.frame
    if not player or c.player~=player or not EntityGetIsAlive(player) or NHNative.held(player)~=c.weapon
        or input.weapon~=c.weapon or inputAge<0 or inputAge>1 then cancel();return end
    local dm=first(player,"DamageModelComponent")
    if not dm or ComponentGetValue2(dm,"hp")<=0 then cancel();return end
    local frame=GameGetFrameNum()
    local def=K.types[c.kind]
    if input.blocked or not enabled then
        leaveShortField()
        leaveField()
        c.attack,c.charge=nil,nil
        c.release=input.heldAtEquip
        guard(player,0)
        visual.pose(player,c.weapon,c.kind,frame)
        return
    end
    if c.release then
        c.release=input.heldAtEquip
        visual.pose(player,c.weapon,c.kind,frame)
        local item=def.durability and first(c.weapon,"ItemComponent")
        return {kind=c.kind,remaining=item and ComponentGetValue2(item,"uses_remaining")}
    end
    if c.shortField and not maintainField(c,c.shortField,c.shortToken,c.shortEnd,frame) then leaveShortField() end
    if c.field then
        if maintainField(c,c.field,c.fieldToken,c.fieldEnd,frame) then bladeMode(c,def,frame)
        else leaveField(); c.release=input.left or input.right end
    else
        ordinary(c,def,frame,state,commit)
    end
    local angle,kick
    if c.attack then angle,kick=advanceAttack(c,c.attack,frame) end
    visual.pose(player,c.weapon,c.kind,frame,{angle=angle,handKick=kick})
    local charge=c.charge
    local preparing=charge and charge.hand=="right"
    local progress=charge and math.min(1,(frame-charge.start)/(preparing and K.zandatsu.chargeFrames or def.chargeFrames))
    local item=def.durability and first(c.weapon,"ItemComponent")
    return {kind=c.kind,charge=progress,preparing=preparing,plunder=c.field and math.max(0,c.fieldEnd-frame),
        stasis=c.shortField and math.max(0,c.shortEnd-frame),remaining=item and ComponentGetValue2(item,"uses_remaining"),
        releaseDash=def.chargeAttack=="stasis_dash",heavyReady=charge and not preparing and progress==1}
end
return M
