-- A reliable room grant chooses the one peer with loaded chunks that may
-- stamp terrain. Every visitor still needs a local backdrop and console.
local M={}
local function get(k) return GlobalsGetValue("nh_ew."..k,"") end
local function put(k,v) GlobalsSetValue("nh_ew."..k,v) end
local missingKey,firstMissing,nextProbe,probeMode,notified

-- A late visitor may load an empty sky chunk after the proxy restarts. A
-- damaged floor is not evidence of that: inspect every row, and leave any
-- loose objects, other players and player-built structures undisturbed.
local function emptySite(cabin,player)
    local right=cabin.left+cabin.width-1
    for y=cabin.top,cabin.bottom-1 do
        if Raytrace(cabin.left,y,right,y) then return false end
    end
    local mx,my=cabin.left+cabin.width/2,cabin.top+cabin.height/2
    local radius=math.sqrt(cabin.width^2+cabin.height^2)/2+1
    for _,entity in ipairs(EntityGetInRadius(mx,my,radius) or {}) do
        if EntityGetRootEntity(entity)~=player then
            local x,y=EntityGetTransform(entity)
            if x>=cabin.left and x<=right and y>=cabin.top and y<cabin.bottom then return false end
        end
    end
    return true
end

function M.schedule(key,round)
    local value=key.."|"..tostring(round)
    if GameHasFlagRun("ew_flag_this_is_host") and get("ship_repair")~=value then put("ship_repair",value) end
end

function M.ensure(key,cabin,player,read,write,moveSafe,makeConsole)
    local marker,round,mode,token=get("ship_state"):match("^([^|]+)|([^|]+)|(%a+)|(%d+)$")
    if marker~=key or not DoesWorldExistAt(cabin.left,cabin.top,cabin.left+cabin.width-1,cabin.bottom-1) then return false end
    local built=read("built")==cabin.revision
    if built and read("repaired_round")==round and mode=="done" then return makeConsole() end
    local frame=GameGetFrameNum()
    local function request(action)
        local value=table.concat({key,round,action,token},"|")
        if get("ship_request")~=value then put("ship_request",value) end
        if action~="ack" then put("ship_touch",tostring(frame)) end
    end
    if mode=="wait" then request("ask"); return false end
    if mode~="build" and mode~="copy" and mode~="done" then return false end
    local bx,by=cabin.point(cabin.infirmary)
    local cx,cy=cabin.point(cabin.terminal)
    local floor=RaytracePlatforms(bx,by,bx,by+24) and RaytracePlatforms(cx,cy-8,cx,cy+5)
    local stamp=read("ew_stamped")
    if not floor and (mode=="done" or mode=="copy") then
        if built or stamp==round then return false end
        local ref=key.."|"..round
        if missingKey~=ref or frame<firstMissing then
            missingKey,firstMissing,nextProbe,probeMode,notified=ref,frame,frame+45,mode,false
        end
        if frame<nextProbe and mode==probeMode then return false end
        nextProbe,probeMode=frame+30,mode
        if not emptySite(cabin,player) then
            if not notified then GamePrint(GameTextGetTranslatedOrNot("$nh_travel_ew_occupied")); notified=true end
            return false
        end
        if mode=="done" then request("copy"); return false end
    end
    if (mode=="build" or (mode=="copy" and not floor)) and stamp~=round then
        -- Adopt an existing cabin on first contact. Later host storm rounds
        -- repair even an intact floor because other walls may be damaged.
        if not floor or round~="-" then
            if cabin.wouldEmbed(EntityGetTransform(player)) then moveSafe(player,bx,by) end
            RemovePixelSceneBackgroundSprite(cabin.background,cabin.left,cabin.top)
            LoadPixelScene(cabin.material,cabin.background,cabin.left,cabin.top,cabin.background,true,true,{},50,true)
            write("ew_stamped",round)
            return false
        end
    end
    if not floor then return false end
    missingKey=nil
    if not built and stamp~=round then
        RemovePixelSceneBackgroundSprite(cabin.background,cabin.left,cabin.top)
        LoadBackgroundSprite(cabin.background,cabin.left,cabin.top,50,true)
    end
    if not makeConsole() then return false end
    write("built",cabin.revision)
    write("repaired_round",round)
    if mode=="build" or mode=="copy" then request("ack") end
    return true
end
return M
