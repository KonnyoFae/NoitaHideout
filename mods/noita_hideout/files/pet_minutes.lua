local finds=dofile("mods/noita_hideout/files/pet_finds.lua")
local M={}
local minute,modulus=3600,2147483647
local dogPeriod,catPeriod=30*minute,60*minute
local food={{"fiber",3},{"grain",2},{"herb",1}}
M.dogBundles=food
local lanes={dog_find=2791,cat1=3371,cat2=3877,cat3=4729,red=5107}

function M.rates(species,adults,bonus)
    local factor=1+(bonus or 0)/10000
    if species=="dog" then
        local rate=adults*minute/dogPeriod*factor
        return {dog_find=adults,travel_satchel=rate,travel_pack=rate}
    end
    return {cat_tool=adults>0 and (adults+3)/4 or 0,loot_case=adults*minute/catPeriod*factor}
end

local function add(t,k,n)
    if n>0 then t[k]=(t[k] or 0)+n end
end

local function journal(book)
    if not book.forage then book.forage={seeds={},pending={}} end
    return book.forage
end

-- Merge identical completed minutes into one run. Even a distant restored
-- world records a constant population in O(1) and only rolls a bounded batch.
local function redRun(log,weight,count)
    if weight==0 or count==0 then return end
    local runs=log.red or {}
    log.red=runs
    local last=runs[#runs]
    if last and last.weight==weight then last.count=last.count+count
    else runs[#runs+1]={weight=weight,count=count} end
end

local function redWork(log,from,to,weight)
    local boundary=from-from%minute+minute
    local open=log.redOpen or 0
    if to<boundary then log.redOpen=open+(to-from)*weight; return end
    redRun(log,open+(boundary-from)*weight,1)
    redRun(log,minute*weight,math.floor((to-boundary)/minute))
    local tail=(to-boundary)%minute*weight
    log.redOpen=tail>0 and tail or nil
end

-- Population can change inside a minute when a juvenile matures. Split at
-- those few birthdays, not at every simulated minute or at each animal-frame.
function M.accrue(state,from,to,pet,basis,credit,bonus)
    local herds=state.farm.herds or {}
    local d,c=herds.dog,herds.cat
    if not d and not c then return end
    local dogs,cats=d and d.adults or 0,c and c.adults or 0
    local di,ci=1,1
    local book=state.farm.minuteIncome
    local dogBonus=bonus(state,"dog_kennel","dog_kennel",pet,basis)
    local catBonus=bonus(state,"cat_house","cat_house",pet,basis)
    local tier=c and NHStore.level(state,"cat_house") or 0
    local reds=finds.hasRed()
    while from<to do
        local nextDog=d and d.young[di] or math.huge
        local nextCat=c and c.young[ci] or math.huge
        local finish=math.min(to,nextDog,nextCat)
        local frames=finish-from
        if frames>0 then
            if dogs>0 then
                credit(book,"dog_find",frames,dogs,minute,1,10000)
                credit(book,"travel_satchel",frames,dogs,dogPeriod,1,10000+dogBonus)
                credit(book,"travel_pack",frames,dogs,dogPeriod,1,10000+dogBonus)
            end
            if cats>0 then
                credit(book,"cat_tool",frames,cats+3,4*minute,1,10000,"cat"..tier)
                credit(book,"loot_case",frames,cats,catPeriod,1,10000+catBonus)
            end
            if reds and dogs+cats>0 then redWork(journal(book),from,finish,dogs+2*cats) end
        end
        if nextDog==finish then dogs,di=dogs+1,di+1 end
        if nextCat==finish then cats,ci=cats+1,ci+1 end
        from=finish
    end
end

local function draw(state,log,lane,size)
    local seed=log.seeds[lane]
    if not seed then
        local world=StatsGetValue and tonumber(StatsGetValue("world_seed")) or 0
        seed=1+(world%modulus+state.profile*15485863+lanes[lane])%(modulus-1)
    end
    seed=seed*48271%modulus
    log.seeds[lane]=seed
    return 1+math.floor((seed-1)/(modulus-1)*size)
end

-- Convert bounded earned opportunities to concrete debts once. Inventory
-- capacity never participates in these choices.
function M.resolve(state)
    local book=state.farm.minuteIncome
    local changed=false
    for _,lane in ipairs({"dog_find","cat1","cat2","cat3"}) do
        local owed=book.owed[lane]
        if owed then
            local log=journal(book)
            local count=math.min(owed,NHFarm.batchLimit)
            local pool=lane~="dog_find" and finds.toolPool(tonumber(lane:sub(-1)))
            for _=1,count do
                if pool then add(log.pending,pool[draw(state,log,lane,#pool)],1)
                else
                    local result=food[draw(state,log,lane,#food)]
                    add(book.owed,result[1],result[2])
                end
            end
            book.owed[lane]=owed>count and owed-count or nil
            changed=true
        end
    end
    for _,key in ipairs({"travel_satchel","travel_pack","loot_case"}) do
        if book.owed[key] then
            add(journal(book).pending,key,book.owed[key])
            book.owed[key]=nil
            changed=true
        end
    end
    local log=book.forage
    local budget=NHFarm.batchLimit
    while log and log.red and budget>0 do
        local run=log.red[1]
        local count=math.min(budget,run.count)
        for _=1,count do
            if draw(state,log,"red",minute*25000)<=run.weight then
                local key=finds.redKey(function(size) return draw(state,log,"red",size) end)
                if key then add(log.pending,key,1) end
            end
        end
        run.count,budget=run.count-count,budget-count
        if run.count==0 then table.remove(log.red,1); if #log.red==0 then log.red=nil end end
        changed=true
    end
    return changed
end

local fits=setmetatable({},{__mode="k"})
local function canPay(state,key)
    local cache=fits[state]
    local order=state.order and state.order.output
    local supplies=NHStore.warehouseCapacity(state,"supplies")
    local gear=NHStore.warehouseCapacity(state,"equipment")
    local collection=NHStore.warehouseCapacity(state,"collection")
    if not cache or cache.rows~=state.warehouse or cache.count~=#state.warehouse or cache.nextId~=state.nextItemId
        or cache.revision~=state.revision or cache.order~=order or cache.supplies~=supplies or cache.gear~=gear or cache.collection~=collection then
        cache={rows=state.warehouse,count=#state.warehouse,nextId=state.nextItemId,revision=state.revision,
            order=order,supplies=supplies,gear=gear,collection=collection}
        fits[state]=cache
    end
    if cache[key]==nil then cache[key]=finds.canPay(state,key) end
    return cache[key]
end

function M.ready(state)
    local log=state.farm.minuteIncome.forage
    if not log then return false end
    if log.red then return true end
    for key in pairs(log.pending) do if canPay(state,key) then return true end end
    return false
end

function M.deliver(state)
    local log=state.farm.minuteIncome.forage
    if not log or not next(log.pending) then return false end
    local keys={}
    for key in pairs(log.pending) do if canPay(state,key) then keys[#keys+1]=key end end
    table.sort(keys)
    local changed=false
    for _,key in ipairs(keys) do
        local owed=log.pending[key]
        local count,draft=finds.payment(state,key,math.min(owed,NHFarm.batchLimit))
        if count>0 then
            state.warehouse,state.nextItemId=draft.warehouse,draft.nextItemId
            log.pending[key]=count<owed and owed-count or nil
            changed=true
        end
    end
    return changed
end

function M.pending(state,species,blockedOnly)
    local book=state.farm.minuteIncome
    local log=book and book.forage
    local n=0
    if not log then return n end
    for key,count in pairs(log.pending) do
        local source="cat"
        if key:sub(1,4)=="red:" then source="shared"
        elseif key=="travel_satchel" or key=="travel_pack" then source="dog" end
        if source==species and (not blockedOnly or not canPay(state,key)) then n=n+count end
    end
    return n
end

function M.validate(log,whole)
    if not log then return end
    assert(type(log)=="table" and type(log.seeds)=="table" and type(log.pending)=="table","Invalid pet finds")
    for lane,seed in pairs(log.seeds) do assert(lanes[lane] and whole(seed) and seed>=1 and seed<modulus,"Invalid pet seed") end
    for key,count in pairs(log.pending) do assert(finds.known(key) and whole(count) and count>0,"Invalid stored pet find") end
    assert(not log.redOpen or (whole(log.redOpen) and log.redOpen<18*minute),"Invalid current pet search")
    if log.red then
        assert(type(log.red)=="table" and #log.red>0,"Invalid pet search backlog")
        local n=0
        for i,run in pairs(log.red) do
            assert(whole(i) and i>=1 and i<=#log.red and whole(run.weight) and run.weight>0 and run.weight<=18*minute
                and whole(run.count) and run.count>0,"Invalid pet search batch")
            n=n+1
        end
        assert(n==#log.red,"Invalid pet search queue")
    end
end
return M
