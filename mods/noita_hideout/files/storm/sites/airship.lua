local M={}
local root="mods/noita_hideout/files/storm/sites/"
local locations=dofile(root.."locations.lua")
local cabin=dofile("mods/noita_hideout/files/travel/cabin.lua")
local prefix="cycle_storm.sites.ship_"
local holds={
    {file="ship_safe",sprite="safe_lv2_sprite.xml",loot={"improved_supply_pack","advanced_supply_pack","tactical_medkit","loot_case"}},
    {file="ship_cache",sprite="supply_safe_sprite.xml",loot={"supply_pack","improved_supply_pack","shield_charger","ammo_pack"}},
}
-- All offsets are relative to the material scene's top left. Both layouts
-- save the mooring at ground level as their navigation/retirement record.
local transport={geometry=locations.ship,scene="ship",solids=dofile(root.."ship_solids.lua"),
    guards={{"shotgunner_weak",43,65},{"scavenger_smg",86,65},{"shotgunner",117,65}}}
local steel={kind="steel",geometry=locations.steelFleet,scene="steel_fleet",solids=dofile(root.."steel_fleet_solids.lua"),
    guards={{"shotgunner_weak",122,224},{"scavenger_smg",219,224},{"shotgunner",310,170},{"scavenger_smg",149,170}}}
local lastRound

local function setBoxFrame(box,hold,frameName)
    local sprite=EntityGetFirstComponentIncludingDisabled(box,"SpriteComponent")
    if not sprite then return end
    if not EntityHasTag(box,"nh_ship_box_art") then
        -- Saved boxes have the pivot of the old standalone PNG on the component.
        -- Both new frames use the common pivot in the sprite definition.
        ComponentSetValue2(sprite,"image_file",root..hold.sprite)
        ComponentSetValue2(sprite,"offset_x",0)
        ComponentSetValue2(sprite,"offset_y",0)
        ComponentSetValue2(sprite,"has_special_scale",true)
        ComponentSetValue2(sprite,"special_scale_x",0.5)
        ComponentSetValue2(sprite,"special_scale_y",0.5)
        EntityAddTag(box,"nh_ship_box_art")
    end
    ComponentSetValue2(sprite,"rect_animation",frameName)
    ComponentSetValue2(sprite,"next_rect_animation",frameName)
    EntityRefreshSprite(box,sprite)
end

local function berthTag(left,ground)
    return string.format("nh_ship_berth_%d_%d",left,ground)
end

local function claimed(state,index)
    return math.floor(state/2^(index-1))%2==1
end

local function probe(layout,left,py)
    local g=layout.geometry
    local x=left+g.anchorX
    if not DoesWorldExistAt(x-8,py-80,x+8,py+114) then return end
    local hit,_,ground=RaytraceSurfaces(x,py-80,x,py+110)
    if not hit then return end
    ground=math.floor(ground)
    local top=ground-g.groundY
    if cabin.overlaps(left,top,left+g.width,ground+4,320) then return end
    if not DoesWorldExistAt(left-8,top-5,left+g.width+8,ground+6) then return end
    if GameGetSkyVisibility(x,ground-12)<0.5 then return end
    if locations.shipOverlaps(left-260,top-32,left+g.width+260,ground+32) then return end
    local radius=layout==steel and math.sqrt(g.width^2+g.height^2)/2+48 or 165
    local centerY=layout==steel and top+g.height/2 or ground-60
    for _,tag in ipairs({"cycle_storm_well","cycle_storm_rig","nh_home_terminal","nh_landmark_terminal","nh_remote_station"}) do
        if #(EntityGetInRadiusWithTag(left+g.width/2,centerY,radius,tag) or {})>0 then return end
    end
    -- Three points support the anchor. Reject water above the soil, ledges
    -- and a tree or hillside crossing the cabins or the boarding route.
    for dx=-8,8,8 do
        local floorHit,_,y=RaytracePlatforms(x+dx,ground-7,x+dx,ground+5)
        if not floorHit or math.abs(y-ground)>4 then return end
        if RaytraceSurfacesAndLiquiform(x+dx,ground-18,x+dx,ground-6) then return end
    end
    for dx=0,g.width-1,4 do
        local bottom=top
        for _,part in ipairs(g.parts) do
            if dx>=part[1]-2 and dx<=part[3]+2 then bottom=math.max(bottom,top+part[4]) end
        end
        if bottom>top and RaytraceSurfacesAndLiquiform(left+dx,top,left+dx,math.min(bottom,ground-6)) then return end
    end
    return ground
end

local function spawnBox(layout,index,left,top)
    local point=layout.geometry.boxes[index]
    local id=EntityLoad(root..point.file..".xml",left+point.x,top+point.y)
    if id and id~=0 and layout==steel then EntityAddTag(id,"nh_steel_fleet_box") end
    return id
end

local function place(layout,left,ground)
    local g=layout.geometry
    local top=ground-g.groundY
    local tag=berthTag(left,ground)
    local spawned={}
    local function stage(id)
        if not id or id==0 then
            for _,e in ipairs(spawned) do EntityKill(e) end
            return false
        end
        spawned[#spawned+1]=id
        EntityAddTag(id,tag)
        return true
    end
    for i in ipairs(g.boxes) do
        if not stage(spawnBox(layout,i,left,top)) then return end
    end
    for _,guard in ipairs(layout.guards) do
        if not stage(EntityLoad("data/entities/animals/"..guard[1]..".xml",left+guard[2],top+guard[3])) then return end
    end
    if not stage(EntityLoad(root.."mooring_light.xml",left+g.anchorX,ground-12)) then return end
    if layout==steel and not stage(EntityLoad(root.."mooring_light.xml",left+162,top+326)) then return end
    local bg=root..layout.scene.."_background.png"
    LoadPixelScene(root..layout.scene.."_materials.png",layout==steel and bg or "",left,top,bg,true,layout==steel,{},50,true)
    locations.setShip(left+g.anchorX,ground,0,layout.kind)
    return true
end

local function startRound(round)
    if GlobalsGetValue(prefix.."round","")==round then return end
    locations.each("ship",function(x,y,state,kind)
        local g=kind=="steel" and steel.geometry or transport.geometry
        if state==g.empty then locations.setShip(x,y,g.retiring) end
    end)
    GlobalsSetValue(prefix.."remaining","3")
    GlobalsSetValue(prefix.."round",round)
end

local function retireShip(layout,x,ground)
    local g=layout.geometry
    local left,top=x-g.anchorX,ground-g.groundY
    local air=CellFactory_GetType("air")
    for material,squares in pairs(layout.solids) do
        local source=CellFactory_GetType(material)
        for _,square in ipairs(squares) do
            -- The native converter includes both endpoints and clips tall rectangles.
            local extent=square[3]-1
            ConvertMaterialOnAreaInstantly(left+square[1],top+square[2],extent,extent,source,air,false,false)
        end
    end
    RemovePixelSceneBackgroundSprite(root..layout.scene.."_background.png",left,top)
    local tag=berthTag(left,ground)
    for _,e in ipairs(EntityGetWithTag(tag) or {}) do
        local ex,ey=EntityGetTransform(e)
        if ex>=left-8 and ex<=left+g.width+8 and ey>=top-8 and ey<=ground+6 then EntityKill(e)
        else EntityRemoveTag(e,tag) end
    end
    locations.setShip(x,ground,nil)
end

local function restoreBox(layout,index,left,top)
    local point=layout.geometry.boxes[index]
    local tag=point.file=="ship_cache" and "nh_ship_cache" or "nh_ship_safe"
    if #(EntityGetInRadiusWithTag(left+point.x,top+point.y,4,tag) or {})>0 then return true end
    local id=spawnBox(layout,index,left,top)
    if not id or id==0 then return false end
    EntityAddTag(id,berthTag(left,top+layout.geometry.groundY))
    return true
end

local function serviceBerths(px,py,cx,cy,cw,ch,inStorm)
    local pending,retired=false,false
    locations.each("ship",function(x,y,state,kind,refit)
        local layout=kind=="steel" and steel or transport
        local g=layout.geometry
        local left,top=x-g.anchorX,y-g.groundY
        local visible=cx+cw>=left-12 and cx<=left+g.width+12 and cy+ch>=top-12 and cy<=y+16
        if state==g.empty then return end
        if refit and state<g.empty then
            -- On an existing, still-active fleet, add each new safe as its room
            -- streams in. Preserve the pending upgrade across claims and reloads.
            local ready=true
            for i=3,#g.boxes do
                if not claimed(state,i) then
                    local sx,sy=left+g.boxes[i].x,top+g.boxes[i].y
                    if not DoesWorldExistAt(sx-16,sy-24,sx+16,sy+4) or not restoreBox(layout,i,left,top) then ready=false end
                end
            end
            if ready then locations.setShip(x,y,state,kind) end
        end
        if not DoesWorldExistAt(left-8,top-8,left+g.width+8,y+6) then
            if visible and state==g.retiring then pending=true end
            return
        end
        if state==g.retiring then
            pending=true
            if inStorm and not retired and not locations.nearShipStructure(x,y,px,py,kind) then
                retireShip(layout,x,y)
                retired=true
            end
        else
            -- If another effect removed an unopened box, restore that box alone.
            if visible or locations.nearShipStructure(x,y,px,py,kind) then return end
            for i in ipairs(g.boxes) do
                if not claimed(state,i) then restoreBox(layout,i,left,top) end
            end
        end
    end)
    return pending
end

function M.service(phase,age)
    local frame=GameGetFrameNum()
    local inStorm=phase==4
    if inStorm then
        local round=tostring(frame-age)
        if lastRound~=round then startRound(round); lastRound=round end
    else
        lastRound=nil
    end
    if frame%30~=0 then return end
    if frame%120==0 then
        for _,hold in ipairs(holds) do
            for _,box in ipairs(EntityGetWithTag("nh_"..hold.file) or {}) do
                if not EntityHasTag(box,"nh_ship_box_art") then
                    local interact=EntityGetFirstComponentIncludingDisabled(box,"InteractableComponent")
                    setBoxFrame(box,hold,interact and "closed" or "open")
                end
            end
        end
    end
    local player=(EntityGetWithTag("player_unit") or {})[1]
    if not player then return end
    local px,py=EntityGetTransform(player)
    local cx,cy,cw,ch=GameGetCameraBounds()
    return serviceBerths(px,py,cx,cy,cw,ch,inStorm)
end

local function tryArrival(layout,px,py,frame,first)
    local cx,cy,cw,ch=GameGetCameraBounds()
    local g=layout.geometry
    -- Align the low boarding craft with the edge of the screen. A high hull
    -- may extend over the camera horizontally while remaining above it.
    local attempts=layout==steel and 3 or 2
    for i=0,attempts-1 do
        local gap=16+ProceduralRandomi(frame+i,py,0,layout==steel and 80 or 36)
        local rightSide=i<2 and (first+i)%2==0
        local boardingRight=layout==steel and (i==2 and 300 or 168) or g.width
        local left=math.floor(rightSide and cx+cw+gap or cx-gap-boardingRight)
        local ground=probe(layout,left,math.floor(py))
        if ground then
            local top=ground-g.groundY
            local clear=not locations.nearShipStructure(left+g.anchorX,ground,px,py,layout.kind)
            for _,part in ipairs(g.parts) do
                if left+part[1]<=cx+cw and left+part[3]>=cx and top+part[2]<=cy+ch and top+part[4]>=cy then clear=false end
            end
            if clear and place(layout,left,ground) then return true end
        end
    end
end

function M.arrive()
    local frame=GameGetFrameNum()
    if frame%60~=30 then return end
    local remaining=tonumber(GlobalsGetValue(prefix.."remaining","0")) or 0
    if remaining<=0 then return end
    local player=(EntityGetWithTag("player_unit") or {})[1]
    if not player then return end
    local px,py=EntityGetTransform(player)
    if GameGetSkyVisibility(px,py)<0.35 then return end
    local first=ProceduralRandomi(frame,px,0,1)
    local round=GlobalsGetValue(prefix.."round","")
    local fleetDue=GlobalsGetValue(prefix.."steel_round","")~=round
    local message="$nh_storm_ship_desc"
    if fleetDue and tryArrival(steel,px,py,frame,first) then
        GlobalsSetValue(prefix.."steel_round",round)
        message="$nh_storm_steel_fleet_desc"
    elseif (fleetDue and remaining==1) or not tryArrival(transport,px,py,frame,first) then
        return
    end
    GlobalsSetValue(prefix.."remaining",tostring(remaining-1))
    if remaining==3 or message=="$nh_storm_steel_fleet_desc" then
        GamePrintImportant("$nh_storm_ship_arrives",message,"data/ui_gfx/decorations_biome_modifier/booby_trapped.png")
    else
        GamePrint(GameTextGetTranslatedOrNot(message))
    end
end

function M.open(player,box)
    if not EntityHasTag(player,"player_unit") then return end
    local interact=EntityGetFirstComponentIncludingDisabled(box,"InteractableComponent")
    if not interact then return end
    local hold=EntityHasTag(box,"nh_ship_cache") and holds[2] or holds[1]
    local layout=EntityHasTag(box,"nh_steel_fleet_box") and steel or transport
    local x,y=EntityGetTransform(box)
    local g=layout.geometry
    local index=hold==holds[2] and 2 or 1
    if layout==steel then
        -- Existing and newly placed fixtures carry the ground berth tag. It
        -- disambiguates otherwise identical safes without changing old entities.
        index=nil
        for i,slot in ipairs(g.boxes) do
            if EntityHasTag(box,berthTag(x-slot.x,y-slot.y+g.groundY)) then index=i; break end
        end
        if not index then return end
    end
    local point=g.boxes[index]
    local anchor,ground=x-point.x+g.anchorX,y-point.y+g.groundY
    local state=locations.shipState(anchor,ground)
    if not state or state>=g.empty or claimed(state,index) then return end
    local round=tonumber(GlobalsGetValue(prefix.."round","0")) or 0
    local prize=hold.loot[ProceduralRandomi(x+round,y,1,#hold.loot)]
    local gold
    if hold==holds[1] then
        gold=EntityLoad("data/entities/items/pickup/goldnugget_50.xml",x-6,y-8)
        if not gold or gold==0 then return end
    end
    local item=EntityLoad("mods/noita_hideout/files/items/"..prize..".xml",x+7,y-8)
    if not item or item==0 then
        if gold then EntityKill(gold) end
        return
    end
    locations.setShip(anchor,ground,state+2^(index-1))
    EntityRemoveComponent(box,interact)
    setBoxFrame(box,hold,"open")
end
return M
