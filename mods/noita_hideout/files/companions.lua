NHCompanions={durability=3,order={"dryad","flower_fairy","minotaur","griffin"}}
local items="mods/noita_hideout/files/items/"
local pets="mods/noita_hideout/files/companions/"
NHCompanions.species={
    dryad={zh="树精",en="Dryad",gift="bread",effect="effect_protection_radioactivity",damage=0.22},
    flower_fairy={zh="花妖",en="Flower fairy",gift="bandage",damage=0.16},
    minotaur={zh="米诺陶少女",en="Minotaur maiden",gift="bandage",effect="effect_protection_melee",damage=0.32},
    griffin={zh="狮鹫少女",en="Griffin maiden",gift="sugar_cube",effect="effect_faster_levitation",damage=0.24},
}
local families={farm={"dryad","flower_fairy"},livestock={"minotaur","griffin"}}
local modulus=2147483647

local function card(id,remaining)
    return {kind="summon_card",species=id,remaining=remaining,name="$nh_card_"..id,icon=items.."card_"..id..".png"}
end

function NHCompanions.validCard(item)
    local n=item.remaining
    return NHCompanions.species[item.species]~=nil and type(n)=="number" and n==math.floor(n) and n>=1 and n<=NHCompanions.durability
end

function NHCompanions.validate(state,whole)
    if not state.summons then return end
    for source in pairs(families) do
        local seed=state.summons[source]
        assert(seed==nil or (whole(seed) and seed>0 and seed<modulus),"Invalid summon reward sequence")
    end
    for id,amount in pairs(state.summons.pending) do
        assert(NHCompanions.species[id] and whole(amount) and amount>0,"Invalid pending summon cards")
    end
end

function NHCompanions.deliver(state)
    local pending=state.summons and state.summons.pending
    if not pending or not next(pending) then return end
    for _,id in ipairs(NHCompanions.order) do
        while pending[id] do
            local slot=NHStore.freeSlot(state,"warehouse",nil,"summon_card")
            if not slot or state.nextItemId>=NHStore.maxResourceAmount then return end
            state.warehouse[#state.warehouse+1]={slot=slot,id=state.nextItemId,item=card(id,NHCompanions.durability)}
            state.nextItemId=state.nextItemId+1
            pending[id]=pending[id]>1 and pending[id]-1 or nil
        end
    end
end

-- Transfer drafts share their parent's reward book. Stage any delivery into
-- detached tables until the settings commit pointer has been published.
function NHCompanions.stageDelivery(state)
    local book=state.summons
    if not book or not next(book.pending) or not NHStore.freeSlot(state,"warehouse",nil,"summon_card") then return end
    local pending={}
    for id,n in pairs(book.pending) do pending[id]=n end
    state.summons={farm=book.farm,livestock=book.livestock,pending=pending}
    local rows={}
    for i,row in ipairs(state.warehouse) do rows[i]=row end
    state.warehouse=rows
    NHCompanions.deliver(state)
end

-- One persistent roll per successful crop or animal production cycle, in the
-- same transaction as its produce. Batched collection has the same odds.
function NHCompanions.reward(state,source,units)
    local family=assert(families[source])
    local book=state.summons or {pending={}}
    state.summons=book
    local seed=book[source]
    if not seed then
        local world=StatsGetValue and tonumber(StatsGetValue("world_seed")) or 0
        seed=1+(world%modulus+state.profile*15485863+(source=="farm" and 126 or 7918))%(modulus-1)
    end
    local found={}
    for _=1,units do
        seed=seed*48271%modulus
        if seed%100<3 then
            seed=seed*48271%modulus
            local id=family[1+seed%2]
            book.pending[id]=(book.pending[id] or 0)+1
            found[#found+1]=id
        end
    end
    book[source]=seed
    NHCompanions.deliver(state)
    return found
end

function NHCompanions.rewardText(ids,lang,state)
    local names={}
    for _,id in ipairs(ids) do names[#names+1]=NHCompanions.species[id][lang=="zh" and "zh" or "en"] end
    local zh=lang=="zh"
    local message=(zh and "获得召唤卡：" or "Summon cards: ")..table.concat(names,zh and "、" or ", ")
    if next(state.summons.pending) then
        return message..(zh and "。装备库已满，腾出栏位后自动入库。" or ". Waiting for a free equipment slot.")
    end
    return message
end

local function speciesOf(entity)
    for _,id in ipairs(NHCompanions.order) do
        if EntityHasTag(entity,"nh_companion_"..id) then return id end
    end
end

function NHCompanions.registerItems()
    NHTransfers.registerItem("summon_card",function(entity) return EntityHasTag(entity,"noita_hideout_summon_card") end,{
        warehouseCategory="equipment",
        capture=function(entity)
            local id=speciesOf(entity)
            local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
            if not id or not item then return nil,"Invalid summon card." end
            local record=card(id,ComponentGetValue2(item,"uses_remaining"))
            if NHCompanions.validCard(record) then return record end
            return nil,"Invalid summon card."
        end,
        restore=function(record,x,y)
            if not NHCompanions.validCard(record) then return nil,"Invalid summon card." end
            local entity=EntityLoad(items.."card_"..record.species..".xml",x,y)
            if not entity or entity==0 then return nil,"Summon card could not be created." end
            local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
            if not item then EntityKill(entity); return nil,"Invalid summon card." end
            ComponentSetValue2(item,"uses_remaining",record.remaining)
            return entity
        end,
    })
end

function NHCompanions.use(player,entity,lang)
    if not EntityHasTag(entity,"noita_hideout_summon_card") or GameIsInventoryOpen() or NHNative.held(player)~=entity then return end
    local id=speciesOf(entity)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    local remaining=item and ComponentGetValue2(item,"uses_remaining")
    if not NHCompanions.validCard({species=id,remaining=remaining}) then return end
    for _,child in ipairs(EntityGetAllChildren(player,"noita_hideout_companion") or {}) do
        if EntityGetIsAlive(child) then
            GamePrint(lang=="zh" and "已有伙伴随行。" or "A companion is already with you.")
            return true
        end
    end
    local x,y=EntityGetTransform(player)
    local pet=EntityLoad(pets..id..".xml",x+12,y-8)
    if not pet or pet==0 then return end
    local gifts=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_gifts")
    if not gifts then EntityKill(pet); return end
    ComponentSetValue2(gifts,"value_int",ProceduralRandomi(x+GameGetFrameNum(),y,1,1000000))
    EntityAddChild(player,pet)
    if EntityGetParent(pet)~=player then EntityKill(pet); return end
    if remaining==1 then GameKillInventoryItem(player,entity)
    else ComponentSetValue2(item,"uses_remaining",remaining-1) end
    local spec=NHCompanions.species[id]
    GamePrint(lang=="zh" and (spec.zh.."开始随行。") or (spec.en.." joined you."))
    return true
end
