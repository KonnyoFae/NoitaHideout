local root="mods/noita_hideout/files/travel/"
local cabin=dofile(root.."cabin.lua")
local routes=dofile(root.."routes.lua")
local landmarks=dofile("mods/noita_hideout/files/terminals/landmarks.lua")
local access=dofile("mods/noita_hideout/files/terminals/access.lua")
local N={}
local prefix,cycle,checkedFrame="nh_travel.",nil,nil
local repairRound,repairedRound="",""
local function read(key) return GlobalsGetValue(prefix..key,"") end
local function write(key,value) GlobalsSetValue(prefix..key,value) end
local function say(key) GamePrint(GameTextGetTranslatedOrNot("$nh_travel_"..key)) end
local function near(x,y,tx,ty,r) return (x-tx)^2+(y-ty)^2<=r*r end
local function here(x,y,r,tag) return (EntityGetInRadiusWithTag(x,y,r,tag) or {})[1] end
local function coords(x,y) return ("%d,%d"):format(math.floor(x),math.floor(y)) end
local terminalX,terminalY=cabin.point(cabin.terminal)
local infirmaryX,infirmaryY=cabin.point(cabin.infirmary)
-- Coordinates and steel masks of previously shipped cabins.
local formerCabins={
    ["1"]={left=164,top=-26480,w=192,h=80,consoleX=264,consoleY=-26413,gate="318,-26424",mask="prototype_clear.png"},
    ["2"]={left=10,top=-26756,w=500,h=356,consoleX=192,consoleY=-26549,gate="309,-26560",mask="three_deck_clear.png"},
}
local function inFormerCabin(x,y)
    local built,placing=read("built"),read("placing"):match("^([^,]+),")
    for revision,c in pairs(formerCabins) do
        if (revision==built or revision==placing) and x>=c.left and x<c.left+c.w
            and y>=c.top and y<c.top+c.h then return true end
    end
    return false
end
local menu,held,startHold,latched,hint,lastMountain,lastLandmark
local returnKeys={["10"]="G",["11"]="H",["13"]="J"}
local function returnKey()
    local key=tostring(ModSettingGet("noita_hideout.return_key") or "10")
    if not returnKeys[key] then key="10" end
    return tonumber(key),returnKeys[key]
end
local function syncCycle(frame)
    if frame and frame==checkedFrame then return end
    checkedFrame=frame
    local ng=tonumber(SessionNumbersGetValue and SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) or 0
    if cycle==ng then return end
    if cycle~=nil then
        write("trip","")
        write("gate","")
        write("exit","")
    end
    cycle=ng
    menu,held,startHold,latched,hint,lastMountain,lastLandmark=nil,nil,nil,false,nil,nil,nil
    access.invalidateAccess()
    prefix=ng==0 and "nh_travel." or ("nh_travel.ng"..ng..".")
    repairRound,repairedRound=read("repair_round"),read("repaired_round")
    local gate=read("gate")
    local source,kind,rest=gate:match("^([^,]+,[^,]+),(%a+),(.+)$")
    if kind=="home" or kind=="mountain" then
        for _,c in pairs(formerCabins) do
            if source==c.gate then write("gate",coords(cabin.point(cabin.gate))..","..kind..","..rest); break end
        end
    end
    return true
end
function N.reset() cycle=nil; syncCycle() end
function N.scheduleRepair(round)
    syncCycle()
    local stamp=tostring(round)
    if stamp~=repairRound then
        repairRound=stamp
        write("repair_round",stamp)
    end
end
function N.inCabin(player,x,y)
    if not x then x,y=EntityGetTransform(player) end
    return cabin.inside(x,y) and read("built")==cabin.revision
end

function N.landmarkName(player,x,y)
    if not x then x,y=EntityGetTransform(player) end
    local id,site=landmarks.near(x,y)
    if id then return site.name end
end

local function register(id)
    local x,y=EntityGetTransform(id)
    local pos=coords(x,y)..";"
    local routes=read("stations")
    if not (";"..routes):find(";"..pos,1,true) then
        write("stations",routes..pos)
        say("unlocked")
    end
end

-- Check the head, shoulders and feet on both sides of a standing player.
local function landing(x,y)
    for _,dx in ipairs({0,10,-10,20,-20,32,-32}) do
        local sx=x+dx
        local hit,_,floor=RaytracePlatforms(sx,y-8,sx,y+48)
        if hit and floor then
            local clear=true
            for side=-4,4,2 do
                if RaytraceSurfacesAndLiquiform(sx+side,floor-20,sx+side,floor-1)
                    or not RaytracePlatforms(sx+side,floor-1,sx+side,floor+4) then clear=false; break end
            end
            if clear then return sx,floor-6 end
        end
    end
end

local function move(player,x,y)
    local motion=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
    if motion then ComponentSetValue2(motion,"mVelocity",0,0) end
    EntitySetTransform(player,x,y)
end
local function protect(player)
    if not (EntityGetAllChildren(player,"nh_transit_protection") or {})[1] then
        local x,y=EntityGetTransform(player)
        local e=EntityLoad(root.."transit_protection.xml",x,y)
        if e and e~=0 then EntityAddChild(player,e) end
    end
end

local function ensureCabin(player)
    local built=read("built")
    local restoring=built~=cabin.revision or repairRound~=repairedRound
    if restoring then
        if not DoesWorldExistAt(cabin.left,cabin.top,cabin.left+cabin.width-1,cabin.bottom-1) then return false end
        local frame=GameGetFrameNum()
        local revision,attempt=read("placing"):match("^([^,]+),(%d+)$")
        local age=attempt and frame-tonumber(attempt)
        if revision~=cabin.revision or age<0 or age>=120 then
            for version,c in pairs(formerCabins) do
                if (version==built or version==revision) and
                    not DoesWorldExistAt(c.left,c.top,c.left+c.w-1,c.top+c.h-1) then return false end
            end
            for version,c in pairs(formerCabins) do
                if version==built or version==revision then
                    RemovePixelSceneBackgroundSprite(cabin.background,c.left,c.top)
                    LoadPixelScene(root..c.mask,"",c.left,c.top,"",true,true,{},50,true)
                    for _,id in ipairs(EntityGetInRadiusWithTag(c.consoleX,c.consoleY,4,"nh_travel_console") or {}) do
                        EntityKill(id)
                    end
                end
            end
            if built==cabin.revision and cabin.wouldEmbed(EntityGetTransform(player)) then
                protect(player)
                move(player,infirmaryX,infirmaryY)
            end
            if revision==cabin.revision or built==cabin.revision then
                RemovePixelSceneBackgroundSprite(cabin.background,cabin.left,cabin.top)
            end
            LoadPixelScene(cabin.material,cabin.background,cabin.left,cabin.top,cabin.background,true,true,{},50,true)
            write("repairing_round",repairRound)
            write("placing",cabin.revision..","..frame)
            return false
        end
        if age==0 or not RaytracePlatforms(infirmaryX,infirmaryY,infirmaryX,infirmaryY+24)
            or not RaytracePlatforms(terminalX,terminalY-8,terminalX,terminalY+5) then return false end
    end
    if not DoesWorldExistAt(terminalX-8,terminalY-8,terminalX+8,terminalY+8) then return not restoring end
    local id=here(terminalX,terminalY,4,"nh_travel_console")
    if not id then id=EntityLoad(root.."console.xml",terminalX,terminalY) end
    if not id or id==0 then return false end
    if restoring then
        write("built",cabin.revision)
        access.invalidateAccess()
        write("placing","")
        repairedRound=read("repairing_round")
        write("repaired_round",repairedRound)
    end
    return true
end

local function begin(player,kind,x,y,bx,by)
    -- The player streams the destination. Save the return point before moving
    -- and hold still until the loaded material grid yields a standable floor.
    write("trip",table.concat({kind,coords(x,y),coords(bx,by),GameGetFrameNum()+240},","))
    menu=nil
    protect(player)
end
function N.rescue(player,hx,hy)
    syncCycle()
    write("gate","")
    begin(player,"rescue",infirmaryX,infirmaryY,hx,hy)
end

local function transit(player,data,frame)
    local kind,x,y,bx,by,deadline=data:match("^(%a+),(-?%d+),(-?%d+),(-?%d+),(-?%d+),(%d+)$")
    if not kind then write("trip",""); return end
    x,y,bx,by,deadline=tonumber(x),tonumber(y),tonumber(bx),tonumber(by),tonumber(deadline)
    -- A pending outbound trip from the previous version can still roll back.
    if (kind=="home" or kind=="mountain" or kind=="back") and inFormerCabin(bx,by) then
        bx,by=infirmaryX,infirmaryY
        if kind=="back" then x,y=bx,by end
    end
    local inbound=kind=="ship" or kind=="rescue" or kind=="refit"
        or (kind=="back" and x==infirmaryX and y==infirmaryY)
    if inbound then x,y=infirmaryX,infirmaryY end
    protect(player)
    local loaded=DoesWorldExistAt(x-70,y-35,x+70,y+56)
    if loaded and inbound then loaded=ensureCabin(player) end
    if loaded and kind=="mountain" then loaded=here(x,y,4,"noita_hideout_mountain_storage")~=nil end
    if loaded and kind=="landmark" then loaded=here(x,y,4,"nh_landmark_terminal")~=nil end
    if loaded then
        local tx,ty=x,y
        if kind=="home" then
            local terminal=here(x,y,128,"nh_home_terminal")
            if terminal then tx,ty=EntityGetTransform(terminal) end
        end
        if kind=="home" or kind=="mountain" or kind=="landmark" then tx=tx+12 end
        local sx,sy=landing(tx,ty)
        if sx then
            move(player,sx,sy)
            write("trip","")
            if kind~="back" and kind~="refit" then write("gate","") end
            return
        end
    end
    if frame>=deadline or (loaded and kind~="back") then
        if kind=="back" then
            -- Last resort is the original stand position or known spawn point.
            move(player,bx,by)
            write("trip","")
        else
            write("exit","1")
            begin(player,"back",bx,by,bx,by)
            say(kind=="rescue" and "rescue_fallback" or "blocked")
        end
        return
    end
    move(player,x,y)
end

local function syncGate(gx,gy)
    local found
    for _,id in ipairs(EntityGetWithTag("nh_travel_gate") or {}) do
        local x,y=EntityGetTransform(id)
        if gx and x==gx and y==gy and not found then found=id else EntityKill(id) end
    end
    if gx and not found and DoesWorldExistAt(gx-8,gy-8,gx+8,gy+8) then
        found=EntityLoad(root.."gate.xml",gx,gy)
    end
    return found and found~=0
end

local function openGate(gx,gy,kind,x,y,mustLeave)
    gx,gy=math.floor(gx),math.floor(gy)
    if not syncGate(gx,gy) then say("blocked"); return end
    write("gate",table.concat({coords(gx,gy),kind,coords(x,y)},","))
    write("exit",mustLeave and "1" or "")
    say("gate_ready")
end

local function atConsole(x,y)
    return near(x,y,terminalX,terminalY,36) and cabin.inside(x,y) and read("built")==cabin.revision
        and here(terminalX,terminalY,4,"nh_travel_console")~=nil
end

function N.choose(player,index)
    syncCycle()
    local row=menu and menu.rows[index]
    if not row or not GameIsInventoryOpen() or not atConsole(EntityGetTransform(player)) or read("trip")~="" then return end
    local gx,gy=cabin.point(cabin.gate)
    openGate(gx,gy,row.kind,row.x,row.y)
end

local function returnGate(player,terminal)
    local x,y=EntityGetTransform(player)
    local tx=EntityGetTransform(terminal)
    local side=x<tx and -1 or 1
    local gx,gy=landing(x+side*27,y)
    if not gx then gx,gy=landing(x-side*27,y) end
    if not gx then say("blocked"); return end
    openGate(gx,gy-3,"ship",infirmaryX,infirmaryY,near(x,y,gx,gy-3,12))
end

function N.update(player,hx,hy,blocked)
    local frame=GameGetFrameNum()
    local x,y=EntityGetTransform(player)
    -- Native NG+ can replace the world between updates. Check it on the
    -- maintenance tick and before acting on an outstanding trip or a gate.
    if cycle==nil or frame%15==0 then syncCycle(frame) end
    if frame%15==0 then
        landmarks.update(x,y,prefix)
        access.invalidateAccess()
    end
    hint=nil
    local trip=read("trip")
    if trip~="" then
        if syncCycle(frame) then return end
        transit(player,trip,frame)
        hint={transit=true}
        return
    end
    if frame%15==0 and (cabin.overlaps(x,y,x,y,240)
        or (frame%60==0 and repairRound~=repairedRound and read("built")==cabin.revision)) then
        if inFormerCabin(x,y) then
            begin(player,"refit",infirmaryX,infirmaryY,hx,hy)
            return
        end
        ensureCabin(player)
        x,y=EntityGetTransform(player)
    end
    local data=read("gate")
    local gx,gy,kind,tx,ty=data:match("^(-?%d+),(-?%d+),(%a+),(-?%d+),(-?%d+)$")
    gx,gy=tonumber(gx),tonumber(gy)
    if frame%15==0 then syncGate(gx,gy) end
    if gx then
        if not near(x,y,gx,gy,12) then
            if read("exit")=="1" then write("exit","") end
        elseif not blocked and read("exit")=="" and here(gx,gy,2,"nh_travel_gate") then
            if syncCycle(frame) then return end
            begin(player,kind,tonumber(tx),tonumber(ty),x,y)
            return
        end
    end
    local mountain=here(x,y,48,"noita_hideout_mountain_storage")
    if mountain~=lastMountain then
        if mountain then
            syncCycle(frame)
            register(mountain)
        end
        lastMountain=mountain
    end
    local landmark,site,world=landmarks.near(x,y)
    if landmark~=lastLandmark then
        if landmark then
            syncCycle(frame)
            if landmarks.unlock(prefix,site,world) then say(site.key.."_unlocked") end
        end
        lastLandmark=landmark
    end
    if hx and hy and atConsole(x,y) then
        if not menu then menu=routes.collect(read("stations"),hx,hy,landmarks.unlocked(prefix)) end
        menu.gateKind,menu.gateX,menu.gateY=kind,tonumber(tx),tonumber(ty)
        held,startHold,latched=nil,nil,false
        return
    end
    menu=nil
    if blocked then held,startHold=nil,nil; return end
    local terminal=mountain or landmark or here(x,y,48,"nh_home_terminal") or here(x,y,48,"nh_remote_station")
    if not terminal then held,startHold,latched=nil,nil,false; return end
    local key,label=returnKey()
    hint={key=label}
    local down=InputIsKeyDown(key) and not InputIsKeyDown(224)
    if not down then latched=false end
    if not down or latched then held,startHold=nil,nil; return end
    if held~=terminal then held,startHold=terminal,frame end
    hint.percent=math.min(100,math.floor((frame-startHold)*100/36))
    if frame-startHold>=36 then
        if syncCycle(frame) then return end
        latched=true
        returnGate(player,terminal)
    end
end
function N.view() return menu or hint end
return N
