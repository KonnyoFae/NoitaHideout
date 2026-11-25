local files="mods/noita_hideout/files/"
local entities,components={},{}
local frame=60
local function spawn(tags,x,parent)
    local id=#entities+1
    local e={tags={},components={},x=x or 0,parent=parent or id,alive=true}
    for tag in tags:gmatch("[^,]+") do e.tags[tag]=true end
    entities[id]=e
    return id
end
function EntityAddComponent2(id,kind,c)
    c=c or {}
    c.tags={}
    for tag in (c._tags or ""):gmatch("[^,]+") do c.tags[tag]=true end
    c.kind,c.enabled=kind,c.enabled~=false
    if kind=="VariableStorageComponent" then c.name=c.name or ""; c.value_string=c.value_string or "" end
    if kind=="LuaComponent" then c.script_source_file=c.script_source_file or ""; c.execute_every_n_frame=c.execute_every_n_frame or 1 end
    components[#components+1]=c
    table.insert(entities[id].components,#components)
    return #components
end
function EntityGetAllComponents(id)
    local ids={}
    for _,i in ipairs(entities[id].components) do if components[i].kind then ids[#ids+1]=i end end
    return ids
end
function EntityGetComponentIncludingDisabled(id,kind,tag)
    local ids={}
    for _,i in ipairs(EntityGetAllComponents(id)) do
        local c=components[i]
        if c.kind==kind and (not tag or c.tags[tag]) then ids[#ids+1]=i end
    end
    return ids
end
function EntityGetFirstComponentIncludingDisabled(id,kind,...)
    local tag=select(1,...)
    assert(select("#",...)==0 or tag~=nil,"Noita rejects an explicitly nil component tag")
    if tag=="" then return nil end
    return EntityGetComponentIncludingDisabled(id,kind,tag)[1]
end
function EntityGetFirstComponent(id,kind,tag)
    for _,i in ipairs(EntityGetComponentIncludingDisabled(id,kind,tag)) do if components[i].enabled then return i end end
end
function EntityGetIsAlive(e) return entities[e] and entities[e].alive end
function EntityGetRootEntity(e) return entities[e].parent end
function EntityHasTag(id,tag) return entities[id].tags[tag] or false end
function EntityAddTag(e,t) entities[e].tags[t]=true end
function EntityRemoveTag(e,t) entities[e].tags[t]=nil end
function EntityGetTransform(e) return entities[e].x,0 end
function EntityGetInRadiusWithTag(x,y,r,tag)
    local found={}
    for i,e in ipairs(entities) do
        if e.alive and math.abs(e.x-x)<=r and (not tag or e.tags[tag]) then found[#found+1]=i end
    end
    return found
end
EntityGetInRadius=EntityGetInRadiusWithTag
function EntityGetWithTag(tag) return EntityGetInRadiusWithTag(0,0,1e9,tag) end
function ComponentGetValue2(c,k)
    local value=components[c][k]
    if type(value)=="table" then return unpack(value) end
    return value
end
function ComponentSetValue2(c,k,...)
    if select("#",...)>1 then components[c][k]={...} else components[c][k]=select(1,...) end
end
function ComponentGetIsEnabled(c) return components[c].enabled end
function EntitySetComponentIsEnabled(e,c,b) components[c].enabled=b end
function ComponentGetTypeName(c) return components[c].kind end
function ComponentAddTag(c,t) components[c].tags[t]=true end
function ComponentRemoveTag(c,t) components[c].tags[t]=nil end
function ComponentHasTag(c,t) return components[c].tags[t] end
function EntityRemoveComponent(e,c) components[c].kind=nil end
function ComponentGetTags(c) return components[c]._tags or "" end
function EntityKill(e) entities[e].alive=false end
function GameGetFrameNum() return frame end
local globals={}
function GlobalsGetValue(key,default) return globals[key] or default end
function GlobalsSetValue(key,value) globals[key]=value end
function GameGetCameraBounds() return -180,-110,360,220 end
function GameCreateCosmeticParticle() end
function ModIsEnabled() return false end
function EntityLoad(path,x,y)
    assert(path==files.."hourglass_field.xml")
    local id=spawn("nh_hourglass_field",x)
    EntityAddComponent2(id,"VariableStorageComponent",{_tags="nh_hourglass_clock",value_int=0})
    return id
end
local cache={}
function dofile_once(path)
    if path==files.."ew.lua" then return {localBody=function(e) return not EntityHasTag(e,"ew_client") end} end
    if not cache[path] then cache[path]=dofile(path) or true end
    return cache[path]
end
local function body(x)
    local id=spawn("props",x)
    EntityAddComponent2(id,"PhysicsBodyComponent",{is_static=false})
    entities[id].body={5,6,0.1,2,-3,0.4}
    return id
end
function PhysicsBodyIDGetFromEntity(e) return entities[e].body and {e} end
function PhysicsBodyIDGetTransform(id) return unpack(entities[id].body) end
function PhysicsBodyIDSetTransform(id,...) entities[id].body={...} end
function PhysicsSetStatic(id,b)
    entities[id].static=b
    if b then for i=4,6 do entities[id].body[i]=0 end end
end
local load=EntityLoad
local failLoad,failSource=false,false
local add=EntityAddComponent2
function EntityAddComponent2(id,kind,data)
    if failSource and data and data._tags=="nh_stasis_source" then return 0 end
    return add(id,kind,data)
end
function EntityLoad(path,x,y)
    if failLoad then return 0 end
    if path~=files.."katana_field.xml" then return load(path,x,y) end
    local field=spawn("nh_katana_field",x)
    EntityAddComponent2(field,"VariableStorageComponent",{_tags="nh_katana_field_clock",value_int=0})
    return field
end
function EntityGetHerdRelationSafe(a,b) return entities[b].friendly and 100 or 0 end
function GetHerdRelation(a,b) return a==b and 100 or 0 end
function GameGetGameEffectCount(entity,effect) return entities[entity].charmed and 1 or 0 end
local query=EntityGetInRadius
local queries=0
function EntityGetInRadius(x,y,r)
    assert(r<=180,"katana must query only its bounded neighborhood")
    queries=queries+1
    return query(x,y,r)
end
local function comp(id,kind,data) return EntityAddComponent2(id,kind,data or {}) end
local player=spawn("player_unit,mortal")
comp(player,"GenomeDataComponent",{herd_id=1})
local weapon=spawn("noita_hideout_katana",0,player)
local inventory=comp(player,"Inventory2Component",{mActiveItem=weapon})
local enemy=spawn("enemy,mortal",20)
local ai=comp(enemy,"AnimalAIComponent")
local behavior=comp(enemy,"LuaComponent",{script_source_file="enemy_tick.lua",execute_every_n_frame=5,script_death="drops.lua"})
local disabled=comp(enemy,"HomingComponent",{enabled=false})
local projectile=spawn("projectile",25)
local vel=comp(projectile,"VelocityComponent",{mVelocity=170})
local shot=comp(projectile,"ProjectileComponent",{mWhoShot=enemy,lifetime=44})
local ttl=comp(projectile,"LifetimeComponent",{kill_frame=frame+15,lifetime=15})
local item=body(30)
comp(item,"ItemComponent")
local friendlyEnemy=spawn("enemy,mortal",35); entities[friendlyEnemy].friendly=true
local companion=spawn("enemy,mortal,noita_hideout_companion",40)
local turret=spawn("enemy,mortal,nh_deployed_turret",45)
local charmed=spawn("enemy,mortal",50); entities[charmed].charmed=true
local allyShot=spawn("projectile",55); comp(allyShot,"ProjectileComponent",{mWhoShot=player})
local unknownShot=spawn("projectile",60); comp(unknownShot,"ProjectileComponent",{mWhoShot=0})
local carried=spawn("enemy,mortal",65,player)
local remoteEnemy=spawn("enemy,mortal,ew_des",70)
comp(remoteEnemy,"VariableStorageComponent",{name="ew_gid_lid",value_string="9",value_bool=false})
local orphanHostile=spawn("projectile",75); comp(orphanHostile,"ProjectileComponent",{mWhoShot=0,mShooterHerdId=2})
local orphanAlly=spawn("projectile",78); comp(orphanAlly,"ProjectileComponent",{mWhoShot=0,mShooterHerdId=1})
local outside=spawn("enemy,mortal",91); local outsideAI=comp(outside,"AnimalAIComponent")
local physicsEnemy=body(83); EntityAddTag(physicsEnemy,"enemy")
local hg=dofile_once(files.."hourglass_field.lua")
local blade=dofile_once(files.."katana_field.lua")
local freeze=dofile_once(files.."stasis.lua")
local paid=0
local function pay() paid=paid+1; return true end
assert(not blade.activate(0,{},pay))
failLoad=true; assert(not blade.activate(player,{},pay)); failLoad=false
failSource=true; assert(not blade.activate(player,{},pay)); failSource=false
assert(paid==0,"failed preparation must not charge")
assert(not blade.activate(player,{},function() paid=paid+1; return false end))
assert(not EntityHasTag(enemy,"nh_hourglass_still"),"rejected payment must not freeze")
local field=assert(blade.activate(player,{radius=90,duration=12},pay))
assert(paid==2 and blade.active(field))
assert(not blade.activate(player,{},pay) and paid==2,"one hold cannot pay twice")
assert(EntityHasTag(enemy,"nh_hourglass_still") and EntityHasTag(projectile,"nh_hourglass_still"))
local recovery=EntityGetFirstComponentIncludingDisabled(enemy,"LuaComponent","nh_hourglass_still")
assert(components[recovery].script_source_file==components[recovery].script_item_picked_up,
    "shared recovery VM must load one self-contained source for updates and pickup")
assert(EntityHasTag(orphanHostile,"nh_hourglass_still"))
assert(entities[physicsEnemy].static,"single-body hostile must be immobilized")
for _,entity in ipairs({player,weapon,item,friendlyEnemy,companion,turret,charmed,allyShot,unknownShot,carried,remoteEnemy,orphanAlly,outside}) do
    assert(not EntityHasTag(entity,"nh_hourglass_still"),"excluded target "..entity)
end
assert(not components[ai].enabled and not components[vel].enabled and not components[disabled].enabled)
assert(components[behavior].enabled and components[behavior].execute_every_n_frame==-1 and components[behavior].script_death=="drops.lua")
local calls=queries; blade.tick(field); assert(queries==calls,"runtime and component duplicate ticks must be coalesced")
entities[player].x=70; entities[outside].x=80; frame=frame+1; blade.tick(field)
assert(entities[field].x==0 and not components[outsideAI].enabled,"field stays at its origin and captures new arrivals each frame")
blade.cancel(field)
assert(not EntityHasTag(enemy,"nh_hourglass_still") and components[ai].enabled and not components[disabled].enabled)
assert(components[behavior].execute_every_n_frame==5 and components[vel].mVelocity==170 and components[shot].lifetime==44)
assert(components[ttl].kill_frame==frame+15 and not blade.active(field))
assert(not entities[physicsEnemy].static and entities[physicsEnemy].body[4]==2 and entities[physicsEnemy].body[5]==-3,
    "thaw restores a hostile rigid body's previous velocity")

-- A short blade finishing must not restore the older hourglass snapshot.
entities[player].x=0
assert(hg.activate(player))
local hourglass=EntityGetWithTag("nh_hourglass_field")[1]
local field2=assert(blade.activate(player,{duration=10},pay))
blade.cancel(field2)
assert(not components[ai].enabled and entities[item].static,"hourglass retains its independent lease")
frame=frame+1800; hg.tick(hourglass)
assert(components[ai].enabled and not entities[item].static)

-- In the reverse order, hourglass release must leave the blade's lease alive.
frame=frame+1
local field3=assert(blade.activate(player,{duration=30},pay))
assert(hg.activate(player))
hourglass=EntityGetWithTag("nh_hourglass_field")[1]
freeze.cancelSource(hourglass); EntityKill(hourglass)
assert(not components[ai].enabled)
blade.cancel(field3)
assert(components[ai].enabled and components[behavior].execute_every_n_frame==5)

-- Save reload rebuilds shared source references without freezing a snapshot twice.
frame=frame+1801
assert(hg.activate(player))
hourglass=EntityGetWithTag("nh_hourglass_field")[1]
field=assert(blade.activate(player,{duration=30},pay))
cache[files.."stasis.lua"]=nil; cache[files.."hourglass_field.lua"]=nil; cache[files.."katana_field.lua"]=nil
freeze=dofile_once(files.."stasis.lua"); hg=dofile_once(files.."hourglass_field.lua"); blade=dofile_once(files.."katana_field.lua")
frame=frame+3; blade.tick(field,true)
assert(not blade.active(field) and not components[ai].enabled,"reload cancels blade but preserves hourglass")
freeze.cancelSource(hourglass); EntityKill(hourglass)
assert(components[ai].enabled)

-- Upgrade an old save whose targets and field predate per-source references.
frame=frame+1801
assert(hg.activate(player))
hourglass=EntityGetWithTag("nh_hourglass_field")[1]
for _,ref in ipairs(EntityGetComponentIncludingDisabled(enemy,"VariableStorageComponent","nh_stasis_ref")) do EntityRemoveComponent(enemy,ref) end
local snapshot=EntityGetFirstComponentIncludingDisabled(enemy,"VariableStorageComponent","nh_hourglass_still")
ComponentSetValue2(snapshot,"value_bool",false)
EntityRemoveComponent(hourglass,EntityGetFirstComponentIncludingDisabled(hourglass,"VariableStorageComponent","nh_stasis_source"))
EntityRemoveTag(hourglass,"nh_stasis_field")
cache[files.."stasis.lua"]=nil; cache[files.."hourglass_field.lua"]=nil; cache[files.."katana_field.lua"]=nil
freeze=dofile_once(files.."stasis.lua"); hg=dofile_once(files.."hourglass_field.lua"); blade=dofile_once(files.."katana_field.lua")
frame=frame+1; freeze.checkTarget(enemy)
assert(not components[ai].enabled and #EntityGetComponentIncludingDisabled(enemy,"VariableStorageComponent","nh_stasis_ref")==1,
    "legacy snapshot must attach to the existing hourglass without thawing")
freeze.cancelSource(hourglass); EntityKill(hourglass)
assert(components[ai].enabled and components[behavior].execute_every_n_frame==5)

-- Picked-up/carried targets, changed allegiances and disappeared controllers thaw.
field=assert(blade.activate(player,{duration=30},pay))
entities[enemy].charmed=true; frame=frame+1; freeze.checkTarget(enemy)
assert(components[ai].enabled)
entities[enemy].charmed=false; frame=frame+1; blade.tick(field)
assert(not components[ai].enabled)
ComponentSetValue2(inventory,"mActiveItem",0); frame=frame+1; blade.tick(field)
assert(not blade.active(field) and components[ai].enabled,"dropping or switching weapon cancels")
ComponentSetValue2(inventory,"mActiveItem",weapon)
field=assert(blade.activate(player,{duration=30},pay))
EntityAddTag(player,"polymorphed_player"); frame=frame+1; blade.tick(field)
assert(not blade.active(field) and components[ai].enabled)
EntityRemoveTag(player,"polymorphed_player")
field=assert(blade.activate(player,{duration=30},pay)); EntityKill(field)
frame=frame+1; freeze.checkTarget(enemy); assert(components[ai].enabled,"lost field must self-recover")

-- Multiplayer visual replicas create local authority-only fields with a short lease.
local peer=spawn("ew_client,player_unit",0)
assert(not blade.applyRemote(peer,"peer/boot/no_weapon",0,0,90,120),"remote caster must hold a katana")
local peerWeapon=spawn("noita_hideout_katana",0,peer)
local peerInventory=comp(peer,"Inventory2Component",{mActiveItem=peerWeapon})
local remote=assert(blade.applyRemote(peer,"peer/boot/1",0,0,90,120))
assert(not components[ai].enabled and not EntityHasTag(remoteEnemy,"nh_hourglass_still"))
frame=frame+15
assert(blade.applyRemote(peer,"peer/boot/1",40,0,180,90)==remote and entities[remote].x==0,"heartbeats cannot move an existing fixed field")
frame=frame+29; assert(blade.active(remote))
frame=frame+1; blade.tick(remote); assert(not blade.active(remote) and components[ai].enabled,"lost sender expires in 30 frames")
remote=assert(blade.applyRemote(peer,"peer/boot/2",0,0,90,120)); blade.cancelRemote("peer/boot/2")
assert(not blade.active(remote) and components[ai].enabled)

-- Long and short Dragon King casts keep the same thirty-frame network lease.
remote=assert(blade.applyRemote(peer,"peer/boot/long",0,0,160,1800))
frame=frame+29;assert(blade.active(remote))
frame=frame+1;blade.tick(remote)
assert(not blade.active(remote) and components[ai].enabled,"thirty-second source duration is not a thirty-second disconnect lease")
remote=assert(blade.applyRemote(peer,"peer/boot/short",0,0,160,120))
local replacement=spawn("noita_hideout_katana",0,peer)
ComponentSetValue2(peerInventory,"mActiveItem",replacement)
frame=frame+1;blade.tick(remote)
assert(not blade.active(remote) and components[ai].enabled,"remote replica must continue holding the same item")
ComponentSetValue2(peerInventory,"mActiveItem",peerWeapon)
field=assert(blade.activate(player,{radius=160,duration=1800},pay))
frame=frame+1799;assert(blade.active(field))
frame=frame+1;blade.tick(field)
assert(not blade.active(field) and components[ai].enabled,"local fields support the Dragon King's full thirty seconds")

-- A shield receipt sets both serialized clocks before acquiring any target.
-- High-HP shields can buy more than a minute of stasis, tiny charges one tick.
for _,duration in ipairs({1,300,7200}) do
    local id,actual=blade.activate(player,{radius=160},function() return true,duration end)
    assert(id and actual==duration and blade.active(id))
    for _,tag in ipairs({"nh_katana_field_clock","nh_stasis_source"}) do
        local clock=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent",tag)
        assert(ComponentGetValue2(clock,"value_int")==frame+duration)
    end
    frame=frame+duration-1;assert(blade.active(id))
    frame=frame+1;blade.tick(id);assert(not blade.active(id) and components[ai].enabled)
end

-- Parrying and field capture share the same faction and authority policy.
local targets=dofile_once(files.."field_targets.lua")
for _,id in ipairs({player,peer,friendlyEnemy,companion,turret,charmed}) do assert(targets.friendly(player,id)) end
assert(not targets.friendly(player,enemy) and not targets.friendly(player,0))
local reflected=spawn("projectile",20)
local reflectedVelocity=comp(reflected,"VelocityComponent",{mVelocity={120,-160}})
local reflectedShot=comp(reflected,"ProjectileComponent",{mWhoShot=enemy,mShooterHerdId=2,lifetime=73})
local reflectedTTL=comp(reflected,"LifetimeComponent",{kill_frame=frame+17,lifetime=17})
local reflectedTick=comp(reflected,"LuaComponent",{script_source_file="projectile_tick.lua",execute_every_n_frame=7})
assert(targets.hostileProjectile(player,reflected) and targets.hostileProjectile(player,reflected,reflectedShot))
for _,shooter in ipairs({player,peer,friendlyEnemy,companion,turret,charmed,weapon,peerWeapon}) do
    ComponentSetValue2(reflectedShot,"mWhoShot",shooter)
    assert(not targets.hostileProjectile(player,reflected,reflectedShot),"friendly shooter or its held weapon was hostile")
end
local enemyWeapon=spawn("wand",20,enemy)
ComponentSetValue2(reflectedShot,"mWhoShot",enemyWeapon)
assert(targets.hostileProjectile(player,reflected,reflectedShot),"shooter root must determine allegiance")
ComponentSetValue2(reflectedShot,"mWhoShot",enemy)
entities[enemy].alive=false
assert(targets.hostileProjectile(player,reflected,reflectedShot),"dead shooter's hostile herd must survive")
ComponentSetValue2(reflectedShot,"mShooterHerdId",1)
assert(not targets.hostileProjectile(player,reflected,reflectedShot))
ComponentSetValue2(reflectedShot,"mShooterHerdId",0)
assert(not targets.hostileProjectile(player,reflected,reflectedShot),"unknown effects are not proof of hostile fire")
entities[enemy].alive=true
ComponentSetValue2(reflectedShot,"mShooterHerdId",2)
local remoteShot=spawn("projectile,ew_des",20)
local remoteVelocity=comp(remoteShot,"VelocityComponent",{mVelocity={120,-160}})
comp(remoteShot,"ProjectileComponent",{mWhoShot=enemy,mShooterHerdId=2})
local gid=comp(remoteShot,"VariableStorageComponent",{name="ew_gid_lid",value_string="24",value_bool=false})
assert(not targets.hostileProjectile(player,remoteShot))
assert(not freeze.redirect(remoteShot,300,0) and components[remoteVelocity].mVelocity[1]==120,"remote velocity must stay untouched")
ComponentSetValue2(gid,"value_bool",true)
assert(targets.hostileProjectile(player,remoteShot),"local DES owner may redirect its authoritative projectile")
local itemShot=spawn("projectile",20)
comp(itemShot,"ProjectileComponent",{mWhoShot=enemy});comp(itemShot,"ItemComponent")
assert(not targets.hostileProjectile(player,itemShot),"physical inventory items are excluded from hostile projectile targeting")
entities[itemShot].parent=player
assert(not targets.hostileProjectile(player,itemShot))

local function speed(x,y)
    local vx,vy=freeze.getVelocity(reflected)
    assert(vx==x and vy==y,"base velocity lost or replaced by frozen world displacement")
end
speed(120,-160)
assert(not freeze.getVelocity(0) and not freeze.getVelocity(enemy))
assert(not freeze.redirect(reflected,0/0,1) and not freeze.redirect(reflected,1,math.huge))
assert(not freeze.redirect(0,1,2) and not freeze.redirect(enemy,1,2))
speed(120,-160)
assert(freeze.redirect(reflected,180,240));speed(180,240)
assert(components[reflectedVelocity].enabled and not EntityHasTag(reflected,"nh_hourglass_still"))

-- A frozen projectile keeps its existing entity, timers and damage. Updating
-- its firing faction before redirect removes just the now-friendly blade lease.
field=assert(blade.activate(player,{duration=30},pay))
assert(not components[reflectedVelocity].enabled and ComponentHasTag(reflectedVelocity,"nh_hourglass_paused"))
speed(180,240)
ComponentSetValue2(reflectedShot,"mWhoShot",player);ComponentSetValue2(reflectedShot,"mShooterHerdId",1)
assert(freeze.redirect(reflected,300,0));speed(300,0)
assert(not EntityHasTag(reflected,"nh_hourglass_still") and components[reflectedVelocity].enabled and components[reflectedShot].enabled)
assert(components[reflectedShot].lifetime==73 and components[reflectedTTL].kill_frame==frame+17
    and components[reflectedTick].execute_every_n_frame==7)
frame=frame+1;blade.tick(field)
assert(not EntityHasTag(reflected,"nh_hourglass_still"),"same blade field recaptured a friendly parried projectile")
blade.cancel(field)

-- Both cancellation orders retain the independent hourglass, including after
-- a module reload; reflection must never enable movement ahead of that lease.
local reflectedHoming=comp(reflected,"HomingComponent",{target_tag="prey",target_who_shot=true,predefined_target=player})
for _,cancelFirst in ipairs({"blade","hourglass"}) do
    frame=frame+1801
    ComponentSetValue2(reflectedShot,"mWhoShot",enemy);ComponentSetValue2(reflectedShot,"mShooterHerdId",2)
    ComponentSetValue2(reflectedTTL,"kill_frame",frame+17)
    field=assert(blade.activate(player,{duration=30},pay))
    assert(hg.activate(player));hourglass=EntityGetWithTag("nh_hourglass_field")[1]
    assert(#EntityGetComponentIncludingDisabled(reflected,"VariableStorageComponent","nh_stasis_ref")==2)
    local parry=dofile(files.."katana_parry.lua")
    assert(parry.reflect(player,reflected,reflectedShot,reflectedVelocity,-1,0));speed(-300,0)
    assert(components[reflectedShot].mWhoShot==player and components[reflectedShot].mShooterHerdId==1
        and components[reflectedHoming].target_tag=="enemy" and not components[reflectedHoming].target_who_shot
        and components[reflectedHoming].predefined_target==0 and not components[reflectedHoming].enabled,
        "real parry must retarget homing without running its paused integrator")
    assert(EntityHasTag(reflected,"nh_hourglass_still") and not components[reflectedVelocity].enabled
        and #EntityGetComponentIncludingDisabled(reflected,"VariableStorageComponent","nh_stasis_ref")==1)
    cache[files.."stasis.lua"]=nil;freeze=dofile_once(files.."stasis.lua")
    speed(-300,0)
    if cancelFirst=="blade" then
        blade.cancel(field);assert(not components[reflectedVelocity].enabled,"blade cancel released the independent hourglass")
    end
    freeze.cancelSource(hourglass);EntityKill(hourglass)
    assert(components[reflectedVelocity].enabled and components[reflectedShot].enabled and components[reflectedHoming].enabled
        and components[reflectedHoming].target_tag=="enemy" and not EntityHasTag(reflected,"nh_hourglass_still"))
    speed(-300,0)
    assert(components[reflectedShot].lifetime==73 and components[reflectedTTL].kill_frame==frame+17)
    if cancelFirst=="hourglass" then blade.cancel(field) end
end

-- Originally disabled velocity must not be force-enabled by reflection.
ComponentSetValue2(reflectedShot,"mWhoShot",enemy);ComponentSetValue2(reflectedShot,"mShooterHerdId",2)
components[reflectedVelocity].enabled=false
field=assert(blade.activate(player,{duration=30},pay))
assert(not ComponentHasTag(reflectedVelocity,"nh_hourglass_paused"))
ComponentSetValue2(reflectedShot,"mWhoShot",player)
assert(freeze.redirect(reflected,0,-300))
assert(not components[reflectedVelocity].enabled and not EntityHasTag(reflected,"nh_hourglass_still"))
blade.cancel(field)

-- Bounded round-robin scans eventually reach a crowded query's tail.
for n=1,400 do local e=spawn("enemy,mortal",20); comp(e,"AnimalAIComponent") end
field=assert(blade.activate(player,{duration=30},pay))
local last=#entities-1
for n=1,5 do frame=frame+1; blade.tick(field) end
assert(EntityHasTag(last,"nh_hourglass_still"),"bounded scan must not starve later entities")
blade.cancel(field)
print("Katana fields: shared hostile targeting, redirected frozen velocities, independent leases, payment rollback, restoration and bounded scans passed.")
