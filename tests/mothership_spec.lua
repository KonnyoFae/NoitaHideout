local root="mods/noita_hideout/files/travel/"
local cabin=dofile(root.."cabin.lua")
local travel=dofile(root.."network.lua")
local hud=dofile(root.."hud.lua")
local ix,iy=cabin.point(cabin.infirmary)
local cx,cy=cabin.point(cabin.terminal)
local gateX,gateY=cabin.point(cabin.gate)
local hx,hy=0,-6
local frame,keys,world,entities,notices=0,{},{},{},{}
local streamed,obstructed,painted=true,false,0
local inventory=false
function GameIsInventoryOpen() return inventory end
function GetParallelWorldPosition(x) return math.floor(x/35840+0.5),0 end
function BiomeMapGetSize() return 70,48 end
function BiomeMapGetName() return "$biome_holymountain" end
local cleared,removed=0,0
local function entity(x,y,tag)
    entities[#entities+1]={x=x,y=y,tag=tag}
    return #entities
end
local player=entity(hx,hy,"player_unit")
entity(10,-7,"nh_home_terminal")
function GameGetFrameNum() return frame end
local ng,cycleReads=0,0
function SessionNumbersGetValue(key)
    assert(key=="NEW_GAME_PLUS_COUNT",key)
    cycleReads=cycleReads+1
    return tostring(ng)
end
function GlobalsGetValue(k,d) return world[k] or d end
function GlobalsSetValue(k,v) world[k]=v end
function GameTextGetTranslatedOrNot(k) return k end
function GamePrint(s) notices[#notices+1]=s end
function EntityGetTransform(i) return entities[i].x,entities[i].y end
function EntitySetTransform(i,x,y) entities[i].x,entities[i].y=x,y end
function EntityGetWithTag(t)
    local r={}
    for i,e in ipairs(entities) do if not e.dead and e.tag==t then r[#r+1]=i end end
    return r
end
function EntityGetInRadiusWithTag(x,y,r,t)
    local near={}
    for _,i in ipairs(EntityGetWithTag(t)) do
        local e=entities[i]
        if (e.x-x)^2+(e.y-y)^2<=r*r then near[#near+1]=i end
    end
    return near
end
function EntityGetAllChildren(_,tag) return EntityGetWithTag(tag) end
function EntityGetFirstComponentIncludingDisabled() end
function EntityAddChild() end
function EntityKill(i) entities[i].dead=true end
function EntityHasTag(i,t) return entities[i].tag==t end
function EntityLoad(path,x,y)
    local tag=({[root.."console.xml"]="nh_travel_console",[root.."gate.xml"]="nh_travel_gate",
        [root.."transit_protection.xml"]="nh_transit_protection"})[path]
    assert(tag,path)
    return entity(x,y,tag)
end
function ModSettingGet() return "10" end
function InputIsKeyDown(k) return keys[k] end
function InputIsKeyJustDown(k) return keys[k] end
function DoesWorldExistAt(x,y) return y>-20000 or streamed end
function RemovePixelSceneBackgroundSprite(bg,x,y)
    assert(bg==cabin.background and ((x==164 and y==-26480) or (x==10 and y==-26756)
        or (x==cabin.left and y==cabin.top)))
    removed=removed+1
end
function LoadPixelScene(mask,colors,x,y,bg,skipBiome,skipEdges,mapping,z,repeatable)
    if mask==root.."prototype_clear.png" or mask==root.."three_deck_clear.png" then
        assert(colors=="" and bg=="")
        assert((mask==root.."prototype_clear.png" and x==164 and y==-26480)
            or (mask==root.."three_deck_clear.png" and x==10 and y==-26756))
        cleared=cleared+1
        return
    end
    assert(mask==cabin.material and colors==cabin.background and bg==colors and x==cabin.left and y==cabin.top)
    assert(skipBiome and skipEdges and next(mapping)==nil and z==50 and repeatable)
    painted=painted+1
end
function RaytracePlatforms(x,y,_,bottom)
    local floor=0
    if y<-20000 then
        floor=y<=cabin.top+60 and cabin.top+60 or cabin.top+144
    end
    if x>600 then floor=500 end
    return y<=floor and bottom>=floor,x,floor
end
function RaytraceSurfacesAndLiquiform(x) return obstructed and x>600 end
local function tick(block)
    frame=frame+1
    travel.update(player,hx,hy,block or false)
end
local function position(x,y) EntitySetTransform(player,x,y) end
local function key(k)
    keys[k]=true; tick(); keys[k]=nil
end
local function console()
    position(cx,cy-6)
    inventory=true
    tick(true); return assert(travel.view().rows)
end
local function choose(i)
    travel.choose(player,i)
    inventory=false
end
local function enter()
    tick()
    local e=assert(EntityGetWithTag("nh_travel_gate")[1])
    position(EntityGetTransform(e)); tick()
    assert(world["nh_travel.trip"]~="")
end
local function hold()
    keys[10]=true
    for _=1,37 do tick() end
    keys[10]=nil; tick()
end
-- A short press, an inventory-held key and a distant player never open a gate.
key(10)
keys[10]=true; for _=1,40 do tick(true) end; keys[10]=nil
assert(#EntityGetWithTag("nh_travel_gate")==0)
hold()
streamed=false; enter(); tick()
assert(not travel.inCabin(player) and painted==0)
travel=dofile(root.."network.lua") -- continue in the middle of streaming
streamed=true; tick(); tick()
assert(travel.inCabin(player) and painted==1 and world["nh_travel.trip"]=="" and world["nh_travel.gate"]=="")
local list=console()
assert(#list==1 and list[1].kind=="home")
choose(1); enter(); tick()
assert(not travel.inCabin(player) and math.abs(entities[player].x-10)<30)
local holy=entity(900,493,"noita_hideout_mountain_storage")
position(900,493)
for _=1,25 do tick() end
assert(world["nh_travel.stations"]=="900,493;")
entity(-700,-7,"nh_remote_station"); position(-700,-6); hold(); enter(); tick()
assert(travel.inCabin(player) and painted==1 and #console()==2)
assert(travel.view().rows[2].x==900)
choose(2)
-- Updating a portal at the same deck before boarding keeps one gate.
console(); choose(1); console(); choose(2)
assert(#EntityGetWithTag("nh_travel_gate")==1)
obstructed=true; enter(); tick(); tick()
assert(travel.inCabin(player) and world["nh_travel.trip"]=="" and world["nh_travel.gate"]~="")
obstructed=false; position(cx,cy-6); tick(); position(gateX,gateY); tick(); tick()
assert(math.abs(entities[player].x-entities[holy].x)<35 and world["nh_travel.gate"]=="")
-- Rescue uses the same landing and bounded fallback, without changing the stations.
streamed=false; travel.rescue(player,hx,hy)
for _=1,244 do tick() end
assert(math.abs(entities[player].x-hx)<15 and world["nh_travel.trip"]=="")
assert(notices[#notices]=="$nh_travel_rescue_fallback")
assert(world["nh_travel.stations"]=="900,493;")
-- An occupied 0.42.0 room may also have an open outbound gate and registered stations.
streamed=true
for _,id in ipairs(EntityGetWithTag("nh_travel_console")) do EntityKill(id) end
local oldConsole=entity(264,-26413,"nh_travel_console")
local oldGate=entity(318,-26424,"nh_travel_gate")
world["nh_travel.built"]="1"
world["nh_travel.gate"]="318,-26424,home,0,-6"
position(245,-26418)
travel=dofile(root.."network.lua")
for _=1,45 do tick() end
assert(travel.inCabin(player) and entities[player].x==ix and entities[player].y==cabin.top+60-6)
assert(painted==2 and cleared==1 and removed==1 and entities[oldConsole].dead and entities[oldGate].dead,
    ("prototype refit: scenes %d/%d/%d, console %s, gate %s (%s)"):format(
        painted,cleared,removed,tostring(entities[oldConsole].dead),tostring(entities[oldGate].dead),world["nh_travel.gate"]))
assert(#EntityGetWithTag("nh_travel_console")==1 and #EntityGetWithTag("nh_travel_gate")==1)
assert(world["nh_travel.gate"]==gateX..","..gateY..",home,0,-6" and world["nh_travel.stations"]=="900,493;")
-- Replace the later three-deck ship as well, including a gate to an unlocked station.
for _,id in ipairs(EntityGetWithTag("nh_travel_console")) do EntityKill(id) end
local bridge=entity(192,-26549,"nh_travel_console")
local oldHologram=entity(309,-26560,"nh_travel_gate")
world["nh_travel.built"]="2"
world["nh_travel.gate"]="309,-26560,mountain,900,493"
position(340,-26668)
travel=dofile(root.."network.lua")
for _=1,45 do tick() end
assert(painted==3 and cleared==2 and removed==2 and entities[bridge].dead and entities[oldHologram].dead)
assert(entities[player].x==ix and entities[player].y==cabin.top+54)
assert(#EntityGetWithTag("nh_travel_console")==1 and #EntityGetWithTag("nh_travel_gate")==1)
assert(world["nh_travel.gate"]==gateX..","..gateY..",mountain,900,493")
-- Walking down the hatch and up to the control screen must not board the open gate.
position(cabin.left+213,cabin.top+83); tick(); assert(travel.inCabin(player))
position(cx,cy-6); tick(); assert(world["nh_travel.trip"]=="")
position(cabin.left+315,cabin.top+135); assert(not travel.inCabin(player))
position(gateX,gateY); tick(); tick()
assert(math.abs(entities[player].x-entities[holy].x)<35 and world["nh_travel.gate"]=="")
-- A storm restores terrain and a destroyed console once; a live gate and routes survive.
console(); choose(1)
local activeGate=world["nh_travel.gate"]
assert(activeGate~="")
position(ix,cabin.top+54)
EntityKill(EntityGetWithTag("nh_travel_console")[1])
while frame%15~=14 do tick() end
local before=painted
travel.scheduleRepair(0); tick()
assert(painted==before+1 and world["nh_travel.placing"]~="")
travel=dofile(root.."network.lua")
for _=1,65 do travel.scheduleRepair(0); tick() end
assert(painted==before+1 and world["nh_travel.repaired_round"]=="0")
assert(entities[player].x==ix and entities[player].y==cabin.top+54)
assert(world["nh_travel.gate"]==activeGate and world["nh_travel.stations"]=="900,493;")
assert(#EntityGetWithTag("nh_travel_gate")==1 and #EntityGetWithTag("nh_travel_console")==1)
-- Storms missed away from the ship coalesce. A player in a breach is moved before it seals.
position(hx,hy); streamed=false
travel.scheduleRepair(72000)
for _=1,64 do tick() end
travel.scheduleRepair(144000)
travel=dofile(root.."network.lua")
for _=1,64 do tick() end
assert(painted==before+1 and world["nh_travel.repaired_round"]=="0")
streamed=true; position(cabin.left+150,cabin.top+8)
for _=1,46 do tick() end
assert(painted==before+2 and world["nh_travel.repaired_round"]=="144000")
assert(entities[player].x==ix and entities[player].y==iy and world["nh_travel.gate"]==activeGate)
assert(#EntityGetWithTag("nh_travel_console")==1 and #EntityGetWithTag("nh_travel_gate")==1)
local labels={}
function GuiZSetForNextWidget() end
function GuiColorSetForNextWidget() end
function GuiGetTextDimensions(_,text) return #text*3,9 end
function GuiImage() end
function GuiText(_,x,y,text) labels[text]=y end
local function zh(a,b) return a end
hud(1,{key="G",percent=50},400,230,zh)
assert(labels["长按 G  开启返航门  50%"]<210)
-- Each parallel altar registers independently, including those at the same depth.
entity(-35840,493,"noita_hideout_mountain_storage"); position(-35840,493); tick()
entity(35840,493,"noita_hideout_mountain_storage"); position(35840,493); tick()
local routes=console()
local groups=travel.view().groups
assert(#routes==4 and #groups==3 and groups[1].world==0 and #groups[1].routes==2)
assert(groups[2].world==1 and groups[3].world==-1 and groups[2].routes[1]==routes[4])
inventory=false; travel.choose(player,4); assert(world["nh_travel.gate"]==activeGate)
inventory=true; position(ix,iy); travel.choose(player,4); assert(world["nh_travel.gate"]==activeGate)
console(); choose(4); tick()
assert(travel.view().gateKind=="mountain" and travel.view().gateX==35840)
local registered=world["nh_travel.stations"]
-- Start the outbound trip, then let vanilla replace the world before the
-- next maintenance tick. An old trip must never move the player in NG+.
while frame%15>=13 do tick(true) end
inventory=false
position(gateX,gateY); tick()
assert(world["nh_travel.trip"]~="" and (frame+1)%15~=0)
ng=1
position(-1000,0); tick()
local nx,ny=EntityGetTransform(player)
assert(nx==-1000 and ny==0 and world["nh_travel.trip"]=="" and world["nh_travel.gate"]=="")
assert(not travel.inCabin(player) and travel.view()==nil)
assert(not world["nh_travel.ng1.stations"] and world["nh_travel.stations"]==registered)
-- A field shortcut cannot open a boarding gate away from a terminal.
-- Idle exploration only polls the vanilla NG+ counter on maintenance ticks.
cycleReads=0
keys[10]=true
for _=1,60 do tick() end
keys[10]=nil
assert(cycleReads==4 and not world["nh_travel.ng1.gate"] and travel.view()==nil)
-- Actual biome-map neighbors determine each name, even for a shuffled layer.
do
    local names=dofile(root.."routes.lua")
    local cells={[1]="coalmine",[3]="excavationsite",[4]="excavationsite",[6]="snowcave",[8]="snowcave",[10]="snowcastle",
        [11]="snowcastle",[13]="rainforest",[15]="rainforest",[17]="vault",[19]="vault",[21]="crypt",[24]="boss_arena"}
    function BiomeMapGetName(x,y)
        if x==-35840 and y==512*3 then return "$biome_rainforest" end
        return "$biome_"..(cells[math.floor(y/512)] or "holymountain")
    end
    local g=names.collect("0,12288;0,10240;0,8192;0,6144;0,4608;0,2560;0,1024;-35840,1024;71680,-3072;",0,0).groups
    local expected={"煤矿矿坑入口圣山","积雪深渊入口圣山","席西基地入口圣山","地下丛林入口圣山","避难所入口圣山","艺之神殿入口圣山","实验室入口圣山"}
    for i,name in ipairs(expected) do assert(names.label(g[1].routes[i+1],zh)==name) end
    assert(g[2].world==-1 and g[3].world==2 and names.label(g[3].routes[1],zh)=="高空圣山")
    local name,detail=names.label(g[2].routes[1],zh)
    assert(name=="地下丛林入口圣山" and detail=="来自矿场")
end
print("Mothership: first visit, run-local registration, remote recall, one-way gate replacement, reload, blocked landing and rescue fallback passed.")
