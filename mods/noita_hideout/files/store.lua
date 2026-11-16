-- Two revisioned snapshots in Noita's normal mod settings. A complete
-- readback checks the settings API; it does not force the engine to flush.
NHStore = {}
dofile("mods/noita_hideout/files/pouches.lua")
local progression=dofile("mods/noita_hideout/files/progression.lua")
local max_bytes = 1024 * 1024
local max_depth = 40
local max_safe_integer = 9007199254740991
local profile_counter = "noita_hideout.profile_count"
local profile_flag = "noita_hideout_profile_"
local cached_profile

NHStore.pouchCapacity = 4
NHStore.doseDurability = 3
NHStore.checkpointFrames = 60 * 60
NHStore.maxGold = max_safe_integer

function NHStore.productionFrames(recipe)
    return (recipe and recipe.durationFrames) or 2 * 60 * 60
end

local function fresh(profile)
    local s={
        version = 1, profile = profile, revision = 0,
        runSerial = 0, closedThrough = 0, checkpoints = {},
        nextItemId = 1, materials = {}, docks = {}, warehouse = {}, safe = {}, safeCapacity = 2, sharedSlots = true,
        pouches = {},
        order = false, finished = 0, levels = {}, storageBase = {}, resources = {}, bankGold = 0, bankWalletNet = 0,
    }
    s.starterPouchId=NHPouches.create(s,"safe",2,2)
    return s
end

local function whole(n)
    return type(n) == "number" and n >= 0 and n <= max_safe_integer and n == math.floor(n)
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
NHStore.itemCategories={wand="wand",spell="spell",potion="containers",pouch="equipment"}
function NHStore.category(kind)
    return NHStore.itemCategories[kind] or "supplies"
end

local function warehouse_grids()
    return {wand={},spell={},containers={},supplies={},equipment={}}
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
    for key,visited in pairs(s.checkpoints) do
        assert(type(key)=="string" and key~="" and visited==true,"Invalid Holy Mountain checkpoint")
    end
    assert(type(s.warehouse) == "table" and type(s.safe) == "table", "Invalid inventory")
    assert(type(s.materials)=="table" and type(s.docks)=="table","Invalid bulk storage")
    progression.validate(s,whole)
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
        assert(row.item.kind~="pouch" and whole(slot) and slot>=1 and slot<=capacity and not seen[slot],"Invalid secure inventory slot")
        seen[slot]=true
    end
    local function validDose(remaining,count)
        return whole(remaining) and remaining>=1 and remaining<=NHStore.doseDurability
            and whole(count) and count>=1 and (remaining==NHStore.doseDurability or count==1)
    end
    NHPouches.validate(s,whole,validDose)
    for _,row in ipairs(s.safe) do
        if row.item.kind=="dose" then assert(validDose(row.item.remaining or NHStore.doseDurability,row.item.count or 1),"Invalid stored injector") end
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
        assert(row.item.kind~="pouch" and whole(slot) and slot>=1 and slot<=NHStore.warehouseCapacity(s,NHStore.category(row.item.kind)) and not used[slot],"Invalid warehouse slot")
        used[slot]=true
        if row.item.kind=="dose" then assert(validDose(row.item.remaining or NHStore.doseDurability,row.item.count or 1),"Invalid warehouse injector") end
    end
    for _,record in pairs(s.issuedDoses or {}) do
        assert(validDose(record.remaining or NHStore.doseDurability,1),"Invalid issued injector")
    end
    if s.order ~= false then
        assert(type(s.order) == "table" and s.order.id==s.finished+1 and whole(s.order.progress) and whole(s.order.required)
            and s.order.progress < s.order.required and type(s.order.output) == "table", "Invalid production order")
        local output=s.order.output
        if output.item then
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
function NHStore.acceptsDose(cell, remaining)
    return not cell or (remaining==NHStore.doseDurability and cell.remaining==remaining)
end

function NHStore.putPouchDose(pouch, remaining, slot)
    if pouch.location=="lost" then return false end
    if slot==nil then
        for i=1,NHStore.pouchCapacity do
            if pouch.cells[i] and NHStore.acceptsDose(pouch.cells[i],remaining) then slot=i; break end
        end
        if not slot then
            for i=1,NHStore.pouchCapacity do if not pouch.cells[i] then slot=i; break end end
        end
    end
    if not whole(slot) or slot<1 or slot>NHStore.pouchCapacity then return false end
    local cell=pouch.cells[slot]
    if not NHStore.acceptsDose(cell,remaining) then return false end
    pouch.cells[slot]={remaining=remaining,count=(cell and cell.count or 0)+1}
    pouch.doses=pouch.doses+1
    return true
end

function NHStore.takePouchDose(pouch,slot)
    local cell=pouch.cells[slot]
    if not cell or pouch.location=="lost" then return nil end
    pouch.cells[slot]=cell.count>1 and {count=cell.count-1,remaining=cell.remaining} or nil
    pouch.doses=pouch.doses-1
    return cell.remaining
end

NHStore.restock=NHPouches.restock

-- Each listed reaction in data/materials.xml converts one pixel of each
-- ingredient into the same number of product pixels. Use 250 units per part.
local function alchemyBatch(id,zh,en,product,ingredients)
    local inputs={}
    for _,name in ipairs(ingredients) do
        inputs[#inputs+1]={name=name,amount=250}
    end
    local yield=250*#inputs
    return {id=id,category="alchemy",alchemyMode="synthesis",zh=zh,en=en,inputs=inputs,
        materials={[product]=yield},count=yield,reversible=true}
end

-- Inputs and the paid order are committed together. Only loose stock is spendable.
NHStore.recipes={
    alchemyBatch("stable","稳定传送液","Teleportatium","magic_liquid_teleportation",
        {"magic_liquid_unstable_teleportation","slime"}),
    alchemyBatch("flummoxium","除草基质","Flummoxium","material_confusion",
        {"magic_liquid_worm_attractor","blood_worm"}),
    alchemyBatch("pheromone","费洛蒙","Pheromone","magic_liquid_charm",
        {"material_confusion","magic_liquid_berserk"}),
    -- Copper is a powder in the vanilla [sand_metal] group. Naming one metal
    -- keeps the recovered ingredient unambiguous when a batch is decomposed.
    alchemyBatch("levitatium","漂浮基质","Levitatium","magic_liquid_faster_levitation",
        {"material_confusion","copper"}),
    alchemyBatch("hastium","迅速基质","Hastium","magic_liquid_faster_levitation_and_movement",
        {"magic_liquid_faster_levitation","magic_liquid_movement_faster"}),
    alchemyBatch("unstable_polymorphine","不稳变形魔药","Unstable polymorphine","magic_liquid_unstable_polymorph",
        {"material_confusion","blood","oil"}),
    alchemyBatch("diminution","缩小","Diminution","magic_liquid_weakness",
        {"vomit","bone"}),
    {id="medical",category="medical",facility="medical",zh="医疗包",en="Medkit",inputs={{name="water",amount=100},{name="blood",amount=50}},
        item={kind="medkit",remaining=3,name="$nh_hideout_medkit",icon="mods/noita_hideout/files/items/medkit.png"}},
    {id="injector",category="medical",facility="injector",zh="耐火激活剂",en="Fire injector",inputs={{name="water",amount=100},{name="lava",amount=25}},
        item={kind="dose",remaining=3,count=1}},
    {id="grenade",category="weapons",facility="grenade",zh="魔法手雷",en="Magic grenade",inputs={{name="sand",amount=100},{name="slime",amount=50}},
        item={kind="grenade",name="$nh_hideout_grenade",icon="mods/noita_hideout/files/items/grenade.png"}},
    {id="pouch",category="equipment",facility="injector",zh="空针剂包",en="Empty injector pouch",
        inputs={{name="slime",amount=50}},emptyContainers=1,item={kind="pouch"}},
}
NHStore.recipe=NHStore.recipes[1]

-- A reversible material recipe spends the entire original yield and returns
-- exactly one batch of its original ingredients. Items are never disassembled here.
local function reverseRecipe(recipe)
    assert(recipe.category=="alchemy" and not recipe.item and not recipe.emptyContainers
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

local function findRecipe(id)
    for _,recipe in ipairs(NHStore.recipes) do if recipe.id==id then return recipe end end
end

function NHStore.canStartBatch(state,recipe)
    recipe=recipe or NHStore.recipe
    if recipe.facility and NHStore.level(state,recipe.facility)==0 then return false,"Facility is locked." end
    if state.order then return false,"Another order is active." end
    local payment={}
    for _,input in ipairs(recipe.inputs) do
        local required=(payment[input.name] or 0)+input.amount
        if (state.materials[input.name] or 0)<required then return false,"Not enough bulk ingredients." end
        payment[input.name]=required
    end
    if recipe.emptyContainers and NHStore.emptyContainerCount(state)<recipe.emptyContainers then
        return false,"Not enough empty containers."
    end
    if recipe.item then
        local slot=NHStore.freeSlot(state,"warehouse",nil,recipe.item.kind)
        if not slot then return false,"Product storage is full." end
        return true,slot
    end
    if not NHStore.canStockMaterials(state,recipe.materials,payment) then return false,"Material storage is full." end
    return true
end

function NHStore.startOrder(state,id)
    local recipe=findRecipe(id or "stable")
    if not recipe then return false,"Unknown recipe." end
    local ready,slot=NHStore.canStartBatch(state,recipe)
    if not ready then return false,slot end
    if recipe.emptyContainers then
        local ok,reason=NHStore.spendEmptyContainers(state,recipe.emptyContainers)
        if not ok then return false,reason end
    end
    local output={item=recipe.item,slot=slot,materials=recipe.materials}
    for _,input in ipairs(recipe.inputs) do
        local left=state.materials[input.name]-input.amount
        state.materials[input.name]=left>0 and left or nil
    end
    state.order={id=state.finished+1,recipe=recipe.id,progress=0,required=NHStore.productionFrames(recipe),output=output}
    return true
end

function NHStore.salvageYield(item)
    if item.kind=="wand" then return 3,"arcane_scrap" end
    if item.kind=="spell" then return item.card.stack or 1,"arcane_scrap" end
    if item.kind=="potion" and NHPotion.isEmptyContainer(item) then return 1,"container_scrap" end
end

function NHStore.salvage(state,request)
    if NHStore.level(state,"salvage")==0 then return false,"Facility is locked." end
    local index=NHStore.slotIndex(state,"warehouse",request.slot,request.kind)
    local row=index and state.warehouse[index]
    if not row or row.id~=request.id or row.item.kind~=request.kind then return false,"Inventory slot changed." end
    local amount,resource=NHStore.salvageYield(row.item)
    if not amount then
        return false,row.item.kind=="potion" and "Only empty containers can be dismantled." or "Unsupported salvage item."
    end
    table.remove(state.warehouse,index)
    state.resources[resource]=(state.resources[resource] or 0)+amount
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
        NHPouches.create(state,"warehouse",output.slot,0)
    elseif output.item then
        table.insert(state.warehouse,{id=state.nextItemId,slot=output.slot,item=output.item})
        state.nextItemId=state.nextItemId+1
    else
        for name,amount in pairs(output.materials) do state.materials[name]=(state.materials[name] or 0)+amount end
    end
    state.order=false
    state.finished=state.finished+1
    return true,true
end
