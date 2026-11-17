-- Two revisioned snapshots in Noita's normal mod settings. A complete
-- readback checks the settings API; it does not force the engine to flush.
NHStore = {}
NHEquipment=dofile("mods/noita_hideout/files/equipment.lua")
dofile("mods/noita_hideout/files/companions.lua")
dofile("mods/noita_hideout/files/affinity.lua")
dofile("mods/noita_hideout/files/card_wallets.lua")
NHInjectors=dofile("mods/noita_hideout/files/injectors.lua")
NHMedkits=dofile("mods/noita_hideout/files/medkits.lua")
NHSurgeryKits=dofile("mods/noita_hideout/files/surgery_kits.lua")
NHThrowables=dofile("mods/noita_hideout/files/throwables.lua")
NHDragonLoot=dofile("mods/noita_hideout/files/dragon_loot.lua")
NHGelPool=dofile("mods/noita_hideout/files/gel_pool.lua")
dofile("mods/noita_hideout/files/farming.lua")
dofile("mods/noita_hideout/files/essences.lua")
dofile("mods/noita_hideout/files/pouches.lua")
local progression=dofile("mods/noita_hideout/files/progression.lua")
local max_bytes = 1024 * 1024
local max_depth = 40
local max_safe_integer = 9007199254740991
local profile_counter = "noita_hideout.profile_count"
local profile_flag = "noita_hideout_profile_"
local cached_profile

NHStore.doseDurability = 3
NHStore.checkpointFrames = 60 * 60
NHStore.maxGold = max_safe_integer
NHStore.maxMaterialAmount = max_safe_integer
NHStore.maxResourceAmount = max_safe_integer

function NHStore.productionFrames(recipe)
    -- Pre-timer saves used the original two-minute batch when converting progress to frames.
    local frames=(recipe and recipe.durationFrames) or 2 * 60 * 60
    return math.min(frames, 3 * 60 * 60)
end

local function fresh(profile)
    local s={
        version = 1, profile = profile, revision = 0,
        runSerial = 0, closedThrough = 0, checkpoints = {},
        nextItemId = 1, materials = {}, docks = {}, warehouse = {}, safe = {}, safeCapacity = 2, sharedSlots = true, collectionSlots=true,
        pouches = {},
        order = false, finished = 0, levels = {}, storageBase = {}, resources = {}, farm={time=0,plots={},passive=true}, bankGold = 0, bankWalletNet = 0,
    }
    s.starterPouchId=NHPouches.create(s,"safe",2,2)
    return s
end

local function whole(n)
    return type(n) == "number" and n >= 0 and n <= max_safe_integer and n == math.floor(n)
end

function NHStore.validBandageCount(n)
    -- The physical item stores the rolls in ItemComponent.uses_remaining (int32).
    return whole(n) and n>=1 and n<=2147483647
end

-- Mutate the same detached profile draft as the transfer or shop purchase.
function NHStore.creditGold(s,amount)
    if not whole(amount) or amount==0 then return false,"Invalid gold amount." end
    if amount>NHStore.maxGold-s.bankGold then return false,"Piggy bank is full." end
    s.bankGold=s.bankGold+amount
    return true
end

function NHStore.spendGold(s,amount)
    if not whole(amount) or amount==0 then return false,"Invalid gold amount." end
    if amount>s.bankGold then return false,"Not enough stored gold." end
    s.bankGold=s.bankGold-amount
    return true
end

function NHStore.safeCapacity(s)
    return s.safeCapacity or 1
end

-- Call on the same draft as the upgrade payment, then commit both together.
function NHStore.expandSafe(s, capacity)
    if not whole(capacity) or capacity < NHStore.safeCapacity(s) then
        return false, "Invalid secure inventory upgrade."
    end
    s.safeCapacity = capacity
    return true
end

function NHStore.safeIndex(s, slot)
    for index, row in ipairs(s.safe) do
        if (row.slot or 1) == slot then return index end
    end
end

function NHStore.freeSafeSlot(s, preferred)
    local capacity = NHStore.safeCapacity(s)
    if preferred and (not whole(preferred) or preferred<1 or preferred>capacity) then return nil end
    for i=preferred or 1,preferred or capacity do
        if not NHStore.safeIndex(s,i) and not NHPouches.at(s,"safe",i) then return i end
    end
end

-- Each item kind resolves to one warehouse grid for both live items and saved rows.
NHStore.itemCategories={wand="wand",spell="spell",potion="containers",pouch="equipment",summon_card="collection"}
NHStore.itemCategories.card_wallet="equipment"
NHStore.itemCategories.remote_terminal="equipment"
function NHStore.category(kind)
    return NHStore.itemCategories[kind] or "supplies"
end

local function warehouse_grids()
    return {wand={},spell={},containers={},supplies={},equipment={},collection={}}
end

function NHStore.slotIndex(s,container,slot,kind)
    if container=="safe" then return NHStore.safeIndex(s,slot) end
    if container=="docks" then
        for i,row in ipairs(s.docks or {}) do if row.slot==slot then return i end end
        return
    end
    local category=NHStore.category(kind)
    for index,row in ipairs(s.warehouse) do
        if NHStore.category(row.item.kind)==category and (row.slot or index)==slot then return index end
    end
end

function NHStore.freeSlot(s,container,preferred,kind)
    if container=="safe" then return NHStore.freeSafeSlot(s,preferred) end
    if container=="docks" then
        if kind=="potion" and (preferred==1 or preferred==2) and not NHStore.slotIndex(s,"docks",preferred) then return preferred end
        return
    end
    local occupied={}
    local category=NHStore.category(kind)
    if category=="equipment" then
        for _,pouch in pairs(s.pouches) do
            if pouch.location=="warehouse" then occupied[pouch.slot]=true end
        end
    end
    for i,row in ipairs(s.warehouse) do
        if NHStore.category(row.item.kind)==category then occupied[row.slot or i]=true end
    end
    local output=s.order and s.order.output
    if output and output.item and NHStore.category(output.item.kind)==category then occupied[output.slot]=true end
    local capacity=NHStore.warehouseCapacity(s,category)
    if preferred then
        if whole(preferred) and preferred>=1 and preferred<=capacity and not occupied[preferred] then return preferred end
        return nil
    end
    local slot=1
    while occupied[slot] do slot=slot+1 end
    if slot<=capacity then return slot end
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
    for _, k in ipairs({"profile","revision","runSerial","closedThrough","nextItemId","finished"}) do
        assert(whole(s[k]), "Invalid profile field: " .. k)
    end
    assert(s.profile >= 1 and s.closedThrough <= s.runSerial
        and s.nextItemId >= 1, "Invalid profile counters")
    assert(whole(s.bankGold),"Invalid piggy bank balance")
    assert(type(s.bankWalletNet)=="number" and whole(math.abs(s.bankWalletNet)),"Invalid wallet transfer total")
    assert(type(s.checkpoints)=="table","Invalid Holy Mountain checkpoints")
    NHCompanions.validate(s,whole)
    NHDragonLoot.validate(s,whole)
    NHGelPool.validate(s,whole)
    NHAffinity.validate(s,whole)
    for key,visited in pairs(s.checkpoints) do
        assert(type(key)=="string" and key~="" and visited==true,"Invalid Holy Mountain checkpoint")
    end
    assert(type(s.warehouse) == "table" and type(s.safe) == "table", "Invalid inventory")
    assert(type(s.materials)=="table" and type(s.docks)=="table","Invalid bulk storage")
    progression.validate(s,whole)
    NHFarm.validate(s,whole)
    local function validateConsumable(item)
        if NHMedkits.types[item.kind] then
            assert(NHMedkits.validUses(item.kind,NHMedkits.remaining(item)) and (item.count==nil or item.count==1),"Invalid medkit.")
        elseif NHSurgeryKits.types[item.kind] then
            assert(item.remaining==NHSurgeryKits.types[item.kind].uses and (item.count==nil or item.count==1),"Invalid surgery kit.")
        elseif item.kind=="bandage" and item.count~=nil then
            assert(NHStore.validBandageCount(item.count),"Invalid bandage count.")
        elseif NHThrowables.types[item.kind] then
            assert(NHThrowables.validCount(NHThrowables.count(item)),"Invalid throwable count.")
        elseif item.kind=="remote_terminal" then
            assert(NHEquipment.validRemoteUses(item.remaining) and (item.count==nil or item.count==1),"Invalid remote terminal.")
        end
    end
    for _,rows in ipairs({s.safe,s.warehouse}) do
        for _,row in ipairs(rows) do
            if row.item.kind=="card_wallet" then assert(NHCardWallets.valid(row.item),"Invalid card wallet") end
            validateConsumable(row.item)
        end
    end
    if s.transit then
        for _,release in pairs(s.transit.issued) do
            if release.row.item.kind=="card_wallet" then assert(NHCardWallets.valid(release.row.item),"Invalid issued card wallet") end
            validateConsumable(release.row.item)
        end
    end
    for name,amount in pairs(s.materials) do
        assert(type(name)=="string" and name~="" and whole(amount) and amount>0,"Invalid material stock")
    end
    local occupied={}
    for _,row in ipairs(s.docks) do
        assert((row.slot==1 or row.slot==2) and row.slot==NHPotion.dockSlot(row.item) and not occupied[row.slot],"Invalid docked container")
        occupied[row.slot]=true
    end
    local capacity, seen = NHStore.safeCapacity(s), {}
    assert(whole(capacity) and capacity>=1, "Invalid secure inventory capacity")
    for _,row in ipairs(s.safe) do
        local slot = row.slot or 1
        if row.item.kind=="summon_card" then assert(NHCompanions.validCard(row.item),"Invalid summon card") end
        assert(row.item.kind~="pouch" and whole(slot) and slot>=1 and slot<=capacity and not seen[slot],"Invalid secure inventory slot")
        seen[slot]=true
    end
    local function validDose(remaining,count,subtype)
        return (subtype==nil or NHInjectors.types[subtype]~=nil)
            and whole(remaining) and remaining>=1 and remaining<=NHStore.doseDurability
            and whole(count) and count>=1 and (remaining==NHStore.doseDurability or count==1)
    end
    NHPouches.validate(s,whole,validDose)
    for _,row in ipairs(s.safe) do
        if row.item.kind=="dose" then assert(validDose(row.item.remaining or NHStore.doseDurability,row.item.count or 1,row.item.subtype),"Invalid stored injector") end
    end
    local warehouseSlots=warehouse_grids()
    for _,pouch in pairs(s.pouches) do
        if pouch.location=="warehouse" then warehouseSlots.equipment[pouch.slot]=true
        elseif s.sharedSlots and pouch.location=="safe" then
            assert(not seen[pouch.slot],"Secure slot already occupied")
        end
    end
    for i,row in ipairs(s.warehouse) do
        local slot=row.slot or i
        local used=warehouseSlots[NHStore.category(row.item.kind)]
        if row.item.kind=="summon_card" then assert(NHCompanions.validCard(row.item),"Invalid summon card") end
        assert(row.item.kind~="pouch" and whole(slot) and slot>=1 and slot<=NHStore.warehouseCapacity(s,NHStore.category(row.item.kind)) and not used[slot],"Invalid warehouse slot")
        used[slot]=true
        if row.item.kind=="dose" then assert(validDose(row.item.remaining or NHStore.doseDurability,row.item.count or 1,row.item.subtype),"Invalid warehouse injector") end
    end
    for _,record in pairs(s.issuedDoses or {}) do
        assert(validDose(record.remaining or NHStore.doseDurability,1,record.subtype),"Invalid issued injector")
    end
    if s.order ~= false then
        assert(type(s.order) == "table" and s.order.id==s.finished+1 and whole(s.order.progress) and whole(s.order.required)
            and s.order.progress < s.order.required and type(s.order.output) == "table", "Invalid production order")
        local output=s.order.output
        if output.item then
            validateConsumable(output.item)
            if output.item.kind=="pouch" or output.item.kind=="card_wallet" then
                assert(NHEquipment.get(output.item.kind,output.item.tier),"Invalid equipment output tier")
            end
            if output.item.kind=="dose" then
                assert(validDose(output.item.remaining or NHStore.doseDurability,output.item.count or 1,output.item.subtype),"Invalid injector output")
            end
            local category=NHStore.category(output.item.kind)
            assert(type(output.item.kind)=="string" and not output.materials and whole(output.slot) and output.slot>=1
                and output.slot<=NHStore.warehouseCapacity(s,category) and not warehouseSlots[category][output.slot],
                "Invalid reserved production slot")
        else
            assert(type(output.materials)=="table" and next(output.materials),"Missing order yield")
            for name,amount in pairs(output.materials) do
                assert(type(name)=="string" and whole(amount) and amount>0,"Invalid order yield")
            end
        end
        if s.order.catalysts then
            assert(type(s.order.catalysts)=="table" and type(output.materials)=="table","Invalid held catalyst")
            for name,amount in pairs(s.order.catalysts) do
                assert(whole(amount) and amount>0 and (output.materials[name] or 0)>=amount,"Invalid held catalyst")
            end
        end
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
    if s.bankGold==nil then s.bankGold=0 end
    if s.bankWalletNet==nil then s.bankWalletNet=0 end
    if s.checkpoints==nil then
        -- The previous format counted one world clear per order. Keep its already
        -- paid output and reservation while converting that unit into gameplay frames.
        if s.order then
            local order=s.order
            assert(whole(order.required) and whole(order.progress) and order.progress<order.required,"Invalid legacy order")
            local duration=NHStore.productionFrames()
            order.id=s.finished+1
            order.progress=math.floor(duration*order.progress/order.required)
            order.required=duration
        end
        s.checkpoints={}
        s.rewardedThrough=nil
    end
    s.materials,s.docks=s.materials or {},s.docks or {}
    NHPouches.adopt(s)
    -- Old warehouse records had only a list order. Give them stable grid positions.
    local used=warehouse_grids()
    for _,pouch in pairs(s.pouches) do
        if pouch.location=="warehouse" then used.equipment[pouch.slot]=true end
    end
    for _,row in ipairs(s.warehouse) do
        if row.slot then used[NHStore.category(row.item.kind)][row.slot]=true end
    end
    local cursor={}
    for _,row in ipairs(s.warehouse) do
        if not row.slot then
            local category=NHStore.category(row.item.kind)
            local slot=cursor[category] or 1
            while used[category][slot] do slot=slot+1 end
            row.slot,used[category][slot],cursor[category]=slot,true,slot+1
        end
    end
    progression.adopt(s)
    if not s.collectionSlots then
        -- Previous cards occupied equipment slots. Preserve every card's ID and
        -- actual charges, including profiles with an expanded equipment grid.
        local n=0
        for _,row in ipairs(s.warehouse) do
            if row.item.kind=="summon_card" then n=n+1; row.slot=n end
        end
        if n>NHStore.warehouseCapacity(s,"collection") then s.storageBase.collection=n end
        s.collectionSlots=true
    end
    if s.farm==nil then s.farm={time=0,plots={}} end
    NHFarm.adopt(s.farm)
    if not s.sharedSlots then
        s.safeCapacity = NHStore.safeCapacity(s)+1
        s.sharedSlots = true
        local starter=s.pouches[s.starterPouchId]
        if starter and starter.location=="safe" then starter.slot=s.safeCapacity end
    end
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
        NHCompanions.stageDelivery(next_state)
        NHDragonLoot.stageDelivery(next_state)
        NHGelPool.stageDelivery(next_state)
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
        return next_state
    end)
    if not ok then return nil, tostring(result) end
    state.revision,state.nextItemId=result.revision,result.nextItemId
    state.warehouse,state.summons,state.dragonLoot=result.warehouse,result.summons,result.dragonLoot
    state.gelBonus,state.resources=result.gelBonus,result.resources
    return true
end

function NHStore.newRun(state)
    NHStore.endRun(state, state.runSerial)
    state.runSerial = state.runSerial + 1
    state.bankWalletNet = 0
    state.checkpoints = {}
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
    NHPouches.endRun(state)
    return true, "Run closed."
end

-- Replace cell records on edits so a failed commit cannot mutate a live stack.
function NHStore.acceptsDose(cell, remaining, subtype)
    return not cell or ((cell.subtype or "fire")==(subtype or "fire") and remaining==NHStore.doseDurability
        and (cell.remaining or NHStore.doseDurability)==remaining and (cell.count or 1)<max_safe_integer)
end

function NHStore.putPouchDose(pouch, remaining, slot, subtype)
    if pouch.location=="lost" then return false end
    local capacity=NHEquipment.get("pouch",pouch.tier).capacity
    if slot==nil then
        for i=1,capacity do
            if pouch.cells[i] and NHStore.acceptsDose(pouch.cells[i],remaining,subtype) then slot=i; break end
        end
        if not slot then
            for i=1,capacity do if not pouch.cells[i] then slot=i; break end end
        end
    end
    if not whole(slot) or slot<1 or slot>capacity then return false end
    local cell=pouch.cells[slot]
    if not NHStore.acceptsDose(cell,remaining,subtype) then return false end
    pouch.cells[slot]={remaining=remaining,subtype=subtype,count=(cell and cell.count or 0)+1}
    pouch.doses=pouch.doses+1
    return true
end

function NHStore.takePouchDose(pouch,slot)
    local cell=pouch.cells[slot]
    if not cell or pouch.location=="lost" then return nil end
    pouch.cells[slot]=cell.count>1 and {count=cell.count-1,remaining=cell.remaining,subtype=cell.subtype} or nil
    pouch.doses=pouch.doses-1
    return cell.remaining,cell.subtype
end

NHStore.restock=NHPouches.restock

-- Scale every part of a reversible reaction together so splitting the full
-- output returns the exact amount purchased, including for small rare batches.
local function alchemyBatch(id,zh,en,product,ingredients,units,seconds)
    local inputs={}
    for _,name in ipairs(ingredients) do
        inputs[#inputs+1]={name=name,amount=units}
    end
    local yield=units*#inputs
    return {id=id,category="alchemy",alchemyMode="synthesis",zh=zh,en=en,inputs=inputs,
        materials={[product]=yield},count=yield,reversible=true,durationFrames=seconds*60}
end

local function catalyticBatch(id,zh,en,ingredient,catalyst,product,units,seconds)
    return {id=id,category="alchemy",alchemyMode="synthesis",zh=zh,en=en,
        inputs={{name=ingredient,amount=units}},catalysts={{name=catalyst,amount=1}},
        materials={[product]=units},count=units,durationFrames=seconds*60}
end

local function farmItem(kind)
    return {kind=kind,name="$nh_hideout_"..kind,icon="mods/noita_hideout/files/items/"..kind..".png"}
end
local medkit=NHMedkits.item("medkit")
local medkit_frames=5 * 60
local bandage_bundle=farmItem("bandage")
bandage_bundle.count=8

-- Inputs and the paid order are committed together. Only loose stock is spendable.
NHStore.recipes={
    alchemyBatch("stable","稳定传送液","Teleportatium","magic_liquid_teleportation",
        {"magic_liquid_unstable_teleportation","slime"},250,8),
    alchemyBatch("flummoxium","除草基质","Flummoxium","material_confusion",
        {"magic_liquid_worm_attractor","blood_worm"},100,10),
    alchemyBatch("pheromone","费洛蒙","Pheromone","magic_liquid_charm",
        {"material_confusion","magic_liquid_berserk"},100,15),
    -- Copper is a powder in the vanilla [sand_metal] group. Naming one metal
    -- keeps the recovered ingredient unambiguous when a batch is decomposed.
    alchemyBatch("levitatium","漂浮基质","Levitatium","magic_liquid_faster_levitation",
        {"material_confusion","copper"},100,15),
    {id="levitatium_metals",category="alchemy",alchemyMode="synthesis",zh="漂浮基质（替代金属粉）",en="Levitatium (metal powders)",
        inputs={{name="material_confusion",amount=100},{name="metal_sand",amount=100,
            alternatives={"metal_sand","steel_sand","brass","silver","gold_radioactive","gold","diamond"},
            labelZh="替代金属粉",labelEn="Metal powders"}},
        materials={magic_liquid_faster_levitation=200},count=200,durationFrames=15*60,
        noteZh="分解漂浮基质固定返还除草基质和铜。",noteEn="Decomposition always returns flummoxium and copper."},
    alchemyBatch("hastium","迅速基质","Hastium","magic_liquid_faster_levitation_and_movement",
        {"magic_liquid_faster_levitation","magic_liquid_movement_faster"},100,30),
    alchemyBatch("unstable_polymorphine","不稳变形魔药","Unstable polymorphine","magic_liquid_unstable_polymorph",
        {"material_confusion","blood","oil"},100,30),
    alchemyBatch("diminution","缩小","Diminution","magic_liquid_weakness",
        {"vomit","bone"},100,8),
    {id="ambrosia",category="alchemy",alchemyMode="synthesis",zh="灵丹妙药",en="Ambrosia",
        inputs={{name="honey",amount=50},{name="diamond",amount=50}},
        materials={magic_liquid_protection_all=50,poison=50},count=100,reversible=true,durationFrames=90*60},
    catalyticBatch("mana","扩制汇聚法力","Multiply concentrated mana",
        "water","magic_liquid_mana_regeneration","magic_liquid_mana_regeneration",100,8),
    catalyticBatch("chaotic_polymorphine","混乱变形魔药","Chaotic polymorphine",
        "magic_liquid_polymorph","radioactive_liquid","magic_liquid_random_polymorph",100,45),
    catalyticBatch("midas","扩制点金之水","Multiply Draught of Midas",
        "midas_precursor","midas","midas",100,180),
    alchemyBatch("purifying_powder","净化粉末","Purifying powder","purifying_powder",{"brass","diamond"},50,45),
    {id="purifying_powder_silver",category="alchemy",alchemyMode="synthesis",zh="净化粉末（银）",en="Purifying powder (silver)",
        inputs={{name="diamond",amount=50},{name="silver",amount=50},{name="blood_worm",amount=50}},
        materials={purifying_powder=50},count=50,durationFrames=60*60,
        noteZh="烟雾在反应中逸散。",noteEn="Smoke dissipates during the reaction."},
    {id="guiding_powder",category="alchemy",alchemyMode="synthesis",zh="导引粉末",en="Guiding powder",
        inputs={{name="material_confusion",amount=100},{name="magic_liquid_unstable_teleportation",amount=100}},
        materials={orb_powder=100},count=100,durationFrames=30*60,
        noteZh="反应产生的火焰会消散。",noteEn="Fire dissipates during the reaction."},
    {id="void_diamond",category="alchemy",alchemyMode="synthesis",zh="虚无液体（钻石）",en="Void liquid (diamond)",
        inputs={{name="diamond",amount=50},{name="magic_liquid_random_polymorph",amount=50},{name="radioactive_liquid",amount=50}},
        materials={void_liquid=150},count=150,durationFrames=120*60},
    {id="void_fungus",category="alchemy",alchemyMode="synthesis",zh="虚无液体（怪异真菌）",en="Void liquid (weird fungus)",
        inputs={{name="radioactive_liquid",amount=50},{name="blood_worm",amount=50},{name="fungi",amount=50}},
        materials={void_liquid=100},count=100,durationFrames=120*60,
        noteZh="每三份原料回收两份液体。",noteEn="Three parts of ingredients yield two parts of liquid."},
    {id="medical",category="medical",facility="medical",zh=NHMedkits.types.medkit.zh,en=NHMedkits.types.medkit.en,durationFrames=medkit_frames,
        inputs={{name="water",amount=100},{name="blood",amount=50}},item=medkit,
        noteZh="每包可使用 3 次，每次最多恢复 10 生命。",noteEn="Three uses per kit. Each restores up to 10 HP."},
    {id="bandage",category="medical",facility="medical",zh="绷带",en="Bandage",durationFrames=3 * 60,
        inputs={},resources={fiber=4,sugar=2},item=bandage_bundle,count=bandage_bundle.count,
        noteZh="每用一卷最多恢复 5 生命。",noteEn="Each roll restores up to 5 HP."},
    {id="field_medkit",category="medical",facility="medical",zh="小医疗包（绷带与草药）",en="Medkit (bandage and herbs)",durationFrames=medkit_frames,
        inputs={},resources={herb=2},storedIngredient="bandage",item=medkit,
        noteZh="每包可使用 3 次，每次最多恢复 10 生命。",noteEn="Three uses per kit. Each restores up to 10 HP."},
    NHMedkits.upgradeRecipe("tactical_medkit","medkit",4,2,60),
    NHMedkits.upgradeRecipe("advanced_medkit","tactical_medkit",8,3,180),
    NHSurgeryKits.recipe("field_surgery_kit"),
    NHSurgeryKits.recipe("tactical_surgery_kit"),
    NHSurgeryKits.recipe("advanced_surgery_kit"),
    NHThrowables.recipe("grenade",{{name="sand",amount=64},{name="slime",amount=32}}),
    NHThrowables.recipe("grenade",nil,{essence_high_energy=4},"grenade_essence","魔法手雷（高能精华）","Magic grenade (high-energy essence)"),
    NHThrowables.recipe("fire_grenade",nil,{essence_fire=6}),
    NHThrowables.recipe("frost_grenade",nil,{essence_frost=6}),
    NHThrowables.recipe("shock_grenade",nil,{essence_lightning=6}),
    NHThrowables.recipe("sand_knife",{{name="sand",amount=40}}),
    NHThrowables.recipe("metal_knife",{{name="metal_sand",amount=64,
        alternatives={"metal_sand","steel_sand","copper","brass","silver"},labelZh="金属粉",labelEn="Metal powders"}}),
}
for _,id in ipairs(NHInjectors.order) do
    NHStore.recipes[#NHStore.recipes+1]=NHInjectors.recipe(id)
end
for _,kind in ipairs({"pouch","card_wallet"}) do
    for _,d in ipairs(NHEquipment[kind]) do
        local isPouch=kind=="pouch"
        NHStore.recipes[#NHStore.recipes+1]={id=d.filename,category="equipment",facility=isPouch and "injector" or "farmland",
            zh="空"..d.zh,en="Empty "..d.en:gsub("^%u",string.lower),durationFrames=d.workSeconds*60,
            inputs=isPouch and {{name=d.ingredient,amount=d.amount}} or {},
            resources=not isPouch and {[d.ingredient]=d.amount} or nil,emptyContainers=d.emptyContainers,
            item=isPouch and {kind=kind,tier=d.tier,icon=d.icon,name=d.name} or NHCardWallets.empty(d.tier),
            noteZh=d.capacity.." 格，制作完成后空容器存入装备库。",
            noteEn=d.capacity.." slots. Delivered empty to equipment storage."}
    end
end
local terminal=NHEquipment.remoteTerminal
NHStore.recipes[#NHStore.recipes+1]={id="remote_terminal",category="equipment",zh=terminal.zh,en=terminal.en,
    inputs={},resources={essence_displacement=10},goldCost=100,durationFrames=30*60,
    item=NHEquipment.remoteItem(),noteZh=terminal.noteZh,noteEn=terminal.noteEn}
for _,food in ipairs(dofile("mods/noita_hideout/files/cooking.lua")) do
    NHStore.recipes[#NHStore.recipes+1]={id=food.id,category="food",facility=food.facility,zh=food.zh,en=food.en,
        durationFrames=food.workSeconds*60,inputs={},resources=food.resources,item=farmItem(food.id),noteZh=food.noteZh,noteEn=food.noteEn}
end
NHStore.recipe=NHStore.recipes[1]

-- A reversible material recipe spends the entire original yield and returns
-- exactly one batch of its original ingredients. Items are never disassembled here.
local function reverseRecipe(recipe)
    assert(recipe.category=="alchemy" and not recipe.item and not recipe.emptyContainers and not recipe.catalysts
        and type(recipe.materials)=="table" and next(recipe.materials) and #recipe.inputs>0,
        "Only bulk alchemy recipes can be reversed")
    local inputs={}
    for name,amount in pairs(recipe.materials) do
        inputs[#inputs+1]={name=name,amount=amount}
    end
    table.sort(inputs,function(a,b) return a.name<b.name end)
    local materials,count={},0
    for _,input in ipairs(recipe.inputs) do
        materials[input.name]=(materials[input.name] or 0)+input.amount
        count=count+input.amount
    end
    return {id="reverse_"..recipe.id,reverseOf=recipe.id,category=recipe.category,alchemyMode="decomposition",facility=recipe.facility,
        zh="分解"..recipe.zh,en="Decompose "..recipe.en,inputs=inputs,materials=materials,count=count,
        durationFrames=recipe.durationFrames}
end

for i=1,#NHStore.recipes do
    local recipe=NHStore.recipes[i]
    if recipe.reversible then table.insert(NHStore.recipes,reverseRecipe(recipe)) end
end

table.insert(NHStore.recipes,{
    id="separate_gunpowder",category="alchemy",alchemyMode="decomposition",zh="分解火药",en="Separate gunpowder",
    inputs={{name="gunpowder",amount=200}},
    materials={magic_liquid_hp_regeneration=100,purifying_powder=100},count=200,durationFrames=90*60,
})

for _,recipe in ipairs(dofile("mods/noita_hideout/files/spell_recipes.lua")) do
    NHStore.recipes[#NHStore.recipes+1]=recipe
end

local function findRecipe(id)
    for _,recipe in ipairs(NHStore.recipes) do if recipe.id==id then return recipe end end
end

local function materialGood(material,zh,en,price)
    return {id=material,material=material,zh=zh,en=en,category="materials",price=price,quantity=250}
end

local function supplyGood(id,recipeId,price)
    local recipe=findRecipe(recipeId)
    return {id=id,item=recipe.item,zh=recipe.zh,en=recipe.en,category="supplies",price=price,quantity=1}
end

NHStore.shopGoods={
    materialGood("water","水","Water",20),
    materialGood("sand","沙","Sand",25),
    materialGood("oil","油","Oil",40),
    materialGood("slime","黏液","Slime",50),
    supplyGood("medkit","medical",120),
    supplyGood("injector","injector",160),
    {id="chick",animal="chick",zh="小鸡",en="Chick",category="livestock",price=120,quantity=1},
    {id="calf",animal="calf",zh="牛犊",en="Calf",category="livestock",price=240,quantity=1},
    {id="queen_bee",animal="queen_bee",zh="女王蜂",en="Queen bee",category="livestock",price=480,quantity=1},
    {id="dragon_egg",animal="dragon_egg",zh="龙蛋",en="Dragon egg",category="livestock",price=3000,quantity=1},
    {id="gel_pool",animal="gel_pool",zh="凝胶幼体",en="Gel hatchling",category="livestock",price=320,quantity=1},
}

function NHStore.stockDoseSlot(state,subtype)
    for index,row in ipairs(state.warehouse) do
        if row.item.kind=="dose" and NHStore.acceptsDose(row.item,NHStore.doseDurability,subtype) then
            return row.slot or index,index
        end
    end
    if state.nextItemId<max_safe_integer then return NHStore.freeSlot(state,"warehouse",nil,"dose") end
end

function NHStore.canBuyGood(state,good)
    if good.animal then
        local slot,reason=NHLivestock.freePen(state,good.animal)
        if not slot then return false,reason end
        if state.bankGold<good.price then return false,"Not enough stored gold." end
        return true,slot
    end
    if state.bankGold<good.price then return false,"Not enough stored gold." end
    if good.material then
        local incoming={[good.material]=good.quantity}
        if not NHStore.canStockMaterials(state,incoming) then return false,"Material storage is full." end
        return true
    end
    local kind=good.item.kind
    if kind=="dose" then
        local slot,index=NHStore.stockDoseSlot(state,good.item.subtype)
        if slot then return true,slot,index and state.warehouse[index] end
        return false,"Supplies storage is full."
    end
    local slot=NHStore.freeSlot(state,"warehouse",nil,kind)
    if not slot or state.nextItemId>=max_safe_integer then return false,"Supplies storage is full." end
    return true,slot
end

local function stockItem(state,slot,item)
    table.insert(state.warehouse,{id=state.nextItemId,slot=slot,item=item})
    state.nextItemId=state.nextItemId+1
end

function NHStore.grantTestWallet(state)
    local slot=NHStore.freeSlot(state,"warehouse",nil,"card_wallet")
    if not slot then return false,"Equipment storage is full." end
    if state.nextItemId>=max_safe_integer then return false,"Item ID limit reached." end
    stockItem(state,slot,NHCardWallets.empty())
    return true
end

-- The request names the offer. Price, quantity and destination come from the
-- catalog and are checked on the same draft that pays and receives the goods.
function NHStore.buyGood(state,request,now)
    if type(request)~="table" then return false,"Unknown shop item." end
    local good
    for _,offer in ipairs(NHStore.shopGoods) do
        if offer.id==request.id then good=offer; break end
    end
    if not good then return false,"Unknown shop item." end
    local ready,slot,stack=NHStore.canBuyGood(state,good)
    if not ready then return false,slot end
    if good.animal then
        if request.pen~=nil and request.pen~=slot then return false,"Livestock collection changed." end
        if not NHLivestock.deliver(state,good.animal,slot,now) then return false,"Livestock collection changed." end
        return NHStore.spendGold(state,good.price)
    end
    local paid,reason=NHStore.spendGold(state,good.price)
    if not paid then return false,reason end
    if good.material then
        state.materials[good.material]=(state.materials[good.material] or 0)+good.quantity
    elseif stack then
        stack.item={kind="dose",subtype=good.item.subtype,remaining=NHStore.doseDurability,count=(stack.item.count or 1)+1}
    else
        local item={}
        for key,value in pairs(good.item) do item[key]=value end
        stockItem(state,slot,item)
    end
    return true
end

-- Only recipe costs share these stocks. Stored materials and outputs keep their own IDs.
local gunpowderGroup={alternatives={"gunpowder_unstable","gunpowder"},labelZh="火药",labelEn="Gunpowder"}
local defaultIngredientGroups={gunpowder=gunpowderGroup,gunpowder_unstable=gunpowderGroup}
-- Construction and finished goods use physical supplies. Alchemy keeps the
-- material IDs of its reactions and returns, except for explicit substitutes.
local bulkSupplies={
    sand={alternatives={"sand","sandstone","sandstone_surface","sand_surface","sand_petrify","sand_blue"},
        labelZh="砂石",labelEn="Sand and sandstone"},
    soil={alternatives={"soil","soil_lush","soil_lush_dark"},labelZh="泥土",labelEn="Soil"},
    water={alternatives={"water","water_fading","water_temp"},labelZh="清水",labelEn="Fresh water"},
    slime={alternatives={"slime","slime_green","slime_yellow"},labelZh="黏液",labelEn="Slime"},
    blood={alternatives={"blood","blood_fading"},labelZh="血液",labelEn="Blood"},
}

function NHStore.ingredientSources(input,category)
    local group=input.alternatives and input or defaultIngredientGroups[input.name]
        or (category and category~="alchemy" and bulkSupplies[input.name]) or input
    return group.alternatives or {input.name},input.labelZh or group.labelZh,input.labelEn or group.labelEn
end

function NHStore.ingredientStock(state,input,category)
    local total=0
    for _,name in ipairs(NHStore.ingredientSources(input,category)) do
        total=total+math.min(state.materials[name] or 0,max_safe_integer-total)
    end
    return total
end

function NHStore.allocateIngredient(stock,sources,needed,payment)
    for _,name in ipairs(sources) do
        local allocated=payment[name] or 0
        local take=math.min(needed,(stock[name] or 0)-allocated)
        if take>0 then payment[name]=allocated+take end
        needed=needed-take
        if needed==0 then return true end
    end
    return false
end

-- If the preferred payment cannot free room, consuming the smallest stocks
-- first clears the most alternative type slots for a given ingredient amount.
local function smallestFirst(stock,sources,payment)
    local sorted,priority={},{}
    for i,name in ipairs(sources) do sorted[i],priority[name]=name,i end
    table.sort(sorted,function(a,b)
        local left=(stock[a] or 0)-(payment[a] or 0)
        local right=(stock[b] or 0)-(payment[b] or 0)
        if left==right then return priority[a]<priority[b] end
        return left<right
    end)
    return sorted
end

local function batchPayment(stock,recipe,held,freeSlots)
    local payment,alternative={},false
    for name,amount in pairs(held or {}) do payment[name]=amount end
    for _,input in ipairs(recipe.inputs) do
        local sources=NHStore.ingredientSources(input,recipe.category)
        if #sources>1 then
            alternative=true
            if freeSlots then sources=smallestFirst(stock,sources,payment) end
        end
        if not NHStore.allocateIngredient(stock,sources,input.amount,payment) then return nil end
    end
    return payment,alternative
end

function NHStore.warehouseIngredientCount(state,kind)
    local count,firstIndex,firstSlot,bestRank=0,nil,nil,nil
    local kit=NHMedkits.types[kind]
    for i,row in ipairs(state.warehouse) do
        local remaining=kit and NHMedkits.remaining(row.item)
        if row.item.kind==kind and (not kit or NHMedkits.validUses(kind,remaining)) then
            local quantity=row.item.count or 1
            count=count+quantity
            local slot=row.slot or i
            -- Use worn kits first. For bandages, finish the smallest bundle first.
            local rank=remaining or quantity
            if not bestRank or rank<bestRank or (rank==bestRank and slot<firstSlot) then
                firstIndex,firstSlot,bestRank=i,slot,rank
            end
        end
    end
    return count,firstIndex
end

function NHStore.canStartBatch(state,recipe)
    recipe=recipe or NHStore.recipe
    if recipe.facility and NHStore.level(state,recipe.facility)==0 then return false,"Facility is locked." end
    if recipe.unlockFlag and not HasFlagPersistent(recipe.unlockFlag) then return false,"Spell not unlocked in this save." end
    if state.order then return false,"Another order is active." end
    if recipe.goldCost and state.bankGold<recipe.goldCost then return false,"Not enough stored gold." end
    for key,amount in pairs(recipe.resources or {}) do
        if (state.resources[key] or 0)<amount then return false,"Not enough workshop resources." end
    end
    local delivery=recipe.materials
    local held
    if recipe.catalysts then
        delivery,held={},{}
        for name,amount in pairs(recipe.materials) do delivery[name]=amount end
        -- Remove the sample from available stock while the batch runs.
        -- The paid order records every particle owed, even after a reload.
        for _,sample in ipairs(recipe.catalysts) do
            if not NHStore.allocateIngredient(state.materials,{sample.name},sample.amount,held) then return false,"Missing catalyst." end
            delivery[sample.name]=(delivery[sample.name] or 0)+sample.amount
        end
    end
    local payment,alternative=batchPayment(state.materials,recipe,held)
    if not payment then return false,"Not enough bulk ingredients." end
    if recipe.emptyContainers and NHStore.emptyContainerCount(state)<recipe.emptyContainers then
        return false,"Not enough empty containers."
    end
    if recipe.item then
        local slot,ingredientIndex
        if recipe.storedIngredient then
            local count
            count,ingredientIndex=NHStore.warehouseIngredientCount(state,recipe.storedIngredient)
            if count==0 then return false,"Missing stored ingredient." end
            local row=state.warehouse[ingredientIndex]
            if (row.item.count or 1)==1 and NHStore.category(recipe.storedIngredient)==NHStore.category(recipe.item.kind) then
                slot=row.slot or ingredientIndex
            end
        end
        slot=slot or NHStore.freeSlot(state,"warehouse",nil,recipe.item.kind)
        if not slot then return false,"Product storage is full." end
        return true,slot,payment,nil,nil,ingredientIndex
    end
    if NHStore.canStockMaterials(state,delivery,payment) then return true,nil,payment,delivery,held end
    if alternative then
        local swapped=batchPayment(state.materials,recipe,held,true)
        if swapped and NHStore.canStockMaterials(state,delivery,swapped) then return true,nil,swapped,delivery,held end
    end
    return false,"Material storage is full."
end

function NHStore.deductStock(stock,costs)
    for key,amount in pairs(costs) do
        local remaining=stock[key]-amount
        stock[key]=remaining>0 and remaining or nil
    end
end

function NHStore.startOrder(state,id)
    local recipe=findRecipe(id or "stable")
    if not recipe then return false,"Unknown recipe." end
    local ready,slot,payment,delivery,held,ingredientIndex=NHStore.canStartBatch(state,recipe)
    if not ready then return false,slot end
    if recipe.emptyContainers then
        local ok,reason=NHStore.spendEmptyContainers(state,recipe.emptyContainers)
        if not ok then return false,reason end
    end
    if recipe.goldCost then
        local ok,reason=NHStore.spendGold(state,recipe.goldCost)
        if not ok then return false,reason end
    end
    -- The paid order owns its item, including a spell's nested native card fields.
    local output={item=recipe.item and decode(encode(recipe.item)),slot=slot,materials=delivery}
    if ingredientIndex then
        local item=state.warehouse[ingredientIndex].item
        if (item.count or 1)>1 then item.count=item.count-1
        else table.remove(state.warehouse,ingredientIndex) end
    end
    NHStore.deductStock(state.materials,payment)
    if recipe.resources then NHStore.deductStock(state.resources,recipe.resources) end
    state.order={id=state.finished+1,recipe=recipe.id,progress=0,required=NHStore.productionFrames(recipe),output=output,catalysts=held}
    return true
end

function NHStore.salvageYield(item,mode)
    if mode~=nil and mode~="scrap" and mode~="essence" then return end
    if item.kind=="spell" then
        local card=item.card
        if type(card)~="table" then return end
        local amount=card.stack or 1
        if not whole(amount) or amount<1 then return end
        if mode=="essence" then
            local resource=NHEssences.byAction[card.id]
            if not resource then return end
            local perCard=NHEssences.values[card.id]
            return amount*perCard,resource
        end
        return amount,"arcane_scrap"
    end
    if mode=="essence" then return end
    if item.kind=="wand" then return 3,"arcane_scrap" end
    if item.kind=="potion" and NHPotion.isEmptyContainer(item) then return 1,"container_scrap" end
end

function NHStore.salvage(state,request)
    if NHStore.level(state,"salvage")==0 then return false,"Facility is locked." end
    local index=NHStore.slotIndex(state,"warehouse",request.slot,request.kind)
    local row=index and state.warehouse[index]
    if not row or row.id~=request.id or row.item.kind~=request.kind then return false,"Inventory slot changed." end
    local amount,resource=NHStore.salvageYield(row.item,request.mode)
    if not amount then
        if request.mode=="essence" then return false,"No essence for this spell." end
        if request.mode~=nil and request.mode~="scrap" then return false,"Invalid salvage mode." end
        return false,row.item.kind=="potion" and "Only empty containers can be dismantled." or "Unsupported salvage item."
    end
    local stock=state.resources[resource] or 0
    if amount>NHStore.maxResourceAmount-stock then return false,"Resource storage is full." end
    table.remove(state.warehouse,index)
    state.resources[resource]=stock+amount
    return true
end

-- The caller submits the absolute progress for this order, so retrying a save
-- cannot award the same elapsed frames again. The checkpoint receipt and the
-- output are committed with the order in the same detached profile.
function NHStore.advanceProduction(state,request)
    local order=state.order
    if request.run~=state.runSerial or request.run<=state.closedThrough
        or request.orderId~=(order and order.id or false) then return false,false end
    local key=request.checkpoint
    local target=request.progress or 0
    if not whole(target) or (key~=nil and (type(key)~="string" or key=="")) then return false,false end
    local firstVisit=key~=nil and not state.checkpoints[key]
    if firstVisit then state.checkpoints[key]=true end
    if not order then return firstVisit,false end
    local progress=math.max(target,order.progress)
    if firstVisit then progress=progress+NHStore.checkpointFrames end
    if progress==order.progress then return false,false end
    if progress<order.required then
        order.progress=progress
        return true,false
    end
    local output=order.output
    if output.item and output.item.kind=="pouch" then
        NHPouches.create(state,"warehouse",output.slot,0,output.item.tier)
    elseif output.item and output.item.kind=="card_wallet" then
        stockItem(state,output.slot,NHCardWallets.empty(output.item.tier))
    elseif output.item then
        stockItem(state,output.slot,output.item)
    else
        for name,amount in pairs(output.materials) do state.materials[name]=(state.materials[name] or 0)+amount end
    end
    state.order=false
    state.finished=state.finished+1
    return true,true
end
