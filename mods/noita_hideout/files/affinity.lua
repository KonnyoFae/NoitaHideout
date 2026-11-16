-- Companion entity scripts and init.lua have separate Lua states. World
-- globals retain the exact number of companionship frames between checkpoints.
NHAffinity={thresholds={0,10,40,100},framesPerPoint=360}
local maximum=NHAffinity.framesPerPoint*100
local prefix="noita_hideout_affinity_"
local run_key="noita_hideout_run_v1"

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

function NHAffinity.follow(id,elapsed)
    local bound=GlobalsGetValue(prefix.."run","")
    if bound=="" or bound~=GlobalsGetValue(run_key,"") then return 0 end
    local current=worldFrames(id)
    local floor=tonumber(GlobalsGetValue(prefix.."floor_"..id,"0")) or 0
    if floor>=maximum then return 100 end
    local advanced=math.min(maximum,current+elapsed)
    if advanced~=current then GlobalsSetValue(prefix..id,tostring(advanced)) end
    return math.floor(math.max(floor,advanced)/NHAffinity.framesPerPoint)
end

function NHAffinity.points(state,id)
    local total=saved(state,id)
    if GlobalsGetValue(prefix.."run","")==run(state) then total=math.max(total,worldFrames(id)) end
    return math.floor(total/NHAffinity.framesPerPoint)
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
