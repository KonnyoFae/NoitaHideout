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

return function(weather, current, elapsed, age, stations, locations)
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
    local width = math.min(sw - 16, chinese and 158 or 186)
    local well,rig,wellPending,rigPending
    if stations then well,rig,wellPending,rigPending=stations.available() end
    local extra=(wellPending or rigPending) and 10 or 0
    local x, y = sw - width - 8, sh - 45 - extra
    if locations then draw_scan(locations,sw,y-3,chinese) end
    -- Even a scaled GuiImage can cover the reticle. Leave the aimed area free of widgets.
    if aiming_at(x - 3, y - 2, width + 6, 41 + extra) then return end
    rect(1, x - 3, y - 2, width + 6, 41+extra, 0.06, 0.09, 0.13, 0.82, 5)

    local stage = weather.phases[current]
    local remaining = math.ceil((stage.frames - elapsed) / weather.fps)
    local countdown = clock(remaining)
    local status = stage[locale] .. "  " .. (chinese and ("剩余 " .. countdown) or (countdown .. " left"))
    local progress = clock(math.floor(age / weather.fps)) .. " / " .. clock(weather.frames / weather.fps)
    GuiColorSetForNextWidget(gui, 1, 0.88, 0.59, 1)
    GuiText(gui, x, y, status)
    GuiText(gui, x + width - GuiGetTextDimensions(gui, progress), y, progress)

    local start_frame = 0
    for i, phase in ipairs(weather.phases) do
        local left = math.floor(width * start_frame / weather.frames)
        start_frame = start_frame + phase.frames
        local right = math.floor(width * start_frame / weather.frames)
        local span = right - left - 1
        rect(10 + i, x + left, y + 12, span, 2, 0.44, 0.54, 0.65, 0.75, 1)
        local filled = 0
        if i < current then filled = span end
        if i == current then filled = math.max(1, math.floor(span * elapsed / phase.frames)) end
        if filled > 0 then
            rect(20 + i, x + left, y + 12, filled, 2, 1, 0.79, 0.39, 1, 0)
        end
        local name = phase[locale]
        local label_width = GuiGetTextDimensions(gui, name, 0.8)
        if i == current then
            GuiColorSetForNextWidget(gui, 1, 0.88, 0.59, 1)
        else
            GuiColorSetForNextWidget(gui, 0.77, 0.81, 0.86, 1)
        end
        GuiText(gui, x + left + (span - label_width) / 2, y + 15, name, 0.8)
    end

    local well_label = chinese and "[气塔]" or "[Gas tower]"
    if well then GuiColorSetForNextWidget(gui, 0.38, 0.76, 1, 1)
    else GuiColorSetForNextWidget(gui, 0.58, 0.60, 0.62, 1) end
    GuiText(gui, x, y + 27, well_label)
    if rig then GuiColorSetForNextWidget(gui, 1, 0.43, 0.37, 1)
    else GuiColorSetForNextWidget(gui, 0.58, 0.60, 0.62, 1) end
    local rigX=x+width/2
    GuiText(gui, rigX, y + 27, chinese and "[油钻]" or "[Oil rig]")
    if wellPending then
        GuiColorSetForNextWidget(gui,0.94,0.79,0.49,1)
        GuiText(gui,x,y+37,chinese and "雪原待落地" or "Pending · Snow",0.8)
    end
    if rigPending then
        GuiColorSetForNextWidget(gui,0.94,0.79,0.49,1)
        GuiText(gui,rigX,y+37,chinese and "沙漠待落地" or "Pending · Desert",0.8)
    end
end
