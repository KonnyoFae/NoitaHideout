dofile("mods/noita_hideout/files/livestock.lua")
local minuteIncome=dofile("mods/noita_hideout/files/minute_income.lua")
NHFarm={crops={},order={},minute=3600,levelBasisPoints=minuteIncome.levelBonus,income=minuteIncome}
local longestCycle=0

local function crop(key,zh,en,amount,seconds,equipment)
    NHFarm.order[#NHFarm.order+1]=key
    NHFarm.crops[key]={zh=zh,en=en,amount=amount,frames=seconds*60,equipment=equipment}
    longestCycle=math.max(longestCycle,seconds*60)
end

crop("fiber","纤维","Fiber",6,120)
crop("herb","草药","Herbs",4,180)
crop("grain","粮食","Grain",6,180)
crop("sugar","糖分","Sugar",4,150)
crop("spice","香料","Spices",3,240,true)
crop("active_herb","激活草药","Stimulating herbs",3,300,true)

function NHFarm.adopt(farm)
    if not farm.passive then
        -- Manual fields held one ripe crop, and old pens held up to four
        -- batches. Preserve those limits before converting to shared groups.
        for _,plot in pairs(farm.plots) do
            if plot.crop then plot.readyAt=math.max(plot.readyAt,farm.time) end
        end
        for _,animal in pairs(farm.pens or {}) do
            local period=NHLivestock.species[animal.kind].period
            animal.nextAt=math.max(animal.nextAt,farm.time-3*period)
        end
        farm.passive=true
    end
    NHLivestock.adopt(farm)
end

function NHFarm.validate(state,whole)
    local farm=state.farm
    assert(type(farm)=="table" and whole(farm.time) and type(farm.plots)=="table","Invalid farmland")
    local capacity=NHStore.level(state,"farmland")
    assert(capacity>0 or NHStore.level(state,"agri_equipment")==0,"Farm equipment requires a field")
    if farm.pending then
        assert(type(farm.pending)=="table","Invalid pending crops")
        for id,count in pairs(farm.pending) do
            assert(NHFarm.crops[id] and whole(count) and count>0,"Invalid pending crop")
        end
    end
    for slot,plot in pairs(farm.plots) do
        assert(whole(slot) and slot>=1 and slot<=capacity and type(plot)=="table"
            and whole(plot.token) and plot.token>=1,"Invalid farm plot")
        if plot.crop then
            local kind=NHFarm.crops[plot.crop]
            -- A crop switch keeps the deadline of the cycle already in progress.
            assert(kind and whole(plot.readyAt) and plot.readyAt>0
                and plot.readyAt-farm.time<=longestCycle,"Invalid growing crop")
            assert(not kind.equipment or NHStore.level(state,"agri_equipment")>0,"Farm equipment missing")
        else assert(plot.readyAt==nil,"Empty field has a harvest time") end
    end
    minuteIncome.validate(farm,whole)
    NHLivestock.validate(state,whole)
end

local function active(farm)
    if farm.herds and next(farm.herds) then return true end
    for _,plot in pairs(farm.plots) do
        if plot.crop then return true end
    end
    return false
end

-- Fields and livestock count game frames only while something is growing.
local world_key="noita_hideout_farm_clock"
local clock_profile,clock_run,clock_ticket,last_frame,clock_time

function NHFarm.resetClock()
    clock_profile,clock_run,clock_ticket,last_frame,clock_time=nil,nil,nil,nil,nil
end

function NHFarm.suspendClock()
    last_frame=nil
end

function NHFarm.observe(state,frame)
    local farm=state.farm
    local growing=active(farm)
    if clock_profile~=state.profile or clock_run~=state.runSerial then
        clock_profile,clock_run=state.profile,state.runSerial
        clock_ticket=table.concat({clock_profile,clock_run,""},"/")
        local saved=GlobalsGetValue(world_key,"")
        local value=saved:sub(1,#clock_ticket)==clock_ticket and tonumber(saved:sub(#clock_ticket+1))
        clock_time=value and math.max(0,math.floor(value)) or farm.time
        if not value then GlobalsSetValue(world_key,clock_ticket..clock_time) end
        last_frame=frame
    end
    local delta=last_frame and math.max(0,frame-last_frame) or 0
    local elapsed=growing and clock_time+delta or farm.time
    if elapsed~=clock_time then GlobalsSetValue(world_key,clock_ticket..elapsed) end
    clock_time,last_frame=elapsed,frame
    -- A world snapshot may predate already-paid profile batches. Its clock
    -- catches up before those replayed frames can earn another harvest.
    return math.max(elapsed,farm.time)
end

-- Normally one batch matures at a time. Bound the number of reward rolls
-- per source per tick when a restored world is far ahead of its profile.
NHFarm.batchLimit=128
function NHFarm.nextMinute(now)
    return now-now%NHFarm.minute+NHFarm.minute
end

function NHFarm.due(state,now)
    local farm=state.farm
    if now>=NHFarm.nextMinute(farm.time) and active(farm) then return true end
    if not farm.minuteIncome then
        -- Test the legacy debt on load and once per second until it can be
        -- committed. Unrelated transactions can still use the old compact
        -- snapshot (notably a cancellation in a nearly full EW profile).
        if now~=farm.time and now%60~=0 then return false end
        if farm.pending and next(farm.pending) then return true end
        for _,plot in pairs(farm.plots) do
            if plot.crop and plot.readyAt<=farm.time then return true end
        end
        for _,herd in pairs(farm.herds or {}) do
            if herd.owed>0 then return true end
        end
        return false
    end
    return minuteIncome.ready(state)
end

function NHFarm.sync(state,now,changingCrop)
    local farm=state.farm
    local growing=active(farm)
    local converting=farm.minuteIncome and not farm.minuteIncome.searchVersion
    if not farm.minuteIncome then
        if not growing and not farm.pending then return false,false,{} end
        if not changingCrop and now<=farm.time and not NHFarm.due(state,farm.time) then return false,false,{} end
        minuteIncome.adopt(state)
    elseif converting then
        minuteIncome.adopt(state)
    end
    local elapsed=growing and math.max(now,farm.time) or farm.time
    local boundary=elapsed-elapsed%NHFarm.minute
    local from=farm.time
    if boundary>from then
        minuteIncome.advance(state,from,boundary)
        minuteIncome.close(farm.minuteIncome)
        from=boundary
    end
    minuteIncome.advance(state,from,elapsed)
    local advanced=elapsed>farm.time
    farm.time=elapsed
    local produced,awards=minuteIncome.pay(state)
    return advanced or produced or converting or false,produced,awards
end

local function quotedPlot(state,request)
    if type(request)~="table" then return end
    local slot=request.plot
    if type(slot)~="number" or slot~=math.floor(slot) or slot<1 or slot>NHStore.level(state,"farmland") then return end
    local plot=state.farm.plots[slot] or {token=0}
    if request.token==plot.token then return plot end
end

function NHFarm.plant(state,request,now)
    local plot=quotedPlot(state,request)
    if not plot or plot.crop==request.crop then return false,"Farm plot changed." end
    local kind=NHFarm.crops[request.crop]
    if not kind then return false,"Unknown crop." end
    if kind.equipment and NHStore.level(state,"agri_equipment")==0 then return false,"Farm equipment is required." end
    if plot.token>=NHStore.maxResourceAmount then return false,"Farm plot changed." end
    NHFarm.sync(state,now,plot.crop~=nil)
    local farm=state.farm
    local deadline=plot.readyAt or farm.time+kind.frames
    farm.plots[request.plot]={token=plot.token+1,crop=request.crop,readyAt=deadline}
    return true
end

function NHFarm.view(state,lang,now)
    local view={plots={},crops={},equipment=NHStore.level(state,"agri_equipment")>0}
    now=math.max(now,state.farm.time)
    view.remaining=math.max(0,math.ceil((NHFarm.nextMinute(state.farm.time)-now)/60))
    local pet,basis=NHCompanions.productionCurrent(state)
    local cropMultiplier=1+minuteIncome.bonus(state,"farmland","farm",pet,basis)/10000
    local livestockRates
    view.pens,view.produce,livestockRates=NHLivestock.view(state,lang,now,pet,basis)
    view.dragonPending=NHDragonLoot.pendingCount(state)
    view.gelPending=NHGelPool.pendingDoses(state)
    view.gelSpicePending=state.gelBonus and state.gelBonus.spice or 0
    local fieldCounts={}
    for id=1,NHStore.level(state,"farmland") do
        local plot=state.farm.plots[id] or {token=0}
        if plot.crop then fieldCounts[plot.crop]=(fieldCounts[plot.crop] or 0)+1 end
        local remaining=plot.crop and view.remaining or 0
        view.plots[id]={id=id,token=plot.token,crop=plot.crop,remaining=remaining,
            blocked=plot.crop~=nil and (state.resources[plot.crop] or 0)>=NHStore.maxResourceAmount}
    end
    for _,id in ipairs(NHFarm.order) do
        local kind=NHFarm.crops[id]
        view.crops[#view.crops+1]={id=id,name=lang=="zh" and kind.zh or kind.en,amount=kind.amount,
            duration=kind.frames/60,unlocked=not kind.equipment or view.equipment,stock=state.resources[id] or 0,
            plotRate=kind.amount*3600/kind.frames*cropMultiplier,
            perMinute=(fieldCounts[id] or 0)*kind.amount*3600/kind.frames*cropMultiplier+(livestockRates[id] or 0)}
    end
    for _,row in ipairs(view.produce) do
        local crop=NHFarm.crops[row.id]
        if crop then row.perMinute=row.perMinute+(fieldCounts[row.id] or 0)*crop.amount*3600/crop.frames*cropMultiplier end
    end
    return view
end
