local root="mods/noita_hideout/files/"
local originalDofile=dofile
NHShields=originalDofile(root.."shields.lua")
NHFirearms=originalDofile(root.."firearms.lua")
NHKatanas=originalDofile(root.."katanas.lua")
local state,liveCharge,liveEpoch,failCommit,syncCount,held
local now=50
local entities={}
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
local shieldRuntime={
    snapshot=function(draft)
        if draft.gearShield and draft.gearShield.epoch==liveEpoch then draft.gearShield.item.charge=liveCharge end
    end,
    sync=function(draft)
        syncCount=syncCount+1
        if draft.gearShield then liveCharge,liveEpoch=draft.gearShield.item.charge,draft.gearShield.epoch end
    end,
}
function dofile(path)
    if path==root.."shield_runtime.lua" then return shieldRuntime end
    return originalDofile(path)
end
local resources=dofile(root.."katana_resources.lua")
local targets=originalDofile(root.."field_targets.lua")
function dofile_once(path)
    if path==root.."katana_resources.lua" then return resources end
    if path==root.."field_targets.lua" then return targets end
    return originalDofile(path)
end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive~=false or false end
function EntityGetRootEntity(id) return id end
function EntityHasTag(id,tag) return entities[id] and entities[id].tags[tag] or false end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityGetFirstComponentIncludingDisabled(id,kind,...)
    local tag=select(1,...)
    assert(select("#",...)==0 or tag~=nil,"Noita rejects an explicitly nil component tag")
    if tag=="" then return nil end -- Explicit empty tag is not an omitted filter.
    return entities[id] and entities[id].comps[kind..(tag or "")]
end
function EntityAddComponent2(id,kind,fields)
    local c={value_int=0,value_float=0,value_string="",name=""}
    for k,v in pairs(fields) do c[k]=v end
    entities[id].comps[kind..(fields._tags or "")]=c
    return c
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function GameGetFrameNum() return now end
local hpScale=25
function MagicNumbersGetValue(key) assert(key=="GUI_HP_MULTIPLIER");return tostring(hpScale) end
function GameGetGameEffectCount(id,effect) return entities[id].effects[effect] or 0 end
function ModIsEnabled() return false end
function EntityInflictDamage() error("Resource spending must not inflict damage") end
NHNative={held=function() return held end}
local function commit(edit)
    local draft=copy(state)
    local ok,reason=edit(draft)
    if not ok then return false,reason end
    -- The real controller snapshots live shield state again inside save().
    shieldRuntime.snapshot(draft)
    if failCommit then return false,"injected failure" end
    draft.revision=draft.revision+1
    state=draft
    return true
end
local function reset(charge,kind,ammo)
    state={profile=1,runSerial=1,revision=5,
        gearShield={id=10,epoch=3,item={kind=kind or "shield_storm",charge=charge,repair=100,delay=0}},
        gearRig={id=11,item={kind="ammo_rig",reserve=ammo or 20}}}
    liveCharge,liveEpoch,failCommit,syncCount,held=charge,3,false,0,7
    entities={[1]={tags={player_unit=true},effects={},comps={DamageModelComponent={hp=5,max_hp=10}}}}
end
local halfCell=NHShields.cell/2
for _,charge in ipairs({halfCell,halfCell+1,60000,60001,210001,240000}) do
    reset(charge)
    assert(resources.spend(1,7,commit,0.5,nil))
    assert(state.gearShield.item.charge==charge-halfCell and liveCharge==charge-halfCell,
        "each activation must spend half a cell, independent of remaining charge")
    assert(state.gearShield.epoch==6 and state.gearShield.item.repair==0 and state.gearShield.item.delay==180)
    assert(entities[1].comps.DamageModelComponent.hp==5 and syncCount==1)
end
-- Balances below half a cell cannot buy a shorter field or mutate any resource.
for _,charge in ipairs({0,1,2,300,1200,halfCell-1}) do
    reset(charge)
    local ok,points=resources.spend(1,7,commit,0.5,5)
    assert(not ok and points==nil and state.revision==5 and syncCount==0)
    assert(liveCharge==charge and state.gearShield.item.charge==charge and state.gearShield.epoch==3)
    assert(state.gearShield.item.repair==100 and state.gearShield.item.delay==0)
    assert(state.gearRig.item.reserve==20 and entities[1].comps.DamageModelComponent.hp==5)
end
-- One full cell is 50 displayed points at the starting 100 maximum HP.
-- Live charge decides eligibility, while current max HP and panel scale decide
-- the value of the fixed payment. Neither capacity nor partial charge changes it.
reset(120000)
entities[1].comps.DamageModelComponent.max_hp=4
liveCharge=60000
local ok,points=resources.spend(1,7,commit,0.5)
assert(ok and points==25 and liveCharge==30000)
reset(240000)
liveCharge=halfCell-1
ok,points=resources.spend(1,7,commit,0.5)
assert(not ok and points==nil and liveCharge==halfCell-1 and syncCount==0 and state.revision==5,
    "stale full profile charge must not bypass the live half-cell threshold")
for _,case in ipairs({{charge=30001,maxHP=4,scale=25,points=25},
        {charge=210001,maxHP=8,scale=25,points=50},{charge=240000,maxHP=4,scale=50,points=50}}) do
    reset(case.charge)
    entities[1].comps.DamageModelComponent.max_hp=case.maxHP
    hpScale=case.scale
    ok,points=resources.spend(1,7,commit,0.5)
    assert(ok and points==case.points and liveCharge==case.charge-halfCell)
end
hpScale=25
-- Higher tiers grant more complete activations, rather than more expensive
-- activations. No regeneration or kill reward is needed between these spends.
for _,kind in ipairs({"shield_basic","shield_fire","shield_storm"}) do
    local casts=NHShields.types[kind].cells*2
    reset(NHShields.types[kind].cells*NHShields.cell,kind)
    entities[1].comps.DamageModelComponent.max_hp=4
    for cast=1,casts do
        ok,points=resources.spend(1,7,commit,0.5)
        assert(ok and points==25 and liveCharge==(casts-cast)*halfCell)
    end
    assert(not resources.spend(1,7,commit,0.5) and syncCount==casts and state.revision==5+casts)
end
reset(60000)
hpScale=30
ok,points=resources.spend(1,7,commit,0.5)
assert(ok and points==75 and liveCharge==30000)
hpScale=25
reset(0)
assert(not resources.spend(1,7,commit,0.5) and state.revision==5 and syncCount==0)
state.gearShield=nil
assert(not resources.spend(1,7,commit,0.5))
reset(90000)
held=8
assert(not resources.spend(1,7,commit,0.5,5) and liveCharge==90000 and state.gearRig.item.reserve==20)
held=7;failCommit=true
ok,points=resources.spend(1,7,commit,0.5,5)
assert(not ok and points==nil and state.revision==5 and liveCharge==90000 and state.gearRig.item.reserve==20 and syncCount==0)
failCommit=false
assert(resources.spend(1,7,commit,nil,5) and state.gearRig.item.reserve==15 and liveCharge==90000)
state.gearRig.item.reserve=4
assert(not resources.spend(1,7,commit,0.5,5) and liveCharge==90000 and state.gearRig.item.reserve==4)
state.gearRig=nil
assert(not resources.spend(1,7,commit,nil,5))

reset(230000,"shield_storm",238)
local amount=NHKatanas.zandatsu
assert(resources.reward(1,commit,"kills",2,amount))
assert(liveCharge==240000 and state.gearRig.item.reserve==240 and state.katanaRewardSeen==2)
assert(not resources.reward(1,commit,"kills",2,amount))
assert(not resources.reward(1,commit,"kills",1,amount))
assert(liveCharge==240000 and state.gearRig.item.reserve==240)
reset(0,"shield_basic",0)
failCommit=true
assert(not resources.reward(1,commit,"kills",1,amount))
assert(liveCharge==0 and state.gearRig.item.reserve==0 and state.katanaRewardSeen==nil)
failCommit=false
assert(resources.reward(1,commit,"kills",1,amount))
assert(liveCharge==12000 and state.gearRig.item.reserve==5)
state.gearShield,state.gearRig=nil,nil
assert(resources.reward(1,commit,"kills",2,amount) and state.katanaRewardSeen==2)

-- Real death credit and claim logic: only a matching final sword blow earns
-- one credit; a marked survivor killed by another message or owner does not.
local rewards=originalDofile(root.."katana_rewards.lua")
reset(100000,"shield_storm",20)
local credit=rewards.ensure(1,state)
entities[2]={tags={enemy=true},effects={},comps={DamageModelComponent={hp=0,max_hp=4}}}
assert(rewards.mark(2,1,"blade/a"))
rewards.death(2,"unrelated",1)
rewards.death(2,"blade/a",3)
assert(credit.value_int==0)
rewards.death(2,"blade/a",1)
rewards.death(2,"blade/a",1)
assert(credit.value_int==1)
failCommit=true
rewards.claim(state,1,commit)
assert(entities[1].comps.DamageModelComponent.hp==5 and credit.value_float==0 and liveCharge==100000)
failCommit=false
rewards.claim(state,1,commit)
assert(entities[1].comps.DamageModelComponent.hp==5.5 and liveCharge==124000 and state.gearRig.item.reserve==25)
rewards.claim(state,1,commit)
assert(entities[1].comps.DamageModelComponent.hp==5.5 and state.gearRig.item.reserve==25)
local serialized=copy(credit)
entities[1].comps.VariableStorageComponentnh_katana_credit=serialized
local reloaded=originalDofile(root.."katana_rewards.lua")
reloaded.claim(state,1,commit)
assert(entities[1].comps.DamageModelComponent.hp==5.5 and state.gearRig.item.reserve==25)

entities[1].effects.NO_HEAL=1
assert(reloaded.credit(1))
reloaded.claim(state,1,commit)
assert(entities[1].comps.DamageModelComponent.hp==5.5 and state.gearRig.item.reserve==30)
entities[1].effects.NO_HEAL=nil
reloaded.claim(state,1,commit)
assert(entities[1].comps.DamageModelComponent.hp==5.5)
entities[1].comps.DamageModelComponent.hp=9.9
assert(reloaded.credit(1))
reloaded.claim(state,1,commit)
assert(entities[1].comps.DamageModelComponent.hp==10)
entities[1].comps.DamageModelComponent.hp=0
assert(not reloaded.credit(1))
reloaded.claim(state,1,commit)
assert(entities[1].comps.DamageModelComponent.hp==0)

-- Runtime can still hold its pre-commit state table after another transaction
-- replaces the controller's state. The draft receipt, not that stale table,
-- must decide how much shield and ammo can be paid.
reset(100000,"shield_storm",20)
local stale=copy(state)
credit=rewards.ensure(1,state)
assert(rewards.credit(1))
rewards.claim(stale,1,commit)
assert(liveCharge==124000 and state.gearRig.item.reserve==25 and credit.value_float==1)
rewards.claim(stale,1,commit)
assert(liveCharge==124000 and state.gearRig.item.reserve==25 and entities[1].comps.DamageModelComponent.hp==5.5)
assert(rewards.credit(1))
rewards.claim(stale,1,commit)
assert(liveCharge==148000 and state.gearRig.item.reserve==30 and entities[1].comps.DamageModelComponent.hp==6)
assert(state.katanaRewardSeen==2 and credit.value_float==2)
state.runSerial=state.runSerial+1
rewards.claim(state,1,commit)
assert(credit.value_int==0 and credit.value_float==0 and liveCharge==148000 and state.gearRig.item.reserve==30)
dofile=originalDofile
print("Katana resources: fixed half-cell threshold, tier capacity, panel values, atomic failures, kill attribution, caps, NO_HEAL and saved cursors passed.")
