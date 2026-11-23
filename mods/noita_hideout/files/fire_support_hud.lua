local tile="data/ui_gfx/inventory/quick_inventory_box.png"
local icon="mods/noita_hideout/files/support_pointer_icon.png"
local grip="mods/noita_hideout/files/support_pointer_grip.png"
local pixel="data/ui_gfx/1px_white.png"
local cardPixel="mods/noita_hideout/files/support_card_pixel.png"
local cardFill={0.10,0.075,0.045}
local cardGold={0.93,0.73,0.29}
local arrowPath="mods/noita_hideout/files/support_arrow_"
-- Tight white alpha masks from Noita's notosans_zhcn_48 atlas. One texture
-- pixel is 1/4 GUI unit at normal size, including in the HD language renderer.
local function labelPath(key,lang)
    return "mods/noita_hideout/files/support_labels/"..key.."_"..lang..".png"
end
local categoryLabels={zh={},en={}}
for lang,paths in pairs(categoryLabels) do
    for i,key in ipairs({"supply","strike","reinforcements","intel"}) do
        paths[i]=labelPath(key,lang)
    end
end
local normalLabelScale=0.25
local selectedMagnification=1.2

local digitScale=0.65
local function drawCard(gui,base,x,y,w,h,scale,label,active,cue,amount)
    local id=base
    local function rect(dx,dy,width,height,color,alpha)
        id=id+1
        GuiZSetForNextWidget(gui,-79)
        GuiOptionsAddForNextWidget(gui,GUI_OPTION.NoPositionTween)
        GuiColorSetForNextWidget(gui,color[1],color[2],color[3],1)
        GuiImage(gui,id,x+dx*scale,y+dy*scale,cardPixel,alpha,width*scale,height*scale)
    end
    rect(1,1,w-2,h-2,cardFill,active and 1 or 0.92)
    local border=active and 1 or 0.94
    rect(0,0,w,1,cardGold,border)
    rect(0,h-1,w,1,cardGold,border)
    rect(0,1,1,h-2,cardGold,border)
    rect(w-1,1,1,h-2,cardGold,border)
    local function arrow(dx,dy,direction)
        id=id+1
        GuiZSetForNextWidget(gui,-82)
        GuiOptionsAddForNextWidget(gui,GUI_OPTION.NoPositionTween)
        GuiColorSetForNextWidget(gui,cardGold[1],cardGold[2],cardGold[3],1)
        GuiImage(gui,id,x+dx*scale,y+dy*scale,arrowPath..direction..".png",1,scale,scale)
    end
    local offsetY=0
    if cue=="expand" then
        arrow(2,h-5,"down")
        arrow(w-7,h-5,"down")
    elseif cue=="right" then
        arrow(w-6,(h-5)/2,"right")
    elseif cue=="up" or cue=="down" then
        local up=cue=="up"
        offsetY=up and -2 or 2
        arrow((w-5)/2,up and h-5 or 2,cue)
    end
    local zoom=normalLabelScale*scale*(active and not amount and selectedMagnification or 1)
    local tw,th=GuiGetImageDimensions(gui,label)
    local textX=x+(w*scale-tw*zoom)/2
    if amount then offsetY=-(10*digitScale+2)/2 end
    local textY=y+(h*scale-th*zoom)/2+offsetY*scale
    GuiOptionsAddForNextWidget(gui,GUI_OPTION.NoPositionTween)
    GuiColorSetForNextWidget(gui,0.98,0.83,0.48,1)
    GuiImage(gui,base+16,textX,textY,label,active and 1 or 0.96,zoom,zoom)
    if amount then
        local size=digitScale*scale
        local left=x+(w*scale-(#amount*7-1)*size)/2
        for i=1,#amount do
            local char=amount:sub(i,i)
            GuiOptionsAddForNextWidget(gui,GUI_OPTION.NoPositionTween)
            GuiColorSetForNextWidget(gui,0.98,0.83,0.48,1)
            GuiImage(gui,base+16+i,left+(i-1)*7*size,textY+th*zoom+2*scale,
                "mods/noita_hideout/files/slot_digits.xml",1,size,size,0,1,char=="/" and "slash" or char)
        end
    end
end

local function labelSize(gui,labels)
    local labelW,labelH=0,0
    for _,label in ipairs(labels) do
        local w,h=GuiGetImageDimensions(gui,label)
        labelW,labelH=math.max(labelW,w*normalLabelScale),math.max(labelH,h*normalLabelScale)
    end
    return labelW,labelH
end

local function drawCategories(gui,v,lang,px,py,sw,sh)
    local labels=categoryLabels[lang]
    local selected=v.menu.category
    local gap=3
    local labelW,labelH=labelSize(gui,labels)
    local smallW=math.max(38,math.ceil(labelW)+8)
    local largeW=math.max(smallW+10,math.ceil(labelW*selectedMagnification)+16)
    local smallH=math.max(15,math.ceil(labelH)+4)
    local largeH=smallH+4
    local total=(#labels-1)*(smallW+gap)+largeW
    local anchor=(selected-1)*(smallW+gap)+largeW/2
    local leftExtent,rightExtent=anchor,total-anchor
    local projects={}
    local current=v.menu.project or 1
    local first,last,pw,ph,activeW,activeH,status,statusW,statusH
    local confirm,confirmW,costLabel,costW,amount
    local above,below=0,0
    if v.menu.level>=2 then
        for i,key in ipairs(v.projects) do projects[i]=labelPath(key,lang) end
        local tw,th=labelSize(gui,projects)
        pw,ph=math.max(34,math.ceil(tw)+8),math.max(15,math.ceil(th)+10)
        activeW=math.max(pw+6,math.ceil(tw*selectedMagnification)+16)
        activeH=math.max(ph+2,math.ceil(th*selectedMagnification)+4)
        first,last=math.max(1,current-2),math.min(#projects,current+2)
        if v.payment then
            local payment=v.payment
            costLabel=labelPath(payment.resource,lang)
            local rw,rh=GuiGetImageDimensions(gui,costLabel)
            amount=string.format("%.0f/%.0f",payment.cost,payment.stock)
            costW=math.ceil(math.max(rw*normalLabelScale,(#amount*7-1)*digitScale))+8
            activeH=math.max(activeH,math.ceil(rh*normalLabelScale+10*digitScale)+6)
            leftExtent=math.max(leftExtent,activeW/2+gap+costW)
            if v.menu.level==3 and not v.projectStatus then
                confirm=labelPath("confirm",lang)
                local cw,ch=GuiGetImageDimensions(gui,confirm)
                confirmW=math.max(38,math.ceil(cw*normalLabelScale*selectedMagnification)+16)
                activeH=math.max(activeH,math.ceil(ch*normalLabelScale*selectedMagnification)+4)
                rightExtent=math.max(rightExtent,activeW/2+gap+confirmW)
            end
        end
        local columnW=0
        if #projects>0 then
            above=(current-first)*(ph+gap)
            below=gap+activeH+(last-current)*(ph+gap)
            columnW=activeW
        end
        if v.projectStatus then
            status=labelPath(v.projectStatus,lang)
            local w,h=GuiGetImageDimensions(gui,status)
            statusW,statusH=math.ceil(w*normalLabelScale)+10,math.ceil(h*normalLabelScale)+6
            below=below+gap+statusH
            columnW=math.max(columnW,statusW)
        end
        leftExtent,rightExtent=math.max(leftExtent,columnW/2),math.max(rightExtent,columnW/2)
    end
    local scale=math.min(1,(sw-4)/(leftExtent+rightExtent),(sh-4)/(above+largeH+below))
    if scale<=0 then return end
    -- Keep the selected card under the player until the row reaches a screen edge.
    local center=math.max(2+leftExtent*scale,math.min(px,sw-2-rightExtent*scale))
    local left=center-anchor*scale
    local top=math.max(2+above*scale,math.min(py+12,sh-2-(largeH+below)*scale))
    GuiIdPushString(gui,"nh_support_categories")
    for i,label in ipairs(labels) do
        local active=i==selected
        local w,h=active and largeW or smallW,active and largeH or smallH
        local y=top+(largeH-h)*scale/2
        drawCard(gui,i*20,left,y,w,h,scale,label,active,active and v.menu.level==1 and "expand")
        left=left+(w+gap)*scale
    end
    if v.menu.level>=2 then
        local projectTop=top+(largeH+gap)*scale
        for i=first,last do
            local active=i==current
            local w,h=active and activeW or pw,active and activeH or ph
            local y=projectTop
            local cue
            if i<current then
                y=top-(current-i)*(ph+gap)*scale
                if i==current-1 then cue="up" end
            elseif i>current then
                y=projectTop+(activeH+gap+(i-current-1)*(ph+gap))*scale
                if i==current+1 then cue="down" end
            elseif not v.projectStatus then cue="right" end
            drawCard(gui,100+i*20,center-w*scale/2,y,w,h,scale,projects[i],active,cue)
        end
        if status then
            local y=top+(largeH+below-statusH)*scale
            drawCard(gui,100+(#projects+1)*20,center-statusW*scale/2,y,statusW,statusH,scale,status,false)
        end
        if costLabel then
            local side=(activeW/2+gap)*scale
            local base=100+(#projects+1)*20
            if confirm then drawCard(gui,base,center+side,projectTop,confirmW,activeH,scale,confirm,true,"right") end
            drawCard(gui,base+20,center-side-costW*scale,projectTop,costW,activeH,scale,costLabel,true,nil,amount)
        end
    end
    GuiIdPop(gui)
end

local function drawStrikeWarning(gui,screen,path,sx,sy,locked)
    local function line(id,x,y,tx,ty,danger)
        x,y=screen(x,y)
        tx,ty=screen(tx,ty)
        local dx,dy=tx-x,ty-y
        local length=math.sqrt(dx*dx+dy*dy)
        if length<0.01 then return end
        GuiOptionsAddForNextWidget(gui,GUI_OPTION.NoPositionTween)
        GuiColorSetForNextWidget(gui,1,danger and 0.25 or 0.75,0.12,1)
        GuiImage(gui,id,x,y,pixel,locked and 0.95 or 0.68,length,1,math.atan2(dy,dx))
    end
    local x,y=path.endX or path.x,path.endY or path.y
    if x~=path.x or y~=path.y then line(6030,path.x,path.y,x,y,true) end
    local radius=path.danger or path.radius
    local dx,dy=x-sx,y-sy
    for i=0,5 do
        local a,b=i/6,(i+0.65)/6
        line(6000+i,sx+dx*a,sy+dy*a,sx+dx*b,sy+dy*b)
    end
    local length=math.sqrt(dx*dx+dy*dy)
    if length>10 then
        local ax,ay=sx+dx*0.52,sy+dy*0.52
        dx,dy=dx/length,dy/length
        for i=-1,1,2 do
            line(6008+i,ax-4*dx+i*2*dy,ay-4*dy-i*2*dx,ax,ay)
        end
    end
    local segments=math.max(20,math.ceil(radius/5))
    for i=0,segments-1 do
        local a,b=i*2*math.pi/segments,(i+0.84)*2*math.pi/segments
        line(6010+i,x+math.cos(a)*radius,y+math.sin(a)*radius,
            x+math.cos(b)*radius,y+math.sin(b)*radius,true)
    end
end

local function zoneNotice(gui,v,sw,row,alert,path,due,tr)
    local dx,dy=v.x-path.x,v.y-path.y
    local distance=math.sqrt(dx*dx+dy*dy)
    local inside=distance<=path.radius
    local state=inside and tr("危险区内","DANGER") or tr("危险区外","Outside zone")
    local seconds=due and math.max(0,math.ceil((due-GameGetFrameNum())/60))
    local time=seconds and string.format(" · %ds",seconds) or ""
    local text=string.format("%s · %s%s · %d/%d px",tr(unpack(alert)),state,time,math.floor(distance),path.radius)
    local width,height=GuiGetTextDimensions(gui,text)
    local x,y=(sw-width)/2,5+row*(height+4)
    GuiColorSetForNextWidget(gui,inside and 0.42 or 0.12,0.05,0.04,1)
    GuiImage(gui,6450+row,x-3,y-1,cardPixel,0.92,width+6,height+2)
    GuiColorSetForNextWidget(gui,1,inside and 0.72 or 0.91,0.52,1)
    GuiText(gui,x,y,text)
end

local function drawPattern(gui,screen,v)
    local function line(id,x,y,tx,ty)
        x,y=screen(x,y)
        tx,ty=screen(tx,ty)
        local dx,dy=tx-x,ty-y
        GuiOptionsAddForNextWidget(gui,GUI_OPTION.NoPositionTween)
        GuiColorSetForNextWidget(gui,1,0.47,0.12,1)
        GuiImage(gui,id,x,y,pixel,0.85,math.sqrt(dx*dx+dy*dy),1,math.atan2(dy,dx))
    end
    if v.center then
        local c=v.center
        for i=0,23 do
            local a,b=i*math.pi/12,(i+0.78)*math.pi/12
            line(6200+i,c.x+c.radius*math.cos(a),c.y+c.radius*math.sin(a),c.x+c.radius*math.cos(b),c.y+c.radius*math.sin(b))
        end
        local nextPoint=v.route[v.index or 1]
        if nextPoint then line(6224,nextPoint.x-2,nextPoint.y,nextPoint.x+2,nextPoint.y) end
    elseif v.route then
        local route=v.route
        for i=2,#route do
            local a,b=route[i-1],route[i]
            for side=-1,1,2 do
                local extent=side*(v.spec and (v.spec.danger or v.spec.radius) or v.path.danger or v.path.radius)/3
                line(6230+2*i+(side+1)/2,a.x+a.ox*extent,a.y+a.oy*extent,b.x+b.ox*extent,b.y+b.oy*extent)
            end
        end
        local function arrow(id,p,dx,dy)
            for sign=-1,1,2 do
                line(id+(sign+1)/2,p.x-4*dx+sign*2*dy,p.y-4*dy-sign*2*dx,p.x,p.y)
            end
        end
        arrow(6260,route[1],route.dx,route.dy)
        if #route>1 then
            local p,q=route[#route],route[#route-1]
            local dx,dy=q.x-p.x,q.y-p.y
            local length=math.sqrt(dx*dx+dy*dy)
            if length>0 then arrow(6262,p,dx/length,dy/length) end
        end
    end
end

return function(gui,v,sw,sh,tr)
    local cx,cy,cw,ch=GameGetCameraBounds()
    if cw<=0 or ch<=0 then return end
    local function screen(x,y) return (x-cx)*sw/cw,(y-cy)*sh/ch end
    local call=v.call
    local frame=GameGetFrameNum()
    if v.salvo then drawPattern(gui,screen,v.salvo)
    elseif call and call.route and call.path and (call.phase=="queued" or call.phase=="aim" and not v.menu) then
        drawPattern(gui,screen,call)
    end
    if v.airborne then
        local p=v.airborne.path
        local sx,sy=EntityGetTransform(v.airborne.id)
        drawStrikeWarning(gui,screen,p,sx,sy,true)
    end
    if call and call.path and (call.phase=="queued" or (call.phase=="aim" and not v.menu)) then
        GuiIdPushString(gui,"nh_designated_path")
        drawStrikeWarning(gui,screen,call.path,call.path.sx,call.path.sy,call.phase=="queued")
        GuiIdPop(gui)
    end
    local row=0
    if call and v.alert and call.path and (call.phase=="aim" or call.phase=="queued") then
        zoneNotice(gui,v,sw,row,v.alert,call.path,call.due,tr)
        row=row+1
    end
    local closest,clearance
    for _,zone in ipairs(v.activeZones or {}) do
        local path=zone.path
        local sx,sy=EntityGetTransform(zone.id)
        GuiIdPushString(gui,"nh_zone_"..zone.id)
        drawStrikeWarning(gui,screen,path,sx,sy,true)
        GuiIdPop(gui)
        local dx,dy=v.x-path.x,v.y-path.y
        local edge=math.sqrt(dx*dx+dy*dy)-path.radius
        if not clearance or edge<clearance then closest,clearance=zone,edge end
    end
    if closest then zoneNotice(gui,v,sw,row,closest.alert,closest.path,nil,tr) end
    if call and call.phase=="connecting" then
        local x,y=screen(v.x,v.y)
        local seconds=math.max(0,math.ceil((call.connectedAt-frame)/60))
        local text=string.format(tr("数据链连接中 · %d 秒","Connecting · %d s"),seconds)
        if not v.menu then GuiText(gui,x-GuiGetTextDimensions(gui,text)/2,y+12,text) end
    elseif call and call.targeted then
        local w,h=GuiGetImageDimensions(gui,tile)
        local sx=(tonumber(MagicNumbersGetValue("UI_BARS_POS_X")) or 0)+8*w+2
        local sy=tonumber(MagicNumbersGetValue("UI_BARS_POS_Y")) or 0
        local alpha=1
        if call.phase=="queued" or call.phase=="finished" then alpha=0.32
        elseif call.phase=="ready" then alpha=0.65+0.35*math.cos(frame/7) end
        GuiImage(gui,5960,sx,sy,tile,alpha)
        local iw,ih=GuiGetImageDimensions(gui,icon)
        GuiImage(gui,5961,sx+3,sy+3,icon,alpha,(w-6)/iw,(h-6)/ih)
        if call.selected and call.grip and not v.menu then
            local g=call.grip
            local x,y=screen(g.x,g.y)
            GuiImage(gui,5963,x,y,grip,1,sw/cw,sh/ch,math.atan2(g.dy*sh/ch,g.dx*sw/cw))
        end
        if call.phase=="aim" and call.beam and not v.menu then
            local b=call.beam
            local x,y=screen(b.sx,b.sy)
            local tx,ty=screen(b.x,b.y)
            local dx,dy=tx-x,ty-y
            local length=math.sqrt(dx*dx+dy*dy)
            if length>0.01 then
                local angle=math.atan2(dy,dx)
                GuiColorSetForNextWidget(gui,1,0.1,0.1,1)
                GuiImage(gui,5962,x,y,pixel,0.9,length,1,angle)
                if b.target then
                    GuiColorSetForNextWidget(gui,1,0.25,0.18,1)
                    GuiText(gui,tx-3,ty-5,"+")
                end
                if b.hit and (not call.tracking or b.target) and not call.path then
                    GuiColorSetForNextWidget(gui,1,0.55,0.25,1)
                    GuiText(gui,tx+4,ty+3,tr("弹道受阻","Path blocked"))
                end
            end
        elseif call.phase=="queued" and call.marker then
            local x,y=screen(call.marker.x,call.marker.y)
            local alpha=0.35+0.65*(0.5+0.5*math.cos(frame/4))
            GuiColorSetForNextWidget(gui,0.2,1,0.3,alpha)
            GuiText(gui,x-4,y-6,"+",1.3)
        end
    end
    local m=v.menu
    if not m then return end
    local px,py=screen(v.x,v.y)
    drawCategories(gui,v,tr("zh","en"),px,py,sw,sh)
end
