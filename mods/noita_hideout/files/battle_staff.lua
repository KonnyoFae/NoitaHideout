local staff={}
local root="mods/noita_hideout/files/"
local dragonAttack=dofile(root.."companions/dragon_attack.lua")
local formRoot=root.."staff_forms/"
local forms={}
local payloads=dofile(root.."staff_payloads.lua")
local started,wasDown,swing,lastMode

local function unstableForm(path)
    local name=path and path:match("([^/]+)%.xml$")
    return name=="acidshooter" or name=="acidshooter_weak"
end

local pool={}
local herds={}
local function herdOf(path,seen)
    if herds[path]~=nil then return herds[path] end
    if seen[path] then return false end
    seen[path]=true
    local xml=(ModTextFileGetContent(path) or ""):gsub("<!%-%-.-%-%->","")
    local herd=xml:match('<GenomeDataComponent%s[^>]-herd_id="([^"]+)"')
    if not herd then
        local base=xml:match('<Base%s+file="(data/entities/[%w_/]+%.xml)"')
        if base then herd=herdOf(base,seen) end
    end
    herds[path]=herd or false
    return herds[path]
end

function staff.register()
    forms,pool,herds={},{},{}
    for _,path in ipairs(PolymorphTableGet(false) or {}) do
        local name=path:match("^data/entities/animals/([%w_/]+)%.xml$")
        if name and not forms[path] and not unstableForm(path) and not name:find("boss",1,true)
            and not name:find("necromancer_shop",1,true) and not name:find("illusions/",1,true) then
            local xml=ModTextFileGetContent(path)
            local tags=xml and xml:match('<Entity%s[^>]-tags="([^"]*)"') or ""
            if xml and xml~="" and not (","..tags..","):find(",boss,",1,true) and not xml:find("$animal_acidshooter",1,true) and not xml:find("/acidshooter",1,true) then
                forms[path]=formRoot..name.."_effect.xml"
                ModTextFileSetContent(forms[path],'<Entity><Base file="data/entities/misc/effect_polymorph.xml"><GameEffectComponent _tags="nh_staff_mimic" frames="3600" polymorph_target="'..path..'" /></Base></Entity>')
                pool[#pool+1]={path=path,name=name:match("([^/]+)$"),herd=herdOf(path,{})}
            end
        end
    end
    table.sort(pool,function(left,right) return left.path<right.path end)
end

local function resolveForm(player,id)
    local path=EntityGetFilename(id) or ""
    local name=path:match("([^/]+)%.xml$") or ""
    local species=EntityGetName(id) or ""
    local acid=unstableForm(path) or species=="$animal_acidshooter"
    local boss=EntityHasTag(id,"boss") or path:find("boss",1,true) or species:find("boss",1,true)
    local special=acid or boss
        or not EntityHasTag(id,"enemy") or EntityHasTag(id,"nh_reinforcement") or EntityHasTag(id,"noita_hideout_companion")
        or EntityHasTag(id,"nh_deployed_turret") or EntityGetHerdRelationSafe(player,id)>=40 or GameGetGameEffectCount(id,"CHARM")>0
    if not special and forms[path] then return forms[path] end
    local genome=EntityGetFirstComponentIncludingDisabled(id,"GenomeDataComponent")
    local herd=genome and HerdIdToString(ComponentGetValue2(genome,"herd_id"))
    local family=name:match("^([^_]+)_")
    local mechanical=EntityHasTag(id,"nh_deployed_turret") or EntityHasTag(id,"nh_reinforcement")
    local preferred=acid and "slimeshooter" or mechanical and "roboguard"
    local best,score
    for _,candidate in ipairs(pool) do
        local rank
        if acid and preferred==candidate.name then rank=5
        elseif candidate.name==name or species=="$animal_"..candidate.name then rank=4
        elseif family and candidate.name:match("^([^_]+)_")==family then rank=3
        elseif preferred==candidate.name or (herd and herd~="-1" and candidate.herd==herd) or (mechanical and candidate.herd=="robot") then rank=2 end
        if rank and not (boss and candidate.path==path) and (not score or rank>score) then best,score=candidate,rank end
    end
    if best then return forms[best.path],best.name end
end

function staff.reset() started,wasDown,swing,lastMode=nil,false,nil,nil end
staff.reset()

function staff.guardMimic(body)
    if not body or not EntityGetFirstComponentIncludingDisabled(body,"DamageModelComponent") then return false end
    local effect=GameGetGameEffect(body,"POLYMORPH")
    if not effect or effect==0 then return false end
    if not ComponentHasTag(effect,"nh_staff_mimic") then
        local target=ComponentGetValue2(effect,"polymorph_target") or ""
        if target:sub(1,#formRoot)~=formRoot then return false end
    end
    if EntityHasTag(body,"nh_staff_mimic_hit") then
        local frames=ComponentGetValue2(effect,"frames")
        if frames>1 or frames<0 then ComponentSetValue2(effect,"frames",1) end
    elseif not EntityGetFirstComponentIncludingDisabled(body,"LuaComponent","nh_staff_mimic_guard") then
        EntityAddComponent2(body,"LuaComponent",{_tags="nh_staff_mimic_guard",execute_every_n_frame=-1,
            script_damage_about_to_be_received=root.."staff_mimic_damage.lua"})
        print("[noita_hideout] mimic active: "..EntityGetFilename(body))
    end
    return true,not EntityHasTag(body,"nh_staff_mimic_hit") and ComponentGetValue2(effect,"frames") or nil
end

local function hostile(player,id)
    return id~=player and EntityHasTag(id,"enemy") and not EntityHasTag(id,"nh_reinforcement")
        and not EntityHasTag(id,"noita_hideout_companion") and not EntityHasTag(id,"nh_deployed_turret")
        and EntityGetHerdRelationSafe(player,id)<40
end

local function push(id,dx,dy,speed)
    local body=EntityGetFirstComponent(id,"PhysicsBodyComponent") or EntityGetFirstComponent(id,"PhysicsBody2Component")
    if body then PhysicsApplyForce(id,dx*speed,dy*speed) end
    local motion=EntityGetFirstComponent(id,"CharacterDataComponent") or EntityGetFirstComponent(id,"VelocityComponent")
    if motion then
        local vx,vy=ComponentGetValue2(motion,"mVelocity")
        local impulse=math.max(0,speed-vx*dx-vy*dy)
        ComponentSetValue2(motion,"mVelocity",vx+dx*impulse,vy+dy*impulse)
    end
end

-- Check the nearest point on the swept staff against the actual rigid body.
-- A box may stop the ray at its own surface, well before its entity origin.
local function bodyContacts(x,y,dx,dy,stroke,halfStep,radius)
    local contacts={}
    for _,body in ipairs(PhysicsBodyIDQueryBodies(x-radius,y-radius,x+radius,y+radius) or {}) do
        if not stroke.bodies[body] then
            local bx,by=PhysicsBodyIDGetWorldCenter(body)
            if bx then
                bx,by=PhysicsPosToGamePos(bx,by)
                local ax,ay=bx-x,by-y
                local angle=math.atan2(dy,dx)+math.max(-halfStep,math.min(halfStep,math.atan2(dx*ay-dy*ax,dx*ax+dy*ay)))
                local nx,ny=math.cos(angle),math.sin(angle)
                local along=math.max(0,math.min(radius,ax*nx+ay*ny))
                local tx,ty=x+nx*along,y+ny*along
                local wall,wx,wy=RaytracePlatforms(x,y,tx,ty)
                local pad=2
                if wall then tx,ty,pad=wx,wy,0.5 end
                for _,overlap in ipairs(PhysicsBodyIDQueryBodies(tx-pad,ty-pad,tx+pad,ty+pad) or {}) do
                    if overlap==body then contacts[body]={x=tx,y=ty}; break end
                end
            end
        end
    end
    return contacts
end

local function looseObject(id,body)
    return not EntityHasTag(id,"enemy") and not EntityHasTag(id,"nh_reinforcement")
        and not EntityHasTag(id,"noita_hideout_companion") and not EntityHasTag(id,"nh_deployed_turret")
        and not EntityGetFirstComponent(id,"GenomeDataComponent") and (body or EntityGetFirstComponent(id,"ItemComponent"))
end

local function strike(player,stroke,id,x,y)
    if not stroke.sounded then
        GamePlaySound("data/audio/Desktop/player.bank","player/kick",x,y)
        stroke.sounded=true
    end
    if not id or stroke.hit[id] or not EntityGetIsAlive(id) then return end
    stroke.hit[id]=true
    if EntityGetFirstComponent(id,"DamageModelComponent") or hostile(player,id) then
        EntityInflictDamage(id,1,"DAMAGE_MELEE","$nh_hideout_battle_staff","NORMAL",
            stroke.kx*80,stroke.ky*80,player,x,y,2)
    end
end

local function strikeTargets(player,x,y,dx,dy,stroke,halfStep)
    local width=2
    local radius=13+width
    local contacts=bodyContacts(x,y,dx,dy,stroke,halfStep,radius)
    -- A prop's origin may be outside the arc even though its near face was hit.
    for _,id in ipairs(EntityGetInRadius(x,y,radius+32) or {}) do
        local body=EntityGetFirstComponent(id,"PhysicsBodyComponent") or EntityGetFirstComponent(id,"PhysicsBody2Component")
        local eligible=id~=player and EntityGetRootEntity(id)==id and
            ((hostile(player,id) and GameGetGameEffectCount(id,"CHARM")==0) or looseObject(id,body))
        if body then
            if next(contacts) then
                for _,part in ipairs(PhysicsBodyIDGetFromEntity(id,body) or {}) do
                    if contacts[part] then
                        if eligible then contacts[part].owner=id else contacts[part]=nil end
                    end
                end
            end
        elseif eligible and not stroke.hit[id] then
            local tx,ty=EntityGetFirstHitboxCenter(id)
            if tx then
                local ax,ay=tx-x,ty-y
                local dist=math.sqrt(ax*ax+ay*ay)
                local arc=halfStep+math.asin(math.min(1,width/math.max(1,dist)))
                if dist<=radius and dx*ax+dy*ay>=dist*math.cos(arc) and not RaytracePlatforms(x,y,tx,ty) then
                    push(id,stroke.kx,stroke.ky,210)
                    strike(player,stroke,id,tx,ty)
                end
            end
        end
    end
    for body,contact in pairs(contacts) do
        stroke.bodies[body]=true
        PhysicsBodyIDApplyLinearImpulse(body,stroke.ix,stroke.iy,contact.x,contact.y)
    end
    -- Apply all impulses before damage can break a prop into new bodies.
    for _,contact in pairs(contacts) do strike(player,stroke,contact.owner,contact.x,contact.y) end
end

local function repel(player,x,y,dx,dy)
    for _,id in ipairs(EntityGetInRadius(x,y,80) or {}) do
        if id~=player and EntityGetRootEntity(id)==id then
            local body=EntityGetFirstComponent(id,"PhysicsBodyComponent") or EntityGetFirstComponent(id,"PhysicsBody2Component")
            if hostile(player,id) or looseObject(id,body) or EntityHasTag(id,"projectile") then
                local tx,ty=EntityGetTransform(id)
                if not RaytracePlatforms(x,y,tx,ty) then
                    local ax,ay=tx-x,ty-y
                    local dist=math.sqrt(ax*ax+ay*ay)
                    if dist>0.01 then push(id,ax/dist,ay/dist,340) else push(id,dx,dy,340) end
                end
            end
        end
    end
end

local poseStep=2*math.pi/64
local function showPose(gun,clock,name,frame)
    local sprite=EntityGetFirstComponent(gun,"SpriteComponent","enabled_in_hand")
    ComponentSetValue2(clock,"value_float",frame)
    if sprite and ComponentGetValue2(sprite,"rect_animation")~=name then
        ComponentSetValue2(sprite,"rect_animation",name)
        ComponentSetValue2(sprite,"next_rect_animation",name)
        EntityRefreshSprite(gun,sprite)
    end
end

local function pose(gun,clock,angle,frame)
    local x,y,rotation=EntityGetTransform(gun)
    local sprite=EntityGetFirstComponent(gun,"SpriteComponent","enabled_in_hand")
    if not sprite then return x,y,angle end
    -- Undo the native item's rotation and flips to select a frame in sprite space.
    local signX=ComponentGetValue2(sprite,"special_scale_x")<0 and -1 or 1
    local signY=ComponentGetValue2(sprite,"special_scale_y")<0 and -1 or 1
    local relative=angle-rotation
    local localAngle=math.atan2(signY*math.sin(relative),signX*math.cos(relative))
    local step=math.floor(localAngle/poseStep+0.5)
    local index=step%64
    local name="swing_"..swing.mode.."_"..index
    showPose(gun,clock,name,frame)
    return x,y,angle+signX*signY*(step*poseStep-localAngle)
end

local function advanceSwing(player,gun,clock,frame)
    local age=frame-swing.start
    if age>swing.duration then swing=nil;return end
    local progress=age/swing.duration
    local angle=swing.aim+swing.side*swing.arc*(2*progress*progress*(3-2*progress)-1)
    local x,y
    x,y,angle=pose(gun,clock,angle,frame)
    local center=(swing.last+angle)*0.5
    strikeTargets(player,x,y,math.cos(center),math.sin(center),swing,math.abs(angle-swing.last)*0.5)
    swing.last=angle
    if age==swing.duration then swing=nil end
end

local function orb(player,x,y,dx,dy)
    local id=EntityLoad(root.."projectiles/staff_orb.xml",x+dx*6,y+dy*6)
    if not id or id==0 then return false end
    GameShootProjectile(player,x+dx*6,y+dy*6,x+dx*120,y+dy*120,id)
    local shot=EntityGetFirstComponent(id,"ProjectileComponent")
    ComponentSetValue2(shot,"mWhoShot",player)
    local genome=EntityGetFirstComponent(player,"GenomeDataComponent")
    if genome then ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(genome,"herd_id")) end
    ComponentSetValue2(EntityGetFirstComponent(id,"VelocityComponent"),"mVelocity",dx*115,dy*115)
    return true
end

local function pulse(player,x,y,dx,dy)
    local buff=EntityLoad(root.."staff_mana.xml",x,y)
    if not buff or buff==0 then return false end
    EntityAddChild(player,buff)
    repel(player,x,y,dx,dy)
    for step=1,48 do
        local angle=step*math.pi/24
        local nx,ny=math.cos(angle),math.sin(angle)
        GameCreateParticle("spark_blue",x+nx*8,y+ny*8,2,nx*200,ny*200,true,true,false)
    end
    GamePlaySound("data/audio/Desktop/explosion.bank","explosions/magic_rocket_small",x,y)
    return true
end

local function mimic(player,x,y,dx,dy)
    local pad=GameGetIsGamepadConnected() and not InputIsMouseButtonDown(1)
    local mx,my=DEBUG_GetMouseWorld()
    local best,score
    local candidates={}
    for _,tag in ipairs({"enemy","nh_reinforcement","noita_hideout_companion","nh_deployed_turret","boss","homing_target"}) do
        for _,id in ipairs(EntityGetInRadiusWithTag(pad and x or mx,pad and y or my,pad and 180 or 14,tag) or {}) do
            if id~=player and not EntityHasTag(id,"polymorphed_player") and not EntityHasTag(id,"player_unit")
                and (tag~="homing_target" or EntityGetFirstComponentIncludingDisabled(id,"GenomeDataComponent")) then candidates[id]=true end
        end
    end
    for id in pairs(candidates) do
        local tx,ty=EntityGetTransform(id)
        local ax,ay=tx-x,ty-y
        local along=ax*dx+ay*dy
        local distance=pad and along or (tx-mx)^2+(ty-my)^2
        if (not pad or (along>0 and math.abs(ax*dy-ay*dx)<=12)) and (not score or distance<=score) then
            local form,substitute=resolveForm(player,id)
            if not score or distance<score or (distance==score and form and (not best.form or (best.substitute and not substitute))) then
                score,best=distance,{x=tx,y=ty,form=form,substitute=substitute,status=form and "ready" or "unsupported"}
            end
        end
    end
    return best
end

local function mimicCast(player,gun,mag,clock,frame,points,cost,form)
    return function(shield,state)
        if NHNative.held(player)~=gun or ComponentGetValue2(mag,"value_int")~=points or not shield.allowMimic(player) then return end
        local prior=ComponentGetValue2(clock,"value_int")
        ComponentSetValue2(mag,"value_int",points-cost)
        ComponentSetValue2(clock,"value_int",frame+60)
        print("[noita_hideout] mimic cast: "..form)
        local effect=LoadGameEffectEntityTo(player,form)
        if (not effect or effect==0) and EntityGetIsAlive(player) then
            ComponentSetValue2(mag,"value_int",points)
            ComponentSetValue2(clock,"value_int",prior)
            shield.sync(state,player)
        elseif effect and effect~=0 and EntityGetIsAlive(effect) then
            local body=EntityGetRootEntity(effect)
            if body and body~=0 and EntityHasTag(body,"polymorphed_player") then staff.guardMimic(body) end
        end
    end
end

local function quickStrike(player,gun,clock,x,y,dx,dy,frame,mode)
    local aim=math.atan2(dy,dx)
    local side=dx<0 and -1 or 1
    local arc=math.rad(48)
    -- A level strike lifts loose objects slightly off the floor.
    local kx,ky=dx,dy-0.28*math.abs(dx)
    local length=math.sqrt(kx*kx+ky*ky)
    kx,ky=kx/length,ky/length
    local ix,iy=GameVecToPhysicsVec(kx*150,ky*150)
    swing={mode=mode,start=frame,duration=6,side=side,arc=arc,aim=aim,last=aim-side*arc,
        kx=kx,ky=ky,ix=ix,iy=iy,hit={},bodies={}}
    GamePlaySound("data/audio/Desktop/player.bank","player/throw",x,y)
    dragonAttack(player,dx,dy)
    advanceSwing(player,gun,clock,frame)
    ComponentSetValue2(clock,"value_int",frame+7)
end

function staff.update(player,gun,mag,index,points,frame,blocked,reloading,canMimic)
    local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    local clock=EntityGetFirstComponentIncludingDisabled(gun,"VariableStorageComponent","nh_staff_clock")
    if not clock or not controls then staff.reset(); return points end
    local down=ComponentGetValue2(controls,"mButtonDownFire")
    local pressed=down and not wasDown
    wasDown=down
    local changed=lastMode and lastMode~=index
    lastMode=index
    local idle="charge_"..index.."_0"
    if blocked or changed then
        started,swing=nil,nil
        showPose(gun,clock,idle,frame)
        if not (index==3 and reloading) then return points end
    end

    local mode=NHFirearms.staffModes[index]
    local ready=frame>=ComponentGetValue2(clock,"value_int")
    local x,y=EntityGetTransform(player)
    local dx,dy=NHProducts.aim(player,x,y)
    dx,dy=dx or 1,dy or 0
    local target=index==3 and mimic(player,x,y,dx,dy) or nil
    if target and target.form then
        if reloading then target.status="reload"
        elseif points<mode.costs[3] then target.status="ammo"
        elseif not ready then target.status="cooldown"
        elseif canMimic and not canMimic(player) then target.status="immune" end
    end
    if blocked then return points,nil,nil,target end
    if swing then advanceSwing(player,gun,clock,frame); return points,nil,nil,target end
    if pressed and ready then started=frame end
    if not started then
        showPose(gun,clock,idle,frame)
        return points,nil,nil,target
    end
    local level=math.min(#mode.costs-1,math.floor((frame-started)/30))
    if down then
        showPose(gun,clock,"charge_"..index.."_"..level,frame)
        return points,level,nil,target
    end

    started=nil
    local cost=mode.costs[level+1]
    if (index==2 or index==3) and level==0 then
        quickStrike(player,gun,clock,x,y,dx,dy,frame,index)
        return points,nil,nil,target
    end
    showPose(gun,clock,idle,frame)
    if cost>points then return points,nil,nil,target,true end
    if index==3 and level==2 then
        if target and target.status=="ready" then
            return points,nil,mimicCast(player,gun,mag,clock,frame,points,cost,target.form),target
        end
        return points,nil,nil,target
    end

    local ok
    local delay=10
    if index==1 then
        if level==0 then ok=payloads.missile(player,x,y,dx,dy)
        elseif level==1 then
            ok=pulse(player,x,y,dx,dy)
            if ok then dragonAttack(player,dx,dy) end
            delay=60
        elseif level==2 then ok=orb(player,x,y,dx,dy); delay=36
        else ok=payloads.rail(player,x,y,dx,dy) end
    elseif index==2 then ok=payloads.summon(player,x,y,dx,dy,level)
    elseif index==3 then ok=payloads.sheep(player,x,y,dx,dy)
    else ok=payloads.restore(player,x,y,dx,dy,level) end
    if ok then
        points=points-cost
        ComponentSetValue2(mag,"value_int",points)
        ComponentSetValue2(clock,"value_int",frame+delay)
    end
    return points,nil,nil,target
end
return staff
