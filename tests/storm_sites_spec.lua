local stations=dofile("mods/noita_hideout/files/storm/sites/stations.lua")
local entities,globals,spawns={},{},{}
local notices,streamed,fail={},true,nil
local landings={}
local now,biome=900*60,"$biome_desert"
local nearbyFrame,rollCommon=false,false
local crystalFile=assert(io.open("mods/noita_hideout/files/storm/sites/crystal.xml"))
local crystalXml=crystalFile:read("*a")
crystalFile:close()
local function make(path,x,y)
    local kind=path:match("([^/]+)%.xml$") or path
    local id=#entities+1
    local e={kind=kind,x=x,y=y,vars={},children={},scripts={},tags={}}
    if kind=="rig" then
        e.sprites={body={image_file="mods/cycle_storm/files/sites/oil_drill.png"},production_meter={tag="production_meter"}}
        e.scripts[1]={script_interacting="mods/cycle_storm/files/sites/activate.lua"}
    elseif kind=="well" then
        e.tags.nh_storm_site=true
        e.tags.nh_segmented_tower=true
        e.sprites={tower_back={}}
        for i=1,3 do e.sprites["port"..i.."_bud"]={enabled=false} end
    elseif kind=="crystal" then
        for tag in crystalXml:match('<Entity[^>]- tags="([^"]+)"'):gmatch("[^,]+") do e.tags[tag]=true end
        e.hitbox={}
        for k,v in crystalXml:match("<HitboxComponent ([^>]+)"):gmatch('([%w_]+)="([%-0-9]+)"') do
            e.hitbox[k]=tonumber(v)
        end
        e.glow={}
    end
    entities[id]=e
    spawns[kind]=(spawns[kind] or 0)+1
    for k,v in pairs({started=-1,wave=0,produced=0,port1=0,port2=0,port3=0,port=0,pure=0}) do
        e.vars[#e.vars+1]={name=k,value_int=v}
    end
    return id
end
local player=make("player",0,-1)
function EntityLoad(path,x,y)
    if fail and fail(path,x,y) then return 0 end
    return make(path,x,y)
end
function GameGetFrameNum() return now end
function GlobalsGetValue(k,d) return globals[k] or d end
function GlobalsSetValue(k,v) globals[k]=v end
function GamePrintImportant(title,desc,decoration)
    if title=="$nh_storm_sites_confirmed" then notices[#notices+1]={title,desc,decoration}
    else landings[#landings+1]=desc end
end
function GameTextGetTranslatedOrNot(k) return k end
function GamePrint(k) landings[#landings+1]=k end
function EntityGetWithTag(tag)
    local result={}
    for id,e in ipairs(entities) do if not e.dead and not e.unloaded and EntityHasTag(id,tag) then result[#result+1]=id end end
    return result
end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
function GameGetCameraBounds() return entities[player].x-200,-115,400,230 end
function BiomeMapGetName() return biome end
function GameGetSkyVisibility() return 1 end
function DoesWorldExistAt() return streamed end
function ProceduralRandomi(_,__,lo,hi) return rollCommon and hi==10000 and hi or lo end
function RaytraceSurfaces(x,y,_,endY) return y<0 and endY>=0,x,0 end
function EntityGetComponentIncludingDisabled(id,kind)
    if kind=="VariableStorageComponent" then return entities[id].vars end
    if kind=="LuaComponent" then return entities[id].scripts end
    local result={}
    for _,c in pairs(entities[id].sprites or {}) do result[#result+1]=c end
    return result
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    if kind=="HitboxComponent" then return entities[id].hitbox end
    if kind=="PhysicsImageShapeComponent" then return entities[id].shape end
    if kind=="SpriteComponent" and entities[id].sprites then return entities[id].sprites[tag] end
    if kind=="AudioLoopComponent" then return entities[id].drilling end
    if kind=="ParticleEmitterComponent" and tag=="nh_ripe_glow" then return entities[id].glow end
end
function ComponentHasTag(c,tag) return c.tag==tag end
function EntityRemoveComponent(id,c)
    for name,component in pairs(entities[id].sprites or {}) do
        if c==component then entities[id].sprites[name]=nil; return end
    end
    if entities[id].eject==c then entities[id].eject=nil end
end
function EntityLoadToEntity(file,id)
    local e=entities[id]
    if file:match("rig_body.xml$") then
        assert(not next(e.sprites))
        e.sprites.cycle_storm_rig_body={}
    elseif file:match("crystal_glow.xml$") then
        assert(e.kind=="crystal" and not e.glow); e.glow={}
    else
        assert(file:match("rig_drilling.xml$") and not e.drilling)
        e.drilling={}
    end
end
function EntityAddComponent2(id,kind,config)
    assert(kind=="LuaComponent")
    if config.script_source_file:match("/eject_can.lua$") then entities[id].eject=config
    else
        assert(config.script_source_file=="mods/noita_hideout/files/storm/sites/tick.lua")
        table.insert(entities[id].scripts,config)
    end
end
function ComponentGetIsEnabled(c) return c.enabled end
function EntitySetComponentIsEnabled(_,c,enabled) c.enabled=enabled end
function EntityGetFirstComponent() return {} end
function EntityRefreshSprite() end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityHasTag(id,tag) return (id==player and tag=="player_unit") or (entities[id].kind=="rig" and tag=="cycle_storm_rig") or (entities[id].kind=="well" and tag=="cycle_storm_well") or entities[id].tags[tag] end
function EntityGetInRadiusWithTag(_,__,r) return (r>400 or (r==140 and nearbyFrame)) and {player} or {} end
function EntityAddChild(p,c) entities[c].parent=p; table.insert(entities[p].children,c) end
function EntityGetParent(e) return entities[e].parent end
function EntityGetAllChildren(e) return entities[e].children end
function EntityKill(e) entities[e].dead=true end
local ejecting,bodyReady
function GetUpdatedEntityID() return ejecting end
function GetUpdatedComponentID() return entities[ejecting].eject end
function EntityGetRootEntity(id) return entities[id].parent or id end
function PhysicsBodyIDGetFromEntity() return bodyReady and {42} or {} end
function PhysicsApplyForce(id,x,y)
    if entities[id].eject then
        assert(bodyReady and x>0 and y<0 and not entities[id].thrown)
        entities[id].thrown=true
    end
end

local function status(tower,rig,workingRig)
    local hasTower,hasRig,_,__,runningTower,runningRig=stations.available()
    assert(hasTower==tower and hasRig==rig and runningTower==tower)
    if workingRig~=nil then assert(runningRig==workingRig) end
end
status(false,false)
-- Confirm on the exact core entry frame, even underground and between
-- placement polls. Reloading the same round must not announce it twice.
biome="$biome_coalmine"; now=54016
stations.update(3,53999)
assert(#notices==0)
now=54017; stations.update(4,54000)
local _,__,wellPending,rigPending=stations.available()
assert(wellPending and rigPending and #notices==1 and notices[1][2]=="$nh_storm_sites_pending_both")
assert(not spawns.rig and not spawns.well and #landings==0)
stations=dofile("mods/noita_hideout/files/storm/sites/stations.lua")
stations.update(4,54000)
assert(#notices==1)
biome="$biome_desert"; now=64860
stations.update(5,now-17,true)
assert(not spawns.rig and globals["cycle_storm.sites.desert"]=="pending")
stations.update(5,now-17)
status(false,true,false)
_,__,wellPending,rigPending=stations.available()
assert(wellPending and not rigPending and #landings==1 and landings[1]=="$nh_storm_rigs_arrive_desc")
assert(spawns.rig==3 and globals["cycle_storm.idle_rigs"]=="3")
assert(entities[2].x-13>200 and entities[3].x-entities[2].x==68)
stations.update(5,now-17)
stations.update(5,now-17)
assert(#notices==1)
assert(entities[2].tags.nh_storm_site and #entities[2].scripts==2)
assert(entities[2].scripts[1].script_interacting=="mods/noita_hideout/files/storm/sites/activate.lua")
-- Exercise the production callback through the same XML field read by Noita.
local xml=assert(io.open("mods/noita_hideout/files/storm/sites/rig.xml"))
local tick=assert(xml:read("*a"):match('script_source_file="([^"]+)"'))
xml:close()
function dofile_once(path) return dofile(path) end
ejecting=2
dofile(tick)
assert(not stations.rigProgress(2,now) and not entities[2].drilling and entities[2].sprites.cycle_storm_rig_body)
local start=now
dofile(entities[2].scripts[1].script_interacting)
interacting(player,2)
interacting(player,2)
status(false,true,true) -- The interaction VM has started one of three idle rigs.
assert(globals["cycle_storm.idle_rigs"]=="2" and entities[2].drilling and not entities[3].drilling)
for seconds=0,300 do
    now=start+seconds*60
    ejecting=2
    dofile(tick)
    local cans=spawns.storm_mercury_pressure or 0
    if seconds==59 then assert(cans==0) end
    if seconds==30 or seconds==60 then
        local running,fill,left,count=stations.rigProgress(2,now)
        assert(running and fill==(seconds==30 and 0.5 or 0))
        assert(left==(seconds==30 and 30 or 45) and count==cans)
    end
    if seconds==60 then
        assert(cans==1)
        for id,e in ipairs(entities) do if e.eject then ejecting=id end end
        local can=entities[ejecting]
        assert(can.x>entities[2].x+13 and can.y<=entities[2].y-14)
        dofile(can.eject.script_source_file)
        assert(can.eject and not can.thrown)
        bodyReady=true
        dofile(can.eject.script_source_file)
        assert(can.thrown and not can.eject)
    end
    if seconds==150 then assert(cans==4) end
    if seconds==180 then assert(cans==7 and spawns.firemage_weak==1) end
    if seconds==299 then assert(cans==18) end
end
assert(spawns.storm_mercury_pressure==19 and entities[2].dead)
now=now+1200*60
stations.update(4,900*60)
assert(spawns.rig==3)
biome="$biome_winter"
entities[player].x=35840
fail=function(path) return path:match("/shell.xml$") end
stations.update(4,900*60)
status(false,true)
assert(#notices==2 and notices[2][2]=="$nh_storm_sites_pending_well" and #landings==1 and globals["cycle_storm.sites.winter"]=="pending")
fail=nil
stations.update(4,900*60)
status(true,true)
assert(#notices==2 and #landings==2 and landings[2]=="$nh_storm_tower_arrives_desc")
local well
for id,e in ipairs(entities) do if e.kind=="well" then well=id end end
assert(well and spawns.shell==1 and math.abs(entities[well].x-35840)<500)
local shell=entities[entities[well].children[1]]
assert(shell.x==entities[well].x-64 and shell.y==entities[well].y-256)
start=now
local function wellTick(seconds) now=start+seconds*60; stations.tick(well) end
local fill,remaining,roof=stations.wellProgress(well,now)
assert(fill==1 and remaining==600 and roof==231)
-- Upgrade an already placed tower. It is discovered silently, even mid-phase.
globals["cycle_storm.sites.well_locations"]=nil
stations=dofile("mods/noita_hideout/files/storm/sites/stations.lua")
now=start+1; stations.update(1,1); status(true,true); assert(#notices==2)
local tank_y={75,101,128}
wellTick(0)
for i,y in ipairs(tank_y) do
    local bud=entities[well].sprites["port"..i.."_bud"]
    assert(bud.enabled and (8-bud.offset_x)*bud.special_scale_x==77-64)
    assert((8-bud.offset_y)*bud.special_scale_y==y-256)
end
wellTick(45); wellTick(90)
assert(spawns.crystal==3)
for i,y in ipairs(tank_y) do
    local ripe=entities[entities[well].children[i+1]]
    assert(ripe.x==shell.x+77 and ripe.y==shell.y+y)
    assert(not entities[well].sprites["port"..i.."_bud"].enabled)
end
local crystal=entities[well].children[2]
local function directHit(id,damage)
    local target=entities[id]
    assert(target.tags.hittable and target.hitbox.aabb_min_x<0 and target.hitbox.aabb_max_x>0)
    assert(target.hitbox.aabb_min_y==-8 and target.hitbox.aabb_max_y==8)
    ejecting=id
    dofile(assert(crystalXml:match('script_damage_received="([^"]+)"')))
    damage_received(damage)
end
entities[crystal].glow=nil
entities[crystal].tags.hittable=nil
entities[crystal].hitbox.aabb_min_y=-7
entities[well].tags.nh_crystal_target_checked=nil
entities[well].tags.nh_crystal_glow_checked=true
entities[well].tags.nh_crystal_art=true -- Previously upgraded sprite, still missing the new emitter.
wellTick(90); wellTick(90)
assert(entities[crystal].glow)
directHit(crystal,0); assert(not entities[crystal].dead)
directHit(crystal,0.12); directHit(crystal,0.12)
assert(spawns.storm_mana_pure==2 and spawns.crystal_burst==1)
assert(not entities[entities[well].children[3]].dead and not entities[entities[well].children[4]].dead)
assert(entities[#entities].x==shell.x+77 and entities[#entities].y==shell.y+75)
wellTick(91); assert(entities[well].sprites.port1_bud.enabled)
wellTick(134); assert(spawns.crystal==3)
rollCommon=true
wellTick(135); assert(spawns.crystal==4)
local regrown=entities[entities[well].children[5]]
assert(regrown.x==shell.x+77 and regrown.y==shell.y+75)
directHit(entities[well].children[5],0.12)
assert(spawns.storm_mana==2 and spawns.crystal_burst==2)
-- A live old frame is exchanged once, clear of the player, without touching its occupied ports.
entities[well].tags.nh_segmented_tower=nil
shell.shape={image_file="mods/noita_hideout/files/storm/sites/tower_structure.png"}
streamed=false; wellTick(136)
streamed=true; nearbyFrame=true; wellTick(137)
nearbyFrame=false; fail=function(path) return path:match("/shell.xml$") end
wellTick(138); assert(not shell.dead and not entities[well].tags.nh_segmented_tower)
fail=nil; wellTick(139); wellTick(140)
assert(shell.dead and spawns.shell==2 and entities[well].tags.nh_segmented_tower)
local newShell=entities[entities[well].children[6]]
assert(newShell.kind=="shell" and newShell.x==shell.x and newShell.y==shell.y)
assert(not entities[entities[well].children[3]].dead and spawns.crystal==4)
wellTick(180); wellTick(360); wellTick(540)
fill,remaining=stations.wellProgress(well,start+300*60)
assert(fill==0.5 and remaining==300)
-- Unload the region, reload the Lua state, and let the tower expire at a distance.
entities[well].unloaded=true; streamed=false
stations=dofile("mods/noita_hideout/files/storm/sites/stations.lua")
stations.update(1,0); status(true,true)
now=start+600*60; status(false,true)
entities[well].unloaded=false; streamed=true
assert(spawns.shotgunner==9 and spawns.miner==12 and spawns.icemage==1)
wellTick(600); assert(entities[well].dead and entities[entities[well].children[1]].dead)
assert(newShell.dead and spawns.shell==2)
stations.update(1,0); status(false,true)
-- The cluster stays usable until its last idle or working rig is gone.
EntityKill(3); stations.update(1,0); status(false,true)
assert(globals["cycle_storm.idle_rigs"]=="1")
stations.activate(player,4)
entities[4].unloaded=true; streamed=false
stations=dofile("mods/noita_hideout/files/storm/sites/stations.lua")
now=now+60; stations.update(1,0); status(false,true,true)
now=now+299*60-1; status(false,true,true)
now=now+1; status(false,false,false)
assert(#notices==2)
-- A rolled-back partial cluster never lights the HUD or queues a toast.
entities[4].unloaded=false; streamed=true; biome="$biome_desert"
local attempts=0
fail=function(path)
    if path:match("/rig.xml$") then attempts=attempts+1; return attempts%2==0 end
end
assert(stations.update(4,900*60)); status(false,false)
assert(attempts==0 and not entities[4].dead)
stations.tick(4)
assert(entities[4].dead)
now=now+60; stations.update(4,900*60+60)
assert(attempts==4 and #notices==3 and #landings==2 and globals["cycle_storm.sites.desert"]=="pending")
-- A tower destroyed early in a loaded chunk no longer counts. Another live
-- tower keeps the indicator blue until its own deadline.
local a,b=make("well",50,0),make("well",90,0)
for _,id in ipairs({a,b}) do
    for _,c in ipairs(entities[id].vars) do if c.name=="started" then c.value_int=now end end
end
biome="$biome_coalmine"
stations.update(1,0); status(true,false)
EntityKill(b); stations.update(1,0); status(true,false)
EntityKill(a); stations.update(1,0); status(false,false)
assert(#notices==3 and #landings==2)
-- One idle rig keeps the cluster available. The two working rigs retain
-- their individual deadlines after the cluster is unloaded and the VM reloaded.
local first,second,idle=make("rig",700,0),make("rig",768,0),make("rig",836,0)
now=now-now%60+60
stations.activate(player,first)
now=now+60; stations.activate(player,second)
local lastDeadline=now+300*60
entities[first].unloaded,entities[second].unloaded,entities[idle].unloaded=true,true,true
streamed=false; stations=dofile("mods/noita_hideout/files/storm/sites/stations.lua")
stations.update(1,0); status(false,true,true)
now=lastDeadline-60; status(false,true,true)
now=lastDeadline; status(false,true,false)
print("Storm sites: group lock, full oil schedule, reinforcements, blocked ports, shatter, regrowth and expiry passed.")
