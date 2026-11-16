NHUI = {}

local gui
local tab = "orders"
local warehouse_tab, warehouse_page, folded = "wand", 1, false
local warehouse_tabs = {
    {"wand","魔杖","Wands"}, {"spell","法术","Spells"}, {"containers","容器","Containers"},
    {"supplies","消耗品","Supplies"}, {"materials","物料","Materials"},
}
local recipe_choice = 1
local panel_width, panel_height = 314, 196
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
local material_page,loading=1,nil
local material_rows=3
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

local function draw_case(model, ox, oy, scale, sw, sh, tr, label, dispatch)
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
            if GuiButton(gui,35,ox+110*scale,oy+5*scale,"<",scale) and not drag then page=math.max(1,page-1) end
            label(130,5,page.."/"..pages,31,muted)
            if GuiButton(gui,36,ox+167*scale,oy+5*scale,">",scale) and not drag then page=math.min(pages,page+1) end
        end
        for i=1,math.min(3,model.capacity-(page-1)*3) do
            local n = (page-1)*3+i
            local v = model.secure_loot[n] or {}
            slot(i-1,25,"valuable",v.kind,v.name or tr("空格","Empty slot"),v.icon,v.id)
            slots[#slots].safeSlot,slots[#slots].dockSlot=n,v.dockSlot
            slots[#slots].remaining,slots[#slots].count=v.remaining,v.count
        end
    end
    local popupY = standalone and 0 or -66
    if model.popup then
        if not standalone then
            GuiZSetForNextWidget(gui,-79)
            GuiImageNinePiece(gui,37,ox,oy+popupY*scale,187*scale,61*scale,1)
        end
        label(8,popupY+5,tr("针剂包","Injector pouch"),120,white)
        if GuiButton(gui,38,ox+148*scale,oy+(popupY+5)*scale,tr("关闭","Close"),scale) then
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

    local warehouse_hover=false
    if model.near and not standalone then
        local left=5*scale
        local available=(ox-left)/scale-5
        local above=available<100
        local width=math.min(230,above and (sw/scale-10) or available)
        local cols=math.max(1,math.min(10,math.floor((width-16)/qw)))
        local per_page=cols*2
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
        local height=folded and 20 or grid_y+2*qh+4
        if not folded and warehouse_tab=="materials" then height=grid_y+2*qh+16+material_rows*13 end
        local bottom=above and (oy+(model.popup and popupY or 0)*scale) or sh
        local top=bottom-(height+5)*scale
        warehouse_hover=mx>=left and mx<left+width*scale and my>=top and my<top+height*scale
        if warehouse_hover and drag and drag.source.key=="native" and not folded and warehouse_tab~="materials"
            and drag.source.kind~="other" then
            local category=NHStore.category(drag.source.kind)
            if category~=warehouse_tab then warehouse_tab,warehouse_page=category,1 end
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
                    warehouse_tab,warehouse_page,loading=t[1],1,nil
                    return
                end
            end
            if warehouse_tab=="materials" then
                local docks,materials=model.docks,model.materials
                for n=1,2 do
                    local dock=docks[n] or {}
                    local y=grid_y+(n-1)*qh
                    local title=n==1 and tr("药瓶","Flask") or tr("粉末袋","Powder pouch")
                    slot(0,y,"docks",dock.kind,dock.name or title,dock.icon,dock.id,left,top)
                    slots[#slots].safeSlot=n
                    local x=left+(qw+11)*scale
                    local caption,trimmed=fit(title,(width-qw-(dock.id and 63 or 16))*scale,scale)
                    GuiText(gui,x,top+y*scale,caption,scale)
                    if trimmed then GuiTooltip(gui,title,"") end
                    if dock.id then
                        GuiText(gui,x,top+(y+9)*scale,dock.used.."/"..dock.capacity,0.85*scale)
                        tint(dock.used>0 and gold or muted)
                        if GuiButton(gui,180+n,left+(width-49)*scale,top+(y+4)*scale,tr("全部卸入","Unload all"),scale)
                            and not drag and dock.used>0 then
                            dispatch("material_transfer",{container="docks",slot=n,storedId=dock.id,unload=true})
                            return
                        end
                    end
                end
                local y=grid_y+2*qh+2
                local pages=math.max(1,math.ceil(#materials/material_rows))
                material_page=math.min(material_page,pages)
                GuiText(gui,left+8*scale,top+y*scale,tr("库存","Stock"),scale)
                if pages>1 then
                    if GuiButton(gui,184,left+(width-64)*scale,top+y*scale,"<",scale) then material_page=math.max(1,material_page-1) end
                    GuiText(gui,left+(width-51)*scale,top+y*scale,material_page.."/"..pages,scale)
                    if GuiButton(gui,185,left+(width-16)*scale,top+y*scale,">",scale) then material_page=math.min(pages,material_page+1) end
                end
                if #materials==0 then
                    tint(muted)
                    GuiText(gui,left+8*scale,top+(y+13)*scale,tr("库存为空","Empty"),scale)
                end
                local held_target
                for i=1,material_rows do
                    local mat=materials[(material_page-1)*material_rows+i]
                    if mat then
                        local row_y=top+(y+13*i)*scale
                        local dock=docks[mat.slot]
                        local enabled=dock and dock.used<dock.capacity
                        local amount=tostring(mat.amount)
                        local count_x=left+(width-43)*scale-GuiGetTextDimensions(gui,amount,scale)
                        local name,trimmed=fit(mat.name,count_x-left-11*scale,scale)
                        GuiText(gui,left+8*scale,row_y,name,scale)
                        if trimmed then GuiTooltip(gui,mat.name,"") end
                        GuiText(gui,count_x,row_y,amount,scale)
                        local bx=left+(width-36)*scale
                        tint(enabled and gold or muted)
                        GuiButton(gui,186+i,bx,row_y,tr("装入","Load"),scale)
                        local hover=mx>=bx and mx<left+(width-3)*scale and my>=row_y and my<row_y+12*scale
                        if hover then
                            local tip=enabled and tr("点按 1 单位，按住加速","Click for 1 unit; hold to load faster")
                                or (not mat.slot and tr("无匹配容器","No compatible container")
                                or (dock and tr("容器已满","Container full") or tr("请先放入对应容器","Dock a compatible container first")))
                            GuiTooltip(gui,tip,"")
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
                local pages=1+math.floor((model.warehouse_last[warehouse_tab] or 0)/per_page)
                warehouse_page=math.min(warehouse_page,pages)
                if pages>1 then
                    if GuiButton(gui,72,left+(width-65)*scale,top+3*scale,"<",scale) and not drag then warehouse_page=math.max(1,warehouse_page-1) end
                    GuiText(gui,left+(width-52)*scale,top+3*scale,warehouse_page.."/"..pages,scale)
                    if GuiButton(gui,73,left+(width-16)*scale,top+3*scale,">",scale) and not drag then warehouse_page=math.min(pages,warehouse_page+1) end
                end
                for i=0,per_page-1 do
                    local n=(warehouse_page-1)*per_page+i+1
                    local v=rows[n] or {}
                    slot(i%cols,grid_y+math.floor(i/cols)*qh,"warehouse",v.kind,v.name or tr("空格","Empty slot"),v.icon,v.id,left,top)
                    local target=slots[#slots]
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
    if warehouse_hover then hovered={key="panel"} end
    for _,v in ipairs(slots) do
        if mx>=v.x and my>=v.y and mx<v.x+qw*scale and my<v.y+qh*scale then hovered=v end
    end
    if not hovered and mx>=ox and my>=oy+(model.popup and popupY or 0)*scale and mx<ox+187*scale and my<oy+72*scale then
        hovered = {key="panel"}
    end
    if drag and model.revision~=drag.revision then drag=nil end
    if not fresh and InputIsMouseButtonJustDown(1) and hovered and hovered.kind then
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
            if target.key=="dose" and model.popup and source.kind=="dose" and (not target.kind or canStack) then return "place",source end
            if to_store and (not target.kind or canStack) and source.kind~="other"
                and (target.key~="warehouse" or NHStore.category(source.kind)==warehouse_tab) then
                return "place",source,target.safeSlot
            end
            if target.key~="native" then return "cancel_native",source end
        elseif target.key=="native" and not target.entity then
            local lane=source.kind=="spell" and "spell" or (source.kind=="wand" and "wand" or "tool")
            if target.lane~=lane then return end
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
        GuiImage(gui,id,x-w*zoom/2,y-h*zoom/2,image,alpha,zoom)
    end
    for i,v in ipairs(slots) do
        if drop(v)=="place" then tint(green) end
        GuiImage(gui,100+i,v.x,v.y,tile,1,scale)
        if v.kind then sprite(v,130+i,v.x+qw*scale/2,v.y+qh*scale/2,source and source.key==v.key and source.safeSlot==v.safeSlot and source.cell==v.cell and 0.35 or 1)
        end
        if v.kind=="dose" then
            local remaining=v.remaining or model.maxUses
            local caption=(v.count or 1)>1 and ("×"..v.count) or (remaining.."/"..model.maxUses)
            GuiZSetForNextWidget(gui,-84)
            GuiText(gui,v.x,v.y+(v.key=="warehouse" and qh-7 or qh-1)*scale,caption,0.8*scale)
        end
    end
    local hint = hovered and hovered.name
    if hovered and hovered.kind=="pouch" then hint=tr("点击打开，拖动移动","Click to open or drag to move") end
    if hovered and hovered.kind=="dose" then hint=tr("耐火激活剂 · 耐久 ","Fire injector · durability ")..(hovered.remaining or model.maxUses).."/"..model.maxUses end
    if source then
        if source.key~="native" then sprite(source,160,mx,my,0.95) end
        if hovered and drop(hovered) and drop(hovered)~="cancel_native" then hint=tr("松开放置", "Release to place")
        else hint=tr("拖至对应空格", "Drag to a matching slot") end
    end
    label(8,56,hint or (model.status ~= "" and model.status) or tr("拖动物品以存取", "Drag items to transfer"),172,muted)
    if drag and InputIsMouseButtonJustUp(1) then
        local action, arg, safeSlot, storedId = drop(hovered)
        drag=nil
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
    if not model.open or model.mode == "home" then drag,last_case_frame=nil,nil end
    if not gui then gui = GuiCreate() end
    GuiStartFrame(gui)
    GuiZSet(gui, -80)

    local sw, sh = GuiGetScreenDimensions(gui)
    local function tr(zh, en) return model.lang == "zh" and zh or en end
    if not model.open then
        if not model.near then return end
        local caption = tr("物品栏：仓库  [H] 工坊", "Inventory: stash  [H] Workshop")
        local text_w = GuiGetTextDimensions(gui, caption)
        local x = math.floor((sw - text_w) / 2)
        local y = sh - 20
        GuiZSetForNextWidget(gui, -79)
        GuiImageNinePiece(gui, 1, x - 5, y - 2, text_w + 10, 15, 0.96)
        tint(gold)
        GuiText(gui, x, y, caption)
        return
    end

    local case = model.mode == "case" or model.mode == "container"
    local pw, ph = case and 187 or panel_width, case and 72 or panel_height
    local s = math.min(1, (sw - 10) / pw, (sh - 10) / ph)
    if s <= 0 then return end
    local ox = case and sw - pw*s - 5 or math.floor((sw - pw*s)/2)
    local oy = case and sh - ph*s - 5 or math.floor((sh - ph*s)/2)
    GuiZSetForNextWidget(gui, -79)
    GuiImageNinePiece(gui, 10, ox, oy, pw*s, ph*s, 1)

    local function label(x, y, value, w, color)
        local txt, truncated = fit(value, w * s, s)
        tint(color or white)
        GuiText(gui, ox + x * s, oy + y * s, txt, s)
        if truncated then GuiTooltip(gui, tostring(value), "") end
    end
    local function button(id, x, y, txt, color)
        tint(color or gold)
        local clicked = GuiButton(gui, id, ox + x * s, oy + y * s, txt, s)
        return clicked
    end
    local next_action, param
    local function command(id, x, y, txt, action, arg)
        if button(id, x, y, txt) then next_action, param = action, arg end
    end

    if model.mode~="container" then
        label(9, 5, case and tr("安全箱", "Secure case") or tr("藏身处", "Hideout"), case and 98 or 198, white)
    end
    if case then
        draw_case(model,ox,oy,s,sw,sh,tr,label,dispatch)
        return
    end

    command(11,252,5,tr("关闭","Close"),"close")
    local tabs = {
        { "orders", tr("生产", "Production") },
    }
    if model.debug then tabs[#tabs + 1] = { "samples", tr("测试物资", "Test supplies") } end
    if tab == "samples" and not model.debug then tab = "orders" end
    local tx = 9
    if not case then
        for i, t in ipairs(tabs) do
            local active = tab == t[1]
            local title = active and ("[" .. t[2] .. "]") or t[2]
            if button(20 + i, tx, 24, title, active and gold or muted) then tab = t[1] end
            tx = tx + GuiGetTextDimensions(gui, "[" .. t[2] .. "]", s) / s + 12
        end
    end

    if tab == "orders" then
        label(10, 42, tr("稳定传送液   500 单位", "Stable teleportatium   500 units"), 293)
        label(10, 56, tr("每批投入不稳定传送液 250、黏液 250。", "One batch takes 250 unstable teleportatium and 250 slime."), 293, muted)
        label(10, 71, tr("订单   ", "Order   ") .. tostring(model.order or ""), 293, green)
        if not model.order_active then
            local choices = model.recipe_indices or {}
            local total = #choices + (model.batch_available and 1 or 0)
            recipe_choice = math.max(1, math.min(recipe_choice, total))
            if total == 0 then
                label(10, 89, tr("将两种原料存入仓库，可用同瓶或分瓶。", "Deposit both ingredients in one or more flasks."), 293, muted)
            else
                local index = choices[recipe_choice] or 0
                if index == 0 then
                    label(10, 88, tr("跨瓶取料", "From multiple flasks"), 228)
                    if model.batch_sources and model.batch_sources ~= "" then
                        GuiTooltip(gui, tr("投料瓶", "Source flasks"), model.batch_sources)
                    end
                else
                    local name = model.loot[index] or ""
                    label(10, 88, tr("投料瓶  #", "Source  #") .. index .. "  " .. name, 228)
                end
                if total > 1 then
                    if button(53, 252, 88, "<") then recipe_choice = (recipe_choice - 2) % total + 1 end
                    if button(54, 278, 88, ">") then recipe_choice = recipe_choice % total + 1 end
                end
                local start = index == 0 and tr("按仓库顺序投料", "Start batch in stash order")
                    or tr("用此瓶投料", "Start batch with this flask")
                command(50, 10, 105, start, "order", index)
            end
        end
        local timing = model.reward_spent and tr("本局奖励已结算，订单待下局通关后送入仓库。", "Clear the next run to deliver the flask to the stash.")
            or tr("完成普通结局后，成品药瓶进入仓库。", "Clear a normal ending to deliver the flask to the stash.")
        label(10, 122, timing, 293, muted)
        if model.debug then
            if model.reward_spent then
                command(52, 10, 140, tr("测试：再次模拟通关", "Test: repeat simulation"), "simulate")
                label(10, 154, tr("本局已结算，重复模拟不会追加奖励。", "Already settled. Repeating gives no extra reward."), 293, muted)
            else
                command(52, 10, 140, tr("测试：模拟本局通关", "Test: simulate clear"), "simulate")
                label(10, 154, tr("模拟会用掉本局唯一一次通关奖励。", "Simulation spends this run's one clear reward."), 293, muted)
            end
        end
    else
        command(62, 10, 45, tr("生成测试魔杖与混合药瓶", "Spawn sample wand and mixed flask"), "preview_items")
        label(10, 62, tr("拾取样品后打开原版物品栏，拖入仓库。", "Pick up a sample, open your inventory and drag it into the stash."), 293, muted)
        command(60, 10, 89, tr("重发测试针剂包", "Reissue test pouch"), "restock")
        label(10, 106, tr("替换当前针剂包，在安全箱放入两支激活剂。", "Replaces your pouch with two doses in the secure case."), 293, muted)
    end
    if model.status and model.status ~= "" then label(10, 175, model.status, 293, green) end
    if next_action then dispatch(next_action, param) end
end
