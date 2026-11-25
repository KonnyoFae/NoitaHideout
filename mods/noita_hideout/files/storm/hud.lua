local gui
local bars = dofile("mods/noita_hideout/files/world_status_bar.lua")
local mouse_x, mouse_y

local function aiming_at(x, y, width, height)
    return mouse_x >= x and mouse_x <= x + width and mouse_y >= y and mouse_y <= y + height
end

local function clock(seconds)
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function rect(id, x, y, width, height, r, g, b, alpha, z)
    bars.rect(gui,id,x,y,width,height,r,g,b,alpha,z)
end

local function station_bar(id, x, y, width, height, label, fill, r, g, b)
    local bar = math.max(32, width)
    if aiming_at(x - bar/2 - 2, y - height - 7, bar + 4, height + 8) then return end
    bars.draw(gui,id,x,y,bar,label,width,height,fill,r,g,b)
end

local function draw_sites(stations, sw, sh, chinese, left, top, width, height)
    local rigs = EntityGetWithTag("cycle_storm_rig") or {}
    local wells = EntityGetWithTag("cycle_storm_well") or {}
    if #rigs == 0 and #wells == 0 then return end
    local frame = GameGetFrameNum()
    for i, rig in ipairs(rigs) do
        local rx, ry = EntityGetTransform(rig)
        local x = (rx - left) * sw / width
        local y = (ry - 28 - top) * sh / height
        if x >= 0 and x <= sw and y >= 0 and y <= sh then
            local active, fill, seconds, count = stations.rigProgress(rig, frame)
            local label = chinese and "待启动" or "Idle"
            if active then
                label = string.format(chinese and "钻探中 %ds · 已出%d罐" or "Drilling %ds · %d out", seconds, count)
            end
            local tw, th = GuiGetTextDimensions(gui, label, 0.8)
            station_bar(100 + i * 3, x, y, tw, th, label, fill, 0.94, 0.39, 0.25)
        end
    end
    for i, well in ipairs(wells) do
        local wx, wy = EntityGetTransform(well)
        local x = (wx - left) * sw / width
        if x >= 0 and x <= sw and wy >= top then
            local fill, seconds, tower_height = stations.wellProgress(well, frame)
            if fill and fill > 0 and wy - tower_height < top + height then
                local label = (chinese and "气塔剩余 " or "Gas tower · ") .. clock(seconds)
                local tw, th = GuiGetTextDimensions(gui, label, 0.8)
                -- From the base of the tower its roof can be above the camera.
                local y = math.max(th + 8, (wy - tower_height - 3 - top) * sh / height)
                local margin = math.max(32, tw)/2 + 2
                x = math.max(margin, math.min(sw-margin, x))
                station_bar(100 + (#rigs + i) * 3, x, y, tw, th, label, fill, 0.38, 0.76, 1)
            end
        end
    end
end

local bearings={
    {"右","E"},{"右下","SE"},{"下","S"},{"左下","SW"},
    {"左","W"},{"左上","NW"},{"上","N"},{"右上","NE"},
}
local site_names={ship={"飞艇","Airship"},well={"气塔","Gas tower"},rig={"油钻","Oil rig"}}
local scan_rows,next_scan={},0
local function draw_scan(locations,sw,y,chinese)
    local frame=GameGetFrameNum()
    if not locations.active(frame) then next_scan=0; return end
    local player=(EntityGetWithTag("player_unit") or {})[1]
    if not player then return end
    local px,py=EntityGetTransform(player)
    if frame>=next_scan or frame<next_scan-15 then
        scan_rows=locations.nearby(px,py,frame)
        next_scan=frame+15
    end
    local lang=chinese and 1 or 2
    for i,site in ipairs(scan_rows) do
        local dx,dy=site.x-px,site.y-py
        local bearing=bearings[math.floor(math.atan2(dy,dx)*4/math.pi+0.5)%8+1][lang]
        local distance=math.floor(math.sqrt(dx*dx+dy*dy)+0.5)
        local name=site_names[site.kind][lang]
        if site.count and site.count>1 then name=name.." ×"..site.count end
        local label=string.format("%s  %s  %d px",name,bearing,distance)
        local w,h=GuiGetTextDimensions(gui,label)
        local ty=y-i*(h+3)
        if not aiming_at(sw-w-14,ty-1,w+7,h+2) then
            rect(60+i,sw-w-14,ty-1,w+7,h+2,0.06,0.09,0.13,0.88,2)
            GuiColorSetForNextWidget(gui,1,0.84,0.49,1)
            GuiText(gui,sw-w-10,ty,label)
        end
    end
end

local icon_sizes={}
local function effect_icon(id,x,y,size,path)
    local zoom=icon_sizes[path]
    if not zoom then
        local w,h=GuiGetImageDimensions(gui,path)
        if not w or not h or w<=0 or h<=0 then return end
        local longest=math.max(w,h)
        zoom={w=w/longest,h=h/longest,scale=1/longest}
        icon_sizes[path]=zoom
    end
    GuiImage(gui,id,x+(1-zoom.w)*size/2,y+(1-zoom.h)*size/2,path,1,size*zoom.scale)
end

local function station_label(x,y,label,scale,lit,gas)
    if lit and gas then GuiColorSetForNextWidget(gui,0.38,0.76,1,1)
    elseif lit then GuiColorSetForNextWidget(gui,1,0.43,0.37,1)
    else GuiColorSetForNextWidget(gui,0.58,0.60,0.62,1) end
    GuiText(gui,x,y,label,scale)
end

local function hint(text,sw,sh,panelY)
    local w,h=GuiGetTextDimensions(gui,text)
    local scale=math.min(0.85,(sw-12)/math.max(w,1))
    w,h=w*scale,h*scale
    local x=math.max(4,math.min(sw-w-4,mouse_x-w/2))
    local y=panelY-h-6
    if y<2 then y=math.min(sh-h-2,mouse_y+h+4) end
    rect(45,x-2,y-1,w+4,h+2,0.06,0.09,0.13,0.94,-3)
    GuiZSetForNextWidget(gui,-4)
    GuiText(gui,x,y,text,scale)
end

local timer_rows={}
local function measure_timers(effects,fps,locale)
    local count,widest=0,0
    if not effects then return 0,9 end
    for _,effect in ipairs(effects) do
        if effect.frames>0 then
            count=count+1
            local row=timer_rows[count] or {}
            timer_rows[count]=row
            local seconds=math.ceil(effect.frames/fps)
            if row.seconds~=seconds or row.locale~=locale then
                row.seconds,row.time,row.locale=seconds,clock(seconds),locale
                -- The localized fallback font can paint wider digits than the
                -- scaled measurement reports. Reserve one full digit cell per glyph.
                row.width=math.max(GuiGetTextDimensions(gui,row.time),5*#row.time)
            end
            row.icon,row.label=effect.icon,effect.label
            widest=math.max(widest,row.width)
        end
    end
    return count,8+1+widest
end

return function(weather, current, elapsed, age, stations, locations, effects)
    if not gui then
        dofile_once("data/scripts/lib/utilities.lua")
        gui = GuiCreate()
    end
    GuiStartFrame(gui)
    GuiOptionsAdd(gui, GUI_OPTION.NonInteractive)
    GuiOptionsAdd(gui, GUI_OPTION.NoPositionTween)
    local sw, sh = GuiGetScreenDimensions(gui)
    local left, top, cw, ch = GameGetCameraBounds()
    if cw <= 0 or ch <= 0 then return end
    local wx, wy = DEBUG_GetMouseWorld()
    mouse_x, mouse_y = (wx - left) * sw / cw, (wy - top) * sh / ch
    local language = GameTextGet("$current_language")
    local chinese = language == "完全汉化" or language:find("中文", 1, true) ~= nil
    if stations then draw_sites(stations, sw, sh, chinese, left, top, cw, ch) end
    local locale = chinese and "zh" or "en"
    local stage=weather.phases[current]
    elapsed=math.max(0,math.min(stage.frames,elapsed))
    local countdown=clock(math.ceil((stage.frames-elapsed)/weather.fps))
    local status=stage[locale].."  "..(chinese and ("剩余 "..countdown) or (countdown.." left"))
    local progress=clock(math.floor(age/weather.fps)).." / "..clock(weather.frames/weather.fps)
    local wellLabel=chinese and "[气塔]" or "[Gas tower]"
    local rigLabel=chinese and "[油钻]" or "[Oil rig]"
    local statusW=GuiGetTextDimensions(gui,status)
    local progressW=GuiGetTextDimensions(gui,progress)
    local wellW=GuiGetTextDimensions(gui,wellLabel)
    local rigW=GuiGetTextDimensions(gui,rigLabel)
    local space=GuiGetTextDimensions(gui,wellLabel.." "..rigLabel)-wellW-rigW
    local headerW=statusW+progressW+wellW+rigW+space+12
    local width=math.min(sw-16,math.max(chinese and 200 or 218,headerW))
    if width<=0 or sh<20 then return end
    local headerScale=math.min(1,width/headerW)
    local x=sw-width-8
    local rigX=x+width-rigW*headerScale
    local wellX=rigX-(wellW+space)*headerScale
    local progressX=x+statusW*headerScale+(wellX-x-(statusW+progressW)*headerScale)/2
    local wellPending,rigPending,wellRunning,rigRunning
    if stations then wellPending,rigPending,wellRunning,rigRunning=select(3,stations.available()) end

    local count,cellW=measure_timers(effects,weather.fps,locale)
    local columns=math.max(1,math.floor((width+4)/(cellW+4)))
    local rows=math.ceil(count/columns)
    local gridScale=1
    -- On short displays fit the entire list, retaining the input order.
    if rows>0 then
        gridScale=math.min(1,width/cellW,math.max(1,sh-35)/(rows*10))
        columns=math.max(1,math.floor((width/gridScale+4)/(cellW+4)))
        rows=math.ceil(count/columns)
    end
    local gridY=26
    local height=(rows>0 and gridY+rows*10*gridScale or 25)
    local y=sh-6-height
    if locations then draw_scan(locations,sw,y-4,chinese) end
    local hovered=aiming_at(x-3,y-2,width+6,height+4)
    local tip
    if hovered then
        if wellPending and aiming_at(wellX,y,wellW*headerScale,9*headerScale) then
            tip=chinese and "雪原待落地" or "Pending · Snow"
        elseif rigPending and aiming_at(rigX,y,rigW*headerScale,9*headerScale) then
            tip=chinese and "沙漠待落地" or "Pending · Desert"
        end
    else
        rect(1,x-3,y-2,width+6,height+4,0.06,0.09,0.13,0.82,5)
        GuiColorSetForNextWidget(gui,1,0.88,0.59,1)
        GuiText(gui,x,y,status,headerScale)
        GuiText(gui,progressX,y,progress,headerScale)
        local blink=GameGetFrameNum()%60<30
        station_label(wellX,y,wellLabel,headerScale,wellRunning and blink or not wellRunning and wellPending,true)
        station_label(rigX,y,rigLabel,headerScale,rigRunning and blink or not rigRunning and rigPending,false)

        local start_frame=0
        for i,phase in ipairs(weather.phases) do
            local begin=math.floor(width*start_frame/weather.frames)
            start_frame=start_frame+phase.frames
            local span=math.floor(width*start_frame/weather.frames)-begin-1
            if span>0 then
                rect(10+i,x+begin,y+11,span,2,0.44,0.54,0.65,0.75,1)
                local fill=i<current and span or i==current and math.max(1,math.floor(span*elapsed/phase.frames)) or 0
                if fill>0 then rect(20+i,x+begin,y+11,fill,2,1,0.79,0.39,1,0) end
                local name=phase[locale]
                local labelW=GuiGetTextDimensions(gui,name)
                local scale=math.min(0.8,span/math.max(1,labelW))
                if i==current then GuiColorSetForNextWidget(gui,1,0.88,0.59,1)
                else GuiColorSetForNextWidget(gui,0.77,0.81,0.86,1) end
                GuiText(gui,x+begin+(span-labelW*scale)/2,y+14,name,scale)
            end
        end
    end
    for i=1,count do
        local effect=timer_rows[i]
        local cellX=x+(i-1)%columns*(cellW+4)*gridScale
        local cellY=y+gridY+math.floor((i-1)/columns)*10*gridScale
        if not hovered then
            effect_icon(10000+i,cellX,cellY,8*gridScale,effect.icon)
            GuiColorSetForNextWidget(gui,1,0.88,0.59,1)
            GuiText(gui,cellX+9*gridScale,cellY,effect.time,0.8*gridScale)
        elseif effect.label and aiming_at(cellX,cellY,cellW*gridScale,8*gridScale) then
            tip=effect.label
        end
    end
    -- The panel yields to the reticle; an optional hint sits outside its bounds.
    if tip then hint(tip,sw,sh,y) end
end
