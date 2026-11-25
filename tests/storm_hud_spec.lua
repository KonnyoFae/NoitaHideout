local draw=dofile("mods/noita_hideout/files/storm/hud.lua")
local weather=dofile("mods/noita_hideout/files/storm/weather.lua")
local language="简体中文"
local well,rig,seconds=false,false,600
local wellPending,rigPending,wellRunning,rigRunning=false,false,false,false
local sw,sh,frame=400,230,40020
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
function GuiGetScreenDimensions() return sw,sh end
function GuiGetTextDimensions(_,s,scale)
    local width=0
    for _,c in ipairs({s:byte(1,#s)}) do
        if c>=192 then width=width+8 elseif c<128 then width=width+(c==32 and 3 or 4) end
    end
    if scale and scale<1 and s:match("^%d+:%d%d$") then width=width*0.77 end
    return width*(scale or 1),8*(scale or 1)
end
local measured={}
function GuiGetImageDimensions(_,path)
    measured[path]=(measured[path] or 0)+1
    return 16,32
end
function GuiZSetForNextWidget() end
function GuiColorSetForNextWidget(_,r,g,b) color={r,g,b} end
function GuiImage(_,id,x,y,path,alpha,w,h)
    assert(options[GUI_OPTION.NonInteractive])
    if path~="data/ui_gfx/1px_white.png" then w,h=w*16,(h or w)*32 end
    assert(not images[id] and w>0 and h>0)
    images[id]={x=x,y=y,width=w,height=h,color=color,path=path}
    color=nil
end
function GuiText(_,x,y,s,scale)
    assert(options[GUI_OPTION.NonInteractive])
    local w=GuiGetTextDimensions(1,s,scale)
    -- In-game CJK fallback paints ~20-22 units for a scaled five-glyph clock.
    if s:match("^%d+:%d%d$") then w=#s*5.4*(scale or 1) end
    labels[s]={x=x,y=y,color=color,w=w,scale=scale or 1}
    color=nil
end
function GameTextGet() return language end
function EntityGetWithTag(tag) return tag=="cycle_storm_well" and {2} or {} end
function EntityGetTransform() return wellX,0 end
function GameGetFrameNum() return frame end
function GameGetCameraBounds() return -200,cameraY,cameraWidth,cameraHeight end
function DEBUG_GetMouseWorld() return mouseX,mouseY end
local stations={
    available=function() return well,rig,wellPending,rigPending,wellRunning,rigRunning end,
    wellProgress=function() return seconds/600,seconds,231 end
}
local function render(effects) draw(weather,4,600,54600,stations,nil,effects) end
local function gray(label)
    local c=labels[label].color
    return math.max(unpack(c))-math.min(unpack(c))<0.06
end

render()
assert(gray("[气塔]") and gray("[油钻]"))
local function header(status,wellName,rigName)
    local a,b,c,d=labels[status],labels["15:10 / 20:00"],labels[wellName],labels[rigName]
    assert(a and b and c and d and a.y==b.y and b.y==c.y and c.y==d.y)
    assert(a.x+a.w<b.x and b.x+b.w<c.x)
    assert(math.abs(d.x-c.x-c.w-GuiGetTextDimensions(1," ",c.scale))<0.001)
    assert(a.x>=images[1].x and d.x+d.w<=images[1].x+images[1].width)
end
header("风暴  剩余 02:50","[气塔]","[油钻]")
-- At the base, keep the tower timer readable if the roof is above the screen.
assert(labels["气塔剩余 10:00"].y>=0 and images[105].width==images[104].width)
mouseX,mouseY=images[103].x-199,images[103].y+cameraY+1
render()
assert(not images[103] and not labels["气塔剩余 10:00"] and images[1])
mouseX,mouseY=-999,-999
well,wellRunning,seconds=true,true,300
cameraY=-300
render()
assert(labels["气塔剩余 05:00"].y>0 and images[105].width==images[104].width/2)
assert(labels["[气塔]"].color[3]>labels["[气塔]"].color[1] and gray("[油钻]"))
well,wellRunning,rig,rigRunning=false,false,true,true
seconds=0
render()
assert(gray("[气塔]") and labels["[油钻]"].color[1]>labels["[油钻]"].color[3])
assert(not labels["气塔剩余 00:00"] and not images[105])
language,well,wellX,seconds="English",true,900,45
render()
assert(labels["[Gas tower]"] and labels["[Oil rig]"] and not labels["Gas tower · 00:45"])
wellPending,rigPending=true,true
wellRunning,rigRunning=false,false
render()
local compact=images[1].height
assert(not labels["Pending · Snow"] and not labels["Pending · Desert"])
header("Storm  02:50 left","[Gas tower]","[Oil rig]")
assert(labels["[Gas tower]"].color[3]>labels["[Gas tower]"].color[1] and not gray("[Oil rig]"))
-- A pending station stays colored. Only an operating station alternates every half second.
wellRunning,wellPending=true,false
frame=frame+30; render()
assert(gray("[Gas tower]") and not gray("[Oil rig]"))
frame=frame+30; render()
assert(not gray("[Gas tower]") and not gray("[Oil rig]"))
wellRunning,wellPending=false,true
local function aimAtGui(x,y)
    mouseX,mouseY=-200+x*cameraWidth/sw,cameraY+y*cameraHeight/sh
end
cameraWidth,cameraHeight=800,460
aimAtGui(labels["[Oil rig]"].x+1,labels["[Oil rig]"].y+1)
render(); render()
assert(labels["Pending · Desert"] and not images[1] and images[45])
mouseX=-999; render()
aimAtGui(images[1].x+2,images[1].y+images[1].height-1)
render(); render(); assert(not next(images) and not next(labels))
cameraWidth,cameraHeight=400,230
language="简体中文"; rigPending=false; mouseX=-999; render()
aimAtGui(labels["[气塔]"].x+1,labels["[气塔]"].y+1); render()
assert(labels["雪原待落地"] and not images[1])
wellPending=false; language="English"; mouseX=-999; render()
assert(gray("[Gas tower]") and gray("[Oil rig]") and images[1].height==compact)

-- Fractions of a second round up; expired entries never occupy a slot.
local first="mods/noita_hideout/files/items/tarot_sun.png"
local effects={{icon=first,frames=60*60+1,label="Sun"},{icon="mods/noita_hideout/files/items/tarot_moon.png",frames=1},
    {icon=first,frames=0},{icon=first,frames=-30}}
render(effects)
assert(images[10001].path==first and images[10002] and not images[10003])
assert(labels["01:01"] and labels["00:01"] and not labels["00:00"])
assert(images[10001].x<images[10002].x and images[10001].y==images[10002].y)
assert(images[10001].height==8 and images[10001].width==4 and measured[first]==1)
assert(labels["01:01"].x>images[10001].x+images[10001].width and labels["01:01"].x+labels["01:01"].w<images[10002].x)
assert(labels["01:01"].y>labels["Storm"].y and images[1].height>compact)
aimAtGui(images[10001].x+1,images[10001].y+1); render(effects)
assert(labels.Sun and not images[10001])
mouseX=-999; render(effects); assert(measured[first]==1)
effects[1].frames=60*60; render(effects); assert(labels["01:00"] and not labels["01:01"])
render({}); assert(images[1].height==compact and not images[10001])
-- Multiple rows preserve source order; every timer fits within the frame on both aspect ratios.
effects={}
for i=1,32 do effects[i]={icon=first,frames=i*60} end
effects[32].frames=100*60*60
for _,dims in ipairs({{640,360},{165,90}}) do
    sw,sh=dims[1],dims[2]
    for _,lang in ipairs({"English","简体中文"}) do
        language=lang; render(effects)
        if lang=="English" then header("Storm  02:50 left","[Gas tower]","[Oil rig]")
        else header("风暴  剩余 02:50","[气塔]","[油钻]") end
        assert(images[1].x>=0 and images[1].y>=0 and images[1].y+images[1].height<=sh)
        assert(images[10032].y>images[10001].y)
        for i=1,32 do
            local icon=assert(images[10000+i])
            local text=assert(labels[i==32 and "100:00" or string.format("00:%02d",i)])
            assert(text.x>=icon.x+icon.width and text.x+text.w<=images[1].x+images[1].width)
            assert(icon.y+icon.height<=images[1].y+images[1].height)
            if i>1 then
                local previous=images[9999+i]
                assert(icon.y>previous.y or (icon.y==previous.y and icon.x>previous.x))
                local previousText=labels[string.format("00:%02d",i-1)]
                if icon.y==previous.y then assert(previousText.x+previousText.w<icon.x) end
            end
        end
    end
end
sw,sh,language=400,230,"English"
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
