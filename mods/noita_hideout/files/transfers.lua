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

local customItems = {}
local customOrder = {}
-- Register before gameplay. A codec snapshots a live item and rebuilds it
-- from the saved record; the transfer journal owns commit and disposal.
function NHTransfers.registerItem(kind, matches, adapter)
    assert(type(kind)=="string" and type(matches)=="function" and type(adapter)=="table" and type(adapter.capture)=="function"
        and type(adapter.restore)=="function","Invalid item adapter")
    assert(not customItems[kind] and kind~="wand" and kind~="spell" and kind~="potion"
        and kind~="pouch" and kind~="dose" and kind~="other","Duplicate or reserved item kind")
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
    if NHTransfers.item_kind(entity) == "potion" then
        NHPotion.discard(entity, owner)
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
    local source = marker(item)
    if source then
        local ids, origins = storage_ids(s)
        if journal(s).retired[source] or origins[source] or stored_release(s, source, ids) then
            dispose(item, player)
            return nil, "The stored item was already transferred."
        end
    end
    local kind = NHTransfers.item_kind(item)
    local slot=NHStore.freeSlot(s,dest,preferred,kind)
    if not slot then return nil,"Inventory slot changed." end

    local adapter = codec(kind)
    if not adapter then return nil, "This item has no storage adapter." end
    local record, err = adapter.capture(item)
    if not record then return nil, err end
    if record.kind~=kind then return nil,"Invalid item record." end
    if dest=="docks" and NHPotion.dockSlot(record)~=slot then return nil,"Wrong loading slot." end
    local id = s.nextItemId
    if not source or not EntityHasTag(item, tag) then
        source = source or new_token("d", s, id, id, item)
        if not stamp(item, source) then return nil, "Could not mark this item; it remains in your inventory." end
    end

    local changed = draft(s)
    changed.nextItemId = id + 1
    table.insert(changed[dest], {id = id, item = record, origin = source, slot = slot})
    -- Keep retirement after a stored flask's contents are spent or the item
    -- is withdrawn. A replayed source object must never become spendable.
    changed.transit.retired[source] = true
    changed.transit.issued[source] = nil
    local ok, reason = commit(s, changed)
    if not ok then return nil, reason end
    dispose(item, player)
    return true
end

function NHTransfers.withdraw(s, player, index, container, deliver)
    local src = container_name(container)
    if not src then return nil, "Unknown container." end
    local row = s[src][index]
    if not row then return nil, "Item is no longer in this container." end
    local adapter = codec(row.item.kind)
    if not adapter then return nil, "Stored item type is unsupported." end
    local x, y = EntityGetTransform(player)
    local entity, err = adapter.restore(row.item, x, y - 4)
    if not entity or entity == 0 then return nil, err or "Could not restore this item." end
    local ticket = s.nextItemId
    local token = new_token("r", s, ticket, row.id, entity)
    if not stamp(entity, token) then
        dispose(entity, player)
        return nil, "Could not mark the delivery; item remains in storage."
    end

    if deliver and not deliver(entity) then
        dispose(entity, player)
        return nil, "Inventory slot changed."
    end
    local changed = draft(s)
    table.remove(changed[src], index)
    changed.nextItemId = ticket + 1
    changed.transit.issued[token] = {row = row, container = src, x = x, y = y - 4}
    local ok, reason = commit(s, changed)
    if not ok then
        dispose(entity, player)
        return nil, reason
    end
    GlobalsSetValue(receipt(token), "1")
    return true, entity
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
                if j.retired[token] or origins[token] or stored_release(s, token, ids) then
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
            changed = changed or draft(s)
            local dest = release.container
            local row = copy(release.row)
            if dest == "safe" then
                row.slot = NHStore.freeSafeSlot(changed,row.slot or 1) or NHStore.freeSafeSlot(changed)
                if not row.slot then dest = "warehouse" end
            end
            if dest=="docks" and not NHStore.freeSlot(changed,dest,row.slot,row.item.kind) then
                dest,row.slot="warehouse",nil
            end
            if dest=="warehouse" then row.slot=NHStore.freeSlot(changed,dest,row.slot,row.item.kind) or NHStore.freeSlot(changed,dest,nil,row.item.kind) end
            if not ids[release.row.id] then
                table.insert(changed[dest], row)
                ids[release.row.id] = true
            end
            changed.transit.retired[token] = true
            changed.transit.issued[token] = nil
        end
    end
    if changed then return commit(s, changed) end
    return true
end
