local id=GetUpdatedEntityID()
local anim=EntityGetFirstComponent(id,"VariableStorageComponent")
local tick=tonumber(ComponentGetValue2(anim,"value_string")) or 0
local angle=ComponentGetValue2(anim,"value_float")-0.9+tick*0.3
local scale=ComponentGetValue2(anim,"value_int")
local dx,dy=math.cos(angle),math.sin(angle)
local x,y=EntityGetTransform(id)
for distance=3,18*scale,2 do
    for side=-scale,scale,2 do
        GameCreateParticle("spark_white",x+dx*distance-dy*side,y+dy*distance+dx*side,1,0,0,true,false,false)
    end
end
ComponentSetValue2(anim,"value_string",tostring(tick+1))
