local root="mods/noita_hideout/files/companions/"
local deck="data/entities/projectiles/deck/"
local targets=dofile(root.."targets.lua")
local shoot=dofile(root.."projectile.lua")
local dragonAttack=dofile(root.."dragon_attack.lua")
local combat={hostile=targets.hostile}

-- Speeds are world pixels per second. Cooldowns and lifetimes are game frames.
local primary={
    dragon={file=deck.."flamethrower.xml",range=135,delay=18,speed=390,count=3,spread=13,life=24,damage=0.12},
    bee={file=deck.."swarm_wasp.xml",range=190,delay=144,speed=110,count=5,spread=24,life=216},
    griffin={file="mods/noita_hideout/files/projectiles/griffin_ball_lightning.xml",range=300,delay=84,speed=720,count=3,spread=4},
    cat={file="data/entities/projectiles/darkflame.xml",range=155,delay=90,speed=240,life=36},
    dog={file=deck.."chain_bolt.xml",range=135,delay=72,speed=110},
    slime={file=deck.."swarm_firebug.xml",range=175,delay=126,speed=120,count=3,spread=18,life=210},
    flower_fairy={file=deck.."cloud_acid.xml",range=200,delay=198,speed=0,life=108},
    minotaur={file=deck.."lance_holy.xml",range=310,delay=114,speed=690,life=45},
    dryad={range=165,delay=300},
}
local close={
    griffin={range=64,delay=36,replacesAttack=true,file=deck.."light_bullet_air.xml",speed=620,count=3,spread=12},
    cat={range=42,delay=24},
    dog={range=42,delay=240},
    slime={range=46,delay=96,file=deck.."freezing_gaze_beam.xml",speed=540,count=12,spread=25},
    flower_fairy={range=56,delay=66,replacesAttack=true,file=deck.."pollen.xml",speed=68,count=5,spread=52,life=84},
    minotaur={range=54,delay=264},
    dryad={range=45,delay=144,file=deck.."disc_bullet_bigger.xml",speed=245,life=32},
}

local function volley(player,move,x,y,target,tx,ty)
    local angle=math.atan2(ty-y,tx-x)
    local count=move.count or 1
    local arc=math.rad(move.spread or 0)
    local id
    for i=1,count do
        local offset=count==1 and 0 or arc*((i-1)/(count-1)-0.5)
        id=shoot(player,move.file,x,y,math.cos(angle+offset),math.sin(angle+offset),move.speed,move.life,target,move.damage)
    end
    return id
end

local function attack(id,player,move,x,y,target,tx,ty)
    if id=="dryad" then
        -- This is the allied physics body created by the vanilla pebble spell.
        local spirit=EntityLoad(deck.."pebble_player_physics.xml",x,y)
        if spirit and spirit~=0 then
            EntityAddTag(spirit,"summon_player")
            EntityAddComponent2(spirit,"LifetimeComponent",{lifetime=288})
            local ai=EntityGetFirstComponentIncludingDisabled(spirit,"AnimalAIComponent")
            if ai then
                ComponentSetValue2(ai,"mGreatestThreat",target)
                ComponentSetValue2(ai,"attack_dash_damage",0.8)
            end
            local body=EntityGetFirstComponentIncludingDisabled(spirit,"PhysicsBodyComponent")
            if body then ComponentSetValue2(body,"on_death_leave_physics_body",false) end
            -- The stock rock detonates on touching any mortal, including its owner.
            local proximity=EntityGetFirstComponentIncludingDisabled(spirit,"CollisionTriggerComponent")
            if proximity then EntityRemoveComponent(spirit,proximity) end
            for _,blast in ipairs(EntityGetComponentIncludingDisabled(spirit,"ExplosionComponent") or {}) do
                ComponentObjectSetValue2(blast,"config_explosion","damage_mortals",false)
            end
        end
    elseif id=="flower_fairy" then
        -- The cloud's own positioning script finds the ceiling above its spawn.
        shoot(player,move.file,tx,ty,1,0,0,move.life,target)
    else
        local projectile=volley(player,move,x,y,target,tx,ty)
        if id=="dog" and projectile then
            local jump=EntityGetFirstComponentIncludingDisabled(projectile,"LuaComponent")
            ComponentSetValue2(jump,"script_source_file",root.."chain_jump.lua")
            EntityAddComponent2(projectile,"VariableStorageComponent",{_tags="nh_chain_memory",value_int=0,value_float=0})
        end
    end
end

local function guardRing(pet,player,x,y,big)
    local count=big and 8 or 4
    local radius=big and 40 or 16
    local file=deck..(big and "big_magic_shield_part.xml" or "magic_shield_part.xml")
    for i=1,count do
        local angle=2*math.pi*i/count
        local part=shoot(player,file,x+radius*math.cos(angle),y+radius*math.sin(angle),1,0,0,180)
        if part then
            EntityAddComponent2(part,"VariableStorageComponent",{name="angle",value_float=angle})
            EntityAddComponent2(part,"VariableStorageComponent",{name="rot",value_int=6})
            EntityAddComponent2(part,"VariableStorageComponent",{name="owner",value_int=player})
            EntityAddChild(pet,part)
        end
    end
end

local function curse(player,x,y,radius)
    for _,enemy in ipairs(EntityGetInRadiusWithTag(x,y,radius,"homing_target") or {}) do
        if targets.hostile(player,enemy) and not EntityHasTag(enemy,"effect_CURSE") and not EntityHasTag(enemy,"curse_NOT") then
            local ex,ey=EntityGetFirstHitboxCenter(enemy)
            if ex and (ex-x)^2+(ey-y)^2<=radius^2 and not RaytracePlatforms(x,y,ex,ey) then
                local effect=EntityLoad("data/entities/misc/curse.xml",ex,ey)
                if effect and effect~=0 then
                    local strength=EntityGetFirstComponentIncludingDisabled(effect,"VariableStorageComponent")
                    if strength then ComponentSetValue2(strength,"value_float",0.32) end
                    EntityAddComponent2(effect,"VariableStorageComponent",{name="projectile_who_shot",value_int=player})
                    EntityAddTag(enemy,"effect_CURSE")
                    EntityAddChild(enemy,effect)
                end
            end
        end
    end
end

local function defend(id,pet,player,move,x,y,target,tx,ty)
    if id=="cat" then curse(player,x,y,move.range)
    elseif id=="dog" or id=="minotaur" then guardRing(pet,player,x,y,id=="minotaur")
    else
        local projectile=volley(player,move,x,y,target,tx,ty)
        if id=="dryad" and projectile then
            -- Vanilla Omega returns to its shooter and cuts every hittable entity.
            -- Keep its blade, wall cutting and contact hit, and filter the cutting edge.
            for _,script in ipairs(EntityGetComponentIncludingDisabled(projectile,"LuaComponent") or {}) do
                local file=ComponentGetValue2(script,"script_source_file")
                if file=="data/scripts/projectiles/disc_bullet_bigger_trajectory.lua" or file=="data/scripts/projectiles/disc_bullet_big_damage.lua" then
                    EntityRemoveComponent(projectile,script)
                end
            end
            local area=EntityGetFirstComponentIncludingDisabled(projectile,"AreaDamageComponent")
            if area then EntityRemoveComponent(projectile,area) end
            EntityAddComponent2(projectile,"LuaComponent",{script_source_file=root.."disc_edge.lua",execute_every_n_frame=6})
        end
    end
end

local function ensureBees(pet,x,y)
    local bees=EntityGetAllChildren(pet,"nh_bee_guard") or {}
    for i=#bees+1,3 do
        local angle=(i-1)*2*math.pi/3
        local bee=EntityLoad(root.."bee_guard.xml",x+21*math.cos(angle),y+16*math.sin(angle))
        if bee and bee~=0 then
            EntityAddComponent2(bee,"VariableStorageComponent",{_tags="nh_bee_phase",value_float=angle})
            EntityAddChild(pet,bee)
        end
    end
end

function combat.update(id,pet,player,age,x,y,px,py)
    local state=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_combat_clock")
    if not state then
        state=EntityAddComponent2(pet,"VariableStorageComponent",{_tags="nh_combat_clock",value_int=0,value_float=0})
        if id=="bee" then ensureBees(pet,x,y) end
    end
    if id=="dragon" then
        if not EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_dragon_shot") then
            EntityAddComponent2(player,"LuaComponent",{_tags="nh_dragon_shot",script_shot=root.."dragon_shot.lua",execute_every_n_frame=-1})
        end
        local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
        local kick=EntityGetFirstComponentIncludingDisabled(player,"KickComponent")
        if controls and kick and ComponentGetValue2(kick,"can_kick") then
            local sinceKick=GameGetFrameNum()-ComponentGetValue2(controls,"mButtonFrameKick")
            if sinceKick>=0 and sinceKick<6 and not GameIsInventoryOpen() then
                dragonAttack(player,ComponentGetValue2(controls,"mAimingVectorNormalized"))
            end
        end
    end
    local fireReady=age>=ComponentGetValue2(state,"value_int")
    local reaction=close[id]
    local guardReady=reaction and age>=ComponentGetValue2(state,"value_float")
    if not fireReady and not guardReady then return end
    local closeOnly=reaction and reaction.replacesAttack
    if guardReady or (closeOnly and fireReady) then
        local enemy,tx,ty=targets.nearest(player,x,y,reaction.range)
        if enemy then
            if guardReady then
                defend(id,pet,player,reaction,x,y,enemy,tx,ty)
                ComponentSetValue2(state,"value_float",age+reaction.delay)
            end
            if closeOnly then return end
        end
    end
    if fireReady then
        local move=primary[id]
        local enemy,tx,ty=targets.nearest(player,px,py,move.range)
        if enemy then
            -- A companion can see around a corner that blocks the player's view.
            if id=="griffin" and (tx-x)^2+(ty-y)^2<=reaction.range^2 then return end
            attack(id,player,move,px,py,enemy,tx,ty)
            ComponentSetValue2(state,"value_int",age+move.delay)
        end
    end
end

return combat
