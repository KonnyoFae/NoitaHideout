local root="mods/noita_hideout/files/"
dofile(root.."store.lua")
local entities,frame,nextId={},0,10
local held,pressed,wall,deny=false,false,false,false
local controls={}
local state={resources={},levels={reinforcement=2},gearLink={id=7,item={kind="data_link_3",remaining=2}}}
local notices,delivered,flashes,shots={},{},0,{}
local function unit(x,y,herd)
    return {x=x,y=y,tags={mortal=true},cs={AnimalAIComponent={},GenomeDataComponent={herd_id=herd},
        DamageModelComponent={hp=2,max_hp=2},CharacterDataComponent={mVelocity={0,0},is_on_ground=true}}}
end
entities[1]=unit(0,0,9)
entities[1].cs.ControlsComponent=controls
function EntityGetFirstComponentIncludingDisabled(id,k) return entities[id] and entities[id].cs[k] end
function EntityGetComponentIncludingDisabled(id,kind)
    local e=entities[id]
    if e and kind=="LuaComponent" and e.aura then return {e.aura} end
    return {}
end
function EntityRemoveComponent() end
function EntityAddComponent2(id,k,c) entities[id].cs[k]=c; return c end
function ComponentSetValue2(c,k,v,w) c[k]=w and {v,w} or v end
function ComponentGetValue2(c,k) if type(c[k])=="table" then return unpack(c[k]) end; return c[k] end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
EntityGetFirstHitboxCenter=EntityGetTransform
function EntitySetTransform(id,x,y) entities[id].x,entities[id].y=x,y end
EntityApplyTransform=EntitySetTransform
function EntityHasTag(id,k) return entities[id].tags[k] end
function EntityAddTag(id,k) entities[id].tags[k]=true end
function EntityRemoveTag(id,k) entities[id].tags[k]=nil end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityKill(id) entities[id]=nil end
function EntityGetWithTag() return {1} end
function EntityGetHerdRelation(a,b) return entities[a].cs.GenomeDataComponent.herd_id==entities[b].cs.GenomeDataComponent.herd_id and 100 or 0 end
function EntityGetInRadiusWithTag(x,y,r,tag)
    local list={}
    for id,e in pairs(entities) do
        if e.tags[tag] and (e.x-x)^2+(e.y-y)^2<=r*r then list[#list+1]=id end
    end
    return list
end
function DoesWorldExistAt() return true end
function RaytracePlatforms(x,y,tx,ty)
    if wall then return true,x,y end
    if y<=20 and ty>=20 then return true,tx,20 end
    return false
end
function EntityLoad(path,x,y)
    nextId=nextId+1
    local e=unit(x,y,45); entities[nextId]=e
    if path:find("animals/",1,true) or path:match("/turrets/[%w_]+_reinforcement%.xml$") then
        if path:find("/necrobot.xml",1,true) then e.aura={script_source_file="data/scripts/animals/necrobot.lua"} end
        e.tags.enemy,e.tags.homing_target=true,true; delivered[#delivered+1]={id=nextId,path=path}
        if path:find("_physics",1,true) or path:find("drone_shield",1,true) then e.cs.PhysicsBodyComponent={id=nextId} end
    else
        e.tags={}
        if path==root.."supply_pod.xml" then e.tags.nh_supply_pod=true
        elseif path==root.."escort_shield.xml" then e.tags.nh_escort_shield=true
        elseif path==root.."pod_open_fx.xml" then flashes=flashes+1
        else assert(path=="data/entities/projectiles/healshot_slow.xml")
            e.cs.VelocityComponent,e.cs.ProjectileComponent={},{}
        end
    end
    return nextId
end
function PhysicsComponentGetTransform(c) local e=entities[c.id]; return e.x,e.y,0,0,0,0 end
function PhysicsComponentSetTransform(c,x,y,_,vx,vy) c.motion={x=x,y=y,vx=vx,vy=vy} end
function GamePosToPhysicsPos(x,y) return x,y end
GameVecToPhysicsVec=GamePosToPhysicsPos
function GameShootProjectile(id,x,y,tx,ty,bolt) shots[#shots+1]={x=tx,y=ty,owner=id,bolt=bolt} end
function GameGetFrameNum() return frame end
function InputIsKeyDown(code) return code==224 and held end
function InputIsKeyJustDown(code) return code==224 and pressed end
function InputIsMouseButtonDown() return false end
local support=dofile(root.."fire_support.lua")
local reinforcements=dofile(root.."reinforcements.lua")
local function tick(key)
    frame=frame+1
    for _,k in ipairs({"Up","Down","Left","Right"}) do controls["mButtonDown"..k]=k==key end
    support.input(state,1,false)
    support.finishInput()
    pressed=false
    support.update(state,1,function(edit) return not deny and edit(state) end,function(msg) notices[#notices+1]=msg end)
    return support.view(state,1)
end
local function selectUnit(n)
    held,pressed=true,true
    tick(); tick("Right"); tick("Down")
    for _=2,n do tick(); tick("Down") end
    return tick("Right")
end
assert(selectUnit(1).projectStatus=="insufficient_packs")
held=false; tick()
local function summon(n)
    local cost=({4,5,5,10,9,14,10,20,24,22,21,30,18})[n]
    state.resources.reinforcement_logistics=cost
    local v=selectUnit(n)
    assert(v.menu.level==3 and v.payment.resource=="reinforcement_logistics" and v.payment.cost==cost)
    tick(); local call=tick("Right").call
    held=false; frame=call.connectedAt-2
    assert(tick().call.phase=="connecting")
    entities[1].x=entities[1].x+30
    assert(tick().call.phase=="descending" and state.resources.reinforcement_logistics==cost)
    for _=1,120 do if not tick() then return end end
    error("pod never opened")
end
local names={"drone_physics","basebot_soldier","mg_turret","healerdrone_physics","basebot_hidden","missilecrab","chaingun_turret","drone_shield","drone_lasership","assassin","monk","necrobot","missile_turret"}
for i,name in ipairs(names) do
    state.levels.reinforcement=i<=3 and 1 or (i<=7 and 2 or 3)
    summon(i)
    local turrets={mg_turret="mg_reinforcement",chaingun_turret="chaingun_reinforcement",missile_turret="missile_reinforcement"}
    local expected=turrets[name] and root.."turrets/"..turrets[name]..".xml" or "data/entities/animals/"..name..".xml"
    assert(#delivered==i and delivered[i].path==expected)
    local e=entities[delivered[i].id]
    assert(e.tags.nh_reinforcement and not e.tags.enemy and e.cs.GenomeDataComponent.herd_id==9)
    assert(not e.tags.homing_target,"new escort is still a homing target")
    assert(e.cs.AnimalAIComponent.dont_counter_attack_own_herd and math.abs(e.x-entities[1].x)<50)
    if turrets[name] then assert(not e.cs.StreamingKeepAliveComponent and not e.cs.LuaComponent) end
    assert(flashes==i and not state.resources.reinforcement_logistics and state.gearLink.item.remaining==2)
end
deny=true; summon(4)
assert(#delivered==#names+1 and not entities[delivered[#delivered].id] and flashes==#names and state.resources.reinforcement_logistics==10)
local drone,medic,guard=delivered[1].id,delivered[4].id,delivered[6].id
local m=entities[medic]
EntitySetTransform(1,m.x-18,m.y)
entities[1].cs.DamageModelComponent.hp=1
entities[guard].cs.DamageModelComponent.hp=1
EntitySetTransform(guard,m.x-9,m.y)
entities[2]=unit(m.x-3,m.y,45)
entities[2].tags.homing_target=true
m.tags.homing_target=true
entities[2].cs.DamageModelComponent.hp=0.1
m.cs.VariableStorageComponent.value_int=0
reinforcements.update(medic)
local targets=EntityGetInRadiusWithTag(m.x,m.y,120,"homing_target")
assert(#targets==1 and targets[1]==2,"only the hostile, not the legacy escort, should attract homing fire")
assert(#shots==1 and shots[1].x==entities[1].x and not m.cs.AnimalAIComponent.attack_ranged_enabled)
entities[1].cs.DamageModelComponent.hp=2
frame=frame+30; reinforcements.update(medic)
assert(#shots==2 and shots[2].x==entities[guard].x)
wall=true; frame=frame+30; reinforcements.update(medic)
assert(#shots==2 and m.cs.AnimalAIComponent.attack_ranged_enabled and not m.cs.AnimalAIComponent.tries_to_ranged_attack_friends)
wall=false
EntitySetTransform(1,entities[guard].x-85,entities[guard].y)
reinforcements.update(guard)
assert(entities[guard].cs.CharacterDataComponent.mVelocity[1]<0)
EntitySetTransform(drone,entities[1].x-58,entities[1].y)
reinforcements.update(drone)
assert(entities[drone].cs.PhysicsBodyComponent.motion.vx>0)
EntitySetTransform(1,entities[drone].x+600,0)
reinforcements.update(drone)
assert(math.abs(entities[drone].cs.PhysicsBodyComponent.motion.x-entities[1].x)<50)
print("All reinforcement menu calls, pod release, rollback, escort movement and repair targeting passed.")

do
    state.levels.reinforcement=3
    deny=false
    local id=delivered[8].id
    local shields={}
    function EntityGetAllChildren(owner,tag) return tag=="nh_escort_shield" and shields[owner] end
    function EntityAddChild(owner,child) shields[owner]={child} end
    local x,y=EntityGetTransform(id)
    local role=entities[id].cs.VariableStorageComponent
    role.value_int=0
    EntitySetTransform(1,x-20,y)
    EntitySetTransform(guard,x+3,y)
    EntitySetTransform(2,x+1,y)
    reinforcements.update(id)
    assert(shields[1] and not shields[guard] and not shields[2])
    EntitySetTransform(1,x+170,y)
    frame=frame+90
    reinforcements.update(id)
    assert(shields[guard] and not shields[2])
end

-- Friendly sentries only switch to bullets for the enemy they are engaging.
do
    local sentry=2900 -- a guard already deployed before the roster changed
    entities[sentry]=unit(0,0,9)
    entities[sentry].cs.VariableStorageComponent={value_string="robot_sentry"}
    local ai=entities[sentry].cs.AnimalAIComponent
    local marked
    function EntityGetAllChildren(id,tag)
        if id==marked and tag=="nh_sentry_mark" then return {90} end
    end
    local x,y=EntityGetTransform(sentry)
    EntitySetTransform(1,x-30,y)
    ai.mGreatestThreat=2
    marked=guard
    reinforcements.update(sentry)
    assert(ai.attack_ranged_entity_file==root.."escort_sentry_shot.xml")
    marked=2
    reinforcements.update(sentry)
    assert(ai.attack_ranged_entity_file=="data/entities/projectiles/machinegun_bullet_roboguard_big.xml")
    ai.mGreatestThreat=0
    reinforcements.update(sentry)
    assert(ai.attack_ranged_entity_file==root.."escort_sentry_shot.xml")
end

-- Ground reinforcements need a floor, even when airborne escorts can deploy.
do
    local ray=RaytracePlatforms
    function RaytracePlatforms() return false end
    local pod=dofile(root.."resupply.lua")
    assert(not pod.launch({project="missile_crab"},1))
    assert(not pod.launch({project="robot_monk"},1))
    assert(not pod.launch({project="mg_turret"},1))
    assert(not pod.launch({project="chaingun_turret"},1))
    assert(not pod.launch({project="missile_turret"},1))
    assert(not reinforcements.deploy(1,{project="mg_turret",x=400,y=5},function() error("paid without ground") end,function() end))
    assert(pod.launch({project="laser_drone"},1))
    assert(not reinforcements.deploy(1,{project="missile_crab",x=400,y=5},function() error("paid without ground") end,function() end))
    RaytracePlatforms=ray
end

-- New and already-deployed tier-three escorts both fire the reinforced volley.
do
    local id=delivered[9].id
    local ai=entities[id].cs.AnimalAIComponent
    assert(ai.attack_ranged_entity_file==root.."escort_laser_charge.xml")
    ai.attack_ranged_entity_file="data/entities/projectiles/megalaser_blue.xml"
    reinforcements.update(id)
    assert(ai.attack_ranged_entity_file==root.."escort_laser_charge.xml" and ai.attack_ranged_max_distance==240)
    local volley={}
    function dofile_once() end
    function GetUpdatedEntityID() return id end
    function GameGetVelocityCompVelocity() return 0,-1 end
    function shoot_projectile_from_projectile(owner,file,x,y,vx,vy)
        assert(owner==id and file==root.."escort_laser_beam.xml")
        assert(vx==0 and vy<0 and y==entities[id].y)
        volley[#volley+1]={offset=x-entities[id].x,speed=-vy}
    end
    function GamePlaySound() end
    dofile(root.."escort_laser_fire.lua")
    assert(#volley==7 and volley[4].speed==120)
    for i,beam in ipairs(volley) do assert(beam.offset==i-4) end
end

-- At the same distance the assassin can finish a dash while the monk regroups.
do
    local assassin,monk=delivered[10].id,delivered[11].id
    EntitySetTransform(1,0,0)
    for _,id in ipairs({assassin,monk}) do
        EntitySetTransform(id,130,0)
        entities[id].cs.AnimalAIComponent.mGreatestThreat=2
        entities[id].cs.CharacterDataComponent.mVelocity={117,-3}
        reinforcements.update(id)
    end
    assert(entities[assassin].cs.CharacterDataComponent.mVelocity[1]==117)
    assert(entities[monk].cs.CharacterDataComponent.mVelocity[1]<0)
    local script=entities[monk].cs.LuaComponent.script_shot
    assert(script==root.."escort_monk_shot.lua")
    dofile(script)
    local orb=unit(0,0,9)
    orb.cs.ProjectileComponent={}
    entities[3000]=orb
    local file="data/entities/projectiles/machinegun_bullet_slower.xml"
    function EntityGetFilename() return file end
    function EntityLoadToEntity(path,id) entities[id].orbEffect=path end
    shot(3000)
    assert(not orb.orbEffect)
    file="data/entities/projectiles/orb_green_accelerating.xml"
    shot(3000)
    assert(orb.cs.ProjectileComponent.friendly_fire==false)
    assert(orb.orbEffect==root.."escort_monk_orb_hit.xml")
end

-- An escort's mark survives the protecting robot. Restore the escort role once,
-- without inheriting the vanilla enemy faction or charging another call.
do
    local robot=delivered[12].id
    local medic=delivered[4].id
    local other=3500
    entities[other]=unit(1020,0,9)
    entities[other].tags.nh_reinforcement=true
    entities[other].cs.VariableStorageComponent={value_string="necrobot"}
    EntitySetTransform(robot,1000,0)
    EntitySetTransform(medic,1040,0)
    EntitySetTransform(2,1030,0)
    local current=robot
    function GetUpdatedEntityID() return current end
    local nativeLoad=EntityLoad
    local sparks,marker=0,nil
    function EntityLoad(path,x,y)
        if path==root.."escort_necrobot_revive.xml" then
            nextId=nextId+1; marker=nextId
            entities[marker]=unit(x,y,9)
            entities[marker].cs.VariableStorageComponent={value_string=""}
            return marker
        end
        if path=="data/entities/particles/tinyspark_green_sparse.xml" then sparks=sparks+1; return 4000 end
        if path=="data/entities/particles/poof_green_sparse.xml" then return 4001 end
        return nativeLoad(path,x,y)
    end
    function EntityAddChild(parent,child) assert(parent==medic and child==4000) end
    local aura=entities[robot].aura.script_source_file
    assert(aura==root.."escort_necrobot_aura.lua")
    dofile(aura); dofile(aura)
    assert(sparks==1 and entities[medic].tags.nh_revive_protected)
    assert(not entities[other].tags.nh_revive_protected and not entities[2].tags.nh_revive_protected)
    current=medic
    dofile(entities[medic].cs.LuaComponent.script_death)
    EntityKill(robot); death(); EntityKill(medic)
    assert(entities[marker].cs.VariableStorageComponent.value_string=="repair_drone")
    current=marker
    dofile(root.."escort_necrobot_revive.lua")
    local revived=entities[delivered[#delivered].id]
    assert(not entities[marker] and revived.x==1040 and revived.tags.nh_reinforcement and not revived.tags.enemy)
    assert(not revived.tags.homing_target,"revived escort is still a homing target")
    assert(revived.cs.VariableStorageComponent.value_string=="repair_drone" and revived.cs.GenomeDataComponent.herd_id==9)
    assert(revived.cs.LuaComponent.script_source_file==root.."reinforcement_tick.lua")
end
