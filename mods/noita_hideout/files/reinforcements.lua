local R={resource="reinforcement_logistics",station="reinforcement",shortage="Not enough reinforcement logistics packs.",
    units={gun_drone="drone_physics",robot_sentry="basebot_sentry",robot_soldier="basebot_soldier",mg_turret="mg_reinforcement",
        chaingun_turret="chaingun_reinforcement",missile_turret="missile_reinforcement",
        repair_drone="healerdrone_physics",robot_spy="basebot_hidden",missile_crab="missilecrab",
        shield_drone="drone_shield",laser_drone="drone_lasership",robot_assassin="assassin",robot_monk="monk",necrobot="necrobot",ground_guard="roboguard"}}
local root="mods/noita_hideout/files/"
local component=EntityGetFirstComponentIncludingDisabled

local sentryShot=root.."escort_sentry_shot.xml"
local sentryBullet="data/entities/projectiles/machinegun_bullet_roboguard_big.xml"
local laserCharge=root.."escort_laser_charge.xml"

local function armLaserDrone(ai)
    ComponentSetValue2(ai,"attack_ranged_entity_file",laserCharge)
    ComponentSetValue2(ai,"attack_ranged_max_distance",240)
    ComponentSetValue2(ai,"attack_ranged_frames_between",44)
    ComponentSetValue2(ai,"attack_ranged_state_duration_frames",36)
end

-- Existing guards keep their ground escort behaviour after leaving the call menu.
local function walks(kind)
    return kind=="missile_crab" or kind=="robot_monk" or kind=="ground_guard"
end

local function emplacement(kind)
    return kind=="mg_turret" or kind=="chaingun_turret" or kind=="missile_turret"
end

local function needsGround(kind)
    return emplacement(kind) or walks(kind)
end

local function supported(x,y,depth,stationary)
    if RaytracePlatforms(x,y+3,x,y+depth) then return true end
    -- A sloped ledge can support the uphill side of the four-pixel half-width chassis.
    return stationary and (RaytracePlatforms(x-4,y+3,x-4,y+depth) or RaytracePlatforms(x+4,y+3,x+4,y+depth))
end

local function fits(x,y,ground,turret)
    local top=turret=="missile_turret" and -21 or (turret and -19 or (ground and -12 or -8))
    local halfWidth=turret=="missile_turret" and 10 or 8
    if not DoesWorldExistAt(math.floor(x)-halfWidth-1,math.floor(y)+math.min(-12,top),math.ceil(x)+halfWidth+1,math.ceil(y)+6)
        or #(EntityGetInRadiusWithTag(x,y,14,"nh_reinforcement") or {})>0 then return false end
    if turret and #(EntityGetInRadiusWithTag(x,y,18,"nh_deployed_turret") or {})>0 then return false end
    for h=top,ground and 4 or 6,2 do
        if RaytracePlatforms(x-halfWidth,y+h,x+halfWidth,y+h) then return false end
    end
    return true
end

local function nearby(player,ground)
    local px,py=EntityGetTransform(player)
    for _,dy in ipairs(ground and {0,-15,-30} or {-18,-3,-32}) do
        for _,dx in ipairs({22,-22,38,-38,0}) do
            local x,y=px+dx,py+dy
            if ground then
                local hit,_,floor=RaytracePlatforms(x,y-4,x,y+24)
                y=hit and floor-6 or nil
            end
            if y and not RaytracePlatforms(px,py,x,y) and fits(x,y,ground) then return x,y end
        end
    end
end

local function discard(id)
    for _,kind in ipairs({"LuaComponent","ExplodeOnDamageComponent","MaterialInventoryComponent"}) do
        for _,c in ipairs(EntityGetComponentIncludingDisabled(id,kind) or {}) do EntityRemoveComponent(id,c) end
    end
    local body=component(id,"PhysicsBodyComponent")
    if body then ComponentSetValue2(body,"on_death_leave_physics_body",false) end
    local model=component(id,"DamageModelComponent")
    if model then ComponentSetValue2(model,"create_ragdoll",false) end
    EntityKill(id)
end

local function spawnEscort(player,kind,x,y)
    local directory=emplacement(kind) and root.."turrets/" or "data/entities/animals/"
    local id=EntityLoad(directory..R.units[kind]..".xml",x,y)
    if not id or id==0 then return end
    local genome,owner=component(id,"GenomeDataComponent"),component(player,"GenomeDataComponent")
    local ai=component(id,"AnimalAIComponent")
    if not genome or not owner or not ai then discard(id); return end
    EntityRemoveTag(id,"enemy")
    EntityRemoveTag(id,"homing_target")
    EntityAddTag(id,"nh_reinforcement")
    ComponentSetValue2(genome,"herd_id",ComponentGetValue2(owner,"herd_id"))
    ComponentSetValue2(genome,"berserk_dont_attack_friends",true)
    ComponentSetValue2(ai,"dont_counter_attack_own_herd",true)
    ComponentSetValue2(ai,"creature_detection_check_every_x_frames",12)
    ComponentSetValue2(ai,"max_distance_to_move_from_home",110)
    if kind=="robot_sentry" then
        ComponentSetValue2(ai,"attack_ranged_entity_file",sentryShot)
        ComponentSetValue2(ai,"attack_ranged_frames_between",90)
    elseif kind=="robot_assassin" then
        ComponentSetValue2(ai,"hide_from_prey",false)
        ComponentSetValue2(ai,"max_distance_to_move_from_home",165)
    elseif kind=="laser_drone" then
        armLaserDrone(ai)
    elseif kind=="missile_crab" then
        ComponentSetValue2(ai,"attack_ranged_entity_file",root.."escort_crab_salvo.xml")
    elseif kind=="shield_drone" then
        ComponentSetValue2(ai,"tries_to_ranged_attack_friends",false)
        ComponentSetValue2(ai,"attack_ranged_entity_file","data/entities/projectiles/machinegun_bullet_slower.xml")
    elseif kind=="repair_drone" then
        -- Healing has an explicit patient; native combat only fires bullets at enemies.
        ComponentSetValue2(ai,"tries_to_ranged_attack_friends",false)
        ComponentSetValue2(ai,"attack_ranged_entity_file","data/entities/projectiles/machinegun_bullet_slower.xml")
        ComponentSetValue2(ai,"attack_ranged_frames_between",80)
        ComponentSetValue2(ai,"attack_melee_enabled",false)
        ComponentSetValue2(ai,"escape_if_damaged_probability",0)
    end
    if kind=="robot_assassin" or kind=="necrobot" then
        local pickup=component(id,"ItemPickUpperComponent")
        if pickup then EntityRemoveComponent(id,pickup) end
    end
    for _,c in ipairs(EntityGetComponentIncludingDisabled(id,"LuaComponent") or {}) do
        local death=ComponentGetValue2(c,"script_death")
        local source=ComponentGetValue2(c,"script_source_file")
        local enemyAura=kind=="shield_drone" and source=="data/scripts/animals/drone_shield_aura.lua"
        local enemySentry=kind=="robot_sentry" and source=="data/scripts/animals/basebot_sentry_check.lua"
        if kind=="necrobot" and source=="data/scripts/animals/necrobot.lua" then
            ComponentSetValue2(c,"script_source_file",root.."escort_necrobot_aura.lua")
        elseif enemyAura or enemySentry or death=="data/scripts/items/drop_money.lua" or death==root.."enemy_loot.lua" then EntityRemoveComponent(id,c) end
    end
    local bound=component(id,"CameraBoundComponent")
    if bound then EntityRemoveComponent(id,bound) end
    local role=EntityAddComponent2(id,"VariableStorageComponent",{_tags="nh_reinforcement_role",value_string=kind})
    if not role or role==0 then discard(id); return end
    -- The emplacement holds its drop site, including when saved outside the loaded area.
    if emplacement(kind) then return id end
    EntityAddComponent2(id,"StreamingKeepAliveComponent",{})
    local tick=EntityAddComponent2(id,"LuaComponent",{script_source_file=root.."reinforcement_tick.lua",
        execute_every_n_frame=6,script_shot=root..(kind=="robot_monk" and "escort_monk_shot.lua" or "turrets_shot.lua")})
    if not tick or tick==0 then discard(id); return end
    return id
end

function R.deploy(player,order,pay,report)
    local kind=order.project
    local ground=needsGround(kind)
    local stationary=emplacement(kind)
    local x,y=nil,order.y+(ground and 2 or 0)
    for _,dx in ipairs({0,16,-16,28,-28}) do
        local tx=order.x+dx
        if (not ground or supported(tx,y,10,stationary)) and fits(tx,y,ground,stationary and kind)
            and (dx==0 or not RaytracePlatforms(order.x,y,tx,y)) then x=tx; break end
    end
    if not x then report("No room for reinforcement."); return end
    local id=spawnEscort(player,kind,x,y)
    if not id then report("Reinforcement deployment failed."); return end
    if not pay() then discard(id); return end
    return true
end

function R.revive(marker)
    local data=component(marker,"VariableStorageComponent","necrobot_entity_file")
    local kind=data and ComponentGetValue2(data,"value_string")
    if not R.units[kind] or kind=="necrobot" then EntityKill(marker); return end
    local player=(EntityGetWithTag("player_unit") or {})[1]
    if not player then return end
    local x,y=EntityGetTransform(marker)
    local ground=needsGround(kind)
    if not fits(x,y,ground,emplacement(kind) and kind) or (ground and not supported(x,y,12,emplacement(kind))) then
        if emplacement(kind) then return end
        x,y=nearby(player,ground)
    end
    local revived=x and spawnEscort(player,kind,x,y)
    if revived then
        if emplacement(kind) and ComponentGetValue2(data,"value_bool") then
            local ammo=dofile(root.."turrets/ammo.lua")
            ammo.set(revived,ammo.counter(revived),ComponentGetValue2(data,"value_int"))
        end
        EntityKill(marker)
        EntityLoad("data/entities/particles/poof_green_sparse.xml",x,y)
    end
end

local function patient(player,id,x,y)
    local function visibleWound(target)
        local model=component(target,"DamageModelComponent")
        if not model then return end
        local hp=ComponentGetValue2(model,"hp")
        if hp<=0 or hp>=ComponentGetValue2(model,"max_hp") then return end
        local tx,ty=EntityGetFirstHitboxCenter(target)
        if tx and (tx-x)^2+(ty-y)^2<=100^2 and not RaytracePlatforms(x,y,tx,ty) then return tx,ty end
    end
    local tx,ty=visibleWound(player)
    if tx then return tx,ty end
    local best=math.huge
    for _,ally in ipairs(EntityGetInRadiusWithTag(x,y,100,"mortal") or {}) do
        if ally~=id and ally~=player and component(ally,"GenomeDataComponent") and EntityGetHerdRelation(player,ally)>=60 then
            local ax,ay=visibleWound(ally)
            if ax then
                local d=(ax-x)^2+(ay-y)^2
                if d<best then tx,ty,best=ax,ay,d end
            end
        end
    end
    return tx,ty
end

local function heal(id,x,y,tx,ty)
    local dx,dy=tx-x,ty-y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<0.01 then return end
    local bolt=EntityLoad("data/entities/projectiles/healshot_slow.xml",x,y)
    if not bolt or bolt==0 then return end
    local velocity,shot=component(bolt,"VelocityComponent"),component(bolt,"ProjectileComponent")
    if not velocity or not shot then EntityKill(bolt); return end
    -- The drone must own this friendly-fire projectile so it can hit its player.
    GameShootProjectile(id,x,y,tx,ty,bolt,false)
    ComponentSetValue2(shot,"mWhoShot",id)
    ComponentSetValue2(velocity,"mVelocity",dx*275/length,dy*275/length)
end

function R.update(id)
    local player=(EntityGetWithTag("player_unit") or {})[1]
    if not player then return end
    local role=component(id,"VariableStorageComponent","nh_reinforcement_role")
    local ai=component(id,"AnimalAIComponent")
    if not role or not ai then return end
    if EntityHasTag(id,"homing_target") then EntityRemoveTag(id,"homing_target") end
    local kind=ComponentGetValue2(role,"value_string")
    -- Escorts already deployed in a saved run still carry the native weapon.
    if kind=="laser_drone" and ComponentGetValue2(ai,"attack_ranged_entity_file")~=laserCharge then
        armLaserDrone(ai)
    end
    local x,y=EntityGetTransform(id)
    local px,py=EntityGetTransform(player)
    ComponentSetValue2(ai,"mHomePosition",px,py)
    local ground=walks(kind)
    local dx,dy=px-x,py-y
    local distance=math.sqrt(dx*dx+dy*dy)
    local body=component(id,"PhysicsBodyComponent")
    if distance>180 then
        local tx,ty=nearby(player,ground)
        if tx then
            if body then
                local bx,by=GamePosToPhysicsPos(tx,ty)
                PhysicsComponentSetTransform(body,bx,by,0,0,0,0)
            else EntityApplyTransform(id,tx,ty) end
            return
        end
    end
    if kind=="shield_drone" and GameGetFrameNum()>=ComponentGetValue2(role,"value_int") then
        local target=distance<=160 and player or nil
        local best=160^2
        if not target then
            for _,ally in ipairs(EntityGetInRadiusWithTag(x,y,160,"nh_reinforcement") or {}) do
                if ally~=id and EntityGetHerdRelation(player,ally)>=60 then
                    local ax,ay=EntityGetTransform(ally)
                    local d=(ax-x)^2+(ay-y)^2
                    if d<best then target,best=ally,d end
                end
            end
        end
        if target and #(EntityGetAllChildren(target,"nh_escort_shield") or {})==0 then
            local ax,ay=EntityGetTransform(target)
            local shield=EntityLoad(root.."escort_shield.xml",ax,ay)
            if shield and shield~=0 then
                EntityAddChild(target,shield)
                ComponentSetValue2(role,"value_int",GameGetFrameNum()+90)
            end
        end
    end
    if kind=="repair_drone" then
        local tx,ty=patient(player,id,x,y)
        ComponentSetValue2(ai,"attack_ranged_enabled",not tx)
        local frame=GameGetFrameNum()
        if tx and frame>=ComponentGetValue2(role,"value_int") then
            heal(id,x,y,tx,ty)
            ComponentSetValue2(role,"value_int",frame+30)
        end
    end
    local enemy=ComponentGetValue2(ai,"mGreatestThreat")
    local engaging=enemy and enemy~=0 and EntityGetIsAlive(enemy) and component(enemy,"GenomeDataComponent")
        and EntityGetHerdRelation(player,enemy)<40
    if kind=="robot_sentry" then
        local marked=engaging and #(EntityGetAllChildren(enemy,"nh_sentry_mark") or {})>0
        local weapon=marked and sentryBullet or sentryShot
        if ComponentGetValue2(ai,"attack_ranged_entity_file")~=weapon then
            ComponentSetValue2(ai,"attack_ranged_entity_file",weapon)
            ComponentSetValue2(ai,"attack_ranged_frames_between",marked and 20 or 90)
        end
    end
    local combatRadius=105
    if kind=="robot_assassin" then combatRadius=165
    elseif kind=="robot_monk" then combatRadius=42 end
    if distance<(engaging and combatRadius or 34) then return end
    -- Steer the physical body; native platforming and collisions remain active.
    if body then
        local bx,by,angle,_,_,spin=PhysicsComponentGetTransform(body)
        if bx then
            local vx,vy=GameVecToPhysicsVec(dx*90/distance,(dy-12)*90/distance)
            PhysicsComponentSetTransform(body,bx,by,angle,vx,vy,spin)
        end
    else
        local character=component(id,"CharacterDataComponent")
        if not character then return end
        local _,vy=ComponentGetValue2(character,"mVelocity")
        if not ground then
            ComponentSetValue2(character,"mVelocity",dx*90/distance,(dy-12)*90/distance)
            return
        end
        local step=dx>0 and 9 or -9
        if ComponentGetValue2(character,"is_on_ground") and (dy< -12 or RaytracePlatforms(x,y,x+step,y)) then vy=-100 end
        ComponentSetValue2(character,"mVelocity",math.max(-80,math.min(80,dx*3)),vy)
    end
end
return R
