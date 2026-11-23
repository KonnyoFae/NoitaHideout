local width, height = 427, 240
local click, action, argument
local drawn,panels,tips,badges,glyphRuns = {},{},{},{},{}
local frame = 0
local pointer = {x = 0, y = 0}
function GameGetFrameNum() return frame end
function InputIsMouseButtonDown() return pointer.down == true end
function InputIsMouseButtonJustDown(which) return which==pointer.wheel or (which==2 and pointer.right) or (which==1 and pointer.pressed) or false end
function InputIsMouseButtonJustUp() return pointer.released == true end
function GameGetCameraBounds() return 0, 0, width, height end
function DEBUG_GetMouseWorld() return pointer.x, pointer.y end
function GuiCreate() return {} end
function GuiStartFrame() drawn,panels,tips,badges,glyphRuns = {},{},{},{},{} end
function GuiGetScreenDimensions() return width, height end
function GuiZSet() end
function GuiZSetForNextWidget() end
local scroll,scroll_key
local widgetOptions,animation={},nil
function dofile_once(path)
    assert(path=="data/scripts/lib/utilities.lua")
    GUI_OPTION={AlwaysClickable=3,NoPositionTween=6,Layout_NoLayouting=15}
end
function GuiOptionsAddForNextWidget(_,option) widgetOptions[option]=true end
function GuiAnimateBegin() assert(not animation); animation={} end
function GuiAnimateAlphaFadeIn(_,_,speed,step,reset) animation.hidden=speed==0 and step==0 and reset end
function GuiAnimateEnd() assert(animation); animation=nil end
function GuiIdPushString(_,key) assert(not scroll_key); scroll_key=key end
function GuiIdPop() assert(scroll_key and not scroll); scroll_key=nil end
function GuiBeginScrollContainer(_,id,x,y,w,h,focusable)
    assert(scroll_key and not scroll and w>0 and h>0)
    scroll={id=id,x=x,y=y,w=w,h=h,key=scroll_key,offset=0}
    scroll.options,scroll.hidden,scroll.focusable=widgetOptions,animation and animation.hidden,focusable
    widgetOptions={}
    panels[id]=scroll
end
function GuiEndScrollContainer() assert(scroll); scroll=nil end
local next_color,image_colors={},{}
local shieldImages,shieldText={},{}
local shieldStripes={}
local ammoText={}
local rescueText={}
local hudImages,noticeText={},{}
function GuiColorSetForNextWidget(_,r,g,b,a) next_color={r,g,b,a} end
local tipbox
function GuiImageNinePiece(_,id,x,y,w,h)
    panels[id]={x=x,y=y,w=w,h=h}
    if id==200 then tipbox={x=x,y=y,w=w,h=h} end
end
local tiles={}
local tracks={}
function GuiImage(_,id,x,y,sprite,alpha,scale,scaleY,rotation,playback,frameName)
    if id==7100 or id==7102 or id==7110 or id==7112 or id==7352 then tracks[id]={x=x,y=y,h=scaleY,frame=frame} end
    if scroll_key and scroll_key:match("^shield_stripes_") then
        shieldStripes[#shieldStripes+1]={cell=tonumber(scroll_key:match("(%d+)$")),x=x,y=y,w=scale,h=scaleY,a=alpha,color=next_color}
    end
    if sprite=="mods/noita_hideout/files/slot_digits.xml" then
        assert(rotation==0 and playback==1 and scaleY==scale)
        local base=id-id%32
        if id==base then glyphRuns[base]={text="",x=x,y=y,h=10*scale,scale=scale} end
        local run=assert(glyphRuns[base])
        local char=frameName=="slash" and "/" or frameName=="times" and "×" or frameName
        assert(char:match("^%d$") or char=="/" or char=="×")
        assert(math.abs(x-run.x-(id-base)*7*scale)<0.001 and run.y==y)
        run.text,run.w=run.text..char,x+6*scale-run.x
    end
    if id>5700 and id<5740 then shieldImages[id]={x=x,y=y,w=scale,h=scaleY,a=alpha} end
    if id>=5800 and id<=5845 then hudImages[id]={x=x,y=y,w=scale,h=scaleY,a=alpha,color=next_color} end
    image_colors[id],next_color=next_color,{}
    drawn[sprite]=true
    if sprite=="data/ui_gfx/inventory/quick_inventory_box.png" then tiles[id]={x=x,y=y,scale=scale} end
end
function GuiTooltip(_,title,body) tips[title]=body or "" end
function GuiGetImageDimensions() return 20,20 end
local hudSettings={UI_FULL_INVENTORY_OFFSET_X=170,UI_BARS2_OFFSET_X=-40,UI_BARS_SCALE=1,GUI_HP_MULTIPLIER=25}
function MagicNumbersGetValue(k) return tostring(hudSettings[k] or 20) end
function GuiGetTextDimensions(_, value, scale)
    local w = 0
    for letter in value:gmatch("[^\128-\191][\128-\191]*") do
        w = w + (#letter > 1 and 8 or 4)
    end
    return w * (scale or 1), 9 * (scale or 1)
end
function GuiText(_, x, y, value, scale)
    drawn[value]=true
    noticeText[value]={x=x,y=y,scale=scale or 1,color=next_color}
    if value:match("^保险") or value:match("^同行") or value:match("^本次保金") or value:match("^保金上限") then
        rescueText[value]={x=x,y=y,scale=scale or 1}
    end
    if y==62 or y==72 then ammoText[value]={x=x,y=y,color=next_color} end
    if value:match("^%[.*%]%+%[.*%]$") then shieldText={value=value,x=x,y=y} end
end
local buttons={}
function GuiButton(_, id, x, y, value, scale)
    if scroll then x,y=x+scroll.x,y+scroll.y-scroll.offset end
    buttons[id]={x=x,y=y,name=value,color=next_color,scroll=scroll,scale=scale or 1}
    drawn[value] = true
    return id == click
end
function GuiImageButton(_, id) return id == click end

dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
function CellFactory_GetType() return -1 end
dofile("mods/noita_hideout/files/transfers.lua")
dofile("mods/noita_hideout/files/perks.lua")
NHInventoryUse=dofile("mods/noita_hideout/files/inventory_use.lua")
dofile("mods/noita_hideout/files/native_items.lua")
dofile("mods/noita_hideout/files/ui.lua")
local function render(model, widget)
    frame = frame + 1
    buttons={}
    click, action, argument = widget, nil, nil
    NHUI.draw(model, function(command, item)
        assert(not action, "multiple actions on a single input")
        action, argument = command, item
    end)
    for _,run in pairs(glyphRuns) do badges[run.text]=run; drawn[run.text]=true end
    assert(not scroll and not scroll_key and not animation and not next(widgetOptions),"unclosed GUI scope")
    return action, argument
end
do
    local a={rounds=24,max=36,reserve=162,modes=NHFirearms.modes.guns.scatter_revolver,index=3,keyName="B"}
    local m={open=false,near=false,lang="en",ammo=a}
    render(m)
    assert(drawn["Scatter  24/36  ·  4 shots"] and drawn["[B] Mode   [R] Reload  Reserve 162"])
    a.loading=18
    render(m)
    assert(drawn["Reload 0.3s  Reserve 162"])
    m.lang,a.menu,a.hover="zh",true,2
    render(m)
    assert(drawn["> 马格南 · 3 <"] and drawn["霰弹 · 6"] and drawn["松开确认"])
    a.menu,a.modes,a.index=false,NHFirearms.staffModes,4
    a.mimicTarget={x=90,y=65,status="ready",form="test.xml"};render(m)
    assert(drawn["可拟态"] and noticeText["可拟态"].x<90 and noticeText["可拟态"].y<65)
    a.mimicTarget.status="unsupported";a.mimicTarget.form=nil;render(m);assert(drawn["未收录形态"] and not drawn["可拟态"])
    m.lang="en";render(m);assert(drawn["Unsupported form"])
    a.mimicTarget=nil;render(m);assert(not drawn["Unsupported form"])
    render({mimicFrames=61,lang="zh"});assert(drawn["拟态剩余 2 秒"])
    render({mimicFrames=1,lang="en"});assert(drawn["Mimic: 1s"])
end
-- Inspect through the same wheel input a player uses. Hidden controls are
-- intentionally absent from the widget tree until the viewport reaches them.
local function seekWorkshop(m,found)
    if found() then return true end
    local track=tracks[7102]
    if not track or track.frame~=frame then return false end
    for _,key in ipairs({5,4}) do
        pointer={x=track.x-2,y=track.y+3,wheel=key}
        for _=1,24 do
            render(m)
            if found() then pointer.wheel=nil; return true end
        end
    end
    pointer.wheel=nil
    return false
end
local function reveal(model,id)
    assert(seekWorkshop(model,function() return buttons[id] end),"cannot reach button "..id)
    return buttons[id]
end
local function see(m,text)
    return seekWorkshop(m,function() return drawn[text] or tips[text] end)
end
local function green_button(id)
    local b=buttons[id]
    return b and b.color[1]==0.62 and b.color[2]==0.95 and b.color[3]==0.75
end

local function wheelAt(m,track,button,ticks)
    render(m)
    local bar=tracks[track]
    assert(bar and bar.frame==frame,debug.traceback("missing active scrollbar "..track))
    pointer={x=bar.x-2,y=bar.y+3,wheel=button}
    for _=1,ticks or 1 do render(m) end
    pointer.wheel=nil
end
local function listItem(name)
    for id,b in pairs(buttons) do if b.name==name then return id end end
    error("missing list item "..name)
end

local function native(lane,col,x,id,kind)
    return {key="native",lane=lane,col=col,xslot=x,yslot=0,entity=id,kind=kind,parent=lane=="spell" and 3 or 2}
end
local model={lang="en",open=false,near=false,status=""}
assert(not render(model,2))
do
    local function overlay(cells,charge,repair,maxHp)
        shieldImages,shieldText,shieldStripes={},{},{}
        model.shield={cells=cells,charge=charge*NHShields.cell,repair=repair,maxHp=maxHp}
        render(model)
    end
    overlay(2,2,0,4)
    local innerRight=width-41
    assert(shieldImages[5711].x+shieldImages[5711].w==innerRight and shieldImages[5712].x==innerRight-40)
    assert(shieldImages[5711].y==21 and shieldImages[5711].h==4 and shieldImages[5711].a==0.82)
    assert(shieldText.value=="[50]+[50]" and shieldText.x+GuiGetTextDimensions(nil,shieldText.value)==innerRight and shieldText.y+9<=shieldImages[5711].y-3)
    overlay(2,2,0,40)
    assert(shieldImages[5702].x==innerRight-40 and shieldText.value=="[500]+[500]")
    overlay(3,3,0,40)
    assert(shieldImages[5703].x==innerRight-60)
    overlay(4,2.5,0,4)
    assert(shieldText.value=="[100]+[25]" and shieldImages[5704].x==innerRight-80)
    assert(shieldImages[5713].w==10 and not shieldImages[5714])
    assert(#shieldStripes>0)
    local rows={}
    for _,stripe in ipairs(shieldStripes) do
        local fill=assert(shieldImages[5710+stripe.cell])
        assert(stripe.x>=fill.x and stripe.x+stripe.w<=fill.x+fill.w)
        assert(stripe.y>=fill.y and stripe.y+stripe.h<=fill.y+fill.h)
        assert(stripe.color[1]>stripe.color[2] and stripe.color[3]>stripe.color[1])
        rows[stripe.y]=true
    end
    assert(rows[21] and rows[24])
    overlay(4,1,120,5)
    assert(shieldText.value=="[0]+[62.5]" and shieldImages[5732] and not shieldImages[5712])
    overlay(2,0,0,4)
    assert(shieldText.value=="[0]+[0]" and not shieldImages[5711] and not shieldImages[5731])
    width=640
    hudSettings.UI_BARS2_OFFSET_X,hudSettings.UI_BARS_POS_Y,hudSettings.UI_BARS_SCALE=-65,28,2
    overlay(3,3,0,1000000)
    assert(shieldImages[5711].x+shieldImages[5711].w==width-66 and shieldImages[5711].y==29 and shieldImages[5711].h==8)
    assert(shieldText.x>=width/2 and shieldText.y+9<shieldImages[5711].y)
    width=427
    hudSettings.UI_BARS2_OFFSET_X,hudSettings.UI_BARS_POS_Y,hudSettings.UI_BARS_SCALE=-40,20,1
    model.shield=nil
    shieldImages,shieldText={},{}
    render(model)
    assert(not next(shieldImages) and not next(shieldText))
end
model.open,model.mode,model.pouch_location,model.case_count=true,"case","safe",2
model.capacity,model.revision,model.secure_loot=4,1,{[3]={kind="pouch",name="Injector pouch #17",id=17}}
model.native_slots={native("wand",0,0,42,"wand"),native("tool",4,0,43,"dose"),
    native("spell",0,0,44,"spell"),native("spell",5,5),native("tool",6,2),native("wand",3,3)}
local function point(x,y,event)
    pointer={x=x,y=y,down=event=="press",pressed=event=="press",released=event=="release"}
    return render(model)
end
local cx,cy=5,height-72-5
render(model)
local shift
function InputIsKeyDown(key) return key==shift end
shift=229
pointer={x=28,y=28,pressed=true,down=true}
assert(NHUI.quickTarget().entity==42 and not NHUI.useTarget())
assert(not render(model) and NHUI.quickTarget().entity==42)
shift=nil
assert(not point(cx+12,cy+30,"release"))
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
for i=1006,1008 do assert(tiles[i].x-tiles[i-1].x==20) end -- pouch
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
model.cells[4]={subtype="frost",remaining=3,count=1}
point(cx+72,cy-38)
assert(drawn["Frost injector"] and drawn["60 seconds of freeze immunity"])
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
assert(not buttons[36])
point(198,28,"press")
cmd,arg=point(cx+73,cy+30,"release")
assert(arg.safeSlot==4)
point(cx+12,cy+36,"press")
model.open=false
render(model)
model.open=true
assert(not point(148,28,"release"))
print("Native inventory drag, spell row, exact slot, upgrade pages and close cancellation passed.")

model.capacity=3
-- Right warehouse, native tile pitch, automatic filing and materials tab.
model.near,model.warehouse=true,{}
model.warehouse_capacity={wand=48,spell=48,containers=48,supplies=48,equipment=48,collection=48,materials=16}
model.debug=true
local profile={safeCapacity=2,levels={},materials={water=500,sand=350,soil=150,slime=200,gunpowder_unstable=80,gunpowder=60},resources={},warehouse={}}
model.progression=NHStore.progressMenu(profile,"en")
model.recipes={
    {id="stable",category="alchemy",alchemyMode="synthesis",name="Teleportatium",output=500,duration=120,ready=true,inputs={{name="Slime",available=300,amount=250}}},
    {id="medical",category="medical",name="Medkit",icon="mods/noita_hideout/files/items/medkit.png",output=1,duration=5,ready=true,inputs={{name="Slime",available=300,amount=100}}},
    {id="injector",category="medical",name="Fire injector",output=1,duration=120,ready=false,reason="Need stock",inputs={}},
    {id="grenade",category="weapons",name="Magic grenade",icon="mods/noita_hideout/files/items/grenade.png",output=8,duration=10,ready=false,unlocked=false,reason="Build the station",inputs={}},
    {id="pouch",category="containers",name="Injector pouch",output=1,duration=120,ready=true,
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
-- Scrolling keeps exact destination slots in an otherwise empty warehouse.
local page_size=math.floor((panels[70].w-16)/20)*4
model.warehouse_capacity.spell=page_size*7
local item_panel=panels[70]
do
    render(model)
    local bar=assert(tracks[7112])
    pointer={x=bar.x-4,y=bar.y+4}
    for _,pulse in ipairs({false,5,4}) do
        pointer.wheel=pulse
        render(model)
        local hit=assert(panels[2],"hover must register a native wheel target even before the first notch")
        assert(hit.key=="nh_wheel/stash/spell" and hit.hidden and hit.focusable==false)
        assert(hit.options[GUI_OPTION.AlwaysClickable] and hit.options[GUI_OPTION.NoPositionTween])
        assert(pointer.x>=hit.x and pointer.x<hit.x+hit.w and pointer.y>=hit.y and pointer.y<hit.y+hit.h)
    end
    pointer.y,pointer.wheel=bar.y-2,5
    render(model)
    assert(not panels[2],"a header must leave the native wheel alone")
    pointer.y,pointer.wheel=bar.y+4,nil
    model.open=false
    render(model)
    assert(not panels[2],"closing the inventory must release the wheel")
    model.open=true
    render(model)
end
wheelAt(model,7112,5)
point(198,28,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="place" and arg.safeSlot==1+3*page_size/4)
wheelAt(model,7112,5)
point(198,28,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="place" and arg.safeSlot==1+6*page_size/4)
-- A committed placement reveals the actual row even when the stash was folded.
render(model,71)
NHUI.showTransfer("warehouse","spell",page_size*5+1)
render(model)
assert(buttons[76].color[1]==1 and not buttons[301])
render(model,39)
model.capacity=14
NHUI.showTransfer("safe","potion",13)
render(model)
assert(tracks[7110].frame==frame and tiles[1001])
model.capacity=3
NHUI.showTransfer("safe","potion",1)
render(model)
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
NHUI.showTransfer("docks","potion",2)
render(model)
assert(drawn.Flask and drawn["Powder pouch"] and drawn.Empty)
assert(not panels[299])
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
assert(drawn["1k"] and drawn["1.2M"] and buttons[188].x>load_button.x and buttons[188].y==load_button.y)
local button2=buttons[188]
point(button2.x+1,button2.y+1)
assert(drawn["M2  1000"])
wheelAt(model,7112,5)
assert(drawn["M9"] and not drawn["M2"])
wheelAt(model,7112,4)
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

-- Drag across a category label, then release on the destination page's first slot.
local function dragFlaskAcrossTab(tab)
    local source=tiles[1004]
    point(source.x+2,source.y+2,"press")
    local b=buttons[tab]
    pointer={x=b.x+GuiGetTextDimensions(nil,b.name,b.scale)-0.5,y=b.y+2,down=true}
    render(model)
    render(model)
    assert(buttons[tab].color[1]==1,"hovering a category with a flask switches to it")
    local target=tiles[1004]
    local command,arg=point(target.x+2,target.y+2,"release")
    assert(command=="move_dock" and arg.entity==123 and arg.safeSlot==1)
end
model.warehouse.containers[1].dockSlot=1
model.docks[1]=nil
dragFlaskAcrossTab(80)
model.docks[1],model.warehouse.containers[1]=model.warehouse.containers[1],nil
render(model)
dragFlaskAcrossTab(77)
model.warehouse.containers[1]=model.docks[1]
render(model)

-- The shop keeps the balance and both transfers fixed above its goods.
local function testShopTransfers()
    model.walletGold,model.bankGold,model.shopGoods=234,120345,{}
    render(model,212)
    model.open=false
    render(model)
    model.open=true
    render(model)
    assert(drawn.Convert and drawn["Savings:"] and drawn["120k"] and tips["Savings:"]=="120345" and panels[70])
    assert(not buttons[224] and not buttons[270] and not buttons[276])
    assert(tips["[Deposit]"]:find("234",1,true))
    assert(tiles[1004].x==first_tile.x,"shopping keeps warehouse items accessible")
    local depositX,withdrawX=buttons[274].x,buttons[275].x
    for _,pair in ipairs({{0,"0"},{999,"999"},{1000,"1k"},{1150,"1.15k"},{12345,"12.3k"},
        {999999,"999k"},{1000000,"1M"},{1234567890,"1.23B"},{1000000000000,"1T"},{NHStore.maxGold,"9P"}}) do
        model.bankGold=pair[1]
        render(model)
        assert(drawn[pair[2]] and tips["Savings:"]==string.format("%.0f",pair[1]))
        assert(buttons[274].x==depositX and buttons[275].x==withdrawX)
    end
    model.bankGold=120345
    render(model)
    local function press(id)
        local b=buttons[id]
        local action,arg=point(b.x+1,b.y+1,"press")
        pointer.pressed=false
        return action,arg
    end
    local function apply(id,amount,action,arg)
        assert(action=="bank_transfer" and arg.direction==(id==274 and "deposit" or "withdraw") and arg.amount==amount)
        local delta=id==274 and amount or -amount
        model.walletGold,model.bankGold=model.walletGold-delta,model.bankGold+delta
    end
    apply(274,1,press(274))
    for i=1,65 do
        local action,arg=render(model)
        if i>=24 and (i-24)%6==0 then apply(274,i<48 and 5 or 10,action,arg)
        else assert(not action,"no transfer between repeat ticks") end
    end
    assert(not point(pointer.x,pointer.y,"release"))
    apply(275,1,press(275))
    pointer.x=buttons[274].x+1
    for i=1,31 do assert(not render(model),"sliding to the other button must not reverse a transfer") end
    assert(not point(pointer.x,pointer.y,"release"))

    model.bankGold,model.walletGold=NHStore.maxGold-3,100
    apply(274,1,press(274))
    for i=1,23 do assert(not render(model)) end
    apply(274,2,render(model))
    for i=1,30 do assert(not render(model) and not green_button(274),"stop when the savings limit is reached") end
    point(pointer.x,pointer.y,"release")
    model.walletGold,model.bankGold=0,3
    apply(275,1,press(275))
    for i=1,23 do assert(not render(model)) end
    apply(275,2,render(model))
    for i=1,30 do assert(not render(model) and not green_button(275),"stop when savings run out") end
    point(pointer.x,pointer.y,"release")
    model.walletGold=nil
    assert(not press(274) and not green_button(274) and tips["[Deposit]"]=="Wallet unavailable")
    model.walletInfinite=true
    assert(not press(275) and tips["[Withdraw]"]=="Transfers unavailable with infinite gold")
    model.walletGold,model.bankGold,model.walletInfinite=1000,100,false

    for _,lang in ipairs({"zh","en"}) do
        model.lang=lang
        for _,sw in ipairs({320,427,640}) do
            width=sw
            render(model)
            local panel=panels[210]
            local a,b=buttons[274],buttons[275]
            assert(not a.scroll and not b.scroll and a.y==b.y and a.x>=panel.x and b.y+9*b.scale<=panel.y+panel.h)
            local title=noticeText[lang=="zh" and "存款余额：" or "Savings:"]
            local balance=noticeText["100"]
            assert(buttons[220].y<buttons[212].y or (buttons[220].y==buttons[212].y and buttons[220].x<buttons[212].x))
            assert(title.y==a.y and balance.y==a.y)
            assert(title.x+GuiGetTextDimensions(nil,lang=="zh" and "存款余额：" or "Savings:",title.scale)<a.x)
            assert(a.x+GuiGetTextDimensions(nil,a.name,a.scale)<balance.x)
            assert(balance.x+GuiGetTextDimensions(nil,"100",balance.scale)<b.x)
            assert(math.abs(buttons[269].y-a.y-13*buttons[220].scale)<0.01)
            assert(b.x+GuiGetTextDimensions(nil,b.name,b.scale)<=panel.x+panel.w)
        end
    end
    width=427
    render(model)
    apply(274,1,press(274))
    model.near=false
    render(model)
    model.near=true
    for i=1,30 do assert(not render(model),"leaving the hideout cancels a held transfer") end
    point(pointer.x,pointer.y,"release")
    apply(274,1,press(274))
    render(model,212)
    render(model,220)
    for i=1,30 do assert(not render(model),"switching tabs cancels a held transfer") end
    point(pointer.x,pointer.y,"release")
    apply(274,1,press(274))
    model.open=false
    render(model)
    model.open=true
    for i=1,30 do assert(not render(model),"closing the inventory cancels a held transfer") end
    point(pointer.x,pointer.y,"release")

    local case_flask,bank_button=tiles[1001],buttons[274]
    point(case_flask.x+1,case_flask.y+1,"press")
    pointer={x=bank_button.x+1,y=bank_button.y+1,down=true}
    for i=1,30 do assert(not render(model),"dragging an item cannot start a transfer") end
    point(pointer.x,pointer.y,"release")
    render(model,212)
    render(model)
    assert(not buttons[274] and panels[70])
end
testShopTransfers()
render(model,71)
render(model)
assert(drawn["[+] Stash"] and not drawn.Materials)
model.near=false
render(model)
assert(not drawn["[+] Stash"])

-- Three bottom panels stay separate at different widths, including the open pouch.
model.near,model.popup=true,true
render(model,71)
assert(buttons[274] and buttons[275])
render(model,212)
for _,size in ipairs({{640,360},{427,240},{320,240}}) do
    width,height=size[1],size[2]
    render(model)
    local stash,bench,secure,pouch=panels[70],panels[210],panels[10],panels[37]
    assert(secure.x==5 and secure.x+secure.w<bench.x and bench.x+bench.w<stash.x)
    assert(stash.x+stash.w==width-5 and pouch.x==secure.x and pouch.y+pouch.h<secure.y)
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
assert(drawn["Teleportatium ×500"] and drawn["300 / 250"] and drawn["Delivery"] and drawn["Instant"] and green_button(214))
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
assert(drawn["交付"] and drawn["每批产出"] and drawn["即时完成"] and drawn["< 分解"] and drawn["确认分解"])
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
        local b,bench=reveal(model,214),panels[210]
        assert(bench.y>=0 and b.y>=bench.y and b.y+9*b.scale<=bench.y+bench.h)
        local catalyst=lang=="zh" and "催化剂（完工归还）" or "Catalyst (returned)"
        assert(drawn[catalyst] or tips[catalyst])
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

-- Both alchemy lists scroll independently, including when production is active.
for _,mode in ipairs({"synthesis","decomposition"}) do
    for i=2,18 do
        model.recipes[#model.recipes+1]={id=mode..i,category="alchemy",alchemyMode=mode,name=mode.." "..i,
            output=1,duration=120,ready=true,inputs={}}
    end
end
model.order_active,model.order_name,model.order_remaining=true,"Medkit",65
width,height=640,360
wheelAt(model,7100,5,8)
render(model)
assert(drawn["decomposition 18"] and drawn["1:05"] and not green_button(244))
assert(panels[210].y>=0 and (buttons[244].y+9<=height or (buttons[244].scroll and buttons[244].scroll.y+buttons[244].scroll.h<=height)))
render(model,254)
render(model)
assert(drawn.Teleportatium and drawn["1:05"] and not drawn["decomposition 18"])
model.order_active=false
wheelAt(model,7100,5,8)
render(model,listItem("synthesis 18"))
action,param=render(model,214)
assert(action=="craft" and param.id=="synthesis18")
render(model,240)
render(model)
assert(drawn["synthesis 18"] and not drawn.Teleportatium)
render(model,255)
render(model)
assert(drawn["decomposition 18"])
render(model,listItem("decomposition 18"))
action,param=render(model,214)
assert(action=="craft" and param.id=="decomposition18")
render(model,240)
render(model,251)
render(model)
assert(drawn.Medkit and drawn["Fire injector"] and not drawn.Teleportatium and not buttons[254] and not buttons[255])
assert(drawn["mods/noita_hideout/files/items/medkit.png"])
assert(green_button(244) and not green_button(245))
render(model,245)
assert(not render(model,214) and drawn["Need stock"])
render(model,240)
render(model,244)
action,param=render(model,214)
assert(action=="craft" and param.id=="medical" and drawn["Instant"])
assert(drawn["mods/noita_hideout/files/items/medkit.png"])
do
    local recipe={id="injector_essence",category="medical",name="Fire injector (fire essence)",output=1,duration=120,
        ready=false,reason="Not enough workshop resources.",inputs={{name="Fire essence",available=5,amount=6}}}
    table.insert(model.recipes,recipe)
    render(model,240)
    render(model,246)
    assert(not render(model,214) and drawn["5 / 6"] and tips["Fire essence  5 / 6"])
    assert(drawn[recipe.reason] or tips[recipe.reason])
    recipe.ready,recipe.inputs[1].available=true,6
    local order,request=render(model,214)
    assert(drawn["6 / 6"] and order=="craft" and request.id=="injector_essence")
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
assert(drawn["mods/noita_hideout/files/items/grenade.png"])
render(model,244)
assert(not render(model,214) and drawn["Build the station"])
assert(drawn["mods/noita_hideout/files/items/grenade.png"])
model.order_active=true
assert(not render(model,214) and drawn["Making: Medkit"] and drawn["Build the station"] and drawn["0:05"])
model.order_active=false
render(model,240)
render(model,266)
render(model)
assert(not drawn["Gear 1"] and drawn["Injector pouch"] and green_button(244) and not buttons[214])
render(model,244)
render(model)
assert((drawn["Empty container"] or tips["Empty container"]) and drawn["2 / 1"] and drawn["100 / 50"])
action,param=render(model,214)
assert(action=="craft" and param.id=="pouch")
render(model,240)
-- Equipment is separate from container recipes.
for i=1,18 do
    model.recipes[#model.recipes+1]={id="gear"..i,category="equipment",name="Gear "..i,output=1,duration=120,ready=true,inputs={}}
end
render(model,253)
render(model)
assert(not drawn["Injector pouch"])
wheelAt(model,7100,5,8)
render(model,listItem("Gear 18"))
action,param=render(model,214)
assert(action=="craft" and param.id=="gear18")
render(model,240)
render(model)
assert(green_button(listItem("Gear 18")) and not drawn["Gear 1"])
render(model,213)
assert(render(model,216)=="preview_items")
assert(render(model,217)=="restock")
assert(render(model,480)=="test_cards" and render(model,481)=="test_wallet")
render(model,211)
render(model)
assert(drawn["[+] Hideout"] and panels[70] and panels[10] and not drawn.Workshop)
render(model,211)
model.debug=false
render(model)
assert(not render(model,217) and drawn.Workshop and not drawn["Reissue test pouch"])
do
    local travel=dofile("mods/noita_hideout/files/travel/routes.lua")
    function GetParallelWorldPosition(x) return math.floor(x/35840+0.5),0 end
    function BiomeMapGetName(x,y)
        if y==1536 then return "$biome_excavationsite" end
        if y==512 then return "$biome_coalmine" end
        return "$biome_holymountain"
    end
    local stations=""
    for n=1,10 do stations=stations..(n*35840)..",1024;" end
    stations=stations.."-35840,1024;0,1024;"
    local view=travel.collect(stations,0,0)
    local function clickText(name)
        assert(drawn[name],name.." at "..width.."x"..height)
        local p=noticeText[name]
        pointer={x=p.x+1,y=p.y+1,pressed=true}
        local cmd,arg=render(model)
        pointer.pressed=nil
        return cmd,arg
    end
    local sw,sh,lang=width,height,model.lang
    for _,size in ipairs({{640,360},{320,180}}) do
        width,height,model.lang=size[1],size[2],"zh"
        model.travel=view
        render(model)
        local panel=assert(panels[7350])
        assert(drawn["[+] 藏身处"] and panel.y+panel.h<=panels[210].y and panel.x+panel.w<panels[70].x)
        assert(drawn["[-] 主世界"] and drawn["已解锁 2 站"] and drawn["煤矿矿坑入口圣山"] and drawn["来自矿场"])
        assert(not clickText("[-] 主世界")); render(model)
        assert(not drawn["煤矿矿坑入口圣山"] and drawn["[+] 主世界"])
        wheelAt(model,7352,5,10)
        assert(not clickText("[+] 东 10 平行世界")); render(model)
        wheelAt(model,7352,5,1)
        local cmd,index=clickText("煤矿矿坑入口圣山")
        assert(cmd=="travel_to" and view.rows[index].x==10*35840 and view.rows[index].y==1024)
        view.gateKind,view.gateX,view.gateY="mountain",10*35840,1024
        render(model)
        assert(drawn["> 煤矿矿坑入口圣山"])
        local bar=tracks[7352]
        pointer={x=bar.x+1,y=bar.y+1,pressed=true}
        assert(not render(model),"scrollbar clicks may not pick a route")
        pointer={x=0,y=0}
        render(model,211); render(model)
        assert(not panels[7350] and drawn["[-] 藏身处"])
        render(model,211); render(model); assert(panels[7350])
        model.travel=nil; render(model)
        assert(not panels[7350] and drawn["[-] 藏身处"])
        view.gateKind=nil
    end
    render(model,211); render(model)
    model.travel=travel.collect("",0,0); render(model)
    assert(drawn["矿井入口 · 藏身处"] and tracks[7352].frame~=frame)
    render({open=false}); model.travel=nil; render(model)
    assert(drawn["[+] 藏身处"] and not panels[7350],"restore original folded preference")
    render(model,211)
    width,height,model.lang=sw,sh,lang
    render(model)
end
-- Purchases use savings; an active workshop order does not gate the shop.
model.shopGoods={
    {id="water",category="materials",name="Water",quantity=250,price=5,ready=true},
    {id="dose",category="supplies",name="Fire injector",quantity=1,price=80,ready=true},
    {id="rescue_policy",category="services",name="Rescue insurance",quantity=1,scrap=1,ready=true},
}
for i=2,18 do
    model.shopGoods[#model.shopGoods+1]={id="bulk"..i,category="materials",name="Material "..i,
        quantity=10,price=5,ready=true}
end
model.bankGold,model.walletGold,model.order_active=200,0,true
assert(not render(model,220))
render(model)
assert(drawn.Convert and buttons[256].name=="Materials" and buttons[257].name=="Consumables"
    and green_button(244) and buttons[244].name=="Water" and not buttons[258])
assert(not render(model,244))
render(model)
assert(drawn["Water"] and drawn["250"] and drawn["Materials"] and drawn["5"] and drawn["200"])
model.bankGold=NHStore.maxGold
for _,lang in ipairs({"zh","en"}) do
    model.lang=lang
    for _,sw in ipairs({320,427,640}) do
        width=sw
        render(model)
        local bench,b=panels[210],reveal(model,258)
        assert(bench.y>=0 and b.x>=bench.x and b.x+GuiGetTextDimensions(nil,b.name)<=bench.x+bench.w
            and b.y+9<=bench.y+bench.h and green_button(258))
        assert(b.name==(lang=="zh" and "确认转化" or "Convert gold"))
        assert(drawn[lang=="zh" and "存款余额：" or "Savings:"] and drawn[lang=="zh" and "耗金" or "Gold cost"])
        assert(drawn["9P"] and tips[lang=="zh" and "存款余额：" or "Savings:"]=="9007199254740991")
    end
end
action,param=render(model,258)
assert(action=="shop_buy" and param.id=="water")
model.bankGold,model.walletGold,model.shopGoods[1].ready,model.shopGoods[1].reason=4,10000,false,"Not enough stored gold."
assert(not render(model,258) and drawn["Not enough stored gold."] and drawn["4"])
model.bankGold,model.shopGoods[1].reason=100,"Material storage is full."
assert(not render(model,258) and drawn["Material storage is full."])
render(model,240)
wheelAt(model,7100,5,8)
assert(drawn["Material 18"] and not drawn.Water)
render(model,257)
model.bankGold=200
render(model)
assert(buttons[244].name=="Fire injector" and not buttons[245] and not buttons[243])
render(model,244)
render(model)
assert(drawn.Supplies and drawn["80"] and drawn["1"])
action,param=render(model,258)
assert(action=="shop_buy" and param.id=="dose")
render(model,240)
render(model,265)
render(model,244)
render(model)
assert(drawn["Arcane scrap"] and drawn.Uninsured and not drawn["Gold cost"])
reveal(model,258)
action,param=render(model,258)
assert(action=="shop_buy" and param.id=="rescue_policy")
render(model,240)
do
    local oldRecipes,oldGoods=model.recipes,model.shopGoods
    local oldWidth,oldHeight,oldLang=width,height,model.lang
    width,height,model.lang,model.order_active=640,360,"zh",false
    model.recipes,model.shopGoods={},{}
    for _,recipe in ipairs(NHStormProducts.recipes) do
        local key,n=next(recipe.resources)
        local outputs={}
        if recipe.materials then outputs[1]={name="点金水",amount=recipe.materials.midas} end
        for res,amount in pairs(recipe.resourceYield) do
            outputs[#outputs+1]={name=NHStore.alchemyResources[res].zh,amount=amount}
        end
        model.shopGoods[#model.shopGoods+1]={id=recipe.id,category=recipe.category,name=recipe.zh,icon=recipe.icon,output=recipe.count,
            inputs={{name=NHStore.alchemyResources[key].zh,available=50,amount=n}},outputs=outputs,ready=true}
    end
    for _,offer in ipairs(NHStormProducts.offers) do
        model.shopGoods[#model.shopGoods+1]={id=offer.id,category=offer.category,name=offer.zh,icon=offer.icon,
            resourceName=NHStore.alchemyResources[offer.resource].zh,quantity=1,resourceStock=50,yield=offer.yield,ready=true}
    end
    render(model,269)
    for i,id in ipairs({"refine_red_mercury","refine_mana_arcane","refine_mana_container","sell_red_mercury","sell_crystallized_mana"}) do
        render(model)
        assert(buttons[243+i] and not buttons[7206])
        render(model,243+i)
        render(model)
        assert(see(model,"50 / 1"))
        local confirm=i<=3 and 214 or 258
        if i<=3 then
            for _,out in ipairs(model.shopGoods[i].outputs) do assert(see(model,out.name.." ×20")) end
        else assert(see(model,"500")) end
        reveal(model,confirm)
        local cmd,req=render(model,confirm)
        assert(cmd==(i<=3 and "craft" or "shop_buy") and req.id==id)
        render(model,240)
    end
    model.recipes,model.shopGoods=oldRecipes,oldGoods
    width,height,model.lang,model.order_active=oldWidth,oldHeight,oldLang,true
end
render(model,256)
render(model)
assert(drawn["Material 18"] and not drawn.Water)
render(model,212)
model.order_active=false
width=320
-- Return to the remembered spell page. Clamp it if the high slots disappear.
render(model,76)
render(model)
assert(tracks[7112].frame==frame)
model.warehouse_capacity.spell=1
render(model)
assert(tracks[7112].frame~=frame and not buttons[301])
local shortList=tiles[1008]
pointer={x=shortList.x+2,y=shortList.y+2,wheel=5}
render(model)
assert(panels[2] and panels[2].key=="nh_wheel/stash/spell" and tracks[7112].frame~=frame,
    "a list that fits still owns the wheel under its cells without drawing a scrollbar")
pointer.wheel=nil
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
render(model,271)
render(model)
do
    local station
    for _,entry in ipairs(model.progression.expansion) do if entry.id=="grenade" then station=entry end end
    local stockDetail="Combined stock, in preferred order\nAlchemical gunpowder  80\nRegular gunpowder  60"
    station.costs[1].detail=stockDetail
    render(model,listItem("Weapon station"))
    render(model)
    assert(drawn["140 / 150"] and tips["Gunpowder (total)"]==stockDetail)
    render(model,240)
end
render(model)
assert(not green_button(listItem("Salvage bench")))
render(model,listItem("Salvage bench"))
assert(not render(model,241) and drawn["Insufficient stock"])
render(model,240)
render(model,272)
render(model)
assert(drawn.Farmland and not drawn["Bombardment station"])
render(model,273)
render(model,244)
assert(not render(model,241) and drawn["Insufficient stock"] and drawn["0 / 100"] and drawn["0 / 5"])
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
    render(model,7081);render(model)
    assert(buttons[7081].name=="[x] Quick extract")
    assert(not point(spell_tile.x+2,spell_tile.y+2,"press"))
    point(pointer.x,pointer.y,"release")
    view.quick_essence=true
    command,request=point(spell_tile.x+2,spell_tile.y+2,"press")
    assert(command=="salvage" and request.mode=="quick_essence" and request.id==32 and request.slot==1)
    pointer.pressed=false;assert(not render(model))
    point(pointer.x,pointer.y,"release")
    render(model,7081)
    model.essences={}
    for i,key in ipairs(NHEssences.order) do
        local amount=i==1 and 1234000 or (i==#NHEssences.order and NHStore.maxResourceAmount or 0)
        model.essences[i]={key=key,name=NHEssences.types[key].en,amount=amount}
    end
    local function checkGrid(lang,stacked)
        local cells={}
        local draw=GuiText
        function GuiText(g,x,y,title,s)
            local w,h=GuiGetTextDimensions(g,title,s)
            cells[#cells+1]={title=title,x=x,y=y,w=w,h=h,color=next_color}
            draw(g,x,y,title,s)
        end
        render(model)
        GuiText=draw
        local first,prior
        local colors={}
        for i,entry in ipairs(model.essences) do
            local kind=NHEssences.types[entry.key]
            local color=kind.color
            local label=i==1 and "1.2M" or (i==#NHEssences.order and "9007.1T" or "0")
            local cell
            for j,name in ipairs(cells) do
                local value=cells[j+1]
                if value and value.title==label and name.color[1]==color[1] and name.color[2]==color[2]
                    and name.color[3]==color[3] then
                    local short=entry.name:gsub("精华$",""):gsub(" essence$","")
                    assert(name.title==short or (lang=="en" and name.title==kind.shortEn))
                    assert(value.color[1]==color[1] and value.color[2]==color[2] and value.color[3]==color[3])
                    if stacked then assert(value.x==name.x and value.y>=name.y+name.h-0.01)
                    else assert(value.x>=name.x+name.w and value.y==name.y) end
                    cell={x=name.x,y=name.y,right=math.max(name.x+name.w,value.x+value.w),
                        bottom=value.y+value.h,value=value}
                    break
                end
            end
            assert(cell,"missing essence: "..entry.name)
            assert(cell.x>=panels[70].x and cell.right<panels[70].x+panels[70].w and cell.bottom<=panels[70].y+panels[70].h)
            local signature=table.concat(color,"/")
            assert(not colors[signature],"two essence types share a color")
            colors[signature]=true
            if i==1 then first=cell
            elseif (i-1)%4==0 then assert(cell.x==first.x and cell.y>=prior.bottom-0.01)
            else assert(cell.y==prior.y and cell.x>prior.right-0.01) end
            prior=cell
        end
        point(first.value.x+1,first.value.y+1)
        assert(drawn[model.essences[1].name.."  1234000"])
    end
    local sw,sh=width,height
    width=640
    render(model,82)
    checkGrid("en",false)
    assert(not buttons[300] and not buttons[301])
    for i=18,21 do model.essences[i]={name="Extra "..i.." essence",amount=i} end
    wheelAt(model,7112,5)
    render(model)
    assert(drawn["Extra 21"] and not drawn.Healing)
    for i=21,18,-1 do model.essences[i]=nil end
    width,height=320,180
    checkGrid("en",true)
    model.lang="zh"
    for i,key in ipairs(NHEssences.order) do model.essences[i].name=NHEssences.types[key].zh end
    checkGrid("zh",true)
    assert(drawn["强化"] and drawn["酸液"] and panels[70].y>=0 and not buttons[300])
    width=640
    checkGrid("zh",false)
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
do
    local flask=model.warehouse.containers[2]
    flask.salvage_yield,flask.materials_fit,flask.store_contents=1,true,{}
    for i=1,18 do flask.store_contents[i]={name="Material "..i,amount=i} end
    pointer.right=true; render(model); pointer.right=false
    render(model)
    assert(drawn["Store in bulk storage"] or tips["Store in bulk storage"])
    assert(not buttons[260] and not panels[20000])
    local heading=noticeText.Dismantle.y
    wheelAt(model,7102,5,12)
    assert(panels[2].key=="nh_wheel/salvage/potion/store_contents" and noticeText.Dismantle.y==heading)
    assert(drawn["Material 18"] and (drawn["Store and dismantle"] or tips["Store and dismantle"]))
    flask.materials_fit=false
    assert(not render(model,260) and (drawn["Material storage full"] or tips["Material storage full"]))
    flask.materials_fit=true
    local command,req=render(model,260)
    assert(command=="salvage" and req.mode=="store_contents" and req.id==162)
    pointer={x=0,y=0}
    render(model,7081)
    render(model)
    assert(buttons[7081].name=="[x] Store and dismantle" and buttons[7080].y==buttons[7081].y)
    command,req=point(empty_flask.x+1,empty_flask.y+1,"press")
    assert(command=="salvage" and req.mode=="store_contents" and req.slot==2 and req.id==162)
    assert(not NHUI.quickTarget() and not NHUI.useTarget())
    pointer.pressed=false
    assert(not render(model),"holding the button must not dismantle another container")
    assert(not point(pointer.x,pointer.y,"release"))
    render(model,75)
    render(model,77)
    render(model)
    assert(buttons[7081].name=="[ ] Store and dismantle")
    model.salvage_enabled=false
    render(model,7081)
    render(model)
    assert(buttons[7081].name=="[ ] Store and dismantle")
    model.salvage_enabled=true
end
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

local function checkStockColumns(lang,stock,rate)
    local cells={}
    local drawText=GuiText
    function GuiText(g,x,y,value,scale)
        cells[#cells+1]={value=value,x=x,y=y,right=x+GuiGetTextDimensions(g,value,scale)}
        drawText(g,x,y,value,scale)
    end
    render(model)
    GuiText=drawText
    local function find(value,predicate)
        for _,cell in ipairs(cells) do
            if cell.value==value and (not predicate or predicate(cell)) then return cell end
        end
    end
    local rates=assert(find(lang=="zh" and "每分钟" or "Per min") or find(lang=="zh" and "每分" or "/min"))
    local stocks=assert(find(lang=="zh" and "库存" or "Stock",function(c) return c.y==rates.y end))
    local qty=assert(find(stock,function(c) return c.y>stocks.y and math.abs(c.right-stocks.right)<0.01 end))
    local output=assert(find(rate,function(c) return c.y==qty.y and math.abs(c.right-rates.right)<0.01 end))
    assert(qty.right<output.x,"inventory and per-minute output occupy separate columns")
    for _,entry in ipairs(cells) do
        if entry.y==qty.y and entry.x<qty.x then
            assert(entry.right<qty.x,"product name overlaps the stock quantity")
            assert(entry.value~="..." and entry.value~="","the stock row must identify its product")
            return
        end
    end
    error("stock row is missing a product name")
end

local function testFarmPanel(lang)
    width,height,model.lang,model.near=320,180,lang,true
    pointer={x=0,y=0}
    local stock={profile=1,levels={},resources={fiber=13},farm={time=0,plots={}},warehouse={},pouches={},nextItemId=1}
    model.farm=NHFarm.view(stock,lang,0)
    render(model,221)
    render(model,410)
    render(model)
    assert(buttons[412] and not buttons[421])
    render(model,412)
    render(model)
    assert(buttons[240] and buttons[241],"unbuilt farm links to the farmland expansion quote")

    stock.levels.farmland=1
    model.farm=NHFarm.view(stock,lang,0)
    render(model,221)
    render(model,421)
    render(model)
    assert(buttons[436] and panels[210].y>=0 and buttons[436].y<height)
    assert(not render(model,436),"locked farm equipment prevents selecting an advanced crop")
    local lockedTip=lang=="zh" and "激活草药  +3 / 5:00   库存 0   需要农业设备"
        or "Stimulating herbs  +3 / 5:00   In storage 0   Needs farming equipment"
    assert(tips[lockedTip])
    local action,request=render(model,431)
    assert(action=="farm_plant" and request.plot==1 and request.crop=="fiber" and request.token==0)
    assert(NHFarm.plant(stock,request,0))
    model.farm=NHFarm.view(stock,lang,60)
    render(model)
    assert(drawn["1:59"] and green_button(431) and not render(model,431),"clicking the planted crop is a no-op")
    action,request=render(model,432)
    assert(action=="farm_plant" and request.plot==1 and request.crop=="herb" and request.token==1)
    assert(NHFarm.plant(stock,request,60))
    model.farm=NHFarm.view(stock,lang,60)
    render(model)
    assert(drawn["1:59"] and green_button(432) and not green_button(431))
    assert(NHFarm.sync(stock,7200))
    model.farm=NHFarm.view(stock,lang,7200)
    render(model)
    assert(not buttons[415] and drawn["3:00"] and green_button(432) and reveal(model,436).y<height)
    model.farm.plots[1].blocked=true
    render(model)
    local full=lang=="zh" and "农产库存已满" or "Crop storage full"
    assert(see(model,full))
    render(model,411)
    checkStockColumns(lang,"4","1.33")
    assert(drawn["13"] and drawn["4"] and drawn["0"] and not buttons[415])
    for _,crop in ipairs(model.farm.crops) do assert(drawn[crop.name] or tips[crop.name]) end
    stock.resources.fiber=12345
    model.farm=NHFarm.view(stock,lang,7200)
    checkStockColumns(lang,"12.3k","0")
    local name=model.farm.crops[1].name
    assert(tips[name]:find("12345",1,true),"stock tooltip should show unabridged quantities")
    assert(drawn[name],"short product names should fit beside large quantities on the narrow panel")
    width,height=640,360
    checkStockColumns(lang,"12.3k","0")
    assert(drawn[lang=="zh" and "每分钟" or "Per min"])
    assert(panels[210].y>=0)

    width,height=320,180
    stock.resources.fiber=NHStore.maxResourceAmount
    model.farm=NHFarm.view(stock,lang,7200)
    local measure=GuiGetTextDimensions
    function GuiGetTextDimensions(g,value,scale)
        local w,h=measure(g,value,scale)
        return w*1.125,h
    end
    checkStockColumns(lang,"9007.1T","0")
    assert(drawn[lang=="zh" and "产物" or "Item"])
    GuiGetTextDimensions=measure

    local crops=model.farm.crops
    model.farm.crops={}
    for i=1,32 do model.farm.crops[i]={name="C"..i,stock=i,perMinute=i} end
    wheelAt(model,7102,4,16)
    local tabY=buttons[411].y
    assert(drawn.C1 and not drawn.C32)
    local firstY=noticeText.C3.y
    wheelAt(model,7102,5)
    assert(not drawn.C1 and not drawn.C2 and math.abs(firstY-noticeText.C3.y-39*buttons[411].scale)<0.01)
    wheelAt(model,7102,5,16)
    assert(drawn.C32 and not drawn.C3 and buttons[411].y==tabY)
    assert(panels[2].hidden and panels[2].key=="nh_wheel/farm/stock/")
    pointer={x=buttons[411].x+1,y=tabY+1,wheel=4}
    render(model)
    assert(not panels[2] and drawn.C32,"hovering a fixed tab must not scroll the stock table")
    pointer={x=0,y=0}
    model.farm.crops=crops
end
testFarmPanel("en")
testFarmPanel("zh")
print("UI: one-click planting and crop switching, equipment lock, passive deposits and stock in both languages passed.")

local function testLivestockPanel(lang)
    width,height,model.lang,model.near=320,180,lang,true
    pointer={x=0,y=0}
    local stock={profile=1,levels={livestock=1},resources={egg=21},farm={time=0,plots={}},warehouse={},pouches={},nextItemId=1}
    local first=assert(NHLivestock.freePen(stock,"chick"))
    model.shopGoods={{id="chick",category="livestock",name="Chick",price=120,quantity=1,ready=true,pen=first}}
    model.farm=NHFarm.view(stock,lang,0)
    render(model,223)
    render(model,440)
    render(model)
    assert(buttons[451] and buttons[452] and panels[210].y>=0)
    render(model,451)
    render(model)
    reveal(model,444)
    render(model,444)
    render(model)
    assert(see(model,"120") and see(model,"3:00") and see(model,"2:00") and see(model,"2 / 1"))
    assert(panels[210].y>=0 and reveal(model,258).y<height)
    local action,request=render(model,258)
    assert(action=="shop_buy" and request.id=="chick" and request.pen==first)
    NHLivestock.deliver(stock,"chick",first,0)
    NHLivestock.deliver(stock,"calf",assert(NHLivestock.freePen(stock,"calf")),0)
    model.farm=NHFarm.view(stock,lang,0)
    render(model,223)
    render(model,451)
    render(model)
    assert(drawn["0 / 1"] and drawn["1 / 2"] and drawn["3:00"] and drawn["5:00"] and reveal(model,444))
    model.farm=NHFarm.view(stock,lang,180*60)
    render(model)
    assert(see(model,"1 / 0") and see(model,"2:00") and reveal(model,444))
    assert(NHFarm.sync(stock,300*60))
    model.farm=NHFarm.view(stock,lang,300*60)
    render(model)
    assert(see(model,"2:00") and reveal(model,444),"partly filled adult housing still sells youngstock")
    model.farm.pens[1].blocked=true
    render(model)
    local full=lang=="zh" and "畜产库存已满" or "Produce storage full"
    assert(see(model,full))
    render(model,441)
    checkStockColumns(lang,"1","1.17")
    assert(drawn["23"] and drawn["1"] and panels[210].y>=0)
    stock.levels.livestock,stock.farm=0,{time=0,plots={}}
    model.farm=NHFarm.view(stock,lang,0)
    render(model,440)
    render(model)
    assert(buttons[442] and not buttons[451])
end
testLivestockPanel("en")
testLivestockPanel("zh")
print("UI: youngstock shop, pen timers and passive produce deposits in both languages passed.")

local function testSpecialPens(lang)
    model.lang,width,height=lang,320,180
    local stock={profile=1,levels={beehive=1,dragon_nest=1},resources={},bankGold=3480,
        farm={time=0,plots={}},warehouse={},pouches={},nextItemId=1}
    model.shopGoods={}
    for _,id in ipairs({"queen_bee","dragon_egg"}) do
        local animal=NHLivestock.species[id]
        model.shopGoods[#model.shopGoods+1]={id=id,category="livestock",name=animal.young[lang=="zh" and 1 or 2],
            price=id=="queen_bee" and 480 or 3000,quantity=1,ready=true,pen=assert(NHLivestock.freePen(stock,id))}
    end
    model.farm=NHFarm.view(stock,lang,0)
    for i,good in ipairs(model.shopGoods) do
        render(model,223)
        render(model,440)
        render(model,450+i)
        render(model)
        assert(see(model,"3%") and (i==1 or see(model,"5%") and see(model,"10%")))
        assert(see(model,i==1 and "5 / 2" or "150 / 1"))
        reveal(model,444)
        render(model,444)
        render(model)
        assert(see(model,tostring(good.price)) and see(model,"3%"))
        reveal(model,258)
        local action,arg=render(model,258)
        assert(action=="shop_buy" and arg.id==good.id and arg.pen==good.pen)
    end
    NHLivestock.deliver(stock,"dragon_egg",assert(NHLivestock.freePen(stock,"dragon_egg")),0)
    stock.dragonLoot={seed=1,pending={spell_BOMB=3}}
    model.farm=NHFarm.view(stock,lang,0)
    render(model,223)
    render(model,452)
    render(model)
    local pending=lang=="zh" and "已找到，待入库" or "Found, awaiting space"
    assert(see(model,pending) and see(model,"3") and see(model,"8:00") and see(model,"13:00") and reveal(model,444))
end
testSpecialPens("zh")
testSpecialPens("en")

local function testGelPool(lang)
    model.lang,width,height=lang,320,180
    local zh=lang=="zh"
    local stock={profile=1,levels={},resources={},materials={slime=250,water=150,soil=100},bankGold=320,
        farm={time=0,plots={}},warehouse={},pouches={},nextItemId=1}
    local original=model.progression
    model.progression=NHStore.progressMenu(profile,lang)
    model.farm=NHFarm.view(stock,lang,0)
    render(model,223)
    render(model,440)
    render(model)
    reveal(model,446)
    render(model,446)
    render(model)
    local title=zh and "凝胶池" or "Gel pool"
    assert(buttons[240] and (drawn[title] or tips[title]))
    assert(NHStore.buyUpgrade(stock,{id="gel_pool",level=0},0))
    model.farm=NHFarm.view(stock,lang,0)
    render(model,223)
    render(model,451)
    render(model)
    local bonus=zh and "香料 + 激活剂" or "Spice + injector"
    local card=zh and "凝胶少女卡" or "Gel maiden card"
    assert(see(model,bonus) and tips[bonus]:find(zh and "消耗品库" or "supplies",1,true))
    assert(see(model,card) and tips[card]:find(zh and "独立" or "separately",1,true))
    assert(see(model,"4 / 6") and see(model,"4:00") and see(model,"30%") and see(model,"3%") and see(model,"1 / 2") and reveal(model,444))
    model.farm.gelPending,model.farm.gelSpicePending=3,2
    render(model)
    local meds=zh and "待入库激活剂" or "Injectors awaiting space"
    local spices=zh and "待入库香料" or "Spice awaiting space"
    assert(see(model,meds) and see(model,spices) and see(model,"3") and see(model,"2"))
    wheelAt(model,7102,4,8)
    local anchor=buttons[223].y
    assert(not buttons[444] and not panels[20000])
    local cycle=zh and "当前产出间隔" or "Current cycle"
    local y=assert(noticeText[cycle]).y
    wheelAt(model,7102,5)
    assert(math.abs(y-noticeText[cycle].y-39*buttons[223].scale)<0.01)
    assert(buttons[223].y==anchor and panels[2].hidden and panels[2].options[GUI_OPTION.AlwaysClickable])
    wheelAt(model,7102,5,12)
    assert(buttons[444] and not buttons[443] and panels[2].key=="nh_wheel/livestock/pens/gel_pool")
    model.farm.pens[1].blocked=true
    render(model)
    local full=zh and "草药或纤维库存已满" or "Herb or fiber stock full"
    assert(see(model,full))
    model.farm=NHFarm.view(stock,lang,0)
    local slot=assert(NHLivestock.freePen(stock,"gel_pool"))
    model.shopGoods={{id="gel_pool",name=zh and "凝胶幼体" or "Gel hatchling",category="livestock",price=320,quantity=1,ready=true,pen=slot}}
    reveal(model,444)
    render(model,444)
    render(model)
    assert(see(model,"1 / 2") and see(model,"4:00") and see(model,"2:00") and see(model,"320"))
    reveal(model,258)
    local action,arg=render(model,258)
    assert(action=="shop_buy" and arg.id=="gel_pool" and arg.pen==slot)
    NHLivestock.deliver(stock,arg.id,arg.pen,0)
    model.farm=NHFarm.view(stock,lang,60*60)
    render(model,223)
    render(model,451)
    render(model)
    assert(see(model,"2 / 2") and see(model,"1 / 1") and see(model,"1:00") and see(model,"4:00"))
    assert(reveal(model,447) and not buttons[444],"a full pool permits expansion even while its young are maturing")
    render(model,447)
    render(model)
    assert(buttons[240] and (drawn[title] or tips[title]))
    model.farm=NHFarm.view(stock,lang,120*60)
    render(model,223)
    render(model,451)
    render(model)
    assert(see(model,"2 / 0") and see(model,"2:00") and not see(model,"4:00"))
    stock.levels.gel_pool=3
    for i=3,6 do NHLivestock.deliver(stock,"gel_pool",assert(NHLivestock.freePen(stock,"gel_pool")),120*60) end
    model.farm=NHFarm.view(stock,lang,120*60)
    render(model)
    assert(see(model,"6 / 6") and not buttons[444] and not buttons[447])
    model.progression=original
end
testGelPool("zh")
testGelPool("en")

local function testCardWalletPanel()
    width,height,model.lang,model.debug=640,360,"en",true
    model.perkCapacity,model.packablePerk=0,nil
    model.pouchId,model.walletId,model.popup=nil,nil,false
    model.secure_loot={{id=95,kind="card_wallet",name="Card wallet"}}
    local function card(id,species,remaining,count)
        return {id=id,kind="summon_card",name=species,species=species,remaining=remaining,count=count}
    end
    model.warehouse.collection={card(201,"dryad",80,9754),card(202,"flower_fairy",3),card(203,"minotaur",80)}
    local affinity={dryad=100,flower_fairy=400,griffin=1000}
    model.affinityPoints=function(id) return affinity[id] or 0 end
    model.warehouse.equipment={model.secure_loot[1]}
    render(model,213)
    assert(render(model,480)=="test_cards")
    render(model)
    for _,id in ipairs({"dryad","flower_fairy","minotaur"}) do
        assert(drawn[NHCompanions.cardIcon(id)],"collection cards use the species portrait without a saved icon")
    end
    local first=tiles[1004]
    point(first.x+1,first.y+1)
    assert(drawn["Dryad"] and drawn["Count 9754"] and drawn["Durability 80/80"])
    assert(drawn["Affinity 100/10000   Next at 400"] and drawn["Toxic sludge immunity"] and drawn["Slice immunity"])
    assert(drawn["Heals 1% of max HP per second"] and drawn["Every 2 min: tier 1 gift box"])
    affinity.dryad=1000
    point(first.x+1,first.y+1)
    assert(drawn["Affinity 1000/10000"] and drawn["Heals 2% of max HP per second"] and drawn["Every 2 min: tier 3 gift box"])
    local action,req=drag_tiles(1,1)
    assert(action=="open_container" and req.walletId==95 and req.container=="safe")
    model.walletId,model.walletCapacity,model.pouchName,model.popup=95,4,"Card wallet #95",true
    model.cells={card(nil,"dryad",80,3),card(nil,"dryad",79),card(nil,"griffin",80)}
    render(model)
    assert(drawn[NHCompanions.cardIcon("griffin")],"wallet cells use the species portrait")
    assert(tiles[1007].x-tiles[1004].x==60)
    point(tiles[1006].x+1,tiles[1006].y+1)
    assert(drawn["Affinity 1000/10000"] and drawn["Restores 17% flight fuel per second"])
    model.cells[3],affinity.bee=card(nil,"bee",80),1000
    point(tiles[1006].x+1,tiles[1006].y+1)
    assert(drawn[NHCompanions.cardIcon("bee")] and drawn["Faster movement"] and drawn["Restores 19% flight fuel per second"])
    model.cells[3],affinity.dragon=card(nil,"dragon",80),1000
    point(tiles[1006].x+1,tiles[1006].y+1)
    assert(drawn[NHCompanions.cardIcon("dragon")] and drawn["Fire immunity"] and drawn["Projectile shield at 100% of normal recharge"])
    model.cells[3],affinity.slime=card(nil,"slime",80),0
    point(tiles[1006].x+1,tiles[1006].y+1)
    assert(drawn[NHCompanions.cardIcon("slime")] and drawn["Suffocation immunity"] and not drawn["Heals 2% of max HP per second"])
    affinity.slime=1000
    point(tiles[1006].x+1,tiles[1006].y+1)
    assert(drawn["Heals 2% of max HP per second"] and drawn["Every 2 min: tier 3 gift box"])
    model.lang="zh"
    render(model)
    point(tiles[1009].x+1,tiles[1009].y+1)
    assert(drawn["好感度 400/10000   下一阶段 1000"] and drawn["每秒恢复最大生命的 1.5%"])
    model.lang="en"
    render(model)
    action,req=drag_tiles(8,4)
    assert(action=="move_wallet_card" and req.walletId==95 and req.entity==201 and req.from==1 and req.targetCell==1)
    assert(not drag_tiles(8,5) and not drag_tiles(8,6),"cannot stack worn or other-species cards")
    action,req=drag_tiles(5,7)
    assert(action=="move_wallet_card" and req.sourceCell==2 and req.targetCell==4 and req.remaining==79)
    action,req=drag_tiles(4,8)
    assert(action=="move_wallet_card" and req.sourceCell==1 and req.safeSlot==1 and req.container=="warehouse")
    action,req=drag_tiles(4,2)
    assert(action=="move_wallet_card" and req.sourceCell==1 and req.safeSlot==2 and req.container=="safe")
    action,req=drag_tiles(9,2)
    assert(action=="move_stored_card" and req.source=="warehouse" and req.destination=="safe" and req.entity==202)
    local c=tiles[1005]
    point(c.x+1,c.y+1,"press")
    action,req=point(148,28,"release")
    assert(action=="take_card" and req.walletId==95 and req.sourceCell==2 and req.remaining==79)
    local carried=model.native_slots[2]
    carried.kind,carried.species,carried.remaining="summon_card","dryad",80
    point(108,28,"press")
    c=tiles[1004]
    action,req=point(c.x+1,c.y+1,"release")
    assert(action=="place" and req.entity==carried.entity and req.targetCell==1 and req.walletId==95)
    for _,lang in ipairs({"zh","en"}) do
        model.lang,width,height=lang,320,180
        render(model,213)
        render(model)
        assert(tips[lang=="zh" and "共 9 种召唤卡，每种各发一张满耐久卡。" or "One full-charge card for each of the 9 companions."])
        assert(render(model,480)=="test_cards")
        render(model)
        assert(panels[70].y>=0 and panels[210].y>=0 and buttons[481].y<height)
    end
end
testCardWalletPanel()

do
    width,height,model.lang=640,360,"en"
    local frost=NHFirearms.mods.byId.frost
    model.walletId,model.popup=nil,false
    model.secure_loot={{id=78,kind="marksman_rifle",rounds=10},{id=79,kind="spell",icon=frost.icon,name=frost.en,actionId=frost.action}}
    render(model)
    local action,req=drag_tiles(1,1)
    assert(action=="open_container" and req.entity==78 and req.container=="safe")
    model.gunId,model.popup,model.pouchName,model.pouchCapacity,model.cells=78,true,"Gun attachments",2,{}
    render(model)
    assert(drag_tiles(2,5)==nil)
    action,req=drag_tiles(2,4)
    assert(action=="move_gun_attachment" and req.gunId==78 and req.targetCell==1 and req.from==2 and req.entity==79)
    model.secure_loot[2],model.cells[1]=nil,frost
    render(model)
    action,req=drag_tiles(4,2)
    assert(action=="move_gun_attachment" and req.gunId==78 and req.sourceCell==1 and req.safeSlot==2 and req.entity=="frost")
    model.gunId,model.popup=nil,false
end

do
    width,height,model.lang=640,360,"en"
    model.walletId,model.popup=nil,false
    model.secure_loot={{id=96,kind="relic_chain",name="Relic chain",relics={"1. Kiuaskivi"}}}
    render(model)
    point(tiles[1001].x+1,tiles[1001].y+1)
    assert(drawn["1. Kiuaskivi"])
    local action,req=drag_tiles(1,1)
    assert(action=="open_container" and req.entity==96 and req.container=="safe")
    model.chainId,model.popup,model.pouchCapacity,model.pouchName=96,true,2,"Relic chain"
    model.cells={{id=301,kind="relic",name="Kiuaskivi",icon="data/ui_gfx/items/brimstone.png"}}
    render(model)
    assert(drawn["data/ui_gfx/items/brimstone.png"])
    action,req=drag_tiles(4,5)
    assert(action=="move_chain_relic" and req.chainId==96 and req.entity==301 and req.sourceCell==1 and req.targetCell==2)
    action,req=drag_tiles(4,2)
    assert(action=="move_chain_relic" and req.destination=="safe" and req.safeSlot==2)
    local c=tiles[1004]
    point(c.x+1,c.y+1,"press")
    action,req=point(148,28,"release")
    assert(action=="take_relic" and req.sourceCell==1 and req.storedId==301)
    local carried=model.native_slots[2]
    for _,kind in ipairs({"other","relic"}) do
        carried.kind=kind
        point(108,28,"press")
        c=tiles[1005]
        action,req=point(c.x+1,c.y+1,"release")
        assert(action==(kind=="other" and "reject_relic" or "place") and req.entity==carried.entity and req.chainId==96)
    end
    model.chainId,model.popup=nil,false
end
print("UI: test supplies, collection, 80/80 stacks and exact-wallet transfers passed.")

local function testFixedWorkshop()
    model.debug,model.near,model.order_active=true,true,false
    model.popup,model.walletId,model.pouchId=false,nil,nil
    local inputs={}
    for i=1,18 do inputs[i]={name="Ingredient "..i,amount=1,available=3} end
    model.recipes={{id="long_recipe",category="medical",name="Long recipe",duration=120,
        output=1,ready=true,inputs=inputs}}
    local tabs={212,218,219,220,221,223,213}
    for _,lang in ipairs({"en","zh"}) do
        model.lang=lang
        for _,size in ipairs({{320,180},{427,240},{640,360}}) do
            width,height=size[1],size[2]
            render(model,212)
            render(model)
            local stash=panels[70]
            local positions={}
            for _,id in ipairs(tabs) do positions[id]=buttons[id] end
            local function check()
                local p=panels[210]
                assert(p.y==stash.y and p.h==stash.h and p.y>=0 and p.y+p.h<=height)
                for _,id in ipairs(tabs) do
                    local b=assert(buttons[id])
                    assert(not b.scroll and b.x==positions[id].x and b.y==positions[id].y,
                        "the main category buttons must stay fixed outside the scroll area")
                end
            end
            for _,id in ipairs(tabs) do
                render(model,id)
                render(model)
                check()
            end
            render(model,212)
            render(model,251)
            render(model,244)
            render(model)
            check()
            wheelAt(model,7102,4,16)
            local box=assert(tracks[7102])
            assert(box.y>buttons[213].y and box.y+box.h<stash.y+stash.h)
            assert(not buttons[214] and not panels[20000],"hidden crafting controls must not receive clicks")
            local backY=buttons[240].y
            wheelAt(model,7102,5)
            assert(panels[2].key=="nh_wheel/recipe/long_recipe" and buttons[240].y==backY)
            reveal(model,214)
            check()
            local action,arg=render(model,214)
            assert(action=="craft" and arg.id=="long_recipe")
            render(model,71)
            render(model)
            check()
            assert(panels[70].h<panels[210].h)
            render(model,71)
            render(model,211)
            render(model)
            assert(panels[210].h<panels[70].h and not buttons[212])
            render(model,211)
            render(model)
            check()
        end
    end
end
testFixedWorkshop()
print("UI: fixed warehouse and hideout bounds, stationary tabs, independent folding and scrollable confirmations passed.")

local function testWarehouseTabs()
    local ids={75,76,77,78,79,80,82,83}
    local names={zh={"魔杖","法术","容器","消耗品","装备","物料","精华","藏品"},
        en={"Wands","Spells","Containers","Supplies","Equipment","Materials","Essences","Collection"}}
    for lang,titles in pairs(names) do
        model.lang=lang
        for _,size in ipairs({{320,180},{427,240},{640,360}}) do
            width,height=size[1],size[2]
            for _,selected in ipairs(ids) do
                render(model,selected)
                render(model)
                local panel=panels[70]
                assert(panels[10].x+panels[10].w<panels[210].x and panels[210].x+panels[210].w<panel.x)
                local right=panel.x
                local seen={}
                for i,id in ipairs(ids) do
                    local b=assert(buttons[id])
                    assert(b.y==buttons[75].y and b.x>right,"warehouse tabs must have separate buttons on one row")
                    assert(not seen[b.name] and (b.name==titles[i] or tips[titles[i]]),"short titles must be unique and explainable")
                    seen[b.name]=true
                    right=b.x+GuiGetTextDimensions(nil,b.name,b.scale)
                    assert(right<panel.x+panel.w)
                    assert((b.color[1]==1)==(id==selected))
                end
            end
        end
    end
end
testWarehouseTabs()
print("UI: single-row warehouse navigation, localized labels and bottle dragging across tabs passed.")

local function testSpellRecipes(lang,sw,sh)
    width,height,model.lang=sw,sh,lang
    model.order_active=false
    local key="essence_healing"
    local family=NHEssences.types[key]
    local label=family[lang]
    local spell=lang=="zh" and "治疗魔弹" or "Healing Bolt"
    local card={id="spell_HEAL_BULLET",actionId="HEAL_BULLET",name=spell,category="spell",spellType="projectile",
        icon="data/ui_gfx/gun_actions/heal_bullet.png",ready=true,output=1,duration=120,
        inputs={{name=label,essence=key,amount=175,available=NHStore.maxResourceAmount}}}
    model.spellFamilies={{id=key,name=label}}
    model.spellRecipes={[key]={card}}
    render(model,212)
    render(model,225)
    render(model)
    assert(buttons[244].name==label or tips[label])
    render(model,244)
    render(model)
    assert(buttons[226] and tips[spell]==card.actionId and drawn[card.icon] and green_button(244))
    render(model,244)
    local cells={}
    local draw=GuiText
    function GuiText(g,x,y,title,s)
        cells[#cells+1]={name=title,color=next_color,x=x,y=y,w=GuiGetTextDimensions(g,title,s)}
        draw(g,x,y,title,s)
    end
    render(model)
    GuiText=draw
    local amount
    for i,v in ipairs(cells) do if v.name=="9007.1T / 175" then amount=i end end
    local num=cells[assert(amount,"missing spell price")]
    local name=cells[amount-1]
    assert(name.name==label or name.name==(lang=="zh" and "治疗" or family.shortEn))
    assert(name.x+name.w<num.x and name.y==num.y,"the whole price must fit beside its name")
    for i,c in ipairs(family.color) do assert(name.color[i]==c and num.color[i]==c) end
    local command,request=render(model,214)
    assert(command=="craft" and request.id==card.id)
    card.ready=false
    card.reason="Insufficient essence"
    assert(not render(model,214) and not buttons[214])
    render(model,240)
    render(model)
    assert(buttons[226] and not green_button(244))
    render(model,226)
    render(model)
    assert(not buttons[226] and (buttons[244].name==label or tips[label]))
end
testSpellRecipes("zh",320,180)
testSpellRecipes("en",640,360)
print("UI: spell family navigation, localized card identities, warehouse colors and crafting passed.")

local function testBandageBatchDisplay()
    width,height,model.lang=640,360,"zh"
    model.capacity,model.perkCapacity,model.popup,model.near=2,0,false,true
    local function bandages(id,count)
        return {id=id,name="绷带",kind="bandage",icon="mods/noita_hideout/files/items/bandage.png",count=count}
    end
    model.secure_loot={bandages(1,2)}
    model.warehouse.supplies={bandages(2,4),bandages(3)}
    render(model,78)
    render(model)
    assert(drawn["×4"] and drawn["×2"] and drawn["8/8"] and not drawn["×1"])
    for tile,title in pairs({[1001]="绷带 ×2",[1003]="绷带 ×4",[1004]="绷带"}) do
        point(tiles[tile].x+1,tiles[tile].y+1)
        assert(drawn[title])
    end

    model.recipes={
        {id="bandage",name="绷带",category="medical",output=4,duration=3,ready=true,
            inputs={{name="纤维",amount=4,available=4},{name="糖分",amount=2,available=2}}},
        {id="field_medkit",name="小医疗包",category="medical",output=4,duration=5,ready=true,
            inputs={{name="绷带",amount=1,available=9},{name="草药",amount=2,available=2}}}
    }
    pointer={x=0,y=0}
    render(model,212)
    render(model,251)
    render(model,244)
    render(model)
    assert(drawn["绷带 ×4"] and drawn["即时完成"] and drawn["4 / 4"] and drawn["2 / 2"])
    render(model,240)
    render(model,245)
    render(model)
    assert(drawn["小医疗包 ×4"] and drawn["即时完成"] and drawn["9 / 1"])
end
testBandageBatchDisplay()

do
    local p={id=21,kind="storm_mercury_pressure",count=8,name="高压红水银"}
    p.trade=NHStore.supplyTrade.quote(p)
    model.warehouse.supplies={p}
    render(model,7081)
    render(model)
    local tile=tiles[1003]
    point(tile.x+1,tile.y+1)
    assert(not NHUI.useTarget() and not NHUI.quickTarget())
    local cmd,req=point(tile.x+1,tile.y+1,"press")
    assert(cmd=="supply_trade" and req.mode=="convert" and req.quantity==1 and req.id==21)
    shift=225
    cmd,req=point(tile.x+1,tile.y+1,"press")
    assert(req.mode=="convert" and req.quantity==8)
    pointer.pressed,pointer.down,pointer.right=false,false,true
    cmd,req=render(model)
    assert(not cmd)
    local box={id=22,kind="supply_pack",count=3,name="基础补给箱"}
    box.trade=NHStore.supplyTrade.quote(box)
    model.warehouse.supplies={box}
    pointer.right=false
    assert(not point(tile.x+1,tile.y+1,"press") and not NHUI.quickTarget())
    shift=nil
    assert(not point(tile.x+1,tile.y+1,"press"))
    point(tile.x+1,tile.y+1,"release")
    model.rightUse=assert(NHUI.useTarget())
    pointer.right=true
    cmd,req=render(model)
    assert(cmd=="use_inventory" and req.kind=="supply_pack" and req.container=="warehouse" and req.storedId==22)
    pointer.right=false
    render(model,7081)
end

local function testTieredMedkitDisplay()
    model.secure_loot={{id=1,kind="tactical_medkit",name="战术医疗包",remaining=5}}
    model.warehouse.supplies={{id=2,kind="advanced_medkit",name="高端医疗包",remaining=6}}
    render(model,78)
    render(model)
    assert(drawn["5/6"] and drawn["6/6"])
    point(tiles[1001].x+1,tiles[1001].y+1)
    assert(drawn["剩余次数 5/6"] and drawn["用时 1.5 秒，恢复最大生命的 25%"])
    point(tiles[1003].x+1,tiles[1003].y+1)
    assert(drawn["剩余次数 6/6"] and drawn["用时 2 秒，恢复最大生命的 40%"])

    width,height=320,180
    pointer={x=0,y=0}
    local kit=NHMedkits.types.advanced_medkit
    model.recipes={{id="advanced_medkit",name=kit.zh,category="medical",medkit=kit,output=1,duration=180,ready=true,
        inputs={{name="治疗精华",amount=3,available=200,essence="essence_healing"},{name="草药",amount=8,available=8},
            {name="战术医疗包 (5/6)",amount=1,available=2,detail="优先消耗剩余次数最少的一包。"}}}}
    render(model,212)
    render(model,251)
    render(model)
    assert(green_button(244))
    render(model,244)
    render(model)
    assert(drawn["即时完成"] and drawn["200 / 3"] and drawn["8 / 8"] and drawn["2 / 1"])
    assert(tips["战术医疗包 (5/6)"]:find("剩余次数最少",1,true))
    reveal(model,214)
    assert(drawn["6"] and drawn["40% 最大生命"])
    local cmd,arg=render(model,214)
    assert(cmd=="craft" and arg.id=="advanced_medkit")
end
testTieredMedkitDisplay()
print("UI: medkit charge overlays, percentage healing, fixed costs and scrollable narrow recipe confirmed.")

local function testSurgeryDisplay()
    local kit=NHSurgeryKits.types.advanced_surgery_kit
    local medical={id="advanced_surgery_kit",category="medical",medkit=kit,duration=180,
        name=kit.zh,output=1,ready=true,inputs={}}
    model.recipes={medical}
    render(model,240)
    render(model,244)
    render(model)
    assert(drawn["即时完成"])
    reveal(model,214)
    assert(drawn["50% 最大生命"] and drawn["5 秒"])
    assert(drawn["清除负面状态"] or tips["清除负面状态"])
    assert(drawn["受伤时仍可继续手术"] or tips["受伤时仍可继续手术"])
    reveal(model,214)
    local cmd,arg=render(model,214)
    assert(cmd=="craft" and arg.id==medical.id)
    local outdoors={open=false,near=false,lang="zh",surgery={kind=medical.id,elapsed=90,total=300}}
    render(outdoors)
    assert(drawn["手术中  3.5 秒"] and drawn["data/ui_gfx/1px_white.png"])
    outdoors.near=true
    render(outdoors)
    assert(drawn["手术中  3.5 秒"] and not drawn["打开物品栏：仓库和工坊"])
    outdoors.surgery=nil
    render(outdoors)
    assert(drawn["打开物品栏：仓库和工坊"] and not drawn["手术中  3.5 秒"])
end
testSurgeryDisplay()
print("UI: surgery recipe, damage information and in-world cast display passed.")

local function testRightUse()
    width,height=427,240
    local m={open=true,lang="en",near=false,mode="case",capacity=2,revision=1,status="",maxUses=3,
        secure_loot={{id=10,kind="bandage",count=7,name="Bandages"},{id=11,kind="card_wallet",name="Wallet"}},
        native_slots={native("tool",4,0,41,"medkit"),native("wand",0,0,42,"wand")}}
    render({open=false})
    assert(not NHUI.useTarget())
    pointer={x=102,y=22}
    m.rightUse={container="native",kind="medkit",entity=41,parent=2,lane="tool",xslot=0,yslot=0}
    assert(not render(m),"opening inventory cannot spend an item")
    local function over(tile)
        pointer={x=tiles[tile].x+1,y=tiles[tile].y+1}
        return NHUI.useTarget()
    end
    local function use()
        m.rightUse=assert(NHUI.useTarget())
        local cmd,arg=render(m)
        assert(cmd=="use_inventory" and not m.rightUse)
        return arg
    end
    local native_use=use()
    assert(native_use.container=="native" and native_use.entity==41 and native_use.lane=="tool" and native_use.xslot==0)
    pointer={x=21,y=22}; assert(not NHUI.useTarget(),"wands keep native handling")
    local oldSlot={x=tiles[1001].x+1,y=tiles[1001].y+1}
    render(m,39)
    panels,tiles={},{}
    render(m)
    assert(buttons[39].name=="[+] Equipment" and panels[10].x==5 and panels[10].h==20)
    assert(not panels[4200] and not tiles[1001],"folded case must hide perks and storage slots")
    pointer=oldSlot
    assert(not NHUI.useTarget(),"folded case must release its former slots")
    render({open=false});render(m)
    assert(buttons[39].name=="[+] Equipment")
    render(m,39);render(m)
    local saved=over(1001)
    assert(saved.container=="safe" and saved.slot==1 and saved.storedId==10 and saved.count==7)
    m.rightUse=saved
    over(1002)
    assert(not render(m),"moved from the prepared slot before dispatch")
    over(1001)
    m.rightUse=saved
    m.secure_loot[1].count=6
    assert(not render(m),"changed stack rejected")
    assert(use().count==6 and not render(m))
    over(1002);assert(use().kind=="card_wallet")
    over(1001);pointer.down,pointer.pressed=true,true
    render(m);assert(not NHUI.useTarget(),"left drag owns the slot")
    pointer={x=0,y=0};render(m)
    m.popup,m.pouchId,m.pouchName,m.pouchCapacity=true,99,"Pouch",2
    m.cells={{subtype="frost",remaining=2,count=1}}
    render(m)
    assert(over(1003).cell==1)
    local injection=use()
    assert(injection.container=="pouch" and injection.pouchId==99 and injection.subtype=="frost" and injection.remaining==2)
    local old=injection
    m.pouchId=nil;m.walletId,m.walletCapacity,m.pouchName=80,2,"Wallet"
    m.cells={{species="dryad",count=2,remaining=80}}
    m.rightUse=old;assert(not render(m))
    over(1003)
    local card=use()
    assert(card.container=="card_wallet" and card.walletId==80 and card.species=="dryad" and card.count==2)
    m.popup,m.walletId,m.near=false,nil,true
    m.warehouse={supplies={{id=71,name="Fire grenades",count=8,kind="fire_grenade"}}}
    m.warehouse_capacity={wand=10,supplies=10,equipment=10,spell=10,containers=10,collection=10}
    m.progression={expansion={},upgrade={}};m.recipes={};m.shopGoods={}
    m.surgery={kind="field_surgery_kit",elapsed=60,total=180}
    render(m,78);render(m)
    assert(drawn["Surgery  2.0 s"] and drawn["data/ui_gfx/1px_white.png"])
    over(1003)
    local stack=use()
    assert(stack.container=="warehouse" and stack.slot==1 and stack.storedId==71 and stack.count==8)
    local panel=panels[210]
    pointer={x=panel.x+8,y=panel.y+8}
    local beneath=native("tool",math.floor((pointer.x-20)/20),0,99,"medkit")
    beneath.yslot=math.floor((pointer.y-20)/20)
    m.native_slots={beneath}
    render(m);assert(not NHUI.useTarget(),"the hideout panel covers the native slot")
    render({open=false})
    assert(not NHUI.useTarget())
end
testRightUse()
print("UI: exact right-click sources, moving cursor, stale stacks, occlusion, left drag and inventory surgery HUD passed.")

do
    local m={open=false,lang="en",near=false,remote_linked=true}
    render(m)
    assert(drawn["Small terminal · Open inventory"])
    m.open,m.near,m.mode,m.status=true,true,"case",""
    m.capacity,m.maxUses,m.revision=2,3,1
    m.secure_loot={{id=91,kind="remote_terminal",name="Remote hideout terminal",remaining=18}}
    m.native_slots,m.warehouse={},{}
    m.warehouse_capacity={wand=48,spell=48,containers=48,supplies=48,equipment=48,collection=48,materials=16}
    m.progression,m.recipes,m.shopGoods={expansion={},upgrade={}},{},{}
    render(m)
    assert(buttons[71].name:find("Stash · Remote",1,true) and drawn["18/20"])
    pointer={x=tiles[1001].x+2,y=tiles[1001].y+2}
    render(m)
    assert(drawn["Deployments left 18/20"])
    local target=assert(NHUI.useTarget())
    assert(target.kind=="remote_terminal" and target.remaining==18 and target.storedId==91)
    render(m,79)
    render(m)
    pointer={x=tiles[1001].x+2,y=tiles[1001].y+2,pressed=true,down=true}
    render(m)
    pointer={x=tiles[1003].x+2,y=tiles[1003].y+2,released=true}
    local move,request=render(m)
    assert(move=="move_terminal" and request.source=="safe" and request.destination=="warehouse" and request.entity==91)
    m.open,m.near,m.remote_linked=false,false,false
    render(m)
    assert(not drawn["Small terminal · Open inventory"] and not NHUI.useTarget())
end

local function testContainerGrid(capacity,isWallet,standalone)
    local kind=isWallet and "card_wallet" or "pouch"
    local sample=isWallet and {species="dryad",remaining=79,count=1} or {subtype="frost",remaining=2,count=1}
    local m={open=true,lang="en",mode=standalone and "container" or "case",near=not standalone,
        capacity=2,secure_loot={},native_slots={},revision=1,status="",maxUses=3,popup=true,
        cells={[capacity]=sample},pouchName=kind,perkCapacity=2,perkCells={},packablePerk={entity=27,name="Perk"},
        warehouse={},warehouse_capacity={wand=10,spell=10,containers=10,supplies=10,equipment=10,collection=10,materials=10},
        progression={expansion={},upgrade={}},recipes={},shopGoods={}}
    if isWallet then m.walletId,m.walletCapacity=95,capacity else m.pouchId,m.pouchCapacity=97,capacity end
    pointer={x=0,y=0}
    render({open=false})
    tiles={}
    render(m)
    local popup=assert(panels[standalone and 10 or 37])
    local firstIndex=standalone and 1001 or 1003
    local first=assert(tiles[firstIndex])
    local tileWidth,tileHeight=GuiGetImageDimensions(nil,"data/ui_gfx/inventory/quick_inventory_box.png")
    local pitchX,pitchY=tileWidth*first.scale,tileHeight*first.scale
    local tolerance=0.001
    assert(popup.x>=0 and popup.y>=0 and popup.x+popup.w<=width+tolerance and popup.y+popup.h<=height+tolerance)
    for cell=1,capacity do
        local t=assert(tiles[firstIndex+cell-1])
        assert(math.abs(t.x-first.x-((cell-1)%4)*pitchX)<tolerance and
            math.abs(t.y-first.y-math.floor((cell-1)/4)*pitchY)<tolerance,"grid must use the native tile pitch in both axes")
        assert(t.x>=popup.x and t.x+pitchX<=popup.x+popup.w+tolerance and
            t.y>=popup.y and t.y+pitchY<=popup.y+popup.h+tolerance,"every cell must fit inside the popup")
    end
    if not standalone then
        local perks,secure=assert(panels[4200]),assert(panels[10])
        assert(perks.y>=0 and perks.y+perks.h<=popup.y and popup.y+popup.h<=secure.y+tolerance,
            "perk slots, container and secure case must stay visible without overlapping")
    end
    local last=assert(tiles[firstIndex+capacity-1])
    pointer={x=last.x+pitchX/2,y=last.y+pitchY/2}
    m.rightUse=assert(NHUI.useTarget())
    local action,req=render(m)
    assert(action=="use_inventory" and req.container==kind and req.cell==capacity)
    assert(isWallet and req.walletId==95 and req.species=="dryad" or
        not isWallet and req.pouchId==97 and req.subtype=="frost")

    pointer.down,pointer.pressed=true,true
    assert(not render(m))
    pointer={x=first.x+pitchX/2,y=first.y+pitchY/2,released=true}
    action,req=render(m)
    assert(action==(isWallet and "move_wallet_card" or "move_cell") and req.sourceCell==capacity and req.targetCell==1)
    assert(isWallet and req.walletId==95 or not isWallet and req.pouchId==97)
    m.cells={[1]=sample}
    pointer={x=first.x+pitchX/2,y=first.y+pitchY/2,down=true,pressed=true}
    assert(not render(m))
    pointer={x=last.x+pitchX/2,y=last.y+pitchY/2,released=true}
    action,req=render(m)
    assert(action==(isWallet and "move_wallet_card" or "move_cell") and req.sourceCell==1 and req.targetCell==capacity)
end
for _,size in ipairs({{640,360},{320,180}}) do
    width,height=size[1],size[2]
    for _,capacity in ipairs({4,8,12}) do
        for _,isWallet in ipairs({false,true}) do
            testContainerGrid(capacity,isWallet,false)
            testContainerGrid(capacity,isWallet,true)
        end
    end
end
print("UI: four-column containers fit both screen sizes, preserve perk clearance and dispatch the last cell of every tier.")

do
    local m={open=true,mode="case",lang="en",near=false,status="",revision=1,capacity=2,
        secure_loot={{id=50,kind="shield_basic",name="I",charge=120000}},native_slots={},gear={
        charger={id=51,kind="shield_charger",name="Charger",count=1,remaining=5},
        link={id=52,kind="data_link",name="Data link",count=1}}}
    for _,size in ipairs({{320,180},{640,360}}) do
        width,height=size[1],size[2]
        pointer={x=0,y=0}
        render({open=false})
        render(m)
        local function mouse(tile,event)
            local p=tiles[1000+tile]
            pointer={x=p.x+2,y=p.y+2,down=event=="press",pressed=event=="press",released=event=="release"}
            return render(m)
        end
        render(m,5102)
        mouse(1,"press")
        local function hoverTab(id)
            local b=buttons[id]
            pointer={x=b.x+1,y=b.y+1,down=true}
            render(m)
        end
        hoverTab(5101)
        local shield,charger,link=tiles[1001],tiles[1002],tiles[1005]
        local tileWidth=charger.x-shield.x
        assert(drawn["Shield<Charger"] and shield.y==charger.y and tileWidth==20*shield.scale)
        assert(link.y==shield.y and link.x==charger.x+1.5*tileWidth)
        assert(noticeText["Data link"].x==link.x and link.x+tileWidth<=panels[10].x+panels[10].w)
        assert(buttons[5101].y+9*buttons[5101].scale<shield.y)
        local action,req=mouse(1,"release")
        assert(action=="move_gear" and req.source=="safe" and req.destination=="gear" and req.entity==50)
        mouse(2,"press")
        assert(not mouse(2,"release"))
        m.rightUse=assert(NHUI.useTarget())
        action,req=render(m)
        assert(action=="use_inventory" and req.storedId==51 and req.container=="gear" and req.remaining==5)
        mouse(2,"press")
        hoverTab(5102)
        action,req=mouse(2,"release")
        assert(action=="move_gear" and req.destination=="safe" and req.safeSlot==2)
        NHUI.showTransfer("gear","shield_charger",2)
        render(m)
        mouse(2)
        assert(NHUI.useTarget().container=="gear")
        m.lang="zh"
        render(m)
        assert(drawn["护盾<充能器"] and drawn["弹挂<弹药盒"] and noticeText["数据链"].x==link.x)
        mouse(5)
        local equipped=assert(NHUI.useTarget())
        assert(equipped.kind=="data_link" and equipped.storedId==52 and equipped.container=="gear")
        mouse(5,"press")
        hoverTab(5102)
        action,req=mouse(2,"release")
        assert(action=="move_gear" and req.entity==52 and req.destination=="safe")
        m.lang="en"
    end
end

do
    local m={open=true,mode="case",lang="en",gear={},near=false,status="",revision=1,
        capacity=13,secure_loot={},native_slots={},maxUses=8}
    for i=1,13 do m.secure_loot[i]={id=100+i,kind="medkit",remaining=8,count=1,name="Kit"} end
    for _,size in ipairs({{320,180},{640,360}}) do
        width,height=size[1],size[2]
        render({open=false})
        NHUI.showTransfer("safe","medkit",12)
        render(m)
        local first=tiles[1001]
        local panel=panels[10]
        assert(buttons[39].y<buttons[5102].y and buttons[5101].y==buttons[5102].y)
        assert(buttons[5102].y+9*buttons[5102].scale<first.y and not drawn["Drag items to transfer"])
        for i=1,12 do
            local box=tiles[1000+i]
            assert(box.x==first.x+(i-1)%4*20*box.scale and box.y==first.y+math.floor((i-1)/4)*20*box.scale)
            assert(box.x>=panel.x and box.x+20*box.scale<=panel.x+panel.w)
            assert(box.y+20*box.scale<=panel.y+panel.h)
            pointer={x=box.x+1,y=box.y+1}
            local source=assert(NHUI.useTarget())
            assert(source.slot==i and source.storedId==100+i)
        end
        assert(tracks[7110].frame==frame)
        NHUI.showTransfer("safe","medkit",13)
        render(m)
        pointer={x=first.x+1,y=first.y+40*first.scale+1}
        assert(NHUI.useTarget().slot==13)
        pointer={x=first.x+21*first.scale,y=first.y+40*first.scale+1}
        assert(not NHUI.useTarget())
        m.capacity=12
        render(m)
        pointer={x=tiles[1002].x+1,y=tiles[1002].y+1}
        assert(not buttons[35] and not buttons[36] and NHUI.useTarget().slot==2)
        local heightWithTwelve=panels[10].h
        m.capacity=4
        render(m)
        assert(panels[10].h==heightWithTwelve and not drawn["Drag items to transfer"])
        m.capacity=13
    end
end

do
    local function insideCorner(tileId,text,lower)
        local tile,b=assert(tiles[tileId]),assert(badges[text],text)
        local pad,size=2*tile.scale,20*tile.scale
        local glyphs=#text-(lower and 1 or 0) -- UTF-8 multiplication sign occupies two bytes
        local expected=tile.scale*math.min(0.5,16/(7*glyphs-1))
        assert(math.abs(b.h-10*expected)<0.001 and b.w<=size-2*pad+0.001)
        if lower then
            assert(math.abs(tile.x+size-pad-b.x-b.w)<0.001 and math.abs(tile.y+size-pad-b.y-b.h)<0.001)
        else
            assert(math.abs(tile.x+pad-b.x)<0.001 and math.abs(tile.y+pad-b.y)<0.001)
        end
    end
    local m={open=true,mode="case",lang="zh",near=false,status="",revision=1,capacity=1,native_slots={},
        gear={charger={kind="shield_charger",remaining=6,count=1},rig={kind="ammo_rig",reserve=11},
            ammo={kind="ammo_pack",remaining=3,count=1}},
        secure_loot={{id=91,kind="summon_card",species="dryad",remaining=80,count=9754}}}
    for _,size in ipairs({{320,180},{640,360}}) do
        width,height=size[1],size[2]
        pointer={x=0,y=0}
        NHUI.showTransfer("gear","ammo_pack",4)
        render(m)
        insideCorner(1002,"6/8",false)
        insideCorner(1003,"11/240",false)
        insideCorner(1004,"3/8",false)
        assert(not badges["×1"])
        NHUI.showTransfer("safe","summon_card",1)
        render(m)
        insideCorner(1001,"80/80",false)
        insideCorner(1001,"×9754",true)
        assert(badges["80/80"].y+badges["80/80"].h<badges["×9754"].y)
    end
end

do
    local m={open=true,mode="case",lang="zh",near=false,status="",revision=1,capacity=12,native_slots={},gear={},secure_loot={},
        rescue={insured=true,species="cat",kept=321,limit=10000}}
    for _,size in ipairs({{320,180},{640,360}}) do
        width,height=size[1],size[2]
        pointer={x=0,y=0}
        NHUI.showTransfer("gear","ammo_pack",4)
        render(m)
        local panel=panels[10]
        local label="保险 已投保 · 保金 321"
        assert(drawn[label] and not drawn["同行 猫娘"] and not drawn["保金上限 10000"])
        local t=assert(rescueText[label])
        assert(t.y==44 and t.x>=5 and t.x+GuiGetTextDimensions(nil,label,t.scale)<=width-84)
        assert(tips[label]:find("猫娘",1,true) and tips[label]:find("10000",1,true))
        local shortHeight=panel.h
        m.rescue={insured=false,kept=0,limit=0}
        m.status="获得召唤卡：狮鹫少女"
        render(m)
        assert(drawn["保险 未投保"] and panels[10].h==shortHeight and not drawn[m.status])
        NHUI.showTransfer("safe","medkit",1)
        render(m)
        assert(drawn["保险 未投保"])
        m.open=false
        render(m)
        assert(drawn["保险 未投保"] and not panels[10])
        m.open=true
        m.rescue={insured=true,species="cat",kept=321,limit=10000}
    end
end

do
    width,height=427,240
    local m={open=false,near=false,lang="zh"}
    NHUI.notify("获得召唤卡：狮鹫少女")
    render(m)
    local label="获得召唤卡：狮鹫少女"
    assert(drawn[label] and hudImages[5801].a>0.85 and not panels[10])
    local text=noticeText[label]
    assert(text.x>=0 and text.x+GuiGetTextDimensions(nil,label,text.scale)<width)
    frame=frame+268
    render(m)
    assert(drawn[label] and hudImages[5801].a>0 and hudImages[5801].a<0.5)
    assert(noticeText[label].color[4]>0 and noticeText[label].color[4]<0.6)
    -- A repeated reward restarts its duration even when the message is identical.
    NHUI.notify(label)
    render(m)
    assert(hudImages[5801].a>0.85)
    frame=frame+300
    render(m)
    assert(not drawn[label])
    -- The preview uses camera coordinates and changes tint with placement validity.
    m.deployment={kind="turret_pack",x=150,y=120,valid=true}
    render(m)
    assert(hudImages[5830].x==140 and hudImages[5830].y==104)
    assert(hudImages[5830].color[2]>hudImages[5830].color[1])
    m.deployment.valid=false
    render(m)
    assert(hudImages[5830].color[1]>hudImages[5830].color[2])
    m.deployment={kind="remote_terminal",x=150,y=120,valid=true,
        icon="mods/noita_hideout/files/terminals/comms_small.png",width=24,height=24,offsetX=12,offsetY=18.75}
    render(m)
    assert(hudImages[5830].x==138 and hudImages[5830].y==101.25 and hudImages[5830].w==24)
    assert(hudImages[5830].color[2]>hudImages[5830].color[1] and drawn[m.deployment.icon])
    m.deployment.valid=false
    render(m)
    assert(hudImages[5830].color[1]>hudImages[5830].color[2])
    m.deployment=nil
    render(m)
    assert(not drawn[NHTurrets.types.turret_pack.icon])
end

do
    local card=NHCompanions.withCount({species="tarot_hermit",remaining=40},2)
    card.id,card.slot=10001,1
    local m={open=true,mode="case",lang="zh",near=false,status="",revision=1,capacity=12,native_slots={},gear={},secure_loot={card}}
    NHUI.showTransfer("safe","summon_card",1)
    render(m)
    assert(drawn["40/40"] and drawn["×2"])
    card.remaining,card.count=39,1
    render(m)
    assert(drawn["39/40"] and not drawn["39/80"])
end

do
    local m={open=false,lang="en",terminals={{x=100,y=40,text="10:00",warning=false,alpha=1}}}
    render(m)
    assert(drawn["10:00"] and noticeText["10:00"].y==40 and noticeText["10:00"].color[2]==1)
    m.terminals[1].text,m.terminals[1].warning,m.terminals[1].alpha="2:59",true,0.25
    render(m)
    assert(drawn["2:59"] and noticeText["2:59"].color[1]==1 and noticeText["2:59"].color[2]==0.2 and noticeText["2:59"].color[4]==0.25)
    m.terminals={}
    render(m)
    assert(not drawn["2:59"])
end
print("Remote terminal countdown renders above world position, flashes red and vanishes on expiry.")

do
    local values={x=2,y=8,hp=150,maxHP=300,rounds=750,capacity=3000}
    local m={open=false,lang="zh",turretStatus=values}
    pointer={x=200,y=180}
    hudImages={}
    render(m)
    assert(drawn["耐久 150/300"] and drawn["弹药 750/3000"])
    assert(hudImages[5840].x>=0 and hudImages[5840].y>=0)
    assert(hudImages[5840].y+hudImages[5840].h<hudImages[5843].y)
    assert(hudImages[5841].w==hudImages[5844].w and hudImages[5842].w==hudImages[5841].w/2)
    assert(hudImages[5845].w==hudImages[5844].w/4)
    local red,yellow=hudImages[5842].color,hudImages[5845].color
    assert(red[1]>0.8 and red[2]<0.35 and red[3]<0.35)
    assert(yellow[1]>0.8 and yellow[2]>0.75 and yellow[3]<0.3)
    m.lang="en"
    values.hp,values.maxHP,values.rounds,values.capacity=500,500,0,500
    hudImages={}
    render(m)
    assert(drawn["HP 500/500"] and drawn["Ammo 0/500"])
    assert(hudImages[5841].w==hudImages[5842].w and hudImages[5844] and not hudImages[5845])
    local empty=noticeText["Ammo 0/500"].color
    assert(empty[1]==yellow[1] and empty[2]==yellow[2] and empty[3]==yellow[3])
    pointer={x=hudImages[5844].x+3,y=hudImages[5844].y}
    render(m)
    assert(not drawn["HP 500/500"] and not drawn["Ammo 0/500"])
    pointer={x=0,y=0}
end

do
    dofile("mods/noita_hideout/files/ui.lua")
    local m={open=true,mode="case",lang="zh",near=true,capacity=2,secure_loot={},native_slots={},revision=1,status="",
        warehouse={},warehouse_capacity={wand=48,spell=48,containers=48,supplies=48,equipment=48,collection=48,materials=16},
        essences={},docks={},materials={},
        progression={expansion={},upgrade={}},shopGoods={},recipes={
            {id="philosopher_stone",category="alchemy",alchemyMode="rubedo",name="贤者之石",output=10,outputs={{key="nh_philosopher_stone",name="贤者之石",amount=10,stock=9}},
                inputs={{name="点金水",amount=1,available=1},{name="存钱罐金币",amount=5000,available=5000}},catalysts={},ready=true},
            {id="supply_logistics",category="alchemy",alchemyMode="logistics",name="补给资源包",output=50,inputs={},outputs={{key="supply_logistics",name="补给资源包",amount=50,stock=12}},ready=true},
            {id="stable",category="alchemy",alchemyMode="synthesis",name="稳定传送液",output=500,inputs={},outputs={},ready=true}}}
    pointer={x=0,y=0}
    render(m)
    assert(buttons[274] and buttons[275] and not buttons[267])
    render(m,212); render(m)
    assert(drawn["红化"])
    render(m,267)
    render(m)
    assert(drawn["贤者之石"] and not drawn["稳定传送液"])
    render(m,244)
    render(m)
    assert(drawn["< 红化"] and drawn["确认红化"] and drawn["即时完成"])
    local command,request=render(m,214)
    assert(command=="craft" and request.id=="philosopher_stone")
    render(m,240)
    render(m,268)
    render(m)
    assert(drawn["补给资源包"] and not drawn["贤者之石"])
    render(m,244)
    render(m)
    assert(drawn["成品库存"] and drawn["制作资源包"])
    command,request=render(m,214)
    assert(command=="craft" and request.id=="supply_logistics")
end
print("Rubedo and logistics UI: recipe filtering, resource balances and craft actions passed.")

do
    dofile("mods/noita_hideout/files/ui.lua")
    local m={open=true,mode="case",lang="en",near=true,capacity=2,secure_loot={},native_slots={},revision=1,
        warehouse={},warehouse_capacity={wand=10,spell=10,containers=10,supplies=10,equipment=10,collection=10,materials=16},
        docks={},materials={{key="a",name="Grain",amount=2},{key="b",name="Sugar",amount=6}},
        essences={{key="first",name="First",amount=10},{key="second",name="Second",amount=50}},
        progression={expansion={},upgrade={}},shopGoods={},recipes={},status=""}
    pointer={x=0,y=0}
    render(m)
    for id,category in pairs({[75]="wand",[76]="spell",[77]="containers",[78]="supplies",[79]="equipment",[83]="collection"}) do
        render(m,id)
        local cmd,request=render(m,7080)
        assert(cmd=="organize_warehouse" and request.category==category)
    end
    render(m,80)
    assert(not render(m,7080))
    assert(noticeText.Sugar.x<noticeText.Grain.x and m.materials[1].key=="a")
    render(m,82)
    assert(not render(m,7080))
    assert(noticeText.Second.x<noticeText.First.x and m.essences[1].key=="first")
end
