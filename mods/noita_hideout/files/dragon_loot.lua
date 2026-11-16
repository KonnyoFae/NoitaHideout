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
local spells={"spell_LIGHT_BULLET","spell_LIGHT_BULLET_TRIGGER","spell_BULLET","spell_SPITTER",
    "spell_BOMB","spell_ICEBALL","spell_CLOUD_WATER","spell_DISC_BULLET"}
local containers={"water","slime","magic_liquid_unstable_teleportation","sand","gunpowder"}
local supplies={"medical","bread","sugar_cube","bandage","grenade","metal_knife"}
local groups={
    {cutoff=3,kind="card",keys={"dragon"}},
    {cutoff=8,kind="card",keys=cardPool},
    {cutoff=48,kind="recipe",keys=spells},
    {cutoff=76,kind="container",keys=containers},
    {cutoff=100,kind="recipe",keys=supplies},
}
local kinds={}
for _,group in ipairs(groups) do
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

local templates={}
local function itemFor(key)
    if kinds[key]=="card" then
        return NHCompanions.withCount({species=cardSpecies[key],remaining=NHCompanions.durability},1)
    end
    if kinds[key]=="container" then
        local powder=key=="sand" or key=="gunpowder"
        return {kind="potion",variant=powder and "powder_stash" or nil,materials={[key]=500},capacity=1000,
            icon=powder and "data/ui_gfx/items/material_pouch.png" or "data/ui_gfx/items/potion.png"}
    end
    -- The store loads the workshop catalogue after the farm. Use the same native
    -- spell card (including charges), item descriptions and art as the workshop.
    if not next(templates) then
        for _,recipe in ipairs(NHStore.recipes) do
            if kinds[recipe.id]=="recipe" then templates[recipe.id]=recipe.item end
        end
    end
    local item=copy(assert(templates[key],"Missing dragon discovery: "..key))
    if item.count then item.count=1 end
    return item
end

local function deliver(state)
    local pending=state.dragonLoot.pending
    for _,group in ipairs(groups) do
        for _,key in ipairs(group.keys) do
            while pending[key] do
                local item=itemFor(key)
                local quantity=1
                if item.kind=="summon_card" then
                    local slot,index=NHCompanions.cardSlot(state,"warehouse",nil,item)
                    if not slot then break end
                    local existing=index and (state.warehouse[index].item.count or 1) or 0
                    quantity=math.min(pending[key],NHStore.maxResourceAmount-existing)
                    if not NHCompanions.put(state,"warehouse",slot,index,NHCompanions.withCount(item,quantity)) then break end
                else
                    local slot=NHStore.freeSlot(state,"warehouse",nil,item.kind)
                    if not slot or state.nextItemId>=NHStore.maxResourceAmount then break end
                    state.warehouse[#state.warehouse+1]={slot=slot,id=state.nextItemId,item=item}
                    state.nextItemId=state.nextItemId+1
                end
                pending[key]=pending[key]>quantity and pending[key]-quantity or nil
            end
        end
    end
end

-- Run on a detached farm settlement alongside the bank credit and new deadline.
-- One category roll per cycle: the generic cards and dragon card are exclusive.
function M.award(state,periods)
    local awards={}
    if periods==0 then return awards end
    local book=state.dragonLoot
    if not book then
        local worldSeed=StatsGetValue and tonumber(StatsGetValue("world_seed")) or 0
        book={seed=1+(worldSeed%modulus+state.profile*15485863+45989)%(modulus-1),pending={}}
        state.dragonLoot=book
    end
    for _=1,periods do
        book.seed=advance(book.seed)
        local roll=book.seed%100
        for _,group in ipairs(groups) do
            if roll<group.cutoff then
                book.seed=advance(book.seed)
                local key=group.keys[1+book.seed%#group.keys]
                book.pending[key]=(book.pending[key] or 0)+1
                if group.kind=="card" then awards[#awards+1]=cardSpecies[key] end
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
    state.dragonLoot={seed=state.dragonLoot.seed,pending=copy(state.dragonLoot.pending)}
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
        if kinds[key]=="card" then count=count+n end
    end
    return count
end

function M.validate(state,whole)
    local book=state.dragonLoot
    if not book then return end
    assert(type(book)=="table" and whole(book.seed) and book.seed>0 and book.seed<modulus
        and type(book.pending)=="table","Invalid dragon discoveries")
    for key,number in pairs(book.pending) do
        assert(kinds[key] and whole(number) and number>0,"Invalid pending dragon discovery")
    end
end

return M
