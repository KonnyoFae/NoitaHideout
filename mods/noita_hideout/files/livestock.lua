NHLivestock={
    resources={egg={zh="蛋",en="Eggs"},milk={zh="奶",en="Milk"},meat={zh="肉",en="Meat"},
        gold={zh="金币",en="Gold"},loot={zh="寻宝",en="Treasure"}},
    order={"chick","calf","queen_bee","dragon_egg","gel_pool"},
    species={
        chick={young={"小鸡","Chick"},adult={"母鸡","Hen"},pen={"鸡舍","Coop"},offset=1,
            growth=180*60,period=120*60,yields={{"egg",2},{"meat",1}}},
        calf={young={"牛犊","Calf"},adult={"母牛","Cow"},pen={"牛栏","Cowshed"},offset=2,
            growth=300*60,period=180*60,yields={{"milk",2},{"meat",2}}},
        queen_bee={young={"女王蜂","Queen bee"},adult={"女王蜂","Queen bee"},pen={"蜂箱","Beehive"},
            facility="beehive",locked="Beehive is required.",offset=7,
            growth=0,period=180*60,yields={{"sugar",5},{"spice",2}}},
        dragon_egg={young={"龙蛋","Dragon egg"},adult={"寻宝龙","Treasure dragon"},pen={"龙巢","Dragon nest"},
            facility="dragon_nest",locked="Dragon nest is required.",offset=8,
            growth=480*60,period=300*60,yields={{"gold",150},{"loot",1}}},
        gel_pool={young={"凝胶幼体","Gel hatchling"},adult={"成熟凝胶","Mature gel"},pen={"凝胶池","Gel pool"},facility="gel_pool",offset=9,
            growth=120*60,period=240*60,yields={{"herb",4},{"fiber",6}}},
    },
}

local function newHerd()
    return {adults=0,young={},progress=0,owed=0}
end

function NHLivestock.capacityAtLevel(level)
    return 2*level
end

function NHLivestock.capacity(state,species)
    local kind=NHLivestock.species[species]
    return kind and NHLivestock.capacityAtLevel(NHStore.level(state,kind.facility or "livestock")) or 0
end

-- All counts and deadlines are in game frames. Split whole periods off
-- before multiplying to retain integer precision on very long catch-ups.
local function addWork(progress,owed,frames,workers,period)
    local partial=progress+(frames%period)*workers
    return partial%period,owed+math.floor(frames/period)*workers+math.floor(partial/period)
end

-- Up to 0.33 each inhabitant had a separate production deadline. Pool every
-- earned frame, including overdue batches whose output was blocked in storage.
function NHLivestock.adopt(farm)
    if not farm.pens then return end
    assert(not farm.herds,"Mixed livestock schedules")
    local herds={}
    for slot,animal in pairs(farm.pens) do
        local species=animal.kind
        local kind=assert(NHLivestock.species[species],"Unknown livestock pen")
        local validSlot=kind.facility and slot==kind.offset
            or not kind.facility and slot>=1 and slot<=6 and (slot-kind.offset)%2==0
        assert(validSlot,"Invalid livestock pen")
        local herd=herds[species] or newHerd()
        herds[species]=herd
        local adultAt=animal.born+(species=="gel_pool" and 0 or kind.growth)
        assert(animal.born<=farm.time and animal.nextAt>=adultAt+kind.period,"Invalid old livestock clock")
        if adultAt<=farm.time then
            herd.adults=herd.adults+1
            local work=math.max(0,(farm.time-animal.nextAt)+kind.period)
            herd.progress,herd.owed=addWork(herd.progress,herd.owed,work,1,kind.period)
        else
            herd.young[#herd.young+1]=adultAt
        end
    end
    for _,herd in pairs(herds) do table.sort(herd.young) end
    farm.pens,farm.herds=nil,herds
end

function NHLivestock.validate(state,whole)
    local farm=state.farm
    local herds=farm.herds or {}
    assert(type(herds)=="table" and farm.pens==nil,"Invalid livestock schedules")
    if NHStore.level(state,"gel_pool")>0 then assert(herds.gel_pool,"Missing gel pool production clock") end
    for species,herd in pairs(herds) do
        local kind=NHLivestock.species[species]
        assert(kind and type(herd)=="table" and whole(herd.adults) and type(herd.young)=="table"
            and whole(herd.progress) and herd.progress<kind.period and whole(herd.owed),"Invalid herd")
        local count,last=0,farm.time
        for i,maturity in ipairs(herd.young) do
            assert(whole(maturity) and maturity>farm.time and maturity>=last and maturity-farm.time<=kind.growth,
                "Invalid livestock maturity")
            count,last=i,maturity
        end
        for i in pairs(herd.young) do assert(whole(i) and i>=1 and i<=count,"Invalid livestock member") end
        assert(herd.adults+count>0 and herd.adults+count<=NHLivestock.capacity(state,species),"Invalid livestock population")
    end
end

function NHLivestock.freePen(state,species)
    local kind=NHLivestock.species[species]
    if not kind then return nil,"Unknown shop item." end
    local capacity=NHLivestock.capacity(state,species)
    if capacity==0 then return nil,kind.locked or "Livestock equipment is required." end
    local herd=(state.farm.herds or {})[species]
    local count=herd and herd.adults+#herd.young or 0
    if count>=capacity then return nil,"No matching pen is free." end
    -- A second purchase with the same screen quote cannot spend gold twice.
    return kind.offset+10*count
end

function NHLivestock.deliver(state,species,token,now,adult)
    if token~=NHLivestock.freePen(state,species) or not token then return false end
    local farm=state.farm
    now=math.max(farm.time,now or farm.time)
    NHFarm.sync(state,now)
    farm.time=now
    farm.herds=farm.herds or {}
    local herd=farm.herds[species] or newHerd()
    farm.herds[species]=herd
    local growth=NHLivestock.species[species].growth
    if adult or growth==0 then herd.adults=herd.adults+1
    else herd.young[#herd.young+1]=now+growth end
    return true
end

-- Calculate time worked over [from, now] without changing the saved group.
-- Young animals start contributing precisely at their own maturity frame.
local function project(herd,period,from,now)
    local progress,owed=addWork(herd.progress,herd.owed,now-from,herd.adults,period)
    local matured=0
    for i,at in ipairs(herd.young) do
        if at>now then break end
        progress,owed=addWork(progress,owed,now-at,1,period)
        matured=i
    end
    return progress,owed,matured
end

local function payable(state,kind,owed)
    local count=math.min(owed,NHFarm.batchLimit)
    for _,part in ipairs(kind.yields) do
        local id,amount=part[1],part[2]
        if id=="gold" then count=math.min(count,math.floor((NHStore.maxGold-state.bankGold)/amount))
        elseif id~="loot" then count=math.min(count,math.floor((NHStore.maxResourceAmount-(state.resources[id] or 0))/amount)) end
    end
    return count
end

function NHLivestock.due(state,now)
    for species,herd in pairs(state.farm.herds or {}) do
        local kind=NHLivestock.species[species]
        local _,owed=project(herd,kind.period,state.farm.time,now)
        if owed>0 and payable(state,kind,owed)>0 then return true end
    end
    return false
end

function NHLivestock.settle(state,from,now)
    local total,ranch,hives,gel=0,0,0,0
    local finds={}
    for _,species in ipairs(NHLivestock.order) do
        local herd=(state.farm.herds or {})[species]
        if herd then
            local kind=NHLivestock.species[species]
            local progress,owed,matured=project(herd,kind.period,from,now)
            local count=payable(state,kind,owed)
            herd.progress,herd.owed=progress,owed-count
            herd.adults=herd.adults+matured
            for i=1,matured do table.remove(herd.young,1) end
            if count>0 then
                for _,part in ipairs(kind.yields) do
                    local id,amount=part[1],part[2]*count
                    if id=="gold" then assert(NHStore.creditGold(state,amount))
                    elseif id=="loot" then finds=NHDragonLoot.award(state,amount)
                    else state.resources[id]=(state.resources[id] or 0)+amount end
                end
                total=total+count
                if kind.facility=="beehive" then hives=hives+count
                elseif kind.facility=="gel_pool" then gel=gel+count
                elseif not kind.facility then ranch=ranch+count end
            end
        end
    end
    if ranch>0 then
        for _,id in ipairs(NHCompanions.reward(state,"livestock",ranch)) do finds[#finds+1]=id end
    end
    if hives>0 then
        for _,id in ipairs(NHCompanions.reward(state,"beehive",hives)) do finds[#finds+1]=id end
    end
    if gel>0 then
        NHGelPool.award(state,gel)
        for _,id in ipairs(NHCompanions.reward(state,"gel_pool",gel)) do finds[#finds+1]=id end
    end
    return total,finds
end

function NHLivestock.yieldText(species,lang)
    local labels,amounts={},{}
    for _,part in ipairs(NHLivestock.species[species].yields) do
        local resource=NHFarm.crops[part[1]] or NHLivestock.resources[part[1]]
        labels[#labels+1]=resource[lang=="zh" and "zh" or "en"]
        amounts[#amounts+1]=part[2]
    end
    return table.concat(labels," / "),table.concat(amounts," / ")
end

-- Include future maturities in the estimate. A newly purchased juvenile can
-- shorten the displayed ETA even though it contributes no work before maturity.
local function nextPayout(herd,now,adults,matured,needed)
    local cursor=now
    for i=matured+1,#herd.young do
        local at=herd.young[i]
        local worked=(at-cursor)*adults
        if adults>0 and needed<=worked then return cursor+math.ceil(needed/adults) end
        needed,cursor,adults=needed-worked,at,adults+1
    end
    if adults>0 then return cursor+math.ceil(needed/adults) end
end

function NHLivestock.view(state,lang,now)
    local pens,perMinute={},{}
    local language=lang=="zh" and 1 or 2
    now=math.max(state.farm.time,now)
    for _,species in ipairs(NHLivestock.order) do
        local kind=NHLivestock.species[species]
        local facility=kind.facility or "livestock"
        local capacity=NHLivestock.capacity(state,species)
        if capacity>0 then
            local pen={id=kind.offset,species=species,title=kind.pen[language],young=kind.young[language],
                expansion=facility,canExpand=NHStore.level(state,facility)<3,capacity=capacity,count=0,
                adults=0,juveniles=0,progress=0,owed=0,growth=kind.growth/60,period=kind.period/60}
            pen.yieldLabel,pen.yieldValue=NHLivestock.yieldText(species,lang)
            local herd=(state.farm.herds or {})[species]
            if herd then
                local progress,owed,matured=project(herd,kind.period,state.farm.time,now)
                pen.count=herd.adults+#herd.young
                pen.adults,pen.juveniles=herd.adults+matured,#herd.young-matured
                pen.grown=pen.adults>0
                pen.name=pen.grown and kind.adult[language] or pen.young
                pen.owed,pen.progress=owed,owed>0 and 1 or progress/kind.period
                pen.blocked=owed>0 and payable(state,kind,owed)==0
                if pen.juveniles>0 then pen.growthRemaining=math.ceil((herd.young[matured+1]-now)/60) end
                pen.nextAt=owed>0 and now or nextPayout(herd,now,pen.adults,matured,kind.period-progress)
                pen.remaining=math.ceil((pen.nextAt-now)/60)
                if pen.adults>0 then
                    pen.effectivePeriod=kind.period/(60*pen.adults)
                    local rate=60/pen.effectivePeriod
                    for _,part in ipairs(kind.yields) do
                        perMinute[part[1]]=(perMinute[part[1]] or 0)+part[2]*rate
                    end
                    if species=="gel_pool" then
                        perMinute.spice=(perMinute.spice or 0)+rate*NHGelPool.bonusChance/100
                    end
                end
            end
            pens[#pens+1]=pen
        end
    end
    local produce,ids={},{"egg","milk","meat"}
    local hive=NHStore.level(state,"beehive")>0
    local pool=NHStore.level(state,"gel_pool")>0
    if hive then ids[#ids+1]="sugar" end
    if hive or pool then ids[#ids+1]="spice" end
    if pool then ids[#ids+1]="herb"; ids[#ids+1]="fiber" end
    if NHStore.level(state,"dragon_nest")>0 then ids[#ids+1]="gold" end
    for _,id in ipairs(ids) do
        local resource=NHFarm.crops[id] or NHLivestock.resources[id]
        produce[#produce+1]={id=id,name=lang=="zh" and resource.zh or resource.en,
            stock=id=="gold" and state.bankGold or state.resources[id] or 0,perMinute=perMinute[id] or 0}
    end
    return pens,produce,perMinute
end
