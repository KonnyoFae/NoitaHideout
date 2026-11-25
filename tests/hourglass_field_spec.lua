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
function ComponentGetValue2(c,k) return components[c][k] end
function ComponentSetValue2(c,k,v) components[c][k]=v end
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
local hg=dofile(files.."hourglass_field.lua")
local function comp(id,kind,data) return EntityAddComponent2(id,kind,data or {}) end
local player=spawn("player_unit,mortal")
local enemy=spawn("enemy,mortal",180)
local projectile=spawn("projectile",10)
local vel=comp(projectile,"VelocityComponent",{mVelocity=29})
local proj=comp(projectile,"ProjectileComponent",{lifetime=90})
local ttl=comp(projectile,"LifetimeComponent",{kill_frame=frame+11,lifetime=80})
local secondTTL=comp(projectile,"LifetimeComponent",{kill_frame=frame+20,lifetime=80})
local ai=comp(enemy,"AnimalAIComponent")
local behavior=comp(enemy,"LuaComponent",{script_source_file="attack.lua",execute_every_n_frame=6,script_death="reward.lua"})
local off=comp(enemy,"HomingComponent",{enabled=false})
local outside=spawn("projectile",181)
local terrain=body(50)
local item=body(40)
local itemMotion=comp(item,"VelocityComponent",{_tags="enabled_in_world"})
local guarded={player,spawn("ew_client,player_unit"),spawn("polymorphed_player,enemy"),spawn("ew_notplayer,enemy"),
    spawn("ew_peer,mortal"),spawn("nh_ew_waiting,mortal"),spawn("projectile",0,player),spawn("enemy,ew_des"),
    spawn("projectile",0),spawn("enemy,ew_des")}
comp(guarded[#guarded-1],"VariableStorageComponent",{_tags="nh_ew_deposit_lock"})
comp(guarded[#guarded],"VariableStorageComponent",{name="ew_gid_lid",value_string="22",value_bool=false})
local owned=spawn("enemy,ew_des")
comp(owned,"VariableStorageComponent",{name="ew_gid_lid",value_string="23",value_bool=true})
comp(owned,"AnimalAIComponent")
assert(not hg.activate(player,function() return false end))
assert(not EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_hourglass_cast"))
assert(#EntityGetWithTag("nh_hourglass_field")==0 and not EntityHasTag(enemy,"nh_hourglass_still"))
assert(not hg.activate(0) and hg.activate(player))
assert(not hg.activate(player))
local anchor=EntityGetWithTag("nh_hourglass_field")[1]
assert(anchor)
for _,id in ipairs(guarded) do assert(not EntityHasTag(id,"nh_hourglass_still"),id) end
assert(EntityHasTag(owned,"nh_hourglass_still") and not EntityHasTag(outside,"nh_hourglass_still"))
assert(not components[vel].enabled and not components[proj].enabled and not components[ai].enabled)
assert(not components[off].enabled and components[behavior].enabled and components[behavior].execute_every_n_frame==-1)
assert(entities[terrain].static and not components[itemMotion].enabled)
entities[player].x=900
entities[outside].x=101
frame=61
hg.tick(anchor)
assert(entities[anchor].x==0 and EntityHasTag(outside,"nh_hourglass_still"))
entities[item].parent=player
dofile(files.."hourglass_pickup.lua")
item_pickup(item,player)
assert(not EntityHasTag(item,"nh_hourglass_still") and not components[itemMotion].enabled)
assert(not ComponentHasTag(itemMotion,"nh_hourglass_paused") and not EntityGetFirstComponentIncludingDisabled(item,"VariableStorageComponent","nh_hourglass_still"))
assert(not EntityGetFirstComponentIncludingDisabled(item,"LuaComponent","nh_hourglass_still"))
-- Removing an earlier timer while frozen must not assign its remaining life to another timer.
EntityRemoveComponent(projectile,ttl)
-- Fresh Lua state after save/load. All thaw state belongs to the original components.
frame=1859
hg=dofile(files.."hourglass_field.lua")
hg.checkTarget(projectile)
assert(not components[proj].enabled)
frame=1860
hg.tick(anchor)
assert(not EntityGetIsAlive(anchor) and not EntityHasTag(projectile,"nh_hourglass_still"))
assert(components[vel].enabled and components[vel].mVelocity==29 and components[proj].enabled and components[proj].lifetime==90)
assert(components[secondTTL].enabled and components[secondTTL].kill_frame==1880)
assert(components[ai].enabled and not components[off].enabled and components[behavior].execute_every_n_frame==6)
assert(not entities[terrain].static and entities[terrain].body[4]==2 and entities[terrain].body[5]==-3 and entities[terrain].body[6]==0.4)
-- A streamed out controller or a forced teleport cannot leave a target suspended.
entities[player].x=0
assert(hg.activate(player))
anchor=EntityGetWithTag("nh_hourglass_field")[1]
entities[enemy].x=500
frame=frame+1
hg.checkTarget(enemy)
assert(not EntityHasTag(enemy,"nh_hourglass_still") and components[ai].enabled)
EntityKill(anchor)
frame=frame+1
hg.checkTarget(projectile)
assert(not EntityHasTag(projectile,"nh_hourglass_still") and components[vel].enabled)
assert(not hg.activate(player),"streaming out must not bypass the activation deadline")
frame=frame+1800
assert(hg.activate(player))
assert(#EntityGetComponentIncludingDisabled(player,"VariableStorageComponent","nh_hourglass_cast")==1)
-- A new field-script VM broad-scans on its first update, then keeps the normal cadence.
local seen={}
cache[files.."hourglass_field.lua"]={tick=function(id,fresh) seen[#seen+1]=fresh end}
function GetUpdatedEntityID() return anchor end
dofile(files.."hourglass_tick.lua")
dofile(files.."hourglass_tick.lua")
assert(seen[1]==true and seen[2]==false)
print("Hourglass: deterministic fixed circle, local authority, recoverable timers, physics and pickup handoff passed.")
