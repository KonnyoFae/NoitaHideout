local root="mods/noita_hideout/files/"
local entities,player={},1
local function entity(id,kind,owner)
    entities[id]={kind=kind,owner=owner,tags={},components={}}
    return id
end
function EntityGetRootEntity(id) return entities[id].owner or id end
function EntityHasTag(id,tag) return entities[id].tags[tag] end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityRemoveTag(id,tag) entities[id].tags[tag]=nil end
function EntityGetWithTag(tag)
    local out={}
    for id,e in pairs(entities) do if e.tags[tag] then out[#out+1]=id end end
    return out
end
function EntityAddComponent2(id,kind,c)
    c.type=kind
    table.insert(entities[id].components,c)
    return c
end
function EntityRemoveComponent(id,c)
    for i,v in ipairs(entities[id].components) do if v==c then table.remove(entities[id].components,i); return end end
    error("missing component")
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    for _,c in ipairs(entities[id].components) do
        if c.type==kind and (not tag or (","..(c._tags or "")..","):find(","..tag..",",1,true)) then return c end
    end
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function GameKillInventoryItem(p,id) assert(entities[id].owner==p); entities[id]=nil end
function EntityKill(id) entities[id]=nil end
NHTransfers={carried=function(p)
    local items={}
    for id,e in pairs(entities) do if e.owner==p then items[#items+1]=id end end
    table.sort(items)
    return items
end,available=function(_,p,id) return entities[id].owner==p end,item_kind=function(id) return entities[id].kind end}
NHEWItems={lockInfo=function(id) return entities[id].locked end}
NHStore={validBandageCount=function(n) return n and n>=1 and n==math.floor(n) and n<=2147483647 end}
NHGuns=dofile(root.."guns.lua")
NHFirearms=dofile(root.."firearms.lua")
local W=dofile(root.."rewind_loadout.lua")
local state={profile=1,runSerial=2,gearRig={id=10,epoch=1,item={kind="ammo_rig",reserve=100}}}
entity(player,"player")
EntityAddTag(player,"player_unit")
local anchor=EntityAddComponent2(player,"VariableStorageComponent",{_tags="nh_rewind_snapshot"})
local function capture(t)
    anchor.name="1/2/"..t
    assert(W.capture(state,player,anchor.name))
    EntityAddTag(player,"nh_rewind_armed")
end
local function item(id,kind,n)
    entity(id,kind,player)
    return EntityAddComponent2(id,"ItemComponent",{uses_remaining=n,mFramePickedUp=10})
end
local function gun(id,rounds)
    item(id,"marksman_rifle",1)
    EntityAddComponent2(id,"AbilityComponent",{mana_max=60,mana=rounds})
    return EntityAddComponent2(id,"VariableStorageComponent",{_tags="nh_magazine",name="marksman_rifle",value_int=rounds,value_float=1})
end
item(2,"wand",-1)
local mana=EntityAddComponent2(2,"AbilityComponent",{mana=61.25,mana_max=100})
local support=item(3,"heavy_mg",2)
local carried=item(6,"flare_gun",3)
EntityAddTag(6,"nh_pheromone_launcher")
local original=gun(4,20)
capture(100)
local new=gun(5,30)
mana.mana=2
assert(not EntityHasTag(2,"nh_rewind_equipment"))
NHGuns.consumeRound(player,6,carried,3)
NHGuns.consumeRound(player,3,support,2)
NHGuns.consumeRound(player,3,support,1)
assert(not entities[3])
-- Reload the retained gun and a gun acquired after activation. Only the
-- retained gun's debit may be reversed.
state.gearRig.item.reserve=47
W.reloaded(state,player,4,40,20)
W.reloaded(state,player,5,13,30)
original.value_int,new.value_int=51,43
-- Simulate save/continue changing an entity ID and reinitializing the VM.
entities[8],entities[4]=entities[4],nil
W=dofile(root.."rewind_loadout.lua")
local function commit(edit) return edit(state) end
assert(not W.restore(state,player,anchor.name,function() return false end))
assert(carried.uses_remaining==2 and mana.mana==2 and original.value_int==51)
assert(W.restore(state,player,anchor.name,commit))
assert(not entities[3] and carried.uses_remaining==3 and mana.mana==2)
assert(state.gearRig.item.reserve==87 and state.gearRig.rewindFrame==100 and original.value_int==20 and new.value_int==43)
assert(not EntityHasTag(6,"nh_rewind_equipment"))

support=item(3,"heavy_mg",2)
capture(200)
-- A new physical stack merged into the old gun keeps its own rounds.
support.uses_remaining=12
for n=12,7,-1 do NHGuns.consumeRound(player,3,support,n) end
assert(support.uses_remaining==6)
-- An engine throw permanently gives up this weapon's snapshot, including
-- a throw immediately followed by picking the same physical entity back up.
function GetUpdatedEntityID() return 6 end
dofile(root.."rewind_throw.lua")
throw_item()
NHGuns.consumeRound(player,6,carried,3)
mana.mana=7
W.reloaded(state,player,5,5,38)
state.gearRig.item.reserve=82
entities[5].owner=99
local exported=original.value_int
original.value_int=9
entities[8].locked=true
assert(W.restore(state,player,anchor.name,commit))
assert(support.uses_remaining==8 and mana.mana==7 and exported==20 and original.value_int==9)
assert(carried.uses_remaining==2)
assert(state.gearRig.item.reserve==82 and new.value_int==43)
entities[8].locked=nil

-- A regenerated launcher and a same-body repick without the native callback
-- are both different inventory tenures.
capture(300)
NHGuns.consumeRound(player,6,carried,2)
carried.mFramePickedUp=301
mana.mana=5
NHGuns.consumeRound(player,3,support,8)
entities[3]=nil
local replacement=item(3,"heavy_mg",7)
W.reloaded(state,player,8,20,9)
state.gearRig.item.reserve=62
state.gearRig.epoch=2
assert(W.restore(state,player,anchor.name,commit))
assert(carried.uses_remaining==1 and replacement.uses_remaining==7 and mana.mana==5 and state.gearRig.item.reserve==62)

-- A profile which already acknowledged this or a later settlement survives
-- a rewind of the game's world save without repaying reserve.
capture(400)
state.gearRig.rewindRun,state.gearRig.rewindFrame=2,550
W.reloaded(state,player,8,10,9)
state.gearRig.item.reserve=52
assert(W.restore(state,player,anchor.name,function() error("duplicate payment") end))
assert(state.gearRig.item.reserve==52)
replacement.uses_remaining=1
capture(600)
NHGuns.consumeRound(player,3,replacement,1)
W.cancel(player,anchor.name)
assert(not entities[3])

-- New gold or a consumed ammo pack can raise reserve above the starting
-- amount. An eligible reload is returned once, up to the rig's capacity.
capture(700)
W.reloaded(state,player,8,20,9)
state.gearRig.item.reserve=145
assert(W.restore(state,player,anchor.name,commit))
assert(state.gearRig.item.reserve==165)
capture(701)
W.reloaded(state,player,8,20,9)
state.gearRig.item.reserve=236
assert(W.restore(state,player,anchor.name,commit))
assert(state.gearRig.item.reserve==NHFirearms.rigs.ammo_rig.capacity)
local unmarked=item(3,"heavy_mg",1)
NHGuns.consumeRound(player,3,unmarked,1)
assert(not entities[3])

-- Another rig's loaded ammo stays in its original gun. The other rig is
-- never paid for that ammo a second time.
state.gearRig.item.reserve=45
original.value_int=10
capture(702)
state.gearRig={id=11,epoch=3,item={kind="improved_ammo_rig",reserve=80}}
W.reloaded(state,player,8,30,10)
original.value_int=34
assert(W.restore(state,player,anchor.name,commit))
assert(original.value_int==40 and state.gearRig.item.reserve==80)

-- A newly picked-up gun takes the first 10 opening reserve. A later reload
-- using 20 picked-up rounds has no claim on the now-empty opening reserve.
state.gearRig.item.reserve=10
original.value_int=5
capture(703)
local acquired=gun(11,1)
W.reloaded(state,player,11,10,1)
acquired.value_int=11
W.reloaded(state,player,8,20,5)
original.value_int=17
state.gearRig.item.reserve=0
assert(W.restore(state,player,anchor.name,commit))
assert(original.value_int==22 and acquired.value_int==11 and state.gearRig.item.reserve==0)

-- Original rounds have moved from the rig to the gun. A fresh pickup filled
-- the rig again. The unused rounds that no longer fit can stay in the gun.
state.gearRig.item.reserve=480
original.value_int=0
acquired.value_int=0
capture(704)
W.reloaded(state,player,8,40,0)
W.reloaded(state,player,11,35,0)
original.value_int,acquired.value_int=40,35
state.gearRig.item.reserve=460
assert(W.restore(state,player,anchor.name,commit))
assert(state.gearRig.item.reserve==480 and original.value_int+acquired.value_int==55)
assert(state.gearRig.rewindOverflow==55)

-- A saved owner-scoped token also cleans transferred markers while its EW
-- connection is temporarily unavailable. Keep another peer's marker intact.
NHEW={enabled=function() return true end,issuer=function() return "peerA" end}
anchor.name="1/2/peerA/704"
assert(W.capture(state,player,anchor.name))
local peer=item(12,"heavy_mg",5)
EntityAddTag(12,"nh_rewind_equipment")
EntityAddComponent2(12,"VariableStorageComponent",{_tags="nh_rewind_equipment",value_string="1/2/peerB/704|1|heavy_mg|10|5"})
NHEW.issuer=function() return nil end
W.cancel(player,anchor.name)
assert(not EntityHasTag(8,"nh_rewind_equipment") and EntityHasTag(12,"nh_rewind_equipment"))
entities[12]=nil
-- Pre-upgrade markers can exist before EW has republished its issuer.
anchor.name="1/2/42"
local legacy=item(12,"heavy_mg",0)
EntityAddTag(12,"nh_rewind_equipment")
EntityAddComponent2(12,"VariableStorageComponent",{_tags="nh_rewind_equipment",value_string="peerA/1/2/42|1|heavy_mg|10|2",value_bool=true})
function ModSettingGet(key) if key=="noita_hideout.ew_owner_1" then return "peerA" end end
W.cancel(player,anchor.name)
assert(not entities[12])
NHEW=nil

local add=EntityAddComponent2
function EntityAddComponent2(id,kind,c)
    if kind=="LuaComponent" then return 0 end
    return add(id,kind,c)
end
anchor.name="1/2/solo/705"
assert(not W.capture(state,player,anchor.name))
W.cancel(player,anchor.name)
assert(#EntityGetWithTag("nh_rewind_equipment")==0)
EntityAddComponent2=add

-- Exercise the live shield meter, transaction checkpoint and the next
-- controller sync, including the same shield after a charger changed epoch.
local frame,globals=800,{}
function GameGetFrameNum() return frame end
function GlobalsGetValue(k,d) return globals[k] or d end
function GlobalsSetValue(k,v) globals[k]=v end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetAllChildren() return {} end
function GameGetGameEffectCount() return 0 end
NHCompanions={active=function() end,immunities={apply=function() end}}
NHShields=dofile(root.."shields.lua")
local runtime=dofile(root.."shield_runtime.lua")
state.revision=40
state.gearShield={id=12,epoch=40,item={kind="shield_basic",charge=0,repair=0,delay=0}}
local shield=state.gearShield
local function save(edit)
    assert(edit(state))
    runtime.snapshot(state,player)
    state.revision=state.revision+1
    return true
end
runtime.sync(state,player)
local meter=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_equipped_shield")
local clock=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_shield_clock")
meter.value_int,meter.value_float,clock.value_int=60000,29,frame+73
capture(frame)
W.reloaded(state,player,8,5,10)
frame=820
assert(save(function(draft) return NHShields.repair(draft,"shield_charger") end))
runtime.sync(state,player)
assert(meter.value_int==120000)
W=dofile(root.."rewind_loadout.lua")
assert(not W.restore(state,player,anchor.name,function() return false end))
assert(meter.value_int==120000 and not shield.rewindFrame)
assert(W.restore(state,player,anchor.name,save))
assert(shield.item.charge==60000 and shield.item.repair==29 and shield.item.delay==73 and shield.rewindFrame==800)
runtime.sync(state,player)
assert(meter.value_int==60000 and meter.value_float==29 and clock.value_int==frame+73)
assert(not EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_rewind_shield"))

frame=900
capture(frame)
-- Simulate removing and re-equipping the same original shield in the interim.
shield.equippedAt,shield.epoch=state.revision+1,state.revision+1
shield.item.charge,shield.item.repair,shield.item.delay=45000,0,0
runtime.sync(state,player)
assert(W.restore(state,player,anchor.name,function() error("re-equipped shield was refunded") end))
assert(meter.value_int==45000 and shield.rewindFrame==800)
capture(1000)
W.cancel(player,anchor.name)
assert(not EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_rewind_shield"))
