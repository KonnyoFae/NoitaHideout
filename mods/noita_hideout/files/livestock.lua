NHLivestock={
    maxBatches=4,
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

-- Each animal pauses when its pen holds four complete batches. Other animals
-- and the fields on the same gameplay clock may continue to grow.
function NHLivestock.horizon(farm)
    local limit=farm.time
    for _,animal in pairs(farm.pens or {}) do
        limit=math.max(limit,animal.nextAt+(NHLivestock.maxBatches-1)*NHLivestock.species[animal.kind].period)
    end
    return limit
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

local function batches(animal,kind,now)
    return math.min(NHLivestock.maxBatches,math.max(0,1+math.floor((now-animal.nextAt)/kind.period)))
end

local function hasSpace(state,kind,count)
    return kind.amount*count<=NHStore.maxResourceAmount-(state.resources[kind.product] or 0)
        and kind.meat*count<=NHStore.maxResourceAmount-(state.resources.meat or 0)
end

function NHLivestock.collect(state,request,now)
    local animal=type(request)=="table" and (state.farm.pens or {})[request.pen]
    if not animal or animal.nextAt~=request.nextAt then return false,"Livestock collection changed." end
    local kind=NHLivestock.species[animal.kind]
    now=math.max(now,state.farm.time)
    local count=batches(animal,kind,now)
    if count==0 then return false,"No livestock produce is ready." end
    if not hasSpace(state,kind,count) then return false,"Resource storage is full." end
    NHFarm.sync(state,now)
    state.resources[kind.product]=(state.resources[kind.product] or 0)+kind.amount*count
    state.resources.meat=(state.resources.meat or 0)+kind.meat*count
    if count==NHLivestock.maxBatches then animal.nextAt=state.farm.time+kind.period
    else animal.nextAt=animal.nextAt+count*kind.period end
    return true,NHCompanions.reward(state,"livestock",count)
end

function NHLivestock.view(state,lang,now)
    local pens={}
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
            pen.name=pen.grown and kind.adult[language] or pen.young
            pen.count=batches(animal,kind,now)
            pen.nextAt=animal.nextAt
            pen.canCollect=pen.count>0 and hasSpace(state,kind,pen.count)
            local target=pen.grown and animal.nextAt+pen.count*kind.period or adultAt
            pen.remaining=math.max(0,math.ceil((target-now)/60))
        end
        pens[slot]=pen
    end
    return pens
end
