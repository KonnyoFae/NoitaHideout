local modes={
    scatter_revolver={
        {id="pistol",zh="速射",en="Auto pistol",cost=1,damage=10,wait=8,speed=640,life=22,spread=2},
        {id="magnum",zh="马格南",en="Magnum",cost=3,damage=33,wait=18,speed=810,life=28,semi=true,trail="spark",shake=1.6},
        {id="scatter",zh="霰弹",en="Scatter",cost=6,damage=8,wait=25,speed=580,life=16,spread=9,pellets=8,shake=2},
        {id="spray",zh="喷枪",en="Sprayer",cost=1,damage=5,wait=6,speed=185,life=20,spread=5},
    },
    marksman_rifle={
        {id="rifle",zh="自动步枪",en="Auto rifle",cost=1,damage=15,wait=16,speed=980,life=60,trail="spark"},
        {id="sniper",zh="狙击",en="Sniper",cost=6,damage=95,wait=56,speed=1800,life=60,trail="spark_white",shake=3},
        {id="missile",zh="微型导弹",en="Micro missile",cost=12,damage=0,blast=120,radius=26,wait=48,speed=280,life=180,trail="fire",shake=2},
        {id="beam",zh="光束",en="Beam",cost=3,damage=30,blast=20,radius=13,wait=21,speed=2100,life=37,trail="spark_blue",shake=1},
    },
}
local root="mods/noita_hideout/files/projectiles/"
local soundBank="data/audio/Desktop/projectiles.bank"
local sounds={
    pistol="projectiles/bullet_smg_enemy",magnum="player_projectiles/bullet_heavy_fast",
    scatter="projectiles/shotgun",spray="player_projectiles/flamethrower",
    rifle="projectiles/minigun",sniper="projectiles/bullet_sniper_enemy",
    missile="projectiles/rocket_tiny",beam="player_projectiles/megalaser",
}
local clouds={fire="fire",frost="spark_white",shock="spark_electric",toxin="poison",plasma="plasma_fading",blast="spark"}

local function variant(mode,impact,flight)
    local loss=(impact and 1 or 0)+(flight and 1 or 0)
    local path=root.."multi_"..mode.id..loss
    if flight=="pierce" or (mode.id=="missile" and flight=="homing") then path=path.."_"..flight end
    if mode.id=="spray" then path=path.."_"..(impact or "fire") end
    return path..".xml",loss
end

local function projectile(mode,loss,impact,flight)
    local missile,sniper,spray=mode.id=="missile",mode.id=="sniper",mode.id=="spray"
    local trail=spray and clouds[impact or "fire"] or mode.trail
    local pierce=sniper or flight=="pierce"
    local damage=math.max(0,mode.damage-loss)/25
    local explosion=mode.blast and (mode.blast-(missile and loss or 0))/25
    local fragments={('<Entity><Base file="%sbullet_base.xml"><VelocityComponent mass="0.6" terminal_velocity="3600" />'):format(root),
        ('<ProjectileComponent speed_min="%d" speed_max="%d" lifetime="%d" damage="%s" penetrate_entities="%d" ground_penetration_coeff="%s" ground_penetration_max_durability_to_destroy="%d" on_lifetime_out_explode="%d" camera_shake_when_shot="%s" muzzle_flash_file="data/entities/particles/muzzle_flashes/muzzle_flash_small.xml">'):format(
            mode.speed,mode.speed,mode.life,damage,pierce and 1 or 0,sniper and (flight=="pierce" and 9 or 5) or 0,sniper and (flight=="pierce" and 12 or 9) or 0,explosion and 1 or 0,mode.shake or 0)}
    if explosion then
        fragments[#fragments+1]=('<config_explosion explosion_radius="%d" damage="%s" damage_mortals="1" camera_shake="%d" explosion_sprite="data/particles/explosion_%s.xml" explosion_sprite_lifetime="0.25" explosion_sprite_additive="1" light_enabled="1" sparks_enabled="1" spark_material="%s" sparks_count_min="8" sparks_count_max="16" audio_enabled="1" audio_event_name="explosions/magic_rocket_small" />'):format(mode.radius,explosion,missile and 4 or 1,missile and "032" or "016",missile and "spark" or "spark_blue")
    elseif spray then
        fragments[#fragments+1]='<config_explosion hole_enabled="0" material_sparks_enabled="0" />'
    end
    fragments[#fragments+1]='</ProjectileComponent>'
    if missile then fragments[#fragments+1]='<SpriteComponent image_file="data/projectiles_gfx/rocket_tiny.xml" />'
    elseif spray then fragments[#fragments+1]='<SpriteComponent _enabled="0" />' end
    fragments[#fragments+1]='</Base>'
    if missile then
        local strong=flight=="homing"
        fragments[#fragments+1]=('<HomingComponent target_tag="homing_target" detect_distance="%d" homing_targeting_coeff="%d" homing_velocity_multiplier="1" />'):format(strong and 210 or 120,strong and 105 or 40)
    end
    if trail then
        fragments[#fragments+1]=('<ParticleEmitterComponent emitted_material_name="%s" is_trail="1" trail_gap="%s" count_min="%d" count_max="%d" x_pos_offset_min="-%d" x_pos_offset_max="%d" y_pos_offset_min="-%d" y_pos_offset_max="%d" lifetime_min="0.09" lifetime_max="%s" emission_interval_min_frames="1" emission_interval_max_frames="1" create_real_particles="0" emit_cosmetic_particles="1" is_emitting="1" />'):format(trail,mode.id=="beam" and 0.7 or 2,spray and 4 or 1,spray and 7 or 1,spray and 5 or 0,spray and 5 or 0,spray and 5 or 0,spray and 5 or 0,spray and 0.32 or 0.15)
    end
    if spray and (not impact or impact=="fire") then
        fragments[#fragments+1]='<ParticleEmitterComponent emitted_material_name="fire" count_min="1" count_max="2" lifetime_min="0.2" lifetime_max="0.45" emission_interval_min_frames="4" emission_interval_max_frames="4" create_real_particles="1" emit_cosmetic_particles="0" is_emitting="1" />'
    end
    if not mode.pellets then
        fragments[#fragments+1]='<AudioComponent file="'..soundBank..'" event_root="'..sounds[mode.id]..'" />'
    end
    fragments[#fragments+1]='</Entity>'
    return table.concat(fragments)
end

local function register(mods)
    local impacts,flights={false},{false}
    for _,mod in ipairs(mods.order) do table.insert(mod.slot==1 and impacts or flights,mod.id) end
    local written={}
    for _,list in pairs(modes) do for _,mode in ipairs(list) do
        for _,impact in ipairs(impacts) do for _,flight in ipairs(flights) do
            local path,loss=variant(mode,impact,flight)
            if not written[path] then
                ModTextFileSetContent(path,projectile(mode,loss,impact,flight))
                written[path]=true
            end
        end end
    end end
end
return {guns=modes,path=variant,register=register,soundBank=soundBank,sounds=sounds}
