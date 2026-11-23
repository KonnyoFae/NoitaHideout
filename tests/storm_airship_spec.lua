local root="mods/noita_hideout/files/storm/sites/"
local ship=dofile(root.."airship.lua")
local locations=dofile(root.."locations.lua")
local frame,px,py=54030,0,-8
local loaded,sky,obstacle=false,1,false
local streamFleet=false
local streamBounds
local globals,objects,scenes,notices={},{},{},{}
local failure,removed=nil,0
local cells,backgrounds={},{}
local function pos(x,y) return x..","..y end
local materials={air=0,steel_static=1,wood_static=2}
function CellFactory_GetType(name) return assert(materials[name]) end
function ConvertMaterialOnAreaInstantly(x,y,w,h,source,target,trim,edges)
    assert((source==1 or source==2) and target==0 and not trim and not edges)
    -- Engine probes show that square extents are inclusive. A zero extent clears one cell.
    assert(w==h and w>=0)
    for iy=y,y+h do for ix=x,x+w do
        local p=pos(ix,iy)
        if cells[p]==source then cells[p]=nil end
    end end
end
local function register(path,x,y)
    local kind=path:match("([^/]+)%.xml$") or path
    local e={x=x,y=y,tags={["nh_"..kind]=true},kind=kind,sprite={}}
    if kind=="ship_safe" or kind=="ship_cache" then e.interact={} end
    if kind=="ship_safe_lv1" or kind=="ship_safe_lv3" then
        e.interact={}
        e.tags.nh_ship_safe=true
        e.tags.nh_ship_box_art=true
        e.sprite.image_file=root..kind:sub(6).."_sprite.xml"
    end
    objects[#objects+1]=e
    return #objects
end
local player=register("player",px,py)
objects[player].tags.player_unit=true
function GlobalsGetValue(k,d) return globals[k] or d end
function GlobalsSetValue(k,v) globals[k]=v end
function GameGetFrameNum() return frame end
function GameGetCameraBounds() return px-200,py-115,400,230 end
function GameGetSkyVisibility() return sky end
function DoesWorldExistAt(x1,y1,x2,y2)
    return loaded and (streamFleet or x2-x1<500) and (not streamBounds or (x1>=streamBounds[1] and y1>=streamBounds[2]
        and x2<=streamBounds[3] and y2<=streamBounds[4]))
end
function RaytraceSurfaces(x,a,_,b) return a<0 and b>=0,x,0 end
function RaytracePlatforms(x,a,_,b) return a<0 and b>=0,x,0 end
function RaytraceSurfacesAndLiquiform() return obstacle end
function EntityGetTransform(id)
    if id==player then return px,py end
    return objects[id].x,objects[id].y
end
function EntityGetWithTag(tag)
    local found={}
    for i,e in ipairs(objects) do if e.tags[tag] and not e.dead then found[#found+1]=i end end
    return found
end
function EntityGetInRadiusWithTag(x,y,r,tag)
    local found={}
    for _,i in ipairs(EntityGetWithTag(tag)) do
        if (objects[i].x-x)^2+(objects[i].y-y)^2<=r*r then found[#found+1]=i end
    end
    return found
end
function EntityLoad(path,x,y)
    if failure and path:find(failure,1,true) then return 0 end
    return register(path,x,y)
end
function EntityKill(i) objects[i].dead=true end
function EntityHasTag(i,t) return objects[i].tags[t] end
function EntityAddTag(i,t) objects[i].tags[t]=true end
function EntityRemoveTag(i,t) objects[i].tags[t]=nil end
function EntityGetFirstComponentIncludingDisabled(i,t)
    if t=="InteractableComponent" then return objects[i].interact end
    if t=="SpriteComponent" then return objects[i].sprite end
end
function EntityRemoveComponent(i,c) assert(objects[i].interact==c); objects[i].interact=nil end
function ComponentSetValue2(c,k,v) c[k]=v end
function EntityRefreshSprite() end
function LoadPixelScene(file,colors,x,y,bg)
    local name=file==root.."steel_fleet_materials.png" and "steel_fleet" or "ship"
    assert(file==root..name.."_materials.png" and bg==root..name.."_background.png")
    assert(colors==(name=="steel_fleet" and bg or ""))
    scenes[#scenes+1]={x=x,y=y,name=name}
    backgrounds[pos(x,y)]=bg
    for material,rects in pairs(dofile(root..name.."_solids.lua")) do
        for _,r in ipairs(rects) do
            for iy=y+r[2],y+r[2]+r[3]-1 do for ix=x+r[1],x+r[1]+r[3]-1 do
                cells[pos(ix,iy)]=materials[material]
            end end
        end
    end
end
function RemovePixelSceneBackgroundSprite(bg,x,y)
    assert(bg==root.."ship_background.png" or bg==root.."steel_fleet_background.png")
    removed=removed+1
    local p=pos(x,y)
    local existed=backgrounds[p]~=nil
    backgrounds[p]=nil
    return existed
end
function GamePrintImportant(title) notices[#notices+1]=title end
function GameTextGetTranslatedOrNot(key) return key end
function GamePrint(message) notices[#notices+1]=message end
function ProceduralRandomi(_,__,lo) return lo end
local round=0
local function tick(phase)
    phase=phase or 4
    if not streamFleet then globals["cycle_storm.sites.ship_steel_round"]=tostring(round) end
    local retiring=ship.service(phase,frame-round)
    if phase==4 and not retiring then ship.arrive() end
    frame=frame+60
    return retiring
end
-- Unspent quota in a 0.42.5 save must never spawn a ship during heavy rain.
globals["cycle_storm.sites.ship_remaining"]="2"
globals["cycle_storm.sites.ship_round"]="-72000"
loaded=true; frame=53970; tick(3)
assert(#scenes==0 and #notices==0)
loaded=false; tick()
loaded,obstacle=true,true; tick()
obstacle,sky=false,0; tick()
sky,failure=1,"scavenger_smg"; tick()
assert(#scenes==0 and #EntityGetWithTag("nh_ship_safe")==0 and globals["cycle_storm.sites.ship_remaining"]=="3")
failure=nil
tick(); tick()
px=1100; tick(); px=2000; tick()
assert(#scenes==3 and globals["cycle_storm.sites.ship_remaining"]=="0")
local left,top=scenes[1].x,scenes[1].y
local ax,ground=left+20,top+168
local function box(scene,cache)
    return EntityGetInRadiusWithTag(scene.x+(cache and 55 or 133),scene.y+74,2,cache and "nh_ship_cache" or "nh_ship_safe")[1]
end
local safe,cache=box(scenes[1]),box(scenes[1],true)
assert(left>200 and EntityGetInRadiusWithTag(ax,ground-12,1,"nh_mooring_light")[1])
assert(#EntityGetWithTag("nh_scavenger_smg")==3)
failure="improved_supply_pack"; ship.open(player,safe)
assert(locations.shipState(ax,ground)==0 and #EntityGetWithTag("nh_goldnugget_50")==0)
failure=nil; ship.open(player,safe); ship.open(player,safe)
assert(#EntityGetWithTag("nh_goldnugget_50")==1 and locations.shipState(ax,ground)==1)
assert(objects[safe].sprite.rect_animation=="open" and objects[safe].sprite.next_rect_animation=="open")
assert(locations.nearby(ax,ground,frame)[1].x==ax)
ship.open(player,box(scenes[2],true))
ship.open(player,cache); ship.open(player,cache)
assert(locations.shipState(ax,ground)==3 and objects[cache].sprite.rect_animation=="open")
assert(locations.nearby(ax,ground,frame)[1].x~=ax)
-- Stream in old saves containing both the standalone sprites and the former green Lv2 safe.
local closedSafe=box(scenes[2])
local closedCache=box(scenes[3],true)
for _,id in ipairs({safe,closedSafe,cache,closedCache}) do
    EntityRemoveTag(id,"nh_ship_box_art")
end
EntityAddTag(safe,"nh_ship_safe_lv2")
objects[safe].sprite={image_file=root.."safe_lv2_sprite.xml",rect_animation="open",special_scale_x=0.5,special_scale_y=0.5}
objects[closedSafe].sprite={offset_x=9,offset_y=16,image_file=root.."ship_safe.png"}
objects[cache].sprite={offset_x=9,offset_y=13,image_file=root.."ship_cache_open.png"}
objects[closedCache].sprite={offset_x=9,offset_y=13,image_file=root.."ship_cache.png"}
local previousFrame=frame
frame=frame-frame%120
ship.service(1,0)
frame=previousFrame
for _,id in ipairs({safe,closedSafe,cache,closedCache}) do
    local s=objects[id].sprite
    local art=EntityHasTag(id,"nh_ship_cache") and "supply_safe_sprite.xml" or "safe_lv2_sprite.xml"
    assert(EntityHasTag(id,"nh_ship_box_art") and s.image_file==root..art)
    assert(s.has_special_scale and s.special_scale_x==0.5 and s.special_scale_y==0.5)
    assert(s.offset_x==0 and s.offset_y==0 and s.rect_animation==s.next_rect_animation)
end
assert(objects[safe].sprite.rect_animation=="open" and not objects[safe].interact)
assert(objects[closedSafe].sprite.rect_animation=="closed" and objects[closedSafe].interact)
assert(objects[cache].sprite.rect_animation=="open" and not objects[cache].interact)
assert(objects[closedCache].sprite.rect_animation=="closed" and objects[closedCache].interact)
ship.open(player,cache)
ship.open(player,safe)
assert(#EntityGetWithTag("nh_goldnugget_50")==1 and locations.shipState(ax,ground)==3)
-- Leaving the ship unloaded preserves its cleanup record across save/load.
loaded=false; tick(5); assert(#scenes==3)
ship=dofile(root.."airship.lua")
loaded=true; px=ax; sky=0; tick(5)
assert(#scenes==3 and not objects[safe].dead)
px,py=left+134,top+70; tick(5) -- on board
px,py=left+40,top+116; tick(5) -- on the boarding steps
assert(removed==0 and locations.shipState(ax,ground)==3)
assert(locations.nearby(px,py,frame)[1].x~=ax)
assert(locations.nearby(ax-160,ground,frame)[1].x~=ax)
assert(locations.shipOverlaps(ax-13,ground-26,ax+13,ground+8))
local function pixel(x,y) return pos(left+x,top+y) end
local steel,wood=materials.steel_static,materials.wood_static
assert(cells[pixel(20,168)]==steel and cells[pixel(40,108)]==steel and cells[pixel(39,6)]==wood)
cells[pixel(70,78)]=3        -- another material now fills a damaged deck pixel
cells[pixel(130,72)]=steel   -- player-built steel inside the cabin
cells[pixel(20,171)]=wood    -- ground immediately below the anchor
cells[pixel(152,60)]=steel   -- same material immediately outside the upright
local guard=EntityGetInRadiusWithTag(left+43,top+65,1,"nh_shotgunner_weak")[1]
local wanderer=EntityGetInRadiusWithTag(left+86,top+65,1,"nh_scavenger_smg")[1]
objects[wanderer].x=left+600
local nearby=register("unrelated",left+50,top+74)
local gold=EntityGetWithTag("nh_goldnugget_50")[1]
px,py=left+140,ground-8; tick(); ship=dofile(root.."airship.lua"); tick()
for _,phase in ipairs({5,1,2,3}) do tick(phase) end
assert(removed==0 and locations.shipState(ax,ground)==3)
round=72000; frame=round+54030
px,py=left+134,top+70; sky=1
assert(tick() and locations.shipState(ax,ground)==4 and #scenes==3)
px,py=left+40,top+116
assert(tick() and removed==0)
px,py=left+140,ground-8
assert(tick() and globals["cycle_storm.sites.ship_remaining"]=="3")
assert(#scenes==3 and removed==1 and not backgrounds[pos(left,top)])
assert(not cells[pixel(20,168)] and not cells[pixel(40,108)] and not cells[pixel(39,6)])
assert(cells[pixel(70,78)]==3 and cells[pixel(130,72)]==steel and cells[pixel(20,171)]==wood)
assert(cells[pixel(152,60)]==steel)
for y=52,73 do for x=148,151 do assert(not cells[pixel(x,y)]) end end
for y=156,164 do assert(not cells[pixel(20,y)]) end
assert(objects[safe].dead and objects[cache].dead and objects[guard].dead)
assert(not EntityGetInRadiusWithTag(ax,ground-12,1,"nh_mooring_light")[1])
assert(not objects[wanderer].dead and not objects[nearby].dead and not objects[gold].dead)
assert(not locations.shipState(ax,ground) and not locations.shipOverlaps(ax-53,ground-231,ax+53,ground+8))
assert(locations.shipState(scenes[2].x+20,ground)==2)
sky=0; tick()
local supports=locations.nearby(ax,ground,frame)
assert(#supports==1 and supports[1].x~=ax and supports[1].count==2)
globals["cycle_storm.sites.rig_locations"]=string.format("%d,0,-1;%d,0,-1",ax+2048,ax+2049)
globals["cycle_storm.sites.well_locations"]=string.format("%d,0,%d",ax+45,frame)
supports=locations.nearby(ax,ground,frame)
assert(#supports==2 and supports[2].x==ax+2048)
local paid,reported=0,nil
local function pay() paid=paid+1; return true end
local function report(msg) reported=msg end
px,py=ax,0
locations.scan(player,function() return false end,report); assert(not locations.active(frame))
locations.scan(player,pay,report); locations.scan(player,pay,report)
assert(paid==1 and reported=="Radar already active." and locations.active(frame+599))
frame=frame+600; px=ax+9000; locations.scan(player,pay,report)
assert(paid==1 and not locations.active(frame) and notices[#notices]=="$nh_storm_scan_empty")
-- Moving between worlds during the same core spends the same quota, near
-- the current camera each time, even across a Lua reload.
sky=1; px=35840; frame=round+54150; tick()
assert(#scenes==4 and math.abs(scenes[4].x-px)<500 and globals["cycle_storm.sites.ship_remaining"]=="2")
ship=dofile(root.."airship.lua"); px=-35840; tick()
assert(#scenes==5 and math.abs(scenes[5].x-px)<500 and globals["cycle_storm.sites.ship_remaining"]=="1")
-- Old version's six scheduled replacements are now removals. Never offer them
-- to the radar or release partially streamed structures for overlapping placement.
local waiting={{-5229,-314},{-5672,-425},{900,-674},{2001,-59},{1566,7},{-9203,-222}}
globals["cycle_storm.sites.ship_locations"]=""
for _,p in ipairs(waiting) do locations.setShip(p[1],p[2],4) end
ship=dofile(root.."airship.lua")
for i,p in ipairs(waiting) do
    local x,y=p[1],p[2]
    px,py=x-90,y
    streamBounds={x-28,y-176,x+148,y+5} -- bottom row has not streamed in
    tick(1); assert(#scenes==5 and locations.shipState(x,y)==4)
    assert(locations.shipOverlaps(x-10,y-20,x+10,y+2))
    for _,site in ipairs(locations.nearby(px,py,frame)) do assert(site.kind~="ship") end
    streamBounds[4]=y+6
    assert(tick(3) and locations.shipState(x,y)==4)
    assert(tick())
    assert(not locations.shipState(x,y) and #scenes==5 and removed==i+1)
    assert(not locations.shipOverlaps(x-10,y-20,x+10,y+2))
    if waiting[i+1] then assert(locations.shipState(unpack(waiting[i+1]))==4) end
end
assert(globals["cycle_storm.sites.ship_remaining"]=="1")
-- A completely independent, quota-consuming placement can now select the cleared berth.
streamBounds=nil; px,py=0,-8; frame=round+54510; tick()
assert(#scenes==6 and scenes[6].x==left and scenes[6].y==top)
assert(locations.shipState(ax,ground)==0 and globals["cycle_storm.sites.ship_remaining"]=="0")
-- A formation consumes a single opportunity. Retries and changing world do not
-- duplicate the flagship. Old, unversioned berth records still load alongside it.
px,py=8192,-8
globals["cycle_storm.sites.ship_steel_round"]="-1"
globals["cycle_storm.sites.ship_remaining"]="1"
ship.arrive()
assert(#scenes==6 and globals["cycle_storm.sites.ship_remaining"]=="1")
streamFleet=true; px,py=8192,-8; round=144000;frame=round+54030
failure="mooring_light"; tick()
assert(#scenes==6 and #EntityGetWithTag("nh_steel_fleet_box")==0 and globals["cycle_storm.sites.ship_remaining"]=="3")
failure=nil;tick()
assert(#scenes==7 and scenes[7].name=="steel_fleet" and globals["cycle_storm.sites.ship_remaining"]=="2")
local fx,fy=scenes[7].x,scenes[7].y
local gx,gy=fx+28,fy+492
local function fleetCell(x,y) return pos(fx+x,fy+y) end
assert(locations.shipState(gx,gy)==0 and globals["cycle_storm.sites.ship_locations"]:find(":steel",1,true))
assert(locations.shipOverlaps(fx+490,fy+20,fx+503,fy+31))
assert(cells[fleetCell(60,398)] and cells[fleetCell(168,327)] and cells[fleetCell(175,233)])
assert(not cells[fleetCell(164,233)] and not cells[fleetCell(235,184)] and not cells[fleetCell(121,170)])
local fs=EntityGetInRadiusWithTag(fx+384,fy+157,1,"nh_ship_safe")[1]
local fc=EntityGetInRadiusWithTag(fx+182,fy+233,1,"nh_ship_cache")[1]
assert(fs and fc and objects[fs].sprite.image_file==root.."safe_lv3_sprite.xml")
local function at(x,y)
    local ids=EntityGetInRadiusWithTag(fx+x,fy+y,1,"nh_ship_safe")
    assert(#ids==1)
    return ids[1]
end
local red,chart,gas=at(273,233),at(86,179),at(404,48)
assert(objects[red].kind=="ship_safe_lv1" and objects[chart].kind=="ship_safe" and objects[gas].kind=="ship_safe")
assert(#EntityGetWithTag("nh_steel_fleet_box")==5)
EntityKill(fc);px=fx+900;sky=0;tick(5)
fc=assert(EntityGetInRadiusWithTag(fx+182,fy+233,1,"nh_ship_cache")[1])
assert(EntityHasTag(fc,"nh_steel_fleet_box"))
ship=dofile(root.."airship.lua");sky=1;tick()
assert(scenes[8].name=="ship" and globals["cycle_storm.sites.ship_remaining"]=="1")
ship.open(player,fs);ship.open(player,fc)
assert(locations.shipState(gx,gy)==3 and objects[fs].sprite.image_file==root.."safe_lv3_sprite.xml")
local function onRadar()
    for _,row in ipairs(locations.nearby(gx,gy,frame)) do
        if row.kind=="ship" and row.x==gx then return true end
    end
    return false
end
assert(onRadar())
round=180000; frame=round+54030; sky=0; tick()
assert(locations.shipState(gx,gy)==3 and backgrounds[pos(fx,fy)])
local goldBefore=#EntityGetWithTag("nh_goldnugget_50")
failure="improved_supply_pack";ship.open(player,red);failure=nil
assert(locations.shipState(gx,gy)==3 and #EntityGetWithTag("nh_goldnugget_50")==goldBefore)
ship.open(player,gas);ship.open(player,red);ship.open(player,gas)
assert(locations.shipState(gx,gy)==23 and onRadar())
ship=dofile(root.."airship.lua")
EntityKill(red);EntityKill(chart);px=fx+900;tick(5)
assert(#EntityGetInRadiusWithTag(fx+273,fy+233,1,"nh_ship_safe")==0)
chart=at(86,179)
ship.open(player,chart);ship.open(player,chart)
assert(locations.shipState(gx,gy)==31 and not onRadar() and #EntityGetWithTag("nh_goldnugget_50")==goldBefore+3)
round=216000; frame=round+54030
for _,where in ipairs({{384,165},{165,310},{64,395},{28,478}}) do
    px,py=fx+where[1],fy+where[2];tick()
    assert(locations.shipState(gx,gy)==32 and backgrounds[pos(fx,fy)])
end
px,py=gx-120,gy;sky=0
streamBounds={fx-8,fy+2,fx+520,gy+6};tick()
assert(locations.shipState(gx,gy)==32)
streamBounds=nil
cells[fleetCell(164,235)]=steel -- player-built cell in the open hatch
assert(tick() and not locations.shipState(gx,gy) and not backgrounds[pos(fx,fy)])
assert(not cells[fleetCell(60,398)] and not cells[fleetCell(168,327)] and not cells[fleetCell(175,233)])
assert(cells[fleetCell(164,235)]==steel and objects[fs].dead and objects[fc].dead)
-- Upgrade an in-use 0.42.18 fleet as rooms stream in. An already cleared
-- or retiring old fleet must never re-enter the radar or receive these safes.
globals["cycle_storm.sites.ship_locations"]=("%d,%d,2:steel;%d,%d,3:steel;%d,%d,4:steel"):format(gx,gy,gx+4096,gy,gx+8192,gy)
assert(locations.shipState(gx+4096,gy)==31 and locations.shipState(gx+8192,gy)==32)
px,py=fx+273,fy+221
streamBounds={fx+250,fy+200,fx+300,fy+248}
tick(1)
red=at(273,233);ship.open(player,red)
assert(locations.shipState(gx,gy)==6)
assert(globals["cycle_storm.sites.ship_locations"]:find(":steel_pending",1,true))
ship=dofile(root.."airship.lua");tick(1)
assert(at(273,233)==red and #EntityGetInRadiusWithTag(fx+404,fy+48,2,"nh_ship_safe")==0)
streamBounds=nil;tick(1);tick(1)
assert(at(86,179) and at(404,48) and not globals["cycle_storm.sites.ship_locations"]:find(":steel_pending",1,true))
assert(locations.shipState(gx,gy)==6 and #EntityGetWithTag("nh_steel_fleet_box")==3)
assert(locations.shipState(gx+4096,gy)==31 and locations.shipState(gx+8192,gy)==32)
print("Transport and steel formation placement, loot, retirement, old saves and radar passed.")
