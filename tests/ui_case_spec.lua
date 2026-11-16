local width, height = 427, 240
local click, action, argument
local drawn,panels = {},{}
local frame = 0
local pointer = {x = 0, y = 0}
function GameGetFrameNum() return frame end
function InputIsMouseButtonDown() return pointer.down == true end
function InputIsMouseButtonJustDown(which) return (which==2 and pointer.right) or (which==1 and pointer.pressed) or false end
function InputIsMouseButtonJustUp() return pointer.released == true end
function GameGetCameraBounds() return 0, 0, width, height end
function DEBUG_GetMouseWorld() return pointer.x, pointer.y end
function GuiCreate() return {} end
function GuiStartFrame() drawn,panels = {},{} end
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
dofile("mods/noita_hideout/files/transfers.lua")
dofile("mods/noita_hideout/files/perks.lua")
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
for i=1002,1003 do assert(tiles[i].x-tiles[i-1].x==20) end -- case
for i=1005,1007 do assert(tiles[i].x-tiles[i-1].x==20) end -- pouch
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
model.near,model.warehouse=true,{}
model.warehouse_capacity={wand=48,spell=48,containers=48,supplies=48,materials=16}
model.debug,model.batch_available,model.ingredients=true,true,{slime=300,magic_liquid_unstable_teleportation=500}
local profile={safeCapacity=2,levels={},materials={water=500,sand=350,slime=200},resources={}}
model.progression=NHStore.progressMenu(profile,"en")
model.recipes={{id="stable",name="Teleportatium",output=500,ready=true,inputs={{name="Slime",available=300,amount=250}}},
    {id="medical",name="Medical pack",output=1,ready=true,inputs={{name="Slime",available=300,amount=100}}}}
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
model.docks,model.materials={},{}
render(model,79)
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
end
local action,param=render(model,214)
assert(action=="craft" and param.id=="stable")
render(model,251)
action,param=render(model,214)
assert(action=="craft" and param.id=="medical")
render(model,250)
assert(render(model,215)=="simulate")
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
assert(not render(model,244))
render(model)
assert(drawn["Now: 48 slots"] and drawn["Next: 72 slots"] and drawn["350 / 200"])
action,param=render(model,241)
assert(action=="buy_upgrade" and param.id=="warehouse_wand" and param.level==0)
render(model,243)
render(model,247) -- Salvage bench, missing oil.
assert(not render(model,241) and drawn["Insufficient stock"])
render(model,240)
render(model,248) -- Future support station.
assert(not render(model,241) and drawn["In development"])
render(model,219)
render(model,244)
render(model)
assert(drawn["Now: 2 slots"] and drawn["Next: 3 slots"])
action,param=render(model,241)
assert(action=="buy_upgrade" and param.id=="safe")
model.salvage_enabled,model.scrap=true,2
model.warehouse.spell[1].salvage_yield=3
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
