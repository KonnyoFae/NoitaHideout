-- An injector belongs to one pouch cell, secure slot, or issued entity.
-- The live token list is authoritative even when a world save is older.
NHDoses = {}

local item_tag = "noita_hideout_dose"
local token_tag = "noita_hideout_dose_token"

local function copy(t)
    local result = {}
    for k, v in pairs(t or {}) do result[k] = v end
    return result
end

local function draft(state)
    local s = copy(state)
    s.warehouse = copy(state.warehouse)
    s.safe = copy(state.safe)
    s.pouch = copy(state.pouch)
    s.pouch.cells = copy(state.pouch.cells)
    s.issuedDoses = copy(state.issuedDoses)
    return s
end

local function commit(state, changed)
    local ok, err = NHStore.commit(changed)
    if not ok then return nil, err end
    state.revision, state.nextItemId = changed.revision, changed.nextItemId
    state.warehouse = changed.warehouse
    state.safe = changed.safe
    state.pouch, state.issuedDoses = changed.pouch, changed.issuedDoses
    return true
end

local function token_of(entity)
    local c = EntityGetFirstComponentIncludingDisabled(entity, "VariableStorageComponent", token_tag)
    if c and c ~= 0 then return ComponentGetValue2(c, "value_string") end
end

local function receipt(token)
    return "noita_hideout.dose_delivered." .. token
end

local function dispose(player, entity)
    if EntityGetRootEntity(entity) == player then
        GameKillInventoryItem(player, entity)
    else
        EntityKill(entity)
    end
end

local function is_open_run(s)
    return s.runSerial > s.closedThrough
end

local pouch_tag = "noita_hideout_pouch_token"

function NHDoses.isPouch(s, entity)
    if s.pouch.location ~= "bag" or not s.pouch.token or NHNative.kind(entity) ~= "pouch" then return false end
    local c = EntityGetFirstComponentIncludingDisabled(entity, "VariableStorageComponent", pouch_tag)
    return c and ComponentGetValue2(c, "value_string") == s.pouch.token
end

function NHDoses.takePouch(s, player, deliver)
    if not is_open_run(s) or (s.pouch.location ~= "safe" and s.pouch.location ~= "warehouse") then return nil, "Pouch unavailable." end
    local x, y = EntityGetTransform(player)
    local id, err = NHNative.spawn("pouch", x, y - 4)
    if not id then return nil, err end
    local changed = draft(s)
    local token = table.concat({s.profile, s.runSerial, s.nextItemId}, "/")
    changed.pouch.originContainer = s.pouch.location
    changed.pouch.x, changed.pouch.y = x, y
    local c = EntityAddComponent2(id, "VariableStorageComponent", {_tags=pouch_tag, name=pouch_tag, value_string=token})
    if not c or ComponentGetValue2(c, "value_string") ~= token then
        EntityKill(id)
        return nil, "Could not mark the pouch."
    end
    changed.pouch.location, changed.pouch.token = "bag", token
    changed.nextItemId = changed.nextItemId + 1
    if deliver and not deliver(id) then
        dispose(player, id)
        return nil, "Inventory slot changed."
    end
    local ok, reason = commit(s, changed)
    if not ok then dispose(player, id); return nil, reason end
    GlobalsSetValue(receipt(token), "1")
    return true, id
end

function NHDoses.storePouch(s, player, id, preferred, container)
    container=container or "safe"
    if not is_open_run(s) or not NHDoses.isPouch(s, id) or EntityGetRootEntity(id) ~= player then
        return nil, "Hold your injector pouch first."
    end
    local changed = draft(s)
    local slot = NHStore.freeSlot(s,container,preferred,"pouch")
    if not slot then return nil, "Secure valuables slot is full." end
    changed.pouch = {location=container,slot=slot,cells=changed.pouch.cells,doses=s.pouch.doses}
    local ok, reason = commit(s, changed)
    if not ok then return nil, reason end
    dispose(player, id)
    return true
end

local function add_stored_dose(s,slot,remaining,container)
    container=container or "safe"
    local rows=s[container]
    local index=NHStore.slotIndex(s,container,slot,"dose")
    local row=index and rows[index]
    if row then
        if row.item.kind~="dose" or remaining~=NHStore.doseDurability
            or (row.item.remaining or NHStore.doseDurability)~=remaining then return false end
        row=copy(row)
        row.item={kind="dose",remaining=remaining,count=(row.item.count or 1)+1}
        rows[index]=row
    else
        if not NHStore.freeSlot(s,container,slot,"dose") then return false end
        table.insert(rows,{id=s.nextItemId,slot=slot,item={kind="dose",remaining=remaining,count=1}})
        s.nextItemId=s.nextItemId+1
    end
    return true
end

local function take_stored_dose(s,slot,container)
    container=container or "safe"
    local rows=s[container]
    local index=NHStore.slotIndex(s,container,slot,"dose")
    local row=index and rows[index]
    if not row or row.item.kind~="dose" then return end
    local remaining=row.item.remaining or NHStore.doseDurability
    if (row.item.count or 1)>1 then
        row=copy(row)
        row.item={kind="dose",remaining=remaining,count=row.item.count-1}
        rows[index]=row
    else table.remove(rows,index) end
    return remaining
end

function NHDoses.moveDose(s,slot,to_safe,cell,container)
    if not is_open_run(s) or s.pouch.location=="lost" then return nil,"Pouch unavailable." end
    local changed=draft(s)
    local remaining
    if to_safe then
        remaining=NHStore.takePouchDose(changed.pouch,cell or 1)
        if not remaining or not add_stored_dose(changed,slot,remaining,container) then return nil,"Slot unavailable." end
    else
        remaining=take_stored_dose(changed,slot,container)
        if not remaining or not NHStore.putPouchDose(changed.pouch,remaining,cell) then return nil,"Slot unavailable." end
    end
    return commit(s,changed)
end

function NHDoses.moveSafeDose(s,source,target,container)
    if not is_open_run(s) or source==target then return nil,"Slot unavailable." end
    local changed=draft(s)
    local remaining=take_stored_dose(changed,source,container)
    if not remaining or not add_stored_dose(changed,target,remaining,container) then return nil,"Slot unavailable." end
    return commit(s,changed)
end

function NHDoses.moveCell(s,source,target)
    if not is_open_run(s) or source==target then return nil,"Slot unavailable." end
    local changed=draft(s)
    local remaining=NHStore.takePouchDose(changed.pouch,source)
    if not remaining or not NHStore.putPouchDose(changed.pouch,remaining,target) then return nil,"Slot unavailable." end
    return commit(s,changed)
end

function NHDoses.remaining(s,entity)
    local token=token_of(entity)
    local record=token and s.issuedDoses and s.issuedDoses[token]
    return record and (record.remaining or NHStore.doseDurability)
end

local function show_remaining(entity,remaining)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    if item then ComponentSetValue2(item,"uses_remaining",remaining) end
end

function NHDoses.withdraw(s, player, deliver, pouch, safe_slot, cell, container)
    if not is_open_run(s) then return nil,"Run already closed." end
    if not safe_slot and s.pouch.location=="bag" and not (pouch and NHDoses.isPouch(s,pouch) and EntityGetRootEntity(pouch)==player or NHDoses.isPouch(s,NHNative.held(player))) then return nil,"Hold your injector pouch first." end
    local changed=draft(s)
    local remaining
    if safe_slot then remaining=take_stored_dose(changed,safe_slot,container)
    else remaining=NHStore.takePouchDose(changed.pouch,cell or 1) end
    if not remaining then return nil,"No dose available." end
    local x, y = EntityGetTransform(player)
    y = y - 4
    local entity, err = NHNative.spawn("dose", x, y)
    if not entity or entity == 0 then return nil, err or "Could not create a syringe." end
    local token = table.concat({s.profile, s.runSerial, s.nextItemId, GameGetFrameNum(), entity}, "/")
    local c = EntityAddComponent2(entity, "VariableStorageComponent", {
        _tags = token_tag, name = token_tag, value_string = token,
    })
    if not c or c == 0 or token_of(entity) ~= token then
        EntityKill(entity)
        return nil, "Could not mark the syringe. It remains in the pouch."
    end
    changed.nextItemId = changed.nextItemId + 1
    changed.issuedDoses[token] = {x=x,y=y,safeSlot=safe_slot,container=container,cell=cell,remaining=remaining}
    show_remaining(entity,remaining)
    if deliver and not deliver(entity) then
        dispose(player, entity)
        return nil, "Inventory slot changed."
    end
    local ok, problem = commit(s, changed)
    if not ok then dispose(player, entity); return nil, problem end
    GlobalsSetValue(receipt(token), "1")
    return true, entity
end

local function retire(s, player, entity, to_pouch, slot, cell, container)
    if not is_open_run(s) then return nil, "Run already closed." end
    if not entity or entity == 0 or not EntityGetIsAlive(entity) or NHNative.kind(entity) ~= "dose" then
        return nil, "Select a syringe."
    end
    if to_pouch then
        if not slot and s.pouch.location == "lost" then return nil, "Pouch lost." end
        if EntityGetRootEntity(entity) ~= player then
            return nil, "The selected item is no longer in your quick inventory."
        end
    elseif NHNative.held(player) ~= entity or EntityGetRootEntity(entity) ~= player then
        return nil, "Select a syringe."
    end
    local token = token_of(entity)
    if not token or not s.issuedDoses or not s.issuedDoses[token] then
        return nil, "This syringe is no longer available."
    end
    local changed = draft(s)
    local remaining=changed.issuedDoses[token].remaining or NHStore.doseDurability
    if not to_pouch and remaining>1 then
        local record=copy(changed.issuedDoses[token])
        record.remaining=remaining-1
        changed.issuedDoses[token]=record
        local ok,err=commit(s,changed)
        if not ok then return nil,err end
        show_remaining(entity,record.remaining)
        return true,record.remaining
    end
    if to_pouch then
        if slot then
            if not add_stored_dose(changed,slot,remaining,container) then return nil,"Slot unavailable." end
        elseif not NHStore.putPouchDose(changed.pouch,remaining,cell) then return nil,"Slot unavailable." end
    end
    changed.issuedDoses[token]=nil
    local ok,err=commit(s,changed)
    if not ok then return nil,err end
    dispose(player,entity)
    return true,0
end

function NHDoses.deposit(s,player,entity,slot,cell,container)
    return retire(s,player,entity,true,slot,cell,container)
end

function NHDoses.consume(s, player, entity)
    return retire(s, player, entity, false)
end

function NHDoses.reconcile(s, player)
    if not is_open_run(s) then return true end
    local issued = s.issuedDoses or {}
    local seen, visited = {}, {}
    local pouch_seen = false
    local function inspect(entity)
        if visited[entity] or not EntityGetIsAlive(entity) then return end
        visited[entity] = true
        local kind = NHNative.kind(entity)
        if kind == "pouch" then
            if not pouch_seen and NHDoses.isPouch(s, entity) then
                pouch_seen = true
                GlobalsSetValue(receipt(s.pouch.token), "1")
            else dispose(player, entity) end
            return
        end
        if kind ~= "dose" then return end
        local token = token_of(entity)
        if token and issued[token] and not seen[token] then
            seen[token] = true
            show_remaining(entity,issued[token].remaining or NHStore.doseDurability)
            if GlobalsGetValue(receipt(token), "") ~= "1" then GlobalsSetValue(receipt(token), "1") end
        else
            dispose(player, entity)
        end
    end
    -- Prioritize a carried copy when a rolled-back world reintroduces a twin.
    for _, id in ipairs(GameGetAllInventoryItems(player) or {}) do inspect(id) end
    for _, id in ipairs(EntityGetWithTag(item_tag) or {}) do inspect(id) end
    for _, id in ipairs(EntityGetWithTag("noita_hideout_pouch") or {}) do inspect(id) end
    if not next(issued) and (s.pouch.location ~= "bag" or pouch_seen) then return true end
    local x, y = EntityGetTransform(player)
    local changed
    local pouch = s.pouch
    if pouch.location == "bag" and pouch.token and not pouch_seen and pouch.x and pouch.y
        and GlobalsGetValue(receipt(pouch.token), "") ~= "1"
        and math.abs(x-pouch.x) < 64 and math.abs(y-pouch.y) < 64
        and DoesWorldExistAt(math.floor(pouch.x)-16, math.floor(pouch.y)-16, math.ceil(pouch.x)+16, math.ceil(pouch.y)+16) then
        local container=pouch.originContainer or "safe"
        local slot=NHStore.freeSlot(s,container,pouch.slot,"pouch") or NHStore.freeSlot(s,container,nil,"pouch")
        if slot then
            changed = draft(s)
            changed.pouch = {location=container,slot=slot,cells=changed.pouch.cells,doses=pouch.doses}
        end
    end
    for token, origin in pairs(issued) do
        -- An apparently missing item may have been legitimately used or unloaded.
        -- Refund only if the delivery receipt itself was rewound, and its origin
        -- is nearby and loaded. The old token is retired in that same commit.
        if not seen[token] and GlobalsGetValue(receipt(token), "") ~= "1"
            and math.abs(x - origin.x) < 64 and math.abs(y - origin.y) < 64
            and DoesWorldExistAt(math.floor(origin.x) - 16, math.floor(origin.y) - 16,
                math.ceil(origin.x) + 16, math.ceil(origin.y) + 16)
            and (origin.safeSlot or s.pouch.location ~= "lost") then
            local candidate=draft(changed or s)
            local remaining=origin.remaining or NHStore.doseDurability
            local recovered
            if origin.safeSlot then
                recovered=add_stored_dose(candidate,origin.safeSlot,remaining,origin.container)
                if not recovered then
                    local slot=NHStore.freeSlot(candidate,origin.container or "safe",nil,"dose")
                    recovered=slot and add_stored_dose(candidate,slot,remaining,origin.container)
                end
            else
                recovered=NHStore.putPouchDose(candidate.pouch,remaining,origin.cell)
                    or NHStore.putPouchDose(candidate.pouch,remaining)
            end
            if recovered then
                candidate.issuedDoses[token]=nil
                changed=candidate
            end
        end
    end
    if changed then return commit(s, changed) end
    return true
end
