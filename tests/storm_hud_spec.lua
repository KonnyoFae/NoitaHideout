local draw=dofile("mods/noita_hideout/files/storm/hud.lua")
local weather=dofile("mods/noita_hideout/files/storm/weather.lua")
local language="简体中文"
local well,rig,seconds=false,false,600
local wellPending,rigPending=false,false
local cameraY,wellX=-100,0
local cameraWidth,cameraHeight=400,230
local mouseX,mouseY=-999,-999
local labels,images,color
local options
function dofile_once(path)
    assert(path=="data/scripts/lib/utilities.lua")
    GUI_OPTION={NonInteractive=2,NoPositionTween=6}
end
function GuiCreate() return 1 end
function GuiStartFrame() labels,images,color,options={},{},nil,{} end
function GuiOptionsAdd(_,key) options[key]=true end
function GuiGetScreenDimensions() return 400,230 end
function GuiGetTextDimensions(_,s,scale) return #s*4*(scale or 1),8*(scale or 1) end
function GuiZSetForNextWidget() end
function GuiColorSetForNextWidget(_,r,g,b) color={r,g,b} end
function GuiImage(_,id,x,y,path,alpha,w,h)
    assert(options[GUI_OPTION.NonInteractive])
    assert(not images[id] and w>0 and h>0)
    images[id]={x=x,y=y,width=w,height=h,color=color}
    color=nil
end
function GuiText(_,x,y,s)
    assert(options[GUI_OPTION.NonInteractive])
    labels[s]={x=x,y=y,color=color}
    color=nil
end
function GameTextGet() return language end
function EntityGetWithTag(tag) return tag=="cycle_storm_well" and {2} or {} end
function EntityGetTransform() return wellX,0 end
function GameGetFrameNum() return 40000 end
function GameGetCameraBounds() return -200,cameraY,cameraWidth,cameraHeight end
function DEBUG_GetMouseWorld() return mouseX,mouseY end
local stations={
    available=function() return well,rig,wellPending,rigPending end,
    wellProgress=function() return seconds/600,seconds,231 end
}
local function render() draw(weather,4,600,54600,stations) end
local function gray(label)
    local c=labels[label].color
    return math.max(unpack(c))-math.min(unpack(c))<0.06
end

render()
assert(gray("[气塔]") and gray("[油钻]"))
assert(labels["[气塔]"].x+GuiGetTextDimensions(1,"[气塔]")<labels["[油钻]"].x)
assert(labels["[气塔]"].y>labels["风暴  剩余 02:50"].y)
-- At the base, keep the tower timer readable if the roof is above the screen.
assert(labels["气塔剩余 10:00"].y>=0 and images[105].width==images[104].width)
mouseX,mouseY=images[103].x-199,images[103].y+cameraY+1
render()
assert(not images[103] and not labels["气塔剩余 10:00"] and images[1])
mouseX,mouseY=-999,-999
well,seconds=true,300
cameraY=-300
render()
assert(labels["气塔剩余 05:00"].y>0 and images[105].width==images[104].width/2)
assert(labels["[气塔]"].color[3]>labels["[气塔]"].color[1] and gray("[油钻]"))
well,rig=false,true
seconds=0
render()
assert(gray("[气塔]") and labels["[油钻]"].color[1]>labels["[油钻]"].color[3])
assert(not labels["气塔剩余 00:00"] and not images[105])
language,well,wellX,seconds="English",true,900,45
render()
assert(labels["[Gas tower]"] and labels["[Oil rig]"] and not labels["Gas tower · 00:45"])
wellPending,rigPending=true,true
render()
assert(labels["Pending · Snow"] and labels["Pending · Desert"] and images[1].height==51)
-- Aim at the pending row, hold through a second frame, and move off it at 2x world scale.
cameraWidth,cameraHeight=800,460
mouseX,mouseY=-200+(images[1].x+2)*2,cameraY+(images[1].y+50)*2
render(); render()
assert(not next(labels) and not next(images))
mouseX=-999; render()
assert(labels["Pending · Snow"] and images[1])
cameraWidth,cameraHeight=400,230
language="简体中文"; rigPending=false; render()
assert(labels["雪原待落地"] and not labels["沙漠待落地"] and labels["雪原待落地"].y>labels["[气塔]"].y)
wellPending=false; language="English"; render()
assert(not labels["Pending · Snow"] and images[1].height==41)
local scan={active=function() return true end,nearby=function()
    return {{kind="ship",x=wellX-30,y=-40},{kind="rig",x=wellX+5,y=0}}
end}
function EntityGetWithTag(tag) return tag=="player_unit" and {1} or {} end
draw(weather,4,600,54600,stations,scan)
assert(labels["Airship  NW  50 px"] and labels["Oil rig  E  5 px"])
mouseX,mouseY=-200+images[61].x+2,cameraY+images[61].y+2
draw(weather,4,600,54600,stations,scan)
assert(not images[61] and labels["Oil rig  E  5 px"] and images[1])
mouseX,mouseY=-999,-999
language="简体中文"; draw(weather,4,600,54600,stations,scan)
assert(labels["飞艇  左上  50 px"] and labels["油钻  右  5 px"])
scan.active=function() return false end
draw(weather,4,600,54600,stations,scan)
assert(not labels["飞艇  左上  50 px"])
print("Storm HUD: localized site status, tower countdown, fill and camera clipping passed.")
