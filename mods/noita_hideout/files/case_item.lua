-- The tangible case opens the profile's protected contents. Its world token,
-- not its transient entity ID, identifies the carrier through drops and loads.
NHCase = {}

local tag = "noita_hideout_case_ticket"
local reach = 24

local function prefix(state)
    return state.profile .. "/" .. state.runSerial .. "/"
end

local function generation_key(state)
    return "noita_hideout.case_generation." .. state.profile .. "." .. state.runSerial
end

local function number_of(raw)
    if not raw or not raw:match("^[1-9]%d*$") then return nil end
    return tonumber(raw)
end

local function ticket(entity)
    if not entity or entity == 0 or not EntityGetIsAlive(entity) or not EntityHasTag(entity, tag)
        or NHNative.kind(entity) ~= "case" then return nil end
    local component = EntityGetFirstComponentIncludingDisabled(entity, "VariableStorageComponent", tag)
    return component and ComponentGetValue2(component, "value_string")
end

local function issued(state)
    local generation = number_of(GlobalsGetValue(generation_key(state), ""))
    return generation and prefix(state) .. generation
end

local function close_to(entity, player, radius)
    local x, y = EntityGetTransform(entity)
    local px, py = EntityGetTransform(player)
    return (x-px)^2 + (y-py)^2 <= radius^2
end

function NHCase.accessible(state, player, entity)
    local token = ticket(entity)
    if not token or token ~= issued(state) then return false end
    if NHNative.held(player) == entity and EntityGetRootEntity(entity) == player then return true end
    return EntityGetRootEntity(entity) == entity and close_to(entity, player, reach)
end

function NHCase.nearby(state, player)
    local px, py = EntityGetTransform(player)
    local active = issued(state)
    if not active then return nil end
    local nearest, best = nil, reach^2
    for _, entity in ipairs(EntityGetInRadiusWithTag(px, py, reach, tag) or {}) do
        if ticket(entity) == active and EntityGetRootEntity(entity) == entity then
            local ex, ey = EntityGetTransform(entity)
            local distance = (px-ex)^2 + (py-ey)^2
            if distance <= best then nearest, best = entity, distance end
        end
    end
    return nearest
end

local function loaded_cases(player)
    local cases, seen = {}, {}
    local function collect(list)
        for _, entity in ipairs(list or {}) do
            if not seen[entity] and ticket(entity) then
                cases[#cases + 1] = entity
                seen[entity] = true
            end
        end
    end
    -- Some carried items are omitted by a world tag query. Prefer inventory
    -- on duplicate recovery so the one the player is carrying stays usable.
    collect({NHNative.held(player)})
    collect(GameGetAllInventoryItems(player))
    collect(EntityGetWithTag(tag))
    return cases
end

local function discard(entity, player)
    if EntityGetRootEntity(entity) == player then
        GameKillInventoryItem(player, entity)
    else
        EntityKill(entity)
    end
end

local function place_case(state, anchor_x, anchor_y, generation)
    local x, y = math.floor(anchor_x + 12), math.floor(anchor_y - 5)
    if not DoesWorldExistAt(x-3, y-3, x+3, y+3) then return true end
    local entity, reason = NHNative.spawn("case", x, y)
    if not entity or entity == 0 then return nil, reason or "Could not create the secure case." end
    if NHNative.kind(entity) ~= "case" then return nil, "Secure case template mismatch." end
    local token = prefix(state) .. generation
    local comp = EntityAddComponent2(entity, "VariableStorageComponent", {
        _tags = tag, name = tag, value_string = token
    })
    EntityAddTag(entity, tag)
    if not comp or ticket(entity) ~= token then
        EntityKill(entity)
        return nil, "Could not identify the secure case."
    end
    local key = generation_key(state)
    GlobalsSetValue(key, tostring(generation))
    if GlobalsGetValue(key, "") ~= tostring(generation) then
        EntityKill(entity)
        return nil, "Could not record the secure case."
    end
    return true, entity
end

local function clean(cases, token, player)
    local kept = false
    for _, entity in ipairs(cases) do
        if not kept and ticket(entity) == token then kept = true
        else discard(entity, player) end
    end
end

function NHCase.ensure(state, player, home_x, home_y)
    if not home_x or not home_y then return true end
    local key = generation_key(state)
    local raw = GlobalsGetValue(key, "")
    local cases = loaded_cases(player)
    if raw == "" then
        -- A world snapshot may already contain the carrier before the world
        -- globals were saved. Re-adopt that item if its token matches this run.
        local newest, current = 0, prefix(state)
        for _, entity in ipairs(cases) do
            local value = ticket(entity)
            if value:sub(1, #current) == current then
                local n = number_of(value:sub(#current + 1))
                if n and n > newest then newest = n end
            end
        end
        if newest == 0 then
            -- With no carrier on record, wait until spawn has streamed in.
            -- If a carrier was already issued, its distant chunk may be unloaded.
            return place_case(state, home_x, home_y, 1)
        end
        raw = tostring(newest)
        GlobalsSetValue(key, raw)
        if GlobalsGetValue(key, "") ~= raw then return nil, "Could not record the secure case." end
    end
    if not number_of(raw) then return nil, "Unreadable secure case record." end
    clean(cases, prefix(state) .. raw, player)
    return true
end

function NHCase.recall(state, player, home_x, home_y)
    local x, y = EntityGetTransform(player)
    if not home_x or not home_y or (x-home_x)^2 + (y-home_y)^2 > 80^2 then
        return nil, "Return to spawn to retrieve the case."
    end
    local ok, reason = NHCase.ensure(state, player, home_x, home_y)
    if not ok then return nil, reason end
    local cases, active = loaded_cases(player), issued(state)
    for _, entity in ipairs(cases) do
        if ticket(entity) == active then
            if EntityGetRootEntity(entity) == player then return nil, "The case is already in your inventory." end
            if NHCase.accessible(state, player, entity) then return nil, "The case is already within reach." end
        end
    end
    local key = generation_key(state)
    local current = tonumber(GlobalsGetValue(key, "0")) or 0
    local ok, result = place_case(state, x, y, current + 1)
    if not ok then return nil, result end
    if not result then return nil, "The spawn area is still loading." end
    clean(cases, prefix(state) .. (current + 1), player)
    return true, result
end
