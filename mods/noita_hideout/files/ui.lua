NHUI = {}

local gui
local tab = "orders"
local warehouse_tab, folded = "wand", false
local warehouse_pages = {}
local warehouse_tabs = {
    {"wand","魔杖","Wands"}, {"spell","法术","Spells"}, {"containers","容器","Containers"},
    {"supplies","消耗品","Supplies"}, {"materials","物料","Materials"},
}
local workshop_folded=false
local project_pages={expansion=1,upgrade=1}
local selected_project,selected_recipe,salvage_target
local projects_per_page=5
local work_tabs={
    {key="orders",id=212,zh="工坊",en="Workshop"},
    {key="expansion",id=218,zh="扩建",en="Build"},
    {key="upgrade",id=219,zh="升级",en="Upgrades"},
    {key="samples",id=213,zh="测试物资",en="Supplies"},
}
local white = { 0.96, 0.93, 0.84 }
local gold = { 1.00, 0.83, 0.47 }
local muted = { 0.76, 0.80, 0.78 }
local green = { 0.62, 0.95, 0.75 }
local function tint(color)
    GuiColorSetForNextWidget(gui, color[1], color[2], color[3], 1)
end

-- Trim at character boundaries. The GUI can run with either Chinese or English game fonts.
local function fit(value, available, scale)
    local original = tostring(value or ""):gsub("[\r\n]+", " ")
    local width = GuiGetTextDimensions(gui, original, scale)
    if width <= available then return original, false end
    local chars = {}
    for char in original:gmatch("[^\128-\191][\128-\191]*") do
        chars[#chars + 1] = char
    end
    local lo, hi = 0, #chars
    while lo < hi do
        local n = math.ceil((lo + hi) / 2)
        local w = GuiGetTextDimensions(gui, table.concat(chars, "", 1, n) .. "...", scale)
        if w <= available then lo = n else hi = n - 1 end
    end
    return table.concat(chars, "", 1, lo) .. "...", true
end

local drag, last_case_frame
local page = 1
local loading
local material_rows=4
local function compact(n)
    local unit,suffix
    if n>=1e12 then unit,suffix=1e12,"T"
    elseif n>=1e9 then unit,suffix=1e9,"B"
    elseif n>=1e6 then unit,suffix=1e6,"M"
    elseif n>=1e3 then unit,suffix=1e3,"k"
    else return tostring(n) end
    return tostring(math.floor(n/unit*10)/10)..suffix
end
local function storage_key(key)
    if key=="valuable" then return "safe" end
    if key=="warehouse" or key=="docks" then return key end
end
local full_tile = "data/ui_gfx/inventory/full_inventory_box.png"
local tile = "data/ui_gfx/inventory/quick_inventory_box.png"
local icons = {
    pouch = "mods/noita_hideout/files/items/pouch.png",
    dose = "mods/noita_hideout/files/items/dose.png",
    wand = "data/items_gfx/handgun.png", potion = "data/items_gfx/potion.png",
}

local function cursor_tip(lines,mx,my,sw,sh,scale)
    local pad=4*scale
    local line_h=10*scale
    local limit=math.max(1,math.floor((sh-2*pad-4)/line_h))
    local width=0
    local count=math.min(#lines,limit)
    for i=1,count do
        if i==limit and #lines>limit then lines[i]="… +"..(#lines-limit+1) end
        lines[i]=fit(lines[i],sw-2*pad-4,scale)
        local text_width=GuiGetTextDimensions(gui,lines[i],scale)
        width=math.max(width,text_width)
    end
    width=width+2*pad
    local height=count*line_h+2*pad
    local x,y=mx+8*scale,my+8*scale
    if x+width>sw-2 then x=mx-width-5*scale end
    if y+height>sh-2 then y=my-height-5*scale end
    x=math.max(2,math.min(x,sw-width-2))
    y=math.max(2,math.min(y,sh-height-2))
    GuiZSetForNextWidget(gui,-92)
    GuiImageNinePiece(gui,200,x,y,width,height,1)
    for i=1,count do
        GuiZSetForNextWidget(gui,-93)
        tint(i==1 and gold or white)
        GuiText(gui,x+pad,y+pad+(i-1)*line_h,lines[i],scale)
    end
end

local function item_details(slot,model,tr)
    local record=slot.view and slot.view.potion
    if record then
        local used,capacity=NHPotion.fillLevel(record)
        local lines={NHPotion.containerName(record,model.lang).."  "..used.."/"..capacity}
        local names={}
        for name in pairs(record.materials) do names[#names+1]=name end
        table.sort(names)
        for _,name in ipairs(names) do
            lines[#lines+1]=NHPotion.materialName(name).."  "..string.format("%.0f",record.materials[name])
        end
        return lines
    end
    if slot.kind=="pouch" then return {tr("针剂包","Injector pouch"),tr("点击打开，拖动移动","Click to open or drag to move")} end
    if slot.kind=="dose" then
        return {tr("耐火激活剂","Fire injector"),tr("耐久 ","Durability ")..(slot.remaining or model.maxUses).."/"..model.maxUses
            ..tr("   数量 ","   Count ")..(slot.count or 1)}
    end
    return {slot.name or slot.kind}
end

-- Dimensions here are GUI units. Container cells keep the native tile pitch
-- while the three panels share the available horizontal space at spawn.
local function home_layout(sw,scale,tile_width)
    local room=(sw-10)/scale-10
    local bench=math.min(186,math.floor(room*0.30))
    local stash=math.min(230,math.floor(room*0.43))
    local secure=math.min(187,math.max(16+4*tile_width,room-bench-stash))
    stash=math.min(stash,room-bench-secure)
    local left=5
    local right=sw-5-secure*scale
    local middle=(left+stash*scale+right-bench*scale)/2
    return {left=left,stash=stash,middle=middle,bench=bench,secure=secure}
end

-- Keep the ends of a long page strip reachable and center the nearby numbers.
local function warehouse_pager(x,y,width,scale,current,pages)
    current=math.min(current,pages)
    local selected=current
    GuiZSetForNextWidget(gui,-79)
    GuiImageNinePiece(gui,299,x,y,width*scale,14*scale,0.7)
    local function button(id,offset,title,color)
        tint(color)
        return GuiButton(gui,id,x+offset*scale,y+2*scale,title,scale) and not drag
    end
    if button(300,4,"<",current>1 and gold or muted) then selected=math.max(1,current-1) end
    if button(301,width-11,">",current<pages and gold or muted) then selected=math.min(pages,current+1) end
    local pitch=GuiGetTextDimensions(gui,"["..pages.."]",scale)/scale+5
    local count=math.min(pages,math.max(1,math.floor((width-32)/pitch)))
    local start=math.max(1,math.min(pages-count+1,current-math.floor(count/2)))
    for i=1,count do
        local n=start+i-1
        if count>=5 and i==1 then n=1 elseif count>=5 and i==count then n=pages end
        local title=n==current and ("["..n.."]") or tostring(n)
        local center=width/2+(i-(count+1)/2)*pitch
        local offset=center-GuiGetTextDimensions(gui,title,scale)/(2*scale)
        if button(301+i,offset,title,n==current and gold or white) then selected=n end
    end
    return selected
end

local function draw_workshop(model,layout,scale,sh,tr,dispatch,mx,my)
    local left,width=layout.middle,layout.bench
    if not model.debug and tab=="samples" then tab="orders" end
    local tx,ty=6,18
    local nav={}
    for _,t in ipairs(work_tabs) do
        if t.key~="samples" or model.debug then
            local name=tr(t.zh,t.en)
            local w=GuiGetTextDimensions(gui,name,scale)/scale
            if tx>6 and tx+w>width-5 then tx,ty=6,ty+13 end
            nav[#nav+1]={id=t.id,key=t.key,name=name,x=tx,y=ty}
            tx=tx+w+7
        end
    end
    local body=ty+16
    local menu=model.progression[tab]
    local selected
    for _,item in ipairs(menu or {}) do
        if item.id==selected_project then selected=item; break end
    end
    local recipes=model.recipes
    local rindex=1
    for i,recipe in ipairs(recipes) do if recipe.id==selected_recipe then rindex=i; break end end
    local recipe=recipes[rindex]
    local salvage
    if salvage_target and model.salvage_enabled then
        local category=model.warehouse[salvage_target.kind]
        salvage=category and category[salvage_target.slot]
        if not salvage or salvage.id~=salvage_target.id then salvage_target,salvage=nil,nil end
    end
    local body_height=62
    if salvage then body_height=77
    elseif selected then body_height=80+12*#selected.costs
    elseif menu then body_height=16+projects_per_page*13
    elseif tab=="orders" then body_height=69+12*#recipe.inputs+(model.debug and 14 or 0) end
    local height=workshop_folded and 18 or body+body_height
    local top=sh-5-height*scale
    local function label(y,value,color)
        local txt,short=fit(value,(width-12)*scale,scale)
        tint(color or white)
        GuiText(gui,left+6*scale,top+y*scale,txt,scale)
        if short then GuiTooltip(gui,value,"") end
    end
    local function button(id,x,y,value,color,tip)
        local txt,short=fit(value,(width-x-5)*scale,scale)
        tint(color or gold)
        local clicked=GuiButton(gui,id,left+x*scale,top+y*scale,txt,scale)
        if tip or short then GuiTooltip(gui,tip or value,"") end
        return clicked and not drag
    end
    GuiZSetForNextWidget(gui,-79)
    GuiImageNinePiece(gui,210,left,top,width*scale,height*scale,1)
    local hover=mx>=left and mx<left+width*scale and my>=top and my<top+height*scale
    if button(211,6,3,(workshop_folded and "[+] " or "[-] ")..tr("藏身处","Hideout")) then
        workshop_folded=not workshop_folded
        return hover
    end
    if workshop_folded then return hover end
    for _,t in ipairs(nav) do
        if button(t.id,t.x,t.y,t.name,t.key==tab and gold or muted) then
            tab,selected_project,salvage_target=t.key,nil,nil
            return hover
        end
    end
    -- Keep the amounts visible even if a long localized ingredient name needs a tooltip.
    local function cost(y,name,have,need)
        local amount=compact(have).." / "..compact(need)
        local right=width-6-GuiGetTextDimensions(gui,amount,scale)/scale
        local txt,short=fit(name,(right-9)*scale,scale)
        tint(muted)
        GuiText(gui,left+6*scale,top+y*scale,txt,scale)
        if short then GuiTooltip(gui,name,"") end
        tint(have>=need and green or gold)
        GuiText(gui,left+right*scale,top+y*scale,amount,scale)
        GuiTooltip(gui,name.."  "..have.." / "..need,"")
    end
    if salvage then
        label(body,tr("拆解","Dismantle"),gold)
        label(body+13,salvage.name)
        label(body+27,tr("奥术碎片 +","Arcane scrap +")..salvage.salvage_yield,green)
        label(body+39,tr("现有碎片 ","Current scrap ")..compact(model.scrap),muted)
        if button(260,6,body+53,tr("确认拆解","Dismantle item")) then
            dispatch("salvage",salvage_target)
            salvage_target=nil
        elseif button(261,6,body+65,tr("取消","Cancel")) then salvage_target=nil end
    elseif menu and selected then
        if button(240,6,body,tr("< 返回列表","< Projects")) then selected_project=nil; return hover end
        label(body+14,selected.name,gold)
        label(body+27,tr("当前：","Now: ")..selected.current)
        if selected.next then label(body+39,tr("升级后：","Next: ")..selected.next,green) end
        local y=body+51
        if #selected.costs>0 then
            label(y,tr("物料  库存 / 所需","Materials  stock / cost"),muted)
            for _,input in ipairs(selected.costs) do
                y=y+12
                cost(y,input.name,input.available,input.amount)
            end
            y=y+13
        end
        if selected.canBuy then
            local confirm=tab=="expansion" and tr("确认扩建","Confirm build") or tr("确认升级","Confirm upgrade")
            if button(241,6,y,confirm) then
                dispatch("buy_upgrade",{id=selected.id,level=selected.level})
                selected_project=nil
            end
        elseif selected.planned then label(y,tr("尚未开放","In development"),muted)
        elseif selected.maxed then label(y,tr("已完成","Complete"),green)
        else label(y,tr("所需物料不足","Insufficient stock"),gold) end
    elseif menu then
        local pages=math.max(1,math.ceil(#menu/projects_per_page))
        local current=math.min(project_pages[tab],pages)
        if pages>1 then
            if button(242,6,body,"<",current>1 and gold or muted) then current=math.max(1,current-1) end
            if button(243,width-14,body,">",current<pages and gold or muted) then current=math.min(pages,current+1) end
            tint(muted)
            GuiText(gui,left+(width/2-8)*scale,top+body*scale,current.."/"..pages,scale)
        end
        project_pages[tab]=current
        for i=1,projects_per_page do
            local item=menu[(current-1)*projects_per_page+i]
            if item and button(243+i,6,body+(pages>1 and 13 or 0)+(i-1)*13,item.name,item.planned and muted or white) then
                selected_project=item.id
                return hover
            end
        end
    elseif tab=="orders" then
        local y=body
        if #recipes>1 then
            if button(250,6,y,"<") then selected_recipe=recipes[(rindex-2)%#recipes+1].id; return hover end
            if button(251,width-14,y,">") then selected_recipe=recipes[rindex%#recipes+1].id; return hover end
            tint(muted)
            GuiText(gui,left+(width/2-8)*scale,top+y*scale,rindex.."/"..#recipes,scale)
            y=y+13
        end
        label(y,recipe.name.." ×"..recipe.output)
        for _,input in ipairs(recipe.inputs) do
            y=y+12
            cost(y,input.name,input.available,input.amount)
        end
        y=y+15
        if model.order_active then label(y,tr("生产中：","Queued: ")..model.order_name,green)
        elseif recipe.ready then
            if button(214,6,y,tr("从物料库存投料","Start batch from stock")) then dispatch("craft",{id=recipe.id}) end
        else label(y,recipe.reason or tr("材料或空位不足","Need stock or space"),muted) end
        label(y+13,model.reward_spent and tr("下次通关后入库","Delivered on next run's clear")
            or tr("本局通关后入库","Delivered on this run's clear"),muted)
        if model.debug and button(215,6,y+28,tr("模拟通关","Simulate clear"),gold,
            tr("每局仅结算一次通关奖励。","Uses this run's one clear reward.")) then dispatch("simulate") end
    else
        if button(216,6,body+3,tr("生成测试魔杖和混合瓶","Spawn wand and flask")) then dispatch("preview_items") end
        label(body+17,tr("在脚边拾取样品","Pick up the samples at your feet"),muted)
        if button(217,6,body+33,tr("重发测试针剂包","Reissue test pouch"),gold,
            tr("替换现有针剂包，内含两支激活剂。","Replace the current pouch with two doses.")) then dispatch("restock") end
    end
    return hover
end

local function draw_case(model, ox, oy, scale, sw, sh, tr, label, dispatch,layout,pw)
    local frame = GameGetFrameNum()
    local fresh = last_case_frame ~= frame - 1
    if fresh then drag,page,loading = nil,1,nil end
    last_case_frame = frame
    local wx, wy = DEBUG_GetMouseWorld()
    local cx, cy, cw, ch = GameGetCameraBounds()
    local mx, my = (wx-cx)*sw/cw, (wy-cy)*sh/ch
    local slots = {}
    -- Container rows advance by the native tile width, including its border.
    local qw,qh = GuiGetImageDimensions(gui,tile)
    local function slot(column,y,key,kind,name,icon,entity,left,top)
        local x = 8 + column * qw
        slots[#slots+1] = {x=(left or ox)+x*scale, y=(top or oy)+y*scale, key=key, kind=kind,
            name=name, icon=icon, entity=entity}
    end

    local standalone = model.mode=="container"
    if not standalone then
        local pages = math.ceil(model.capacity/3)
        page = math.min(page,pages)
        if pages>1 then
            local py=pw<145 and 56 or 5
            if GuiButton(gui,35,ox+(pw-72)*scale,oy+py*scale,"<",scale) and not drag then page=math.max(1,page-1) end
            label(pw-54,py,page.."/"..pages,38,muted)
            if GuiButton(gui,36,ox+(pw-15)*scale,oy+py*scale,">",scale) and not drag then page=math.min(pages,page+1) end
        end
        for i=1,math.min(3,model.capacity-(page-1)*3) do
            local n = (page-1)*3+i
            local v = model.secure_loot[n] or {}
            slot(i-1,25,"valuable",v.kind,v.name or tr("空格","Empty slot"),v.icon,v.id)
            slots[#slots].safeSlot,slots[#slots].dockSlot,slots[#slots].view=n,v.dockSlot,v
            slots[#slots].remaining,slots[#slots].count=v.remaining,v.count
        end
    end
    local popupY = standalone and 0 or -66
    if model.popup then
        if not standalone then
            GuiZSetForNextWidget(gui,-79)
            GuiImageNinePiece(gui,37,ox,oy+popupY*scale,pw*scale,61*scale,1)
        end
        label(8,popupY+5,tr("针剂包","Injector pouch"),pw-43,white)
        if GuiButton(gui,38,ox+(pw-34)*scale,oy+(popupY+5)*scale,tr("关闭","Close"),scale) then
            drag=nil
            dispatch("close_container")
            return
        end
        for i=1,model.pouchCapacity do
            local cell=model.cells[i]
            slot(i-1,popupY+23,"dose",cell and "dose",cell and tr("耐火激活剂","Fire injector") or tr("空格","Empty slot"))
            local v=slots[#slots]
            v.cell=i
            if cell then v.remaining,v.count=cell.remaining,cell.count end
        end
    end

    local perk_top
    if not standalone then
        perk_top=NHPerks.draw(gui,model,ox,oy,scale,pw,qw,qh,tr,slot,slots,function(action,args)
            if not fresh and not drag then dispatch(action,args) end
        end)
    end
    local stock_tip
    local panel_hover=false
    if layout then
        panel_hover=draw_workshop(model,layout,scale,sh,tr,dispatch,mx,my)
        local left,width=layout.left,layout.stash
        local cols=math.max(1,math.min(10,math.floor((width-16)/qw)))
        local tx,ty=8,22
        local tabs={}
        for i,t in ipairs(warehouse_tabs) do
            local name=tr(t[2],t[3])
            local text_width=GuiGetTextDimensions(gui,name,scale)/scale
            if tx>8 and tx+text_width>width-6 then tx,ty=8,ty+13 end
            tabs[i]={x=tx,y=ty,name=name}
            tx=tx+text_width+8
        end
        local grid_y=ty+15
        local content_height=qh+30+material_rows*11
        local height=folded and 20 or grid_y+content_height+18
        local top=sh-5-height*scale
        local warehouse_hover=mx>=left and mx<left+width*scale and my>=top and my<top+height*scale
        panel_hover=panel_hover or warehouse_hover
        if warehouse_hover and drag and drag.source.key=="native" and not folded and warehouse_tab~="materials"
            and drag.source.kind~="other" then
            local category=NHStore.category(drag.source.kind)
            warehouse_tab=category
        end
        GuiZSetForNextWidget(gui,-79)
        GuiImageNinePiece(gui,70,left,top,width*scale,height*scale,1)
        tint(gold)
        if GuiButton(gui,71,left+6*scale,top+3*scale,(folded and "[+] " or "[-] ")..tr("仓库","Stash"),scale) and not drag then
            folded,loading=not folded,nil
            return
        end
        if not folded then
            for i,t in ipairs(warehouse_tabs) do
                local pos=tabs[i]
                tint(t[1]==warehouse_tab and gold or muted)
                local bx,by=left+pos.x*scale,top+pos.y*scale
                local clicked=GuiButton(gui,74+i,bx,by,pos.name,scale)
                -- A stored bottle can cross between both pages without visiting the quick bar.
                local cross=drag and drag.source.kind=="potion" and
                    ((drag.source.key=="warehouse" and t[1]=="materials") or (drag.source.key=="docks" and t[1]=="containers"))
                local over=cross and mx>=bx and mx<bx+GuiGetTextDimensions(gui,pos.name,scale) and my>=by and my<by+10*scale
                if (clicked and not drag or over) and warehouse_tab~=t[1] then
                    warehouse_tab,loading=t[1],nil
                    return
                end
            end
            local bulk=warehouse_tab=="materials"
            local per_page=bulk and material_rows*2 or cols*math.floor(content_height/qh)
            local capacity=model.warehouse_capacity[warehouse_tab]
            local pages
            if bulk then pages=math.max(1,math.ceil(#model.materials/per_page))
            else pages=math.max(1,math.ceil(capacity/per_page)) end
            local current=warehouse_pages[warehouse_tab] or 1
            local page_no=warehouse_pager(left+4*scale,top+(height-17)*scale,width-8,scale,current,pages)
            if current~=page_no then loading=nil end
            warehouse_pages[warehouse_tab]=page_no
            if bulk then
                local docks,materials=model.docks,model.materials
                local column_width=math.floor((width-12)/2)
                for n=1,2 do
                    local dock=docks[n] or {}
                    local x0=left+(n-1)*column_width*scale
                    local title=n==1 and tr("药瓶","Flask") or tr("粉末袋","Powder pouch")
                    slot(0,grid_y,"docks",dock.kind,dock.name or title,dock.icon,dock.id,x0,top)
                    slots[#slots].safeSlot,slots[#slots].view=n,dock
                    local x=x0+(qw+10)*scale
                    local title_fit=fit(title,(column_width-qw-10)*scale,scale)
                    GuiText(gui,x,top+grid_y*scale,title_fit,scale)
                    if dock.id then
                        GuiText(gui,x,top+(grid_y+10)*scale,compact(dock.used).."/"..compact(dock.capacity),0.85*scale)
                        tint(dock.used>0 and gold or muted)
                        if GuiButton(gui,180+n,x0+8*scale,top+(grid_y+qh+1)*scale,tr("全部卸入","Unload all"),scale)
                            and not drag and dock.used>0 then
                            dispatch("material_transfer",{container="docks",slot=n,storedId=dock.id,unload=true})
                            return
                        end
                    end
                end
                local y=grid_y+qh+15
                GuiText(gui,left+8*scale,top+y*scale,tr("库存 ","Stock ")..#materials.."/"..capacity,scale)
                if #materials==0 then
                    tint(muted)
                    GuiText(gui,left+8*scale,top+(y+13)*scale,tr("库存为空","Empty"),scale)
                end
                local held_target
                for i=1,per_page do
                    local mat=materials[(page_no-1)*per_page+i]
                    if mat then
                        local col=(i-1)%2
                        local row=math.floor((i-1)/2)+1
                        local row_y=top+(y+11*row)*scale
                        local start_x=left+(8+col*column_width)*scale
                        local end_x=start_x+(column_width-4)*scale
                        local dock=docks[mat.slot]
                        local enabled=dock and dock.used<dock.capacity
                        local amount=compact(mat.amount)
                        local bx=end_x-9*scale
                        local count_x=bx-4*scale-GuiGetTextDimensions(gui,amount,scale)
                        local name=fit(mat.name,count_x-start_x-3*scale,scale)
                        GuiText(gui,start_x,row_y,name,scale)
                        GuiText(gui,count_x,row_y,amount,scale)
                        tint(enabled and gold or muted)
                        GuiButton(gui,186+i,bx,row_y,"+",scale)
                        local hover=mx>=start_x and mx<end_x and my>=row_y and my<row_y+11*scale
                        if hover then
                            local tip=enabled and tr("点按 1 单位，按住加速","Click for 1 unit; hold to load faster")
                                or (not mat.slot and tr("无匹配容器","No compatible container")
                                or (dock and tr("容器已满","Container full") or tr("请先放入对应容器","Dock a compatible container first")))
                            stock_tip={mat.name.."  "..string.format("%.0f",mat.amount),tip}
                        end
                        if enabled and hover and not drag and not fresh then
                            if InputIsMouseButtonJustDown(1) then
                                loading={name=mat.key,id=dock.id,start=frame}
                            end
                            if loading and loading.name==mat.key and loading.id==dock.id and InputIsMouseButtonDown(1) then
                                held_target=true
                                local elapsed=frame-loading.start
                                if elapsed==0 or (elapsed>=24 and (elapsed-24)%6==0) then
                                    local batch=elapsed==0 and 1 or math.min(100,5*2^math.floor((elapsed-24)/24))
                                    dispatch("material_transfer",{container="docks",slot=mat.slot,storedId=dock.id,material=mat.key,amount=batch})
                                end
                            end
                        end
                    end
                end
                if not held_target then loading=nil end
            else
                local rows=model.warehouse[warehouse_tab] or {}
                for i=0,math.min(per_page,capacity-(page_no-1)*per_page)-1 do
                    local n=(page_no-1)*per_page+i+1
                    local v=rows[n] or {}
                    slot(i%cols,grid_y+math.floor(i/cols)*qh,"warehouse",v.kind,v.name or tr("空格","Empty slot"),v.icon,v.id,left,top)
                    local target=slots[#slots]
                    target.view=v
                    target.safeSlot,target.remaining,target.count,target.dockSlot=n,v.remaining,v.count,v.dockSlot
                end
            end
        end
    else
        loading=nil
        if drag and (drag.source.key=="warehouse" or drag.source.key=="docks") then drag=nil end
    end

    local native_x = tonumber(MagicNumbersGetValue("UI_BARS_POS_X"))
    local native_y = tonumber(MagicNumbersGetValue("UI_BARS_POS_Y"))
    local full_offset = tonumber(MagicNumbersGetValue("UI_FULL_INVENTORY_OFFSET_X"))
    local fw,fh = GuiGetImageDimensions(gui,full_tile)
    local hovered
    -- Hit-test the vanilla widgets without drawing over them or consuming
    -- their clicks. Normal reordering and wand editing remain engine-owned.
    for _, v in ipairs(model.native_slots) do
        local full = v.lane=="spell"
        local w,h = full and fw or qw,full and fh or qh
        local x = native_x + (full and full_offset or 0) + v.col*w
        local y = native_y + v.yslot*h
        if (not standalone or not full) and mx>=x and my>=y and mx<x+w and my<y+h then hovered=v; break end
    end
    if panel_hover or (perk_top and mx>=ox and mx<ox+pw*scale and my>=perk_top and my<oy) then hovered={key="panel"} end
    for _,v in ipairs(slots) do
        if mx>=v.x and my>=v.y and mx<v.x+qw*scale and my<v.y+qh*scale then hovered=v end
    end
    if not hovered and mx>=ox and my>=oy+(model.popup and popupY or 0)*scale and mx<ox+pw*scale and my<oy+72*scale then
        hovered = {key="panel"}
    end
    if drag and model.revision~=drag.revision then drag=nil end
    if model.salvage_enabled and hovered and hovered.key=="warehouse" and hovered.view and hovered.view.salvage_yield
        and not fresh and not drag and InputIsMouseButtonJustDown(2) then
        salvage_target={id=hovered.entity,kind=hovered.kind,slot=hovered.safeSlot}
        workshop_folded=false
    end
    if not fresh and InputIsMouseButtonJustDown(1) and hovered and hovered.kind and hovered.kind~="reserved" then
        drag={source=hovered,revision=model.revision,x=mx,y=my}
    end
    if drag and ((mx-drag.x)^2+(my-drag.y)^2)>9*scale^2 then drag.moved=true end
    local source=drag and drag.source
    local function drop(target)
        if not source or not target then return end
        if source.kind=="pouch" and source.key==target.key and source.entity==target.entity
            and source.safeSlot==target.safeSlot and not drag.moved then
            return "open_container",source,source.safeSlot
        end
        local from_store=source.key=="valuable" or source.key=="warehouse"
        local to_store=target.key=="valuable" or target.key=="warehouse"
        if model.mode=="case" and source.kind=="perk" and not target.kind then
            if from_store and target.key=="perk" then return "equip_stored_perk",source end
            if source.key=="perk" and to_store and (target.key=="valuable" or warehouse_tab=="supplies") then
                return "store_equipped_perk",source
            end
        end
        if source.kind=="pouch" and from_store and source.key==target.key and not target.kind then
            return "move_pouch",source,target.safeSlot
        end
        if target.key=="docks" and not target.kind and source.kind=="potion" and source.dockSlot==target.safeSlot then
            if source.key=="native" then return "place",source,target.safeSlot end
            if from_store then return "move_dock",source,target.safeSlot end
        end
        if source.key=="docks" and to_store and not target.kind and (target.key=="valuable" or warehouse_tab=="containers") then
            return "move_dock",source,target.safeSlot
        end
        local canStack = source.kind=="dose" and target.kind=="dose"
            and (source.remaining or model.maxUses)==model.maxUses and (target.remaining or model.maxUses)==model.maxUses
        if from_store and source.kind=="dose" and source.key==target.key
            and source.safeSlot~=target.safeSlot and (not target.kind or canStack) then
            return "move_safe_dose",source,target.safeSlot
        end
        if source.key=="warehouse" and target.key=="warehouse" and not target.kind then
            return "move_warehouse",source,target.safeSlot
        end
        if source.key=="dose" and target.key=="dose" and source.cell~=target.cell and (not target.kind or canStack) then
            return "move_cell",source
        end
        if source.key=="dose" and to_store and (target.key~="warehouse" or warehouse_tab=="supplies") and (not target.kind or canStack) then
            return "unpack_dose",source,target.safeSlot
        end
        if from_store and source.kind=="dose" and target.key=="dose" and (not target.kind or canStack) then
            return "pack_dose",source,source.safeSlot
        end
        if source.key=="native" then
            if target.key=="perk" and not target.kind and source.kind=="perk" then return "equip_perk",source,target.perkSlot end
            if target.key=="dose" and model.popup and source.kind=="dose" and (not target.kind or canStack) then return "place",source end
            if to_store and (not target.kind or canStack) and source.kind~="other"
                and (target.key~="warehouse" or NHStore.category(source.kind)==warehouse_tab) then
                return "place",source,target.safeSlot
            end
            if target.key~="native" then return "cancel_native",source end
        elseif target.key=="native" and not target.entity then
            local lane=source.kind=="spell" and "spell" or (source.kind=="wand" and "wand" or "tool")
            if target.lane~=lane then return end
            if source.key=="perk" then return "unequip_perk",target,source.perkSlot,source.entity end
            if source.kind=="pouch" then return "take_pouch",target,source.safeSlot end
            if from_store or source.key=="docks" then return "secure_withdraw",target,source.safeSlot,source.entity end
            if source.key=="dose" then return "take_dose",target end
        end
    end
    local function sprite(v,id,x,y,alpha)
        local image = v.icon
        if type(image) ~= "string" or not image:match("%.png$") then image=icons[v.kind] end
        if not image then
            GuiText(gui,x-2*scale,y-4*scale,"?",scale)
            return
        end
        local w,h = GuiGetImageDimensions(gui,image)
        if not w or not h or w<=0 or h<=0 then return end
        local zoom = math.min(1,(qw-3)/w,(qh-3)/h)*scale
        GuiZSetForNextWidget(gui,-83)
        local view=v.view
        if view and view.potion then
            if view.tint==nil then view.tint=NHPotion.contentsColor(view.potion) or false end
            if view.tint then
                local c=view.tint
                GuiColorSetForNextWidget(gui,c%256/255,math.floor(c/256)%256/255,math.floor(c/65536)%256/255,1)
            end
        end
        GuiImage(gui,id,x-w*zoom/2,y-h*zoom/2,image,alpha,zoom)
    end
    for i,v in ipairs(slots) do
        local placement=drop(v)
        if placement=="place" or placement=="equip_stored_perk" or placement=="store_equipped_perk" then tint(green) end
        GuiImage(gui,1000+i,v.x,v.y,tile,1,scale)
        if v.kind=="reserved" then GuiText(gui,v.x+5*scale,v.y+3*scale,"...",scale)
        elseif v.kind then sprite(v,2000+i,v.x+qw*scale/2,v.y+qh*scale/2,source and source.key==v.key and source.safeSlot==v.safeSlot and source.cell==v.cell and source.perkSlot==v.perkSlot and 0.35 or 1)
        end
        if v.kind=="dose" then
            local remaining=v.remaining or model.maxUses
            local caption=(v.count or 1)>1 and ("×"..v.count) or (remaining.."/"..model.maxUses)
            GuiZSetForNextWidget(gui,-84)
            GuiText(gui,v.x,v.y+(v.key=="warehouse" and qh-7 or qh-1)*scale,caption,0.8*scale)
        end
    end
    local tip=stock_tip
    if source then
        if source.key~="native" then sprite(source,3000,mx,my,0.95) end
        local action=hovered and drop(hovered)
        tip={action and action~="cancel_native" and tr("松开放置","Release to place") or tr("拖至对应空格","Drag to a matching slot")}
    elseif hovered and hovered.kind and hovered.key~="native" then
        tip=item_details(hovered,model,tr)
        if model.salvage_enabled and hovered.key=="warehouse" and hovered.view.salvage_yield then
            tip[#tip+1]=tr("右键预览拆解","Right-click to preview dismantling")
        end
    end
    if tip then cursor_tip(tip,mx,my,sw,sh,scale) end
    if standalone or pw>=145 or model.capacity<=3 then
        label(8,56,(model.status~="" and model.status) or tr("拖动物品以存取","Drag items to transfer"),pw-16,muted)
    end
    if drag and InputIsMouseButtonJustUp(1) then
        local action, arg, safeSlot, storedId = drop(hovered)
        drag=nil
        if action=="equip_stored_perk" or action=="store_equipped_perk" then
            dispatch(action,{entity=source.entity,container=storage_key(source.key) or storage_key(hovered.key),
                storageSlot=source.safeSlot or hovered.safeSlot,perkSlot=source.perkSlot or hovered.perkSlot})
            return
        end
        if action then
            local request = {parent=arg.parent,lane=arg.lane,xslot=arg.xslot,yslot=arg.yslot,
                entity=arg.entity,safeSlot=safeSlot,storedId=storedId,from=arg.safeSlot,kind=source.kind,
                source=storage_key(source.key),destination=storage_key(hovered.key),
                container=(source.key=="docks" or hovered.key=="docks") and "docks" or storage_key(source.key) or storage_key(hovered.key) or "safe",
                sourceCell=source.cell,targetCell=hovered and hovered.cell,
                intoContainer=hovered and hovered.key=="dose"}
            dispatch(action,request)
        end
    elseif not InputIsMouseButtonDown(1) then drag=nil end
end

function NHUI.draw(model, dispatch)
    if not model.open then drag,last_case_frame,salvage_target=nil,nil,nil end
    if not gui then gui = GuiCreate() end
    GuiStartFrame(gui)
    GuiZSet(gui, -80)

    local sw, sh = GuiGetScreenDimensions(gui)
    local function tr(zh, en) return model.lang == "zh" and zh or en end
    if not model.open then
        if not model.near then return end
        local caption = tr("打开物品栏：仓库和工坊", "Open inventory for stash and workshop")
        local text_w = GuiGetTextDimensions(gui, caption)
        local x = math.floor((sw - text_w) / 2)
        local y = sh - 20
        GuiZSetForNextWidget(gui, -79)
        GuiImageNinePiece(gui, 1, x - 5, y - 2, text_w + 10, 15, 0.96)
        tint(gold)
        GuiText(gui, x, y, caption)
        return
    end

    local at_home=model.near and model.mode=="case"
    local pw,ph=187,72
    local s=math.min(1,(sw-10)/(at_home and 310 or pw),(sh-10)/(at_home and 173 or ph))
    if s<=0 then return end
    local layout
    if at_home then
        layout=home_layout(sw,s,GuiGetImageDimensions(gui,tile))
        pw=layout.secure
    end
    local ox,oy=sw-pw*s-5,sh-ph*s-5
    GuiZSetForNextWidget(gui, -79)
    GuiImageNinePiece(gui, 10, ox, oy, pw*s, ph*s, 1)

    local function label(x, y, value, w, color)
        local txt, truncated = fit(value, w * s, s)
        tint(color or white)
        GuiText(gui, ox + x * s, oy + y * s, txt, s)
        if truncated then GuiTooltip(gui, tostring(value), "") end
    end
    if model.mode=="case" then label(9,5,tr("安全箱","Secure case"),pw-16,white) end
    draw_case(model,ox,oy,s,sw,sh,tr,label,dispatch,layout,pw)
end
