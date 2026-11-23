local eye=GetUpdatedEntityID()
local player=EntityGetRootEntity(eye)
local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
local beam=(EntityGetAllChildren(eye) or {})[1]
if controls and beam then
    local dx,dy=ComponentGetValue2(controls,"mAimingVectorNormalized")
    local x,y=EntityGetTransform(player)
    EntitySetTransform(beam,x+dx*10,y+dy*10,math.atan2(dy,dx))
end
