local M={bonusChance=30}
local modulus=2147483647

local function copy(t)
    local result={}
    for key,value in pairs(t) do result[key]=value end
    return result
end

local function deliver(state)
    local book=state.gelBonus
    if book.spice then
        local stock=state.resources.spice or 0
        local amount=math.min(book.spice,NHStore.maxResourceAmount-stock)
        if amount>0 then
            state.resources.spice=stock+amount
            book.spice=book.spice>amount and book.spice-amount or nil
        end
    end
    for _,subtype in ipairs(NHInjectors.order) do
        while book.pending[subtype] do
            local slot,index=NHStore.stockDoseSlot(state,subtype)
            if not slot then break end
            local row=index and state.warehouse[index]
            local stock=row and (row.item.count or 1) or 0
            local amount=math.min(book.pending[subtype],NHStore.maxResourceAmount-stock)
            local item={kind="dose",subtype=subtype,remaining=NHStore.doseDurability,count=stock+amount}
            if row then
                state.warehouse[index]={slot=slot,id=row.id,item=item}
            else
                state.warehouse[#state.warehouse+1]={slot=slot,id=state.nextItemId,item=item}
                state.nextItemId=state.nextItemId+1
            end
            book.pending[subtype]=book.pending[subtype]>amount and book.pending[subtype]-amount or nil
        end
    end
end

-- A separate persisted roll selects the paired bonus. Its delivery and the
-- independent companion roll never advance the bonus stream on a retry.
function M.award(state,cycles)
    local book=state.gelBonus
    if not book then
        local world=StatsGetValue and tonumber(StatsGetValue("world_seed")) or 0
        book={seed=1+(world%modulus+state.profile*15485863+96281)%(modulus-1),pending={}}
        state.gelBonus=book
    end
    for _=1,cycles do
        book.seed=book.seed*48271%modulus
        if book.seed%100<M.bonusChance then
            book.seed=book.seed*48271%modulus
            local subtype=NHInjectors.order[1+book.seed%#NHInjectors.order]
            book.pending[subtype]=(book.pending[subtype] or 0)+1
            book.spice=(book.spice or 0)+1
        end
    end
    deliver(state)
end

function M.stageDelivery(state)
    local book=state.gelBonus
    if not book or (not next(book.pending) and not book.spice) then return end
    -- The commit may receive a shallow transfer draft. Keep its original
    -- pending rewards, item rows and spice unchanged if publication fails.
    state.gelBonus={seed=book.seed,pending=copy(book.pending),spice=book.spice}
    state.warehouse=copy(state.warehouse)
    if book.spice then state.resources=copy(state.resources) end
    deliver(state)
end

function M.pendingDoses(state)
    local n=0
    for _,count in pairs(state.gelBonus and state.gelBonus.pending or {}) do n=n+count end
    return n
end

function M.validate(state,whole)
    local book=state.gelBonus
    if not book then return end
    assert(type(book)=="table" and whole(book.seed) and book.seed>0 and book.seed<modulus
        and type(book.pending)=="table" and (not book.spice or whole(book.spice) and book.spice>0),
        "Invalid gel pool harvest")
    for subtype,count in pairs(book.pending) do
        assert(NHInjectors.types[subtype] and whole(count) and count>0,"Invalid pending gel pool injector")
    end
end

return M
