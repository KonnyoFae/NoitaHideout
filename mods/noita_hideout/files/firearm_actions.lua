-- Appended to the native action catalog. Previews must never spend a round.
local files="mods/noita_hideout/files/"
local mods=dofile(files.."ammo_mods.lua")
local modes=dofile(files.."firearm_modes.lua")
local status={fire="apply_on_fire",frost="frozen",shock="electricity",toxin="apply_poison"}
-- A native hit-world trigger runs its child only on contact. Give the child
-- its own config so trajectory modifiers and direct damage never leak into it.
local function contactProjectile(path,impact)
    BeginProjectile(path)
    BeginTriggerHitWorld()
    BeginProjectile(files.."projectiles/ammo_"..impact..".xml")
    EndProjectile()
    local state=create_shot(0).state
    register_action(state)
    SetProjectileConfigs()
    EndTrigger()
    EndProjectile()
end

local function ammunition(kind,icon)
    table.insert(actions,{
        id="NH_"..kind:upper(),name="$nh_hideout_"..kind,description="$nh_hideout_"..kind.."_desc",
        sprite=icon,type=ACTION_TYPE_PROJECTILE,spawn_level="0",spawn_probability="0",price=0,mana=0,
        never_unlimited=true,
        action=function()
            local mode=modes.guns[kind][1]
            local impact,flight
            if not reflecting then
                local owner=EntityGetRootEntity(GetUpdatedEntityID())
                local inv=EntityGetFirstComponentIncludingDisabled(owner,"Inventory2Component")
                local gun=inv and ComponentGetValue2(inv,"mActiveItem")
                local mag=gun and gun~=0 and EntityGetFirstComponentIncludingDisabled(gun,"VariableStorageComponent","nh_magazine")
                if not mag or ComponentGetValue2(mag,"name")~=kind or ComponentGetValue2(mag,"value_bool") then return end
                mode=modes.guns[kind][ComponentGetValue2(mag,"value_float")] or mode
                local points=ComponentGetValue2(mag,"value_int")
                if points<mode.cost then return end
                if mode.semi then
                    local controls=EntityGetFirstComponentIncludingDisabled(owner,"ControlsComponent")
                    local press=controls and tostring(ComponentGetValue2(controls,"mButtonFrameFire"))
                    if press and ComponentGetValue2(mag,"value_string")==press then return end
                    if press then ComponentSetValue2(mag,"value_string",press) end
                end
                local profile=EntityGetFirstComponentIncludingDisabled(gun,"VariableStorageComponent","nh_gun_profile")
                impact,flight=mods.parse(profile and ComponentGetValue2(profile,"name"))
                ComponentSetValue2(mag,"value_int",points-mode.cost)
                if mode.pellets then
                    local posX,posY=EntityGetTransform(owner)
                    GamePlaySound(modes.soundBank,modes.sounds[mode.id].."/create",posX,posY)
                end
            end
            c.fire_rate_wait=mode.wait
            current_reload_time=mode.wait
            c.spread_degrees=c.spread_degrees+(mode.spread or 0)
            local core,trajectory=impact and impact.id,flight and flight.id
            local path=modes.path(mode,core,trajectory)
            if trajectory=="speed" then c.speed_multiplier=c.speed_multiplier*1.5
            elseif trajectory=="cursor" or (trajectory=="homing" and mode.id~="missile") then
                c.extra_entities=c.extra_entities.."data/entities/misc/"..(trajectory=="cursor" and "homing_cursor" or "homing")..".xml,"
            end
            local effect=status[core or (mode.id=="spray" and "fire" or "")]
            if effect then c.game_effect_entities=c.game_effect_entities.."data/entities/misc/effect_"..effect..".xml," end
            for pellet=1,mode.pellets or 1 do
                if core then contactProjectile(path,core) else add_projectile(path) end
            end
        end,
    })
end
ammunition("scatter_revolver","data/ui_gfx/gun_actions/buckshot.png")
ammunition("marksman_rifle","data/ui_gfx/gun_actions/light_bullet.png")
table.insert(actions,{id="NH_BATTLE_STAFF",name="$nh_hideout_battle_staff",description="$nh_hideout_battle_staff_desc",
    sprite="data/ui_gfx/gun_actions/energy_shield.png",type=ACTION_TYPE_UTILITY,spawn_level="0",spawn_probability="0",price=0,mana=0,
    action=function() end})

for _,d in ipairs(mods.order) do
    table.insert(actions,{id=d.action,name=d.name,description=d.name.."_desc",sprite=d.icon,type=ACTION_TYPE_MODIFIER,
        spawn_level="0",spawn_probability="0",price=20,mana=0,
        action=function() draw_actions(1,true) end})
end
