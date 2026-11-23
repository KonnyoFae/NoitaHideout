local root="mods/noita_hideout/files/"
local items=dofile(root.."throwables.lua")
local function source(path)
    local f=assert(io.open(path,"rb"))
    local s=f:read("*a"); f:close()
    return s
end
local base=source(root.."projectiles/throwable.xml")
assert(base:find('on_collision_die="1"') and base:find('on_collision_remove_projectile="0"'))
assert(base:find('bounces_left="0"') and base:find('on_death_explode="0"'))
assert(base:find('execute_on_removed="1"') and base:find('execute_every_n_frame="-1"',1,true))
local bulletPath=root.."projectiles/bullet_base.xml"
local bullet=source(bulletPath)
assert(bullet:find('on_collision_die="1"') and bullet:find('on_death_gfx_leave_sprite="0"'))
assert(bullet:find('on_death_explode="1"') and bullet:find('on_lifetime_out_explode="0"'))
assert(bullet:find('explosion_radius="2"') and bullet:find('max_durability_to_destroy="9"') and bullet:find('hole_enabled="1"'))
assert(bullet:find('damage_mortals="0"') and bullet:find('hole_destroy_liquid="0"') and bullet:find('create_cell_probability="0"'))
assert(bullet:match('image_file="([^"]+)"')=="data/projectiles_gfx/bullet.xml")
for id,damage in pairs({derringer="1.2",scatter_revolver="0.25",marksman_rifle="1.5",flare_gun="0.04"}) do
    local xml=source(root.."projectiles/"..id..".xml")
    assert(xml:find('<Base file="'..bulletPath..'">',1,true) and xml:find('damage="'..damage..'"',1,true))
    assert(not xml:find("on_death_gfx_leave_sprite") and not xml:find("on_death_explode"))
    if id=="marksman_rifle" then assert(xml:find('explosion_radius="3"')) end
end
local callback=assert(base:match('script_source_file="([^"]+)"'))
local field={
    fire_grenade={30,"DAMAGE_FIRE","effect_on_fire.xml","PROTECTION_FIRE"},
    frost_grenade={28,"DAMAGE_ICE","effect_frozen_short.xml","STUN_PROTECTION_FREEZE"},
    shock_grenade={32,"DAMAGE_ELECTRICITY","effect_electricity.xml","PROTECTION_ELECTRICITY"},
    flare_gun={22,"DAMAGE_FIRE","sand_blindness.xml","PROTECTION_ALL"},
    sand_knife={18,"DAMAGE_PROJECTILE","sand_blindness.xml","PROTECTION_ALL"},
    metal_knife={22,"DAMAGE_SLICE",nil,"PROTECTION_ALL"},
}
local shot,marker,kind,loaded,actors,hit,status,particles,sounds
local owner,projectile=1,99
function GetUpdatedEntityID() return projectile end
function EntityGetFirstComponentIncludingDisabled(entity,component,tag)
    assert(entity==projectile)
    if component=="ProjectileComponent" then return shot end
    assert(component=="VariableStorageComponent" and tag=="nh_throwable_impact")
    return marker
end
function EntityGetFirstComponent(id,key) assert(key=="DamageModelComponent"); return actors[id] end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function ComponentObjectGetValue2(c,group,k) assert(group=="damage_multipliers"); return c[k] or 1 end
function EntityGetTransform(id) assert(id==projectile);return 5.25,20 end
function DoesWorldExistAt(x,y,w,h) assert(x==5 and y==20 and w==6 and h==21); return loaded end
function EntityGetIsAlive(id) return actors[id] and actors[id].hp>0 end
function EntityGetHerdRelationSafe(from,to) assert(from==owner);return actors[to].relation or 0 end
function EntityHasTag(id,k) assert(k=="noita_hideout_companion");return actors[id].pet end
function GameGetGameEffectCount(id,k) return actors[id].buff==k and 1 or 0 end
function EntityGetInRadiusWithTag(x,y,r,tag)
    assert(x==5.25 and y==20 and r==field[kind][1] and tag=="mortal")
    local result={}
    for id,a in pairs(actors) do if a.distance<=r then result[#result+1]=id end end
    return result
end
function GameTextGetTranslatedOrNot(key) assert(key=="$nh_hideout_"..kind);return key end
function GamePlaySound() sounds=sounds+1 end
function GameCreateParticle(_,_,_,_,_,_,visual) assert(visual);particles=particles+1 end
function EntityInflictDamage(id,amount,damage_type,_,_,_,_,who,x,y)
    assert(amount>0 and damage_type==field[kind][2] and who==owner and x==5.25 and y==20)
    assert(not hit[id],"damage applied twice")
    hit[id]=true
    actors[id].hp=actors[id].hp-amount
end
function LoadGameEffectEntityTo(id,path)
    if kind=="flare_gun" and path:match("effect_on_fire.xml$") then
        assert(status[id]==true)
        status[id]="blind_and_burning"
        return
    end
    assert(hit[id] and not status[id] and path:match("[^/]+$")==field[kind][3])
    status[id]=true
end

for id,expected in pairs(field) do
    kind=id
    local xml=source(id=="flare_gun" and root.."projectiles/flare_gun.xml" or items.types[id].projectile)
    if id=="flare_gun" then
        assert(xml:find('script_source_file="'..callback..'"',1,true) and xml:find('execute_on_removed="1"'))
        assert(xml:find('emitted_material_name="spark_red"') and xml:find('create_real_particles="0"'))
    else assert(xml:find('file="'..root..'projectiles/throwable.xml"',1,true)) end
    assert(xml:find('value_string="'..id..'"',1,true) and xml:find('value_bool="0"'))
    if id~="flare_gun" then assert(source(xml:match('image_file="([^"]+)"')):sub(2,4)=="PNG") end
    marker={value_string=id,value_bool=false}
    hit,status,particles,sounds={},{},0,0
    actors={
        [owner]={hp=4,distance=2},[2]={hp=4,distance=0},[3]={hp=4,distance=expected[1]},
        [4]={hp=4,distance=expected[1]+1},[5]={hp=4,distance=4,pet=true},
        [6]={hp=4,distance=3,buff="CHARM"},[7]={hp=4,distance=2,relation=90},
        [8]={hp=4,distance=3,buff=expected[4]},[9]={hp=0,distance=0},
        [10]={hp=0.01,distance=1},[11]={hp=4,distance=1,fire=0,ice=0,electricity=0},
    }
    loaded=true
    shot=nil; dofile(callback) -- Runtime discards malformed shots before launch.
    shot={mWhoShot=0}; dofile(callback)
    shot.mWhoShot=owner; loaded=false; dofile(callback)
    assert(not next(hit) and not marker.value_bool and sounds==0 and particles==0)
    loaded=true; dofile(callback)
    assert(hit[2] and hit[3] and hit[8] and hit[10] and hit[11] and not hit[4] and not hit[owner])
    assert(not hit[5] and not hit[6] and not hit[7] and not hit[9])
    assert(not status[8] and not status[10])
    if expected[3] then
        assert(status[2] and status[3])
        assert((status[11]==true)==(id=="sand_knife" or id=="flare_gun"))
        if id=="flare_gun" then assert(status[2]=="blind_and_burning") end
    else assert(not next(status)) end
    assert(marker.value_bool and particles>0 and sounds==1)
    local drawn=particles
    dofile(callback)
    assert(sounds==1 and particles==drawn)
end
print("Throwables: five typed area bursts, real XML wiring, statuses, source ownership, immunity and one-shot impact passed.")
