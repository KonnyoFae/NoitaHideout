local width, height = 427, 240
local click, action, argument
local drawn,panels,tips = {},{},{}
local frame = 0
local pointer = {x = 0, y = 0}
function GameGetFrameNum() return frame end
function InputIsMouseButtonDown() return pointer.down == true end
function InputIsMouseButtonJustDown(which) return (which==2 and pointer.right) or (which==1 and pointer.pressed) or false end
function InputIsMouseButtonJustUp() return pointer.released == true end
function GameGetCameraBounds() return 0, 0, width, height end
function DEBUG_GetMouseWorld() return pointer.x, pointer.y end
function GuiCreate() return {} end
function GuiStartFrame() drawn,panels,tips = {},{},{} end
function GuiGetScreenDimensions() return width, height end
function GuiZSet() end
function GuiZSetForNextWidget() end
local next_color,image_colors={},{}
function GuiColorSetForNextWidget(_,r,g,b) next_color={r,g,b} end
local tipbox
function GuiImageNinePiece(_,id,x,y,w,h)
    panels[id]={x=x,y=y,w=w,h=h}
    if id==200 then tipbox={x=x,y=y,w=w,h=h} end
end
local tiles={}
function GuiImage(_,id,x,y,sprite)
    image_colors[id],next_color=next_color,{}
    if sprite=="data/ui_gfx/inventory/quick_inventory_box.png" then tiles[id]={x=x,y=y} end
end
function GuiTooltip(_,title,body) tips[title]=body or "" end
function GuiGetImageDimensions() return 20,20 end
function MagicNumbersGetValue(k) return k=="UI_FULL_INVENTORY_OFFSET_X" and "170" or "20" end
function GuiGetTextDimensions(_, value, scale)
    local w = 0
    for letter in value:gmatch("[^\128-\191][\128-\191]*") do
        w = w + (#letter > 1 and 8 or 4)
    end
    return w * (scale or 1), 9 * (scale or 1)
end
function GuiText(_, _, _, value) drawn[value] = true end
local buttons={}
function GuiButton(_, id, x, y, value)
    buttons[id]={x=x,y=y,name=value,color=next_color}
    drawn[value] = true
    return id == click
end
function GuiImageButton(_, id) return id == click end

dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
function CellFactory_GetType() return -1 end
dofile("mods/noita_hideout/files/transfers.lua")
dofile("mods/noita_hideout/files/perks.lua")
dofile("mods/noita_hideout/files/ui.lua")
local function render(model, widget)
    frame = frame + 1
    buttons={}
    click, action, argument = widget, nil, nil
    NHUI.draw(model, function(command, item)
        assert(not action, "multiple actions on a single input")
        action, argument = command, item
    end)
    return action, argument
end
local function green_button(id)
    local b=buttons[id]
    return b and b.color[1]==0.62 and b.color[2]==0.95 and b.color[3]==0.75
end

local function native(lane,col,x,id,kind)
    return {key="native",lane=lane,col=col,xslot=x,yslot=0,entity=id,kind=kind,parent=lane=="spell" and 3 or 2}
end
local model={lang="en",open=false,near=false,status=""}
assert(not render(model,2))
model.open,model.mode,model.pouch_location,model.case_count=true,"case","safe",2
model.capacity,model.revision,model.secure_loot=4,1,{[3]={kind="pouch",name="Injector pouch #17",id=17}}
model.native_slots={native("wand",0,0,42,"wand"),native("tool",4,0,43,"dose"),
    native("spell",0,0,44,"spell"),native("spell",5,5),native("tool",6,2),native("wand",3,3)}
local function point(x,y,event)
    pointer={x=x,y=y,down=event=="press",pressed=event=="press",released=event=="release"}
    return render(model)
end
local cx,cy=width-187-5,height-72-5
render(model)
point(28,28,"press")
local cmd,arg=point(cx+12,cy+30,"release")
assert(cmd=="place" and arg.entity==42 and arg.safeSlot==1)
point(198,28,"press")
cmd,arg=point(cx+35,cy+30,"release")
assert(cmd=="place" and arg.entity==44 and arg.safeSlot==2)
model.secure_loot[2]={kind="spell",name="Bomb",id=22}
point(cx+35,cy+30,"press")
assert(not point(88,28,"release"),"spell cannot go in wand row")
point(cx+35,cy+30,"press")
cmd,arg=point(298,28,"release")
assert(cmd=="secure_withdraw" and arg.xslot==5 and arg.storedId==22 and arg.safeSlot==2)
point(cx+58,cy+30,"press")
cmd,arg=point(cx+58,cy+30,"release")
assert(cmd=="open_container" and arg.safeSlot==3 and arg.pouchId==17)
model.popup,model.pouchId,model.pouchName=true,17,"Injector pouch #17"
model.maxUses,model.pouchCapacity,model.cells=3,4,{{remaining=3,count=2}}
render(model)
for i=1002,1003 do assert(tiles[i].x-tiles[i-1].x==20) end -- case
for i=1005,1007 do assert(tiles[i].x-tiles[i-1].x==20) end -- pouch
point(cx+58,cy+30,"press")
cmd,arg=point(148,28,"release")
assert(cmd=="take_pouch" and arg.xslot==2 and arg.safeSlot==3 and arg.pouchId==17)
point(108,28,"press")
cmd,arg=point(cx+12,cy-38,"release")
assert(cmd=="place" and arg.entity==43 and arg.intoContainer and arg.pouchId==17)
point(cx+12,cy-38,"press")
cmd,arg=point(cx+12,cy+30,"release")
assert(cmd=="unpack_dose" and arg.safeSlot==1 and arg.pouchId==17)
model.secure_loot[1]={kind="dose",id=9}
point(cx+12,cy+30,"press")
cmd,arg=point(cx+12,cy-38,"release")
assert(cmd=="pack_dose" and arg.safeSlot==1 and arg.pouchId==17)
point(cx+12,cy-38,"press")
cmd,arg=point(cx+72,cy-38,"release")
assert(cmd=="move_cell" and arg.sourceCell==1 and arg.targetCell==4 and arg.pouchId==17)
model.cells[4]={remaining=2,count=1}
point(cx+12,cy-38,"press")
assert(not point(cx+72,cy-38,"release"))
point(cx+72,cy-38,"press")
cmd,arg=point(148,28,"release")
assert(cmd=="take_dose" and arg.sourceCell==4 and arg.pouchId==17)
model.secure_loot[2]={kind="pouch",id=83,name="Injector pouch #83",doses=0}
point(cx+35,cy+30,"press")
cmd,arg=point(cx+35,cy+30,"release")
assert(cmd=="open_container" and arg.pouchId==83)
point(cx+12,cy-38,"press")
model.pouchId,model.pouchName,model.cells=83,"Injector pouch #83",{}
assert(not point(148,28,"release"),"switching pouches cancels the previous cell drag")
assert(drawn["Injector pouch #83"] and not drawn["×2"])
point(108,28,"press")
cmd,arg=point(cx+12,cy-38,"release")
assert(cmd=="place" and arg.pouchId==83)
model.secure_loot[2]={kind="spell",name="Bomb",id=22}
assert(render(model,38)=="close_container")
model.popup=false
point(198,28,"press")
assert(not point(298,28,"release"),"vanilla reorder")
render(model,36)
point(198,28,"press")
cmd,arg=point(cx+12,cy+30,"release")
assert(arg.safeSlot==4)
point(cx+12,cy+36,"press")
model.open=false
render(model)
model.open=true
assert(not point(148,28,"release"))
print("Native inventory drag, spell row, exact slot, upgrade pages and close cancellation passed.")

-- Left warehouse, native tile pitch, automatic filing and materials tab.
model.near,model.warehouse=true,{}
model.warehouse_capacity={wand=48,spell=48,containers=48,supplies=48,equipment=48,materials=16}
model.debug=true
local profile={safeCapacity=2,levels={},materials={water=500,sand=350,slime=200},resources={},warehouse={}}
model.progression=NHStore.progressMenu(profile,"en")
model.recipes={
    {id="stable",category="alchemy",alchemyMode="synthesis",name="Teleportatium",output=500,duration=120,ready=true,inputs={{name="Slime",available=300,amount=250}}},
    {id="medical",category="medical",name="Medkit",output=1,duration=90,ready=true,inputs={{name="Slime",available=300,amount=100}}},
    {id="injector",category="medical",name="Fire injector",output=1,duration=120,ready=false,reason="Need stock",inputs={}},
    {id="grenade",category="weapons",name="Magic grenade",output=1,duration=120,ready=false,unlocked=false,reason="Build the station",inputs={}},
    {id="pouch",category="equipment",name="Injector pouch",output=1,duration=120,ready=true,
        inputs={{name="Slime",amount=50,available=100},{name="Empty container",amount=1,available=2}}},
    {id="reverse_stable",category="alchemy",alchemyMode="decomposition",name="Decompose Teleportatium",duration=120,ready=true,
        inputs={{name="Teleportatium",available=600,amount=500}},
        outputs={{name="Unstable teleportatium",amount=250},{name="Slime",amount=250}}},
}
render(model)
local origin=tiles[1004]
assert(tiles[1005].x-origin.x==20)
local nextrow
for _,t in pairs(tiles) do if t.x==origin.x and t.y==origin.y+20 then nextrow=t end end
assert(nextrow)
point(198,28,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="place" and arg.kind=="spell" and arg.container=="warehouse" and arg.safeSlot==1)
model.warehouse.spell={{kind="spell",name="Bomb",id=32}}
point(origin.x+1,origin.y+1,"press")
cmd,arg=point(298,28,"release")
assert(cmd=="secure_withdraw" and arg.container=="warehouse" and arg.storedId==32 and arg.xslot==5)
-- Each category pages independently and the next empty page remains writable.
local page_size=math.floor((panels[70].w-16)/20)*4
model.warehouse_capacity.spell=page_size*7
local item_panel,item_pager=panels[70],panels[299]
render(model,301)
point(198,28,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="place" and arg.safeSlot==1+page_size)
-- Directly select page 5; the arrows step from that selection.
render(model,306)
point(198,28,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="place" and arg.safeSlot==4*page_size+1)
render(model,300)
render(model)
assert(drawn["[4]"])
-- The pouch files into equipment even while another category is displayed.
-- Its popup still accepts interaction inside the warehouse.
model.native_slots[2].kind="pouch"
point(108,28,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="place" and arg.kind=="pouch" and arg.container=="warehouse" and arg.safeSlot==1)
model.native_slots[2].kind="dose"
model.warehouse.equipment={[1]={kind="pouch",name="Injector pouch",id=97}}
render(model)
point(origin.x+1,origin.y+1)
assert(drawn["Injector pouch"])
point(origin.x+1,origin.y+1,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="open_container" and arg.container=="warehouse" and arg.safeSlot==1 and arg.pouchId==97)
point(origin.x+1,origin.y+1,"press")
cmd,arg=point(148,28,"release")
assert(cmd=="take_pouch" and arg.container=="warehouse" and arg.safeSlot==1 and arg.pouchId==97)
local original_slot=model.secure_loot[1]
model.secure_loot[1]=nil
render(model)
point(origin.x+1,origin.y+1,"press")
cmd,arg=point(tiles[1001].x+1,tiles[1001].y+1,"release")
assert(cmd=="move_pouch" and arg.pouchId==97 and arg.source=="warehouse" and arg.destination=="safe" and arg.safeSlot==1)
render(model,76) -- Starting over the spell page should still file the case pouch under equipment.
render(model)
point(tiles[1003].x+1,tiles[1003].y+1,"press")
cmd,arg=point(origin.x+21,origin.y+1,"release")
assert(cmd=="move_pouch" and arg.pouchId==17 and arg.source=="safe" and arg.destination=="warehouse" and arg.safeSlot==2)
model.secure_loot[1]=original_slot
model.docks,model.materials={},{}
render(model,80)
render(model)
assert(drawn.Flask and drawn["Powder pouch"] and drawn.Empty)
assert(item_pager.x==panels[299].x and item_pager.y==panels[299].y)
assert(item_panel.x==panels[70].x and item_panel.y==panels[70].y and item_panel.w==panels[70].w and item_panel.h==panels[70].h)
local flask,powder=tiles[1004],tiles[1005]
assert(powder.y==flask.y and powder.x>flask.x+20)
local native_flask=native("tool",5,1,51,"potion")
native_flask.dockSlot=1
table.insert(model.native_slots,native_flask)
point(125,28,"press")
cmd,arg=point(powder.x+2,powder.y+2,"release")
assert(cmd=="cancel_native")
point(125,28,"press")
cmd,arg=point(flask.x+2,flask.y+2,"release")
assert(cmd=="place" and arg.container=="docks" and arg.safeSlot==1)
local mixed={kind="potion",capacity=50,materials={water=12,slime=8},color=0xff102080}
model.docks[1]={kind="potion",id=123,name="Mixed flask",used=20,capacity=50,potion=mixed}
model.secure_loot[1]={kind="potion",id=124,name="Mixed flask",potion=mixed}
model.materials={{key="water",name="Water",amount=100,slot=1}}
cmd,arg=render(model,181)
assert(cmd=="material_transfer" and arg.unload and arg.storedId==123)
render(model)
local load_button=buttons[187]
for n=2,9 do model.materials[n]={key="m"..n,name="M"..n,amount=n==2 and 1000 or 1250000,slot=1} end
render(model)
assert(drawn["1k"] and drawn["1.2M"] and drawn["[1]"] and drawn["2"] and buttons[188].x>load_button.x and buttons[188].y==load_button.y)
local button2=buttons[188]
point(button2.x+1,button2.y+1)
assert(drawn["M2  1000"])
render(model,303)
assert(drawn["M9"] and not drawn["M2"])
render(model,300)
point(flask.x+1,flask.y+1)
assert(drawn["Flask  20/50"] and drawn["water  12"] and drawn["slime  8"])
assert(image_colors[2004][1]==128/255 and image_colors[2004][2]==32/255 and image_colors[2004][3]==16/255)
assert(image_colors[2001][1]==128/255)
assert(tipbox.x>flask.x and tipbox.x<flask.x+20 and tipbox.x>=0 and tipbox.y>=0 and tipbox.x+tipbox.w<=width and tipbox.y+tipbox.h<=height)
cmd,arg=point(load_button.x+1,load_button.y+1,"press")
assert(cmd=="material_transfer" and arg.amount==1 and arg.material=="water")
assert(not point(load_button.x+1,load_button.y+1,"release"))
cmd,arg=point(load_button.x+1,load_button.y+1,"press")
pointer.pressed=false
for elapsed=1,48 do
    cmd,arg=render(model)
    if elapsed==24 then assert(cmd=="material_transfer" and arg.amount==5)
    elseif elapsed==48 then assert(cmd=="material_transfer" and arg.amount==10)
    elseif elapsed<24 then assert(not cmd) end
end
pointer.x=0
assert(not render(model))
pointer.x=load_button.x+1
for i=1,24 do assert(not render(model)) end
point(0,0,"release")
point(flask.x+2,flask.y+2,"press")
cmd,arg=point(148,28,"release")
assert(cmd=="secure_withdraw" and arg.container=="docks" and arg.storedId==123)
model.warehouse.containers={model.docks[1]}
render(model,77)
render(model)
assert(image_colors[2004][1]==128/255)
local first_tile=tiles[1004]
point(first_tile.x+1,first_tile.y+1)
assert(drawn["Flask  20/50"] and drawn["water  12"])

-- The bank has no inventory cells or pager. Presets move the exact amount;
-- "all" is a separate one-click action in either direction.
model.walletGold,model.bankGold=234,120345
render(model,81)
render(model)
assert(drawn.Wallet and drawn.Savings and drawn["234"] and drawn["120345"] and not panels[299])
assert(not render(model,272))
cmd,arg=render(model,274)
assert(cmd=="bank_transfer" and arg.direction=="deposit" and arg.amount==100)
cmd,arg=render(model,275)
assert(cmd=="bank_transfer" and arg.direction=="withdraw" and arg.amount==100)
assert(not render(model,273))
assert(not render(model,274) and not green_button(274))
cmd,arg=render(model,276)
assert(cmd=="bank_transfer" and arg.direction=="deposit" and arg.amount=="all")
cmd,arg=render(model,277)
assert(cmd=="bank_transfer" and arg.direction=="withdraw" and arg.amount=="all")
model.walletGold=0
assert(not render(model,276) and green_button(277))
model.walletGold=nil
assert(not render(model,277) and not green_button(275) and drawn["—"])
model.walletInfinite=true
assert(not render(model,277) and not green_button(276) and drawn["∞"])
model.walletInfinite=false
model.walletGold,model.bankGold=NHStore.maxGold-2,20
assert(not render(model,277) and drawn["9007199254740989"],"all requires space for the entire source balance")
assert(not render(model,270))
assert(green_button(275))
model.walletGold,model.bankGold=20,NHStore.maxGold-2
assert(not render(model,276) and green_button(274))
model.walletGold,model.bankGold=13,0
assert(not render(model,277) and not green_button(275))
assert(not render(model,270))
assert(green_button(274))
for _,lang in ipairs({"zh","en"}) do
    model.lang=lang
    for _,sw in ipairs({320,427,640}) do
        width=sw
        render(model)
        local panel=panels[70]
        local function inside(id)
            local b=assert(buttons[id])
            assert(b.x>=panel.x and b.x+GuiGetTextDimensions(nil,b.name)<=panel.x+panel.w and b.y+9<panel.y+panel.h)
            return b
        end
        for i=270,277 do inside(i) end
        for i=274,275 do
            local a,b=inside(i),inside(i+2)
            assert(a.x+GuiGetTextDimensions(nil,a.name)<b.x)
        end
        assert(drawn[lang=="zh" and "存钱罐" or "Piggy bank"])
    end
end
width=427
render(model)
local case_flask,bank_button=tiles[1001],buttons[276]
point(case_flask.x+1,case_flask.y+1,"press")
pointer={x=bank_button.x+1,y=bank_button.y+1,released=true}
assert(not render(model,276),"dragging an item over a money button cannot transfer gold")
pointer.released=false
render(model,77)
render(model)
assert(drawn["[1]"] and not buttons[274])
render(model,71)
render(model)
assert(drawn["[+] Stash"] and not drawn.Materials)
model.near=false
render(model)
assert(not drawn["[+] Stash"])

-- Three bottom panels stay separate at different widths, including the open pouch.
model.near,model.popup=true,true
render(model,71)
for _,size in ipairs({{640,360},{427,240},{320,240}}) do
    width,height=size[1],size[2]
    render(model)
    local stash,bench,secure,pouch=panels[70],panels[210],panels[10],panels[37]
    assert(stash.x>=0 and stash.x+stash.w<bench.x and bench.x+bench.w<secure.x)
    assert(secure.x+secure.w<=width and pouch.x>=bench.x+bench.w and pouch.y+pouch.h<secure.y)
    assert(bench.y+bench.h==stash.y+stash.h and bench.y+bench.h==secure.y+secure.h)
    assert(tiles[1002].x-tiles[1001].x==20 and tiles[1007].x+20<=pouch.x+pouch.w)
    for i=250,255 do
        local b=assert(buttons[i])
        assert(b.x>=bench.x and b.y>=bench.y and b.x+GuiGetTextDimensions(nil,b.name)<=bench.x+bench.w)
    end
end
-- Select a recipe to inspect it before submission. Categories are usable at
-- the narrow size as well, and availability colors update with live stock.
assert(drawn.Alchemy and drawn.Medical and drawn.Weapons and drawn.Equipment)
assert(drawn.Synthesis and drawn.Decomposition and not buttons[245])
assert(drawn.Teleportatium and not drawn.Medkit and green_button(244))
assert(not render(model,214))
assert(not render(model,244))
render(model)
assert(drawn["Teleportatium ×500"] and drawn["300 / 250"] and drawn["Craft time"] and drawn["2:00"] and green_button(214))
assert(drawn["< Synthesis"] and drawn.Synthesize)
local action,param=render(model,214)
assert(action=="craft" and param.id=="stable")
assert(not buttons[215] and not render(model,215))
render(model,240)
render(model,255)
render(model)
assert(not drawn.Teleportatium and not buttons[245] and green_button(244))
render(model,244)
render(model)
assert(drawn["Batch output"] and tips["Unstable teleportatium ×250"] and tips["Slime ×250"] and drawn["600 / 500"])
assert(tips["Decompose Teleportatium"] or drawn["Decompose Teleportatium"])
action,param=render(model,214)
assert(action=="craft" and param.id=="reverse_stable")
model.lang="zh"
render(model)
assert(drawn["预计用时"] and drawn["每批产出"] and drawn["2:00"] and drawn["< 分解"] and drawn["确认分解"])
render(model,240)
render(model)
assert(drawn["炼成"] and drawn["分解"])
model.lang="en"

local powderInfo="Stock / used this batch\nAlchemical gunpowder  200 / 200\nRegular gunpowder  320 / 300"
model.recipes[#model.recipes+1]={id="separate_gunpowder",category="alchemy",alchemyMode="decomposition",
    name="Separate gunpowder",duration=120,ready=true,output=500,
    inputs={{name="Gunpowder (total)",available=520,amount=500,detail=powderInfo}},
    outputs={{name="Healthium",amount=250},{name="Purifying powder",amount=250}}}
render(model,245)
render(model)
assert(drawn["520 / 500"] and tips["Gunpowder (total)"]==powderInfo)
assert(tips["Healthium ×250"] and tips["Purifying powder ×250"])
action,param=render(model,214)
assert(action=="craft" and param.id=="separate_gunpowder")
render(model,240)
table.remove(model.recipes)

-- The sample is reserved separately. Net yield excludes that sample even when
-- the product name matches the recipe name.
local sample={name="Concentrated mana",available=1,amount=1}
local mana={id="mana",category="alchemy",alchemyMode="synthesis",name=sample.name,duration=120,ready=true,
    inputs={{name="Water",available=300,amount=250}},catalysts={sample},outputs={{name=sample.name,amount=250}}}
model.recipes[#model.recipes+1]=mana
render(model,254)
render(model,245)
for _,lang in ipairs({"en","zh"}) do
    model.lang=lang
    for _,size in ipairs({{320,180},{427,240},{640,360}}) do
        width,height=size[1],size[2]
        render(model)
        local b,bench=assert(buttons[214]),panels[210]
        assert(bench.y>=0 and b.y>=bench.y and b.y+9<=bench.y+bench.h)
        assert(drawn[lang=="zh" and "催化剂（完工归还）" or "Catalyst (returned)"])
        assert(drawn[lang=="zh" and "净产出" or "Net output"] and drawn["300 / 250"] and drawn["1 / 1"])
        local info=tips["Concentrated mana  1 / 1"]
        assert(info and info~="" and tips["Concentrated mana ×250"] and not tips["Concentrated mana ×251"])
    end
end
model.lang="en"
width,height=320,240
sample.available=0
mana.ready,mana.reason=false,"Missing catalyst sample"
assert(not render(model,214) and drawn["0 / 1"] and (drawn[mana.reason] or tips[mana.reason]))
sample.available,mana.ready=1,true
action,param=render(model,214)
assert(action=="craft" and param.id=="mana")
model.order_active,model.order_name,model.order_remaining=true,mana.name,67
sample.available,sample.held=0,1
assert(not render(model,214) and drawn["Held 1"] and drawn["1:07"] and drawn["Net output"])
assert(tips["Held 1"]:find("Stock 0",1,true))
model.order_active=false
render(model,240)
table.remove(model.recipes)
-- Omitted gas and fire must remain readable on narrow screens.
local note="Smoke escapes during this reaction."
model.recipes[#model.recipes+1]={id="powder",category="alchemy",alchemyMode="synthesis",name="Purifying powder",
    duration=120,ready=true,output=250,inputs={{name="Diamond",available=250,amount=250}},
    outputs={{name="Purifying powder",amount=250}},note=note}
render(model,245)
render(model)
assert(tips[note] and green_button(214))
render(model,240)
table.remove(model.recipes)
render(model,255)

-- Both alchemy lists page independently, including when production is active.
for _,mode in ipairs({"synthesis","decomposition"}) do
    for i=2,6 do
        model.recipes[#model.recipes+1]={id=mode..i,category="alchemy",alchemyMode=mode,name=mode.." "..i,
            output=1,duration=120,ready=true,inputs={}}
    end
end
model.order_active,model.order_name,model.order_remaining=true,"Medkit",65
render(model,243)
render(model)
assert(drawn["decomposition 6"] and drawn["2/2"] and drawn["1:05"] and not green_button(244))
assert(panels[210].y>=0 and buttons[244].y+9<=height)
render(model,254)
render(model)
assert(drawn.Teleportatium and drawn["1/2"] and drawn["1:05"] and not drawn["decomposition 6"])
render(model,243)
model.order_active=false
render(model,244)
action,param=render(model,214)
assert(action=="craft" and param.id=="synthesis6")
render(model,240)
render(model)
assert(drawn["synthesis 6"] and drawn["2/2"])
render(model,255)
render(model)
assert(drawn["decomposition 6"] and drawn["2/2"])
render(model,244)
action,param=render(model,214)
assert(action=="craft" and param.id=="decomposition6")
render(model,240)
render(model,251)
render(model)
assert(drawn.Medkit and drawn["Fire injector"] and not drawn.Teleportatium and not buttons[254] and not buttons[255])
assert(green_button(244) and not green_button(245))
render(model,245)
assert(not render(model,214) and drawn["Need stock"])
render(model,240)
render(model,244)
action,param=render(model,214)
assert(action=="craft" and param.id=="medical")
do
    local recipe={id="injector_essence",category="medical",name="Fire injector (fire essence)",output=1,duration=120,
        ready=false,reason="Not enough workshop resources.",inputs={{name="Fire essence",available=179,amount=180}}}
    table.insert(model.recipes,recipe)
    render(model,240)
    render(model,246)
    assert(not render(model,214) and drawn["179 / 180"] and tips["Fire essence  179 / 180"])
    assert(drawn[recipe.reason] or tips[recipe.reason])
    recipe.ready,recipe.inputs[1].available=true,180
    local order,request=render(model,214)
    assert(drawn["180 / 180"] and order=="craft" and request.id=="injector_essence")
    render(model,240)
    table.remove(model.recipes)
    render(model,244)
end
model.order_active,model.order_name,model.order_remaining=true,"Medkit",65
assert(not render(model,214) and drawn["Making: Medkit"] and drawn["1:05"])
model.order_remaining=5
assert(not render(model,214) and drawn["0:05"])
render(model,240)
render(model)
assert(drawn["Making: Medkit"] and drawn["0:05"] and not green_button(244))
model.lang="zh"
render(model)
assert(drawn["生产中：Medkit"] and drawn["0:05"])
model.lang="en"
model.order_active=false
model.recipes[2].ready,model.recipes[2].reason=false,"No storage space"
assert(not render(model) and not green_button(244))
render(model,244)
assert(not render(model,214) and drawn["No storage space"])
render(model,240)
render(model,252)
render(model)
assert(drawn["Magic grenade"] and not green_button(244))
render(model,244)
assert(not render(model,214) and drawn["Build the station"])
model.order_active=true
assert(not render(model,214) and drawn["Making: Medkit"] and drawn["Build the station"] and drawn["0:05"])
model.order_active=false
render(model,240)
render(model,253)
render(model)
assert(drawn["Injector pouch"] and green_button(244) and not buttons[214])
render(model,244)
render(model)
assert((drawn["Empty container"] or tips["Empty container"]) and drawn["2 / 1"] and drawn["100 / 50"])
action,param=render(model,214)
assert(action=="craft" and param.id=="pouch")
render(model,240)
-- Future equipment recipes share the same pagination and return navigation.
for i=1,5 do
    model.recipes[#model.recipes+1]={id="gear"..i,category="equipment",name="Gear "..i,output=1,duration=120,ready=true,inputs={}}
end
render(model,243)
render(model,244)
action,param=render(model,214)
assert(action=="craft" and param.id=="gear5")
render(model,240)
render(model)
assert(green_button(244) and buttons[244].name=="Gear 5" and not buttons[245])
render(model,213)
assert(render(model,216)=="preview_items")
assert(render(model,217)=="restock")
render(model,211)
render(model)
assert(drawn["[+] Hideout"] and panels[70] and panels[10] and not drawn.Workshop)
render(model,211)
model.debug=false
render(model)
assert(not render(model,217) and drawn.Workshop and not drawn["Reissue test pouch"])
-- Purchases use savings; an active workshop order does not gate the shop.
model.shopGoods={
    {id="water",category="materials",name="Water",quantity=250,price=20,ready=true},
    {id="dose",category="supplies",name="Fire injector",quantity=1,price=160,ready=true},
}
for i=2,6 do
    model.shopGoods[#model.shopGoods+1]={id="bulk"..i,category="materials",name="Material "..i,
        quantity=10,price=5,ready=true}
end
model.bankGold,model.walletGold,model.order_active=200,0,true
assert(not render(model,220))
render(model)
assert(drawn.Shop and buttons[256].name=="Materials" and buttons[257].name=="Consumables"
    and green_button(244) and buttons[244].name=="Water" and not buttons[258])
assert(not render(model,244))
render(model)
assert(drawn["Water"] and drawn["250"] and drawn["Materials"] and drawn["20"] and drawn["200"])
model.bankGold=NHStore.maxGold
for _,lang in ipairs({"zh","en"}) do
    model.lang=lang
    for _,sw in ipairs({320,427,640}) do
        width=sw
        render(model)
        local bench,b=panels[210],assert(buttons[258])
        assert(bench.y>=0 and b.x>=bench.x and b.x+GuiGetTextDimensions(nil,b.name)<=bench.x+bench.w
            and b.y+9<=bench.y+bench.h and green_button(258))
        assert(drawn[lang=="zh" and "确认购买" or "Confirm purchase"])
        assert(drawn[lang=="zh" and "存款余额" or "Savings"] and drawn[lang=="zh" and "价格" or "Price"])
        assert(drawn["9007199254740991"])
    end
end
action,param=render(model,258)
assert(action=="shop_buy" and param.id=="water")
model.bankGold,model.walletGold,model.shopGoods[1].ready,model.shopGoods[1].reason=19,10000,false,"Not enough stored gold."
assert(not render(model,258) and drawn["Not enough stored gold."] and drawn["19"])
model.bankGold,model.shopGoods[1].reason=100,"Material storage is full."
assert(not render(model,258) and drawn["Material storage is full."])
render(model,240)
render(model,243)
render(model)
assert(buttons[244].name=="Material 6" and drawn["2/2"])
render(model,257)
model.bankGold=200
render(model)
assert(buttons[244].name=="Fire injector" and not buttons[245] and not buttons[243])
render(model,244)
render(model)
assert(drawn.Supplies and drawn["160"] and drawn["1"])
action,param=render(model,258)
assert(action=="shop_buy" and param.id=="dose")
render(model,240)
render(model,256)
render(model)
assert(drawn["2/2"] and buttons[244].name=="Material 6")
render(model,212)
model.order_active=false
width=320
-- Return to the remembered spell page. Clamp it if the high slots disappear.
render(model,76)
render(model)
assert(drawn["[4]"])
model.warehouse_capacity.spell=1
render(model)
assert(drawn["[1]"])
render(model,301)
assert(drawn["[1]"])
local first=tiles[1008] -- three secure cells and four pouch cells precede this item grid
point(198,28,"press")
action,param=point(first.x+21,first.y+1,"release")
assert(action=="cancel_native" and param.entity==44)
local bench=panels[210]
point(198,28,"press")
cmd,arg=point(bench.x+8,bench.y+75,"release")
assert(cmd=="cancel_native" and arg.entity==44)
model.near=false
render(model)
assert(not panels[210] and panels[10] and not panels[70])
model.near,model.mode=true,"container"
render(model)
assert(not panels[210] and not panels[70])

-- Selecting previews a single project. Payment requires its own confirmation.
model.mode,model.near,model.popup="case",true,false
render(model,218)
render(model)
assert(green_button(244))
assert(not render(model,244))
render(model)
assert(drawn["Now: 48 slots"] and drawn["Next: 72 slots"] and drawn["350 / 200"] and green_button(241))
action,param=render(model,241)
assert(action=="buy_upgrade" and param.id=="warehouse_wand" and param.level==0)
render(model,243)
render(model)
assert(not green_button(248)) -- Salvage bench, missing oil.
render(model,248)
assert(not render(model,241) and drawn["Insufficient stock"])
render(model,240)
render(model,243)
render(model,244) -- Future support station.
assert(not render(model,241) and drawn["In development"])
render(model,219)
render(model)
assert(green_button(244))
render(model,244)
render(model)
assert(drawn["Now: 2 slots"] and drawn["Next: 3 slots"] and green_button(241))
action,param=render(model,241)
assert(action=="buy_upgrade" and param.id=="safe")
model.salvage_enabled,model.scrap=true,2
model.warehouse.spell[1].salvage_yield,model.warehouse.spell[1].salvage_name,model.warehouse.spell[1].salvage_stock=3,"Arcane scrap",2
render(model,76)
render(model)
local spell_tile=tiles[1004]
pointer={x=spell_tile.x+2,y=spell_tile.y+2,right=true}
assert(not render(model))
pointer.right=false
render(model)
assert(drawn["Arcane scrap +3"])
assert(not render(model,261))
pointer.right=true
render(model)
pointer.right=false
action,param=render(model,260)
assert(action=="salvage" and param.id==32 and param.kind=="spell" and param.slot==1)
do
    local view=model.warehouse.spell[1]
    view.spell_uses=0
    local bomb_value=NHEssences.values.BOMB
    view.essence={key="essence_high_energy",name="High-energy essence",amount=3*bomb_value,stock=1000,per_card=bomb_value}
    pointer.right=true
    render(model)
    pointer.right=false
    render(model)
    assert(drawn["[Essence]"] and drawn["Charges left"] and drawn["0"] and drawn["+"..(3*bomb_value)] and drawn["1k"])
    assert(tips["Per full card"]:find("20-cast",1,true) and tips["Per full card"]:find("375",1,true))
    local profile=NHEssences.healingProfiles.HEAL_BULLET
    view.essence={key="essence_healing",name="Healing essence",amount=3*profile.amount,stock=1000,
        per_card=profile.amount,basis=profile.en}
    local old_width,old_height=width,height
    for _,lang in ipairs({"en","zh"}) do
        model.lang=lang
        width,height=320,180
        view.essence.basis=profile[lang]
        render(model)
        local explanation=tips[lang=="zh" and "每张满额" or "Per full card"]
        assert(explanation:find(profile[lang],1,true))
        assert(explanation:find(lang=="zh" and "1 点标称治疗量折合 1 个治疗精华" or "1 HP of potential healing",1,true))
        assert(not explanation:find(lang=="zh" and "医疗包" or "medkit",1,true))
        assert(drawn[tostring(profile.amount)] and drawn["+"..(3*profile.amount)])
        assert(buttons[260] and panels[210].y>=0 and buttons[261].y<height)
    end
    width,height,model.lang=old_width,old_height,"en"
    assert(not render(model,263))
    render(model)
    assert(drawn["[Scrap]"] and drawn["Arcane scrap +3"] and not tips["Per full card"])
    local command,request=render(model,260)
    assert(command=="salvage" and request.mode=="scrap")
    pointer.right=true
    render(model)
    pointer.right=false
    view.essence.stock=NHStore.maxResourceAmount
    assert(not render(model,260) and drawn["Storage full"])
    view.essence.stock=0
    command,request=render(model,260)
    assert(command=="salvage" and request.mode=="essence" and request.id==32)
    model.essences={}
    for i,key in ipairs(NHEssences.order) do
        model.essences[i]={name=NHEssences.types[key].en,amount=i==1 and 1234000 or 0}
    end
    local sw,sh=width,height
    width=640
    render(model,82)
    render(model)
    assert(drawn.Healing and drawn["1.2M"] and drawn["0"] and drawn["[1]"])
    render(model,301)
    render(model)
    assert(drawn.Enhancement and drawn["[2]"] and not drawn.Healing)
    width,height,model.lang=320,180,"zh"
    for i,key in ipairs(NHEssences.order) do model.essences[i].name=NHEssences.types[key].zh end
    render(model)
    assert(drawn["强化"] and panels[70].y>=0 and buttons[300].y<height)
    render(model,300)
    render(model)
    assert(drawn["酸液"] and drawn["1.2M"])
    point(panels[70].x+9,buttons[82].y+18)
    assert(drawn["治疗精华  1234000"])
    width,height,model.lang=sw,sh,"en"
end
model.warehouse.containers[2]={kind="potion",id=162,name="Empty flask",salvage_yield=1,salvage_name="Container scrap",salvage_stock=7}
render(model,77)
render(model)
local empty_flask=tiles[1005]
pointer={x=empty_flask.x+1,y=empty_flask.y+1,right=true}
render(model)
pointer.right=false
render(model)
assert(drawn["Container scrap +1"] and drawn["Current scrap 7"])
model.warehouse.containers[2].salvage_yield=nil -- refilled before confirmation
assert(not render(model,260))
model.perkCapacity,model.perkCells=1,{}
model.native_slots[2].kind="perk"
point(108,28,"press")
local trait_tile=tiles[1004]
action,param=point(trait_tile.x+2,trait_tile.y+2,"release")
assert(action=="equip_perk" and param.safeSlot==1 and param.entity==43)
model.perkCells[1]={kind="perk",name="Fire immunity",entity=99}
point(trait_tile.x+2,trait_tile.y+2,"press")
action,param=point(148,28,"release")
assert(action=="unequip_perk" and param.safeSlot==1 and param.storedId==99)

-- Cards can cross directly between the perk strip and either store. Use
-- distinct cell numbers and IDs to check both sides of each request.
model.perkCapacity=2
model.packablePerk={entity=135,name="Explosion immunity"}
model.secure_loot[2]={kind="perk",name="Fire immunity",id=71}
model.warehouse.supplies={[3]={kind="perk",name="Melee immunity",id=72}}
render(model,78)
render(model)
local function drag_tiles(source,target)
    local a,b=tiles[1000+source],tiles[1000+target]
    point(a.x+2,a.y+2,"press")
    return point(b.x+2,b.y+2,"release")
end
local function assert_perk_move(actual,request,command,container,storageSlot,perkSlot,id)
    assert(actual==command and request.container==container and request.storageSlot==storageSlot
        and request.perkSlot==perkSlot and request.entity==id)
end
-- Three case slots, two perk slots, then the warehouse.
action,param=drag_tiles(2,5)
assert_perk_move(action,param,"equip_stored_perk","safe",2,2,71)
action,param=drag_tiles(8,5)
assert_perk_move(action,param,"equip_stored_perk","warehouse",3,2,72)
assert(not drag_tiles(2,4),"occupied perk slot")
assert(not drag_tiles(1,5),"a flask cannot be equipped as a perk")
assert(not drag_tiles(4,2),"occupied case slot")
assert(not drag_tiles(4,8),"occupied warehouse slot")
model.secure_loot[1]=nil
action,param=drag_tiles(4,1)
assert_perk_move(action,param,"store_equipped_perk","safe",1,1,99)
action,param=drag_tiles(4,7)
assert_perk_move(action,param,"store_equipped_perk","warehouse",2,1,99)
render(model,75)
render(model)
assert(not drag_tiles(4,7),"cannot put an equipped perk in wand storage")
render(model,78)
render(model)
local stash_src=tiles[1008]
point(stash_src.x+1,stash_src.y+1,"press")
model.near=false
local dest=tiles[1005]
assert(not point(dest.x+1,dest.y+1,"release"),"warehouse drag cannot continue outside the hideout")
render(model)
action,param=drag_tiles(2,5)
assert_perk_move(action,param,"equip_stored_perk","safe",2,2,71)
action,param=drag_tiles(4,1)
assert_perk_move(action,param,"store_equipped_perk","safe",1,1,99)
-- Releasing a dragged card over the pack button consumes neither the card nor
-- the nearby altar choice. The next intentional button click is still usable.
local equipped_tile,pack=tiles[1004],buttons[4201]
point(equipped_tile.x+1,equipped_tile.y+1,"press")
pointer={x=pack.x+1,y=pack.y+1,released=true}
assert(not render(model,4201))
pointer.released=false
action,param=render(model,4201)
assert(action=="pack_perk" and param.entity==135)
