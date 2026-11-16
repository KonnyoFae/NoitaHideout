-- Two revisioned snapshots in Noita's normal mod settings. A complete
-- readback checks the settings API; it does not force the engine to flush.
NHStore = {}
local max_bytes = 1024 * 1024
local max_depth = 40
local profile_counter = "noita_hideout.profile_count"
local profile_flag = "noita_hideout_profile_"
local cached_profile

local function fresh(profile)
    return {
        version = 1, profile = profile, revision = 0,
        runSerial = 0, rewardedThrough = 0, closedThrough = 0,
        nextItemId = 1, warehouse = {}, safe = {},
        pouch = {location = "safe", doses = 2},
        order = false, finished = 0,
    }
end

local function whole(n)
    return type(n) == "number" and n >= 0 and n <= 9007199254740991 and n == math.floor(n)
end

-- Persistent flags belong to the game's save slot. Mod settings can be shared.
-- Bind a separate settings namespace to each save at its first visit.
local function active_profile()
    if cached_profile and HasFlagPersistent(profile_flag .. cached_profile) then return cached_profile end
    local count = ModSettingGet(profile_counter)
    if count == nil then count = 0 end
    assert(whole(count) and count <= 10000, "Invalid hideout profile directory")
    for id = 1, count do
        if HasFlagPersistent(profile_flag .. id) then
            cached_profile = id
            return id
        end
    end
    -- Do not silently allocate a blank warehouse when shared settings were restored
    -- from an older backup but this save still remembers an existing profile.
    assert(not HasFlagPersistent(profile_flag .. "bound"), "Save profile directory missing. Restore matching settings.")
    local id = count + 1
    assert(id <= 10000, "Hideout profile directory full")
    ModSettingSet(profile_counter, id)
    assert(ModSettingGet(profile_counter) == id, "Cannot reserve a hideout profile")
    AddFlagPersistent(profile_flag .. id)
    assert(HasFlagPersistent(profile_flag .. id), "Cannot bind this Noita save")
    AddFlagPersistent(profile_flag .. "bound")
    assert(HasFlagPersistent(profile_flag .. "bound"), "Cannot verify this Noita save")
    cached_profile = id
    return id
end

local function validate(s)
    assert(type(s) == "table" and s.version == 1, "Unknown profile version")
    for _, k in ipairs({"profile","revision","runSerial","rewardedThrough","closedThrough","nextItemId","finished"}) do
        assert(whole(s[k]), "Invalid profile field: " .. k)
    end
    assert(s.profile >= 1 and s.rewardedThrough <= s.runSerial and s.closedThrough <= s.runSerial
        and s.nextItemId >= 1, "Invalid profile counters")
    assert(type(s.warehouse) == "table" and type(s.safe) == "table", "Invalid inventory")
    assert(type(s.pouch) == "table" and whole(s.pouch.doses), "Invalid injector case")
    assert(s.pouch.location == "safe" or s.pouch.location == "bag" or s.pouch.location == "lost",
           "Invalid injector case location")
    if s.order ~= false then
        assert(type(s.order) == "table" and whole(s.order.progress) and whole(s.order.required)
            and s.order.progress < s.order.required and type(s.order.output) == "table"
            and s.order.output.kind == "potion", "Invalid production order")
    end
end

-- Only strings, finite numbers, booleans and tables. Text is length-prefixed
-- in bytes, so localized names and punctuation need no escaping.
local function encode(root)
    local parts, visiting, bytes = {}, {}, 0
    local function add(fragment)
        bytes = bytes + #fragment
        assert(bytes <= max_bytes, "Prototype profile exceeds 1 MiB")
        parts[#parts + 1] = fragment
    end
    local function put(value, depth)
        assert(depth <= max_depth, "Profile nesting too deep")
        local kind = type(value)
        if kind == "table" then
            assert(not visiting[value], "Cyclic inventory data")
            visiting[value] = true
            add("{")
            for k, v in pairs(value) do
                assert(type(k) == "number" or type(k) == "string", "Unsupported inventory key")
                put(k, depth + 1)
                put(v, depth + 1)
            end
            add("}")
            visiting[value] = nil
        elseif kind == "string" then
            add("s" .. #value .. ":")
            add(value)
        elseif kind == "number" then
            assert(value == value and math.abs(value) < math.huge, "Invalid inventory number")
            local token = string.format("%.17g", value)
            add("n" .. #token .. ":" .. token)
        elseif kind == "boolean" then
            add(value and "t" or "f")
        else
            error("Unsupported inventory data: " .. kind)
        end
    end
    put(root, 0)
    return table.concat(parts)
end

local function decode(payload)
    assert(#payload <= max_bytes, "Profile exceeds size limit")
    local pos = 1
    local function read(depth)
        assert(depth <= max_depth, "Profile nesting too deep")
        local tag = payload:sub(pos, pos)
        pos = pos + 1
        if tag == "s" or tag == "n" then
            local first, last, len = payload:find("^(%d+):", pos)
            assert(first and #len <= 8, "Invalid field length")
            len = tonumber(len)
            assert(last + len <= #payload, "Truncated inventory field")
            local data = payload:sub(last + 1, last + len)
            pos = last + len + 1
            if tag == "s" then return data end
            local n = tonumber(data)
            assert(n and n == n and math.abs(n) < math.huge, "Invalid saved number")
            return n
        elseif tag == "{" then
            local t = {}
            while payload:sub(pos, pos) ~= "}" do
                local key = read(depth + 1)
                assert(type(key) == "number" or type(key) == "string", "Invalid saved key")
                assert(t[key] == nil, "Duplicate saved key")
                t[key] = read(depth + 1)
            end
            pos = pos + 1
            return t
        elseif tag == "t" or tag == "f" then
            return tag == "t"
        end
        error("Damaged inventory data")
    end
    local value = read(0)
    assert(pos == #payload + 1, "Trailing saved data")
    return value
end

local function checksum(data)
    local a, b = 1, 0
    for i = 1, #data do
        a = (a + data:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return tostring(b * 65536 + a)
end

local function unpack_slot(raw)
    assert(type(raw) == "string" and #raw <= max_bytes + 32, "Invalid snapshot")
    local first, last, expected = raw:find("^NH1:(%d+):")
    assert(first, "Invalid snapshot header")
    local payload = raw:sub(last + 1)
    assert(expected == checksum(payload), "Snapshot checksum mismatch")
    local s = decode(payload)
    validate(s)
    return s
end

local function read_slots()
    local profile = active_profile()
    local prefix = "noita_hideout.p" .. profile
    local slots = {prefix .. "_a", prefix .. "_b"}
    local head_key = prefix .. "_revision"
    local head = ModSettingGet(head_key)
    assert(head == nil or whole(head), "Invalid hideout revision")
    local winner, index = nil, nil
    for i, key in ipairs(slots) do
        local raw = ModSettingGet(key)
        if raw ~= nil then
            assert(head ~= nil, "Hideout revision missing; restore a matching backup")
            if type(raw) == "string" then
                local version = raw:match("^NH(%d+):")
                assert(not version or version == "1", "Newer hideout profile. Update the mod.")
            end
            local ok, s = pcall(unpack_slot, raw)
            if ok and s.profile == profile and s.revision == head then
                winner, index = s, i
            end
        end
    end
    assert(head == nil or head == 0 or winner,
        "Latest committed hideout snapshot unavailable; restore a matching backup")
    return winner or fresh(profile), index, slots, head_key
end

function NHStore.load()
    local ok, state = pcall(read_slots)
    if ok then return state end
    return nil, tostring(state)
end

local function write_verified(key, value)
    -- A setter can fail before or after applying its write. Its observed value
    -- determines whether this operation committed.
    local ok, err = pcall(ModSettingSet, key, value)
    assert(ModSettingGet(key) == value, ok and "Settings readback failed" or tostring(err))
end

function NHStore.commit(state)
    local ok, result = pcall(function()
        validate(state)
        local saved, active, slots, head_key = read_slots()
        assert(saved.profile == state.profile, "Save slot changed. Reload the hideout.")
        assert(saved.revision == state.revision, "Profile changed. Reload and retry.")
        local next_state = {}
        for k, v in pairs(state) do next_state[k] = v end
        next_state.revision = saved.revision + 1
        validate(next_state)
        local payload = encode(next_state)
        local raw = "NH1:" .. checksum(payload) .. ":" .. payload
        local key = slots[active == 1 and 2 or 1]
        -- On the very first write, publish the empty revision first. An orphan
        -- first snapshot can then never be mistaken for a successful commit.
        if saved.revision == 0 and ModSettingGet(head_key) == nil then write_verified(head_key, 0) end
        write_verified(key, raw)
        -- This pointer is the commit boundary; a newer unpointed snapshot is staged.
        write_verified(head_key, next_state.revision)
        return next_state.revision
    end)
    if not ok then return nil, tostring(result) end
    state.revision = result
    return true
end

function NHStore.newRun(state)
    NHStore.endRun(state, state.runSerial)
    state.runSerial = state.runSerial + 1
    state.transit = nil
    state.issuedDoses = nil
    return state.runSerial
end

function NHStore.endRun(state, run_id)
    local id = tonumber(run_id)
    if not id or id ~= state.runSerial or id <= state.closedThrough then
        return false, "Run already closed or inactive."
    end
    state.closedThrough = id
    if state.pouch.location == "bag" then
        state.pouch = {location = "lost", doses = 0}
    end
    return true, "Run closed."
end

function NHStore.useDose(state)
    local pouch = state.pouch
    if pouch.location == "lost" or pouch.doses <= 0 then return false, "No dose available." end
    pouch.doses = pouch.doses - 1
    return true, "Used one dose."
end

function NHStore.restock(state)
    state.pouch = {location = "safe", doses = 2}
    return true, "Two test doses placed in secure case."
end

function NHStore.findRecipe(state)
    for i, entry in ipairs(state.warehouse) do
        if entry.item.kind == "potion" and NHPotion.can_refine(entry.item) then return i end
    end
end

-- Select in warehouse order and only use the exact amounts still required.
-- One flask may contribute to both ingredients.
function NHStore.planBatch(state)
    local plan = {}
    for _, ingredient in ipairs(NHPotion.ingredients) do
        local remaining = ingredient.amount
        for i, entry in ipairs(state.warehouse) do
            local flask = entry.item
            if flask.kind == "potion" then
                local available = flask.materials[ingredient.material]
                if whole(available) and available > 0 then
                    local amount = math.min(remaining, available)
                    plan[#plan + 1] = {index = i, material = ingredient.material, amount = amount}
                    remaining = remaining - amount
                    if remaining == 0 then break end
                end
            end
        end
        if remaining > 0 then return nil end
    end
    return plan
end

local function payBatch(state)
    local plan = NHStore.planBatch(state)
    if not plan then return nil, "Not enough ingredients across warehouse flasks." end
    -- Stage the new contents per source. Apply them together only once the
    -- canonical flask recipe has produced a complete order.
    local staged, pool = {}, {kind = "potion", materials = {}}
    for _, charge in ipairs(plan) do
        local index, name = charge.index, charge.material
        if not staged[index] then
            local source = state.warehouse[index].item
            staged[index] = {kind = "potion", materials = {}}
            for k, v in pairs(source.materials) do staged[index].materials[k] = v end
        end
        local removed, err = NHPotion.pour(staged[index], name, charge.amount)
        if not removed then return nil, err end
        pool.materials[name] = (pool.materials[name] or 0) + removed
    end
    local output, err = NHPotion.recipe(pool)
    if not output then return nil, err end
    for index, flask in pairs(staged) do
        local source = state.warehouse[index].item
        source.materials, source.label, source.name = flask.materials, flask.label, flask.name
    end
    return output
end

function NHStore.startOrder(state, index)
    if state.order then return false, "Another order is active." end
    local output, err
    if index == 0 then
        output, err = payBatch(state)
    else
        local entry = state.warehouse[index or NHStore.findRecipe(state)]
        if not entry or entry.item.kind ~= "potion" then return false, "Deposit a flask with both ingredients." end
        output, err = NHPotion.recipe(entry.item)
    end
    if not output then return false, err end
    state.order = {progress = 0, required = 1, output = output}
    return true, "Order paid. One completion will finish it."
end

function NHStore.reward(state, run_id)
    local id = tonumber(run_id)
    if not id or id ~= state.runSerial or id <= state.rewardedThrough or id <= state.closedThrough then
        return false, "Run already settled or inactive."
    end
    state.rewardedThrough = id
    if state.order == false then return true, "Completion recorded. No active order." end
    state.order.progress = state.order.progress + 1
    if state.order.progress >= state.order.required then
        state.warehouse[#state.warehouse + 1] = {id = state.nextItemId, item = state.order.output}
        state.nextItemId = state.nextItemId + 1
        state.order = false
        state.finished = state.finished + 1
        return true, "Order finished. Refined flask stored in warehouse."
    end
    return true, "Order advanced."
end
