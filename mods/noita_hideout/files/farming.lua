dofile("mods/noita_hideout/files/livestock.lua")
NHFarm={crops={},order={}}

local function crop(key,zh,en,amount,seconds,equipment)
    NHFarm.order[#NHFarm.order+1]=key
    NHFarm.crops[key]={zh=zh,en=en,amount=amount,frames=seconds*60,equipment=equipment}
end

crop("fiber","纤维","Fiber",6,120)
crop("herb","草药","Herbs",4,180)
crop("grain","粮食","Grain",6,180)
crop("sugar","糖分","Sugar",4,150)
crop("spice","香料","Spices",3,240,true)
crop("active_herb","激活草药","Stimulating herbs",3,300,true)

function NHFarm.validate(state,whole)
    local farm=state.farm
    assert(type(farm)=="table" and whole(farm.time) and type(farm.plots)=="table","Invalid farmland")
    local capacity=NHStore.level(state,"farmland")
    assert(capacity>0 or NHStore.level(state,"agri_equipment")==0,"Farm equipment requires a field")
    for slot,plot in pairs(farm.plots) do
        assert(whole(slot) and slot>=1 and slot<=capacity and type(plot)=="table"
            and whole(plot.token) and plot.token>=1,"Invalid farm plot")
        if plot.crop then
            local kind=NHFarm.crops[plot.crop]
            assert(kind and whole(plot.readyAt) and plot.readyAt>=kind.frames
                and plot.readyAt-kind.frames<=farm.time,"Invalid growing crop")
            assert(not kind.equipment or NHStore.level(state,"agri_equipment")>0,"Farm equipment missing")
        else assert(plot.readyAt==nil,"Empty field has a harvest time") end
    end
    NHLivestock.validate(state,whole)
end

local function horizon(farm)
    local last=NHLivestock.horizon(farm)
    for _,plot in pairs(farm.plots) do
        if plot.crop then last=math.max(last,plot.readyAt) end
    end
    return last
end

-- Fields and livestock share a clock which stops when all output is ready.
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
    local limit=horizon(farm)
    if clock_profile~=state.profile or clock_run~=state.runSerial then
        clock_profile,clock_run=state.profile,state.runSerial
        clock_ticket=table.concat({clock_profile,clock_run,""},"/")
        local saved=GlobalsGetValue(world_key,"")
        local value=saved:sub(1,#clock_ticket)==clock_ticket and tonumber(saved:sub(#clock_ticket+1))
        clock_time=math.min(limit,math.max(farm.time,math.floor(value or 0)))
        last_frame=frame
    end
    local delta=last_frame and math.max(0,frame-last_frame) or 0
    local elapsed=math.min(limit,math.max(clock_time,farm.time)+delta)
    if elapsed~=clock_time then GlobalsSetValue(world_key,clock_ticket..elapsed) end
    clock_time,last_frame=elapsed,frame
    return elapsed
end

function NHFarm.due(state,now)
    local farm=state.farm
    if now<=farm.time then return false end
    if now-farm.time>=600 then return true end
    for _,plot in pairs(farm.plots) do
        if plot.crop and farm.time<plot.readyAt and now>=plot.readyAt then return true end
    end
    return false
end

function NHFarm.sync(state,now)
    local farm=state.farm
    local elapsed=math.min(now,horizon(farm))
    if elapsed<=farm.time then return false end
    farm.time=elapsed
    return true
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
    if not plot or plot.crop then return false,"Farm plot changed." end
    local kind=NHFarm.crops[request.crop]
    if not kind then return false,"Unknown crop." end
    if kind.equipment and NHStore.level(state,"agri_equipment")==0 then return false,"Farm equipment is required." end
    if plot.token>=NHStore.maxResourceAmount then return false,"Farm plot changed." end
    NHFarm.sync(state,now)
    state.farm.plots[request.plot]={token=plot.token+1,crop=request.crop,readyAt=state.farm.time+kind.frames}
    return true
end

function NHFarm.harvest(state,request,now)
    local plot=quotedPlot(state,request)
    if not plot or not plot.crop or (request.crop and request.crop~=plot.crop) then return false,"Farm plot changed." end
    if math.max(now,state.farm.time)<plot.readyAt then return false,"Crop is still growing." end
    local amount=NHFarm.crops[plot.crop].amount
    local stock=state.resources[plot.crop] or 0
    if amount>NHStore.maxResourceAmount-stock then return false,"Resource storage is full." end
    NHFarm.sync(state,now)
    state.resources[plot.crop]=stock+amount
    -- Retain the planting token after harvest to reject a replayed sowing
    -- request that referred to this field before its last crop was planted.
    state.farm.plots[request.plot]={token=plot.token}
    return true,NHCompanions.reward(state,"farm",1)
end

function NHFarm.view(state,lang,now)
    local view={plots={},crops={},equipment=NHStore.level(state,"agri_equipment")>0}
    now=math.max(now,state.farm.time)
    view.pens=NHLivestock.view(state,lang,now)
    view.produce={}
    for _,id in ipairs({"egg","milk","meat"}) do
        local resource=NHLivestock.resources[id]
        table.insert(view.produce,{name=lang=="zh" and resource.zh or resource.en,stock=state.resources[id] or 0})
    end
    for id=1,NHStore.level(state,"farmland") do
        local plot=state.farm.plots[id] or {token=0}
        local remaining=plot.crop and math.max(0,math.ceil((plot.readyAt-now)/60)) or 0
        view.plots[id]={id=id,token=plot.token,crop=plot.crop,remaining=remaining,ready=plot.crop~=nil and remaining==0}
    end
    for _,id in ipairs(NHFarm.order) do
        local kind=NHFarm.crops[id]
        view.crops[#view.crops+1]={id=id,name=lang=="zh" and kind.zh or kind.en,amount=kind.amount,
            duration=kind.frames/60,unlocked=not kind.equipment or view.equipment,stock=state.resources[id] or 0}
    end
    return view
end
