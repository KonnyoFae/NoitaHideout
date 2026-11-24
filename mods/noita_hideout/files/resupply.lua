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
local function spawnPod(call,x,start,bottom)
    local id=EntityLoad("mods/noita_hideout/files/supply_pod.xml",x,start)
    if not id or id==0 then return false end
    call.phase,call.pod,call.x,call.y,call.bottom,call.speed="descending",id,x,start,bottom,1
    return true
end

function R.playerDropClear(x,y,ignore)
    -- EW keeps ew_client on remote polymorphs when the normal peer body
    -- (and its ew_peer tag) has been replaced.
    for _,tag in ipairs({"ew_peer","ew_client"}) do
        for _,body in ipairs(EntityGetInRadiusWithTag(x,y,13,tag) or {}) do
            if body~=ignore and not EntityHasTag(body,"nh_ew_waiting") then return false end
        end
    end
    return true
end

-- A player can open the capsule in midair. Check the whole player footprint
-- against terrain and liquid, even when the death point used to have a floor.
function R.reviveSpace(x,y,ignore)
    if not DoesWorldExistAt(x-7,y-15,x+7,y+8) then return false end
    for dx=-6,6,2 do
        if RaytraceSurfacesAndLiquiform(x+dx,y-14,x+dx,y+6) then return false end
    end
    return R.playerDropClear(x,y,ignore)
end

local offsets
function R.reviveSite(x,y,ignore)
    if not offsets then
        offsets={}
        for dx=-48,48,12 do
            for dy=-48,48,12 do
                local d=dx*dx+dy*dy
                if d<=48*48 then offsets[#offsets+1]={x=dx,y=dy,d=d} end
            end
        end
        table.sort(offsets,function(a,b)
            if a.d~=b.d then return a.d<b.d end
            if a.y~=b.y then return a.y<b.y end
            return a.x<b.x
        end)
    end
    for _,off in ipairs(offsets) do
        local px,py=math.floor(x)+off.x,math.floor(y)+off.y
        if R.reviveSpace(px,py,ignore) then
            local start=py-1
            -- Render as much descent as the loaded cave ceiling allows.
            for rise=9,57,8 do
                if not DoesWorldExistAt(px-7,py-rise-7,px+7,py) then break end
                local blocked=false
                for dx=-6,6,3 do
                    if RaytraceSurfacesAndLiquiform(px+dx,py-7,px+dx,py-rise-7) then blocked=true;break end
                end
                if blocked then break end
                start=py-rise
            end
            return {x=px,y=py,start=start}
        end
    end
end

function R.alternatePlayerSite(player)
    local x,y=EntityGetTransform(player)
    for _,dx in ipairs({22,-22,36,-36}) do
        local px=math.floor(x+dx)
        if not RaytracePlatforms(x,y,px,y) and R.reviveSpace(px,math.floor(y)) then
            return px,math.floor(y)
        end
    end
end

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
            return spawnPod(call,x,start,py+100)
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
