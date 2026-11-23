local M={}
local offsets={}
local thumbDrag

function M.begin()
    if thumbDrag and not InputIsMouseButtonDown(1) then thumbDrag=nil end
end

local function wheel()
    if InputIsMouseButtonJustDown(4) then return -1 end
    if InputIsMouseButtonJustDown(5) then return 1 end
end

-- Advertise the row viewport to Noita's native wheel hit-test. Its content
-- stays outside this empty container so only rows() advances the visible rows.
local function captureWheel(gui,key,x,y,w,h)
    GuiIdPushString(gui,"nh_wheel/"..key)
    GuiAnimateBegin(gui)
    GuiAnimateAlphaFadeIn(gui,1,0,0,true)
    GuiOptionsAddForNextWidget(gui,GUI_OPTION.NoPositionTween)
    GuiOptionsAddForNextWidget(gui,GUI_OPTION.Layout_NoLayouting)
    GuiOptionsAddForNextWidget(gui,GUI_OPTION.AlwaysClickable)
    GuiZSetForNextWidget(gui,-78)
    GuiBeginScrollContainer(gui,2,x,y,w,h,false,0,0)
    GuiEndScrollContainer(gui)
    GuiAnimateEnd(gui)
    GuiIdPop(gui)
end

-- Return the first row (zero based). Only visible cells become hit targets.
function M.rows(gui,key,id,total,visible,x,y,w,h,scale,mx,my,reveal,draggingItem)
    local max=math.max(0,total-visible)
    local hovered=mx>=x and mx<x+w and my>=y and my<y+h
    if hovered then captureWheel(gui,key,x,y,w,h) end
    if max==0 then offsets[key]=0; return 0 end
    local offset=math.min(offsets[key] or 0,max)
    if reveal then
        if reveal<offset then offset=reveal
        elseif reveal>=offset+visible then offset=reveal-visible+1 end
    elseif hovered then
        offset=offset+(wheel() or 0)*math.min(3,visible)
    end
    local trackX=x+w-4*scale
    local thumbH=math.min(h,math.max(6*scale,h*visible/total))
    local travel=h-thumbH
    offset=math.max(0,math.min(max,offset))
    local thumbY=y+travel*offset/max
    if not draggingItem and hovered and mx>=trackX and InputIsMouseButtonJustDown(1) then
        thumbDrag={key=key,grab=my>=thumbY and my<thumbY+thumbH and my-thumbY or thumbH/2}
    end
    if thumbDrag and thumbDrag.key==key and travel>0 then
        offset=math.max(0,math.min(max,math.floor((my-y-thumbDrag.grab)*max/travel+0.5)))
        thumbY=y+travel*offset/max
    end
    local pixel="data/ui_gfx/1px_white.png"
    GuiImage(gui,id,trackX,y,pixel,0.20,3*scale,h)
    GuiColorSetForNextWidget(gui,0.88,0.78,0.52,1)
    GuiImage(gui,id+1,trackX,thumbY,pixel,0.95,3*scale,thumbH)
    offsets[key]=offset
    return offset
end
return M
