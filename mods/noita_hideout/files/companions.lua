NHCompanions={durability=80,order={"dryad","flower_fairy","minotaur","griffin"}}
local items="mods/noita_hideout/files/items/"
local pets="mods/noita_hideout/files/companions/"
NHCompanions.species={
    dryad={zh="树精",en="Dryad",gift="bread",effect="effect_protection_radioactivity",damage=0.22},
    flower_fairy={zh="花妖",en="Flower fairy",gift="bandage",damage=0.16},
    minotaur={zh="米诺陶少女",en="Minotaur maiden",gift="bandage",effect="effect_protection_melee",damage=0.32},
    griffin={zh="狮鹫少女",en="Griffin maiden",gift="sugar_cube",effect="effect_faster_levitation",damage=0.24},
}
-- Shield recharge uses the native EnergyShieldComponent scale (0.22 on the perk shield).
NHCompanions.bonuses={
    [0]={fairySeconds=5,dryadSeconds=0,shieldRecharge=0,flightPercent=0,giftSeconds=30},
    [1]={fairySeconds=4,dryadSeconds=12,shieldRecharge=0.08,flightPercent=5,giftSeconds=25},
    [2]={fairySeconds=3,dryadSeconds=9,shieldRecharge=0.15,flightPercent=10,giftSeconds=20},
    [3]={fairySeconds=2,dryadSeconds=6,shieldRecharge=0.22,flightPercent=15,giftSeconds=15},
}
local families={farm={"dryad","flower_fairy"},livestock={"minotaur","griffin"}}
local modulus=2147483647

local function card(id,remaining)
    return {kind="summon_card",species=id,remaining=remaining,name="$nh_card_"..id,icon=items.."card_"..id..".png"}
end

function NHCompanions.withCount(item,count)
    local result=card(item.species,item.remaining)
    if count>1 then result.count=count end
    return result
end

function NHCompanions.validCard(item)
    local n=item.remaining
    local count=item.count
    return NHCompanions.species[item.species]~=nil and type(n)=="number" and n==math.floor(n) and n>=1 and n<=NHCompanions.durability
        and (count==nil or (type(count)=="number" and count==math.floor(count) and count>=1 and count<=NHStore.maxResourceAmount
            and (n==NHCompanions.durability or count==1)))
end

function NHCompanions.canStack(target,source)
    return target and source and target.kind=="summon_card" and source.kind=="summon_card"
        and target.species==source.species and target.remaining==NHCompanions.durability
        and source.remaining==NHCompanions.durability and (target.count or 1)<NHStore.maxResourceAmount
end

-- A specified storage slot must accept the card; automatic deposits prefer
-- an existing full-condition stack even when every storage slot is occupied.
function NHCompanions.cardSlot(s,container,preferred,item)
    if container~="warehouse" and container~="safe" then return end
    if preferred then
        local index=NHStore.slotIndex(s,container,preferred,"summon_card")
        if index then
            if NHCompanions.canStack(s[container][index].item,item) then return preferred,index end
            return
        end
    else
        local slot,at
        for i,row in ipairs(s[container]) do
            if NHCompanions.canStack(row.item,item) and (not slot or (row.slot or i)<slot) then
                slot,at=row.slot or i,i
            end
        end
        if at then return slot,at end
    end
    return NHStore.freeSlot(s,container,preferred,"summon_card")
end

-- Replace rows to keep shallow transfer drafts isolated until their commit succeeds.
function NHCompanions.put(s,container,slot,index,item,id,origin)
    if not slot then return false end
    local rows=s[container]
    if index then
        local row=rows[index]
        local count=row.item.count or 1
        local added=item.count or 1
        if not NHCompanions.canStack(row.item,item) or added>NHStore.maxResourceAmount-count then return false end
        rows[index]={id=row.id,origin=row.origin,slot=slot,item=NHCompanions.withCount(item,count+added)}
    else
        if not id then
            if s.nextItemId>=NHStore.maxResourceAmount then return false end
            id=s.nextItemId
            s.nextItemId=id+1
        end
        rows[#rows+1]={id=id,origin=origin,slot=slot,item=item}
    end
    return true
end

function NHCompanions.take(s,container,index)
    local rows=s[container]
    local row=rows[index]
    if not row or row.item.kind~="summon_card" then return end
    local count=row.item.count or 1
    if count==1 then return table.remove(rows,index) end
    if s.nextItemId>=NHStore.maxResourceAmount then return end
    rows[index]={id=row.id,origin=row.origin,slot=row.slot,item=NHCompanions.withCount(row.item,count-1)}
    local one={id=s.nextItemId,slot=row.slot,item=NHCompanions.withCount(row.item,1)}
    s.nextItemId=s.nextItemId+1
    return one
end

function NHCompanions.moveCard(s,from,sourceSlot,to,targetSlot,expectedId)
    if (from~="warehouse" and from~="safe") or (to~="warehouse" and to~="safe")
        or not targetSlot or (from==to and sourceSlot==targetSlot) then return false,"Inventory slot changed." end
    local index=NHStore.slotIndex(s,from,sourceSlot,"summon_card")
    local row=index and s[from][index]
    if not row or row.id~=expectedId or row.item.kind~="summon_card" then return false,"Inventory slot changed." end
    local slot,stack=NHCompanions.cardSlot(s,to,targetSlot,row.item)
    if not slot then return false,"Inventory slot changed." end
    local one=NHCompanions.take(s,from,index)
    if not one then return false,"Inventory slot changed." end
    if stack and from==to then stack=NHStore.slotIndex(s,to,targetSlot,"summon_card") end
    return NHCompanions.put(s,to,slot,stack,one.item,one.id,one.origin)
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
            local item=card(id,NHCompanions.durability)
            local slot,index=NHCompanions.cardSlot(state,"warehouse",nil,item)
            if not slot then break end
            local amount=pending[id]
            if index then amount=math.min(amount,NHStore.maxResourceAmount-(state.warehouse[index].item.count or 1)) end
            if not NHCompanions.put(state,"warehouse",slot,index,NHCompanions.withCount(item,amount)) then break end
            pending[id]=pending[id]>amount and pending[id]-amount or nil
        end
    end
end

-- Transfer drafts share their parent's reward book. Stage any delivery into
-- detached tables until the settings commit pointer has been published.
function NHCompanions.stageDelivery(state)
    local book=state.summons
    if not book or not next(book.pending) then return end
    local pending={}
    for id,n in pairs(book.pending) do pending[id]=n end
    state.summons={farm=book.farm,livestock=book.livestock,pending=pending}
    local rows={}
    for i,row in ipairs(state.warehouse) do rows[i]=row end
    state.warehouse=rows
    NHCompanions.deliver(state)
end

function NHCompanions.grantSet(state)
    local book=state.summons or {pending={}}
    for _,id in ipairs(NHCompanions.order) do
        if (book.pending[id] or 0)>=NHStore.maxResourceAmount then return false,"Resource storage is full." end
    end
    state.summons=book
    for _,id in ipairs(NHCompanions.order) do book.pending[id]=(book.pending[id] or 0)+1 end
    NHCompanions.deliver(state)
    return true
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
        return message..(zh and "。藏品库已满，腾出栏位后自动入库。" or ". Waiting for a free collection slot.")
    end
    return message
end

local function speciesOf(entity)
    for _,id in ipairs(NHCompanions.order) do
        if EntityHasTag(entity,"nh_companion_"..id) then return id end
    end
end

function NHCompanions.captureCard(entity)
    local id=speciesOf(entity)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    if id and item then
        local record=card(id,ComponentGetValue2(item,"uses_remaining"))
        if NHCompanions.validCard(record) then return record end
    end
    return nil,"Invalid summon card."
end

function NHCompanions.registerItems()
    NHTransfers.registerItem("summon_card",function(entity) return EntityHasTag(entity,"noita_hideout_summon_card") end,{
        warehouseCategory="collection",
        capture=NHCompanions.captureCard,
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

local function dismiss(entity)
    EntityRemoveFromParent(entity)
    EntityKill(entity)
end

-- Older worlds have only the per-effect tags. Native perks, food and
-- injectors with the same GameEffectComponent do not carry these tags.
local supportTags={"noita_hideout_companion_aura","nh_companion_effect_protection_radioactivity",
    "nh_companion_effect_protection_melee","nh_companion_effect_faster_levitation"}
function NHCompanions.clearSupport(player)
    for _,tag in ipairs(supportTags) do
        for _,aura in ipairs(EntityGetAllChildren(player,tag) or {}) do
            dismiss(aura)
        end
    end
end

function NHCompanions.use(player,entity,lang)
    if not EntityHasTag(entity,"noita_hideout_summon_card") or GameIsInventoryOpen() or NHNative.held(player)~=entity then return end
    local id=speciesOf(entity)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    local remaining=item and ComponentGetValue2(item,"uses_remaining")
    if not NHCompanions.validCard({species=id,remaining=remaining}) then return end
    local previous=EntityGetAllChildren(player,"noita_hideout_companion") or {}
    local x,y=EntityGetTransform(player)
    local pet=EntityLoad(pets..id..".xml",x+12,y-8)
    if not pet or pet==0 then return end
    local clock=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_companion_clock")
    local gifts=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_gifts")
    if not (gifts and clock and ComponentGetValue2(clock,"value_string")==id
        and EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_trip")
        and EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_position")) then
        EntityKill(pet)
        return
    end
    ComponentSetValue2(gifts,"value_int",ProceduralRandomi(x+GameGetFrameNum(),y,1,1000000))
    EntityAddChild(player,pet)
    if EntityGetParent(pet)~=player then EntityKill(pet); return end
    -- The 64-pixel source frames are displayed at half size in the world.
    EntitySetTransform(pet,x+12,y-8,0,0.5,0.5)
    for _,child in ipairs(previous) do
        if EntityGetIsAlive(child) then dismiss(child) end
    end
    NHCompanions.clearSupport(player)
    if remaining==1 then GameKillInventoryItem(player,entity)
    else ComponentSetValue2(item,"uses_remaining",remaining-1) end
    local spec=NHCompanions.species[id]
    GamePrint(lang=="zh" and (spec.zh.."开始随行。") or (spec.en.." joined you."))
    return true
end
