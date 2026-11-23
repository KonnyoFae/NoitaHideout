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
    s.pendingChargerUses=changed.pendingChargerUses
    s.revision, s.nextItemId = changed.revision, changed.nextItemId
    s.docks = changed.docks
    s.summons, s.dragonLoot = changed.summons, changed.dragonLoot
    s.gelBonus,s.resources=changed.gelBonus,changed.resources
    s.warehouse, s.safe, s.transit = changed.warehouse, changed.safe, changed.transit
    for _,field in ipairs(NHShields.fields) do s[field]=changed[field] end
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
    for _,field in ipairs(NHShields.fields) do
        local row=s[field]
        if row then ids[row.id]=true; if row.origin then sources[row.origin]=true end end
    end
    for _, rows in ipairs({s.warehouse, s.safe, s.docks}) do
        for _, row in ipairs(rows) do
            ids[row.id] = true
            if row.origin then sources[row.origin] = true end
            if row.item.kind=="relic_chain" then
                for _,socket in pairs(row.item.cells) do
                    ids[socket.id]=true
                    if socket.origin then sources[socket.origin]=true end
                end
            end
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
            or adapter.warehouseCategory=="wand" or adapter.warehouseCategory=="collection","Invalid warehouse category")
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

-- Plan all partial stacks before changing any rows. A full destination can
-- still accept the transfer when several stacks have enough room together.
local function stormStorage(s,dest,item)
    local left=NHStormProducts.count(item.count)
    if not left then return end
    local fills={}
    local slot
    for index,row in ipairs(s[dest]) do
        if row.item.kind==item.kind then
            local n=row.item.count or 1
            local take=math.min(left,NHStormProducts.stackLimit-n)
            if take>0 then
                fills[#fills+1]={index=index,count=n+take}
                slot=row.slot or index
                left=left-take
                if left==0 then break end
            end
        end
    end
    if left>0 then slot=NHStore.freeSlot(s,dest,nil,item.kind) end
    if not slot then return end
    return slot,nil,function(rows,incoming)
        for _,fill in ipairs(fills) do
            local row=copy(rows[fill.index])
            row.item=copy(row.item)
            row.item.count=fill.count
            rows[fill.index]=row
        end
        if left>0 then
            local row=copy(incoming)
            row.slot,row.item=slot,copy(row.item)
            row.item.count=left
            table.insert(rows,row)
        end
    end
end

function NHTransfers.storageSlot(s,dest,item,preferred)
    if not preferred and NHStormProducts.types[item.kind] and (dest=="warehouse" or dest=="safe") then
        return stormStorage(s,dest,item)
    end
    if item.kind=="summon_card" then return NHCompanions.cardSlot(s,dest,preferred,item,item.count) end
    if item.kind=="dose" then
        for i,row in ipairs(s[dest]) do
            local slot=row.slot or i
            if row.item.kind=="dose" and (not preferred or preferred==slot)
                and NHStore.acceptsDose(row.item,item.remaining or NHStore.doseDurability,item.subtype)
                and (item.count or 1)<=NHStore.maxResourceAmount-(row.item.count or 1) then return slot,i end
        end
    end
    local slot,index=NHStore.stackSlot(s,dest,item,preferred)
    if slot then return slot,index end
    return NHStore.freeSlot(s,dest,preferred,item.kind)
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
    local finish
    if deliver then
        local accepted
        accepted,finish=deliver(entity)
        if not accepted then
            dispose(entity,player)
            return nil,"Inventory slot changed."
        end
    end
    release.x,release.y=x,y-4
    changed.nextItemId=ticket+1
    changed.transit.issued[token]=release
    local ok,reason=commit(s,changed)
    if not ok then dispose(entity,player); return nil,reason end
    -- A merge into an existing native item becomes visible only after commit.
    if finish then finish() end
    GlobalsSetValue(receipt(token),"1")
    return true,entity
end

local function deposit_item(s,player,dest,item,preferred,equipped_record,fallback,chain)
    local accepted,source,sourceError=incoming(s,player,item)
    if not accepted then return nil,sourceError end
    local kind = NHTransfers.item_kind(item)
    local adapter = codec(kind)
    if not adapter then return nil, "This item has no storage adapter." end
    local record, err = equipped_record
    if not record then record,err=adapter.capture(item,s) end
    if not record then return nil, err end
    if record.kind~=kind then return nil,"Invalid item record." end
    local slot,stack,putStorm
    if dest=="gear" then
        local field=NHShields.field(kind)
        if field and preferred==NHShields.slot(kind) and not s[field] then slot=preferred end
    elseif chain then
        local row=NHRelics.chain(s,chain)
        if kind~="relic" or not row or not preferred or row.item.cells[preferred] then return nil,"Relic unavailable." end
        slot=preferred
    else
        slot,stack,putStorm=NHTransfers.storageSlot(s,dest,record,preferred)
    end
    if not slot and fallback then
        dest=fallback
        slot,stack,putStorm=NHTransfers.storageSlot(s,dest,record)
    end
    if not slot then return nil,preferred and "Inventory slot changed." or "No free destination slot." end
    if dest=="docks" and NHPotion.dockSlot(record)~=slot then return nil,"Wrong loading slot." end
    local id = s.nextItemId
    if not source or not EntityHasTag(item, tag) then
        source = source or new_token("d", s, id, id, item)
        if not stamp(item, source) then return nil, "Could not mark this item; it remains in your inventory." end
    end

    local changed = draft(s)
    changed.nextItemId = id + 1
    if record.chargerOverflow then
        changed.pendingChargerUses=(changed.pendingChargerUses or 0)+record.chargerOverflow
        record.chargerOverflow=nil
    end
    if dest=="gear" then
        local row={id=id,item=record,origin=source,epoch=s.revision+1}
        changed[NHShields.field(kind)]=row
        if NHShields.supply(kind) and record.count>1 then
            local rest=copy(record)
            rest.count,rest.remaining=record.count-1,NHShields.supply(kind).uses
            record.count=1
            local component=EntityGetFirstComponentIncludingDisabled(item,"ItemComponent")
            local sx,sy=ComponentGetValue2(component,"inventory_slot")
            local parent=EntityGetParent(item)
            changed.transit.retired[source],changed.transit.issued[source]=true,nil
            local release={container="warehouse",row={id=changed.nextItemId,item=rest}}
            local ok,reason=issue(s,changed,player,release,function(remainder)
                return true,function()
                    dispose(item,player)
                    EntityAddChild(parent,remainder)
                    local c=EntityGetFirstComponentIncludingDisabled(remainder,"ItemComponent")
                    ComponentSetValue2(c,"inventory_slot",sx,sy)
                    EntitySetComponentsWithTagEnabled(remainder,"enabled_in_world",false)
                    EntitySetComponentsWithTagEnabled(remainder,"enabled_in_inventory",true)
                    EntitySetComponentsWithTagEnabled(remainder,"enabled_in_hand",false)
                    local inv=EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
                    ComponentSetValue2(inv,"mForceRefresh",true)
                end
            end)
            if not ok then return nil,reason end
            return true,nil,dest,slot
        end
    elseif chain then
        if not NHRelics.put(changed,chain,slot,{id=id,item=record,origin=source}) then return nil,"Relic unavailable." end
    elseif kind=="summon_card" then
        if not NHCompanions.put(changed,dest,slot,stack,record,id,source) then return nil,"Inventory slot changed." end
    elseif putStorm then
        putStorm(changed[dest],{id=id,item=record,origin=source})
    elseif stack then
        local row=changed[dest][stack]
        local target=copy(row.item)
        NHStore.mergeStack(target,record)
        changed[dest][stack]={id=row.id,slot=row.slot,origin=row.origin,item=target}
    else
        local issued=(kind=="card_wallet" or kind=="relic_chain") and changed.transit.issued[source]
        table.insert(changed[dest],{id=issued and issued.row.id or id,item=record,origin=source,slot=slot})
    end
    -- Keep retirement after a stored flask's contents are spent or the item
    -- is withdrawn. A replayed source object must never become spendable.
    changed.transit.retired[source] = true
    changed.transit.issued[source] = nil
    local ok, reason = commit(s, changed)
    if not ok then return nil, reason end
    dispose(item, player)
    return true,nil,dest,slot
end

function NHTransfers.deposit(s, player, container, selected, preferred, fallback, chain)
    local dest = container=="gear" and "gear" or container_name(container)
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
    return deposit_item(s,player,dest,item,preferred,nil,fallback,chain)
end

-- The caller selects a pickable ground entity in interaction range.
function NHTransfers.pickupToSafe(s,player,id)
    if not EntityGetIsAlive(id) or EntityGetRootEntity(id)~=id or EntityGetFirstComponentIncludingDisabled(id,"ItemCostComponent") then
        return nil,"Slot unavailable."
    end
    return deposit_item(s,player,"safe",id)
end

function NHTransfers.available(s,player,id)
    return incoming(s,player,id)
end

function NHTransfers.depositEquippedPerk(s,player,request)
    if request.container~="safe" and request.container~="warehouse" then return nil,"Unknown container." end
    local perk=customItems.perk
    if not perk then return nil,"Stored item type is unsupported." end
    local record,reason=perk.adapter.captureEquipped(s,player,request.perkSlot,request.entity)
    if not record then return nil,reason end
    return deposit_item(s,player,request.container,request.entity,request.storageSlot,record)
end

-- Only the front food portion or launcher may be partly used.
local function take_row(s,src,index,one)
    local row=s[src][index]
    local item=row.item
    if not one then return table.remove(s[src],index) end
    if item.kind=="summon_card" then return NHCompanions.take(s,src,index) end
    local spell=item.kind=="spell" and item.card
    local count=spell and spell.stack or 1
    if item.count and (item.kind=="dose" or NHThrowables.types[item.kind] or NHStore.stackUnits(item)) then
        count=item.count
    end
    if count==1 then return table.remove(s[src],index) end
    if s.nextItemId>=NHStore.maxResourceAmount then return end
    local unit,rest=copy(item),copy(item)
    if spell then
        unit.card,rest.card=copy(spell),copy(spell)
        unit.card.stack,rest.card.stack=nil,count-1
    else
        unit.count,rest.count=1,count-1
        local gun,food=NHGuns.types[item.kind],NHFoods.byId[item.kind]
        if NHMedkits.capacity(item.kind) then rest.remaining=NHMedkits.capacity(item.kind)
        elseif gun then rest.remaining=gun.capacity elseif food then rest.remaining=food.uses end
    end
    s[src][index]={id=row.id,origin=row.origin,slot=row.slot,item=rest}
    local id=s.nextItemId
    s.nextItemId=id+1
    return {id=id,slot=row.slot,item=unit}
end

function NHTransfers.withdraw(s, player, index, container, deliver, one)
    local src = container_name(container)
    if not src then return nil, "Unknown container." end
    local row = s[src][index]
    if not row then return nil, "Item is no longer in this container." end
    local changed = draft(s)
    row=take_row(changed,src,index,one or row.item.kind=="summon_card")
    if not row then return nil,"Inventory slot changed." end
    return issue(s,changed,player,{row=row,container=src},deliver)
end

function NHTransfers.withdrawRelic(s,player,ref,cell,id,deliver)
    local changed=draft(s)
    local row=NHRelics.take(changed,ref,cell,id)
    if not row then return nil,"Inventory slot changed." end
    return issue(s,changed,player,{row=row,container="relic_chain",chain=ref,cell=cell},deliver)
end

function NHTransfers.withdrawGear(s,player,id,kind,deliver)
    local field=NHShields.field(kind)
    local row=s[field]
    if not row or row.id~=id or row.item.kind~=kind then return nil,"Inventory slot changed." end
    local changed=draft(s)
    changed[field]=nil
    return issue(s,changed,player,{row=row,container="gear"},deliver)
end

-- Both containers belong to one profile. Publish the move in a single write.
function NHTransfers.moveStored(s,src,index,dest,one,preferred)
    local changed=draft(s)
    local row=take_row(changed,src,index,one)
    if not row then return nil,"Inventory slot changed." end
    if dest=="docks" and (not preferred or NHPotion.dockSlot(row.item)~=preferred) then return nil,"Wrong loading slot." end
    local slot,stack,putStorm=NHTransfers.storageSlot(changed,dest,row.item,preferred)
    if not slot then return nil,"No free destination slot." end
    if putStorm then
        putStorm(changed[dest],row)
    elseif not stack then
        row=copy(row)
        row.slot=slot
        table.insert(changed[dest],row)
    elseif row.item.kind=="summon_card" then
        if not NHCompanions.put(changed,dest,slot,stack,row.item,row.id,row.origin) then return nil,"Inventory slot changed." end
    else
        local target=copy(changed[dest][stack])
        target.item=copy(target.item)
        if row.item.kind=="dose" then target.item.count=(target.item.count or 1)+(row.item.count or 1)
        else NHStore.mergeStack(target.item,row.item) end
        changed[dest][stack]=target
    end
    local ok,reason=commit(s,changed)
    return ok,reason,dest,slot
end

local function recover(draft,release)
    local dest=release.container
    local row=copy(release.row)
    if dest=="gear" then
        local field=NHShields.field(row.item.kind)
        if not draft[field] then
            row.epoch=draft.revision+1
            draft[field]=row
            return true
        end
        dest,row.slot="warehouse",nil
    end
    if dest=="card_wallet" then return NHCardWallets.recover(draft,release) end
    if dest=="relic_chain" then
        if NHRelics.put(draft,release.chain,release.cell,row) then return true end
        dest,row.slot="warehouse",nil
    end
    if row.item.kind=="summon_card" then
        local slot,index=NHCompanions.cardSlot(draft,dest,row.slot,row.item)
        if not slot then slot,index=NHCompanions.cardSlot(draft,dest,nil,row.item) end
        if not slot and dest=="safe" then
            dest="warehouse"
            slot,index=NHCompanions.cardSlot(draft,dest,nil,row.item)
        end
        return NHCompanions.put(draft,dest,slot,index,row.item,row.id,row.origin)
    end
    local slot,index=NHStore.stackSlot(draft,dest,row.item,row.slot)
    if slot then
        local target=copy(draft[dest][index])
        target.item=copy(target.item)
        NHStore.mergeStack(target.item,row.item)
        draft[dest][index]=target
        return true
    end
    if NHStormProducts.types[row.item.kind] then
        local _,_,putStorm=stormStorage(draft,dest,row.item)
        if not putStorm and dest=="safe" then
            dest="warehouse"
            _,_,putStorm=stormStorage(draft,dest,row.item)
        end
        if not putStorm then return false end
        putStorm(draft[dest],row)
        return true
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
                    if not seen[token] then
                        seen[token] = entity
                        if GlobalsGetValue(receipt(token), "") ~= "1" then GlobalsSetValue(receipt(token), "1") end
                    elseif seen[token]~=entity then
                        dispose(entity, player)
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
                if release.chargerOverflow and not ids[release.row.id] then
                    changed.pendingChargerUses=(changed.pendingChargerUses or 0)+release.chargerOverflow
                end
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
