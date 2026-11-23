local B={}
local pixel="data/ui_gfx/1px_white.png"
local turretStyle={scale=1,pixel="mods/noita_hideout/files/support_card_pixel.png"}

function B.rect(gui,id,x,y,width,height,r,g,b,alpha,z,texture)
    GuiZSetForNextWidget(gui,z)
    GuiColorSetForNextWidget(gui,r,g,b,1)
    GuiImage(gui,id,x,y,texture or pixel,alpha,width,height)
end

function B.draw(gui,id,x,y,width,label,tw,th,fill,r,g,b,style)
    local texture=style and style.pixel
    B.rect(gui,id,x-width/2-2,y-th-7,width+4,th+8,0.07,0.05,0.05,0.84,2,texture)
    B.rect(gui,id+1,x-width/2,y-3,width,2,0.26,0.27,0.30,1,1,texture)
    if fill>0 then B.rect(gui,id+2,x-width/2,y-3,width*math.min(fill,1),2,r,g,b,1,0,texture) end
    if style and fill<=0 then GuiColorSetForNextWidget(gui,r,g,b,1)
    else GuiColorSetForNextWidget(gui,0.96,0.94,0.91,1) end
    GuiText(gui,x-tw/2,y-th-6,label,style and style.scale or 0.8)
end

function B.drawTurret(gui,status,sw,sh,tr)
    local left,top,cw,ch=GameGetCameraBounds()
    if cw<=0 or ch<=0 then return end
    local x,y=(status.x-left)*sw/cw,(status.y-top)*sh/ch
    if x<0 or x>sw or y<0 or y>sh then return end

    local health=tr("耐久 %d/%d","HP %d/%d"):format(status.hp,status.maxHP)
    local ammo=tr("弹药 %d/%d","Ammo %d/%d"):format(status.rounds,status.capacity)
    local hw,hh=GuiGetTextDimensions(gui,health,turretStyle.scale)
    local aw,ah=GuiGetTextDimensions(gui,ammo,turretStyle.scale)
    local width=math.max(32,hw,aw)
    local margin=width/2+2
    x=math.max(margin,math.min(x,sw-margin))
    local bottom=math.max(hh+ah+17,math.min(sh-2,y-27*sh/ch))
    local upper=bottom-ah-9
    local wx,wy=DEBUG_GetMouseWorld()
    local mx,my=(wx-left)*sw/cw,(wy-top)*sh/ch
    if math.abs(mx-x)<=margin and my>=upper-hh-7 and my<=bottom+1 then return end

    B.draw(gui,5840,x,upper,width,health,hw,hh,status.hp/status.maxHP,0.93,0.24,0.22,turretStyle)
    B.draw(gui,5843,x,bottom,width,ammo,aw,ah,status.rounds/status.capacity,1,0.84,0.16,turretStyle)
end

return B
