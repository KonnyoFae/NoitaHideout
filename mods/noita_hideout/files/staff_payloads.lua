local root="mods/noita_hideout/files/"
local deck="data/entities/projectiles/deck/"
local volley=dofile(root.."bow/shoot.lua").volley
local targets=dofile(root.."companions/targets.lua")
local payloads={}
local function launch(player,x,y,dx,dy,path,speed,count,spread,configure)
    if not RaytracePlatforms(x,y,x+dx*7,y+dy*7) then x,y=x+dx*7,y+dy*7 end
    return volley(player,path,x,y,dx,dy,speed,count or 1,math.rad(spread or 0),configure,true)
end

function payloads.missile(player,x,y,dx,dy)
    return launch(player,x,y,dx,dy,deck.."rocket.xml",280)
end

function payloads.rail(player,x,y,dx,dy)
    return launch(player,x,y,dx,dy,root.."projectiles/staff_rail.xml",1500)
end

function payloads.summon(player,x,y,dx,dy,level)
    if level==1 then return launch(player,x,y,dx,dy,deck.."pebble_player.xml",230) end
    local target=targets.nearest(player,x,y,180)
    local function home(id,shot)
        ComponentSetValue2(shot,"never_hit_player",true)
        ComponentSetValue2(shot,"explosion_dont_damage_shooter",true)
        ComponentSetValue2(shot,"friendly_fire",false)
        ComponentSetValue2(shot,"collide_with_shooter_frames",-1)
        EntityAddComponent2(id,"HomingComponent",{target_tag="nh_staff_no_auto_target",predefined_target=target or 0,
            detect_distance=180,homing_targeting_coeff=48,homing_velocity_multiplier=1})
        EntityAddComponent2(id,"LuaComponent",{script_source_file=root.."companions/swarm_target.lua",execute_every_n_frame=4})
    end
    if level==2 then return launch(player,x,y,dx,dy,deck.."duck.xml",260,3,15,home) end
    return launch(player,x,y,dx,dy,deck.."meteor.xml",330,4,16,home)
end

function payloads.sheep(player,x,y,dx,dy)
    return launch(player,x,y,dx,dy,root.."projectiles/staff_sheep.xml",260)
end

function payloads.restore(player,x,y,dx,dy,level)
    if level==0 then return launch(player,x,y,dx,dy,deck.."heal_bullet.xml",620) end
    if level==1 then
        local plant=dofile_once(root.."bow/support_field.lua")
        return plant(player,x,y,4)
    end
    local path=level==2 and root.."items/supply_pack.xml" or root.."staff_crystal.xml"
    local id=EntityLoad(path,x,y-3)
    return id and id~=0
end
return payloads
