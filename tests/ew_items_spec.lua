-- Two personal journals, a shared GID and physically separate Noita entities.
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/transfers.lua")
dofile("mods/noita_hideout/files/ew_items.lua")
local entities,globals,winners={},{},{}
local issuer,online,fail="Host",true,false
local frame=70
local player,quick=1,2
local i=10
NHEW={
    enabled=function() return true end,ready=function() return online end,
    issuer=function() return issuer end,localBody=function(p) return p==player end,
}
local function same(a,b)
    if type(a)~="table" or type(b)~="table" then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local pending,seq,access=nil,0,true
NHEWDeposit={same=same,canAccess=function() return access end,reconcileItem=function() return false end}
function NHEWDeposit.begin(s,p,e,source,intent,record)
    local keys,err=NHEWItems.claimKeys(e,source)
    if not keys then return nil,err end
    if #keys==0 then return false end
    assert(not pending);seq=seq+1
    pending={s=s,p=p,e=e,keys=keys,intent=intent,record=record,tx="world|"..issuer.."|"..seq}
    return true,"Item deposit queued."
end
local function deliver()
    local job=assert(pending);pending=nil
    for _,k in ipairs(job.keys) do if winners[k] and winners[k]~=issuer then return nil,"denied" end end
    local ok,reason=NHTransfers.resumeEW(job.s,job.p,job.e,job.intent,job.record,job.tx)
    if ok then
        for _,k in ipairs(job.keys) do winners[k]=issuer end
        assert(job.s.ewDepositReceipt==job.tx)
    end
    return ok,reason
end
local function spawn(held,gid,token,kind)
    i=i+1
    local e={held=held,alive=true,kind=kind or "wand",tags={},item={},
        gid=gid and {name="ew_gid_lid",value_string=gid,value_bool=false}}
    if token then
        e.mark={value_string=token,name="noita_hideout_transfer_id",_tags="noita_hideout_transfer_id"}
        e.tags.noita_hideout_transfer_item=true
    end
    entities[i]=e
    return i
end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive end
function EntityGetParent(id)
    if id==quick then return player end
    return entities[id] and entities[id].held and quick or 0
end
function EntityGetName(id) return id==quick and "inventory_quick" or "" end
function EntityGetRootEntity(id) return entities[id].held and player or id end
function EntityGetAllChildren(id) return id==player and {quick} or GameGetAllInventoryItems(player) end
function EntityHasTag(id,tag)
    if id==player then return tag=="player_unit" end
    return entities[id] and (entities[id].tags[tag] or entities[id].kind==tag) or false
end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    local e=entities[id]
    if not e then return end
    if kind=="VariableStorageComponent" then return e.mark and e.mark._tags==tag and e.mark or nil end
    if kind=="ItemComponent" then return e.item end
    if kind=="ItemActionComponent" and e.kind=="spell" then return e end
end
function EntityGetComponentIncludingDisabled(id,kind,tag)
    local e,result=entities[id],{}
    if e and kind=="VariableStorageComponent" then
        if e.gid and not tag then result[#result+1]=e.gid end
        if e.mark and (not tag or e.mark._tags==tag) then result[#result+1]=e.mark end
    end
    return result
end
function EntityAddComponent2(id,kind,data) entities[id].mark=data; return data end
function ComponentSetValue2(c,key,v) c[key]=v end
function ComponentGetValue2(c,key) if key=="inventory_slot" then return 0,0 end;return c[key] end
function ComponentGetTags(c) return c._tags end
function GameGetFrameNum() return frame end
function EntityGetTransform() return 0,0 end
function EntityAddChild(parent,id) assert(parent==quick);entities[id].held=true end
function EntitySetComponentsWithTagEnabled() end
function GameGetAllInventoryItems()
    local result={}
    for id,e in pairs(entities) do if e.alive and e.held then result[#result+1]=id end end
    return result
end
function EntityGetWithTag() error("personal reconciliation must never enumerate all peers' items") end
function GameKillInventoryItem(p,id) assert(entities[id].held); entities[id].alive=false end
function EntityKill(id) entities[id].alive=false end
function GlobalsSetValue(k,v) globals[k]=v end
function GlobalsGetValue(k,d) return globals[k] or d end
NHWand={capture=function(id) return entities[id].wand or {kind="wand",name=entities[id].name or "test"} end,
    restore=function() return spawn(false) end}
NHSpell={capture=function() return {kind="spell",id="LIGHT_BULLET"} end}
NHPotion={isFlask=function(id) return entities[id].kind=="potion" end,
    capture=function(id) return {kind="potion",variant=entities[id].variant,materials={water=entities[id].water or 300}} end,
    dockSlot=function(record) return record.kind=="potion" and 1 end,
    discard=function(e,p) return GameKillInventoryItem(p,e) end}
NHStore.commit=function(s)
    if fail then return nil,"write failed" end
    s.revision=s.revision+1
    return true
end
local function state()
    return {warehouse={},safe={},docks={},pouches={},runSerial=1,profile=1,revision=0,nextItemId=1}
end
local host,guest=state(),state()
local gid="18446744073709551604"
local item=spawn(false,gid)
assert(not NHTransfers.pickupToSafe(host,player,item) and entities[item].alive)
entities[item].held=true
entities[item].tags.ew_des=true
assert(not NHTransfers.deposit(host,player,"warehouse",item) and not next(winners))
entities[item].tags.ew_des=nil
online=false
assert(not NHTransfers.deposit(host,player,"warehouse",item))
online=true
assert(NHTransfers.deposit(host,player,"warehouse",item) and entities[item].alive and not entities[item].mark)
fail=true
assert(not deliver() and entities[item].alive and #host.warehouse==0 and not host.ewDepositReceipt)
fail=false
assert(NHTransfers.deposit(host,player,"warehouse",item))
entities[item].name="changed"; assert(not deliver() and entities[item].alive and #host.warehouse==0)
assert(NHTransfers.deposit(host,player,"warehouse",item))
access=false;assert(not deliver() and entities[item].alive);access=true
assert(NHTransfers.deposit(host,player,"warehouse",item))
host.warehouse[1]={slot=1,id=700,item={kind="wand"}}
assert(not deliver() and entities[item].alive);host.warehouse[1]=nil
assert(NHTransfers.deposit(host,player,"warehouse",item))
local successful=pending;assert(deliver() and not entities[item].alive)
assert(NHTransfers.resumeEW(host,player,item,successful.intent,successful.record,successful.tx) and #host.warehouse==1)
local clone=spawn(true,gid)
assert(not NHTransfers.deposit(host,player,"warehouse",clone) and entities[clone].alive and #host.warehouse==1)
issuer="Guest"
assert(NHTransfers.deposit(guest,player,"safe",clone) and not deliver() and #guest.safe==0 and entities[clone].alive)
issuer="Host"
assert(not NHTransfers.withdraw(host,player,1) and #host.warehouse==1)
assert(not NHTransfers.withdraw(host,player,1,"warehouse",function() return true end) and #host.warehouse==1)
local ok,out=NHTransfers.withdraw(host,player,1,"warehouse",function(id) entities[id].held=true; return true end)
assert(ok and #host.warehouse==0)
do
    local profile=state()
    local token="ew/Host/r/1/1/52/42/105/31"
    profile.transit={run=1,issued={},retired={},delivered={[token]="wand"}}
    local wrong=spawn(true,"822",token,"potion")
    assert(not NHTransfers.deposit(profile,player,"safe",wrong) and entities[wrong].alive)
    local wand=spawn(true,"823",token)
    assert(NHTransfers.deposit(profile,player,"safe",wand) and deliver() and #profile.safe==1)
    assert(profile.transit.retired[token] and not profile.transit.delivered[token] and not entities[wand].alive)
end
local release=entities[out].mark.value_string
assert(release:match("^ew/Host/r/") and host.transit.issued[release])
entities[out].held=false
issuer="Guest"
assert(NHTransfers.reconcile(guest,player) and entities[out].alive)
local received=spawn(true,"123",release)
assert(NHTransfers.deposit(guest,player,"safe",received) and deliver() and #guest.safe==1 and not entities[received].alive)
assert(winners["t/"..release]=="Guest")
issuer="Host"
local replay=spawn(true,"456",release)
assert(NHTransfers.deposit(host,player,"warehouse",replay) and not deliver() and entities[replay].alive)
globals={}
assert(NHTransfers.reconcile(host,player) and #host.warehouse==0)
local legacy=spawn(true,nil,"r/1/1/1/1/70/10")
assert(not NHTransfers.deposit(host,player,"warehouse",legacy) and entities[legacy].alive)
local damaged=spawn(true,"corrupted")
assert(not NHTransfers.deposit(host,player,"warehouse",damaged) and entities[damaged].alive)
local reserved=spawn(true,"999","ew/Guest/g/123")
assert(NHTransfers.deposit(host,player,"warehouse",reserved) and not deliver() and entities[reserved].alive)
assert(not winners["g/999"] and not winners["g/456"])
for _,kind in ipairs({"card_wallet","relic_chain"}) do
    NHTransfers.registerItem(kind,function(id) return entities[id].kind==kind end,{
        capture=function() error("foreign contents live only in the issuing journal") end,
        restore=function() error("unreachable") end,
    })
    local foreign=spawn(true,nil,"ew/Guest/r/1/1/9/8/115/10",kind)
    assert(not NHTransfers.deposit(host,player,"warehouse",foreign) and entities[foreign].alive)
end
-- No-key personal items keep the normal synchronous entry; keyed items use
-- the same exact destination after the authorization round trip.
local instant=spawn(true,nil)
assert(NHTransfers.deposit(host,player,"warehouse",instant) and not entities[instant].alive and not pending)
local flask=spawn(true,"200",nil,"potion")
assert(NHTransfers.deposit(host,player,"docks",flask,1));entities[flask].water=299
assert(not deliver() and #host.docks==0 and entities[flask].alive)
assert(NHTransfers.deposit(host,player,"docks",flask,1) and deliver())
assert(host.docks[1].item.materials.water==299 and not entities[flask].alive)
do
    -- An escrow saved by 0.42.41 still contains the native NPC assessment.
    local profile=state()
    local item=spawn(true,"205",nil,"potion")
    local function legacyFlask(knowledge)
        assert(NHTransfers.deposit(profile,player,"docks",item,1))
        pending.record.aiKnowledge=knowledge
        return pending.record
    end
    legacyFlask({is_consumed=true,never_use=true})
    assert(not deliver() and entities[item].alive and not profile.docks[1])
    entities[item].variant="powder_stash"
    legacyFlask({is_consumed=true})
    assert(not deliver() and entities[item].alive and not profile.docks[1])
    entities[item].variant=nil
    legacyFlask({is_consumed=true})
    entities[item].water=275
    assert(not deliver() and entities[item].alive and not profile.docks[1])
    local original=legacyFlask({is_consumed=true,enabled=false})
    assert(deliver() and original.aiKnowledge.enabled==false and not entities[item].alive)
    assert(not profile.docks[1].item.aiKnowledge and profile.docks[1].item.materials.water==275)
end
host.safeCapacity=8
local spell=spawn(true,"201",nil,"spell")
assert(NHTransfers.deposit(host,player,"safe",spell,2) and deliver() and host.safe[1].item.id=="LIGHT_BULLET")
local function register(kind,record)
    NHTransfers.registerItem(kind,function(id) return entities[id].kind==kind end,{
        capture=function() local c={};for k,v in pairs(record) do c[k]=v end;return c end,
        restore=function(rec) local e=spawn(false,nil,nil,kind);entities[e].count=rec.count;return e end})
end
register("relic",{kind="relic",relic="brimstone"})
local chain={container="safe",slot=3,id=70}
host.safe[#host.safe+1]={id=70,slot=3,item=NHRelics.empty()}
local stone=spawn(true,"210",nil,"relic")
assert(NHTransfers.deposit(host,player,"safe",stone,1,nil,chain))
host.safe[#host.safe].id=71;assert(not deliver() and entities[stone].alive)
host.safe[#host.safe].id=70;assert(NHTransfers.deposit(host,player,"safe",stone,1,nil,chain) and deliver())
assert(NHRelics.chain(host,chain).item.cells[1].item.relic=="brimstone")
register("summon_card",{kind="summon_card",species="dryad",remaining=70})
local wallet={container="warehouse",slot=4,id=72}
host.warehouse[#host.warehouse+1]={id=72,slot=4,item=NHCardWallets.empty(1)}
local card=spawn(true,"211",nil,"summon_card")
assert(NHTransfers.depositWalletCard(host,player,wallet,card,2) and deliver())
assert(NHCardWallets.get(host,player,wallet).item.cells[2].remaining==70)
-- Once one unit was equipped, rolling the world back to the full original
-- must give the precise remainder back in hand without adding gear twice.
local supply=NHShields.charger
register(supply,{kind=supply,count=4,remaining=3})
local pack=spawn(true,"212",nil,supply)
assert(NHTransfers.deposit(host,player,"gear",pack,2))
local gearTx=pending.tx;assert(deliver())
assert(host.gearCharger.item.count==1 and host.gearCharger.item.remaining==3)
local tail,issued
for token,release in pairs(host.transit.issued) do if release.splitDeposit==gearTx then tail=token;issued=release end end
assert(tail and issued.row.item.count==3)
for _,id in ipairs(GameGetAllInventoryItems(player)) do
    if entities[id].mark and entities[id].mark.value_string==tail then entities[id].alive=false end
end
globals={}
local old=spawn(true,"212",nil,supply);assert(NHTransfers.cleanupEWDeposit(host,player,old,gearTx))
local twin=spawn(true,"212",nil,supply);assert(NHTransfers.cleanupEWDeposit(host,player,twin,gearTx))
local remainders=0
for _,id in ipairs(GameGetAllInventoryItems(player)) do
    if entities[id].mark and entities[id].mark.value_string==tail then remainders=remainders+1;assert(entities[id].count==3) end
end
assert(remainders==1 and host.gearCharger.item.count==1)
-- Injector uses and pouch contents are owned by their issuing journal. The
-- host arbitrates only their DES identity and never reconstructs another
-- profile's personal token or redirects an order to a moved pouch.
dofile("mods/noita_hideout/files/doses.lua")
NHNative={kind=function(id) return entities[id] and entities[id].kind end}
host.closedThrough=0;host.issuedDoses={}
local pouchId=84
local pouchToken="ew/Host/1/1/54/70/21"
host.pouches[pouchId]={id=pouchId,tier=1,slot=7,location="bag",token=pouchToken,cells={},doses=0}
local pouch=spawn(true,"214",nil,"pouch")
entities[pouch].mark={_tags="noita_hideout_pouch_token",value_string=pouchToken}
local doseToken="ew/Host/1/1/55/70/22"
host.issuedDoses[doseToken]={remaining=5,subtype="fire"}
local dose=spawn(true,"213",nil,"dose")
entities[dose].mark={_tags="noita_hideout_dose_token",value_string=doseToken}
assert(NHDoses.deposit(host,player,dose,nil,nil,nil,pouchId) and pending.intent.cell==1 and pending.intent.dest=="bag")
host.issuedDoses[doseToken].remaining=3
assert(not deliver() and entities[dose].alive and host.pouches[pouchId].doses==0)
assert(NHDoses.deposit(host,player,dose,nil,1,nil,pouchId))
host.pouches[pouchId].location="safe";assert(not deliver() and host.issuedDoses[doseToken])
host.pouches[pouchId].location="bag"
assert(NHDoses.deposit(host,player,dose,nil,1,nil,pouchId) and deliver())
assert(host.pouches[pouchId].cells[1].remaining==3 and not host.issuedDoses[doseToken] and not entities[dose].alive)
assert(NHDoses.storePouch(host,player,pouch,6,"safe") and pending.intent.pouchId==pouchId and deliver())
assert(not entities[pouch].alive and host.pouches[pouchId].slot==6 and host.pouches[pouchId].cells[1].remaining==3)
local wandState=state()
local wand=spawn(true,"300",nil,"wand")
local function snapshot(mana,wait,card,rate)
    return {kind="wand",template="data/entities/items/wand_level_01.xml",ability={mana=mana,mana_max=120,mana_charge_speed=rate or 30,mReloadFramesLeft=wait,
        stat_times_player_has_shot=5},cards={{id=card or "LIGHT_BULLET"}},cast_wait=wait,reload_wait=wait}
end
local function chargeGate(before,after)
    entities[wand].wand=before
    assert(NHTransfers.deposit(wandState,player,"warehouse",wand))
    frame=frame+30; entities[wand].wand=after
    return deliver()
end
assert(not chargeGate(snapshot(40,20),snapshot(39,0)) and entities[wand].alive)
assert(not chargeGate(snapshot(40,20),snapshot(100,0)) and entities[wand].alive)
assert(not chargeGate(snapshot(40,20),snapshot(50,22)) and entities[wand].alive)
assert(not chargeGate(snapshot(40,20),snapshot(50,0,"BOMB")) and entities[wand].alive)
assert(not chargeGate(snapshot(40,20,nil,-30),snapshot(39,0,nil,-30)) and entities[wand].alive)
local legacyWand=snapshot(40,20)
legacyWand.aiKnowledge={is_ranged_weapon=true,is_weapon=true}
assert(not chargeGate(legacyWand,snapshot(55,0,"BOMB")) and entities[wand].alive)
assert(chargeGate(legacyWand,snapshot(55,0)) and legacyWand.aiKnowledge.is_weapon)
assert(wandState.warehouse[1].item.ability.mana==55 and wandState.warehouse[1].item.cast_wait==0
    and wandState.warehouse[1].item.ability.mReloadFramesLeft==0 and not wandState.warehouse[1].item.aiKnowledge)
-- A previously opened container popup holds an entity reference. Moving
-- that same entity into the escrow must revoke access to its personal row.
local openWallet=spawn(true,nil,"ew/Host/r/1/1/90/90/70/3","card_wallet")
entities[openWallet].tags.noita_hideout_card_wallet=true
host.transit.issued[entities[openWallet].mark.value_string]={row={id=90,item=NHCardWallets.empty(1)}}
local walletRef={entity=openWallet,id=90}
local openPouch=spawn(true,nil,nil,"pouch")
local pouchKey="ew/Host/1/1/91/70/4"
entities[openPouch].mark={_tags="noita_hideout_pouch_token",value_string=pouchKey}
host.pouches[91]={id=91,location="bag",token=pouchKey,cells={},tier=1,doses=0}
local oldParent,oldName,box=EntityGetParent,EntityGetName,9100
local stashed=false
function EntityGetParent(id)
    if id==box then return player end
    if stashed and (id==openWallet or id==openPouch) then return box end
    return oldParent(id)
end
function EntityGetName(id) return id==box and "nh_ew_deposit_escrow" or oldName(id) end
assert(NHCardWallets.get(host,player,walletRef) and NHDoses.isPouch(host,openPouch)==91)
stashed=true
assert(EntityGetRootEntity(openWallet)==player and EntityGetRootEntity(openPouch)==player)
assert(not NHCardWallets.get(host,player,walletRef) and not NHDoses.isPouch(host,openPouch))
stashed=false
assert(NHCardWallets.get(host,player,walletRef) and NHDoses.isPouch(host,openPouch)==91)
-- Late world rollback after close: neither this directly equipped perk nor
-- the full-inventory spell appears in the engine's normal inventory list.
dofile("mods/noita_hideout/files/ew_deposit.lua")
local latePerk=spawn(true,"500",nil,"perk");entities[latePerk].tags.noita_hideout_perk_card=true
local fullSpell=spawn(true,"501",nil,"spell")
local foreignSpell=spawn(true,"501",nil,"spell")
local full=4000
local parent=EntityGetParent
function EntityGetParent(id)
    if id==latePerk or id==full then return player end
    if id==fullSpell then return full end
    return parent(id)
end
function GameGetAllInventoryItems(p) assert(p==player);return {} end
function EntityGetAllChildren(id)
    if id==player then return {quick,full,latePerk} end
    if id==full then return {fullSpell} end
    return {}
end
function EntityGetName(id) return id==quick and "inventory_quick" or id==full and "inventory_full" or "" end
local cancelled,stored="world|Host|150","world|Host|151"
host.ewActive="world"
NHEW.world=function() return "world" end
host.ewDepositHistory={[cancelled]="cancelled",[stored]="g/501",["g/501"]=stored}
local lock={_tags=NHEWItems.lockTag,name=NHEWItems.lockTag,value_string=cancelled,value_bool=false}
entities[latePerk].mark=lock;entities[latePerk].item.permanently_attached=true
function EntityRemoveComponent(id,c) assert(entities[id].mark==c);entities[id].mark=nil end
assert(NHTransfers.reconcile(host,player))
assert(entities[latePerk].alive and not entities[latePerk].mark and not entities[latePerk].item.permanently_attached)
assert(not entities[fullSpell].alive and entities[foreignSpell].alive)
-- A holder with no personal deposit history must also scan inventory_full.
-- Change the entity's ticket between asking for proof and consuming it.
local returned=spawn(true,"555",release,"potion")
local transferred=spawn(true,"556",release,"wand")
local oldFullChildren=EntityGetAllChildren
function EntityGetAllChildren(id)
    if id==full then return {returned,transferred} end
    return oldFullChildren(id)
end
local oldFullParent=EntityGetParent
function EntityGetParent(id)
    if id==returned or id==transferred then return full end
    return oldFullParent(id)
end
host.ewDepositHistory,host.ewDepositPending=nil,nil
local queries=0
NHEW.releaseWinner=function(w,h,k)
    assert(w==host.ewActive and h=="Host" and k=="t/"..release)
    queries=queries+1
    if queries==2 then entities[transferred].mark.value_string=release.."9" end
    return "Guest","151"
end
assert(NHTransfers.reconcile(host,player) and queries==2)
assert(not entities[returned].alive and entities[transferred].alive)
print("EW ground veto, host claims, two-player handoff, rollback, legacy receipts and personal delivery passed.")
