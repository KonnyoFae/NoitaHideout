-- Game-shaped stubs for ownership and failure ordering across two stores.
local entities, globals, next_entity, frame, world_loaded = {}, {}, 10, 111, true
local fail, reject_restore, reject_capture, reject_stamp = false, false, false, false
local player = 1
entities[player] = {alive = true, x = 20, y = 30, inv = {mActiveItem = 0}}
local function make(kind, held)
    next_entity = next_entity + 1
    entities[next_entity] = {alive = true, root = held and player or next_entity, tags = {[kind] = true}}
    if held then entities[player].inv.mActiveItem = next_entity end
    return next_entity
end
local function pick(id)
    entities[id].root = player
    entities[player].inv.mActiveItem = id
end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive or false end
function EntityGetRootEntity(id) return entities[id].root end
local quick_id = 2
function EntityGetParent(id)
    if id == quick_id then return player end
    if entities[id] and entities[id].parent then return entities[id].parent end
    return entities[id] and entities[id].root == player and quick_id or 0
end
function EntityGetName(id) return id == quick_id and "inventory_quick" or "" end
function EntityGetAllChildren(id)
    if id == player then return {quick_id} end
    if id == quick_id then return GameGetAllInventoryItems(player) end
    return {}
end
function EntityGetFirstComponentIncludingDisabled(id, kind, tag)
    if kind == "Inventory2Component" then return entities[id].inv end
    if kind == "ItemComponent" then return entities[id].item end
    if kind == "VariableStorageComponent" then
        assert(tag == "noita_hideout_transfer_id")
        return entities[id].marker
    end
end
function EntityAddComponent2(id, kind, fields)
    assert(kind == "VariableStorageComponent")
    if reject_stamp then return nil end
    entities[id].marker = fields
    return fields
end
function ComponentGetValue2(c, k) return c[k] end
function ComponentSetValue2(c, k, value) c[k] = value end
function EntityAddTag(id, tag) entities[id].tags[tag] = true end
function EntityHasTag(id, tag) return entities[id].tags[tag] == true end
function GameGetFrameNum() frame = frame + 1 return frame end
function EntityGetTransform(id) return entities[id].x, entities[id].y end
function DoesWorldExistAt(a, b, c, d) assert(a < c and b < d) return world_loaded end
function EntityGetWithTag(tag)
    local ids = {}
    for id, obj in pairs(entities) do
        if obj.alive and obj.tags and obj.tags[tag] then table.insert(ids, id) end
    end
    return ids
end
function GameGetAllInventoryItems(p)
    local ids = {}
    for id, obj in pairs(entities) do
        if obj.alive and obj.root == p then table.insert(ids, id) end
    end
    return ids
end
function GlobalsGetValue(k, def) return globals[k] or def end
function GlobalsSetValue(k, v) globals[k] = v end
function EntityKill(id) entities[id].alive = false end
function GameKillInventoryItem(p, item)
    assert(p == player and entities[item].root == p)
    if entities[p].inv.mActiveItem == item then entities[p].inv.mActiveItem = 0 end
    EntityKill(item)
end
local function adapter(kind)
    return {
        capture = function(e)
            if reject_capture then return nil, "unsupported" end
            assert(EntityHasTag(e, kind))
            return {kind = kind, name = kind, quantity = 500}
        end,
        restore = function(item, x, y)
            assert(item.kind == kind and x == 20 and y == 26)
            if reject_restore then return nil, "not restorable" end
            return make(kind)
        end
    }
end
NHWand, NHPotion = adapter("wand"), adapter("potion")
function NHPotion.isFlask(id) return EntityHasTag(id, "potion") end
function NHPotion.discard(id, p)
    entities[id].safely_emptied = true
    if p then GameKillInventoryItem(p, id) else EntityKill(id) end
end
dofile("mods/noita_hideout/files/store.lua")
NHStore.commit = function(s)
    if fail then return nil, "rejected" end
    s.revision = s.revision + 1
    return true
end
dofile("mods/noita_hideout/files/transfers.lua")
local function state()
    return {warehouse = {}, safe = {}, pouches = {}, nextItemId = 1, runSerial = 1, revision = 0, profile = 1}
end
local s = state()
do
    local single=state()
    single.warehouse={{id=1,slot=1,item={kind="potion",name="potion",count=2}}}
    single.nextItemId=2
    assert(NHTransfers.withdraw(single,player,1,"warehouse",nil,true))
    assert(#single.warehouse==0)
    EntityKill(next_entity)
end
local e = make("potion", true)
reject_capture = true
assert(not NHTransfers.deposit(s, player) and entities[e].alive and not entities[e].marker)
reject_capture, reject_stamp = false, true
assert(not NHTransfers.deposit(s, player) and entities[e].alive and #s.warehouse == 0)
reject_stamp, fail = false, true
assert(not NHTransfers.deposit(s, player) and entities[e].alive and s.revision == 0)
fail = false
assert(NHTransfers.deposit(s, player))
assert(#s.warehouse == 1 and s.warehouse[1].item.quantity == 500)
assert(not entities[e].alive and entities[e].safely_emptied and entities[player].inv.mActiveItem == 0)
assert(not NHTransfers.deposit(s, player))

-- An old tagged world source replayed after the stored bottle is partly
-- consumed is discarded, without overwriting the updated quantity.
s.warehouse[1].item.quantity = 250
entities[e].alive = true
assert(NHTransfers.reconcile(s, player))
assert(not entities[e].alive and s.warehouse[1].item.quantity == 250)

reject_restore = true
assert(not NHTransfers.withdraw(s, player, 1) and #s.warehouse == 1)
reject_restore, reject_stamp = false, true
assert(not NHTransfers.withdraw(s, player, 1) and not entities[next_entity].alive and #s.warehouse == 1)
reject_stamp, fail = false, true
assert(not NHTransfers.withdraw(s, player, 1) and #s.warehouse == 1 and not entities[next_entity].alive)
fail = false
assert(NHTransfers.withdraw(s, player, 1))
local original_delivery = next_entity
assert(#s.warehouse == 0 and entities[original_delivery].alive)
assert(not NHTransfers.withdraw(s, player, 1))
local token = entities[original_delivery].marker.value_string
assert(s.transit.issued[token] and globals["noita_hideout.delivered." .. token] == "1")
do
    local list=GameGetAllInventoryItems
    local duplicate=make("potion")
    entities[duplicate].marker={value_string=token}
    EntityAddTag(duplicate,"noita_hideout_transfer_item")
    pick(original_delivery)
    GameGetAllInventoryItems=function() return {original_delivery,original_delivery} end
    assert(NHTransfers.reconcile(s,player))
    assert(EntityGetIsAlive(original_delivery) and not EntityGetIsAlive(duplicate))
    GameGetAllInventoryItems=list
end
-- A broken/used up delivery stays spent if its world receipt exists.
entities[original_delivery].alive = false
assert(NHTransfers.reconcile(s, player) and #s.warehouse == 0)
-- No world receipt but the entity has loaded: repair just the receipt.
globals = {}
entities[original_delivery].alive = true
assert(NHTransfers.reconcile(s, player) and #s.warehouse == 0)
assert(globals["noita_hideout.delivered." .. token] == "1")
-- Both entity and receipt rewind. A loaded terminal recovers it exactly once.
globals = {}
entities[original_delivery].alive, world_loaded = false, false
assert(NHTransfers.reconcile(s, player) and #s.warehouse == 0)
world_loaded = true
assert(NHTransfers.reconcile(s, player) and #s.warehouse == 1)
assert(NHTransfers.reconcile(s, player) and #s.warehouse == 1)
entities[original_delivery].alive = true
assert(NHTransfers.reconcile(s, player) and not entities[original_delivery].alive)

-- A new release can be carried back into the secure slot. Replaying any
-- former version of it or the original source doesn't create extra items.
assert(NHTransfers.withdraw(s, player, 1))
local next_delivery = next_entity
pick(next_delivery)
assert(NHTransfers.deposit(s, player, "safe"))
assert(#s.warehouse == 0 and #s.safe == 1 and not entities[next_delivery].alive)
entities[e].alive, entities[next_delivery].alive = true, true
assert(NHTransfers.reconcile(s, player) and not entities[e].alive and not entities[next_delivery].alive)
local wand = make("wand", true)
assert(not NHTransfers.deposit(s, player, "safe") and entities[wand].alive)
assert(NHTransfers.deposit(s, player, "warehouse") and #s.warehouse == 1 and not entities[wand].alive)
assert(NHTransfers.withdraw(s, player, 1, "safe"))
local safe_delivery = next_entity
-- New run loses an unprotected withdrawn item (even if no old receipt exists).
s.runSerial = 2
entities[safe_delivery].alive, globals = false, {}
assert(NHTransfers.reconcile(s, player) and #s.safe == 0 and #s.warehouse == 1)
print("transfer ownership, original and delivery replay, payment, secure slot and rollback tests passed")

local chosen = make("potion", true)
local other = make("wand", true)
assert(NHTransfers.deposit(s, player, "safe", chosen))
assert(not EntityGetIsAlive(chosen) and EntityGetIsAlive(other))
assert(entities[player].inv.mActiveItem == other)
assert(not NHTransfers.deposit(s, player, "warehouse", chosen))
local ground_item = make("potion", false)
assert(not NHTransfers.deposit(s, player, "warehouse", ground_item) and EntityGetIsAlive(ground_item))
local nested = make("potion", true)
entities[nested].parent = other
assert(not NHTransfers.deposit(s, player, "warehouse", nested) and EntityGetIsAlive(nested))

assert(NHStore.expandSafe(s,4))
local extra = make("wand",true)
assert(NHTransfers.deposit(s,player,"safe",extra,4))
assert(not NHTransfers.withdraw(s,player,2,"safe",function() return false end))
assert(s.safe[2].slot==4 and #s.safe==2)
assert(NHTransfers.withdraw(s,player,1,"safe"))
assert(NHStore.safeIndex(s,4)==1 and not NHStore.safeIndex(s,1))

local custom=adapter("ration")
NHTransfers.registerItem("ration",function(id) return EntityHasTag(id,"ration") end,custom)
local ration=make("ration",true)
assert(NHTransfers.deposit(s,player,"warehouse",ration,1))
local index=assert(NHStore.slotIndex(s,"warehouse",1,"ration"))
assert(NHStore.category("ration")=="supplies" and s.warehouse[index].item.quantity==500)
local gear=adapter("field_bag")
gear.warehouseCategory="equipment"
NHTransfers.registerItem("field_bag",function(id) return EntityHasTag(id,"field_bag") end,gear)
local bag=make("field_bag",true)
assert(NHTransfers.deposit(s,player,"warehouse",bag,1))
local equipment_index=assert(NHStore.slotIndex(s,"warehouse",1,"field_bag"))
assert(NHStore.category("field_bag")=="equipment" and equipment_index~=index and s.warehouse[equipment_index].item.kind=="field_bag")
assert(not NHStore.freeSlot(s,"warehouse",1,"pouch"))
local returned,gear_entity=NHTransfers.withdraw(s,player,equipment_index,"warehouse")
assert(returned and NHTransfers.item_kind(gear_entity)=="field_bag" and NHStore.freeSlot(s,"warehouse",1,"pouch")==1)
local ok,restored=NHTransfers.withdraw(s,player,index,"warehouse")
assert(ok and NHTransfers.item_kind(restored)=="ration")

function NHPotion.dockSlot(item) return item.variant=="powder_stash" and 2 or 1 end
local working=state()
local flask=make("potion",true)
assert(not NHTransfers.deposit(working,player,"docks",flask,2) and EntityGetIsAlive(flask))
assert(NHTransfers.deposit(working,player,"docks",flask,1))
assert(not NHTransfers.withdraw(working,player,1,"docks",function() return false end))
assert(#working.docks==1 and not EntityGetIsAlive(flask))
local ok,issued=NHTransfers.withdraw(working,player,1,"docks")
assert(ok and #working.docks==0)
local newer=make("potion",true)
assert(NHTransfers.deposit(working,player,"docks",newer,1))
entities[issued].alive,globals=false,{}
assert(NHTransfers.reconcile(working,player))
assert(#working.docks==1 and #working.warehouse==1 and working.docks[1].id~=working.warehouse[1].id)

local function makeCard(species,remaining)
    local id=make("noita_hideout_summon_card",false)
    entities[id].tags["nh_companion_"..species]=true
    entities[id].item={uses_remaining=remaining}
    return id
end
function EntityLoad(path,x,y)
    return makeCard(assert(path:match("/card_([%w_]+)%.xml$")),80)
end
NHCompanions.registerItems()
local cards=state()
assert(NHCompanions.grantSet(cards) and NHCompanions.grantSet(cards))
local idx=NHStore.slotIndex(cards,"warehouse",1,"summon_card")
local row=cards.warehouse[idx]
assert(row.item.count==2 and row.item.remaining==80)
fail=true
assert(not NHTransfers.withdraw(cards,player,idx) and row.item.count==2 and not EntityGetIsAlive(next_entity))
local orphan=next_entity
entities[orphan].alive=true -- Rewind to just before disposing the unpublished world object.
fail=false
assert(NHTransfers.reconcile(cards,player) and not EntityGetIsAlive(orphan))
local ok,card=NHTransfers.withdraw(cards,player,idx)
assert(ok and not cards.warehouse[idx].item.count and cards.warehouse[idx].id==row.id)
assert(NHTransfers.reconcile(cards,player) and EntityGetIsAlive(card))
pick(card)
fail=true
assert(not NHTransfers.deposit(cards,player,"warehouse",card,1) and not cards.warehouse[idx].item.count and EntityGetIsAlive(card))
fail=false
assert(NHTransfers.deposit(cards,player,"warehouse",card,1) and cards.warehouse[idx].item.count==2)
ok,card=NHTransfers.withdraw(cards,player,idx)
entities[card].alive,globals=false,{}
assert(NHTransfers.reconcile(cards,player) and cards.warehouse[idx].item.count==2)
assert(NHTransfers.reconcile(cards,player) and cards.warehouse[idx].item.count==2)
local worn=makeCard("dryad",79)
pick(worn)
assert(not NHTransfers.deposit(cards,player,"warehouse",worn,1) and EntityGetIsAlive(worn))
assert(NHTransfers.deposit(cards,player,"safe",worn,1) and cards.safe[1].item.remaining==79)
assert(not NHCompanions.moveCard(cards,"safe",1,"warehouse",1,cards.safe[1].id))
local spare=assert(NHStore.freeSlot(cards,"warehouse",nil,"summon_card"))
assert(NHCompanions.moveCard(cards,"safe",1,"warehouse",spare,cards.safe[1].id))
assert(NHCompanions.moveCard(cards,"warehouse",1,"safe",1,row.id))
assert(NHCompanions.moveCard(cards,"warehouse",1,"safe",1,row.id) and cards.safe[1].item.count==2)
assert(NHCompanions.moveCard(cards,"safe",1,"warehouse",1,cards.safe[1].id))
local destination=assert(NHStore.freeSlot(cards,"warehouse",nil,"summon_card"))
assert(NHCompanions.moveCard(cards,"warehouse",spare,"warehouse",destination,cards.warehouse[NHStore.slotIndex(cards,"warehouse",spare,"summon_card")].id))
assert(cards.warehouse[NHStore.slotIndex(cards,"warehouse",destination,"summon_card")].item.remaining==79)
print("Summon cards: single withdrawals, same-species merges, partial charges, failed writes, rewind and secure storage passed.")

dofile("mods/noita_hideout/files/products.lua")
function EntityLoad(path)
    local kind=assert(path:match("^mods/noita_hideout/files/items/([%w_]+)%.xml$"))
    local uses=NHMedkits.types[kind] and NHMedkits.types[kind].uses or 1
    local id=make("noita_hideout_"..kind,false)
    entities[id].item={uses_remaining=uses}
    return id
end
for _,kind in ipairs(NHLootBags.order) do
    local profile=state()
    -- Already-stored bags have no physics or entity fields in their record.
    profile.warehouse={{id=1,slot=1,item=NHLootBags.item(kind,2)}}
    profile.nextItemId=2
    local carried=EntityLoad("mods/noita_hideout/files/items/"..kind..".xml")
    entities[carried].item.uses_remaining=3
    pick(carried)
    assert(NHTransfers.deposit(profile,player,"warehouse",carried,1))
    assert(not EntityGetIsAlive(carried) and #profile.warehouse==1 and profile.warehouse[1].item.count==5)
    local ok,restored=NHTransfers.withdraw(profile,player,1,"warehouse")
    assert(ok and #profile.warehouse==0 and EntityHasTag(restored,"noita_hideout_"..kind))
    assert(entities[restored].item.uses_remaining==5)
    pick(restored)
    assert(NHTransfers.deposit(profile,player,"safe",restored,1))
    assert(not EntityGetIsAlive(restored) and profile.safe[1].item.kind==kind and profile.safe[1].item.count==5)
end
local bundles=state()
bundles.warehouse[1]={id=1,slot=1,item={kind="bandage",count=4}}
bundles.nextItemId=2
local ok,bundle=NHTransfers.withdraw(bundles,player,1,"warehouse")
assert(ok and #bundles.warehouse==0 and entities[bundle].item.uses_remaining==32)
pick(bundle)
entities[bundle].item.uses_remaining=7
assert(NHTransfers.deposit(bundles,player,"safe",bundle,1))
assert(#bundles.safe==1 and bundles.safe[1].item.count==1 and bundles.safe[1].item.remaining==7 and not EntityGetIsAlive(bundle))
ok,bundle=NHTransfers.withdraw(bundles,player,1,"safe")
assert(ok and #bundles.safe==0 and entities[bundle].item.uses_remaining==7)
pick(bundle)
assert(NHTransfers.deposit(bundles,player,"warehouse",bundle,1) and bundles.warehouse[1].item.remaining==7)
print("Bandages: whole bundles retain their roll count through the quickbar, secure case and warehouse.")

for _,kind in ipairs({"tactical_medkit","advanced_medkit"}) do
    local kits=state()
    local kit=NHMedkits.item(kind)
    kits.nextItemId=2
    kits.warehouse[1]={id=1,slot=1,item=kit}
    local withdrawn,entity=NHTransfers.withdraw(kits,player,1,"warehouse")
    assert(withdrawn and entities[entity].item.uses_remaining==kit.remaining)
    pick(entity)
    entities[entity].item.uses_remaining=kit.remaining-1
    assert(NHTransfers.deposit(kits,player,"safe",entity,1))
    assert(kits.safe[1].item.kind==kind and kits.safe[1].item.remaining==kit.remaining-1)
    withdrawn,entity=NHTransfers.withdraw(kits,player,1,"safe")
    assert(withdrawn and entities[entity].item.uses_remaining==kit.remaining-1)
    pick(entity)
    assert(NHTransfers.deposit(kits,player,"warehouse",entity,1))
    assert(kits.warehouse[1].item.kind==kind and kits.warehouse[1].item.remaining==kit.remaining-1)
end
print("Medical kits: both crafted tiers preserve spent charges through quickbar, secure case and warehouse.")

for _,kind in ipairs(NHThrowables.order) do
    local outfit=state()
    outfit.warehouse={{id=1,slot=1,item=NHThrowables.types[kind].bundle}}
    outfit.nextItemId=2
    local ok,entity=NHTransfers.withdraw(outfit,player,1,"warehouse")
    assert(ok and entities[entity].item.uses_remaining==8 and #outfit.warehouse==0)
    pick(entity)
    entities[entity].item.uses_remaining=3
    assert(NHTransfers.deposit(outfit,player,"safe",entity,1) and outfit.safe[1].item.count==3)
    ok,entity=NHTransfers.withdraw(outfit,player,1,"safe")
    assert(ok and #outfit.safe==0 and entities[entity].item.uses_remaining==3)
    pick(entity)
    assert(NHTransfers.deposit(outfit,player,"warehouse",entity,1))
    assert(outfit.warehouse[1].item.kind==kind and outfit.warehouse[1].item.count==3)
end
print("Throwables: all six stacks retain their quantity across quickbar, secure case and supplies storage.")

do
    local s=state()
    s.nextItemId=3
    s.warehouse={{id=1,slot=1,item={kind="bread",remaining=1,count=3}}}
    s.safe={{id=2,slot=1,item={kind="bandage",count=2}}}
    assert(not NHTransfers.moveStored(s,"warehouse",1,"safe",true))
    assert(s.warehouse[1].item.count==3 and s.nextItemId==3)
    s.safe={}
    fail=true
    assert(not NHTransfers.moveStored(s,"warehouse",1,"safe",true))
    assert(not NHTransfers.withdraw(s,player,1,"warehouse",nil,true))
    assert(#s.safe==0 and s.warehouse[1].item.remaining==1 and s.nextItemId==3)
    fail=false
    assert(NHTransfers.moveStored(s,"warehouse",1,"safe",true))
    assert(s.safe[1].id~=1 and s.safe[1].item.remaining==1 and s.safe[1].item.count==1)
    assert(s.warehouse[1].item.remaining==NHFoods.byId.bread.uses and s.warehouse[1].item.count==2)
    assert(NHTransfers.moveStored(s,"safe",1,"warehouse",false))
    assert(s.warehouse[1].item.count==3 and s.warehouse[1].item.remaining==1 and #s.safe==0)
    local ok,id=NHTransfers.withdraw(s,player,1,"warehouse",nil,true)
    assert(ok and entities[id].item.uses_remaining==1)
    entities[id].alive,globals=false,{}
    assert(NHTransfers.reconcile(s,player) and #s.warehouse==1 and s.warehouse[1].item.count==3)
    s.warehouse={{id=1,slot=1,item={kind="spell",card={id="BOMB",stack=4}}}}
    assert(NHTransfers.moveStored(s,"warehouse",1,"safe",true))
    assert(not s.safe[1].item.card.stack and s.warehouse[1].item.card.stack==3)
    s.safe={}
    s.warehouse={}
    for i=1,NHStore.warehouseCapacity(s,"supplies") do
        s.warehouse[i]={id=s.nextItemId,slot=i,item={kind="bandage",count=4}}
        s.nextItemId=s.nextItemId+1
    end
    local id=EntityLoad("mods/noita_hideout/files/items/bandage.xml")
    pick(id)
    assert(NHTransfers.deposit(s,player,"warehouse",id,nil,"safe"))
    assert(s.safe[1].item.kind=="bandage" and not EntityGetIsAlive(id))
end
print("Quick transfers preserve split stacks on full slots, rejected writes and world rewind.")

-- Deployment packs split one at a time without duplicating the source stack.
for _,kind in ipairs(NHTurrets.order) do
    local s=state()
    s.nextItemId=2
    s.warehouse={{id=1,slot=1,item={kind=kind,count=16}}}
    assert(NHTransfers.moveStored(s,"warehouse",1,"safe",true))
    assert(s.warehouse[1].item.count==15 and s.safe[1].item.count==1)
    assert(NHTransfers.moveStored(s,"safe",1,"warehouse",false))
    assert(#s.safe==0 and s.warehouse[1].item.count==16)
    local ok,id=NHTransfers.withdraw(s,player,1,"warehouse",nil,true)
    assert(ok and entities[id].item.uses_remaining==1 and s.warehouse[1].item.count==15)
    pick(id)
    assert(NHTransfers.deposit(s,player,"safe",id,1))
    assert(s.safe[1].item.count==1 and not EntityGetIsAlive(id))
    assert(NHTransfers.moveStored(s,"safe",1,"warehouse",false))
    assert(s.warehouse[1].item.count==16)
    fail=true
    assert(not NHTransfers.withdraw(s,player,1,"warehouse",nil,true))
    fail=false
    assert(s.warehouse[1].item.count==16)
    ok,id=NHTransfers.withdraw(s,player,1,"warehouse")
    assert(ok and entities[id].item.uses_remaining==16 and #s.warehouse==0)
    pick(id)
    assert(NHTransfers.deposit(s,player,"safe",id,1))
    assert(s.safe[1].item.count==16 and not EntityGetIsAlive(id))
end
print("Deployment packs retain exact quantities through safe, warehouse and single-item quick transfers.")

NHStormProducts.register()
local pickup=dofile("mods/noita_hideout/files/pickup.lua")
dofile("mods/noita_hideout/files/bag_pickup.lua")
entities[player].tags={player_unit=true}
function EntityRemoveTag(id,tag) entities[id].tags[tag]=nil end
local loadProduct=EntityLoad
function EntityLoad(path,x,y)
    local id=loadProduct(path,x,y)
    local kind=path:match("/(storm_[%w_]+)%.xml$")
    if kind then entities[id].tags={[kind]=true} end
    return id
end
local function product(kind,n)
    local id=EntityLoad("mods/noita_hideout/files/items/"..kind..".xml")
    entities[id].item.uses_remaining=n
    return id
end
for kind in pairs(NHStormProducts.types) do
    local profile=state()
    profile.nextItemId=2
    profile.warehouse={{id=1,slot=1,item={kind=kind,count=7}}}
    local source=product(kind,3)
    pick(source)
    fail=true
    assert(not NHTransfers.deposit(profile,player,"warehouse",source))
    assert(#profile.warehouse==1 and profile.warehouse[1].item.count==7 and EntityGetIsAlive(source))
    fail=false
    assert(NHTransfers.deposit(profile,player,"warehouse",source))
    assert(profile.warehouse[1].item.count==8 and profile.warehouse[2].item.count==2)
    assert(NHTransfers.moveStored(profile,"warehouse",1,"safe",true))
    assert(profile.warehouse[1].item.count==7 and profile.safe[1].item.count==1)
    local ok,id=NHTransfers.withdraw(profile,player,1,"warehouse")
    assert(ok and entities[id].item.uses_remaining==7)
    pick(id)
    local other=product(kind=="storm_mana_pure" and "storm_mana" or "storm_mana_pure",1)
    pick(other)
    source=product(kind,3)
    pick(source)
    item_pickup(source,player)
    pickup.finishPickups(profile,player)
    assert(entities[id].item.uses_remaining==8 and entities[source].item.uses_remaining==2)
    assert(entities[other].item.uses_remaining==1)
    EntityKill(other)
    local legacy=product(kind,-1)
    pick(legacy)
    item_pickup(legacy,player)
    pickup.finishPickups(profile,player)
    assert(not EntityGetIsAlive(legacy) and entities[source].item.uses_remaining==3)
    assert(NHTransfers.deposit(profile,player,"safe",source))
    assert(#profile.safe==1 and profile.safe[1].item.count==4)
    EntityKill(id)
    local invalid=product(kind,9)
    pick(invalid)
    assert(not NHTransfers.deposit(profile,player,"warehouse",invalid) and EntityGetIsAlive(invalid))
    EntityKill(invalid)
end
print("All four storm products preserve quantities, top up to eight, and keep qualities separate.")

do
    local kind="storm_mana"
    local profile=state()
    local held=product(kind,7)
    pick(held)
    local ground=product(kind,3)
    entities[ground].x,entities[ground].y=20,30
    local c=entities[ground].item
    c.is_pickable,c.next_frame_pickable,c.item_pickup_radius=true,0,16
    NHNative={kind=function() end}
    function EntityGetInRadius() return {ground} end
    EntityGetFirstComponent=EntityGetFirstComponentIncludingDisabled
    assert(not pickup.interact(profile,player,false,function() return {{lane="tool"}} end))
    assert(entities[held].item.uses_remaining==8 and EntityGetIsAlive(ground) and c.uses_remaining==2)
    pick(ground)
    profile.nextItemId=2
    profile.safe={{id=1,slot=1,item={kind=kind,count=6}}}
    local deliver=assert(pickup.stackDelivery(profile,player,profile.safe[1].item,false))
    fail=true
    assert(not NHTransfers.withdraw(profile,player,1,"safe",deliver))
    assert(profile.safe[1].item.count==6 and c.uses_remaining==2)
    fail=false
    assert(NHTransfers.withdraw(profile,player,1,"safe",deliver))
    assert(#profile.safe==0 and c.uses_remaining==8)
end
