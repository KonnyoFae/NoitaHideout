return function(gui,v,sw,sh,tr)
    if v.transit then
        local text=tr("正在确认降落点…","Checking landing site…")
        GuiText(gui,(sw-GuiGetTextDimensions(gui,text))/2,sh-36,text)
        return
    end
    if v.key then
        local text=tr("长按 %s  开启返航门","Hold %s  Open return portal"):format(v.key)
        if v.percent then text=text.."  "..v.percent.."%" end
        GuiColorSetForNextWidget(gui,0.65,0.92,1,1)
        GuiText(gui,(sw-GuiGetTextDimensions(gui,text))/2,sh-36,text)
        return
    end
end
