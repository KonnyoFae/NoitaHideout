local root="mods/noita_hideout/files/"
NHFirearms=dofile(root.."firearms.lua")
local runtime=dofile(root.."ammo_runtime.lua")
local entities,shots={},{}
local frame,updated=100,0
local function entity(parts,x,y)
    entities[#entities+1]={parts=parts or {},x=x or 0,y=y or 0,tags={},children={}}
    return #entities
end
local controls={mButtonDownFire=false}
local player=entity({ControlsComponent=controls,GenomeDataComponent={herd_id=7},DamageModelComponent={hp=1,max_hp=10}})
local mag={name="hunting_bow",value_int=60,value_float=1}
local ability={mana=60}
local gun=entity({nh_magazine=mag,AbilityComponent=ability,nh_bow_clock={value_int=0},enabled_in_hand={}})
entities[gun].tags.nh_firearm=true
local ally=entity({GenomeDataComponent={},DamageModelComponent={hp=2,max_hp=3}},12,0)
local enemy=entity({GenomeDataComponent={},DamageModelComponent={hp=1,max_hp=2}},16,0)
local far=entity({GenomeDataComponent={},DamageModelComponent={hp=1,max_hp=2}},140,0)
entities[ally].tags.nh_reinforcement=true
local rig={gearRig={id=1,item={kind="ammo_rig",reserve=0}}}
NHNative={held=function() return gun end}
NHProducts={aim=function() return 1,0 end}
function dofile_once(p) return dofile(p) end
function GameGetFrameNum() return frame end
function GetUpdatedEntityID() return updated end
function EntityGetIsAlive(id) return entities[id] and not entities[id].dead end
function EntityKill(id) entities[id].dead=true end
function EntityGetTransform(id) local e=entities[id];return e.x,e.y,0,1,1 end
function EntitySetTransform(id,x,y) entities[id].x,entities[id].y=x,y end
function EntityGetFirstHitboxCenter(id) return EntityGetTransform(id) end
function EntityGetFirstComponentIncludingDisabled(id,k,tag) return entities[id].parts[tag or k] end
function ComponentSetValue2(c,k,v,b) c[k]=b and {v,b} or v end
function ComponentGetValue2(c,k) return c[k] end
function EntityHasTag(id,k) return entities[id].tags[k] end
function EntityAddTag(id,k) entities[id].tags[k]=true end
function EntityAddChild(id,child) table.insert(entities[id].children,child) end
function EntityGetAllChildren(id,k)
    local list={}
    for _,c in ipairs(entities[id].children) do if entities[c].tags[k] then table.insert(list,c) end end
    return list
end
function EntityGetInRadiusWithTag(x,y,r)
    local list={}
    for _,id in ipairs({player,enemy,ally,far}) do
        if (entities[id].x-x)^2+(entities[id].y-y)^2<=r*r then list[#list+1]=id end
    end
    return list
end
function EntityGetHerdRelation(_,id) return id==player and 100 or 0 end
EntityGetHerdRelationSafe=EntityGetHerdRelation
function GameGetGameEffectCount() return 0 end
function EntityAddComponent2(id,k,c) entities[id].parts[k]=c; return c end
function DoesWorldExistAt() return true end
function RaytracePlatforms() return false end
function GamePlaySound() end
function EntityRefreshSprite() end
local anchor,failAt
function EntityLoad(path,x,y)
    if failAt then failAt=failAt-1; if failAt==0 then failAt=nil; return 0 end end
    local file=path:match("([^/]+)%.xml$")
    local p={ProjectileComponent={lifetime=100},VelocityComponent={}}
    if file=="rapid" then p.HomingComponent={} end
    if file=="scan" or file=="support" or file=="anchor" then
        p.nh_bow_field={name=file=="scan" and "scout" or "aid"}
        p.nh_bow_ring={}
    elseif file=="ward" or file=="mark" then p.LifetimeComponent={kill_frame=0}
    elseif file=="effect_berserk" or file=="effect_frozen_short" then p.GameEffectComponent={} end
    local id=entity(p,x,y)
    entities[id].file=file
    if file=="anchor" then anchor=id end
    return id
end
function GameShootProjectile(owner,x,y,tx,ty,id,notify)
    assert(owner==player and entities[id].parts.ProjectileComponent.mWhoShot==player)
    shots[#shots+1]=id
end
local function tick(down,input)
    frame=frame+1
    controls.mButtonDownFire=down
    return runtime.update(rig,player,function(change) return change(rig) end,input or {enabled=true})
end
local function draw(mode,level,points)
    mag.value_float,mag.value_int=mode,points or 60
    tick(false)
    for i=1,9 do tick(false) end
    local first=#shots
    local view=tick(true)
    for i=1,level*30 do view=tick(true) end
    assert(view.charge==level and view.rounds==(points or 60))
    assert(entities[gun].parts.enabled_in_hand.rect_animation=="draw_"..level)
    local released=tick(false)
    return first,released,shots[#shots]
end

local expected={{1,2,3,5},{2,3,4,5},{2,4,6,8},{2,1}}
for m,costs in ipairs(expected) do for i,cost in ipairs(costs) do
    local first,view,id=draw(m,i-1)
    assert(view.rounds==60-cost and ability.mana==60-cost)
    local e=entities[id]
    if m==1 and i<4 then
        assert(#shots==first+i and e.file=="rapid" and e.parts.HomingComponent.predefined_target==enemy)
    elseif m==1 then
        assert(#shots==first+1 and e.file=="cluster")
        updated=id
        dofile(root.."bow/split.lua")
        assert(#shots==first+7 and entities[shots[#shots]].file=="fragment")
    elseif m==2 then
        local mode=NHFirearms.bowModes[m]
        assert(e.file=="scan" and e.parts.ProjectileComponent.bounces_left==mode.bounces[i])
        assert(e.parts.ProjectileComponent.lifetime==mode.life[i] and e.parts.nh_bow_ring.special_scale_x==mode.radius[i]/32)
        updated=id
        dofile(root.."bow/field_tick.lua");dofile(root.."bow/field_tick.lua")
        assert(#EntityGetAllChildren(enemy,"nh_bow_mark")==1 and #EntityGetAllChildren(ally,"nh_bow_mark")==0)
        assert(#EntityGetAllChildren(enemy,"nh_bow_frost")==(i==4 and 1 or 0))
    elseif m==3 then
        assert(e.file=="support")
        e.x,e.y=15,0
        updated=id
        dofile(root.."bow/plant.lua")
        local a=entities[anchor]
        assert(a.x==15 and a.parts.LifetimeComponent.lifetime==NHFirearms.bowModes[m].life[i])
        updated=anchor
        local hp=entities[ally].parts.DamageModelComponent
        local old=hp.hp
        dofile(root.."bow/field_tick.lua");dofile(root.."bow/field_tick.lua")
        assert(hp.hp==math.min(3,old+2*NHFirearms.bowModes[m].healPerSecond[i]/125) or math.abs(hp.hp-old-2*NHFirearms.bowModes[m].healPerSecond[i]/125)<1e-6)
        assert(#EntityGetAllChildren(player,"nh_bow_rage")==1 and #EntityGetAllChildren(ally,"nh_bow_rage")==1)
        assert(#EntityGetAllChildren(enemy,"nh_bow_rage")==0 and entities[enemy].parts.DamageModelComponent.hp==1)
        assert(#EntityGetAllChildren(ally,"nh_bow_ward")==(i==4 and 1 or 0))
    else
        assert(e.file==(i==1 and "teleport_long" or "teleport_short"))
        assert(#shots-first==(i==1 and 1 or 6))
        for j=first+1,#shots-1 do assert(entities[shots[j]].file=="drill") end
    end
end end
-- A single remaining point still buys the charged short teleport with reserve equipped.
rig.gearRig.item.reserve=20
local _,one=draw(4,1,1)
assert(one.rounds==0 and not one.loading)
tick(false)
for i=1,60 do tick(false) end
assert(mag.value_int==20 and rig.gearRig.item.reserve==0)
-- Attempting a too-expensive charged shot must start reloading without firing.
rig.gearRig.item.reserve=10
local first,empty=draw(3,3,2)
assert(empty.rounds==2 and empty.loading==60 and #shots==first)
for i=1,60 do tick(false) end
-- A blocked draw must not release on closing inventory or on a mode change.
tick(true);tick(true,{enabled=false});tick(false)
assert(#shots==first)
tick(true);tick(true,{enabled=true,pressed=true,down=true});tick(false)
assert(#shots==first)
-- A failed second entity during a volley must clean up the first and preserve ammo.
mag.value_float,mag.value_int=1,8
tick(false);tick(true)
for i=1,30 do tick(true) end
failAt=2
assert(tick(false).rounds==8 and #shots==first and entities[#entities].dead)
local bow=NHFirearms.recipe("hunting_bow")
assert(bow.category=="weapons" and NHFirearms.valid(bow.item) and NHFirearms.lane(bow.id)=="wand")
print("Hunting bow charge tiers, all four payloads, target filtering, release cancellation and reload passed.")
