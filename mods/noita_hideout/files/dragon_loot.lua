local M={}
local modulus=2147483647

-- These keys identify the exact discovery in the save, even if its warehouse is full.
-- Keep 0.32 discoveries readable. New cards use a separate key space:
-- "slime" already means the flask of slime in an old nest's pending stock.
local cardSpecies={dryad="dryad",flower_fairy="flower_fairy",minotaur="minotaur",griffin="griffin",bee="bee",dragon="dragon"}
local cardPool={}
for _,species in ipairs(NHCompanions.order) do
    if species~="dragon" then
        local key=cardSpecies[species] and species or "card_"..species
        cardSpecies[key]=species
        cardPool[#cardPool+1]=key
    end
end
-- Seed with historical keys so pending discoveries remain recognizable.
local spells={"spell_LIGHT_BULLET","spell_LIGHT_BULLET_TRIGGER","spell_BULLET","spell_SPITTER",
    "spell_BOMB","spell_ICEBALL","spell_CLOUD_WATER","spell_DISC_BULLET"}
local containers={"water","slime","magic_liquid_unstable_teleportation","sand","gunpowder"}
local legacyWandKeys={"nest_wand_010","nest_wand_011","nest_wand_013","nest_wand_016"}
local wandPresets={
    nest_wand_010={10,326,"LIGHT_BULLET"}, nest_wand_011={11,374,"SPITTER"},
    nest_wand_013={13,309,"BULLET"}, nest_wand_016={16,830,"BOUNCY_ORB"},
}
function M.wandItem(key)
    local preset=wandPresets[key]
    if not preset then return end
    return {kind="wand",discovery=key,name="$item_wand",
        template=("data/entities/items/wands/level_01/wand_%03d.xml"):format(preset[1]),
        icon=("data/items_gfx/wands/wand_%04d.png"):format(preset[2]),
        cards={{id=preset[3],x=0,y=0,item={}}}}
end
local rareShare=33
local groups={
    {cutoff=3,kind="card",keys={"dragon"},zh="龙娘卡",en="Dragon card"},
    {cutoff=8,kind="card",keys=cardPool,zh="其他召唤卡",en="Other summon card"},
    {cutoff=18,kind="tarot",keys=NHTarot.order,zh="塔罗牌",en="Tarot card"},
    {cutoff=28,kind="recipe",keys=spells,zh="法术",en="Spell"},
    {cutoff=rareShare,kind="wand",keys={"random_wand"},zh="法杖",en="Wand"},
    {cutoff=53,kind="bag",keys=NHLootBags.order,zh="战利品容器",en="Loot container"},
    {cutoff=68,kind="bag",keys=NHLootBags.packKinds,zh="补给箱",en="Supply box"},
    {cutoff=100,kind="container",keys=containers,zh="物料容器",en="Material container"},
}
local kinds,deliveryGroups={},{}
M.odds={}
local previous=0
for _,group in ipairs(groups) do
    M.odds[#M.odds+1]={group.zh,group.en,(group.cutoff-previous).."%"}
    previous=group.cutoff
    deliveryGroups[#deliveryGroups+1]=group
end
-- Retired rewards remain deliverable to profiles with a full warehouse.
deliveryGroups[#deliveryGroups+1]={kind="wand",keys=legacyWandKeys}
deliveryGroups[#deliveryGroups+1]={kind="recipe",keys={"medical","bread","sugar_cube","bandage","grenade","derringer","flare_gun"}}
for _,group in ipairs(deliveryGroups) do
    for _,key in ipairs(group.keys) do kinds[key]=group.kind end
end

local function advance(seed)
    return seed*48271%modulus
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,child in pairs(value) do result[key]=copy(child) end
    return result
end

local templates,unlockFlags={},{}
local catalogReady=false
local function catalogue()
    if catalogReady then return end
    -- Loaded lazily: the store builds spell recipes after loading this module.
    for _,recipe in ipairs(NHStore.recipes) do
        if recipe.category=="spell" and recipe.item and recipe.item.kind=="spell" then
            if not kinds[recipe.id] then spells[#spells+1]=recipe.id end
            kinds[recipe.id]="recipe"
            unlockFlags[recipe.id]=recipe.unlockFlag
        end
        if kinds[recipe.id]=="recipe" then templates[recipe.id]=recipe.item end
    end
    table.sort(spells)
    catalogReady=true
end
local function availableSpells()
    local pool={}
    for _,key in ipairs(spells) do
        local flag=unlockFlags[key]
        if not flag or HasFlagPersistent(flag) then pool[#pool+1]=key end
    end
    return pool
end
local function itemFor(key)
    if kinds[key]=="bag" then return NHLootBags.item(key,1) end
    if kinds[key]=="wand" then return M.wandItem(key) end
    if kinds[key]=="card" or kinds[key]=="tarot" then
        local species=cardSpecies[key] or key
        return NHCompanions.withCount({species=species,remaining=NHCompanions.cardCapacity(species)},1)
    end
    if kinds[key]=="container" then
        local powder=key=="sand" or key=="gunpowder"
        local capacity=powder and 1500 or 1000
        return {kind="potion",variant=powder and "powder_stash" or nil,materials={[key]=capacity},capacity=capacity,
            icon=powder and "data/ui_gfx/items/material_pouch.png" or "data/ui_gfx/items/potion.png"}
    end
    -- The store loads the workshop catalogue after the farm. Use the same native
    -- spell card (including charges), item descriptions and art as the workshop.
    catalogue()
    local item=copy(assert(templates[key],"Missing dragon discovery: "..key))
    if item.count then item.count=1 end
    return item
end

local function deliver(state)
    catalogue()
    local book=state.dragonLoot
    local pending=book.pending
    for _,group in ipairs(deliveryGroups) do
        for _,key in ipairs(group.keys) do
            while pending[key] do
                local item,wandSlot
                if key=="random_wand" then
                    wandSlot=NHStore.freeSlot(state,"warehouse",nil,"wand")
                    if not wandSlot or state.nextItemId>=NHStore.maxResourceAmount then break end
                    item=NHWand.generateDiscovery(book.wandSeed)
                    if not item then break end
                    book.wandSeed=advance(book.wandSeed)
                else
                    item=itemFor(key)
                end
                local quantity=1
                if item.kind=="summon_card" then
                    local slot,index=NHCompanions.cardSlot(state,"warehouse",nil,item)
                    if not slot then break end
                    local existing=index and (state.warehouse[index].item.count or 1) or 0
                    quantity=math.min(pending[key],NHStore.maxResourceAmount-existing)
                    if not NHCompanions.put(state,"warehouse",slot,index,NHCompanions.withCount(item,quantity)) then break end
                else
                    local slot,index
                    if group.kind=="bag" then
                        slot,index=NHStore.stackSlot(state,"warehouse",item)
                        local existing=index and (state.warehouse[index].item.count or 1) or 0
                        quantity=math.min(pending[key],2147483647-existing)
                        item.count=quantity+existing
                    end
                    if index then
                        local row=state.warehouse[index]
                        state.warehouse[index]={slot=slot,id=row.id,origin=row.origin,item=item}
                    else
                        slot=wandSlot or NHStore.freeSlot(state,"warehouse",nil,item.kind)
                        if not slot or state.nextItemId>=NHStore.maxResourceAmount then break end
                        state.warehouse[#state.warehouse+1]={slot=slot,id=state.nextItemId,item=item}
                        state.nextItemId=state.nextItemId+1
                    end
                end
                pending[key]=pending[key]>quantity and pending[key]-quantity or nil
            end
        end
    end
end

function M.rareProgress(state)
    return state.dragonLoot and state.dragonLoot.rareProgress or 0
end

-- Discoveries 4, 7, 10, ... are rare. The same two seed advances per find
-- select its category and item regardless of when a full warehouse can pay.
local function categoryRoll(book,legacy)
    if legacy then return book.seed%100 end
    local progress=(book.rareProgress or 0)+rareShare
    book.rareProgress=progress%100
    if progress>=100 then return book.seed%rareShare end
    return rareShare+book.seed%(100-rareShare)
end

-- Run on a detached farm settlement alongside the bank credit and new deadline.
-- Already-earned discoveries from older saves use their original single roll.
function M.award(state,periods,legacy)
    local awards={}
    if periods==0 then return awards end
    catalogue()
    local spellPool=availableSpells()
    local book=state.dragonLoot
    if not book then
        local worldSeed=StatsGetValue and tonumber(StatsGetValue("world_seed")) or 0
        book={seed=1+(worldSeed%modulus+state.profile*15485863+45989)%(modulus-1),pending={}}
        state.dragonLoot=book
    end
    for _=1,periods do
        book.seed=advance(book.seed)
        local roll=categoryRoll(book,legacy)
        for _,group in ipairs(groups) do
            if roll<group.cutoff then
                book.seed=advance(book.seed)
                local pool=group.keys==spells and spellPool or group.keys
                local key=pool[1+book.seed%#pool]
                -- Pending wands consume consecutive seeds on delivery. A full
                -- warehouse can retain the entire sequence with just a count.
                if key=="random_wand" and not book.wandSeed then book.wandSeed=book.seed end
                book.pending[key]=(book.pending[key] or 0)+1
                if group.kind=="card" or group.kind=="tarot" then awards[#awards+1]=cardSpecies[key] or key end
                break
            end
        end
    end
    deliver(state)
    return awards
end

-- NHStore.commit also receives shallow transfer drafts. Never consume the
-- original pending book or mutate its item rows before the new revision lands.
function M.stageDelivery(state)
    if not state.dragonLoot or not next(state.dragonLoot.pending) then return end
    state.dragonLoot=copy(state.dragonLoot)
    local pending=state.dragonLoot.pending
    if pending.metal_knife then
        pending.derringer=(pending.derringer or 0)+pending.metal_knife
        pending.metal_knife=nil
    end
    local rows={}
    for i,row in ipairs(state.warehouse) do rows[i]=row end
    state.warehouse=rows
    deliver(state)
end

function M.pendingCount(state)
    local count=0
    for _,n in pairs(state.dragonLoot and state.dragonLoot.pending or {}) do count=count+n end
    return count
end

function M.pendingCards(state)
    local count=0
    for key,n in pairs(state.dragonLoot and state.dragonLoot.pending or {}) do
        if kinds[key]=="card" or kinds[key]=="tarot" then count=count+n end
    end
    return count
end

function M.validate(state,whole)
    catalogue()
    local book=state.dragonLoot
    if not book then return end
    assert(type(book)=="table" and whole(book.seed) and book.seed>0 and book.seed<modulus
        and type(book.pending)=="table","Invalid dragon discoveries")
    assert(book.rareProgress==nil or (whole(book.rareProgress) and book.rareProgress>=0 and book.rareProgress<100),
        "Invalid dragon rare discovery progress")
    assert((not book.wandSeed and not book.pending.random_wand) or
        (whole(book.wandSeed) and book.wandSeed>0 and book.wandSeed<modulus),"Invalid dragon wand seed")
    for key,number in pairs(book.pending) do
        assert((kinds[key] or key=="metal_knife") and whole(number) and number>0,"Invalid pending dragon discovery")
    end
end

return M
