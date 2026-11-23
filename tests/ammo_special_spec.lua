local root="mods/noita_hideout/files/"
local F=dofile(root.."firearms.lua")
local A=F.mods
local saved={gearRig={item={kind="ammo_rig",reserve=11}},warehouse={{item={kind="improved_ammo_rig",reserve=32}}},
    transit={issued={{row={item={kind="advanced_ammo_rig",reserve=49}}}}}}
F.migratePoints(saved)
F.migratePoints(saved)
assert(saved.gearRig.item.reserve==110 and saved.warehouse[1].item.reserve==320 and saved.transit.issued[1].row.item.reserve==490)
actions={}
local mag={name="scatter_revolver",value_int=6}
local profile={value_string=""}
function GetUpdatedEntityID() return 1 end
function EntityGetRootEntity() return 1 end
function GameGetFrameNum() return 42 end
function EntityGetFirstComponentIncludingDisabled(_,name,tag)
    if name=="Inventory2Component" then return {mActiveItem=2} end
    return tag=="nh_magazine" and mag or profile
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
local bullets,contacts,children,plain,depth,trigger,configs
function BeginProjectile(path)
    depth=depth+1
    if depth==1 then bullets[#bullets+1]=path else assert(trigger); children[#children+1]=path end
end
function BeginTriggerHitWorld() assert(depth==1 and not trigger); trigger=true; contacts=contacts+1 end
function EndTrigger() assert(trigger and depth==1); trigger=false end
function EndProjectile() depth=depth-1; assert(depth>=0) end
function add_projectile(path) plain[#plain+1]=path end
function create_shot(n) assert(n==0); return {state={}} end
function register_action(state) assert(next(state)==nil) end
function SetProjectileConfigs() assert(trigger); configs=configs+1 end
dofile(root.."firearm_actions.lua")
local variants={}
local shotsHeard=0
local expectedSounds={pistol="projectiles/bullet_smg_enemy",magnum="player_projectiles/bullet_heavy_fast",
    scatter="projectiles/shotgun",spray="player_projectiles/flamethrower",rifle="projectiles/minigun",
    sniper="projectiles/bullet_sniper_enemy",missile="projectiles/rocket_tiny",beam="player_projectiles/megalaser"}
function EntityGetTransform(owner) assert(owner==1); return 13,17 end
function GamePlaySound(bank,event,posX,posY)
    assert(bank=="data/audio/Desktop/projectiles.bank" and event==expectedSounds.scatter.."/create" and posX==13 and posY==17)
    shotsHeard=shotsHeard+1
end
function ModTextFileSetContent(path,xml) assert(not variants[path]); variants[path]=xml end
F.modes.register(A)
local function fire(kind,index,impact,flight,points)
    shotsHeard=0
    bullets,children,plain,contacts,depth,trigger,configs={},{},{},0,0,false,0
    c={speed_multiplier=1,spread_degrees=0,extra_entities="",game_effect_entities=""}
    mag.name,mag.value_float,mag.value_int,mag.value_bool,mag.value_string=kind,index,points,false,"-1"
    profile.name=A.profile(impact,flight)
    actions[kind=="marksman_rifle" and 2 or 1].action()
    assert(depth==0 and not trigger)
end
for kind,list in pairs(F.modes.guns) do for index,mode in ipairs(list) do
    for _,core in ipairs({false,"frost","shock","blast","plasma","toxin","fire"}) do
        for _,trajectory in ipairs({false,"speed","cursor","homing","pierce"}) do
            fire(kind,index,core,trajectory,mode.cost)
            assert(mag.value_int==0 and (core and contacts or #plain)==(mode.pellets or 1))
            local path=F.modes.path(mode,core,trajectory)
            assert((core and bullets[1] or plain[1])==path)
            local xml=assert(variants[path])
            if mode.id=="scatter" then
                assert(shotsHeard==1 and not xml:find("<AudioComponent",1,true))
            else
                assert(shotsHeard==0 and xml:find('event_root="'..expectedSounds[mode.id]..'"',1,true))
            end
            local loss=(core and 1 or 0)+(trajectory and 1 or 0)
            local direct=tonumber(xml:match('<ProjectileComponent.-damage="([%d%.]+)"'))
            assert(math.abs(direct*25-math.max(0,mode.damage-loss))<0.001)
            if core then assert(configs==contacts and children[1]==root.."projectiles/ammo_"..core..".xml") end
            if trajectory=="speed" then assert(c.speed_multiplier==1.5) end
            if mode.blast then assert(math.abs(tonumber(xml:match('<config_explosion.-damage="([%d%.]+)"'))*25-(mode.blast-(mode.id=="missile" and loss or 0)))<0.001) end
            if mode.id=="missile" then assert(xml:find(trajectory=="homing" and 'detect_distance="210"' or 'detect_distance="120"',1,true)) end
            if mode.id=="spray" and core=="frost" then assert(not xml:find('emitted_material_name="fire"',1,true)) end
            fire(kind,index,core,trajectory,mode.cost-1)
            assert(mag.value_int==mode.cost-1 and #plain==0 and contacts==0 and shotsHeard==0)
        end
    end
end end
reflecting=true
fire("scatter_revolver",1,false,false,1)
assert(mag.value_int==1 and #plain==1)
reflecting=false
local old={warehouse={{item={kind="marksman_rifle",rounds=5,configured="frost/pierce"}}}}
F.migrateMagazines(old); F.migrateMagazines(old)
assert(old.warehouse[1].item.rounds==30 and old.warehouse[1].item.mode==1 and old.warehouse[1].item.configured=="frost/pierce")
local runtime=dofile(root.."ammo_runtime.lua")
local frame=10
local reloadSounds=0
function EntityGetTransform(entity) assert(entity==1); return 12,34 end
function GamePlaySound(bank,event,posX,posY)
    assert(bank=="data/audio/Desktop/animals.bank" and event=="animals/shotgun_cock" and posX==12 and posY==34)
    reloadSounds=reloadSounds+1
end
function GameGetFrameNum() return frame end
function EntityHasTag() return true end
NHFirearms=F
NHNative={held=function() return 2 end}
local ability={mana=5}
function EntityGetFirstComponentIncludingDisabled(_,kind,tag)
    if kind=="AbilityComponent" then return ability end
    if tag=="nh_magazine" then return mag end
end
local state={gearRig={id=1,item={kind="ammo_rig",reserve=10}}}
local function update(input,fail)
    input=input or {}; input.enabled=true
    return runtime.update(state,1,function(edit) if fail then return false end; return edit(state) end,input)
end
local aimX,aimY=0,0
function GameGetIsGamepadConnected() return false end
function DEBUG_GetMouseWorld() return aimX,aimY end
function GameGetCameraBounds() return -100,-60,200,120 end
mag.name,mag.value_float,mag.value_int="marksman_rifle",3,5
assert(update().loading==72 and reloadSounds==1)
assert(update({reload=true}).loading==72 and reloadSounds==1)
update({pressed=true,down=true}); frame=frame+1
assert(update().index==4 and not mag.value_bool and mag.value_int==5)
assert(update({reload=true}).loading==72 and mag.value_bool and reloadSounds==2)
frame=frame+72; update(nil,true)
assert(state.gearRig.item.reserve==10 and mag.value_int==5)
update({reload=true}); frame=frame+72; update()
assert(state.gearRig.item.reserve==0 and mag.value_int==15 and ability.mana==15)
update({reload=true}); assert(reloadSounds==3)
for _,point in ipairs({{0,-50,1},{50,0,2},{0,50,3},{-50,0,4},{0,0,4}}) do
    aimX,aimY=point[1],point[2]
    update({pressed=true,down=true}); frame=frame+15
    assert(update({down=true}).menu and mag.value_bool)
    frame=frame+1; assert(update().index==point[3] and not mag.value_bool)
end
mag.name,mag.value_float,mag.value_int="scatter_revolver",1,36
state.gearRig.item.reserve=10
update({reload=true}); assert(reloadSounds==3)
mag.value_int=35
assert(update({reload=true}).loading==54 and reloadSounds==4)
frame=frame+54; update(); assert(mag.value_int==36 and reloadSounds==4)
print("Eight modes: 280 loadouts, projectile damage, payloads, costs, empty fire, selection, partial reload, rollback and migration passed.")
