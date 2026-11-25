local ground=dofile("mods/noita_hideout/files/support_ground.lua")
local items="mods/noita_hideout/files/items/"
local groundTag="nh_support_ground_art"
local entities={}
NHGuns={types={}}
local function gun(kind,sized)
    NHGuns.types[kind]=sized and {displaySprite=items..kind.."_art.png"} or {}
    local entity={root=false,kind=kind,ammo=9,spin=2.1,shape={image_file=items..kind.."_world.png"},
        item={item_name="$nh_hideout_"..kind},body={enabled=true}}
    entity.root=entity
    entities[#entities+1]=entity
    return entity
end
function EntityGetRootEntity(e) return e.root end
function EntityHasTag(e,tag) return tag=="noita_hideout_"..e.kind end
function EntityGetTransform() return 10,-20 end
function EntityGetInRadiusWithTag(x,y,r,tag)
    assert(x==10 and y==-20 and r<=360 and tag=="nh_support_weapon")
    return entities
end
function EntityGetFirstComponent(e,kind) assert(kind=="ItemComponent"); return e.item end
function EntityGetFirstComponentIncludingDisabled(e,kind,tag)
    if kind=="PhysicsImageShapeComponent" then return e.shape end
    assert(kind=="SpriteComponent" and tag==groundTag)
    return e.overlay
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) assert(k=="image_file"); c[k]=v end
function EntityAddComponent2(e,kind,t)
    assert(kind=="SpriteComponent" and not e.overlay and t._tags=="enabled_in_world,"..groundTag)
    if e.reject then return nil end
    e.overlay=t
    return t
end

local held=gun("heavy_mg",true)
held.root={}
local foreign=gun("heavy_plasma",true)
foreign.shape.image_file="mods/other/body.png"
local native=gun("railgun",false)
local fresh=gun("auto_grenade",true)
fresh.overlay={}
fresh.shape.image_file=items.."auto_grenade_shape.png"
local failed=gun("missile_launcher",true)
failed.reject=true
local old={}
for i=1,9 do old[i]=gun("heavy_plasma",true) end
ground.near({})
assert(not held.overlay and not foreign.overlay and not native.overlay and not failed.overlay)
assert(failed.shape.image_file==items.."missile_launcher_world.png")
assert(not old[9].overlay)
for i=1,8 do
    local e=old[i]
    assert(e.overlay._enabled and e.overlay.image_file==NHGuns.types.heavy_plasma.displaySprite)
    assert(e.shape.image_file==items.."heavy_plasma_shape.png" and e.overlay.has_special_scale)
    assert(e.overlay.offset_x==12 and e.overlay.offset_y==12 and e.overlay.special_scale_x==0.5 and e.overlay.special_scale_y==0.5)
    assert(e.ammo==9 and e.spin==2.1 and e.body.enabled)
end
ground.near({})
assert(old[9].overlay and not ground.repair(old[1],"heavy_plasma"))
assert(ground.repair(held,"heavy_mg") and held.overlay._enabled==false)
