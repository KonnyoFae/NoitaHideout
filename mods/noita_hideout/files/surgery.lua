local M={}
local active

function M.reset(spawnedPlayer)
    active=nil
    -- Older saves may contain the damage listener from an unfinished operation.
    if spawnedPlayer then
        local old=EntityGetFirstComponentIncludingDisabled(spawnedPlayer,"LuaComponent","noita_hideout_surgery_damage")
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

function M.beginUse(player,kind,duration,available,finish)
    if active or not available() then return true end
    local model=health(player)
    if not model then return true end
    local frame=GameGetFrameNum()
    active={player=player,kind=kind,model=model,available=available,finish=finish,
        startFrame=frame,lastFrame=frame,duration=duration}
    return true
end

function M.begin(player,kind,available,pay)
    local surgery=NHSurgeryKits.types[kind]
    if active or not available() then return surgery~=nil end
    local model,hp,maximum=health(player)
    if not model then return surgery~=nil end
    local kit=surgery or NHMedkits.types[kind]
    local function needed(hp,maximum)
        return hp<maximum or (surgery and NHSurgeryCleanse.has(player))
    end
    if not needed(hp,maximum) then return surgery~=nil,"unneeded" end
    return M.beginUse(player,kind,kit.castFrames,available,function()
        local model,hp,maximum=health(player)
        if not model or not needed(hp,maximum) then return "unneeded" end
        if not pay() then return "interrupted" end
        if surgery then
            NHSurgeryCleanse.cleanse(player)
            model,hp,maximum=health(player)
        end
        if model and hp<maximum then
            ComponentSetValue2(model,"hp",math.min(maximum,hp+maximum*kit.healPercent/100))
        end
        return "completed"
    end)
end

function M.physicalSource(player,entity,inventorySlot,maxCharges,legacyBandage)
    local function charges(item)
        local n=item and ComponentGetValue2(item,"uses_remaining")
        if legacyBandage and n==-1 then return 1 end
        if type(n)=="number" and n>=1 and n<=maxCharges and n==math.floor(n) then return n end
    end
    local function available()
        if not EntityGetIsAlive(entity) then return false end
        local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
        if not charges(item) then return false end
        if inventorySlot then
            if EntityGetRootEntity(entity)~=player then return false end
            if inventorySlot==true then return true end
            if EntityGetParent(entity)~=inventorySlot.parent then return false end
            local x,y=ComponentGetValue2(item,"inventory_slot")
            if x~=inventorySlot.xslot or y~=inventorySlot.yslot then return false end
        elseif GameIsInventoryOpen() or NHNative.held(player)~=entity then return false end
        return true
    end
    return available,function()
        local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
        local n=charges(item)
        if n==1 then GameKillInventoryItem(player,entity) else ComponentSetValue2(item,"uses_remaining",n-1) end
        return true
    end
end

function M.start(player,entity,inventorySlot)
    if not entity or entity==0 then return false end
    local kind
    for _,id in ipairs(NHSurgeryKits.order) do
        if EntityHasTag(entity,"noita_hideout_"..id) then kind=id; break end
    end
    if not kind then return false end
    return M.begin(player,kind,M.physicalSource(player,entity,inventorySlot,4*NHSurgeryKits.types[kind].uses))
end

function M.update(player)
    local cast=active
    if not cast then return end
    local frame=GameGetFrameNum()
    if player~=cast.player or frame<cast.lastFrame or not EntityGetIsAlive(player)
        or not cast.available() then
        M.reset()
        return "interrupted",cast.kind
    end
    local model=health(player)
    if model~=cast.model then
        M.reset()
        return "interrupted",cast.kind
    end
    cast.lastFrame=frame
    if frame-cast.startFrame<cast.duration then return end

    M.reset()
    return cast.finish(),cast.kind
end

return M
