NHLivestock={
    resources={egg={zh="蛋",en="Eggs"},milk={zh="奶",en="Milk"},meat={zh="肉",en="Meat"},
        gold={zh="金币",en="Gold"},loot={zh="寻宝",en="Treasure"}},
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
        gel_pool={adult={"生产中","Producing"},pen={"凝胶池","Gel pool"},facility="gel_pool",offset=9,
            growth=0,period=240*60,yields={{"herb",4},{"fiber",6}}},
    },
}

-- Profile slots 1–6 are the three original coop/cowshed pairs. The special
-- pens keep their own fixed addresses even when normal pens are built later.
local function penSpecies(state,slot)
    if slot==7 then
        if NHStore.level(state,"beehive")>0 then return "queen_bee" end
    elseif slot==8 then
        if NHStore.level(state,"dragon_nest")>0 then return "dragon_egg" end
    elseif slot==9 then
        if NHStore.level(state,"gel_pool")>0 then return "gel_pool" end
    elseif slot>=1 and slot<=2*NHStore.level(state,"livestock") then
        return slot%2==1 and "chick" or "calf"
    end
end

function NHLivestock.validate(state,whole)
    local pens=state.farm.pens
    if NHStore.level(state,"gel_pool")>0 then
        assert(type(pens)=="table" and pens[9] and pens[9].kind=="gel_pool","Missing gel pool production clock")
    end
    if pens==nil then return end
    assert(type(pens)=="table","Invalid livestock pens")
    for slot,animal in pairs(pens) do
        assert(whole(slot) and type(animal)=="table" and penSpecies(state,slot)==animal.kind,"Invalid livestock pen")
        local kind=NHLivestock.species[animal.kind]
        assert(kind and whole(animal.born) and animal.born<=state.farm.time
            and whole(animal.nextAt) and animal.nextAt>=animal.born+kind.growth+kind.period,"Invalid livestock")
    end
end

function NHLivestock.freePen(state,species)
    local kind=NHLivestock.species[species]
    if not kind or not kind.young then return nil,"Unknown shop item." end
    local level=NHStore.level(state,kind.facility or "livestock")
    if level==0 then return nil,kind.locked or "Livestock equipment is required." end
    local pens=state.farm.pens or {}
    local last=kind.facility and kind.offset or level*2
    for slot=kind.offset,last,2 do
        if not pens[slot] then return slot end
    end
    return nil,"No matching pen is free."
end

function NHLivestock.deliver(state,species,slot,now)
    NHFarm.sync(state,now or state.farm.time)
    state.farm.time=math.max(state.farm.time,now or state.farm.time)
    local birth=state.farm.time
    local kind=NHLivestock.species[species]
    state.farm.pens=state.farm.pens or {}
    state.farm.pens[slot]={kind=species,born=birth,nextAt=birth+kind.growth+kind.period}
end

function NHLivestock.batches(state,animal,now)
    local kind=NHLivestock.species[animal.kind]
    local space=NHStore.maxResourceAmount
    for _,part in ipairs(kind.yields) do
        local id,amount=part[1],part[2]
        if id=="gold" then space=math.min(space,math.floor((NHStore.maxGold-state.bankGold)/amount))
        elseif id~="loot" then
            space=math.min(space,math.floor((NHStore.maxResourceAmount-(state.resources[id] or 0))/amount))
        end
    end
    return NHFarm.batches(now,animal.nextAt,kind.period,space)
end

function NHLivestock.settle(state,now)
    local total,ranch,hives,gel=0,0,0,0
    local finds={}
    for slot=1,9 do
        local animal=state.farm.pens and state.farm.pens[slot]
        if animal and now>=animal.nextAt then
            local kind=NHLivestock.species[animal.kind]
            local count=NHLivestock.batches(state,animal,now)
            if count>0 then
                for _,part in ipairs(kind.yields) do
                    local id,amount=part[1],part[2]*count
                    if id=="gold" then assert(NHStore.creditGold(state,amount))
                    elseif id=="loot" then finds=NHDragonLoot.award(state,amount)
                    else state.resources[id]=(state.resources[id] or 0)+amount end
                end
                animal.nextAt=animal.nextAt+count*kind.period
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

function NHLivestock.view(state,lang,now)
    local pens,perMinute={},{}
    local language=lang=="zh" and 1 or 2
    local function addPen(slot,species)
        local kind=NHLivestock.species[species]
        local title=kind.pen[language]
        if not kind.facility then title=title.." "..math.ceil(slot/2) end
        local pen={id=slot,species=species,title=title,young=kind.young and kind.young[language],growth=kind.growth/60,period=kind.period/60}
        pen.yieldLabel,pen.yieldValue=NHLivestock.yieldText(species,lang)
        local animal=(state.farm.pens or {})[slot]
        if animal then
            local adultAt=animal.born+kind.growth
            pen.grown=now>=adultAt
            if pen.grown then
                local cyclesPerMinute=3600/kind.period
                for _,part in ipairs(kind.yields) do
                    perMinute[part[1]]=(perMinute[part[1]] or 0)+part[2]*cyclesPerMinute
                end
                if species=="gel_pool" then
                    perMinute.spice=(perMinute.spice or 0)+cyclesPerMinute*NHGelPool.bonusChance/100
                end
            end
            pen.name=pen.grown and kind.adult[language] or pen.young
            pen.nextAt=animal.nextAt
            pen.blocked=now>=animal.nextAt and NHLivestock.batches(state,animal,now)==0
            local target=pen.grown and animal.nextAt or adultAt
            pen.remaining=math.max(0,math.ceil((target-now)/60))
        end
        pens[#pens+1]=pen
    end
    for slot=1,9 do
        local species=penSpecies(state,slot)
        if species then addPen(slot,species) end
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
