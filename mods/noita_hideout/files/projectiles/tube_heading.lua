-- An impact stops the round and the engine can rotate its sprite before removal.
local id=GetUpdatedEntityID()
local movement=EntityGetFirstComponent(id,"VelocityComponent")
local vx,vy=ComponentGetValue2(movement,"mVelocity")
if vx*vx+vy*vy>0.01 then
    local payload=EntityGetFirstComponent(id,"VariableStorageComponent","nh_tube_payload")
    ComponentSetValue2(payload,"value_float",math.atan2(vy,vx))
    ComponentSetValue2(payload,"value_bool",true)
end
