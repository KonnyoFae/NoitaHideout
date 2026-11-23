local T={}
local root="mods/noita_hideout/files/terminals/"
local home
-- Adopt old steel lockers in place; keep their access coordinates and saved ID.
function T.upgrade(id)
    if EntityHasTag(id,"nh_terminal_v2") then return end
    local sprite=EntityGetFirstComponentIncludingDisabled(id,"SpriteComponent")
    if not sprite then sprite=EntityAddComponent2(id,"SpriteComponent",{}) end
    if not sprite then return end
    ComponentSetValue2(sprite,"image_file",root.."comms_big.png")
    ComponentSetValue2(sprite,"offset_x",32)
    ComponentSetValue2(sprite,"offset_y",50)
    ComponentSetValue2(sprite,"has_special_scale",true)
    ComponentSetValue2(sprite,"special_scale_x",0.5)
    ComponentSetValue2(sprite,"special_scale_y",0.5)
    EntityRefreshSprite(id,sprite)
    if not EntityGetFirstComponentIncludingDisabled(id,"LuaComponent","nh_terminal_field") then
        EntityAddComponent2(id,"LuaComponent",{_tags="nh_terminal_field",script_source_file=root.."tick.lua",execute_every_n_frame=1})
    end
    local ring=EntityGetFirstComponentIncludingDisabled(id,"ParticleEmitterComponent","nh_terminal_ring")
    if not ring then
        ring=EntityAddComponent2(id,"ParticleEmitterComponent",{_tags="nh_terminal_ring",emitted_material_name="plasma_fading",
            count_min=8,count_max=8,lifetime_min=0.15,lifetime_max=0.25,
            render_on_grid=true,fade_based_on_lifetime=true,
            emission_interval_min_frames=6,emission_interval_max_frames=6,
            emit_cosmetic_particles=true,is_emitting=true})
    end
    if not ring or ring==0 then return end
    ComponentSetValue2(ring,"area_circle_radius",96,96)
    ComponentSetValue2(ring,"gravity",0,0)
    EntityAddTag(id,"nh_terminal_v1")
    EntityAddTag(id,"nh_terminal_v2")
end
function T.reset() home=nil end
function T.home(player,x,y)
    if not x or not y then return end
    if home and EntityGetIsAlive(home) then return end
    local px,py=EntityGetTransform(player)
    if (px-x)^2+(py-y)^2>256^2 or not DoesWorldExistAt(x-32,y-32,x+64,y+96) then return end
    home=(EntityGetInRadiusWithTag(x,y,128,"nh_home_terminal") or {})[1]
    if not home then
        local hit,_,floor=RaytraceSurfaces(x+24,y-8,x+24,y+88)
        home=EntityLoad(root.."station.xml",x+24,hit and floor-7 or y)
    end
    if home and home~=0 then T.upgrade(home) end
end
return T
