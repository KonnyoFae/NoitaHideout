-- Companion entity scripts and init.lua have separate Lua states. World
-- globals retain the exact number of companionship frames between checkpoints.
NHAffinity={thresholds={0,100,400,1000},framesPerPoint=36,maxPoints=10000}
local maximum=NHAffinity.framesPerPoint*NHAffinity.maxPoints
local prefix="noita_hideout_affinity_"
local run_key="noita_hideout_run_v1"

-- Ten basis points per hundred post-cap points, up to +9 percentage points.
function NHAffinity.incomeBasisPoints(points)
    return math.floor(math.max(0,math.min(points,NHAffinity.maxPoints)-1000)/10)
end

-- Fixed produce and private card rolls have different curves. Keep the
-- displayed and accrued rates in the same integer basis points.
function NHAffinity.productionBasisPoints(points)
    points=math.max(0,math.min(NHAffinity.maxPoints,points))
    if points<=100 then return math.floor(points) end
    if points<=400 then return 100+math.floor((points-100)*200/300) end
    if points<=1000 then return 300+math.floor((points-400)*200/600) end
    return 500+math.floor((points-1000)*500/9000)
end

function NHAffinity.tier(points)
    for i=#NHAffinity.thresholds,2,-1 do
        if points>=NHAffinity.thresholds[i] then return i-1 end
    end
    return 0
end

function NHAffinity.validate(state,whole)
    if state.affinity==nil then return end
    assert(type(state.affinity)=="table","Invalid companion affinity")
    for id,frames in pairs(state.affinity) do
        assert(NHCompanions.species[id] and whole(frames) and frames<=maximum,"Invalid companion affinity")
    end
end

local function saved(state,id)
    return state.affinity and state.affinity[id] or 0
end

local function run(state)
    return state.profile.."/"..state.runSerial
end

local function worldFrames(id)
    return tonumber(GlobalsGetValue(prefix..id,"0")) or 0
end

function NHAffinity.bind(state)
    local ticket=run(state)
    local continued=GlobalsGetValue(prefix.."run","")==ticket
    for _,id in ipairs(NHCompanions.order) do
        local value=saved(state,id)
        if not continued then GlobalsSetValue(prefix..id,tostring(value)) end
        -- On a world rewind, show the earned rank immediately but let its old
        -- clock catch up before promoting the same elapsed time a second time.
        GlobalsSetValue(prefix.."floor_"..id,tostring(value))
    end
    GlobalsSetValue(prefix.."run",ticket)
end

function NHAffinity.livePoints(id)
    local floor=tonumber(GlobalsGetValue(prefix.."floor_"..id,"0")) or 0
    return math.floor(math.max(floor,worldFrames(id))/NHAffinity.framesPerPoint)
end

function NHAffinity.follow(id,elapsed)
    local bound=GlobalsGetValue(prefix.."run","")
    if bound=="" or bound~=GlobalsGetValue(run_key,"") then return 0 end
    local current=worldFrames(id)
    local floor=tonumber(GlobalsGetValue(prefix.."floor_"..id,"0")) or 0
    if floor>=maximum then return NHAffinity.maxPoints end
    local advanced=math.min(maximum,current+elapsed)
    if advanced~=current then GlobalsSetValue(prefix..id,tostring(advanced)) end
    return math.floor(math.max(floor,advanced)/NHAffinity.framesPerPoint)
end

function NHAffinity.points(state,id)
    local total=saved(state,id)
    if GlobalsGetValue(prefix.."run","")==run(state) then total=math.max(total,worldFrames(id)) end
    return math.floor(total/NHAffinity.framesPerPoint)
end

function NHAffinity.productionReading(state,id)
    local earned=worldFrames(id)
    local frames=math.max(saved(state,id),earned)
    local points=math.floor(frames/NHAffinity.framesPerPoint)
    -- The companion script awards six frames at a time. Poll once the next
    -- point can possibly change, including while an older world catches up.
    local delay=math.max(1,(points+1)*NHAffinity.framesPerPoint-earned-5)
    return points,points==NHAffinity.maxPoints and math.huge or delay
end

function NHAffinity.changed(state)
    if GlobalsGetValue(prefix.."run","")~=run(state) then return false end
    for _,id in ipairs(NHCompanions.order) do
        if worldFrames(id)>saved(state,id) then return true end
    end
    return false
end

function NHAffinity.sync(draft)
    if GlobalsGetValue(prefix.."run","")~=run(draft) then return end
    for _,id in ipairs(NHCompanions.order) do
        local total=worldFrames(id)
        if total>saved(draft,id) then
            draft.affinity=draft.affinity or {}
            draft.affinity[id]=total
        end
    end
end
