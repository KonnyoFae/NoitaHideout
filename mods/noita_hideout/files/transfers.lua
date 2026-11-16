-- The profile and world are saved by separate Noita systems. Each physical
-- item gets a token before ownership changes. A world-side receipt survives
-- normal use/destruction of a delivered item, so it cannot be reclaimed.
NHTransfers = {}
local tag = "noita_hideout_transfer_item"
local marker_tag = "noita_hideout_transfer_id"

local function copy(t)
    local result = {}
    for key, value in pairs(t or {}) do result[key] = value end
    return result
end

local function journal(s)
    local j = s.transit
    if j and j.run == s.runSerial then return j end
    return {run = s.runSerial, retired = {}, issued = {}}
end

local function draft(s)
    local next_state, j = copy(s), journal(s)
    next_state.warehouse, next_state.safe = copy(s.warehouse), copy(s.safe)
    next_state.docks = copy(s.docks)
    next_state.transit = {run = s.runSerial, retired = copy(j.retired), issued = copy(j.issued)}
    return next_state
end

local function commit(s, changed)
    local ok, err = NHStore.commit(changed)
    if not ok then return nil, err end
    s.revision, s.nextItemId = changed.revision, changed.nextItemId
    s.docks = changed.docks
    s.summons, s.dragonLoot = changed.summons, changed.dragonLoot
    s.gelBonus,s.resources=changed.gelBonus,changed.resources
    s.warehouse, s.safe, s.transit = changed.warehouse, changed.safe, changed.transit
    return true
end

local function container_name(value)
    if value == nil or value == "warehouse" then return "warehouse" end
    if value == "safe" or value=="docks" then return value end
end

local function marker(entity)
    local c = EntityGetFirstComponentIncludingDisabled(entity, "VariableStorageComponent", marker_tag)
    if c then return ComponentGetValue2(c, "value_string") end
end

local function stamp(entity, token)
    local c = EntityGetFirstComponentIncludingDisabled(entity, "VariableStorageComponent", marker_tag)
    if c then
        ComponentSetValue2(c, "value_string", token)
    else
        c = EntityAddComponent2(entity, "VariableStorageComponent", {
            _tags = marker_tag, name = marker_tag, value_string = token
        })
    end
    if not c or marker(entity) ~= token then return nil end
    EntityAddTag(entity, tag)
    return EntityHasTag(entity, tag)
end

local function new_token(prefix, s, ticket, item_id, entity)
    -- Frame/entity distinguish provisional marks from a previous rejected
    -- commit that didn't consume an item number in the permanent profile.
    return table.concat({prefix, s.profile, s.runSerial, ticket, item_id, GameGetFrameNum(), entity}, "/")
end

local function receipt(token)
    return "noita_hideout.delivered." .. token
end

local function storage_ids(s)
    local ids, sources = {}, {}
    for _, rows in ipairs({s.warehouse, s.safe, s.docks}) do
        for _, row in ipairs(rows) do
            ids[row.id] = true
            if row.origin then sources[row.origin] = true end
        end
    end
    return ids, sources
end

local function stored_release(s, token, ids)
    local profile, item_id = token:match("^r/(%d+)/%d+/%d+/(%d+)/")
    return tonumber(profile) == s.profile and ids[tonumber(item_id)]
end

local function unpublished_release(s,j,token)
    -- A split card has its own ID. Its original stack stays in storage and
    -- cannot identify a world object staged before a failed pointer write.
    local profile,run=token:match("^r/(%d+)/(%d+)/")
    return tonumber(profile)==s.profile and tonumber(run)==s.runSerial and not j.issued[token]
end

local customItems = {}
local customOrder = {}
-- Register before gameplay. A codec snapshots a live item and rebuilds it
-- from the saved record; the transfer journal owns commit and disposal.
-- Set adapter.warehouseCategory="equipment" for wearable gear and mod containers.
function NHTransfers.registerItem(kind, matches, adapter)
    assert(type(kind)=="string" and type(matches)=="function" and type(adapter)=="table" and type(adapter.capture)=="function"
        and type(adapter.restore)=="function","Invalid item adapter")
    assert(not customItems[kind] and kind~="wand" and kind~="spell" and kind~="potion"
        and kind~="pouch" and kind~="dose" and kind~="other","Duplicate or reserved item kind")
    if adapter.warehouseCategory then
        assert(adapter.warehouseCategory=="equipment" or adapter.warehouseCategory=="supplies"
            or adapter.warehouseCategory=="collection","Invalid warehouse category")
        NHStore.itemCategories[kind]=adapter.warehouseCategory
    end
    customItems[kind]={matches=matches,adapter=adapter}
    customOrder[#customOrder+1]=kind
end

function NHTransfers.item_kind(entity)
    for _,kind in ipairs(customOrder) do if customItems[kind].matches(entity) then return kind end end
    if EntityHasTag(entity, "wand") then return "wand" end
    if EntityGetFirstComponentIncludingDisabled(entity,"ItemActionComponent") then return "spell" end
    if NHPotion.isFlask(entity) then return "potion" end
    local ability = EntityGetFirstComponentIncludingDisabled(entity, "AbilityComponent")
    if ability and ComponentGetValue2(ability, "use_gun_script") then return "wand" end
end

local function dispose(entity, player)
    local owner
    if player and player ~= 0 and EntityGetRootEntity(entity) == player then owner = player end
    local kind=NHTransfers.item_kind(entity)
    if kind == "potion" then
        NHPotion.discard(entity, owner)
    elseif kind=="perk" and owner and EntityGetParent(entity)==owner then
        -- Equipped cards sit outside the engine's inventories. Detach the
        -- effect immediately on commit or when rolling back a delivery.
        EntityRemoveFromParent(entity)
        EntityKill(entity)
    elseif owner then
        GameKillInventoryItem(owner, entity)
    else
        EntityKill(entity)
    end
end

local function codec(kind)
    if customItems[kind] then return customItems[kind].adapter end
    if kind == "spell" then return NHSpell end
    if kind == "wand" then return NHWand end
    if kind == "potion" then return NHPotion end
end

-- An engine-listed item may be attached directly to the player or under
-- a renamed inventory node. Check the live hierarchy as the engine list and
-- active slot can still contain the previous item during a drop.
local function top_level_equipment(player, entity)
    if not EntityGetFirstComponentIncludingDisabled(entity, "ItemComponent") then return false end
    local parent = EntityGetParent(entity)
    while parent and parent ~= 0 and parent ~= player do
        if EntityGetName(parent) == "inventory_full"
            or EntityGetFirstComponentIncludingDisabled(parent, "ItemComponent") then return false end
        parent = EntityGetParent(parent)
    end
    return parent == player
end

function NHTransfers.carried(player)
    local items, seen = {}, {}
    local function add(id, quick)
        if not id or id == 0 or seen[id] or not EntityGetIsAlive(id) then return end
        if quick then
            if EntityGetParent(id) ~= quick then return end
        elseif not top_level_equipment(player, id) then return end
        seen[id] = true
        items[#items + 1] = id
    end
    for _, child in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityGetName(child) == "inventory_quick" then
            for _, item in ipairs(EntityGetAllChildren(child) or {}) do add(item, child) end
        end
    end
    for _, item in ipairs(GameGetAllInventoryItems(player) or {}) do add(item) end
    local inv = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    if inv then add(ComponentGetValue2(inv, "mActiveItem")) end
    return items
end

local function quick_item(player, item)
    if not item or item == 0 or not EntityGetIsAlive(item) then return false end
    for _, id in ipairs(NHTransfers.carried(player)) do
        if id == item then return true end
    end
    return false
end

local function incoming(s,player,item)
    local source = marker(item)
    if source then
        local ids, origins = storage_ids(s)
        local j=journal(s)
        if j.retired[source] or origins[source] or stored_release(s, source, ids) or unpublished_release(s,j,source) then
            dispose(item, player)
            return nil,nil,"The stored item was already transferred."
        end
    end
    return true,source
end

local function deposit_item(s,player,dest,item,preferred,equipped_record)
    local accepted,source,sourceError=incoming(s,player,item)
    if not accepted then return nil,sourceError end
    local kind = NHTransfers.item_kind(item)
    local adapter = codec(kind)
    if not adapter then return nil, "This item has no storage adapter." end
    local record, err = equipped_record
    if not record then record,err=adapter.capture(item,s) end
    if not record then return nil, err end
    if record.kind~=kind then return nil,"Invalid item record." end
    local slot,stack
    if kind=="summon_card" then slot,stack=NHCompanions.cardSlot(s,dest,preferred,record)
    else slot=NHStore.freeSlot(s,dest,preferred,kind) end
    if not slot then return nil,"Inventory slot changed." end
    if dest=="docks" and NHPotion.dockSlot(record)~=slot then return nil,"Wrong loading slot." end
    local id = s.nextItemId
    if not source or not EntityHasTag(item, tag) then
        source = source or new_token("d", s, id, id, item)
        if not stamp(item, source) then return nil, "Could not mark this item; it remains in your inventory." end
    end

    local changed = draft(s)
    changed.nextItemId = id + 1
    if kind=="summon_card" then
        if not NHCompanions.put(changed,dest,slot,stack,record,id,source) then return nil,"Inventory slot changed." end
    else
        local issued=kind=="card_wallet" and changed.transit.issued[source]
        table.insert(changed[dest],{id=issued and issued.row.id or id,item=record,origin=source,slot=slot})
    end
    -- Keep retirement after a stored flask's contents are spent or the item
    -- is withdrawn. A replayed source object must never become spendable.
    changed.transit.retired[source] = true
    changed.transit.issued[source] = nil
    local ok, reason = commit(s, changed)
    if not ok then return nil, reason end
    dispose(item, player)
    return true
end

function NHTransfers.deposit(s, player, container, selected, preferred)
    local dest = container_name(container)
    if not dest then return nil, "Unknown container." end
    local inv = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    local item = selected or (inv and ComponentGetValue2(inv, "mActiveItem"))
    local parent = item and item ~= 0 and EntityGetIsAlive(item) and EntityGetParent(item)
    local loose = parent and parent ~= 0 and EntityGetName(parent) == "inventory_full"
        and EntityGetParent(parent) == player and NHTransfers.item_kind(item) == "spell"
    if not loose and not quick_item(player, item) then
        if selected then return nil, "The selected item is no longer in your quick inventory." end
        return nil, "Hold a wand or flask first."
    end
    return deposit_item(s,player,dest,item,preferred)
end

function NHTransfers.depositEquippedPerk(s,player,request)
    if request.container~="safe" and request.container~="warehouse" then return nil,"Unknown container." end
    local perk=customItems.perk
    if not perk then return nil,"Stored item type is unsupported." end
    local record,reason=perk.adapter.captureEquipped(s,player,request.perkSlot,request.entity)
    if not record then return nil,reason end
    return deposit_item(s,player,request.container,request.entity,request.storageSlot,record)
end

-- Both warehouse rows and individual wallet cards use this commit boundary.
local function issue(s,changed,player,release,deliver)
    local row=release.row
    local adapter=codec(row.item.kind)
    if not adapter then return nil,"Stored item type is unsupported." end
    local ticket=changed.nextItemId
    if ticket>=NHStore.maxResourceAmount then return nil,"Inventory slot changed." end
    local x,y=EntityGetTransform(player)
    local entity,err=adapter.restore(row.item,x,y-4)
    if not entity or entity==0 then return nil,err or "Could not restore this item." end
    local token=new_token("r",s,ticket,row.id,entity)
    if not stamp(entity,token) then
        dispose(entity,player)
        return nil,"Could not mark the delivery; item remains in storage."
    end
    if deliver and not deliver(entity) then
        dispose(entity,player)
        return nil,"Inventory slot changed."
    end
    release.x,release.y=x,y-4
    changed.nextItemId=ticket+1
    changed.transit.issued[token]=release
    local ok,reason=commit(s,changed)
    if not ok then dispose(entity,player); return nil,reason end
    GlobalsSetValue(receipt(token),"1")
    return true,entity
end

function NHTransfers.withdraw(s, player, index, container, deliver)
    local src = container_name(container)
    if not src then return nil, "Unknown container." end
    local row = s[src][index]
    if not row then return nil, "Item is no longer in this container." end
    local changed = draft(s)
    if row.item.kind=="summon_card" then
        row=NHCompanions.take(changed,src,index)
        if not row then return nil,"Inventory slot changed." end
    else
        table.remove(changed[src],index)
    end
    return issue(s,changed,player,{row=row,container=src},deliver)
end

local function recover(draft,release)
    local dest=release.container
    local row=copy(release.row)
    if dest=="card_wallet" then return NHCardWallets.recover(draft,release) end
    if row.item.kind=="summon_card" then
        local slot,index=NHCompanions.cardSlot(draft,dest,row.slot,row.item)
        if not slot then slot,index=NHCompanions.cardSlot(draft,dest,nil,row.item) end
        if not slot and dest=="safe" then
            dest="warehouse"
            slot,index=NHCompanions.cardSlot(draft,dest,nil,row.item)
        end
        return NHCompanions.put(draft,dest,slot,index,row.item,row.id,row.origin)
    end
    if dest=="safe" then
        row.slot=NHStore.freeSafeSlot(draft,row.slot or 1) or NHStore.freeSafeSlot(draft)
        if not row.slot then dest="warehouse" end
    end
    if dest=="docks" and not NHStore.freeSlot(draft,dest,row.slot,row.item.kind) then dest,row.slot="warehouse",nil end
    if dest=="warehouse" then
        row.slot=NHStore.freeSlot(draft,dest,row.slot,row.item.kind) or NHStore.freeSlot(draft,dest,nil,row.item.kind)
    end
    if not row.slot then return false end
    table.insert(draft[dest],row)
    return true
end

function NHTransfers.reconcile(s, player)
    -- The engine tag index limits the scan to loaded items touched by this
    -- mod. Nothing examines or deletes unmarked lookalikes on an old save.
    -- Prefer the player's extant copy if a rolled-back world reintroduces a
    -- second instance; also cover held entities missing from the tag index.
    local tracked, listed = {}, {}
    for _, entity in ipairs(GameGetAllInventoryItems(player) or {}) do
        if marker(entity) then
            listed[entity] = true
            table.insert(tracked, entity)
        end
    end
    for _, entity in ipairs(EntityGetWithTag(tag) or {}) do
        if not listed[entity] then table.insert(tracked, entity) end
    end
    local j = journal(s)
    if #tracked == 0 and not next(j.issued) then return true end
    local ids, origins = storage_ids(s)
    local seen = {}
    for _, entity in ipairs(tracked) do
        if EntityGetIsAlive(entity) then
            local token = marker(entity)
            if token then
                if j.retired[token] or origins[token] or stored_release(s, token, ids) or unpublished_release(s,j,token) then
                    dispose(entity, player)
                elseif j.issued[token] then
                    if seen[token] then
                        dispose(entity, player)
                    else
                        seen[token] = true
                        if GlobalsGetValue(receipt(token), "") ~= "1" then GlobalsSetValue(receipt(token), "1") end
                    end
                end
            end
        end
    end
    local x, y = EntityGetTransform(player)
    local changed
    for token, release in pairs(j.issued) do
        -- Reclaim only in the original loaded delivery area after a world
        -- rewind. A receipt means picked up, spent, broken or carried away
        -- are all ordinary world outcomes.
        if not seen[token] and GlobalsGetValue(receipt(token), "") ~= "1"
            and math.abs(x - release.x) < 64 and math.abs(y - release.y) < 64
            and DoesWorldExistAt(math.floor(release.x) - 16, math.floor(release.y) - 16,
                math.ceil(release.x) + 16, math.ceil(release.y) + 16) then
            local candidate=changed or draft(s)
            -- A full warehouse keeps the release in the journal for a later retry.
            if ids[release.row.id] or recover(candidate,candidate.transit.issued[token]) then
                changed=candidate
                ids[release.row.id]=true
                changed.transit.retired[token] = true
                changed.transit.issued[token] = nil
            end
        end
    end
    if changed then return commit(s, changed) end
    return true
end

function NHTransfers.issuedRecord(s,entity)
    if not s then return end
    local token=marker(entity)
    if token then return journal(s).issued[token],token end
end

function NHTransfers.depositWalletCard(s,player,ref,entity,cell)
    if not quick_item(player,entity) or NHTransfers.item_kind(entity)~="summon_card" then return nil,"Select a carried summon card." end
    local accepted,token,reason=incoming(s,player,entity)
    if not accepted then return nil,reason end
    local item,err=codec("summon_card").capture(entity)
    if not item then return nil,err end
    local changed=draft(s)
    if not NHCardWallets.put(changed,player,ref,cell,item) then return nil,"Card wallet slot unavailable." end
    if not token or not EntityHasTag(entity,tag) then
        local ticket=changed.nextItemId
        if ticket>=NHStore.maxResourceAmount then return nil,"Inventory slot changed." end
        token=token or new_token("d",s,ticket,ticket,entity)
        if not stamp(entity,token) then return nil,"Could not mark this item; it remains in your inventory." end
        changed.nextItemId=ticket+1
    end
    changed.transit.retired[token]=true
    changed.transit.issued[token]=nil
    local ok,err=commit(s,changed)
    if not ok then return nil,err end
    dispose(entity,player)
    return true
end

function NHTransfers.withdrawWalletCard(s,player,ref,source,deliver)
    local changed=draft(s)
    local item=NHCardWallets.take(changed,player,ref,source)
    if not item then return nil,"Card wallet slot unavailable." end
    local row={id=changed.nextItemId,item=item}
    return issue(s,changed,player,{row=row,container="card_wallet",walletId=ref.id,cell=source.cell},deliver)
end

function NHTransfers.moveWalletCard(s,player,ref,source,target)
    local changed=draft(s)
    if source.cell then
        if source.cell==target.cell then return nil,"Card wallet slot unavailable." end
        local card=NHCardWallets.take(changed,player,ref,source)
        if not card then return nil,"Card wallet slot unavailable." end
        if target.cell then
            if not NHCardWallets.put(changed,player,ref,target.cell,card) then return nil,"Card wallet slot unavailable." end
        else
            if not target.slot then return nil,"Inventory slot changed." end
            local slot,index=NHCompanions.cardSlot(changed,target.container,target.slot,card)
            if not slot or not NHCompanions.put(changed,target.container,slot,index,card) then return nil,"Inventory slot changed." end
        end
    elseif target.cell and (source.container=="warehouse" or source.container=="safe") then
        local i=NHStore.slotIndex(changed,source.container,source.slot,"summon_card")
        local row=changed[source.container][i]
        if not row or row.id~=source.id or row.item.kind~="summon_card" then return nil,"Inventory slot changed." end
        local one=NHCompanions.take(changed,source.container,i)
        if not one or not NHCardWallets.put(changed,player,ref,target.cell,one.item) then return nil,"Card wallet slot unavailable." end
    else return nil,"Card wallet slot unavailable." end
    return commit(s,changed)
end
