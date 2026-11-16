dofile("mods/noita_hideout/files/livestock.lua")
NHFarm={crops={},order={}}
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
    if farm.passive then return end
    -- Manual fields held one ripe crop, and the old pens held up to four
    -- batches. Start the continuous schedule with exactly that earned output.
    for _,plot in pairs(farm.plots) do
        if plot.crop then plot.readyAt=math.max(plot.readyAt,farm.time) end
    end
    for _,animal in pairs(farm.pens or {}) do
        local period=NHLivestock.species[animal.kind].period
        animal.nextAt=math.max(animal.nextAt,farm.time-3*period)
    end
    farm.passive=true
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
    NHLivestock.validate(state,whole)
end

local function active(farm)
    if farm.pens and next(farm.pens) then return true end
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
local maxBatchesPerSettlement=128
function NHFarm.batches(now,nextAt,period,space)
    if now<nextAt then return 0 end
    return math.min(1+math.floor((now-nextAt)/period),space,maxBatchesPerSettlement)
end

local function cropRoom(state,id)
    return math.floor((NHStore.maxResourceAmount-(state.resources[id] or 0))/NHFarm.crops[id].amount)
end

local function cropBatches(state,plot,now)
    return NHFarm.batches(now,plot.readyAt,NHFarm.crops[plot.crop].frames,cropRoom(state,plot.crop))
end

function NHFarm.due(state,now)
    local farm=state.farm
    if now-farm.time>=600 then return true end
    for id in pairs(farm.pending or {}) do
        if cropRoom(state,id)>0 then return true end
    end
    for _,plot in pairs(farm.plots) do
        if plot.crop and now>=plot.readyAt and cropBatches(state,plot,now)>0 then return true end
    end
    for _,animal in pairs(farm.pens or {}) do
        if now>=animal.nextAt and NHLivestock.batches(state,animal,now)>0 then return true end
    end
    return false
end

function NHFarm.sync(state,now)
    local farm=state.farm
    if not active(farm) and not farm.pending then return false,false end
    local elapsed=math.max(now,farm.time)
    local advanced=elapsed>farm.time
    farm.time=elapsed
    local crops=0
    if farm.pending then
        for id,owed in pairs(farm.pending) do
            local count=math.min(owed,cropRoom(state,id),maxBatchesPerSettlement)
            if count>0 then
                state.resources[id]=(state.resources[id] or 0)+count*NHFarm.crops[id].amount
                farm.pending[id]=owed>count and owed-count or nil
                crops=crops+count
            end
        end
        if not next(farm.pending) then farm.pending=nil end
    end
    for slot=1,NHStore.level(state,"farmland") do
        local plot=farm.plots[slot]
        if plot and plot.crop and elapsed>=plot.readyAt then
            local count=cropBatches(state,plot,elapsed)
            if count>0 then
                local kind=NHFarm.crops[plot.crop]
                state.resources[plot.crop]=(state.resources[plot.crop] or 0)+count*kind.amount
                plot.readyAt=plot.readyAt+count*kind.frames
                crops=crops+count
            end
        end
    end
    local awards=crops>0 and NHCompanions.reward(state,"farm",crops) or {}
    local animalBatches,animalAwards=NHLivestock.settle(state,elapsed)
    for _,id in ipairs(animalAwards) do awards[#awards+1]=id end
    local produced=crops+animalBatches>0
    return advanced or produced,produced,awards
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
    NHFarm.sync(state,now)
    local farm=state.farm
    local deadline=plot.readyAt or farm.time+kind.frames
    if plot.crop and deadline<=farm.time then
        -- Keep completed old batches even if their inventory is full. Only
        -- the next, unfinished cycle changes to the newly selected crop.
        local period=NHFarm.crops[plot.crop].frames
        local owed=1+math.floor((farm.time-deadline)/period)
        farm.pending=farm.pending or {}
        farm.pending[plot.crop]=(farm.pending[plot.crop] or 0)+owed
        deadline=deadline+owed*period
    end
    farm.plots[request.plot]={token=plot.token+1,crop=request.crop,readyAt=deadline}
    return true
end

function NHFarm.view(state,lang,now)
    local view={plots={},crops={},equipment=NHStore.level(state,"agri_equipment")>0}
    now=math.max(now,state.farm.time)
    local livestockRates
    view.pens,view.produce,livestockRates=NHLivestock.view(state,lang,now)
    view.dragonPending=NHDragonLoot.pendingCount(state)
    view.gelPending=NHGelPool.pendingDoses(state)
    view.gelSpicePending=state.gelBonus and state.gelBonus.spice or 0
    local fieldCounts={}
    for id=1,NHStore.level(state,"farmland") do
        local plot=state.farm.plots[id] or {token=0}
        if plot.crop then fieldCounts[plot.crop]=(fieldCounts[plot.crop] or 0)+1 end
        local remaining=plot.crop and math.max(0,math.ceil((plot.readyAt-now)/60)) or 0
        view.plots[id]={id=id,token=plot.token,crop=plot.crop,remaining=remaining,
            blocked=plot.crop~=nil and remaining==0 and cropBatches(state,plot,now)==0}
    end
    for _,id in ipairs(NHFarm.order) do
        local kind=NHFarm.crops[id]
        view.crops[#view.crops+1]={id=id,name=lang=="zh" and kind.zh or kind.en,amount=kind.amount,
            duration=kind.frames/60,unlocked=not kind.equipment or view.equipment,stock=state.resources[id] or 0,
            perMinute=(fieldCounts[id] or 0)*kind.amount*3600/kind.frames+(livestockRates[id] or 0)}
    end
    for _,row in ipairs(view.produce) do
        local crop=NHFarm.crops[row.id]
        if crop then row.perMinute=row.perMinute+(fieldCounts[row.id] or 0)*crop.amount*3600/crop.frames end
    end
    return view
end
