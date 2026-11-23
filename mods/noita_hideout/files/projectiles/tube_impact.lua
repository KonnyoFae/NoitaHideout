local id=GetUpdatedEntityID()
local shot=EntityGetFirstComponentIncludingDisabled(id,"ProjectileComponent")
if not shot or ComponentGetValue2(shot,"lifetime")<=0 then return end
local owner=ComponentGetValue2(shot,"mWhoShot")
if not owner or owner==0 then return end
local x,y,angle=EntityGetTransform(id)
if not x or not DoesWorldExistAt(math.floor(x)-1,math.floor(y)-1,math.ceil(x)+1,math.ceil(y)+1) then return end
local movement=EntityGetFirstComponentIncludingDisabled(id,"VelocityComponent")
local vx,vy=ComponentGetValue2(movement,"mVelocity")
if vx*vx+vy*vy<0.01 then vx,vy=ComponentGetValue2(movement,"mPrevVelocity") end
if vx*vx+vy*vy>=0.01 then angle=math.atan2(vy,vx) end

local marker=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_tube_payload")
local payload=ComponentGetValue2(marker,"value_string")
if payload=="tube_cutter" and ComponentGetValue2(marker,"value_bool") then angle=ComponentGetValue2(marker,"value_float") end
-- Keep the fog and cement on the open side of a wall. The cut starts at contact.
if payload~="tube_cutter" then x,y=x-math.cos(angle)*2,y-math.sin(angle)*2 end
local effect=EntityLoad("mods/noita_hideout/files/projectiles/"..payload..".xml",x,y)
if not effect or effect==0 then return end
if payload=="tube_cutter" or payload=="tube_cloud" then
    if EntityGetIsAlive(owner) then EntityAddChild(owner,effect) end
    EntitySetTransform(effect,x,y,angle)
elseif payload=="tube_freeze" then
    local field=EntityGetFirstComponentIncludingDisabled(effect,"ProjectileComponent")
    ComponentSetValue2(field,"mWhoShot",owner)
    ComponentSetValue2(field,"mShooterHerdId",ComponentGetValue2(shot,"mShooterHerdId"))
elseif payload=="pheromone_splash" and EntityGetIsAlive(owner) then
    local targets=dofile_once("mods/noita_hideout/files/companions/targets.lua")
    for _,enemy in ipairs(EntityGetInRadiusWithTag(x,y,23,"mortal") or {}) do
        if targets.hostile(owner,enemy) then
            local ex,ey=EntityGetFirstHitboxCenter(enemy)
            if ex and (ex-x)^2+(ey-y)^2<=23^2 and not RaytraceSurfaces(x,y,ex,ey) then
                LoadGameEffectEntityTo(enemy,"mods/noita_hideout/files/projectiles/pheromone_contact.xml")
            end
        end
    end
end
