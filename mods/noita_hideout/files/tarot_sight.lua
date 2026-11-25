local M={tickInterval=15}
local published="nh_tarot_sight_shader"
local uniform="nh_tarot_sight"
local blindFiles={
    ["data/entities/misc/effect_blindness.xml"]=true,
    ["data/entities/misc/effect_blindness_custom_short.xml"]=true,
}
local blindParts={GameEffectComponent=true,InheritTransformComponent=true,AudioComponent=true,UIIconComponent=true}

function M.localBody(player)
    return player and player~=0 and EntityGetIsAlive(player)
        and not EntityHasTag(player,"ew_client") and not EntityHasTag(player,"ew_notplayer")
        and not EntityHasTag(player,"nh_ew_waiting") and not EntityHasTag(player,"polymorphed_player")
end

function M.framesLeft(player,tag,now)
    local c=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
    if not c then return 0 end
    return math.max(0,ComponentGetValue2(c,"value_int")-math.max(0,now-ComponentGetValue2(c,"value_float")))
end

-- Read the body's saved clocks directly, including between the normal 15-frame
-- ticks. Enemy scripts have separate Lua states and may use this entry point.
function M.active(player,now)
    if not M.localBody(player) then return false end
    now=now or GameGetFrameNum()
    return M.framesLeft(player,"nh_tarot_sun",now)>0 or M.framesLeft(player,"nh_tarot_moon",now)>0
end

local function publish(enabled,force)
    local value=enabled and "1" or ""
    if force or GlobalsGetValue(published,"")~=value then
        GameSetPostFxParameter(uniform,enabled and 1 or 0,0,0,0)
        GlobalsSetValue(published,value)
    end
end

function M.reset(force) publish(false,force) end

local function protected(tags)
    for tag in (tags or ""):gmatch("[^,]+") do
        if tag=="perk" or tag=="perk_entity" or tag:match("^nh_") or tag:match("^noita_hideout_") then return true end
    end
    return false
end

-- A modded carrier can drive combat, timers or on-remove callbacks from its
-- blindness component. Only discard dedicated temporary status entities.
local function dedicatedBlindness(entity)
    local effects=EntityGetComponentIncludingDisabled(entity,"GameEffectComponent")
    if not effects or #effects~=1 then return false end
    local effect=effects[1]
    if not ComponentGetIsEnabled(effect) or ComponentGetValue2(effect,"effect")~="BLINDNESS"
        or ComponentGetValue2(effect,"frames")<=0 then return false end
    if protected(EntityGetTags(entity)) or protected(ComponentGetTags(effect)) or next(EntityGetAllChildren(entity) or {}) then return false end
    local path=(EntityGetFilename(entity) or ""):gsub("\\","/")
    if not blindFiles[path] then
        -- Streaming may replace the filename. Validate the native status icon
        -- as well as the component layout before removing a restored carrier.
        if path:match("^mods/") then return false end
        local icon=EntityGetFirstComponentIncludingDisabled(entity,"UIIconComponent")
        if not icon or ComponentGetValue2(icon,"name")~="$status_blindness"
            or ComponentGetValue2(icon,"icon_sprite_file")~="data/ui_gfx/status_indicators/blindness.png"
            or ComponentGetValue2(icon,"is_perk") then return false end
    end
    for _,c in ipairs(EntityGetAllComponents(entity) or {}) do
        if not blindParts[ComponentGetTypeName(c)] then return false end
    end
    return true
end

function M.sync(player,now,force)
    if not M.localBody(player) then return end
    now=now or GameGetFrameNum()
    local left=math.max(M.framesLeft(player,"nh_tarot_sun",now),M.framesLeft(player,"nh_tarot_moon",now))
    local enabled=left>0
    publish(enabled,force)
    local closing=enabled and left<=M.tickInterval
    local hook=EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_tarot_tick")
    if hook then
        local period=closing and 1 or M.tickInterval
        if ComponentGetValue2(hook,"execute_every_n_frame")~=period then
            ComponentSetValue2(hook,"execute_every_n_frame",period)
        end
        -- A restored component may already have queued a coarser callback.
        if closing and ComponentGetValue2(hook,"mNextExecutionTime")>now+1 then
            ComponentSetValue2(hook,"mNextExecutionTime",now+1)
        end
    end
    -- The brief expiry countdown only needs to reset the shader. Keep status
    -- inspections on the normal cadence even when closing a card between ticks.
    if enabled and (not closing or now%M.tickInterval==0) and GameGetGameEffectCount(player,"BLINDNESS")>0 then
        for _,child in ipairs(EntityGetAllChildren(player) or {}) do
            if dedicatedBlindness(child) then EntityKill(child) end
        end
    end
    return enabled
end

return M
