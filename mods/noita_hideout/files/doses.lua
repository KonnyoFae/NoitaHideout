-- A dose is owned either by the pouch count or by one issued world item.
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
    s.safe = copy(state.safe)
    s.pouch = copy(state.pouch)
    s.issuedDoses = copy(state.issuedDoses)
    return s
end

local function commit(state, changed)
    local ok, err = NHStore.commit(changed)
    if not ok then return nil, err end
    state.revision, state.nextItemId = changed.revision, changed.nextItemId
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
    if not is_open_run(s) or s.pouch.location ~= "safe" then return nil, "Pouch unavailable." end
    local x, y = EntityGetTransform(player)
    local id, err = NHNative.spawn("pouch", x, y - 4)
    if not id then return nil, err end
    local changed = draft(s)
    local token = table.concat({s.profile, s.runSerial, s.nextItemId}, "/")
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

function NHDoses.storePouch(s, player, id, preferred)
    if not is_open_run(s) or not NHDoses.isPouch(s, id) or EntityGetRootEntity(id) ~= player then
        return nil, "Hold your injector pouch first."
    end
    local changed = draft(s)
    local slot = NHStore.freeSafeSlot(s,preferred)
    if not slot then return nil, "Secure valuables slot is full." end
    changed.pouch = {location = "safe", slot=slot, doses = s.pouch.doses}
    local ok, reason = commit(s, changed)
    if not ok then return nil, reason end
    dispose(player, id)
    return true
end

local function add_safe_dose(s,slot)
    table.insert(s.safe,{id=s.nextItemId,slot=slot,item={kind="dose"}})
    s.nextItemId=s.nextItemId+1
end

function NHDoses.moveDose(s,slot,to_safe)
    if not is_open_run(s) or s.pouch.location=="lost" then return nil,"Pouch unavailable." end
    local changed=draft(s)
    if to_safe then
        if s.pouch.doses<1 or not NHStore.freeSafeSlot(s,slot) then return nil,"Slot unavailable." end
        changed.pouch.doses=changed.pouch.doses-1
        add_safe_dose(changed,slot)
    else
        local index=NHStore.safeIndex(s,slot)
        if not index or s.safe[index].item.kind~="dose" then return nil,"Slot unavailable." end
        table.remove(changed.safe,index)
        changed.pouch.doses=changed.pouch.doses+1
    end
    return commit(s,changed)
end

function NHDoses.withdraw(s, player, deliver, pouch, safe_slot)
    if not is_open_run(s) then return nil, "Run already closed." end
    local safe_index
    if safe_slot then
        safe_index=NHStore.safeIndex(s,safe_slot)
        if not safe_index or s.safe[safe_index].item.kind~="dose" then return nil,"Slot unavailable." end
    elseif s.pouch.location == "lost" or s.pouch.doses < 1 then return nil, "No dose available." end
    if not safe_slot and s.pouch.location == "bag" and not (pouch and NHDoses.isPouch(s,pouch) and EntityGetRootEntity(pouch)==player or NHDoses.isPouch(s, NHNative.held(player))) then return nil, "Hold your injector pouch first." end
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
    local changed = draft(s)
    changed.nextItemId = changed.nextItemId + 1
    if safe_index then table.remove(changed.safe,safe_index)
    else changed.pouch.doses = changed.pouch.doses - 1 end
    changed.issuedDoses[token] = {x = x, y = y, safeSlot=safe_slot}
    if deliver and not deliver(entity) then
        dispose(player, entity)
        return nil, "Inventory slot changed."
    end
    local ok, problem = commit(s, changed)
    if not ok then dispose(player, entity); return nil, problem end
    GlobalsSetValue(receipt(token), "1")
    return true, entity
end

local function retire(s, player, entity, to_pouch, slot)
    if not is_open_run(s) then return nil, "Run already closed." end
    if not entity or entity == 0 or not EntityGetIsAlive(entity) or NHNative.kind(entity) ~= "dose" then
        return nil, "Select a syringe."
    end
    if to_pouch then
        if slot and not NHStore.freeSafeSlot(s,slot) then return nil,"Slot unavailable." end
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
    changed.issuedDoses[token] = nil
    if slot then add_safe_dose(changed,slot)
    elseif to_pouch then changed.pouch.doses = changed.pouch.doses + 1 end
    local ok, err = commit(s, changed)
    if not ok then return nil, err end
    dispose(player, entity)
    return true
end

function NHDoses.deposit(s, player, entity, slot)
    return retire(s, player, entity, true, slot)
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
        local slot = NHStore.freeSafeSlot(s,pouch.slot) or NHStore.freeSafeSlot(s)
        if slot then
            changed = draft(s)
            changed.pouch = {location = "safe", slot=slot, doses = pouch.doses}
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
            if origin.safeSlot then
                local slot=NHStore.freeSafeSlot(changed or s,origin.safeSlot) or NHStore.freeSafeSlot(changed or s)
                if slot then
                    changed=changed or draft(s)
                    add_safe_dose(changed,slot)
                    changed.issuedDoses[token]=nil
                end
            else
                changed=changed or draft(s)
                changed.issuedDoses[token] = nil
                changed.pouch.doses = changed.pouch.doses + 1
            end
        end
    end
    if changed then return commit(s, changed) end
    return true
end
