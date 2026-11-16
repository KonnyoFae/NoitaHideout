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
    s.pouch = copy(state.pouch)
    s.issuedDoses = copy(state.issuedDoses)
    return s
end

local function commit(state, changed)
    local ok, err = NHStore.commit(changed)
    if not ok then return nil, err end
    state.revision, state.nextItemId = changed.revision, changed.nextItemId
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

function NHDoses.withdraw(s, player)
    if not is_open_run(s) then return nil, "Run already closed." end
    if s.pouch.location == "lost" or s.pouch.doses < 1 then return nil, "No dose available." end
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
    changed.pouch.doses = changed.pouch.doses - 1
    changed.issuedDoses[token] = {x = x, y = y}
    local ok, problem = commit(s, changed)
    if not ok then EntityKill(entity); return nil, problem end
    GlobalsSetValue(receipt(token), "1")
    return true, entity
end

local function retire(s, player, entity, to_pouch)
    if not is_open_run(s) then return nil, "Run already closed." end
    if not entity or entity == 0 or not EntityGetIsAlive(entity) or NHNative.kind(entity) ~= "dose" then
        return nil, "Select a syringe."
    end
    if to_pouch then
        if s.pouch.location == "lost" then return nil, "Pouch lost." end
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
    if to_pouch then changed.pouch.doses = changed.pouch.doses + 1 end
    local ok, err = commit(s, changed)
    if not ok then return nil, err end
    dispose(player, entity)
    return true
end

function NHDoses.deposit(s, player, entity)
    return retire(s, player, entity, true)
end

function NHDoses.consume(s, player, entity)
    return retire(s, player, entity, false)
end

function NHDoses.reconcile(s, player)
    if not is_open_run(s) then return true end
    local issued = s.issuedDoses or {}
    local seen, visited = {}, {}
    local function inspect(entity)
        if visited[entity] or not EntityGetIsAlive(entity) or NHNative.kind(entity) ~= "dose" then return end
        visited[entity] = true
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
    if not next(issued) then return true end
    local x, y = EntityGetTransform(player)
    local changed
    for token, origin in pairs(issued) do
        -- An apparently missing item may have been legitimately used or unloaded.
        -- Refund only if the delivery receipt itself was rewound, and its origin
        -- is nearby and loaded. The old token is retired in that same commit.
        if not seen[token] and GlobalsGetValue(receipt(token), "") ~= "1"
            and math.abs(x - origin.x) < 64 and math.abs(y - origin.y) < 64
            and DoesWorldExistAt(math.floor(origin.x) - 16, math.floor(origin.y) - 16,
                math.ceil(origin.x) + 16, math.ceil(origin.y) + 16)
            and s.pouch.location ~= "lost" then
            changed = changed or draft(s)
            changed.issuedDoses[token] = nil
            changed.pouch.doses = changed.pouch.doses + 1
        end
    end
    if changed then return commit(s, changed) end
    return true
end
