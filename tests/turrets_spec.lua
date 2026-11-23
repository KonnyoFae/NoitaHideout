local root="mods/noita_hideout/files/"
local settings,flags={},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile(root.."store.lua")
local state=assert(NHStore.load())
NHStore.newRun(state)
state.levels.grenade=1
for _,kind in ipairs(NHTurrets.order) do
    local d=NHTurrets.types[kind]
    state.resources={arcane_scrap=1}
    state.bankGold=199
    if d.essence then state.resources[d.essence]=1 end
    assert(not NHStore.startOrder(state,kind))
    state.bankGold=200
    if d.essence then
        state.resources[d.essence]=0
        assert(not NHStore.startOrder(state,kind))
        state.resources[d.essence]=1
    end
    assert(NHStore.startOrder(state,kind))
    assert(state.bankGold==0 and not next(state.resources))
    assert(state.order.output.item.count==4)
    assert(NHStore.advanceProduction(state,{run=state.runSerial,orderId=state.order.id,progress=state.order.required}))
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    local row=state.warehouse[#state.warehouse]
    assert(row.item.kind==kind and row.item.count==4)
    assert(not NHStore.stackSlot(state,"warehouse",{kind=kind,count=1}))
    row.item.count=2
    assert(NHStore.stackSlot(state,"warehouse",{kind=kind,count=2}))
    NHStore.mergeStack(row.item,{kind=kind,count=2})
    assert(row.item.count==4)
end

local entities,nextId,selected={},10,nil
entities[1]={x=0,y=0,GenomeDataComponent={{herd_id=7}}}
local failed,omitted,loaded,ground,blocked,overlap=nil,nil,nil,true,false,false
local function comp(id,k,tag)
    for _,c in ipairs(entities[id][k] or {}) do if not tag or c._tags==tag then return c end end
end
function EntityGetFirstComponentIncludingDisabled(id,k,tag) return comp(id,k,tag) end
function EntityGetComponentIncludingDisabled(id,k) return entities[id][k] end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetRootEntity(id) return 1 end
function EntityHasTag(id,tag) return entities[id].tag==tag end
function EntityRemoveComponent(id,c)
    for _,list in pairs(entities[id]) do if type(list)=="table" then
        for i,v in ipairs(list) do if v==c then table.remove(list,i); return end end
    end end
end
function EntityAddComponent2(id,k,c)
    entities[id][k]=entities[id][k] or {}
    table.insert(entities[id][k],c)
    return c
end
function EntityKill(id) entities[id]=nil end
function GameKillInventoryItem(player,id) assert(player==1); EntityKill(id) end
function GameIsInventoryOpen() return false end
function RaytracePlatforms(x,y,tx,ty)
    if ty-y==48 then return ground,x,20 end
    return blocked
end
function EntityGetInRadiusWithTag() return overlap and {100} or {} end
function EntityLoad(path,x,y)
    if failed then return 0 end
    nextId=nextId+1
    local kind=path:match("/items/([%w_]+)%.xml$")
    local e={x=x,y=y,path=path}
    if kind then e.tag="noita_hideout_"..kind; e.ItemComponent={{uses_remaining=1}}
    else
        e.GenomeDataComponent={{herd_id=9}}
        e.DamageModelComponent={{hp=4,max_hp=4}}
        e.VariableStorageComponent={{_tags="nh_decoy_anchor"}}
        e.LuaComponent={{_tags="nh_bag_drop",script_death=root.."enemy_loot.lua"}}
    end
    if omitted then e[omitted]=nil end
    entities[nextId]=e
    loaded=nextId
    return nextId
end
local adapters={}
NHNative={held=function() return selected end}
NHTransfers={registerItem=function(k,match,a) adapters[k]=a end}
dofile(root.."products.lua")
NHProducts.aim=function() return 1,0 end
local runtime=dofile(root.."turret_runtime.lua")
for _,kind in ipairs(NHTurrets.order) do
    local a=adapters[kind]
    selected=assert(a.restore({kind=kind,count=4},0,0))
    assert(a.capture(selected).count==4)
    ground=false
    local view=assert(runtime.heldPreview(1))
    assert(not view.valid and view.kind==kind and view.x==28)
    assert(not NHProducts.fireHeld(1) and a.capture(selected).count==4)
    ground=true; blocked=true
    assert(not runtime.heldPreview(1).valid)
    assert(not NHProducts.fireHeld(1) and a.capture(selected).count==4)
    blocked=false; overlap=true
    assert(not runtime.heldPreview(1).valid)
    assert(not NHProducts.fireHeld(1) and a.capture(selected).count==4)
    overlap=false; failed=true
    assert(not NHProducts.fireHeld(1) and a.capture(selected).count==4)
    failed=false; omitted="VariableStorageComponent"
    assert(not NHProducts.fireHeld(1) and a.capture(selected).count==4 and not entities[loaded])
    omitted=nil
    assert(not runtime.deploy(1,kind,function() return false end) and not entities[loaded])
    local preview=runtime.heldPreview(1)
    assert(preview.valid)
    assert(NHProducts.fireHeld(1) and a.capture(selected).count==3)
    local tower=entities[loaded]
    assert(tower.x==preview.x and tower.y==preview.y)
    assert(tower.GenomeDataComponent[1].herd_id==7)
    local anchor=comp(loaded,"VariableStorageComponent","nh_decoy_anchor")
    assert(anchor.value_int==preview.x and anchor.value_float==preview.y)
    for i=1,3 do assert(NHProducts.fireHeld(1)) end
    assert(not EntityGetIsAlive(selected))
end

-- Pickup delivery only accepts a matching stack with space.
dofile(root.."products.lua")
selected=assert(adapters.turret_pack.restore({kind="turret_pack",count=2},0,0))
local source=assert(adapters.rocket_turret_pack.restore({kind="rocket_turret_pack",count=1},0,0))
NHTransfers.carried=function() return {source,selected} end
NHTransfers.available=function() return true end
local pickup=dofile(root.."pickup.lua")
local target,total=pickup.stackTarget(state,1,"turret_pack",2,source)
assert(target and total==4)
assert(not pickup.stackTarget(state,1,"turret_pack",3,source))
assert(not pickup.stackTarget(state,1,"shield_turret_pack",1,source))

-- Shot ownership and homing are refreshed from the live player after loading.
entities[80]={ProjectileComponent={{}},HomingComponent={{}}}
entities[81]={AnimalAIComponent={{mGreatestThreat=82}}}
entities[82]={}
function EntityGetWithTag() return {1} end
function GetUpdatedEntityID() return 81 end
function EntityGetHerdRelation() return 0 end
function GameGetGameEffectCount() return 0 end
dofile(root.."turrets_shot.lua")
shot(80)
assert(comp(80,"ProjectileComponent").mWhoShot==1 and comp(80,"ProjectileComponent").mShooterHerdId==7)
assert(comp(80,"HomingComponent").predefined_target==82)
function EntityGetHerdRelation() return 100 end
shot(80)
assert(not comp(80,"HomingComponent"))

-- The reinforcement's first native round starts one burst. Subsequent shots follow the moving gun.
local frame,shots=100,{}
local attack={attack_ranged_root_offset_x=0,attack_ranged_root_offset_y=-3,attack_ranged_offset_x=12,
    attack_ranged_entity_file=root.."turrets/mg_round.xml",mRangedAttackCurrentAimAngle=0}
entities[80].tag="nh_mg_round"
entities[81]={tag="nh_mg_turret",x=10,y=20,AIAttackComponent={attack},
    VariableStorageComponent={{_tags="nh_reinforcement_role",value_int=0},{_tags="nh_turret_ammo",value_int=3000,value_float=3000}}}
EntityGetFirstComponent=EntityGetFirstComponentIncludingDisabled
function GetUpdatedComponentID() return comp(81,"LuaComponent","nh_mg_burst_tick") end
function GameGetFrameNum() return frame end
function EntityLoad(path,x,y)
    assert(path==root.."turrets/mg_round.xml")
    local id=90+#shots
    entities[id]={x=x,y=y,ProjectileComponent={{speed_min=500}},VelocityComponent={{}}}
    return id
end
function GameShootProjectile(id,x,y,tx,ty,round,sendMessage)
    assert(id==81 and sendMessage==false)
    table.insert(shots,{frame=frame,x=x,y=y,id=round})
end
function GameEntityPlaySound(id,sound) assert(id==81 and sound=="shoot_bullet") end
shot(80)
local timer=assert(GetUpdatedComponentID())
local tick=assert(loadfile(timer.script_source_file))
for f=101,116 do
    frame=f
    if f==106 then shot(80); assert(#entities[81].LuaComponent==1) end
    if f==110 then attack.mRangedAttackCurrentAimAngle=math.pi/2 end
    tick()
end
assert(#shots==4 and not GetUpdatedComponentID())
for i,s in ipairs(shots) do
    assert(s.frame==100+i*4)
    assert(math.abs(s.x-(i<=2 and 22 or 10))<0.001 and s.y==(i<=2 and 17 or 29))
    local projectile=comp(s.id,"ProjectileComponent")
    assert(projectile.mWhoShot==1 and projectile.mShooterHerdId==7)
end
assert(comp(81,"VariableStorageComponent","nh_turret_ammo").value_int==2994)
frame=200
shot(80)
frame=300
tick()
assert(#shots==4 and not GetUpdatedComponentID())
print("turret recipes, deployment, shot ownership and reinforcement burst cadence passed")

-- Two rounds left permits one native round and exactly one follow-up.
local remaining=comp(81,"VariableStorageComponent","nh_turret_ammo")
remaining.value_int=2
function EntitySetComponentIsEnabled(id,c,enabled) c.disabled=not enabled end
function EntityGetFirstComponent(id,name)
    local c=comp(id,name)
    if c and not c.disabled then return c end
end
frame=350
shot(80)
for f=351,366 do frame=f;tick() end
assert(remaining.value_int==0 and attack.disabled and #shots==5)
