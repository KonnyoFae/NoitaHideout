NHPotion = {}

local empty_flask = "data/entities/items/pickup/potion_empty.xml"
local pickup="data/entities/items/pickup/"
local variants={
    powder_stash={icon="material_pouch",zh="粉末袋",en="Powder pouch"},
    jar={icon="jar",zh="罐子",en="Jar"},
    jar_of_urine={icon="jar",zh="尿罐",en="Urine jar"},
    potion_aggressive={icon="potion_alchemist",zh="炼金师药瓶",en="Alchemist flask"},
}
local fill_scripts={
    ["data/scripts/items/powder_stash.lua"]=true,
    ["data/scripts/items/potion.lua"]=true,
    ["data/scripts/items/potion_aggressive.lua"]=true,
}
local normal_flask_tag = "noita_hideout_standard_flask"
local unstable = "magic_liquid_unstable_teleportation"
local stable = "magic_liquid_teleportation"
local reagent_units = 250

-- These templates differ from the base flask only by their initial fill.
-- Distinct material containers retain their template; mimics remain world entities.
local normal_templates = {}
for _, suffix in ipairs({
    "", "_empty", "_starting", "_water", "_alcohol", "_beer", "_milk",
    "_porridge", "_random_material", "_secret", "_slime", "_vomit",
}) do
    normal_templates["data/entities/items/pickup/potion" .. suffix .. ".xml"] = true
end
normal_templates["data/entities/items/shop_potion.xml"] = true

local function component(entity, kind)
    local id = EntityGetFirstComponentIncludingDisabled(entity, kind)
    return id and id ~= 0 and id or nil
end

function NHPotion.isFlask(entity)
    return entity ~= nil and entity ~= 0 and (EntityHasTag(entity, "potion")
        or (component(entity, "PotionComponent") ~= nil
            and component(entity, "MaterialInventoryComponent") ~= nil))
end

local function normal_path(filename)
    local path = (filename or ""):lower():gsub("\\", "/"):gsub("^%./", "")
    -- EntityGetFilename may include the game directory.
    if path:match("^mods/") then return path end
    return path:match(".*/(mods/.*)") or path:match(".*/(data/entities/.*)") or path
end

local ordinary_art = {
    ["data/ui_gfx/items/potion.png"] = true,
    ["data/items_gfx/potion.png"] = true,
}
local ordinary_scripts = {
    ["data/scripts/items/potion.lua"] = true,
    ["data/scripts/items/potion_starting.lua"] = true,
}
local ordinary_variables = {noita_hideout_transfer_id = true}

-- Read the installed templates, including inherited callback and sprite
-- definitions. No base-game assets are modified.
function NHPotion.readTemplates()
    local seen = {}
    local function read(path)
        if seen[path] or not path:match("^data/") or not ModDoesFileExist(path) then return end
        seen[path] = true
        local xml = (ModTextFileGetContent(path) or ""):gsub("<!%-%-.-%-%->", "")
        for key, value in xml:gmatch([=[([%w_]+)%s*=%s*["']([^"']+)["']]=]) do
            if key:match("^script_") and value:match("^data/") then
                ordinary_scripts[value] = true
            elseif (key == "image_file" or key == "ui_sprite") and value:match("^data/[^/]*gfx/.*potion") then
                ordinary_art[value] = true
            end
        end
        for variable in xml:gmatch("<VariableStorageComponent%s+([^>]+)>") do
            local name = (" " .. variable):match([=[%sname%s*=%s*["']([^"']+)["']]=])
            if name then ordinary_variables[name] = true end
        end
        for base in xml:gmatch([=[<Base%s+[^>]-file%s*=%s*["']([^"']+)["']]=]) do read(base) end
    end
    for path in pairs(normal_templates) do read(path) end
end

local function stock_state(entity)
    for _, variable in ipairs(EntityGetComponentIncludingDisabled(entity, "VariableStorageComponent") or {}) do
        if not ordinary_variables[ComponentGetValue2(variable, "name")] then return false end
    end
    for _, lua in ipairs(EntityGetComponentIncludingDisabled(entity, "LuaComponent") or {}) do
        local members = ComponentGetMembers(lua)
        if not members then return false end
        for field in pairs(members) do
            if field:match("^script_") then
                local script = ComponentGetValue2(lua, field)
                if script and script ~= "" and not ordinary_scripts[script] then return false end
            end
        end
    end
    return true
end

local function ordinary_flask(entity, item)
    if EntityHasTag(entity, "enemy") or component(entity, "AnimalAIComponent") then return false end
    local path = normal_path(EntityGetFilename(entity))
    if normal_templates[path] then return true end
    -- An explicit special or modded template takes precedence over shared art
    -- or tags that it may have inherited from the original bottle.
    if path:match("^mods/") or path:match("^data/entities/items/") or path:match("^data/entities/animals/") then
        return false
    end
    if not stock_state(entity) then return false end
    if EntityHasTag(entity, normal_flask_tag) then return true end
    -- Inline player inventory and streamed entities can report the enclosing
    -- file or an empty filename. Recognize the original bottle on the entity.
    if ordinary_art[ComponentGetValue2(item, "ui_sprite")] then return true end
    for _, sprite in ipairs(EntityGetComponentIncludingDisabled(entity, "SpriteComponent") or {}) do
        if ordinary_art[ComponentGetValue2(sprite, "image_file")] then return true end
    end
    for _, lua in ipairs(EntityGetComponentIncludingDisabled(entity, "LuaComponent") or {}) do
        local script = ComponentGetValue2(lua, "script_source_file")
        if script == "data/scripts/items/potion.lua" or script == "data/scripts/items/potion_starting.lua" then
            return true
        end
    end
    return EntityGetName(entity) == "$item_potion" or ComponentGetValue2(item, "item_name") == "$item_potion"
end

local function variant_for(entity,item)
    local path=normal_path(EntityGetFilename(entity))
    local name=path:match("^data/entities/items/pickup/([%w_]+)%.xml$")
    if name and variants[name] then return name end
    if path:match("^mods/") or path:match("^data/entities/items/") or path:match("^data/entities/animals/") then return end
    -- After a save the reported path may reference the player, not the item.
    for key in pairs(variants) do
        if EntityHasTag(entity,"noita_hideout_"..key) then return key end
    end
    local icon=ComponentGetValue2(item,"ui_sprite")
    if icon=="data/ui_gfx/items/material_pouch.png" and EntityHasTag(entity,"powder_stash") then return "powder_stash" end
    if icon=="data/ui_gfx/items/potion_alchemist.png" and EntityHasTag(entity,"projectile_item") then return "potion_aggressive" end
    if icon=="data/ui_gfx/items/jar.png" and ComponentGetValue2(item,"item_name")=="$item_jar" then
        for _,c in ipairs(EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent") or {}) do
            if ComponentGetValue2(c,"name")=="potion_material" and ComponentGetValue2(c,"value_string")=="urine" then return "jar_of_urine" end
        end
        return "jar"
    end
end

local function flask_components(entity)
    local parts = {}
    for _, kind in ipairs({"MaterialInventoryComponent", "MaterialSuckerComponent",
        "PotionComponent", "ItemComponent", "DamageModelComponent"}) do
        parts[kind] = component(entity, kind)
        assert(parts[kind], "Missing flask component: " .. kind)
    end
    return parts
end

local function whole_units(amount)
    return type(amount) == "number" and amount >= 0 and amount <= 2147483647
        and amount == math.floor(amount)
end

local function material_id(name)
    local id = CellFactory_GetType(name)
    assert(type(id) == "number" and id >= 0 and CellFactory_GetName(id) == name,
        "Material unavailable: " .. name)
    return id
end

local function read_materials(inventory)
    local counts = ComponentGetValue2(inventory, "count_per_material_type")
    assert(type(counts) == "table", "Could not read flask contents")
    local materials = {}
    for slot, amount in pairs(counts) do
        -- Noita returns a one-indexed Lua array for its zero-indexed material IDs.
        assert(whole_units(amount), "Flask contains a quantity that cannot be restored exactly")
        if amount > 0 then
            local name = CellFactory_GetName(slot - 1)
            assert(type(name) == "string" and name ~= "" and material_id(name) == slot - 1,
                "Unrecognized flask material")
            materials[name] = amount
        end
    end
    return materials
end

local short_names = {
    water = {"水", "Water"},
    [unstable] = {"不稳定传送液", "Unstable teleportatium"},
    [stable] = {"稳定传送液", "Teleportatium"},
    slime = {"黏液", "Slime"},
    magic_liquid_hp_regeneration = {"生命基质", "Healthium"},
    purifying_powder = {"净化粉末", "Purifying powder"},
}

-- The base game gives several distinct warehouse stocks the same display name.
local variant_names={
    gunpowder={"普通火药","Regular gunpowder"},gunpowder_unstable={"炼金火药","Alchemical gunpowder"},
    sand_surface={"地表沙","Surface sand"},sand_petrify={"石化沙","Petrified sand"},
    sandstone_surface={"地表砂岩","Surface sandstone"},
    soil_lush={"肥沃泥土","Lush soil"},soil_lush_dark={"深色肥沃泥土","Dark lush soil"},
    water_fading={"短效水","Fading water"},water_temp={"临时水","Temporary water"},
    slime_green={"绿色黏液","Green slime"},slime_yellow={"黄色黏液","Yellow slime"},
    blood_fading={"短效血液","Fading blood"},
}
for name,label in pairs(variant_names) do short_names[name]=label end

function NHPotion.label(record, lang)
    local names = {}
    for name in pairs(record.materials) do names[#names + 1] = name end
    table.sort(names)
    local variant=variants[record.variant]
    local title=variant and variant[lang=="zh" and "zh" or "en"]
    if #names==0 and title then return title end
    if #names == 0 then return lang == "zh" and "空药瓶" or "Empty flask" end
    local parts = {}
    for _, name in ipairs(names) do
        local localized = short_names[name] and short_names[name][lang == "zh" and 1 or 2] or name
        parts[#parts + 1] = localized .. " " .. record.materials[name]
    end
    return (title and (title.." · ") or "")..table.concat(parts, " + ")
end

local function refresh_name(record)
    record.name = NHPotion.label(record, "en")
    record.label = record.name
    return record
end

function NHPotion.dockSlot(record)
    if record.kind=="potion" then return record.variant=="powder_stash" and 2 or 1 end
end

-- Only a captured native material container with an explicitly empty inventory
-- is usable as a shell. Capture rejects entity children before creating a record.
function NHPotion.isEmptyContainer(record)
    if not record or record.kind~="potion" or type(record.materials)~="table" or next(record.materials)
        or type(record.capacity)~="number" or record.capacity<=0
        or (record.variant~=nil and not variants[record.variant]) then return false end
    -- A newer adapter may serialize attachments or additional contents in another table.
    for key,value in pairs(record) do
        if key~="materials" and type(value)=="table" and next(value) then return false end
    end
    return true
end

function NHPotion.fillLevel(record)
    local used=0
    for _,n in pairs(record.materials) do used=used+n end
    local cap=record.capacity or 1000
    if record.max_capacity and record.max_capacity>=0 then cap=math.min(cap,record.max_capacity) end
    return used,math.max(0,math.floor(cap))
end

local material_slots
function NHPotion.materialSlot(name)
    if not material_slots then
        material_slots={}
        for _,liquid in ipairs(CellFactory_GetAllLiquids(true,true)) do material_slots[liquid]=1 end
        for _,powder in ipairs(CellFactory_GetAllSands(true,true)) do material_slots[powder]=2 end
    end
    return material_slots[name]
end

function NHPotion.containerName(record,lang)
    local variant=variants[record.variant]
    if variant then return variant[lang=="zh" and "zh" or "en"] end
    return lang=="zh" and "药瓶" or "Flask"
end

function NHPotion.inventoryIcon(record)
    if record.icon and record.icon~="" then return record.icon end
    local variant=variants[record.variant]
    return "data/ui_gfx/items/"..(variant and variant.icon or "potion")..".png"
end

local pure_colors={}
function NHPotion.contentsColor(record)
    local first=next(record.materials)
    if not first then return end
    if record.color then return record.color end
    local pure=next(record.materials,first)==nil
    if pure and pure_colors[first] then return pure_colors[first] end
    -- The stored item has no live entity. Ask the same native colour mixer
    -- using only a material inventory, without physics, item scripts or spills.
    local probe=EntityCreateNew("noita_hideout_color_sample")
    if not probe or probe==0 then return end
    local ok,color=pcall(function()
        if not EntityAddComponent2(probe,"MaterialInventoryComponent",{on_death_spill=false,do_reactions=0}) then return end
        EntityAddComponent2(probe,"PotionComponent",{})
        for name,amount in pairs(record.materials) do
            if CellFactory_GetType(name)<0 then return end
            AddMaterialInventoryMaterial(probe,name,amount)
        end
        return GameGetPotionColorUint(probe)
    end)
    EntityKill(probe)
    if ok and color then
        if pure then pure_colors[first]=color end
        return color
    end
end

function NHPotion.materialName(name,lang)
    if lang and variant_names[name] then
        return variant_names[name][lang=="zh" and 1 or 2]
    end
    local id=CellFactory_GetType(name)
    if id and id>=0 then
        local label=CellFactory_GetUIName(id)
        if label and label~="" then return GameTextGetTranslatedOrNot(label) end
    end
    return name
end

-- Both sides belong to a detached profile draft and are committed together.
function NHPotion.transferMaterial(state,request)
    local index=NHStore.slotIndex(state,"docks",request.slot)
    local row=index and state.docks[index]
    if not row or row.id~=request.storedId then return false,"Inventory slot changed." end
    local item,stock=row.item,state.materials
    if request.unload then
        if not next(item.materials) then return false,"Container is empty." end
        if not NHStore.canStockMaterials(state,item.materials) then return false,"Material storage is full." end
        for name,amount in pairs(item.materials) do
            stock[name]=(stock[name] or 0)+amount
        end
        item.materials={}
    else
        local name,n=request.material,request.amount
        if not whole_units(n) or n<1 or NHPotion.materialSlot(name)~=row.slot then return false,"Incompatible material." end
        local used,cap=NHPotion.fillLevel(item)
        n=math.min(n,stock[name] or 0,cap-used)
        if n<=0 then return false,"No stock or free capacity." end
        item.materials[name]=(item.materials[name] or 0)+n
        stock[name]=stock[name]-n
        if stock[name]==0 then stock[name]=nil end
    end
    item.color=nil
    refresh_name(item)
    return true
end

local function capture(entity)
    assert(entity and entity ~= 0, "Missing flask")
    local c = flask_components(entity)
    local variant=variant_for(entity,c.ItemComponent)
    assert(variant or ordinary_flask(entity, c.ItemComponent), "Only a recognized ordinary flask can be stored")
    assert(#(EntityGetAllChildren(entity) or {}) == 0, "This flask has attachments that cannot be restored")
    for _, price in ipairs(EntityGetComponentIncludingDisabled(entity, "ItemCostComponent") or {}) do
        local cost = ComponentGetValue2(price, "cost")
        assert(type(cost) == "number" and cost <= 0, "This flask still has a shop price")
    end
    local inv = c.MaterialInventoryComponent
    return refresh_name({
        kind = "potion", materials = read_materials(inv), variant=variant,
        -- Powder pouches disable native tinting. Sample their contents without that flag.
        color=variant~="powder_stash" and GameGetPotionColorUint(entity) or nil,
        icon=ComponentGetValue2(c.ItemComponent,"ui_sprite"),
        capacity = ComponentGetValue2(c.MaterialSuckerComponent, "barrel_size"),
        max_capacity = ComponentGetValue2(inv, "max_capacity"),
        reactions = ComponentGetValue2(inv, "do_reactions"),
        hp = ComponentGetValue2(c.DamageModelComponent, "hp"),
        picked = ComponentGetValue2(c.ItemComponent, "has_been_picked_by_player"),
        extra_capacity = EntityHasTag(entity, "extra_potion_capacity"),
    })
end

function NHPotion.snapshot(entity)
    local ok, value = pcall(capture, entity)
    if ok then return value end
    return nil, tostring(value)
end

NHPotion.capture = NHPotion.snapshot

-- Called only after the contents have a confirmed new owner or on failed spawn.
function NHPotion.discard(entity, owner)
    local inv = component(entity, "MaterialInventoryComponent")
    if inv then
        ComponentSetValue2(inv, "on_death_spill", false)
        RemoveMaterialInventoryMaterial(entity, "")
    end
    for _, kind in ipairs({"LuaComponent", "ExplodeOnDamageComponent"}) do
        for _, id in ipairs(EntityGetComponentIncludingDisabled(entity, kind) or {}) do
            EntityRemoveComponent(entity, id)
        end
    end
    if owner and owner ~= 0 then
        GameKillInventoryItem(owner, entity)
    else
        EntityKill(entity)
    end
end

function NHPotion.restore(record, x, y)
    local entity
    local ok, err = pcall(function()
        assert(record.kind == "potion" and type(record.materials) == "table", "Invalid flask record")
        for name, amount in pairs(record.materials) do
            assert(type(name) == "string" and whole_units(amount) and amount > 0, "Invalid material quantity")
            material_id(name)
        end
        assert(not record.variant or variants[record.variant],"Unknown material container template")
        entity = EntityLoad(record.variant and (pickup..record.variant..".xml") or empty_flask, x, y)
        assert(entity and entity ~= 0, "Empty flask failed to spawn")
        local c = flask_components(entity)
        local inv = c.MaterialInventoryComponent
        if record.capacity then ComponentSetValue2(c.MaterialSuckerComponent, "barrel_size", record.capacity) end
        if record.max_capacity then ComponentSetValue2(inv, "max_capacity", record.max_capacity) end
        if record.reactions ~= nil then ComponentSetValue2(inv, "do_reactions", record.reactions) end
        if record.hp then ComponentSetValue2(c.DamageModelComponent, "hp", record.hp) end
        if record.picked ~= nil then ComponentSetValue2(c.ItemComponent, "has_been_picked_by_player", record.picked) end
        if record.extra_capacity then EntityAddTag(entity, "extra_potion_capacity") end
        if record.variant then
            EntityAddTag(entity,"noita_hideout_"..record.variant)
            -- A newly loaded pouch or jar may still have its one-shot random fill pending.
            for _,lua in ipairs(EntityGetComponentIncludingDisabled(entity,"LuaComponent") or {}) do
                if fill_scripts[ComponentGetValue2(lua,"script_source_file")] then EntityRemoveComponent(entity,lua) end
            end
        else EntityAddTag(entity, normal_flask_tag) end
        -- Prevent a modified base template from contributing any extra liquid.
        RemoveMaterialInventoryMaterial(entity, "")
        for name, amount in pairs(record.materials) do
            AddMaterialInventoryMaterial(entity, name, amount)
        end
        local actual = read_materials(inv)
        for name, amount in pairs(record.materials) do
            assert(actual[name] == amount, "Failed to restore: " .. name)
            actual[name] = nil
        end
        assert(next(actual) == nil, "Unexpected material in restored flask")
    end)
    if ok then return entity end
    if entity and entity ~= 0 then NHPotion.discard(entity) end
    return nil, tostring(err)
end

function NHPotion.sample(x, y)
    -- Vanilla bottles react while carried. Keep this test fixture stable so the
    -- same 250 + 250 units can be counted on both sides of a storage round-trip.
    return NHPotion.restore({
        kind = "potion", materials = {[unstable] = reagent_units, slime = reagent_units},
        capacity = 1000, reactions = 0,
    }, x, y)
end
