-- Only native items with an identifiable held effect can enter a socket.
NHRelics = {dropFiles={}}
local base = "mods/noita_hideout/files/"
local pickup = "data/entities/items/pickup/"
local catalog, byFile, byName = {}, {}, {}
local function define(id, path, icon, name)
    local d = {file=pickup..(path or id)..".xml", icon="data/ui_gfx/items/"..(icon or id)..".png",
        name="$item_"..(name or id)}
    catalog[id], byFile[d.file], byName[d.name] = d, id, id
    table.insert(NHRelics.dropFiles,d.file)
end
define("brimstone")
define("thunderstone", nil, "ingredient_1")
define("waterstone")
define("stonestone")
define("moon")
define("evil_eye")
define("musicstone")
define("wandstone")
define("sunseed", "sun/sunseed")
define("sunstone", "sun/sunstone", "sunseed_2", "seed_c")

function NHRelics.empty()
    return {kind="relic_chain", name="$nh_hideout_relic_chain", icon=base.."items/relic_chain.png", cells={}}
end

function NHRelics.capacity(s)
    return 1 + NHStore.level(s,"perk_slots")
end

local effects={
    brimstone={"免疫火焰，火魔友好。点燃周围可燃物并蒸发液体。","Fire immunity and friendly fire mages. Ignites flammables and vaporizes liquids."},
    thunderstone={"免疫雷电，电魔友好。向附近的导体放电。","Electric immunity and friendly thunder mages. Electrifies nearby conductors."},
    waterstone={"水下呼吸。打湿周围生物，灭火并凝固熔融物。","Breathe underwater. Soaks creatures, extinguishes fire and cools molten materials."},
    stonestone={"将附近地形转成泥土，踢击时引发小型地震。","Turns nearby earth into soil. Kicking triggers a small quake."},
    moon={"吸引周围的投射物与物理物体。","Attracts nearby projectiles and physical objects."},
    evil_eye={"沿瞄准方向持续发射短程电浆束。","Projects a short plasma beam in your aiming direction."},
    musicstone={"奏响当前区域的音乐。","Plays the current biome's music."},
    wandstone={"可随处编辑魔杖，将附近的普通液体转为汇聚法力魔药。","Edit wands anywhere. Converts common liquids into concentrated mana."},
    sunseed={"驱散战争迷雾，将周围的粉末转为不稳定火药。","Reveals unexplored terrain. Converts nearby powders into unstable gunpowder."},
    sunstone={"驱散战争迷雾，将粉末转为液态火焰，并造成范围诅咒伤害。","Reveals terrain, turns powders into liquid fire and deals area curse damage."}
}

function NHRelics.description(id,lang)
    local lines=effects[id]
    return lines and lines[lang=="zh" and 1 or 2]
end

local function validCell(cell, capacity)
    return type(cell)=="number" and cell==math.floor(cell) and cell>=1 and cell<=capacity
end

function NHRelics.valid(item)
    if item.kind=="relic" then return catalog[item.relic]~=nil end
    if item.kind~="relic_chain" or type(item.cells)~="table" then return false end
    for cell,row in pairs(item.cells) do
        if not validCell(cell,4) or type(row)~="table" or type(row.id)~="number" or row.id<1
            or not row.item or row.item.kind~="relic" or not catalog[row.item.relic] then return false end
    end
    return true
end

local function identify(entity)
    if not EntityHasTag(entity,"item_pickup") then return end
    local path=(EntityGetFilename and EntityGetFilename(entity) or ""):gsub("\\","/"):lower()
    local id=byFile[path] or byFile[path:match("/(data/entities/items/pickup/.+)$")]
    if id then return id end
    -- The engine can lose the source filename after a chunk is streamed.
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    if item then
        id=byName[ComponentGetValue2(item,"item_name")]
        if id and catalog[id].icon==ComponentGetValue2(item,"ui_sprite") then return id end
    end
end

function NHRelics.registerItems()
    NHTransfers.registerItem("relic",identify,{
        warehouseCategory="equipment",
        capture=function(entity)
            local id=identify(entity)
            local d=catalog[id]
            if not d or EntityGetFirstComponentIncludingDisabled(entity,"ItemCostComponent") then return nil,"Relic unavailable." end
            return {kind="relic",relic=id,name=d.name,icon=d.icon}
        end,
        restore=function(item,x,y)
            if NHRelics.valid(item) then return EntityLoad(catalog[item.relic].file,x,y) end
        end
    })
    NHTransfers.registerItem("relic_chain",function(entity) return EntityHasTag(entity,"noita_hideout_relic_chain") end,{
        warehouseCategory="equipment",
        capture=function(entity,s)
            local release=NHTransfers.issuedRecord(s,entity)
            if release and release.row.item.kind=="relic_chain" then return release.row.item end
            return NHRelics.empty()
        end,
        restore=function(item,x,y)
            if NHRelics.valid(item) then return EntityLoad(base.."items/relic_chain.xml",x,y) end
        end
    })
end

function NHRelics.chain(s,ref)
    if not ref or ref.container~="safe" or not ref.slot then return end
    local i=NHStore.slotIndex(s,"safe",ref.slot,"relic_chain")
    local row=i and s.safe[i]
    if row and row.id==ref.id and row.item.kind=="relic_chain" then return row,i end
end

local function copy(t)
    local out={}
    for k,v in pairs(t) do out[k]=v end
    return out
end

-- Transfer drafts share nested tables. Replace the whole path to the socket.
local function writeCell(s,ref,cell,value)
    local row,i=NHRelics.chain(s,ref)
    row=copy(row)
    row.item=copy(row.item)
    row.item.cells=copy(row.item.cells)
    row.item.cells[cell]=value
    s.safe[i]=row
end

function NHRelics.put(s,ref,cell,row)
    local chain=NHRelics.chain(s,ref)
    if not chain or not validCell(cell,NHRelics.capacity(s)) or chain.item.cells[cell]
        or row.item.kind~="relic" or not NHRelics.valid(row.item) then return false end
    writeCell(s,ref,cell,row)
    return true
end

function NHRelics.take(s,ref,cell,id)
    local chain=NHRelics.chain(s,ref)
    local row=chain and chain.item.cells[cell]
    if not row or row.id~=id then return end
    writeCell(s,ref,cell,nil)
    return row
end

-- The caller commits this detached draft only after both endpoints succeed.
function NHRelics.move(s,ref,r)
    local row
    if r.sourceCell then row=NHRelics.take(s,ref,r.sourceCell,r.entity)
    elseif r.source=="safe" or r.source=="warehouse" then
        local at=NHStore.slotIndex(s,r.source,r.from,"relic")
        row=at and s[r.source][at]
        if not row or row.id~=r.entity or row.item.kind~="relic" then return false,"Inventory slot changed." end
        table.remove(s[r.source],at)
    end
    if not row then return false,"Inventory slot changed." end
    if r.targetCell then
        if NHRelics.put(s,ref,r.targetCell,row) then return true end
    elseif (r.destination=="warehouse" or r.destination=="safe") and r.safeSlot
        and NHStore.freeSlot(s,r.destination,r.safeSlot,"relic") then
        row=copy(row)
        row.slot=r.safeSlot
        table.insert(s[r.destination],row)
        return true
    end
    return false,"Inventory slot changed."
end

local previousPlayer, previousRevision
function NHRelics.reset()
    previousPlayer,previousRevision=nil,nil
end

local function removeEffect(child)
    EntityRemoveFromParent(child)
    EntityKill(child)
end

function NHRelics.update(s,player)
    if previousPlayer and previousPlayer~=player and EntityGetIsAlive(previousPlayer) then
        for _,child in ipairs(EntityGetAllChildren(previousPlayer,"nh_chain_effect") or {}) do
            if EntityHasTag(child,"nh_chain_effect") then removeEffect(child) end
        end
    end
    if not player then NHRelics.reset(); return end
    if previousPlayer==player and previousRevision==s.revision and GameGetFrameNum()%60~=0 then return end
    previousPlayer,previousRevision=player,s.revision
    local needed={}
    for _,row in ipairs(s.safe) do
        if row.item.kind=="relic_chain" then
            for _,socket in pairs(row.item.cells) do needed[socket.item.relic]=true end
        end
    end
    for _,child in ipairs(EntityGetAllChildren(player,"nh_chain_effect") or {}) do
        if EntityHasTag(child,"nh_chain_effect") then
            local key=EntityGetName(child)
            if needed[key] then needed[key]=nil else removeEffect(child) end
        end
    end
    local x,y=EntityGetTransform(player)
    for id in pairs(needed) do
        local effect=EntityLoad(base.."relic_effects/"..id..".xml",x,y)
        if effect and effect~=0 then EntityAddChild(player,effect) end
    end
end
