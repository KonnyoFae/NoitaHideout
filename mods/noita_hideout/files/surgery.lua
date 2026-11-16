local M={}
local hookTag="noita_hideout_surgery_damage"
local active

local function damageHook(player)
    return EntityGetFirstComponentIncludingDisabled(player,"LuaComponent",hookTag)
end

function M.reset(spawnedPlayer)
    local cast=active
    active=nil
    if cast and EntityGetIsAlive(cast.player) and damageHook(cast.player)==cast.hook then
        EntityRemoveComponent(cast.player,cast.hook)
    end
    if spawnedPlayer then
        local old=damageHook(spawnedPlayer)
        if old then EntityRemoveComponent(spawnedPlayer,old) end
    end
end

function M.view()
    if active then
        return {kind=active.kind,elapsed=active.lastFrame-active.startFrame,total=active.duration}
    end
end

local function health(player)
    local model=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if model then
        local hp=ComponentGetValue2(model,"hp")
        local maximum=ComponentGetValue2(model,"max_hp")
        if hp and hp>0 and maximum and maximum>0 then return model,hp,maximum end
    end
end

local function hasCharge(entity,kind)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    return item and ComponentGetValue2(item,"uses_remaining")==NHSurgeryKits.types[kind].uses
end

function M.begin(player,kind,available,pay)
    if active or not available() then return true end
    local model,hp,maximum=health(player)
    if not model then return true end
    if hp>=maximum and not NHSurgeryCleanse.has(player) then return true,"unneeded" end

    -- A saved player may still carry the listener from a cast abandoned on reload.
    local old=damageHook(player)
    if old then EntityRemoveComponent(player,old) end
    local hook=EntityAddComponent2(player,"LuaComponent",{
        _tags=hookTag,execute_every_n_frame=-1,
        script_damage_received="mods/noita_hideout/files/surgery_damage.lua",
    })
    if not hook or hook==0 then return true,"interrupted" end
    local frame=GameGetFrameNum()
    active={player=player,kind=kind,hook=hook,model=model,hp=hp,maximum=maximum,available=available,pay=pay,
        startFrame=frame,lastFrame=frame,duration=NHSurgeryKits.types[kind].castFrames}
    return true
end

function M.start(player,entity,inventorySlot)
    if not entity or entity==0 then return false end
    local kind
    for _,id in ipairs(NHSurgeryKits.order) do
        if EntityHasTag(entity,"noita_hideout_"..id) then kind=id; break end
    end
    if not kind then return false end
    local function available()
        if inventorySlot then
            if not EntityGetIsAlive(entity) or EntityGetParent(entity)~=inventorySlot.parent or EntityGetRootEntity(entity)~=player then return false end
            local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
            if not item then return false end
            local x,y=ComponentGetValue2(item,"inventory_slot")
            if x~=inventorySlot.xslot or y~=inventorySlot.yslot then return false end
        elseif GameIsInventoryOpen() or NHNative.held(player)~=entity then return false end
        return hasCharge(entity,kind)
    end
    return M.begin(player,kind,available,function() GameKillInventoryItem(player,entity); return true end)
end

function M.update(player)
    local cast=active
    if not cast then return end
    local frame=GameGetFrameNum()
    if player~=cast.player or frame<cast.lastFrame or not EntityGetIsAlive(player)
        or not cast.available()
        or EntityGetFirstComponent(player,"LuaComponent",hookTag)~=cast.hook then
        M.reset()
        return "interrupted"
    end
    local model,hp,maximum=health(player)
    -- Hearty rescales both current and maximum HP. Only HP lost beyond that
    -- change counts as direct damage when the engine sends no damage message.
    if model~=cast.model or hp<cast.hp*math.min(1,maximum/cast.maximum) then
        M.reset()
        return "interrupted"
    end
    cast.lastFrame,cast.hp,cast.maximum=frame,hp,maximum
    if frame-cast.startFrame<cast.duration then return end

    M.reset()
    if hp>=maximum and not NHSurgeryCleanse.has(player) then return "unneeded" end
    if not cast.pay() then return "interrupted" end
    NHSurgeryCleanse.cleanse(player)
    -- Removing a health curse can change the current maximum during this step.
    model,hp,maximum=health(player)
    if model and hp<maximum then
        local percent=NHSurgeryKits.types[cast.kind].healPercent
        ComponentSetValue2(model,"hp",math.min(maximum,hp+maximum*percent/100))
    end
    return "completed"
end

return M
