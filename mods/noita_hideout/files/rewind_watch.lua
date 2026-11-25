-- The record and both deadlines live on the original player so save/continue
-- and independent damage/controller Lua states observe the same transition.
local W={}
local root="mods/noita_hideout/files/"
local ew=NHEW or dofile(root.."ew.lua")
local armed="nh_rewind_armed"
local recordTag="nh_rewind_snapshot"
local onHit="nh_rewind_on_hit"
local guarding="nh_rewind_guarding"
local clockKey="nh_rewind.clock"
local inventory
local seenPlayer,seenProfile,seenRun,hasRecord
local function remember(state,player,present)
    seenPlayer,seenProfile,seenRun,hasRecord=player,state.profile,state.runSerial,present
end
local function loadout()
    if not inventory then inventory=dofile(root.."rewind_loadout.lua") end
    return inventory
end
local function record(player)
    return EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",recordTag)
end
local function healthMode()
    return ew.enabled() and GlobalsGetValue("nh_ew.rewind_health","") or "local_health"
end
local function run(state)
    return tostring(state.profile).."/"..tostring(state.runSerial).."/"
end
local function issuer()
    if ew.enabled() then return ew.issuer() end
    return "solo"
end
local function recordedIssuer(token)
    return token:match("^[^/]+/[^/]+/(%w+)/%d+$")
end
local function clearClock()
    if GlobalsGetValue(clockKey,"")~="" then GlobalsSetValue(clockKey,"") end
    if GlobalsGetValue("nh_rewind.return","")~="" then GlobalsSetValue("nh_rewind.return","") end
end

-- Before 0.42.43 an armed watch could own extra-life suspensions and a death
-- hook. Release only its markers; the rescue module keeps its normal policy.
local function releaseLegacy(state,player)
    local owners={player}
    for _,child in ipairs(EntityGetAllChildren(player) or {}) do owners[#owners+1]=child end
    for _,owner in ipairs(owners) do
        for _,kind in ipairs({"GameEffectComponent","UIIconComponent"}) do
            for _,c in ipairs(EntityGetComponentIncludingDisabled(owner,kind,"nh_rewind_native_life") or {}) do
                ComponentRemoveTag(c,"nh_rewind_native_life")
            end
        end
    end
    local hook=EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_rewind_ew_priority")
    if hook then EntityRemoveComponent(player,hook) end
    local meter=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_rescue")
    if meter then ComponentRemoveTag(meter,"nh_rewind_rescue") end
    local rescue=dofile(root.."rescue.lua")
    if ew.enabled() then rescue.lifePriority(player,false) end
    rescue.arm(state,player)
    clearClock()
end

function W.remaining(player)
    if not player or not EntityHasTag(player,armed) then return 0 end
    local snap=record(player)
    return snap and math.max(0,ComponentGetValue2(snap,"value_int")-GameGetFrameNum()) or 0
end

function W.start(state,player,pay)
    local mode=healthMode()
    if mode=="shared_health" then return false,"Shared health cannot be rewound." end
    if mode~="local_health" or not ew.localBody(player) or (ew.enabled() and not ew.ready())
        or EntityHasTag(player,"polymorphed_player") then return false,"Rewind unavailable." end
    if record(player) then return false,"Rewind already active." end
    local pending=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_rescue")
    if pending and ComponentGetValue2(pending,"value_string")~="" then return false,"Rewind unavailable." end
    local now=GameGetFrameNum()
    local owner=issuer()
    if not owner then return false,"Rewind unavailable." end
    local token=run(state)..owner.."/"..tostring(now)
    if GlobalsGetValue("nh_rewind.last","")==token then return false,"Rewind already active." end
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    local x,y=EntityGetTransform(player)
    if not dm or ComponentGetValue2(dm,"hp")<=0 or not x or not y then return false,"Rewind unavailable." end
    local snap=EntityAddComponent2(player,"VariableStorageComponent",{_tags=recordTag,name=token,
        value_int=now+3600,value_string=("%.12g:%.12g"):format(x,y),value_bool=false})
    if not snap or snap==0 then return false,"Rewind unavailable." end
    if not loadout().capture(state,player,token) or (pay and not pay()) then
        loadout().cancel(player,token)
        EntityRemoveComponent(player,snap)
        return false,"Rewind unavailable."
    end
    ComponentAddTag(snap,onHit)
    GlobalsSetValue("nh_rewind.last",token)
    EntityAddTag(player,armed)
    remember(state,player,true)
    return true
end

-- Called before HP, shield absorption and death handling. The very first
-- hit latches the guard before any cosmetics or subsequent pellet callbacks.
function W.blockHit(player,damage)
    if damage<=0 or not ew.localBody(player) or healthMode()~="local_health" then return false end
    local snap=record(player)
    if not snap or not ComponentHasTag(snap,onHit) or ComponentGetValue2(snap,"value_bool") then return false end
    local token=ComponentGetValue2(snap,"name")
    if recordedIssuer(token)~=issuer() then return false end
    local now,deadline=GameGetFrameNum(),ComponentGetValue2(snap,"value_int")
    if ComponentHasTag(snap,guarding) then return now<=deadline end
    if now>=deadline then return false end
    ComponentSetValue2(snap,"value_int",now+300)
    ComponentAddTag(snap,guarding)
    GlobalsSetValue(clockKey,token.."|"..(now+300))
    local x,y=EntityGetTransform(player)
    EntityLoad(root.."rewind_watch_echo.xml",x,y)
    GamePlaySound("data/audio/Desktop/projectiles.bank","player_projectiles/kantele/a/create",x,y)
    return true
end

local function move(player,x,y)
    EntitySetTransform(player,x,y)
    local motion=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
    if motion then ComponentSetValue2(motion,"mVelocity",0,0) end
end
local function loaded(x,y)
    return DoesWorldExistAt(math.floor(x)-4,math.floor(y)-7,math.ceil(x)+4,math.ceil(y)+2)
end
local function clear(x,y)
    for dy=-6,2,2 do
        if RaytracePlatforms(x-3,y+dy,x+3,y+dy) then return false end
    end
    return true
end
local offsets={{0,-1},{-1,0},{1,0},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}
local function landing(x,y,fromX,fromY)
    if clear(x,y) then return x,y end
    for radius=8,96,8 do
        for _,offset in ipairs(offsets) do
            local tx,ty=x+radius*offset[1],y+radius*offset[2]
            if loaded(tx,ty) and clear(tx,ty) then return tx,ty end
        end
    end
    return fromX,fromY
end

local function flash(player,snap)
    local sx,sy=ComponentGetValue2(snap,"value_string"):match("^([^:]+):([^:]+)$")
    local x,y=tonumber(sx),tonumber(sy)
    local fx,fy=EntityGetTransform(player)
    ComponentSetValue2(snap,"value_bool",true)
    EntityRemoveTag(player,armed)
    clearClock()
    EntityLoad(root.."rewind_watch_echo.xml",fx,fy)
    if loaded(x,y) then x,y=landing(x,y,fx,fy)
    else
        -- The player streams the destination. Resume the landing check from
        -- the saved pair of positions if a save happens between these frames.
        ComponentSetValue2(snap,"value_string",("%.12g:%.12g:%.12g:%.12g"):format(x,y,fx,fy))
        ComponentSetValue2(snap,"value_int",GameGetFrameNum()+120)
        ComponentAddTag(snap,"nh_rewind_landing")
        local grace=EntityLoad(root.."travel/transit_protection.xml",fx,fy)
        if grace and grace~=0 then EntityAddChild(player,grace) end
    end
    move(player,x,y)
    EntityLoad(root.."rewind_watch_echo.xml",x,y)
    GamePlaySound("data/audio/Desktop/misc.bank","misc/teleport_use",x,y)
end

local function finishLanding(player,snap)
    local x,y,fx,fy=ComponentGetValue2(snap,"value_string"):match("^([^:]+):([^:]+):([^:]+):([^:]+)$")
    x,y,fx,fy=tonumber(x),tonumber(y),tonumber(fx),tonumber(fy)
    local px,py=EntityGetTransform(player)
    if math.abs(px-x)<=12 and math.abs(py-y)<=12 then
        if loaded(x,y) then
            local tx,ty=landing(x,y,fx,fy)
            if tx~=x or ty~=y then move(player,tx,ty) end
        elseif GameGetFrameNum()<ComponentGetValue2(snap,"value_int") then return false
        else
            -- Return to the last known occupied point even when it has
            -- streamed out in the meantime; moving there streams it back.
            move(player,fx,fy)
        end
    end
    ComponentRemoveTag(snap,"nh_rewind_landing")
    return true
end

local function cancel(state,player,snap,token)
    EntityRemoveTag(player,armed)
    clearClock()
    loadout().cancel(player,token)
    EntityRemoveComponent(player,snap)
    remember(state,player,false)
end

function W.update(state,player,commit)
    if not player or (seenPlayer==player and seenProfile==state.profile and seenRun==state.runSerial and hasRecord==false) then return end
    if not ew.localBody(player) then return end
    local snap=record(player)
    if not snap then
        clearClock()
        remember(state,player,false)
        return
    end
    local token=ComponentGetValue2(snap,"name")
    if not ComponentHasTag(snap,onHit) then
        releaseLegacy(state,player)
        if not ComponentGetValue2(snap,"value_bool") then return cancel(state,player,snap,token) end
        -- An older return may already have teleported but still owe ammo.
        ComponentAddTag(snap,onHit)
    end
    local mode=healthMode()
    if token:sub(1,#run(state))~=run(state) or mode=="shared_health" then return cancel(state,player,snap,token) end
    if mode~="local_health" then return end
    local owner=recordedIssuer(token)
    if owner then
        local current=issuer()
        if not current then return end
        if owner~=current then return cancel(state,player,snap,token) end
    end
    if not ComponentGetValue2(snap,"value_bool") then
        if GameGetFrameNum()<ComponentGetValue2(snap,"value_int") then return end
        if not ComponentHasTag(snap,guarding) then return cancel(state,player,snap,token) end
        flash(player,snap)
    end
    if ComponentHasTag(snap,"nh_rewind_landing") and not finishLanding(player,snap) then return end
    if loadout().restore(state,player,token,commit) then
        EntityRemoveComponent(player,snap)
        remember(state,player,false)
    end
end

-- A temporary body may replace the original during the five-second guard.
-- Give it only the remaining protection. Ending its native transformation at
-- the deadline lets the original body's record finish the return normally.
function W.polymorph(body,state)
    local stamp=GlobalsGetValue(clockKey,"")
    if stamp=="" or not ew.localBody(body) or healthMode()~="local_health" then return false end
    local token,deadline=stamp:match("^([^|]+)|(%d+)$")
    if state and (token or stamp):sub(1,#run(state))~=run(state) then return false end
    if token and recordedIssuer(token)~=issuer() then return false end
    local effect
    for _,kind in ipairs({"POLYMORPH","POLYMORPH_RANDOM","POLYMORPH_UNSTABLE","POLYMORPH_CESSATION"}) do
        local candidate=GameGetGameEffect(body,kind)
        if candidate and candidate~=0 then effect=candidate; break end
    end
    if not effect then return false end
    local remaining=(tonumber(deadline) or 0)-GameGetFrameNum()
    if remaining<=0 then
        -- Legacy activations also take this path once on a save made as a
        -- polymorph. Let the original body release its old suspended lives.
        ComponentSetValue2(effect,"frames",1)
    elseif not (EntityGetAllChildren(body,"nh_rewind_morph_guard") or {})[1] then
        local x,y=EntityGetTransform(body)
        local grace=EntityLoad(root.."travel/transit_protection.xml",x,y)
        if grace and grace~=0 then
            local protection=EntityGetFirstComponentIncludingDisabled(grace,"GameEffectComponent")
            local lifetime=EntityGetFirstComponentIncludingDisabled(grace,"LifetimeComponent")
            ComponentSetValue2(protection,"frames",remaining)
            ComponentSetValue2(lifetime,"lifetime",remaining+1)
            EntityAddTag(grace,"nh_rewind_morph_guard")
            EntityAddChild(body,grace)
        end
    end
    return true
end
return W
