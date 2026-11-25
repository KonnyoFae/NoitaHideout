local M={radius=2048,ship={width=160,height=172,anchorX=20,groundY=168,
    boxes={{x=133,y=74,file="ship_safe"},{x=55,y=74,file="ship_cache"}},
    parts={{0,0,159,85},{0,86,49,171}}}}
M.steelFleet={width=512,height=496,anchorX=28,groundY=492,
    -- Slot order is persisted in the claim mask. Append new slots at the end.
    boxes={{x=384,y=157,file="ship_safe_lv3"},{x=182,y=233,file="ship_cache"},
        {x=273,y=233,file="ship_safe_lv1"},{x=86,y=179,file="ship_safe"},
        {x=404,y=48,file="ship_safe"}},
    -- Gas decks, bridge, lower gun deck, upper escort, lower escort and anchor.
    parts={{0,0,501,103},{62,104,409,188},{74,189,316,239},
        {140,253,299,337},{8,324,167,409},{14,410,57,436},{14,437,38,465},{16,466,40,495}}}
for _,ship in ipairs({M.ship,M.steelFleet}) do
    ship.empty=2^#ship.boxes-1
    ship.retiring=ship.empty+1
end
local prefix="cycle_storm.sites."
local keys={rig="rig_locations",well="well_locations",ship="ship_locations"}
local scanKey=prefix.."scan_until"

-- Oil and gas records store their expiry (-1 for idle rigs). Ship records
-- retain their ground anchor until the hull and its fixtures have been removed.
function M.each(kind,visit)
    for x,y,value,suffix in GlobalsGetValue(prefix..keys[kind],""):gmatch("(-?%d+),(-?%d+),(-?%d+)(:?[%w_]*)") do
        local state=tonumber(value)
        local layout,refit
        if suffix==":steel" or suffix==":steel_v2" or suffix==":steel_pending" then
            layout="steel"
            refit=suffix==":steel_pending"
            if suffix==":steel" then
                -- The two-box fleet used 3 for cleared and 4 for retiring.
                if state==3 then state=M.steelFleet.empty
                elseif state==4 then state=M.steelFleet.retiring
                else refit=true end
            end
        end
        visit(tonumber(x),tonumber(y),state,layout,refit)
    end
end

function M.shipState(x,y)
    local result
    M.each("ship",function(sx,sy,state)
        if sx==x and sy==y then result=state end
    end)
    return result
end

function M.setShip(x,y,newState,layout)
    local entries,found={},false
    local function append(sx,sy,state,kind,refit)
        local suffix=kind=="steel" and (refit and state<M.steelFleet.empty and ":steel_pending" or ":steel_v2") or ""
        entries[#entries+1]=string.format("%d,%d,%d%s",sx,sy,state,suffix)
    end
    M.each("ship",function(sx,sy,state,kind,refit)
        if sx==x and sy==y then
            found=true
            state=newState
            if layout then kind,refit=layout,false end
        end
        if state~=nil then append(sx,sy,state,kind,refit) end
    end)
    if not found and newState~=nil then append(x,y,newState,layout,false) end
    GlobalsSetValue(prefix..keys.ship,table.concat(entries,";"))
end

function M.shipOverlaps(left,top,right,bottom)
    local overlap=false
    M.each("ship",function(x,y,_,layout)
        local ship=layout=="steel" and M.steelFleet or M.ship
        local sx,sy=x-ship.anchorX,y-ship.groundY
        if left<sx+ship.width and right>sx and top<sy+ship.height and bottom>sy then overlap=true end
    end)
    return overlap
end

function M.nearShipStructure(x,y,px,py,layout)
    local ship=layout=="steel" and M.steelFleet or M.ship
    local lx,ly=px-x+ship.anchorX,py-y+ship.groundY
    local margin=32
    for _,part in ipairs(ship.parts) do
        if lx>=part[1]-margin and lx<=part[3]+1+margin
            and ly>=part[2]-margin and ly<=part[4]+1+margin then return true end
    end
    return false
end

function M.nearby(px,py,frame)
    local matches={}
    for _,kind in ipairs({"ship","well","rig"}) do
        local nearest
        local count=0
        M.each(kind,function(x,y,value,layout)
            local usable
            if kind=="ship" then
                usable=value<(layout=="steel" and M.steelFleet or M.ship).empty
            else
                usable=value<0 or value>frame
            end
            local d=(x-px)^2+(y-py)^2
            if usable and d<=M.radius^2 then
                count=count+1
                if not nearest or d<nearest.d then nearest={kind=kind,x=x,y=y,d=d} end
            end
        end)
        if nearest then
            nearest.count=count
            matches[#matches+1]=nearest
        end
    end
    return matches
end

function M.remaining(frame)
    return math.max(0,(tonumber(GlobalsGetValue(scanKey,"0")) or 0)-frame)
end

function M.active(frame)
    return M.remaining(frame)>0
end

function M.scan(player,pay,report)
    local frame=GameGetFrameNum()
    if M.active(frame) then report("Radar already active."); return end
    local x,y=EntityGetTransform(player)
    if #M.nearby(x,y,frame)==0 then
        GamePrint(GameTextGetTranslatedOrNot("$nh_storm_scan_empty"))
    elseif pay() then
        GlobalsSetValue(scanKey,tostring(frame+600))
    end
end

return M
