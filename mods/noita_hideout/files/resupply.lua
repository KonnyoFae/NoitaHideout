local R={resource="supply_logistics",station="resupply",shortage="Not enough supply logistics packs."}
local items="mods/noita_hideout/files/items/"
local pendingEjections={}

-- Box2D initializes a newly spawned item's body on a subsequent engine tick.
function R.eject()
    for id,side in pairs(pendingEjections) do
        if not EntityGetIsAlive(id) or EntityGetRootEntity(id)~=id then
            pendingEjections[id]=nil
        elseif #(PhysicsBodyIDGetFromEntity(id) or {})>0 then
            PhysicsApplyForce(id,side*32,-55)
            pendingEjections[id]=nil
        end
    end
end

-- Look for a reachable column beside the caller. A cave roof shortens the
-- descent. Sample both edges so the capsule cannot start inside an overhang.
local function column(px,py,x,air)
    if x~=px and RaytracePlatforms(px,py,x,py) then return end
    local floor,ceiling
    for _,edge in ipairs({x-6,x,x+6}) do
        local hit,_,ground=RaytracePlatforms(edge,py-2,edge,py+96)
        if not hit and not air then return end
        if not hit then ground=py+8 end
        floor=math.min(floor or ground,ground)
        local roof,_,top=RaytracePlatforms(edge,py-2,edge,py-64)
        local limit=roof and top+9 or py-60
        ceiling=math.max(ceiling or limit,limit)
    end
    if ceiling+2>=floor-8 then return end
    if not DoesWorldExistAt(math.floor(x-8),math.floor(ceiling-8),math.ceil(x+8),math.ceil(floor+1)) then return end
    return ceiling
end

local groundUnits={missile_crab=true,robot_monk=true,ground_guard=true,mg_turret=true,chaingun_turret=true,missile_turret=true}
function R.launch(call,player)
    local px,py=EntityGetTransform(player)
    local supply=call.tier~=nil or call.weapon~=nil
    for _,offset in ipairs(supply and {0,6,-6,16,-16} or {22,-22,36,-36,0}) do
        local x=px+offset
        local start=column(px,py,x)
        if not supply and not groundUnits[call.project] and not start then
            start=column(px,py,x,true)
            if start then call.airY=py end
        end
        if start then
            local id=EntityLoad("mods/noita_hideout/files/supply_pod.xml",x,start)
            if not id or id==0 then break end
            call.phase,call.pod,call.x,call.y,call.bottom,call.speed="descending",id,x,start,py+100,1
            return true
        end
    end
end

-- Return the first surface touched by the bottom of the moving pod. Check
-- again during flight because explosions and falling material change terrain.
function R.advance(call)
    if not EntityGetIsAlive(call.pod) or not EntityHasTag(call.pod,"nh_supply_pod") then return "failed" end
    local x,y=call.x,call.y
    call.speed=math.min(5,call.speed+0.18)
    local nextY=y+call.speed
    if nextY>call.bottom or not DoesWorldExistAt(math.floor(x-8),math.floor(y-8),math.ceil(x+8),math.ceil(nextY+9)) then
        return "failed"
    end
    local floor
    for _,edge in ipairs({x-6,x,x+6}) do
        local hit,_,ground=RaytracePlatforms(edge,y+8,edge,nextY+8)
        if hit then floor=math.min(floor or ground,ground) end
    end
    call.y=floor and floor-8 or nextY
    if call.airY then call.y=math.min(call.airY,call.y) end
    EntitySetTransform(call.pod,x,call.y)
    if floor or call.y==call.airY then return "landed" end
end

function R.deliver(call,pay)
    local packs={}
    local count=call.weapon and 1 or 4
    local path=items..(call.weapon or NHLootBags.packKinds[call.tier])..".xml"
    for i=1,count do
        local id=EntityLoad(path,call.x+(i-(count+1)/2)*2,call.y)
        if not id or id==0 then break end
        packs[i]=id
    end
    if #packs==count and pay() then
        for i,id in ipairs(packs) do pendingEjections[id]=i-(count+1)/2 end
        return true
    end
    for _,id in ipairs(packs) do EntityKill(id) end
    if #packs<count then return false,"Supply pod could not open." end
    return false
end
return R
