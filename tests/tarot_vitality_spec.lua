local root="mods/noita_hideout/files/"
local V=dofile(root.."tarot_vitality.lua")
local player,remote,mob,wand,shot=1,2,3,4,5
local entities={
    [player]={tags={player_unit=true},parts={}},
    [remote]={tags={ew_client=true},parts={}},
    [mob]={tags={enemy=true},parts={}},
    [wand]={root=player,tags={},parts={}},
    [shot]={tags={},parts={}},
}
local function add(id,kind,values)
    values.kind,values.tags=kind,{}
    table.insert(entities[id].parts,values)
    return values
end
function EntityGetComponentIncludingDisabled(id,kind,tag)
    local list={}
    for _,c in ipairs(entities[id].parts) do
        if c.kind==kind and (not tag or c.tags[tag]) then list[#list+1]=c end
    end
    return list
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return EntityGetComponentIncludingDisabled(id,kind,tag)[1] end
function EntityGetComponent(id,kind) return EntityGetComponentIncludingDisabled(id,kind) end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetRootEntity(id) return entities[id].root or id end
function EntityHasTag(id,tag) return entities[id].tags[tag] end
function ComponentAddTag(c,tag) c.tags[tag]=true end
function ComponentRemoveTag(c,tag) c.tags[tag]=nil end
function ComponentHasTag(c,tag) return c.tags[tag] end
function ComponentGetValue2(c,field) return c[field] end
function ComponentSetValue2(c,field,value) c[field]=value end
ComponentGetMetaCustom,ComponentSetMetaCustom=ComponentGetValue2,ComponentSetValue2
local noHeal=false
function GameGetGameEffectCount(id,effect) assert(id==player and effect=="NO_HEAL"); return noHeal and 1 or 0 end
function GlobalsGetValue(key) assert(key=="nh_ew.status"); return "active" end
local credit
function CrossCall(key,id) assert(key=="ew_hideout_devil_kill"); credit=id end

local function near(actual,wanted) assert(math.abs(actual-wanted)<0.00001,actual.." ~= "..wanted) end
local dm=add(player,"DamageModelComponent",{max_hp=100,hp=10})
V.commit(player,"tarot_sun",nil,false); near(dm.hp,60)
V.pulse(player,"tarot_sun",nil,1); near(dm.hp,62)
V.pulse(player,"tarot_sun",nil,2); near(dm.hp,66)
V.commit(player,"tarot_sun",{},true); near(dm.hp,100)
dm.hp=106
V.pulse(player,"tarot_sun",nil,5); near(dm.hp,106)
dm.hp=100
V.pulse(player,"tarot_devil",nil,1); near(dm.hp,99)
V.pulse(player,"tarot_devil",nil,49); near(dm.hp,50)
V.pulse(player,"tarot_devil",nil,30); near(dm.hp,50)
local requests=0
function ModIsEnabled() return true end
function dofile_once() return {change=function() requests=requests+1; return true end} end
V.pulse(player,"tarot_devil",nil,1); assert(requests==0)
dm.hp=51; V.pulse(player,"tarot_devil",nil,1); assert(requests==1); near(dm.hp,51)
dm.hp=100; V.pulse(player,"tarot_sun",nil,1); assert(requests==1)
ModIsEnabled=nil
dm.hp=23
V.pulse(player,"tarot_devil",nil,1); near(dm.hp,23)
dm.max_hp=40
V.pulse(player,"tarot_devil",nil,8); near(dm.hp,20)
local function kill(id) V.rewardKill(V.killOwner(id)) end
kill(player); near(dm.hp,20) -- No card, no heal.
local clock=add(player,"VariableStorageComponent",{value_int=108000})
clock.tags.nh_tarot_devil=true
local projectile=add(shot,"ProjectileComponent",{mWhoShot=player})
for _,killer in ipairs({player,wand,shot}) do
    local old=dm.hp
    assert(V.killOwner(killer)==player); near(dm.hp,old)
    kill(killer); near(dm.hp,old+2)
end
kill(mob); kill(0); kill(123); near(dm.hp,26)
projectile.mWhoShot=remote
assert(V.killOwner(shot)==remote and not credit)
kill(shot); assert(credit==remote); near(dm.hp,26)
dm.hp=39
kill(player); near(dm.hp,40)
dm.hp=9
noHeal=true
V.commit(player,"tarot_sun"); V.pulse(player,"tarot_sun",{},1); kill(player); near(dm.hp,9)
noHeal=false
entities[player].tags.ew_notplayer=true; kill(player); near(dm.hp,9)
entities[player].tags.ew_notplayer=nil
clock.value_int=0; kill(player); near(dm.hp,9)
dm.hp=0
V.commit(player,"tarot_sun"); V.pulse(player,"tarot_devil",{},5); near(dm.hp,0)

-- A permanent kick perk before and another after the card must each survive expiry.
local vanillaIce="data/entities/misc/crack_ice.xml"
local kick=add(player,"KickComponent",{max_force=12*1.7,player_kickforce=28*1.7,
    kick_damage=2.44,kick_knockback=253,telekinesis_throw_speed=50,kick_entities=","..vanillaIce})
local tele=add(player,"TelekinesisComponent",{throw_speed=50})
V.commit(player,"tarot_devil",nil,false)
near(kick.kick_damage,14.44); near(kick.max_force,12*1.7^6); near(tele.throw_speed,175)
assert(select(2,kick.kick_entities:gsub("tarot_vitality_kick",""))==5)
V.commit(player,"tarot_devil",{},true)
near(kick.kick_damage,14.44)
kick.max_force=kick.max_force*1.7; kick.player_kickforce=kick.player_kickforce*1.7
kick.kick_damage=kick.kick_damage+2.4; kick.kick_knockback=kick.kick_knockback+250
kick.telekinesis_throw_speed=kick.telekinesis_throw_speed+25; kick.kick_entities=kick.kick_entities..","..vanillaIce
tele.throw_speed=tele.throw_speed+25
local newTele=add(player,"TelekinesisComponent",{throw_speed=kick.telekinesis_throw_speed})
dofile(root.."tarot_vitality.lua").expire(player,"tarot_devil")
near(kick.max_force,12*1.7^2); near(kick.player_kickforce,28*1.7^2)
near(kick.kick_damage,4.84); near(kick.kick_knockback,503)
near(kick.telekinesis_throw_speed,75); near(tele.throw_speed,75); near(newTele.throw_speed,75)
assert(kick.kick_entities==","..vanillaIce..","..vanillaIce)

V.commit(player,"tarot_devil",nil,false)
kick.kick_entities=""; kick.kick_damage=0.04; kick.max_force=12; kick.player_kickforce=28
kick.kick_knockback=3; kick.telekinesis_throw_speed=25; tele.throw_speed=25; newTele.throw_speed=25
V.expire(player,"tarot_devil")
near(kick.max_force,12); near(kick.kick_damage,0.04); near(tele.throw_speed,25)

-- A death on the monster authority credits the killer's owning client once and
-- only within the authenticated world and connection.
local callbacks,wire,last={},nil,nil
local rpc={opts_reliable=function() end}
local source={peer_id="A"}
local api={new_rpc_namespace=function() return rpc end,rpc_player_data=function() return source end}
util={add_cross_call=function(key,fn) callbacks[key]=fn end}
function dofile_once(path) if path==root.."tarot_vitality.lua" then return V end; return api end
local target={entity=remote,peer_id="B",dc=false}
ctx={my_id="A",my_player={entity=player},player_data_by_local_entity={[remote]=target}}
local room="game1"
local boots={A="bootA",B="bootB"}
nh_ew_session={world=function() return room end,challenge=function(id) return boots[id] end}
dofile(root.."tarot_vitality_ew.lua")
wire=rpc.credit
rpc.credit=function(...) last={...} end
callbacks.ew_hideout_devil_kill(remote)
assert(last and last[1]==room and last[3]=="B" and last[5]==1)
ctx.my_id="B"
clock.value_int=100; dm.hp=10
wire(unpack(last)); near(dm.hp,12)
wire(unpack(last)); near(dm.hp,12)
room="game2"; last[5]=2
wire(unpack(last)); near(dm.hp,12)
room="game1"; boots.B="reconnected"
wire(unpack(last)); near(dm.hp,12)
boots.B="bootB"; clock.value_int=0
wire(unpack(last)); near(dm.hp,12)
print("Sun and Devil: current maximum HP, timers, five vanilla kick stacks, ownership and remote kill credit passed.")
