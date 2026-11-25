-- Whole items and fractional work are kept separately so large inventories
-- never need to be multiplied by the common fixed-point denominator.
local M={}
local pets=dofile("mods/noita_hideout/files/pet_minutes.lua")
M.petRates,M.dogBundles=pets.rates,pets.dogBundles
local scale=10000
local cycle=216000 -- divisible by every crop and animal period, in frames
local divisor=cycle*scale
local housing={livestock=true,beehive=true,dragon_nest=true,gel_pool=true,dog_kennel=true,cat_house=true}
local sources={"farm","livestock","beehive","dragon","gel_pool","dog_kennel","cat_house"}
local balances={"fiber","herb","grain","sugar","spice","active_herb","egg","milk","meat","gold","dog","cat"}
local function add(t,id,n)
    if n>0 then t[id]=(t[id] or 0)+n end
end
local function rareBook() return {counts={},private={}} end

function M.levelBonus(id,level)
    if id=="agri_equipment" then return level>0 and 400 or 0 end
    if id=="farmland" then return math.max(0,level-1)*200 end
    return housing[id] and math.max(0,level-1)*500 or 0
end

function M.bonus(state,facility,source,pet,basis)
    local amount=M.levelBonus(facility,NHStore.level(state,facility))
    if facility=="farmland" then amount=amount+M.levelBonus("agri_equipment",NHStore.level(state,"agri_equipment")) end
    if pet and NHCompanions.productionMatch(source,pet) then amount=amount+basis end
    return amount
end

local function credit(book,id,frames,workers,period,amount,basis,earnedId)
    if workers==0 or frames==0 or basis==0 then return end
    local rate=workers*amount*basis
    -- First separate the whole cycles, then their whole units and fractional
    -- basis points. The partial-cycle product is bounded even on catch-up.
    local cycles=math.floor(frames/period)
    local whole=math.floor(cycles/scale)*rate
    local part=(cycles%scale)*rate
    whole=whole+math.floor(part/scale)
    local sub=(book.remainder[id] or 0)+(part%scale)*cycle+(frames%period)*(cycle/period)*rate
    add(book.open,earnedId or id,whole+math.floor(sub/divisor))
    local remainder=sub%divisor
    book.remainder[id]=remainder>0 and remainder or nil
end

local function bagSpecies(species) return species=="dog" or species=="cat" end

local function herdFixed(book,species,frames,workers,bonus)
    local kind=NHLivestock.species[species]
    if bagSpecies(species) then return end
    for _,part in ipairs(kind.yields) do
        if part[1]~="loot" then credit(book,part[1],frames,workers,kind.period,part[2],scale+bonus) end
    end
end

local function privateRolls(queue,id,chance,count)
    local last=queue[#queue]
    if last and last.id==id and last.chance==chance then last.count=last.count+count
    else queue[#queue+1]={id=id,chance=chance,count=count} end
end

local function record(book,source,count,span)
    if count==0 then return end
    add(book.counts,source,count)
    if span and NHCompanions.productionMatch(source,span.id) then
        local chance=NHAffinity.incomeBasisPoints(span.points)
        if chance>0 then privateRolls(book.private,span.id,chance,count) end
    end
end

local function close(book)
    for id,amount in pairs(book.open) do add(book.owed,id,amount) end
    for id,count in pairs(book.openRare.counts) do add(book.rare.counts,id,count) end
    for _,roll in ipairs(book.openRare.private) do privateRolls(book.rare.private,roll.id,roll.chance,roll.count) end
    book.open,book.openRare={},rareBook()
    if book.openLegacyDragon then
        book.legacyDragon=(book.legacyDragon or 0)+book.openLegacyDragon
        book.openLegacyDragon=nil
    end
end

-- Existing minutes may have closed while the warehouse was full, or be
-- partly open after a facility upgrade. Honor those discoveries at old rates.
local function convertSearches(farm)
    local book=farm.minuteIncome
    if book.searchVersion then return end
    for _,entry in ipairs({{book.openRare.counts,book.open,"openLegacyDragon"},{book.rare.counts,book.owed,"legacyDragon"}}) do
        local counts,debts=entry[1],entry[2]
        add(debts,"dog",counts.dog_kennel or 0)
        add(debts,"cat",counts.cat_house or 0)
        book[entry[3]]=counts.dragon
    end
    for _,key in ipairs({"dog","cat"}) do
        local herd=(farm.herds or {})[key]
        if herd and herd.progress>0 then
            local share=herd.progress*(divisor/NHLivestock.species[key].period)
            if key=="dog" then
                add(book.remainder,"travel_satchel",share)
                add(book.remainder,"travel_pack",share)
            else add(book.remainder,"loot_case",share) end
        end
    end
    book.searchVersion=1
end

-- Retire already-earned legacy batches at face value. Partial cycles become
-- minute credit at the historical base rate and keep their rare-roll phase.
function M.adopt(state)
    local farm=state.farm
    if farm.minuteIncome then convertSearches(farm); return end
    local book={remainder={},open={},owed={},openRare=rareBook(),rare=rareBook()}
    farm.minuteIncome=book
    -- Old snapshots recorded uncollected batches, but only determined their
    -- private card chance at collection. Capture that opportunity exactly once.
    local id,_,points=NHCompanions.productionCurrent(state)
    local collector=id and {id=id,points=points}
    for id,count in pairs(farm.pending or {}) do
        add(book.owed,id,count*NHFarm.crops[id].amount)
        record(book.rare,"farm",count,collector)
    end
    farm.pending=nil
    for _,plot in pairs(farm.plots) do
        if plot.crop then
            local kind=assert(NHFarm.crops[plot.crop],"Unknown legacy crop")
            local count=math.max(0,1+math.floor((farm.time-plot.readyAt)/kind.frames))
            add(book.owed,plot.crop,count*kind.amount)
            record(book.rare,"farm",count,collector)
            plot.readyAt=plot.readyAt+count*kind.frames
            credit(book,plot.crop,math.max(0,kind.frames-(plot.readyAt-farm.time)),1,kind.frames,kind.amount,scale)
        end
    end
    for species,herd in pairs(farm.herds or {}) do
        local kind=NHLivestock.species[species]
        local source=species=="dragon_egg" and "dragon" or kind.facility or "livestock"
        record(book.rare,source,herd.owed,collector)
        if not bagSpecies(species) then
            for _,part in ipairs(kind.yields) do
                if part[1]~="loot" then add(book.owed,part[1],herd.owed*part[2]) end
            end
            herdFixed(book,species,herd.progress,1,0)
        end
        herd.owed=0
    end
    convertSearches(farm)
end

local function segment(state,from,to,span)
    if to<=from then return end
    local farm=state.farm
    local book=farm.minuteIncome
    local pet,basis=span and span.id,span and span.basis
    pets.accrue(state,from,to,pet,basis,credit,M.bonus)
    local cropBonus=M.bonus(state,"farmland","farm",pet,basis)
    for _,plot in pairs(farm.plots) do
        if plot.crop then
            local kind=NHFarm.crops[plot.crop]
            credit(book,plot.crop,to-from,1,kind.frames,kind.amount,scale+cropBonus)
            if plot.readyAt<=to then
                local count=1+math.floor((to-plot.readyAt)/kind.frames)
                record(book.openRare,"farm",count,span)
                plot.readyAt=plot.readyAt+count*kind.frames
            end
        end
    end
    for _,species in ipairs(NHLivestock.order) do
        local herd=(farm.herds or {})[species]
        if herd then
            local kind=NHLivestock.species[species]
            local facility=kind.facility or "livestock"
            local source=species=="dragon_egg" and "dragon" or facility
            local bonus=M.bonus(state,facility,source,pet,basis)
            herdFixed(book,species,to-from,herd.adults,bonus)
            local progress,count,matured=NHLivestock.project(herd,kind.period,from,to)
            for i=1,matured do herdFixed(book,species,to-herd.young[i],1,bonus) end
            herd.adults=herd.adults+matured
            for i=1,matured do table.remove(herd.young,1) end
            herd.progress=progress
            record(book.openRare,source,count,span)
        end
    end
end

function M.advance(state,from,to)
    if to<=from then return end
    local cursor=from
    for _,span in ipairs(NHCompanions.productionSegments(state,from,to)) do
        segment(state,cursor,span.from)
        segment(state,span.from,span.to,span)
        cursor=span.to
    end
    segment(state,cursor,to)
end
M.close=close

local function room(state,id)
    if id=="gold" then return NHStore.maxGold-state.bankGold end
    return NHStore.maxResourceAmount-(state.resources[id] or 0)
end

-- Published profiles are immutable between transactions. Remember a failed
-- warehouse fit on that snapshot rather than making scratch rows every frame.
local blockedBags=setmetatable({},{__mode="k"})
function M.bagBlocked(state,id)
    local cache=blockedBags[state]
    local capacity=NHStore.warehouseCapacity(state,"supplies")
    if not cache or cache.revision~=state.revision or cache.rows~=state.warehouse or cache.length~=#state.warehouse
        or cache.nextId~=state.nextItemId or cache.capacity~=capacity then
        cache={revision=state.revision,rows=state.warehouse,length=#state.warehouse,nextId=state.nextItemId,capacity=capacity}
        blockedBags[state]=cache
    end
    if cache[id]==nil then cache[id]=NHLivestock.bagPayment(state,id,1)==0 end
    return cache[id]
end

function M.ready(state)
    local book=state.farm.minuteIncome
    if not book then return false end
    if next(book.rare.counts) or #book.rare.private>0 then return true end
    if pets.ready(state) then return true end
    for id in pairs(book.owed) do
        if bagSpecies(id) then
            if not M.bagBlocked(state,id) then return true end
        elseif id=="dog_find" or id=="cat1" or id=="cat2" or id=="cat3"
            or id=="travel_satchel" or id=="travel_pack" or id=="loot_case" then return true
        elseif room(state,id)>0 then return true end
    end
    return false
end

function M.petFraction(state,id)
    local book=state.farm.minuteIncome
    return book and (book.remainder[id] or 0)/divisor or 0
end

function M.petPending(state,species)
    local book=state.farm.minuteIncome
    return pets.pending(state,species)+(book and book.owed[species] or 0)*(species=="dog" and 2 or 1)
end

function M.petSharedPending(state)
    return pets.pending(state,"shared")
end

function M.petBlocked(state,species)
    local book=state.farm.minuteIncome
    if not book then return false end
    if species=="dog" then
        for _,bundle in ipairs(M.dogBundles) do
            if book.owed[bundle[1]] and room(state,bundle[1])==0 then return true end
        end
    end
    return (book.owed[species] and M.bagBlocked(state,species))
        or pets.pending(state,species,true)>0 or pets.pending(state,"shared",true)>0
end

function M.pay(state)
    local book=state.farm.minuteIncome
    local rare=book.rare
    local produced,awards=false,{}
    for _,source in ipairs(sources) do
        local total=rare.counts[source] or 0
        local count=math.min(total,NHFarm.batchLimit)
        if count>0 then
            local found
            if source=="dragon" then
                local legacy=math.min(book.legacyDragon or 0,count)
                if legacy>0 then
                    local cards=NHDragonLoot.award(state,legacy,true)
                    for _,id in ipairs(cards) do awards[#awards+1]=id end
                    book.legacyDragon=book.legacyDragon>legacy and book.legacyDragon-legacy or nil
                end
                found=NHDragonLoot.award(state,count-legacy)
            else
                if source=="gel_pool" then NHGelPool.award(state,count) end
                found=NHCompanions.reward(state,source,count,true)
            end
            for _,id in ipairs(found) do awards[#awards+1]=id end
            rare.counts[source]=total>count and total-count or nil
            produced=true
        end
    end
    local budget=NHFarm.batchLimit
    while budget>0 and rare.private[1] do
        local roll=rare.private[1]
        local n=math.min(roll.count,budget)
        NHCompanions.productionCardRoll(state,roll.id,roll.chance,n,awards)
        roll.count,budget=roll.count-n,budget-n
        if roll.count==0 then table.remove(rare.private,1) end
        produced=true
    end
    if budget<NHFarm.batchLimit then NHCompanions.deliver(state) end
    if pets.resolve(state) then produced=true end
    -- Fixed priority also keeps competing cat/dog container deliveries
    -- reproducible if only one warehouse slot becomes available.
    for _,id in ipairs(balances) do
        local owed=book.owed[id]
        if owed then
            local count
            if bagSpecies(id) then
                local delivery
                count,delivery=NHLivestock.bagPayment(state,id,owed)
                if delivery then state.warehouse,state.nextItemId=delivery.warehouse,delivery.nextItemId end
            else
                count=math.min(owed,room(state,id))
                if count>0 then
                    if id=="gold" then assert(NHStore.creditGold(state,count))
                    else state.resources[id]=(state.resources[id] or 0)+count end
                end
            end
            if count>0 then
                book.owed[id]=owed>count and owed-count or nil
                produced=true
            end
        end
    end
    if pets.deliver(state) then produced=true end
    return produced,awards
end

function M.validate(farm,whole)
    local book=farm.minuteIncome
    if not book then return end -- old profiles are adopted when loaded
    assert(type(book)=="table" and not farm.pending,"Invalid minute income")
    assert(book.searchVersion==nil or book.searchVersion==1,"Unknown minute search version")
    assert(not book.forage or book.searchVersion,"Missing pet income version")
    pets.validate(book.forage,whole)
    for _,field in ipairs({"remainder","open","owed"}) do
        assert(type(book[field])=="table","Invalid minute balance")
        for id,n in pairs(book[field]) do
            local forage=book.searchVersion and (id=="travel_satchel" or id=="travel_pack" or id=="loot_case" or id=="dog_find"
                or (field=="remainder" and id=="cat_tool") or (field~="remainder" and (id=="cat1" or id=="cat2" or id=="cat3")))
            assert((NHFarm.crops[id] or id=="gold" or id=="egg" or id=="meat" or id=="milk" or forage
                or (field=="owed" or field=="open" and book.searchVersion) and bagSpecies(id)) and whole(n) and n>0 and (field~="remainder" or n<divisor),
                "Invalid minute balance")
        end
    end
    for _,rare in ipairs({assert(book.openRare),assert(book.rare)}) do
        assert(type(rare.counts)=="table" and type(rare.private)=="table","Invalid minute reward schedule")
        for source,n in pairs(rare.counts) do
            local known=false
            for _,id in ipairs(sources) do if id==source then known=true end end
            assert(known and whole(n) and n>0,"Invalid earned production rolls")
        end
        local entries=0
        for i,roll in pairs(rare.private) do
            assert(whole(i) and i>=1 and i<=#rare.private and NHCompanions.species[roll.id] and whole(roll.count)
                and roll.count>0 and whole(roll.chance) and roll.chance>0 and roll.chance<=900,"Invalid companion rolls")
            entries=entries+1
        end
        assert(entries==#rare.private,"Invalid companion roll queue")
    end
    for _,k in ipairs({"legacyDragon","openLegacyDragon"}) do
        local n=book[k]
        local counts=(k=="legacyDragon" and book.rare or book.openRare).counts
        assert(n==nil or (book.searchVersion and whole(n) and n>0 and n<=(counts.dragon or 0)),"Invalid legacy dragon searches")
    end
end

return M
