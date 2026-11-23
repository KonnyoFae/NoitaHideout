-- Each instance belongs to the player. Keep companion attacks out of shot callbacks.
return function(player,path,x,y,dx,dy,speed,life,target,damage)
    local id=EntityLoad(path,x,y)
    if not id or id==0 then return end
    local shot=EntityGetFirstComponentIncludingDisabled(id,"ProjectileComponent")
    local velocity=EntityGetFirstComponentIncludingDisabled(id,"VelocityComponent")
    if not shot or not velocity then EntityKill(id); return end
    EntityAddTag(id,"nh_companion_shot")
    ComponentSetValue2(shot,"never_hit_player",true)
    ComponentSetValue2(shot,"friendly_fire",false)
    ComponentSetValue2(shot,"explosion_dont_damage_shooter",true)
    ComponentSetValue2(shot,"collide_with_shooter_frames",-1)
    local homing=EntityGetFirstComponentIncludingDisabled(id,"HomingComponent")
    if homing then
        ComponentSetValue2(homing,"target_who_shot",false)
        ComponentSetValue2(homing,"target_tag","nh_companion_no_auto_target")
        ComponentSetValue2(homing,"predefined_target",target or 0)
        EntityAddComponent2(id,"LuaComponent",{script_source_file="mods/noita_hideout/files/companions/swarm_target.lua",execute_every_n_frame=12})
    end
    GameShootProjectile(player,x,y,x+dx*100,y+dy*100,id,false)
    ComponentSetValue2(shot,"mWhoShot",player)
    local genome=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
    if genome then ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(genome,"herd_id")) end
    ComponentSetValue2(velocity,"mVelocity",dx*speed,dy*speed)
    if life then ComponentSetValue2(shot,"lifetime",life) end
    if damage then ComponentSetValue2(shot,"damage",damage) end
    return id
end
