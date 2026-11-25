local root="mods/noita_hideout/files/"
local entities,components={},{}
local function player()
    local id=#entities+1;entities[id]={tags={},components={},alive=true};return id
end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityRemoveTag(id,tag) entities[id].tags[tag]=nil end
function EntityGetWithTag(tag)
    local result={};for id,e in ipairs(entities) do if e.alive and e.tags[tag] then result[#result+1]=id end end;return result
end
function EntityAddComponent2(id,kind,data)
    data=data or {};data.kind=kind;data.tags={}
    for tag in (data._tags or ""):gmatch("[^,]+") do data.tags[tag]=true end
    components[#components+1]=data;entities[id].components[#entities[id].components+1]=#components;return #components
end
function EntityGetComponentIncludingDisabled(id,kind,tag)
    local result={}
    for _,c in ipairs(entities[id].components) do
        if components[c].kind==kind and (not tag or components[c].tags[tag]) then result[#result+1]=c end
    end
    return result
end
function EntityGetFirstComponentIncludingDisabled(id,kind,...)
    local tag=select(1,...)
    assert(select("#",...)==0 or tag~=nil,"Noita rejects an explicitly nil component tag")
    if tag=="" then return nil end
    return EntityGetComponentIncludingDisabled(id,kind,tag)[1]
end
function EntityRemoveComponent(id,c) components[c].kind=nil end
function ComponentGetValue2(c,key)
    local value=components[c][key];if type(value)=="table" then return unpack(value) end;return value
end
function ComponentSetValue2(c,key,a,b) components[c][key]=b~=nil and {a,b} or a end
function ComponentAddTag(c,tag) components[c].tags[tag]=true end
function ComponentRemoveTag(c,tag) components[c].tags[tag]=nil end
function ComponentHasTag(c,tag) return components[c].tags[tag] or false end
local base={run_velocity=154,fly_velocity_x=52,velocity_min_x=-57,velocity_max_x=57,velocity_min_y=-200,velocity_max_y=350,
    fly_speed_max_up=95,fly_speed_max_down=85,jump_velocity_x=56,jump_velocity_y=-95,pixel_gravity=350}
local function platform(id)
    local data={};for key,value in pairs(base) do data[key]=value end
    data.accel_x_air=0.1
    return EntityAddComponent2(id,"CharacterPlatformingComponent",data)
end
local function near(a,b) return math.abs(a-b)<0.000001 end
local p=player();local movement=platform(p)
local velocity=EntityAddComponent2(p,"CharacterDataComponent",{mVelocity={12,-40}})
ComponentSetValue2(movement,"mIsPrecisionJumping",true)
ComponentSetValue2(movement,"mPrecisionJumpingSpeedX",12)
ComponentSetValue2(movement,"mPrecisionJumpingTimeLeft",30)
local slow=dofile(root.."katana_movement.lua")
assert(slow.apply(p))
for key,value in pairs(base) do
    assert(near(components[movement][key],value*0.3),key)
end
assert(components[movement].accel_x_air==0.1)
local function checkVelocity(x,y)
    assert(near(components[velocity].mVelocity[1],x) and near(components[velocity].mVelocity[2],y))
end
checkVelocity(3.6,-12)
assert(near(components[movement].mPrecisionJumpingSpeedX,3.6))
-- The next native physics tick reuses its own horizontal knockback speed.
ComponentSetValue2(velocity,"mVelocity",components[movement].mPrecisionJumpingSpeedX,-12)
for n=1,15 do assert(slow.apply(p)) end
checkVelocity(3.6,-12)
assert(near(components[movement].mPrecisionJumpingSpeedX,3.6) and components[movement].mPrecisionJumpingTimeLeft==30)
ComponentSetValue2(movement,"mPrecisionJumpingSpeedX",-80)
assert(slow.apply(p) and near(components[movement].mPrecisionJumpingSpeedX,-17.1))
ComponentSetValue2(velocity,"mVelocity",80,400)
assert(slow.apply(p));checkVelocity(17.1,105)
assert(near(components[movement].velocity_max_x,17.1),"holding the mode must not stack its own multiplier")
components[movement].run_velocity=components[movement].run_velocity*1.5
components[movement].velocity_max_x=components[movement].velocity_max_x*1.5
components[movement].pixel_gravity=components[movement].pixel_gravity*0.6
slow.release(p)
checkVelocity(17.1,105)
assert(near(components[movement].mPrecisionJumpingSpeedX,-17.1),"exit must not amplify live knockback")
assert(near(components[movement].pixel_gravity,210),"Moon gravity applied during Blade Mode survives exit")
assert(near(components[movement].run_velocity,231) and near(components[movement].velocity_max_x,85.5),"release preserves an external speed buff")
slow.release(p)
assert(near(components[movement].run_velocity,231),"release is idempotent")
assert(slow.apply(p))
slow=dofile(root.."katana_movement.lua");slow.reset()
assert(near(components[movement].pixel_gravity,210))
assert(near(components[movement].run_velocity,231) and not entities[p].tags.nh_katana_movement,"new Lua state removes serialized slow")
assert(slow.apply(p))
EntityRemoveComponent(p,movement)
local replacement=platform(p)
ComponentSetValue2(replacement,"mIsPrecisionJumping",false)
ComponentSetValue2(replacement,"mPrecisionJumpingSpeedX",50)
ComponentSetValue2(velocity,"mVelocity",10,20)
assert(slow.apply(p) and near(components[replacement].run_velocity,154*0.3),"replacement is scaled once, never inflated by restoration")
checkVelocity(10,20)
assert(components[replacement].mPrecisionJumpingSpeedX==50,"inactive jump cache is unrelated to current momentum")
slow.release(p);assert(near(components[replacement].run_velocity,154))
local other=player();local otherPlatform=platform(other)
assert(slow.apply(p) and slow.apply(other));slow.reset()
assert(near(components[replacement].velocity_max_x,57) and near(components[otherPlatform].velocity_max_x,57))
-- Before 0.44.3 saved fields included speed but not gravity. Loading one
-- must restore exactly what that version changed, even with Moon active.
ComponentSetValue2(otherPlatform,"run_velocity",154*0.3)
ComponentSetValue2(otherPlatform,"pixel_gravity",210)
ComponentAddTag(otherPlatform,"nh_katana_movement_scaled")
EntityAddTag(other,"nh_katana_movement")
EntityAddComponent2(other,"VariableStorageComponent",{_tags="nh_katana_movement",value_float=0.3,value_string="run_velocity"})
dofile(root.."katana_movement.lua").reset()
assert(near(components[otherPlatform].run_velocity,154) and components[otherPlatform].pixel_gravity==210)
assert(not slow.apply(0))
slow.release(nil);slow.release(0)
print("Katana movement: native movement limits, idempotence, external multipliers, replacement and serialized cleanup passed.")
