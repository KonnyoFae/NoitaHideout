NHUI = {}

local gui
local tab = "orders"
local warehouse_tab, folded = "wand", false
local warehouse_pages = {}
local bank_amount=1
local bank_amounts={1,10,100,1000}
local warehouse_tabs = {
    {"wand","魔杖","Wands"}, {"spell","法术","Spells"}, {"containers","容器","Containers"},
    {"supplies","消耗品","Supplies"}, {"equipment","装备","Equipment"}, {"materials","物料","Materials"},
    {"bank","存钱罐","Piggy bank"}, {"essences","精华","Essences"}, {"collection","藏品","Collection"},
}
local workshop_folded=false
local list_pages={}
local entries_per_page=5
local recipe_category="alchemy"
local alchemy_mode="synthesis"
local shop_category="materials"
local selected_entry,salvage_target
local farm_page,selected_plot="plots",nil
local livestock_page,selected_pen="pens",nil
local work_tabs={
    {key="orders",id=212,zh="工坊",en="Workshop"},
    {key="expansion",id=218,zh="扩建",en="Build"},
    {key="upgrade",id=219,zh="升级",en="Upgrades"},
    {key="shop",id=220,zh="商店",en="Shop"},
    {key="farm",id=221,zh="种植",en="Farm"},
    {key="livestock",id=223,zh="畜牧",en="Livestock"},
    {key="samples",id=213,zh="测试物资",en="Supplies"},
}
local recipe_tabs={
    {key="alchemy",id=250,zh="炼金",en="Alchemy"},
    {key="medical",id=251,zh="医疗",en="Medical"},
    {key="weapons",id=252,zh="武器",en="Weapons"},
    {key="equipment",id=253,zh="装备",en="Equipment"},
    {key="food",id=222,zh="食物",en="Food"},
}
local alchemy_tabs={
    {key="synthesis",id=254,zh="炼成",en="Synthesis"},
    {key="decomposition",id=255,zh="分解",en="Decomposition"},
}
local shop_tabs={
    {key="materials",id=256,zh="物料",en="Materials"},
    {key="supplies",id=257,zh="消耗品",en="Consumables"},
    {key="livestock",id=259,zh="幼畜",en="Youngstock"},
}
local farm_tabs={
    {key="plots",id=410,zh="田地",en="Plots"},
    {key="stock",id=411,zh="农产库存",en="Crop stock"},
}
local livestock_tabs={
    {key="pens",id=440,zh="栏舍",en="Pens"},
    {key="produce",id=441,zh="畜产库存",en="Produce"},
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
            lines[#lines+1]=NHPotion.materialName(name,model.lang).."  "..string.format("%.0f",record.materials[name])
        end
        return lines
    end
    if slot.kind=="pouch" or slot.kind=="card_wallet" then
        local details={slot.name,tr("点击打开，拖动移动","Click to open or drag to move")}
        if slot.view and slot.view.doses then
            table.insert(details,2,tr("针剂数量 ","Injectors: ")..slot.view.doses)
        end
        return details
    end
    if slot.kind=="summon_card" then
        local species=NHCompanions.species[slot.species]
        local lines={species and tr(species.zh,species.en) or slot.name,
            tr("耐久 ","Durability ")..slot.remaining.."/"..NHCompanions.durability,
            tr("数量 ","Count ")..string.format("%.0f",slot.count or 1)}
        if not species or not model.affinityPoints then return lines end
        local points=model.affinityPoints(slot.species)
        local tier=NHAffinity.tier(points)
        local bonus=NHCompanions.bonuses[tier]
        local affinity=tr("好感度 ","Affinity ")..points.."/100"
        local nextTier=NHAffinity.thresholds[tier+2]
        lines[#lines+1]=nextTier and (affinity..tr("   下一阶段 ","   Next at ")..nextTier) or affinity
        if slot.species=="dryad" then
            lines[#lines+1]=tr("毒泥免疫","Toxic sludge immunity")
        elseif slot.species=="minotaur" then
            lines[#lines+1]=tr("近战免疫","Melee immunity")
            if bonus.shieldRecharge>0 then
                local rate=math.floor(100*bonus.shieldRecharge/NHCompanions.bonuses[3].shieldRecharge+0.5)
                lines[#lines+1]=string.format(tr("飞弹护盾 · 原版充能速度的 %d%%","Projectile shield at %d%% of normal recharge"),rate)
            end
        elseif slot.species=="griffin" then
            lines[#lines+1]=tr("加快飞行上升速度","Faster levitation")
            if bonus.flightPercent>0 then
                lines[#lines+1]=string.format(tr("每秒恢复 %d%% 飞行能量","Restores %d%% flight fuel per second"),bonus.flightPercent)
            end
        end
        local healSeconds=slot.species=="flower_fairy" and bonus.fairySeconds or (slot.species=="dryad" and bonus.dryadSeconds)
        if healSeconds and healSeconds>0 then
            lines[#lines+1]=string.format(tr("每 %d 秒恢复 1 HP","Heals 1 HP every %d s"),healSeconds)
        end
        lines[#lines+1]=string.format(tr("每结伴移动 %d 秒有 25%% 概率赠物","25%% gift chance per %d s of travel"),bonus.giftSeconds)
        return lines
    end
    if slot.kind=="dose" then
        local d=NHInjectors.get(slot.subtype)
        return {tr(d.zh,d.en),tr("耐久 ","Durability ")..(slot.remaining or model.maxUses).."/"..model.maxUses
            ..tr("   数量 ","   Count ")..(slot.count or 1),tr(d.zhEffect,d.enEffect)}
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

local function stash_tabs(width,scale,tr)
    local x,y=8,22
    local tabs={}
    for i,t in ipairs(warehouse_tabs) do
        local name=tr(t[2],t[3])
        local w=GuiGetTextDimensions(gui,name,scale)/scale
        if x>8 and x+w>width-6 then x,y=8,y+13 end
        tabs[i]={x=x,y=y,name=name}
        x=x+w+8
    end
    return tabs,y+15
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

local function time_text(seconds)
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end

local function draw_bank(model,left,top,width,scale,tr,dispatch)
    local x=left+8*scale
    local right=left+(width-8)*scale
    local function balance(y,title,value,infinite)
        local amount=infinite and "∞" or (value and string.format("%.0f",value) or "—")
        local amount_x=right-GuiGetTextDimensions(gui,amount,scale)
        local shown,short=fit(title,amount_x-x-3*scale,scale)
        tint(muted)
        GuiText(gui,x,top+y*scale,shown,scale)
        if short then GuiTooltip(gui,title,"") end
        tint(gold)
        GuiText(gui,amount_x,top+y*scale,amount,scale)
        if infinite then GuiTooltip(gui,tr("无限金币钱包不支持存取","Transfers unavailable with infinite gold"),"")
        elseif value==nil then GuiTooltip(gui,tr("当前钱包不可用","Wallet unavailable"),"") end
    end
    balance(0,tr("随身金币","Wallet"),model.walletGold,model.walletInfinite)
    balance(13,tr("存款","Savings"),model.bankGold)
    tint(muted)
    GuiText(gui,x,top+30*scale,tr("存取金额","Transfer amount"),scale)
    local cell=(right-x)/#bank_amounts
    for i,n in ipairs(bank_amounts) do
        local selected=n==bank_amount
        local title=selected and ("["..n.."]") or tostring(n)
        tint(selected and gold or white)
        local center=x+(i-0.5)*cell
        if GuiButton(gui,269+i,center-GuiGetTextDimensions(gui,title,scale)/2,top+43*scale,title,scale) and not drag then
            bank_amount=n
        end
    end
    local function action(id,y,title,direction,amount,source,destination)
        local n=amount=="all" and (source or 0) or amount
        local enabled=not model.walletInfinite and source and destination and n>0 and source>=n
            and n<=NHStore.maxGold-destination
        local bx=amount=="all" and right-GuiGetTextDimensions(gui,title,scale) or x
        tint(enabled and green or muted)
        if GuiButton(gui,id,bx,top+y*scale,title,scale) and enabled and not drag then
            dispatch("bank_transfer",{direction=direction,amount=amount})
        end
    end
    action(274,61,tr("存入","Deposit"),"deposit",bank_amount,model.walletGold,model.bankGold)
    action(276,61,tr("全部存入","Deposit all"),"deposit","all",model.walletGold,model.bankGold)
    action(275,77,tr("取出","Withdraw"),"withdraw",bank_amount,model.bankGold,model.walletGold)
    action(277,77,tr("全部取出","Withdraw all"),"withdraw","all",model.bankGold,model.walletGold)
end

local function draw_essences(entries,start,limit,left,top,width,scale,mx,my)
    local column_width=(width-16)/2
    local tip
    for i=1,math.min(limit,#entries-start+1) do
        local entry=entries[start+i-1]
        local x=left+(8+(i-1)%2*column_width)*scale
        local y=top+(2+math.floor((i-1)/2)*13)*scale
        local right=x+(column_width-4)*scale
        local value=compact(entry.amount)
        local value_x=right-GuiGetTextDimensions(gui,value,scale)
        local name=entry.name:gsub("精华$",""):gsub(" [Ee]ssence$","")
        tint(entry.amount>0 and white or muted)
        GuiText(gui,x,y,fit(name,value_x-x-3*scale,scale),scale)
        tint(entry.amount>0 and green or muted)
        GuiText(gui,value_x,y,value,scale)
        if mx>=x and mx<right and my>=y and my<y+12*scale then
            tip={entry.name.."  "..string.format("%.0f",entry.amount)}
        end
    end
    return tip
end

local function draw_farm(farm,y,tr,button,label,value_row,dispatch)
    if #farm.plots==0 then
        if button(412,6,y,tr("去扩建田地","Build farmland")) then
            tab,selected_entry="expansion","farmland"
        end
        return
    end
    local plot=selected_plot and farm.plots[selected_plot]
    local crops={}
    for _,crop in ipairs(farm.crops) do crops[crop.id]=crop end
    if not plot then
        for i,entry in ipairs(farm.plots) do
            local crop=crops[entry.crop]
            local state=tr("空闲","Empty")
            if crop then
                state=crop.name.."  "..(entry.blocked and tr("库存已满","Storage full") or time_text(entry.remaining))
            end
            local title=string.format(tr("田 %d","Plot %d"),i).."   "..state
            if button(420+i,6,y+(i-1)*13,title) then selected_plot=i end
        end
        return
    end
    if button(413,6,y,tr("< 田地","< Plots")) then selected_plot=nil; return end
    local crop=crops[plot.crop]
    local title=string.format(tr("田 %d","Plot %d"),plot.id)
    label(y+14,title.." · "..(crop and crop.name or tr("选择作物","Choose crop")),white)
    local choices_y=y+28
    if crop then
        if plot.blocked then label(y+28,tr("农产库存已满","Crop storage full"),muted)
        else value_row(y+28,tr("下次自动入库","Next deposit"),time_text(plot.remaining),white) end
        choices_y=y+42
    end
    for i,choice in ipairs(farm.crops) do
        local active=plot.crop==choice.id
        local name=(active and "["..choice.name.."]" or choice.name).."  +"..choice.amount
        local detail=choice.name.."  +"..choice.amount.." / "..time_text(choice.duration).."   "
            ..tr("库存 ","In storage ")..string.format("%.0f",choice.stock)
        if not choice.unlocked then detail=detail.."   "..tr("需要农业设备","Needs farming equipment") end
        if button(430+i,6,choices_y+(i-1)*13,name,active and green or choice.unlocked and gold or muted,detail)
            and choice.unlocked and not active then
            dispatch("farm_plant",{plot=plot.id,token=plot.token,crop=choice.id})
        end
    end
end

local function draw_livestock(farm,y,tr,button,label,value_row)
    if #farm.pens==0 then
        if button(442,6,y,tr("去扩建畜牧设备","Build livestock pens")) then tab,selected_entry="expansion","livestock" end
        return
    end
    local pen=selected_pen and farm.pens[selected_pen]
    if not pen then
        for i,p in ipairs(farm.pens) do
            local text=p.title.."   "..(p.name or tr("空闲","Empty"))
            if p.name then text=text.."   "..(p.blocked and tr("库存已满","Storage full") or time_text(p.remaining)) end
            if button(450+i,6,y+(i-1)*13,text) then selected_pen=i end
        end
        return
    end
    if button(443,6,y,tr("< 栏舍","< Pens")) then selected_pen=nil; return end
    label(y+14,pen.title.." · "..(pen.name or tr("空闲","Empty")),white)
    value_row(y+28,pen.product.." / "..tr("肉","Meat"),pen.amount.." / "..pen.meat,white,
        tr("成年后每轮产量","Yield per adult cycle"))
    value_row(y+41,tr("产出间隔","Cycle time"),time_text(pen.period),white)
    if not pen.name then
        value_row(y+56,tr("成长时间","Growth time"),time_text(pen.growth),white)
        if button(444,6,y+70,tr("购买","Buy ")..pen.young) then
            tab,shop_category,selected_entry="shop","livestock",pen.species
        end
    elseif not pen.grown then
        value_row(y+56,tr("距离成年","Time to adulthood"),time_text(pen.remaining),white)
        value_row(y+69,tr("首次自动入库","First deposit"),time_text(pen.remaining+pen.period),white)
    elseif pen.blocked then
        label(y+56,tr("畜产库存已满","Produce storage full"),muted)
    else
        value_row(y+56,tr("下次自动入库","Next deposit"),time_text(pen.remaining),white)
    end
end

local function draw_workshop(model,layout,scale,sh,tr,dispatch,mx,my)
    local left,width=layout.middle,layout.bench
    if not model.debug and tab=="samples" then tab="orders" end
    local function position_tabs(tabs,y)
        local x,positions=6,{}
        for _,t in ipairs(tabs) do
            if t.key~="samples" or model.debug then
                local name=tr(t.zh,t.en)
                local w=GuiGetTextDimensions(gui,name,scale)/scale
                if x>6 and x+w>width-5 then x,y=6,y+13 end
                positions[#positions+1]={id=t.id,key=t.key,name=name,x=x,y=y}
                x=x+w+7
            end
        end
        return positions,y+16
    end
    local nav,body=position_tabs(work_tabs,18)
    local nav_end=body
    local crafting=tab=="orders"
    local alchemy=crafting and recipe_category=="alchemy"
    local shopping=tab=="shop"
    local farming=tab=="farm"
    local ranching=tab=="livestock"
    local menu=model.progression[tab]
    if crafting then
        menu={}
        for _,recipe in ipairs(model.recipes) do
            if recipe.category==recipe_category and (not alchemy or recipe.alchemyMode==alchemy_mode) then
                menu[#menu+1]=recipe
            end
        end
    elseif shopping then
        menu={}
        for _,good in ipairs(model.shopGoods) do
            if good.category==shop_category then menu[#menu+1]=good end
        end
    end
    local selected
    for _,item in ipairs(menu or {}) do
        if item.id==selected_entry then selected=item; break end
    end
    local outputs=crafting and selected and selected.outputs
    local catalysts=crafting and selected and selected.catalysts
    local catalyst_count=catalysts and #catalysts or 0
    local show_outputs=outputs and (#outputs>1 or (#outputs==1 and (outputs[1].name~=selected.name or catalyst_count>0)))
    local savings,wrap_savings
    if shopping and selected then
        savings=string.format("%.0f",model.bankGold)
        wrap_savings=GuiGetTextDimensions(gui,tr("存款余额","Savings").."   "..savings,scale)>(width-12)*scale
    end
    local salvage
    if salvage_target and model.salvage_enabled then
        local category=model.warehouse[NHStore.category(salvage_target.kind)]
        salvage=category and category[salvage_target.slot]
        if not salvage or salvage.id~=salvage_target.id or not salvage.salvage_yield
            or (salvage_target.mode=="essence" and not salvage.essence) then salvage_target,salvage=nil,nil end
    end
    local per_card=salvage and salvage_target.mode=="essence" and salvage.essence.per_card
    local category_nav,alchemy_nav
    if crafting and not selected and not salvage then
        category_nav,body=position_tabs(recipe_tabs,body)
        if alchemy then alchemy_nav,body=position_tabs(alchemy_tabs,body) end
    elseif shopping and not selected and not salvage then
        category_nav,body=position_tabs(shop_tabs,body)
    elseif farming and not salvage then
        category_nav,body=position_tabs(farm_tabs,body)
    elseif ranching and not salvage then
        category_nav,body=position_tabs(livestock_tabs,body)
    end
    local function available(item)
        if crafting then return item.ready and item.unlocked~=false and not model.order_active end
        if shopping then return item.ready end
        return item.canBuy
    end
    local body_height=62
    if tab=="samples" and not salvage then body_height=82
    elseif salvage then
        body_height=77+(salvage.essence and 14 or 0)+(salvage.spell_uses~=nil and 13 or 0)+(per_card and 13 or 0)
    elseif ranching then
        if livestock_page=="produce" then body_height=13*(1+#model.farm.produce)+5
        elseif selected_pen and model.farm.pens[selected_pen] then body_height=84
        else body_height=13*math.max(1,#model.farm.pens)+5 end
    elseif farming then
        local farm=model.farm
        local plot=selected_plot and farm.plots[selected_plot]
        if farm_page=="stock" then body_height=13*(1+#farm.crops)+5
        elseif not plot then body_height=13*math.max(1,#farm.plots)+5
        else body_height=(plot.crop and 42 or 28)+13*#farm.crops+2 end
    elseif crafting and selected then
        body_height=68+12*#selected.inputs
        if catalyst_count>0 then body_height=body_height+13+12*catalyst_count end
        if show_outputs then body_height=body_height+13+12*#outputs end
        if selected.note then body_height=body_height+13 end
        if model.order_active and selected.unlocked==false then body_height=body_height+13 end
    elseif shopping and selected then
        body_height=(wrap_savings and 112 or 99)+(NHLivestock.species[selected.id] and 39 or 0)
    elseif selected then body_height=80+12*#selected.costs
    elseif menu then
        body_height=5+13*math.max(1,math.min(#menu,entries_per_page))
        if #menu>entries_per_page then body_height=body_height+13 end
        if crafting and model.order_active then body_height=body_height+15 end
    end
    local height=workshop_folded and 20 or layout.panelHeight
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
            tab,selected_entry,salvage_target=t.key,nil,nil
            selected_pen=nil
            selected_plot=nil
            return hover
        end
    end
    -- Keep all navigation above the scrolling body when there is room. On a
    -- narrow screen wrapped subcategories may scroll, but the main tabs stay put.
    local scroll=body+body_height>height-2
    local scroll_y=height-body>=38 and body or nav_end
    local in_scroll=false
    local function begin_scroll()
        local view_key=table.concat({tab,recipe_category,alchemy_mode,shop_category,
            farm_page,selected_plot or "",livestock_page,selected_pen or "",selected_entry or "",
            salvage and salvage.id or "",salvage_target and salvage_target.mode or ""},"/")
        GuiIdPushString(gui,view_key)
        GuiBeginScrollContainer(gui,20000,left+2*scale,top+scroll_y*scale,
            (width-4)*scale,(height-scroll_y-3)*scale,true,0,0)
        in_scroll=true
        -- Children of a native scroll container use relative coordinates.
        left,top,width=0,-scroll_y*scale,width-12
    end
    local function finish()
        if in_scroll then
            GuiEndScrollContainer(gui)
            GuiIdPop(gui)
        end
        return hover
    end
    if scroll and scroll_y==nav_end then begin_scroll() end
    for _,t in ipairs(category_nav or {}) do
        local current=ranching and livestock_page or farming and farm_page or (shopping and shop_category or recipe_category)
        if button(t.id,t.x,t.y,t.name,t.key==current and gold or muted) then
            if ranching then livestock_page,selected_pen=t.key,nil
            elseif farming then farm_page,selected_plot=t.key,nil
            elseif shopping then shop_category=t.key else recipe_category=t.key end
            selected_entry=nil
            return finish()
        end
    end
    for _,t in ipairs(alchemy_nav or {}) do
        if button(t.id,t.x,t.y,t.name,t.key==alchemy_mode and gold or muted) then
            alchemy_mode,selected_entry=t.key,nil
            return finish()
        end
    end
    if scroll and scroll_y~=nav_end then begin_scroll() end
    -- Quantities and timers stay visible even when a long name needs a tooltip.
    local function value_row(y,name,value,color,tip,detail)
        local right=width-6-GuiGetTextDimensions(gui,value,scale)/scale
        local txt,short=fit(name,(right-9)*scale,scale)
        tint(muted)
        GuiText(gui,left+6*scale,top+y*scale,txt,scale)
        if short or detail then GuiTooltip(gui,name,detail or "") end
        tint(color)
        GuiText(gui,left+right*scale,top+y*scale,value,scale)
        if tip then GuiTooltip(gui,tip,detail or "") end
    end
    local function stock_table(entries,y)
        local rate_label=width<110 and tr("每分","/min") or tr("每分钟","Per min")
        local rows={{name=tr("产物","Item"),stock=tr("库存","Stock"),rate=rate_label}}
        for _,entry in ipairs(entries) do
            local rate=string.format("%.2f",entry.perMinute):gsub("%.?0+$","")
            rows[#rows+1]={name=entry.name,stock=compact(entry.stock),rate=rate,entry=entry}
        end
        local stock_w,rate_w=0,0
        for _,r in ipairs(rows) do
            r.stockWidth=GuiGetTextDimensions(gui,r.stock,scale)
            r.rateWidth=GuiGetTextDimensions(gui,r.rate,scale)
            stock_w=math.max(stock_w,r.stockWidth)
            rate_w=math.max(rate_w,r.rateWidth)
        end
        local name_x=left+4*scale
        local rate_right=left+(width-3)*scale
        local stock_right=rate_right-rate_w-3*scale
        local name_w=stock_right-stock_w-3*scale-name_x
        for i,r in ipairs(rows) do
            local row_y=top+(y+(i-1)*13)*scale
            local entry=r.entry
            local detail=entry and string.format(tr("库存 %.0f\n每分钟产量 %s","Stock %.0f\nOutput per minute %s"),
                entry.stock,r.rate)
            tint(entry and white or muted)
            GuiText(gui,name_x,row_y,fit(r.name,name_w,scale),scale)
            if detail then GuiTooltip(gui,r.name,detail) end
            tint(entry and entry.stock>0 and white or muted)
            GuiText(gui,stock_right-r.stockWidth,row_y,r.stock,scale)
            if detail then GuiTooltip(gui,r.name,detail) end
            tint(entry and entry.perMinute>0 and green or muted)
            GuiText(gui,rate_right-r.rateWidth,row_y,r.rate,scale)
            if detail then GuiTooltip(gui,r.name,detail)
            else GuiTooltip(gui,tr("每分钟产量","Output per minute"),tr("按当前完整生产周期计算","Average over a full production cycle")) end
        end
    end
    local function cost(y,name,have,need,detail)
        value_row(y,name,compact(have).." / "..compact(need),have>=need and green or gold,
            string.format("%s  %.0f / %.0f",name,have,need),detail)
    end
    local function order_status(y)
        local remaining=time_text(model.order_remaining)
        value_row(y,tr("生产中：","Making: ")..model.order_name,remaining,white,tr("剩余 ","Time left ")..remaining)
    end
    if salvage then
        label(body,tr("拆解","Dismantle"),gold)
        label(body+13,salvage.name)
        local y=body+27
        local extract=salvage_target.mode=="essence"
        local amount,stock=salvage.salvage_yield,salvage.salvage_stock
        if salvage.essence then
            local essence=tr("精华","Essence")
            local scrap=tr("碎片","Scrap")
            local choice=extract and "["..essence.."]" or essence
            if button(262,6,y,choice,extract and gold or muted) then salvage_target.mode="essence"; return finish() end
            local x=13+GuiGetTextDimensions(gui,choice,scale)/scale
            if button(263,x,y,extract and scrap or "["..scrap.."]",extract and muted or gold) then
                salvage_target.mode="scrap"; return finish()
            end
            y=y+14
        end
        if salvage.spell_uses~=nil then
            value_row(y,tr("剩余次数","Charges left"),salvage.spell_uses<0 and "∞" or tostring(salvage.spell_uses),
                white,nil,tr("剩余次数不影响回收量","Remaining charges do not affect the yield"))
            y=y+13
        end
        if extract then
            amount,stock=salvage.essence.amount,salvage.essence.stock
            if per_card then
                local full=tr("每张满额","Per full card")
                local detail=salvage.essence.basis
                if detail then
                    detail=detail.."\n"..tr("每 1 点标称治疗量折合 1 个治疗精华。",
                        "1 HP of potential healing yields 1 healing essence.")
                else
                    detail=tr("按原版满次数估算伤害或功能价值。\n无限次按 20 次计。超过 375 的部分\n按八分之一折算，整卡四舍五入。",
                        "Priced by damage or utility at full charges.\nUnlimited spells use a 20-cast reference.\nValue above 375 counts at one eighth.\nThe total is rounded to the nearest unit.")
                end
                value_row(y,full,tostring(per_card),white,full,detail)
                y=y+13
            end
            value_row(y,salvage.essence.name,"+"..amount,green)
            value_row(y+12,tr("当前库存","In storage"),compact(stock),white,string.format("%.0f",stock))
        else
            label(y,salvage.salvage_name.." +"..amount,green)
            label(y+12,tr("现有碎片 ","Current scrap ")..compact(stock),muted)
        end
        if amount<=NHStore.maxResourceAmount-stock then
            local confirm=extract and tr("确认提取","Extract essence") or tr("确认拆解","Dismantle item")
            if button(260,6,y+26,confirm,green) then
                dispatch("salvage",salvage_target)
                salvage_target=nil
                return finish()
            end
        else label(y+26,tr("库存已满","Storage full"),muted) end
        if button(261,6,y+38,tr("取消","Cancel")) then salvage_target=nil end
    elseif ranching then
        if livestock_page=="produce" then stock_table(model.farm.produce,body)
        else draw_livestock(model.farm,body,tr,button,label,value_row) end
    elseif farming then
        if farm_page=="stock" then stock_table(model.farm.crops,body)
        else draw_farm(model.farm,body,tr,button,label,value_row,dispatch) end
    elseif crafting and selected then
        local back=tr("< 返回配方","< Recipes")
        local confirm=tr("确认制造","Confirm craft")
        if alchemy then
            if alchemy_mode=="synthesis" then
                back,confirm=tr("< 炼成","< Synthesis"),tr("确认炼成","Synthesize")
            else
                back,confirm=tr("< 分解","< Decomposition"),tr("确认分解","Decompose")
            end
        end
        if button(240,6,body,back) then selected_entry=nil; return finish() end
        label(body+14,show_outputs and selected.name or selected.name.." ×"..selected.output,available(selected) and green or white)
        value_row(body+27,tr("预计用时","Craft time"),time_text(selected.duration),white)
        local y=body+40
        label(y,tr("原料  库存 / 所需","Ingredients  stock / cost"),muted)
        for _,input in ipairs(selected.inputs) do
            y=y+12
            cost(y,input.name,input.available,input.amount,input.detail)
        end
        if catalyst_count>0 then
            y=y+13
            label(y,tr("催化剂（完工归还）","Catalyst (returned)"),muted)
            local detail=tr("开工时暂存，完成后原数归还。","Held when the batch starts and returned in full at completion.")
            for _,sample in ipairs(catalysts) do
                y=y+12
                if sample.held and sample.held>0 then
                    local held=tr("暂存 ","Held ")..string.format("%.0f",sample.held)
                    value_row(y,sample.name,held,green,held,tr("当前库存 ","Stock ")..string.format("%.0f",sample.available).."\n"..detail)
                else
                    cost(y,sample.name,sample.available,sample.amount,detail)
                end
            end
        end
        if show_outputs then
            y=y+13
            label(y,catalyst_count>0 and tr("净产出","Net output") or tr("每批产出","Batch output"),muted)
            for _,result in ipairs(outputs) do
                y=y+12
                value_row(y,result.name,"×"..compact(result.amount),white,result.name.." ×"..result.amount)
            end
        end
        if selected.note then
            y=y+13
            label(y,selected.note,muted)
        end
        y=y+15
        if model.order_active then
            order_status(y)
            if selected.unlocked==false then
                y=y+13
                label(y,selected.reason,muted)
            end
        elseif available(selected) then
            if button(214,6,y,confirm,green) then dispatch("craft",{id=selected.id}) end
        else label(y,selected.reason or tr("材料或空位不足","Need stock or space"),muted) end
    elseif shopping and selected then
        if button(240,6,body,tr("< 返回商品","< Goods")) then selected_entry=nil; return finish() end
        label(body+14,selected.name,white)
        value_row(body+27,tr("数量","Quantity"),string.format("%.0f",selected.quantity),white)
        local destination=selected.category=="materials" and tr("物料","Materials") or tr("消耗品","Supplies")
        local animal=NHLivestock.species[selected.id]
        if animal then destination=tr(animal.pen[1],animal.pen[2]) end
        value_row(body+40,animal and tr("送往","Destination") or tr("入库","Warehouse"),destination,white)
        value_row(body+53,tr("价格","Price"),string.format("%.0f",selected.price),gold)
        local confirm_y=body+83
        if wrap_savings then
            label(body+66,tr("存款余额","Savings"),muted)
            label(body+79,savings,white)
            confirm_y=confirm_y+13
        else value_row(body+66,tr("存款余额","Savings"),savings,white) end
        if animal then
            local resource=NHLivestock.resources[animal.product]
            value_row(confirm_y,tr("成长时间","Growth time"),time_text(animal.growth/60),white)
            value_row(confirm_y+13,tr("产出间隔","Cycle time"),time_text(animal.period/60),white)
            value_row(confirm_y+26,tr(resource.zh,resource.en).." / "..tr("肉","Meat"),animal.amount.." / "..animal.meat,white)
            confirm_y=confirm_y+39
        end
        if available(selected) then
            if button(258,6,confirm_y,tr("确认购买","Confirm purchase"),green) then
                dispatch("shop_buy",{id=selected.id,pen=selected.pen})
            end
        else label(confirm_y,selected.reason,gold) end
    elseif selected then
        if button(240,6,body,tr("< 返回列表","< Projects")) then selected_entry=nil; return finish() end
        label(body+14,selected.name,available(selected) and green or white)
        label(body+27,tr("当前：","Now: ")..selected.current)
        if selected.next then label(body+39,tr("升级后：","Next: ")..selected.next) end
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
            if button(241,6,y,confirm,green) then
                dispatch("buy_upgrade",{id=selected.id,level=selected.level})
                selected_entry=nil
            end
        elseif selected.planned then label(y,tr("尚未开放","In development"),muted)
        elseif selected.maxed then label(y,tr("已完成","Complete"),muted)
        elseif selected.id=="agri_equipment" and model.farm and #model.farm.plots==0 then
            label(y,tr("先开垦一块田","Build a field first"),muted)
        else label(y,tr("所需物料不足","Insufficient stock"),gold) end
    elseif menu then
        local list_key=alchemy and alchemy_mode or (crafting and recipe_category) or (shopping and shop_category) or tab
        local pages=math.max(1,math.ceil(#menu/entries_per_page))
        local current=math.min(list_pages[list_key] or 1,pages)
        local y=body
        if crafting and model.order_active then
            order_status(y)
            y=y+15
        end
        if crafting and #menu==0 then label(y,tr("暂无配方","No recipes yet"),muted) end
        if shopping and #menu==0 then label(y,tr("暂无商品","No goods for sale"),muted) end
        if pages>1 then
            if button(242,6,y,"<",current>1 and gold or muted) then current=math.max(1,current-1) end
            if button(243,width-14,y,">",current<pages and gold or muted) then current=math.min(pages,current+1) end
            tint(muted)
            GuiText(gui,left+(width/2-8)*scale,top+y*scale,current.."/"..pages,scale)
            y=y+13
        end
        list_pages[list_key]=current
        for i=1,entries_per_page do
            local item=menu[(current-1)*entries_per_page+i]
            if item then
                local color=available(item) and green or white
                if item.planned or item.maxed or item.unlocked==false then color=muted end
                if button(243+i,6,y+(i-1)*13,item.name,color) then
                    selected_entry=item.id
                    return finish()
                end
            end
        end
    else
        if button(216,6,body+3,tr("生成测试魔杖和混合瓶","Spawn wand and flask")) then dispatch("preview_items") end
        label(body+17,tr("在脚边拾取样品","Pick up the samples at your feet"),muted)
        if button(217,6,body+33,tr("重发测试针剂包","Reissue test pouch"),gold,
            tr("替换现有针剂包，内含两支激活剂。","Replace the current pouch with two doses.")) then dispatch("restock") end
        if button(480,6,body+49,tr("领取四种召唤卡","Claim four summon cards"),gold) then
            folded,warehouse_tab,warehouse_pages.collection=false,"collection",1
            dispatch("test_cards")
        end
        if button(481,6,body+65,tr("领取空卡片夹","Claim empty card wallet"),gold) then
            folded,warehouse_tab,warehouse_pages.equipment=false,"equipment",1
            dispatch("test_wallet")
        end
    end
    return finish()
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
            name=name, icon=icon, entity=entity, pouchId=kind=="pouch" and entity or nil,
            walletId=kind=="card_wallet" and entity or nil}
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
            slots[#slots].remaining,slots[#slots].count,slots[#slots].subtype,slots[#slots].species=v.remaining,v.count,v.subtype,v.species
        end
    end
    local popupY = standalone and 0 or -66
    if model.popup then
        if not standalone then
            GuiZSetForNextWidget(gui,-79)
            GuiImageNinePiece(gui,37,ox,oy+popupY*scale,pw*scale,61*scale,1)
        end
        label(8,popupY+5,model.pouchName,pw-43,white)
        if GuiButton(gui,38,ox+(pw-34)*scale,oy+(popupY+5)*scale,tr("关闭","Close"),scale) then
            drag=nil
            dispatch("close_container")
            return
        end
        for i=1,(model.walletId and model.walletCapacity or model.pouchCapacity) do
            local cell=model.cells[i]
            if model.walletId then
                local species=cell and NHCompanions.species[cell.species]
                slot(i-1,popupY+23,"card_cell",cell and "summon_card",species and tr(species.zh,species.en) or tr("空格","Empty slot"),cell and cell.icon)
            else
                local d=cell and NHInjectors.get(cell.subtype)
                slot(i-1,popupY+23,"dose",cell and "dose",d and tr(d.zh,d.en) or tr("空格","Empty slot"),d and d.icon)
            end
            local v=slots[#slots]
            v.cell,v.pouchId,v.walletId=i,model.pouchId,model.walletId
            if cell then v.remaining,v.count,v.subtype,v.species=cell.remaining,cell.count,cell.subtype,cell.species end
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
        local tabs,grid_y=layout.tabs,layout.gridY
        local content_height=layout.contentHeight
        local height=folded and 20 or layout.panelHeight
        local top=sh-5-height*scale
        local warehouse_hover=mx>=left and mx<left+width*scale and my>=top and my<top+height*scale
        panel_hover=panel_hover or warehouse_hover
        if warehouse_hover and drag and not folded then
            local src=drag.source
            if src.key=="dose" then warehouse_tab="supplies"
            elseif src.key=="card_cell" or (src.key=="valuable" and src.kind=="summon_card") then warehouse_tab="collection"
            elseif src.key=="valuable" and src.kind=="card_wallet" then warehouse_tab="equipment"
            elseif src.key=="valuable" and src.kind=="pouch" then warehouse_tab="equipment"
            elseif src.key=="native" and src.kind~="other" and (warehouse_tab~="materials" or src.kind~="potion") then
                warehouse_tab=NHStore.category(src.kind)
            end
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
            local essences=warehouse_tab=="essences"
            local per_page=essences and 12 or (bulk and material_rows*2 or cols*math.floor(content_height/qh))
            local capacity=essences and #model.essences or model.warehouse_capacity[warehouse_tab]
            local page_no
            if warehouse_tab=="bank" then
                draw_bank(model,left,top+grid_y*scale,width,scale,tr,dispatch)
            else
                local pages=math.max(1,math.ceil((bulk and #model.materials or capacity)/per_page))
                local current=warehouse_pages[warehouse_tab] or 1
                page_no=warehouse_pager(left+4*scale,top+(height-17)*scale,width-8,scale,current,pages)
                if current~=page_no then loading=nil end
                warehouse_pages[warehouse_tab]=page_no
            end
            if essences then
                stock_tip=draw_essences(model.essences,(page_no-1)*per_page+1,per_page,left,top+grid_y*scale,width,scale,mx,my)
            elseif bulk then
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
            elseif page_no then
                local rows=model.warehouse[warehouse_tab] or {}
                for i=0,math.min(per_page,capacity-(page_no-1)*per_page)-1 do
                    local n=(page_no-1)*per_page+i+1
                    local v=rows[n] or {}
                    slot(i%cols,grid_y+math.floor(i/cols)*qh,"warehouse",v.kind,v.name or tr("空格","Empty slot"),v.icon,v.id,left,top)
                    local target=slots[#slots]
                    target.view=v
                    target.subtype,target.species=v.subtype,v.species
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
    if drag and (model.revision~=drag.revision or model.pouchId~=drag.pouchId or model.walletId~=drag.walletId) then drag=nil end
    if model.salvage_enabled and hovered and hovered.key=="warehouse" and hovered.view and hovered.view.salvage_yield
        and not fresh and not drag and InputIsMouseButtonJustDown(2) then
        salvage_target={id=hovered.entity,kind=hovered.kind,slot=hovered.safeSlot,mode=hovered.view.essence and "essence" or "scrap"}
        workshop_folded=false
    end
    if not fresh and InputIsMouseButtonJustDown(1) and hovered and hovered.kind and hovered.kind~="reserved" then
        drag={source=hovered,revision=model.revision,pouchId=model.pouchId,walletId=model.walletId,x=mx,y=my}
    end
    if drag and ((mx-drag.x)^2+(my-drag.y)^2)>9*scale^2 then drag.moved=true end
    local source=drag and drag.source
    local function drop(target)
        if not source or not target then return end
        if (source.kind=="pouch" or source.kind=="card_wallet") and source.key==target.key and source.entity==target.entity
            and source.safeSlot==target.safeSlot and not drag.moved then
            return "open_container",source,source.safeSlot
        end
        local from_store=source.key=="valuable" or source.key=="warehouse"
        local to_store=target.key=="valuable" or target.key=="warehouse"
        if source.kind=="summon_card" then
            local accepts=not target.kind or (target.kind=="summon_card" and NHCompanions.canStack(target,source))
            if target.key=="card_cell" and accepts then
                if source.key=="native" then return "place",source end
                if from_store or (source.key=="card_cell" and source.cell~=target.cell) then return "move_wallet_card",source end
            end
            if to_store and accepts and (target.key=="valuable" or warehouse_tab=="collection") then
                if source.key=="card_cell" then return "move_wallet_card",source,target.safeSlot end
                if from_store and (source.key~=target.key or source.safeSlot~=target.safeSlot) then return "move_stored_card",source,target.safeSlot end
                if source.key=="native" then return "place",source,target.safeSlot end
            end
            if source.key=="card_cell" and target.key=="native" and not target.entity and target.lane=="tool" then return "take_card",target end
        end
        if source.kind=="card_wallet" and from_store and to_store and not target.kind
            and (target.key=="valuable" or warehouse_tab=="equipment") and (source.key~=target.key or source.safeSlot~=target.safeSlot) then
            return "move_wallet",source,target.safeSlot
        end
        if model.mode=="case" and source.kind=="perk" and not target.kind then
            if from_store and target.key=="perk" then return "equip_stored_perk",source end
            if source.key=="perk" and to_store and (target.key=="valuable" or warehouse_tab=="supplies") then
                return "store_equipped_perk",source
            end
        end
        if source.kind=="pouch" and from_store and to_store and not target.kind
            and (target.key=="valuable" or warehouse_tab=="equipment") then
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
            and (source.subtype or "fire")==(target.subtype or "fire")
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
        local image = v.kind=="summon_card" and v.species and NHCompanions.cardIcon(v.species) or v.icon
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
        if placement=="place" or placement=="move_pouch" or placement=="move_wallet" or placement=="move_wallet_card"
            or placement=="move_stored_card" or placement=="equip_stored_perk" or placement=="store_equipped_perk" then tint(green) end
        GuiImage(gui,1000+i,v.x,v.y,tile,1,scale)
        if v.kind=="reserved" then GuiText(gui,v.x+5*scale,v.y+3*scale,"...",scale)
        elseif v.kind then sprite(v,2000+i,v.x+qw*scale/2,v.y+qh*scale/2,source and source.key==v.key and source.safeSlot==v.safeSlot and source.cell==v.cell and source.perkSlot==v.perkSlot and 0.35 or 1)
        end
        if v.kind=="dose" or v.kind=="summon_card" then
            local durability=v.kind=="summon_card" and NHCompanions.durability or model.maxUses
            local remaining=v.remaining or durability
            local quantity=(v.kind=="summon_card" and compact(v.count or 1)) or v.count
            local caption=(v.count or 1)>1 and ("×"..quantity) or (remaining.."/"..durability)
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
                pouchId=source.pouchId or hovered.pouchId,walletId=source.walletId or hovered.walletId,
                species=source.species,remaining=source.remaining,count=source.kind=="summon_card" and (source.count or 1) or source.count,
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
        local qw,qh=GuiGetImageDimensions(gui,tile)
        local content_height=qh+30+material_rows*11
        layout=home_layout(sw,s,qw)
        layout.tabs,layout.gridY=stash_tabs(layout.stash,s,tr)
        local fit_scale=(sh-10)/(layout.gridY+content_height+18)
        if fit_scale<s then
            s=fit_scale
            layout=home_layout(sw,s,qw)
            layout.tabs,layout.gridY=stash_tabs(layout.stash,s,tr)
        end
        layout.contentHeight=content_height
        layout.panelHeight=layout.gridY+content_height+18
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
