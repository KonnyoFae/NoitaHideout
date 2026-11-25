-- Only transitions live in the world snapshot. An interrupted minute can be
-- replayed after a reload, including companion changes before the checkpoint.
-- The durable farm cursor lets us discard old transitions after a successful save.
local M=NHCompanions
local key="noita_hideout_production_companion"
local profile,run,ticket,events
local observed,body,pet,species,previousTime,nextReading

function M.resetProduction()
    profile,run,ticket,events=nil,nil,nil,nil
    observed,body,pet,species,previousTime,nextReading=nil,nil,nil,nil,nil,nil
end

local function marker(at,id,points)
    return {at=at,id=id,points=points,basis=NHAffinity.productionBasisPoints(points)}
end

local function bind(state)
    if events and profile==state.profile and run==state.runSerial then return end
    M.resetProduction()
    profile,run,events=state.profile,state.runSerial,{}
    ticket=tostring(profile).."/"..tostring(run).."|"
    local raw=GlobalsGetValue and GlobalsGetValue(key,"") or ""
    if raw:sub(1,#ticket)~=ticket then return end
    for at,id,points in raw:sub(#ticket+1):gmatch("(%d+),([%w_-]+),(%d+);") do
        at,points=tonumber(at),tonumber(points)
        if (id=="-" or M.species[id]) and points<=NHAffinity.maxPoints and (#events==0 or at>events[#events].at) then
            events[#events+1]=marker(at,M.species[id] and id or nil,points)
        end
    end
end

local function publish()
    if not GlobalsSetValue then return end
    local parts={ticket}
    for _,e in ipairs(events) do
        parts[#parts+1]=("%.0f,%s,%d;"):format(e.at,e.id or "-",e.points)
    end
    GlobalsSetValue(key,table.concat(parts))
end

function M.recordProduction(state,at,id,points)
    bind(state)
    points=points or 0
    local last=events[#events]
    if last and at<last.at then return end
    if not last and not id then return end
    local basis=NHAffinity.productionBasisPoints(points)
    if last and last.id==id and last.basis==basis
        and NHAffinity.incomeBasisPoints(last.points)==NHAffinity.incomeBasisPoints(points) then return end
    if last and last.at==at then events[#events]=nil end
    events[#events+1]=marker(at,id,points)
    publish()
end

function M.checkpointProduction(state)
    if not events or profile~=state.profile or run~=state.runSerial or #events==0 then return end
    local count=0
    while events[count+2] and events[count+2].at<=state.farm.time do count=count+1 end
    if count>0 or (#events==1 and not events[1].id and events[1].at<=state.farm.time) then
        local keep={}
        for i=count+1,#events do keep[#keep+1]=events[i] end
        if keep[1] and not keep[1].id and keep[1].at<=state.farm.time then table.remove(keep,1) end
        events=keep
        publish()
    end
end

-- Summons are created through a single local entry point. Re-enumerate the
-- player's children only after a summon, a body change or a saved-world load.
function M.productionPartyChanged()
    observed=false
end

function M.observeProduction(state,at,frame,player)
    bind(state)
    at=at or previousTime or state.farm.time
    previousTime=at
    if not observed or body~=player then
        body,observed=player,true
        species,pet=nil,nil
        if player then species,pet=M.active(player) end
        nextReading=0
        if not pet then M.recordProduction(state,at,nil) end
    elseif pet and (not EntityGetIsAlive(pet) or EntityGetParent(pet)~=body) then
        species,pet=nil,nil
        M.recordProduction(state,at,nil)
    end
    if pet and frame>=nextReading then
        local points,delay=NHAffinity.productionReading(state,species)
        M.recordProduction(state,at,species,points)
        nextReading=frame+delay
    end
end

function M.productionCurrent(state)
    bind(state)
    local e=events[#events]
    if e and e.id then return e.id,e.basis,e.points end
    return nil,0,0
end

function M.productionSegments(state,from,to)
    bind(state)
    local spans={}
    for i,e in ipairs(events) do
        if e.at>=to then break end
        local finish=math.min(to,events[i+1] and events[i+1].at or to)
        if e.id and finish>from then
            spans[#spans+1]={from=math.max(from,e.at),to=finish,id=e.id,basis=e.basis,points=e.points}
        end
    end
    return spans
end
