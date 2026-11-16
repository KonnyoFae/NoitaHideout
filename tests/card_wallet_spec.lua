-- Use real store snapshots and transfer receipts while the physical item changes
-- between a quick slot, the ground, a protected slot and a rolled-back world.
local settings,flags,globals={},{},{}
local failWrite=false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) if not (failWrite and k:match("_revision$")) then settings[k]=v end end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
function GlobalsGetValue(k,default) return globals[k] or default end
function GlobalsSetValue(k,v) globals[k]=v end
local player,quick=1,2
local entities,serial={},10
function EntityLoad(path)
    serial=serial+1
    local species=path:match("items/card_([%w_]+)%.xml$")
    local tags={}
    if species:match("^wallet") then tags.noita_hideout_card_wallet=true; tags["noita_hideout_card_"..species]=true
    else tags.noita_hideout_summon_card=true; tags["nh_companion_"..species]=true end
    entities[serial]={tags=tags,item={uses_remaining=80},parent=0}
    return serial
end
function EntityGetTransform(_) return 30,45 end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetRootEntity(id) return entities[id].parent==quick and player or id end
function EntityGetName(id) return id==quick and "inventory_quick" or "" end
function EntityGetParent(id) return id==quick and player or entities[id].parent end
function GameGetAllInventoryItems()
    local list={}
    for id,e in pairs(entities) do if e.parent==quick then list[#list+1]=id end end
    return list
end
function EntityGetAllChildren(id) return id==player and {quick} or GameGetAllInventoryItems() end
function EntityGetFirstComponentIncludingDisabled(id,kind)
    if id==player or id==quick then return end
    if kind=="ItemComponent" then return entities[id].item end
    if kind=="VariableStorageComponent" then return entities[id].marker end
end
function EntityAddComponent2(id,_,data) entities[id].marker=data; return data end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function EntityHasTag(id,tag) return entities[id] and entities[id].tags[tag] end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityGetWithTag(tag)
    local list={}
    for id,e in pairs(entities) do if e.tags[tag] then list[#list+1]=id end end
    return list
end
function EntityKill(id) entities[id]=nil end
function GameKillInventoryItem(_,id) EntityKill(id) end
function GameGetFrameNum() return 1234 end
function DoesWorldExistAt() return true end
local function pick(id) entities[id].parent=quick; return true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
dofile("mods/noita_hideout/files/transfers.lua")
NHCompanions.registerItems()
NHCardWallets.registerItem()
local s=assert(NHStore.load())
local run=NHStore.newRun(s)
local function makeWallet(slot,tier)
    local id=s.nextItemId
    s.nextItemId=id+1
    s.warehouse[#s.warehouse+1]={id=id,slot=slot,item=NHCardWallets.empty(tier)}
    return {id=id,container="warehouse",slot=slot}
end
local a,b=makeWallet(1,3),makeWallet(2,1)
local function card(species,uses,count)
    return NHCompanions.withCount({species=species,remaining=uses},count or 1)
end
local function addCard(slot,species,uses,count)
    assert(NHCompanions.put(s,"warehouse",slot,nil,card(species,uses,count)))
    return {container="warehouse",slot=slot,id=s.warehouse[#s.warehouse].id}
end
local full=addCard(1,"dryad",80,130)
local worn=addCard(2,"dryad",79,1)
local fairy=addCard(3,"flower_fairy",80,1)
assert(NHStore.commit(s))
local function move(ref,src,dst) return NHCardWallets.move(s,player,ref,src,dst) end
local function cell(ref,i) return NHCardWallets.get(s,player,ref).item.cells[i] end
assert(move(a,full,{cell=1}) and move(a,full,{cell=1}))
assert(cell(a,1).count==2 and not cell(b,1))
assert(not move(a,worn,{cell=1}) and not move(a,fairy,{cell=1}))
assert(move(a,worn,{cell=3}) and cell(a,3).remaining==79)
assert(move(b,fairy,{cell=1}))
assert(not move(b,{cell=1},{cell=5}) and not move(a,full,{cell=13}))
assert(move(a,{cell=1,count=2},{cell=2}) and not move(a,{cell=1,count=2},{cell=2}))
assert(move(a,{cell=2},{cell=1}) and cell(a,1).count==2)
assert(not move(a,{cell=3},{cell=1}) and cell(a,3).remaining==79)
assert(move(a,{cell=3},{container="safe",slot=1}))
assert(s.safe[1].item.remaining==79 and not cell(a,3))
local ok,entity=NHTransfers.withdraw(s,player,NHStore.slotIndex(s,"warehouse",1,"card_wallet"),"warehouse",pick)
assert(ok and not NHCardWallets.get(s,player,a))
local hand={entity=entity,id=a.id}
assert(NHCardWallets.carried(s,player,entity).id==a.id and cell(hand,1).count==2)
assert(EntityHasTag(entity,"noita_hideout_card_wallet_3") and NHCardWallets.get(s,player,hand).item.tier==3)
assert(move(hand,{container="safe",slot=1,id=s.safe[1].id},{cell=3}))
entities[entity].parent=0
assert(not move(hand,{cell=3},{deliver=pick}))
pick(entity)
s=assert(NHStore.load())
assert(cell(hand,3).remaining==79)
failWrite=true
assert(not move(hand,{cell=3},{deliver=pick}) and cell(hand,3).remaining==79)
failWrite=false
local used,physical=move(hand,{cell=3},{deliver=pick})
assert(used and entities[physical].item.uses_remaining==79 and not cell(hand,3))
entities[physical].item.uses_remaining=78
assert(move(hand,{entity=physical},{cell=12}) and cell(hand,12).remaining==78 and not EntityGetIsAlive(physical))
-- Re-depositing a carried wallet must capture the freshly edited journal row.
assert(NHTransfers.deposit(s,player,"safe",entity,1))
local protected={id=a.id,container="safe",slot=1}
assert(not NHCardWallets.get(s,player,hand) and cell(protected,12).remaining==78)
assert(cell(b,1).species=="flower_fairy" and not cell(b,4))
-- Simultaneous world rollback of the issued wallet AND one card taken out of
-- it must recover the latest contents regardless of traversal order.
ok,entity=NHTransfers.withdraw(s,player,1,"safe",pick); assert(ok)
hand.entity=entity
used,physical=move(hand,{cell=1},{deliver=pick})
assert(used and (cell(hand,1).count or 1)==1)
globals={}
EntityKill(physical)
EntityKill(entity)
assert(NHTransfers.reconcile(s,player))
assert(cell(protected,1).count==2 and cell(protected,12).remaining==78)
assert(NHTransfers.reconcile(s,player) and cell(protected,1).count==2)
-- A carried wallet with an actual world receipt is lost with that run. The
-- protected second wallet and its independently saved cells survive.
ok,entity=NHTransfers.withdraw(s,player,1,"safe",pick); assert(ok)
assert(NHStore.endRun(s,run))
assert(not move({id=a.id,entity=entity},{cell=1},{deliver=pick}))
assert(NHStore.newRun(s)==run+1)
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(not s.transit and not s.safe[1] and cell(b,1).species=="flower_fairy")
print("Card wallets: independent contents, worn cards, failed writes, simultaneous world rewind and loss on death passed.")
