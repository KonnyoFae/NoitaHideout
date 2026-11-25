local M={factor=0.3}
local tag="nh_katana_movement"
local platformTag="nh_katana_movement_scaled"
local fields={"run_velocity","fly_velocity_x","velocity_min_x","velocity_max_x","velocity_min_y","velocity_max_y",
    "fly_speed_max_up","fly_speed_max_down","jump_velocity_x","jump_velocity_y","pixel_gravity"}
local tracked={}
local function record(player)
    return EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
end
local function limit(value,low,high)
    if type(low)=="number" and type(high)=="number" then return math.max(low,math.min(high,value)) end
    return value
end
local function updateMomentum(player,platform,entering)
    local motion=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
    if not motion then return end
    local vx,vy=ComponentGetValue2(motion,"mVelocity")
    if type(vx)~="number" or type(vy)~="number" then return end
    -- Carry the entry velocity into the slower movement scale exactly once.
    -- Native drag then decays this momentum at its normal rate.
    local ratio=entering and M.factor or 1
    local minx,maxx=ComponentGetValue2(platform,"velocity_min_x"),ComponentGetValue2(platform,"velocity_max_x")
    local miny,maxy=ComponentGetValue2(platform,"velocity_min_y"),ComponentGetValue2(platform,"velocity_max_y")
    if ComponentGetValue2(platform,"mIsPrecisionJumping") then
        -- In a precision jump or knockback the engine copies this horizontal
        -- speed back into mVelocity every tick, until that movement ends.
        local heldX=ComponentGetValue2(platform,"mPrecisionJumpingSpeedX")
        if type(heldX)=="number" then
            local nextX=limit(heldX*ratio,minx,maxx)
            if nextX~=heldX then ComponentSetValue2(platform,"mPrecisionJumpingSpeedX",nextX) end
        end
    end
    ComponentSetValue2(motion,"mVelocity",limit(vx*ratio,minx,maxx),limit(vy*ratio,miny,maxy))
end
function M.release(player)
    if not player or player==0 then return end
    tracked[player]=nil
    if not EntityGetIsAlive(player) then return end
    local c=record(player)
    if c then
        local factor=ComponentGetValue2(c,"value_float")
        if type(factor)=="number" and factor>0 then
            for _,platform in ipairs(EntityGetComponentIncludingDisabled(player,"CharacterPlatformingComponent",platformTag) or {}) do
                for field in (ComponentGetValue2(c,"value_string") or ""):gmatch("[^,]+") do
                    local value=ComponentGetValue2(platform,field)
                    if type(value)=="number" then ComponentSetValue2(platform,field,value/factor) end
                end
                ComponentRemoveTag(platform,platformTag)
            end
        end
        EntityRemoveComponent(player,c)
    end
    EntityRemoveTag(player,tag)
end
function M.apply(player)
    if not player or player==0 or not EntityGetIsAlive(player) then return false end
    local platform=EntityGetFirstComponentIncludingDisabled(player,"CharacterPlatformingComponent")
    if not platform then M.release(player);return false end
    local c=record(player)
    local entering=not c
    if c and not ComponentHasTag(platform,platformTag) then
        -- A replaced movement component is unmodified. Unwind only the old
        -- component carrying our marker, never divide the replacement's speed.
        M.release(player); c=nil
    end
    if not c then
        local applied={}
        for _,field in ipairs(fields) do
            if type(ComponentGetValue2(platform,field))=="number" then applied[#applied+1]=field end
        end
        if #applied==0 then return false end
        c=EntityAddComponent2(player,"VariableStorageComponent",{_tags=tag,value_float=M.factor,value_string=table.concat(applied,",")})
        if not c or c==0 then return false end
        for _,field in ipairs(applied) do ComponentSetValue2(platform,field,ComponentGetValue2(platform,field)*M.factor) end
        ComponentAddTag(platform,platformTag)
        EntityAddTag(player,tag)
    end
    tracked[player]=true
    updateMomentum(player,platform,entering)
    return true
end
function M.reset()
    -- Entity/component tags survive save/load even though this Lua table does
    -- not. Reversing our ratio preserves later companion and perk multipliers.
    for _,player in ipairs(EntityGetWithTag(tag) or {}) do tracked[player]=true end
    local pending={}
    for player in pairs(tracked) do pending[#pending+1]=player end
    for _,player in ipairs(pending) do M.release(player) end
end
return M
