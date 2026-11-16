NHLivestock={
    resources={egg={zh="蛋",en="Eggs"},milk={zh="奶",en="Milk"},meat={zh="肉",en="Meat"}},
    species={
        chick={young={"小鸡","Chick"},adult={"母鸡","Hen"},pen={"鸡舍","Coop"},offset=1,
            growth=180*60,period=120*60,product="egg",amount=2,meat=1},
        calf={young={"牛犊","Calf"},adult={"母牛","Cow"},pen={"牛栏","Cowshed"},offset=2,
            growth=300*60,period=180*60,product="milk",amount=2,meat=2},
    },
}

function NHLivestock.validate(state,whole)
    local pens=state.farm.pens
    if pens==nil then return end
    assert(type(pens)=="table","Invalid livestock pens")
    for slot,animal in pairs(pens) do
        assert(whole(slot) and slot>=1 and slot<=2*NHStore.level(state,"livestock") and type(animal)=="table","Invalid livestock pen")
        local kind=NHLivestock.species[animal.kind]
        assert(kind and (slot-kind.offset)%2==0 and whole(animal.born) and animal.born<=state.farm.time
            and whole(animal.nextAt) and animal.nextAt>=animal.born+kind.growth+kind.period,"Invalid livestock")
    end
end

function NHLivestock.freePen(state,species)
    local level=NHStore.level(state,"livestock")
    if level==0 then return nil,"Livestock equipment is required." end
    local pens=state.farm.pens or {}
    for slot=NHLivestock.species[species].offset,level*2,2 do
        if not pens[slot] then return slot end
    end
    return nil,"No matching pen is free."
end

function NHLivestock.deliver(state,species,slot,now)
    NHFarm.sync(state,now or state.farm.time)
    local birth=state.farm.time
    local kind=NHLivestock.species[species]
    state.farm.pens=state.farm.pens or {}
    state.farm.pens[slot]={kind=species,born=birth,nextAt=birth+kind.growth+kind.period}
end

function NHLivestock.batches(state,animal,now)
    local kind=NHLivestock.species[animal.kind]
    local productSpace=math.floor((NHStore.maxResourceAmount-(state.resources[kind.product] or 0))/kind.amount)
    local meatSpace=math.floor((NHStore.maxResourceAmount-(state.resources.meat or 0))/kind.meat)
    return NHFarm.batches(now,animal.nextAt,kind.period,math.min(productSpace,meatSpace))
end

function NHLivestock.settle(state,now)
    local total=0
    for slot=1,NHStore.level(state,"livestock")*2 do
        local animal=state.farm.pens and state.farm.pens[slot]
        if animal and now>=animal.nextAt then
            local kind=NHLivestock.species[animal.kind]
            local count=NHLivestock.batches(state,animal,now)
            if count>0 then
                state.resources[kind.product]=(state.resources[kind.product] or 0)+kind.amount*count
                state.resources.meat=(state.resources.meat or 0)+kind.meat*count
                animal.nextAt=animal.nextAt+count*kind.period
                total=total+count
            end
        end
    end
    return total
end

function NHLivestock.view(state,lang,now)
    local pens={}
    local perMinute={egg=0,milk=0,meat=0}
    local language=lang=="zh" and 1 or 2
    for slot=1,NHStore.level(state,"livestock")*2 do
        local species=slot%2==1 and "chick" or "calf"
        local kind=NHLivestock.species[species]
        local pen={id=slot,species=species,title=kind.pen[language].." "..math.ceil(slot/2),
            young=kind.young[language],amount=kind.amount,meat=kind.meat,
            product=NHLivestock.resources[kind.product][lang=="zh" and "zh" or "en"],growth=kind.growth/60,period=kind.period/60}
        local animal=(state.farm.pens or {})[slot]
        if animal then
            local adultAt=animal.born+kind.growth
            pen.grown=now>=adultAt
            if pen.grown then
                local cyclesPerMinute=3600/kind.period
                perMinute[kind.product]=perMinute[kind.product]+kind.amount*cyclesPerMinute
                perMinute.meat=perMinute.meat+kind.meat*cyclesPerMinute
            end
            pen.name=pen.grown and kind.adult[language] or pen.young
            pen.nextAt=animal.nextAt
            pen.blocked=now>=animal.nextAt and NHLivestock.batches(state,animal,now)==0
            local target=pen.grown and animal.nextAt or adultAt
            pen.remaining=math.max(0,math.ceil((target-now)/60))
        end
        pens[slot]=pen
    end
    local produce={}
    for _,id in ipairs({"egg","milk","meat"}) do
        local resource=NHLivestock.resources[id]
        produce[#produce+1]={id=id,name=lang=="zh" and resource.zh or resource.en,
            stock=state.resources[id] or 0,perMinute=perMinute[id]}
    end
    return pens,produce
end
