local sources=dofile("mods/noita_hideout/files/loot_bonus_sources.lua")
local M={dirtyField="nh_ew.loot_bonuses_dirty"}
local byId,byEvent={},{}
for _,s in ipairs(sources) do
    assert(not byId[s.id] and s.id:match("^[a-z][a-z0-9_]*$") and s.duration>=1 and s.duration==math.floor(s.duration))
    byId[s.id]=s
    s.tag=s.tag or "nh_loot_bonus_"..s.id
    for event,rates in pairs(s.events) do
        local list=byEvent[event] or {}
        byEvent[event]=list
        for lane,chance in pairs(rates) do
            assert((lane=="bag" or lane=="tarot" or lane=="red") and chance>0 and chance<=1)
        end
        list[#list+1]={source=s,rates=rates}
    end
end

local function eligible(player)
    return player and player~=0 and EntityGetIsAlive(player)
        and not EntityHasTag(player,"ew_notplayer") and not EntityHasTag(player,"nh_ew_waiting")
end

local function remaining(player,s,remote,now)
    local tag=remote and s.tag.."_remote" or s.tag
    local c=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
    local frames=c and ComponentGetValue2(c,"value_int")-now or 0
    local limit=remote and math.min(s.duration,180) or s.duration
    return frames>0 and frames<=limit and frames or 0
end

local function setTimer(player,tag,deadline,pay)
    local c=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
    local existing=c
    if not c then
        if deadline==0 then return true end
        c=EntityAddComponent2(player,"VariableStorageComponent",{_tags=tag,name=tag,value_int=0})
        if not c or c==0 then return false end
    end
    if pay and not pay() then
        if not existing then EntityRemoveComponent(player,c) end
        return false
    end
    ComponentSetValue2(c,"value_int",deadline)
    return true
end

function M.activate(player,id,pay)
    local s=byId[id]
    if not s or not eligible(player) or not EntityHasTag(player,"player_unit") or EntityHasTag(player,"ew_client") then return false end
    if not setTimer(player,s.tag,GameGetFrameNum()+s.duration,pay) then return false end
    GlobalsSetValue(M.dirtyField,"1")
    return true
end

function M.remaining(player,id)
    local s=byId[id]
    if not s or not eligible(player) then return 0 end
    return remaining(player,s,EntityHasTag(player,"ew_client"),GameGetFrameNum())
end

-- Read-only. Each lane gets at most one retry with P = 1 - product(1 - q).
function M.rerolls(player,event)
    local list=byEvent[event]
    if not list or not eligible(player) then return end
    local remote,now=EntityHasTag(player,"ew_client"),GameGetFrameNum()
    local result
    for _,entry in ipairs(list) do
        if remaining(player,entry.source,remote,now)>0 then
            result=result or {}
            for lane,chance in pairs(entry.rates) do
                local previous=result[lane] or 0
                result[lane]=previous+(1-previous)*chance
            end
        end
    end
    return result
end

-- EW publishes a full list of active source ids and their remaining game
-- frames. Base probabilities always come from the local source definitions.
function M.snapshot(player)
    local snapshot={}
    if eligible(player) and not EntityHasTag(player,"ew_client") then
        local now=GameGetFrameNum()
        for _,s in ipairs(sources) do
            local frames=remaining(player,s,false,now)
            if frames>0 then snapshot[s.id]=frames end
        end
    end
    return snapshot
end

function M.applyRemote(player,snapshot)
    if type(snapshot)~="table" or not player or player==0 or not EntityGetIsAlive(player)
        or not EntityHasTag(player,"ew_client") then return false end
    for id,frames in pairs(snapshot) do
        local s=byId[id]
        if not s or type(frames)~="number" or frames<1 or frames>s.duration or frames~=math.floor(frames) then return false end
    end
    local now=GameGetFrameNum()
    for _,s in ipairs(sources) do
        local frames=snapshot[s.id]
        if not setTimer(player,s.tag.."_remote",frames and now+math.min(frames,180) or 0) then return false end
    end
    return true
end
return M
