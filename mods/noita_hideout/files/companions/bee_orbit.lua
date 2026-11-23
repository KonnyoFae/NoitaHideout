local bee=GetUpdatedEntityID()
local pet=EntityGetParent(bee)
local player=pet~=0 and EntityGetParent(pet)
if not player or player==0 or not EntityGetIsAlive(player) then EntityKill(bee); return end
local phase=EntityGetFirstComponentIncludingDisabled(bee,"VariableStorageComponent","nh_bee_phase")
if not phase then return end
local angle=GameGetFrameNum()*0.052+ComponentGetValue2(phase,"value_float")
local x,y=EntityGetTransform(player)
EntitySetTransform(bee,x+math.cos(angle)*21,y-3+math.sin(angle)*16,0,math.sin(angle)>0 and -1 or 1,1)
