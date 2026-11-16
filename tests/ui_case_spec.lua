local width, height = 427, 240
local click, action, argument
local drawn = {}
local frame = 0
local pointer = {x = 0, y = 0}
function GameGetFrameNum() return frame end
function InputIsMouseButtonDown() return pointer.down == true end
function InputIsMouseButtonJustDown() return pointer.pressed == true end
function InputIsMouseButtonJustUp() return pointer.released == true end
function GameGetCameraBounds() return 0, 0, width, height end
function DEBUG_GetMouseWorld() return pointer.x, pointer.y end
function GuiCreate() return {} end
function GuiStartFrame() drawn = {} end
function GuiGetScreenDimensions() return width, height end
function GuiZSet() end
function GuiZSetForNextWidget() end
local next_color,image_colors={},{}
function GuiColorSetForNextWidget(_,r,g,b) next_color={r,g,b} end
local tipbox
function GuiImageNinePiece(_,id,x,y,w,h)
    if id==200 then tipbox={x=x,y=y,w=w,h=h} end
end
local tiles={}
function GuiImage(_,id,x,y,sprite)
    image_colors[id],next_color=next_color,{}
    if sprite=="data/ui_gfx/inventory/quick_inventory_box.png" then tiles[id]={x=x,y=y} end
end
function GuiTooltip() end
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
    buttons[id]={x=x,y=y}
    drawn[value] = true
    return id == click
end
function GuiImageButton(_, id) return id == click end

dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
function CellFactory_GetType() return -1 end
dofile("mods/noita_hideout/files/ui.lua")
local function render(model, widget)
    frame = frame + 1
    click, action, argument = widget, nil, nil
    NHUI.draw(model, function(command, item)
        assert(not action, "multiple actions on a single input")
        action, argument = command, item
    end)
    return action, argument
end

local function native(lane,col,x,id,kind)
    return {key="native",lane=lane,col=col,xslot=x,yslot=0,entity=id,kind=kind,parent=lane=="spell" and 3 or 2}
end
local model={lang="en",open=false,near=false,status=""}
assert(not render(model,2))
model.open,model.mode,model.pouch_location,model.case_count=true,"case","safe",2
model.capacity,model.revision,model.secure_loot=4,1,{[3]={kind="pouch",name="Pouch"}}
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
assert(cmd=="open_container" and arg.safeSlot==3)
model.popup=true
model.maxUses,model.pouchCapacity,model.cells=3,4,{{remaining=3,count=2}}
render(model)
for i=102,103 do assert(tiles[i].x-tiles[i-1].x==20) end -- case
for i=105,107 do assert(tiles[i].x-tiles[i-1].x==20) end -- pouch
point(cx+58,cy+30,"press")
cmd,arg=point(148,28,"release")
assert(cmd=="take_pouch" and arg.xslot==2 and arg.safeSlot==3)
point(108,28,"press")
cmd,arg=point(cx+12,cy-38,"release")
assert(cmd=="place" and arg.entity==43 and arg.intoContainer)
point(cx+12,cy-38,"press")
cmd,arg=point(cx+12,cy+30,"release")
assert(cmd=="unpack_dose" and arg.safeSlot==1)
model.secure_loot[1]={kind="dose",id=9}
point(cx+12,cy+30,"press")
cmd,arg=point(cx+12,cy-38,"release")
assert(cmd=="pack_dose" and arg.safeSlot==1)
point(cx+12,cy-38,"press")
cmd,arg=point(cx+72,cy-38,"release")
assert(cmd=="move_cell" and arg.sourceCell==1 and arg.targetCell==4)
model.cells[4]={remaining=2,count=1}
point(cx+12,cy-38,"press")
assert(not point(cx+72,cy-38,"release"))
point(cx+72,cy-38,"press")
cmd,arg=point(148,28,"release")
assert(cmd=="take_dose" and arg.sourceCell==4)
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
model.near,model.warehouse,model.warehouse_last=true,{},{}
render(model)
local origin=tiles[104]
assert(tiles[105].x-origin.x==20)
local nextrow
for _,t in pairs(tiles) do if t.x==origin.x and t.y==origin.y+20 then nextrow=t end end
assert(nextrow)
point(198,28,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="place" and arg.kind=="spell" and arg.container=="warehouse" and arg.safeSlot==1)
model.warehouse.spell={{kind="spell",name="Bomb",id=32}}
model.warehouse_last.spell=1
point(origin.x+1,origin.y+1,"press")
cmd,arg=point(298,28,"release")
assert(cmd=="secure_withdraw" and arg.container=="warehouse" and arg.storedId==32 and arg.xslot==5)
-- Each category pages independently and the next empty page remains writable.
model.warehouse_last.spell=20
render(model,73)
point(198,28,"press")
cmd,arg=point(origin.x+1,origin.y+1,"release")
assert(cmd=="place" and arg.safeSlot==21)
model.docks,model.materials={},{}
render(model,79)
render(model)
assert(drawn.Flask and drawn["Powder pouch"] and drawn.Empty)
local flask,powder=tiles[104],tiles[105]
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
assert(drawn["1k"] and drawn["1.2M"] and drawn["1/2"] and buttons[188].x>load_button.x and buttons[188].y==load_button.y)
local button2=buttons[188]
point(button2.x+1,button2.y+1)
assert(drawn["M2  1000"])
render(model,185)
assert(drawn["M9"] and not drawn["M2"])
render(model,184)
point(flask.x+1,flask.y+1)
assert(drawn["Flask  20/50"] and drawn["water  12"] and drawn["slime  8"])
assert(image_colors[134][1]==128/255 and image_colors[134][2]==32/255 and image_colors[134][3]==16/255)
assert(image_colors[131][1]==128/255)
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
assert(image_colors[134][1]==128/255)
local first_tile=tiles[104]
point(first_tile.x+1,first_tile.y+1)
assert(drawn["Flask  20/50"] and drawn["water  12"])
render(model,71)
render(model)
assert(drawn["[+] Stash"] and not drawn.Materials)
model.near=false
render(model)
assert(not drawn["[+] Stash"])
