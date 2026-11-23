local pet=GetUpdatedEntityID()
local player=EntityGetParent(pet)
if not player or player==0 or not EntityGetIsAlive(player) then return end
local x,y=EntityGetTransform(player)
local frame=GameGetFrameNum()

local function opacity(entity,sprite,alpha)
    ComponentSetValue2(sprite,"visible",alpha>0)
    ComponentSetValue2(sprite,"alpha",alpha)
    EntityRefreshSprite(entity,sprite)
end

-- This script has a private VM per companion. Rebind serialized entities after loading a world.
local state=companionDisplay
if not state then
    local portrait=EntityGetFirstComponentIncludingDisabled(pet,"SpriteComponent")
    local clock=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_companion_clock")
    if not portrait or not clock then return end
    local wisp=(EntityGetAllChildren(pet,"nh_companion_wisp") or {})[1]
    if not wisp then
        wisp=EntityLoad("mods/noita_hideout/files/companions/wisp.xml",x-9,y-12)
        if not wisp or wisp==0 then return end
        EntityAddChild(pet,wisp)
    end
    local dot=EntityGetFirstComponentIncludingDisabled(wisp,"SpriteComponent")
    if not dot then return end
    local species=ComponentGetValue2(clock,"value_string")
    ComponentSetValue2(dot,"rect_animation",species)
    ComponentSetValue2(dot,"next_rect_animation",species)
    local alpha=ComponentGetValue2(portrait,"alpha")
    state={portrait=portrait,wisp=wisp,dot=dot,x=x,y=y,lastMove=alpha==1 and frame-60 or frame,
        alpha=alpha,offsetX=-9,offsetY=-12}
    companionDisplay=state
    opacity(pet,portrait,alpha)
    opacity(wisp,dot,1-alpha)
end

-- Measure displacement from the last significant sample so even a slow walk
-- accumulates, while subpixel vibration at rest does not restart the wait.
local dx,dy=x-state.x,y-state.y
if dx*dx+dy*dy>0.01 then
    state.x,state.y,state.lastMove=x,y,frame
end
local resting=frame-state.lastMove>=60
local alpha
if resting then alpha=math.min(1,state.alpha+1/16)
else alpha=math.max(0,state.alpha-1/8) end
if alpha~=state.alpha then
    opacity(pet,state.portrait,alpha)
    opacity(state.wisp,state.dot,1-alpha)
    state.alpha=alpha
end

-- Smooth the offset, not the player's world position. The light stays at the
-- player's shoulder even during a fast fall or on the frame of a teleport.
local tx,ty=-9,-12+math.sin(frame/19)
if resting then
    local px,py=EntityGetTransform(pet)
    tx,ty=px-x,py-y
end
state.offsetX=state.offsetX+(tx-state.offsetX)*0.2
state.offsetY=state.offsetY+(ty-state.offsetY)*0.2
if alpha<1 then EntitySetTransform(state.wisp,x+state.offsetX,y+state.offsetY) end
