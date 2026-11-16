-- Keep the precise active timer with the world save. The hideout profile
-- periodically checkpoints it, and owns all boosts and product deliveries.
NHClock={}
local world_key="noita_hideout_workshop_clock"
local profile,run,job,ticket,last_frame,progress

function NHClock.reset()
    profile,run,job,ticket,last_frame,progress=nil,nil,nil,nil,nil,0
end

function NHClock.suspend()
    last_frame=nil
end

function NHClock.observe(state,frame)
    local order=state.order
    if not order then NHClock.reset(); return 0 end
    if profile~=state.profile or run~=state.runSerial or job~=order.id then
        profile,run,job=state.profile,state.runSerial,order.id
        ticket=table.concat({profile,run,job,""},"/")
        local saved=GlobalsGetValue(world_key,"")
        local previous=saved:sub(1,#ticket)==ticket and tonumber(saved:sub(#ticket+1)) or 0
        last_frame,progress=frame,math.max(order.progress,math.min(order.required,math.floor(previous)))
    end
    local delta=last_frame and math.max(0,frame-last_frame) or 0
    local elapsed=math.min(order.required,math.max(order.progress,progress)+delta)
    if elapsed~=progress then GlobalsSetValue(world_key,ticket..elapsed) end
    last_frame,progress=frame,elapsed
    return elapsed
end

-- The vanilla room defines its bounds in workshop_aabb.xml. The boss arena
-- also uses this entity, so verify the biome of the fixed room anchor.
function NHClock.mountainAt(player)
    local x,y=EntityGetTransform(player)
    local room=EntityGetClosestWithTag(x,y,"workshop_aabb")
    if not room or room==0 then return end
    local ax,ay=EntityGetTransform(room)
    local hitbox=EntityGetFirstComponentIncludingDisabled(room,"HitboxComponent")
    if not hitbox then return end
    local dx,dy=x-ax,y-ay
    if dx<ComponentGetValue2(hitbox,"aabb_min_x") or dx>ComponentGetValue2(hitbox,"aabb_max_x")
        or dy<ComponentGetValue2(hitbox,"aabb_min_y") or dy>ComponentGetValue2(hitbox,"aabb_max_y") then return end
    if BiomeMapGetName(ax,ay)=="$biome_holymountain" then
        return math.floor(ax)..","..math.floor(ay)
    end
end
