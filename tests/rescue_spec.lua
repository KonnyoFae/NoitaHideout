local root="mods/noita_hideout/files/"
dofile(root.."store.lua")
local R=dofile(root.."rescue.lua")
local world,entities,sequence={}, {},0
function GlobalsGetValue(k,default) return world[k] or default end
function GlobalsSetValue(k,v) world[k]=v end
local function spawn(name,x,y)
    sequence=sequence+1
    entities[sequence]={name=name,x=x or 0,y=y or 0,tags={},components={}}
    return sequence
end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityCreateNew(name) return spawn(name) end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityHasTag(id,tag) return entities[id].tags[tag] end
function ComponentObjectGetValue2(c,group,key) return c[group][key] end
function ComponentObjectSetValue2(c,group,key,value) c[group][key]=value end
function EntityGetAllChildren(parent,tag)
    local result={}
    for id,v in pairs(entities) do if v.parent==parent and (not tag or v.tags[tag]) then result[#result+1]=id end end
    return result
end
function EntityAddChild(parent,id) entities[id].parent=parent end
function EntityRemoveFromParent(id) entities[id].parent=nil end
function EntityKill(id) entities[id]=nil end
function EntityGetTransform(id) local e=entities[id]; return e.x,e.y end
function EntitySetTransform(id,x,y) entities[id].x,entities[id].y=x,y end
function EntityAddComponent2(id,kind,fields)
    fields.key=kind..(fields._tags or "")
    entities[id].components[fields.key]=fields
    return fields
end
function EntityRemoveComponent(id,c) entities[id].components[c.key]=nil end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return entities[id].components[kind..(tag or "")] end
function EntityGetComponentIncludingDisabled(id,kind)
    local list={}
    for key,c in pairs(entities[id].components) do if key:sub(1,#kind)==kind then list[#list+1]=c end end
    return list
end
function ComponentHasTag(c,tag) return c.tags and c.tags[tag] or false end
function ComponentAddTag(c,tag) c.tags=c.tags or {}; c.tags[tag]=true end
function ComponentRemoveTag(c,tag) c.tags[tag]=nil end
function ComponentGetIsEnabled(c) return not c.disabled end
function EntitySetComponentIsEnabled(_,c,enabled) c.disabled=not enabled end
function ComponentGetValue2(c,key) return c[key] end
function ComponentSetValue2(c,key,v) c[key]=v end
local updated,crate,bag,failDrop
function GetUpdatedEntityID() return updated end
function EntityLoad(file,x,y)
    if file:find("lost_gold") and failDrop then return 0 end
    local id=spawn(file,x,y)
    if file:find("lost_gold") then
        EntityAddComponent2(id,"VariableStorageComponent",{_tags="nh_lost_gold",value_string=""})
        if file:find("_case") then
            EntityAddComponent2(id,"DamageModelComponent",{hp=0.2}); crate=id
        else bag=id end
    end
    return id
end
local player=spawn("player",500,60)
local health=EntityAddComponent2(player,"DamageModelComponent",{hp=4,max_hp=4,damage_multipliers={curse=0.6}})
local wallet=EntityAddComponent2(player,"WalletComponent",{money=300,mHasReachedInf=false})
local s={profile=1,runSerial=1,insuranceActive=true,insuranceSerial=1,affinity={cat=NHAffinity.framesPerPoint*123}}
NHAffinity.bind(s)
local function commit(edit) return edit(s) end
local pet=spawn("cat")
entities[pet].tags.noita_hideout_companion=true
EntityAddChild(player,pet)
EntityAddComponent2(pet,"VariableStorageComponent",{_tags="nh_companion_clock",value_string="cat",value_int=40})
NHCompanions.immunities.apply(player,"cat")
assert(health.damage_multipliers.curse==0)
R.arm(s,player)
local view=R.view(s,player)
assert(view.insured and view.species=="cat" and view.kept==123 and view.limit==123)
wallet.money=17
assert(R.view(s,player).kept==17)
wallet.money=300
assert(health.wait_for_kill_flag_on_death)
health.hp=-2
R.intercept(player,health)
assert(health.hp==2 and not EntityGetIsAlive(pet) and health.damage_multipliers.curse==0.6)
failDrop=true
assert(not R.settle(s,player,10,20,commit) and wallet.money==123)
failDrop=false
local source,keep,lost=R.settle(s,player,10,20,commit)
assert(source=="cat" and keep==123 and lost==177 and s.insuranceActive)
assert(R.view(s,player).insured and not R.view(s,player).species and R.view(s,player).kept==0)
assert(wallet.money==123 and entities[player].x==10 and entities[player].y==20)
assert(entities[crate].x==500 and entities[crate].y==60)
assert(not R.settle(s,player,10,20,commit))
updated=crate
dofile(root.."lost_gold_case.lua")
assert(not bag)
entities[crate].components.DamageModelComponent.hp=0
dofile(root.."lost_gold_case.lua")
assert(not entities[crate] and entities[bag])
dofile(root.."lost_gold_pickup.lua")
item_pickup(bag,player)
assert(wallet.money==300 and not entities[bag])
R.arm(s,player)
health.hp=0
R.intercept(player,health)
assert(not R.settle(s,player,10,20,function() return false end) and s.insuranceActive and wallet.money==0 and not entities[crate])
source,keep,lost=R.settle(s,player,10,20,commit)
assert(source=="policy" and not s.insuranceActive and keep==0 and lost==300 and wallet.money==0)
R.arm(s,player)
health.hp=-1
R.intercept(player,health)
assert(health.hp==-1 and not health.wait_for_kill_flag_on_death)
assert(not R.view(s,player).insured and R.view(s,player).limit==0)
-- A transformed body must resolve the same policy at the original hit position.
health.hp=4
s.insuranceActive,s.insuranceSerial=true,2
wallet.money=27
local body=spawn("sheep",150,-30)
local sheepHP=EntityAddComponent2(body,"DamageModelComponent",{hp=1,max_hp=1})
local effect={frames=100}
function GameGetGameEffect(id,kind) return id==body and kind=="POLYMORPH" and effect or 0 end
R.polymorph(s,body)
assert(sheepHP.wait_for_kill_flag_on_death and effect.frames==100)
sheepHP.hp=0
R.polymorph(s,body)
assert(sheepHP.hp>0 and effect.frames==1)
R.arm(s,player)
assert(wallet.money==0)
wallet.money=11 -- A later pickup is not part of the escrowed loss.
source,keep,lost=R.settle(s,player,10,20,commit)
assert(source=="policy" and lost==27 and wallet.money==11 and entities[crate].x==150 and entities[crate].y==-30)

local cat=spawn("cat")
entities[cat].tags.noita_hideout_companion=true
EntityAddChild(player,cat)
EntityAddComponent2(cat,"VariableStorageComponent",{_tags="nh_companion_clock",value_string="cat",value_int=30})
function EntityGetWithTag(tag) return tag=="player_unit" and {player} or {} end
s.affinity.cat=NHAffinity.framesPerPoint*10000
s.companionIncomeSeed=101
local awards={}
NHCompanions.income(s,"farm",100,awards)
assert(#awards==0 and s.companionIncomeSeed==101)
NHCompanions.income(s,"cat_house",100,awards)
assert(#awards>0 and #awards==s.summons.pending.cat)
for _,id in ipairs(awards) do assert(id=="cat") end
EntityKill(cat)
local seed=s.companionIncomeSeed
NHCompanions.income(s,"cat_house",20,awards)
assert(seed==s.companionIncomeSeed)
print("Rescue prioritizes the companion, intercepts lethal HP, retries policy and crate settlement, and recovers exact gold.")

-- Reserve both native and garden lives while rescue is available, across reload.
do
    local p=spawn("priority_player")
    EntityAddComponent2(p,"DamageModelComponent",{hp=4,max_hp=4})
    EntityAddComponent2(p,"WalletComponent",{money=0})
    local function life(spent,disabled)
        local e=spawn("life")
        EntityAddChild(p,e)
        return EntityAddComponent2(e,"GameEffectComponent",{effect="RESPAWN",frames=-1,mIsSpent=spent,disabled=disabled})
    end
    local native,garden,spent,external=life(false,false),life(false,false),life(true,false),life(false,true)
    local state={profile=90,runSerial=1,insuranceActive=true,insuranceSerial=1}
    R.arm(state,p)
    assert(native.disabled and garden.disabled and not spent.disabled and external.disabled)
    assert(not native.mIsSpent and not garden.mIsSpent)
    assert(not ComponentHasTag(external,"nh_rescue_paused_life"))
    R=dofile(root.."rescue.lua")
    R.arm(state,p)
    state.insuranceActive=false
    R.arm(state,p)
    assert(not native.disabled and not garden.disabled and not spent.disabled and external.disabled)
    assert(not ComponentHasTag(native,"nh_rescue_paused_life"))
    state.insuranceActive=true
    R.arm(state,p)
    -- A life granted after arming is covered by the pre-damage pass.
    local fresh=life(false,false)
    R.lifePriority(p)
    assert(fresh.disabled and not fresh.mIsSpent)
    local dm=EntityGetFirstComponentIncludingDisabled(p,"DamageModelComponent")
    dm.hp=-1
    R.intercept(p,dm)
    assert(dm.hp==2 and not native.mIsSpent)
    assert(R.settle(state,p,0,0,function(edit) return edit(state) end)=="policy")
    R.arm(state,p)
    assert(not native.disabled and not garden.disabled and not fresh.disabled)
end
print("Rescue priority suspends unspent lives, survives reload and restores them after policy use without touching external disables.")

-- Continue a 0.42.19 save after the fatal hit but before the controller settled
-- its policy. The player may have moved since the wallet was captured.
do
    local p=spawn("traveler",12,64)
    EntityAddComponent2(p,"DamageModelComponent",{hp=2,max_hp=4,wait_for_kill_flag_on_death=true})
    local wallet=EntityAddComponent2(p,"WalletComponent",{money=7})
    EntityAddComponent2(p,"VariableStorageComponent",{_tags="nh_rescue",name="nh_travel.",
        value_string="policy:-52800:1420:0:41:0",value_int=1,value_bool=true})
    local policy={profile=91,runSerial=1,insuranceActive=true,insuranceSerial=1}
    local function settle(edit) return edit(policy) end
    local trips=0
    local function dispatch(who,x,y)
        assert(who==p and x==10 and y==20)
        trips=trips+1
    end
    R=dofile(root.."rescue.lua")
    R.arm(policy,p)
    local source,keep,lost=R.settle(policy,p,10,20,settle,dispatch)
    assert(source=="policy" and keep==0 and lost==41 and not policy.insuranceActive)
    assert(wallet.money==7 and entities[crate].x==-52800 and entities[crate].y==1420)
    local paidCrate=crate
    R=dofile(root.."rescue.lua")
    R.arm(policy,p)
    assert(not R.settle(policy,p,10,20,settle,dispatch) and crate==paidCrate and trips==1)
end

-- Entering EW must not replay a private transfer against the team wallet,
-- steal its death flag, or discard a policy / rescue that predates this build.
do
    dofile(root.."bank.lua")
    local ew=NHEW
    local soloRescue,soloWallet=ew.rescueAllowed,ew.walletAllowed
    local p=spawn("insured",44,78)
    local dm=EntityAddComponent2(p,"DamageModelComponent",{hp=4,max_hp=4})
    local w=EntityAddComponent2(p,"WalletComponent",{money=75,mHasReachedInf=false})
    local life=EntityAddComponent2(p,"GameEffectComponent",{effect="RESPAWN",mIsSpent=false})
    local policy={profile=111,runSerial=1,insuranceActive=true,insuranceSerial=1,
        resources={arcane_scrap=100},bankGold=200,bankWalletNet=-25}
    R.arm(policy,p)
    local rec=assert(EntityGetFirstComponentIncludingDisabled(p,"VariableStorageComponent","nh_rescue"))
    assert(rec.value_bool and dm.wait_for_kill_flag_on_death and life.disabled)
    local receipt="noita_hideout.bank_wallet.111/1"
    world[receipt]="0/-25/75"
    ew.rescueAllowed=function() return false end
    ew.walletAllowed=function() return false end
    local pet=spawn("cat")
    entities[pet].tags.noita_hideout_companion=true
    EntityAddChild(p,pet)
    EntityAddComponent2(pet,"VariableStorageComponent",{_tags="nh_companion_clock",value_string="cat"})
    dm.hp=-1
    R.arm(policy,p)
    R.lifePriority(p)
    R.intercept(p,dm)
    assert(not life.disabled and dm.wait_for_kill_flag_on_death and not dm.kill_now and dm.hp==-1)
    assert(not EntityGetFirstComponentIncludingDisabled(p,"VariableStorageComponent","nh_rescue"))
    assert(policy.insuranceActive and EntityGetIsAlive(pet) and w.money==75)
    local stashed=policy.resources.arcane_scrap
    policy.insuranceActive=false
    assert(not NHStore.buyGood(policy,{id="rescue_policy"}) and policy.resources.arcane_scrap==stashed)
    policy.insuranceActive=true
    assert(not NHBank.prepare(policy,p,{direction="deposit",amount=20}))
    assert(not NHBank.prepare(policy,p,{direction="withdraw",amount=20}))
    assert(not NHBank.reconcile(policy,p))
    assert(policy.bankGold==200 and policy.bankWalletNet==-25 and w.money==75 and world[receipt]=="0/-25/75")
    assert(NHStore.spendGold(policy,8) and NHStore.creditGold(policy,8))

    local poly=spawn("sheep")
    local polyHP=EntityAddComponent2(poly,"DamageModelComponent",{hp=0,max_hp=1,wait_for_kill_flag_on_death=true})
    ComponentAddTag(polyHP,"nh_rescue_poly_wait")
    R.polymorph(policy,poly)
    assert(polyHP.hp==0 and polyHP.wait_for_kill_flag_on_death and not polyHP.kill_now)
    assert(not ComponentHasTag(polyHP,"nh_rescue_poly_wait") and not world["nh_rescue.111.1.return"])

    local oldCrate=assert(EntityLoad(root.."items/lost_gold_case.xml",12,13))
    local value=EntityGetFirstComponentIncludingDisabled(oldCrate,"VariableStorageComponent","nh_lost_gold")
    value.value_string="19"
    entities[oldCrate].components.DamageModelComponent.hp=0
    updated=oldCrate
    dofile(root.."lost_gold_case.lua")
    assert(EntityGetIsAlive(oldCrate) and value.value_string=="19")
    local nugget=EntityLoad(root.."items/lost_gold.xml",14,15)
    local gold=EntityGetFirstComponentIncludingDisabled(nugget,"VariableStorageComponent","nh_lost_gold")
    gold.value_string,gold.value_bool="11",true
    dofile(root.."lost_gold_pickup.lua")
    item_pickup(nugget,p)
    assert(EntityGetIsAlive(nugget) and gold.value_string=="11" and w.money==75 and not w.mHasReachedInf)

    -- This legacy player already lost gold before joining. Keep the record
    -- and consume it only once if they return to the same private run.
    local escrow=EntityAddComponent2(p,"VariableStorageComponent",{_tags="nh_rescue",value_bool=true,
        value_string="policy:44:78:0:31:0",value_int=1})
    R=dofile(root.."rescue.lua")
    R.arm(policy,p)
    assert(not escrow.value_bool and not R.settle(policy,p,0,0,function() error("unexpected charge") end))
    assert(escrow.value_string=="policy:44:78:0:31:0" and w.money==75 and policy.insuranceActive)
    ew.walletAllowed=soloWallet
    assert(NHBank.reconcile(policy,p) and w.money==50 and world[receipt]=="-25")
    assert(NHBank.reconcile(policy,p) and w.money==50)
    assert(NHBank.prepare(policy,p,{direction="withdraw",amount=10})==10 and NHBank.reconcile(policy,p))
    assert(w.money==60 and policy.bankGold==190 and world[receipt]=="-15")
    assert(not R.settle(policy,p,0,0,function() error("EW still handles death") end))
    ew.rescueAllowed=soloRescue
    local recovered,_,owed=R.settle(policy,p,0,0,function(edit) return edit(policy) end)
    assert(recovered=="policy" and owed==31 and not policy.insuranceActive and w.money==60)
    assert(not R.settle(policy,p,0,0,function() error("duplicate settlement") end))
end
print("EW preserves death ownership, extra lives, policies, lost gold, private shop gold and bank receipts.")
