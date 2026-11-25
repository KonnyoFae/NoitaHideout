local M = {}
local root = "mods/noita_hideout/files/storm/sites/"
local locations = dofile(root.."locations.lua")
local items = "mods/noita_hideout/files/items/"
local idle_key = "cycle_storm.idle_rigs"
local prefix = "cycle_storm.sites."
local running_rig_key = prefix.."running_rig_until"
local rig_life, well_life = 300*60, 600*60
local rig_until, well_until
local lastForecast
local tower_origin_x, tower_origin_y = 64, 256
-- Tank centers on the 128 x 256 GasTower canvas, from the top down.
local tanks = {{77,75}, {77,101}, {77,128}}
-- Towers already serialized with the prototype shell keep its three outlets.
local prototype_ports = {{-23,-10}, {19,-39}, {-15,-69}}
local rig_half_width, rig_spacing = 13, 68
local grow_frames = 45*60

local function field(entity,name)
    for _,c in ipairs(EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent") or {}) do
        if ComponentGetValue2(c,"name")==name then return c end
    end
end

local function get(entity,name)
    return ComponentGetValue2(field(entity,name),"value_int")
end

local function set(entity,name,value)
    ComponentSetValue2(field(entity,name),"value_int",value)
end

local function loaded(path,x,y)
    local e=EntityLoad(path,x,y)
    if e and e~=0 then return e end
end

function M.canTime(number)
    if number<=4 then return ({60,105,135,150})[number] end
    return 150+(number-4)*10
end

function M.rigProgress(e,frame)
    local started=get(e,"started")
    if started<0 then return false,0,0,0 end
    local count=get(e,"produced")
    if count>=19 then return true,1,0,count end
    local age=(frame-started)/60
    local last=count==0 and 0 or M.canTime(count)
    local due=M.canTime(count+1)
    return true,math.max(0,math.min(1,(age-last)/(due-last))),math.max(0,math.ceil(due-age)),count
end

function M.wellProgress(e,frame)
    local started=get(e,"started")
    if started<0 then return end
    local remaining=math.max(0,math.min(well_life,started+well_life-frame))
    local tower=EntityGetFirstComponentIncludingDisabled(e,"SpriteComponent","tower_back")
    return remaining/well_life,math.ceil(remaining/60),tower and 231 or 94
end

-- Station roots are fixed in world space. Keep position and expiry across chunk
-- unloading and save/reload; a streamed entity may return with a different ID.
local function trackSites(oil,frame,entities)
    local key=prefix..(oil and "rig_locations" or "well_locations")
    local old=GlobalsGetValue(key,"")
    local seen,records={},{}
    local runningUntil,lostIdle,hasIdle=0,0,false
    local expiring=false
    local function keep(pos,expires)
        records[#records+1]=pos..","..expires
        if expires<0 then hasIdle=true else runningUntil=math.max(runningUntil,expires) end
    end
    for _,e in ipairs(entities) do
        local x,y=EntityGetTransform(e)
        local pos=string.format("%d,%d",math.floor(x),math.floor(y))
        seen[pos]=true
        local started=get(e,"started")
        if started>=0 then
            local expires=started+(oil and rig_life or well_life)
            if expires>frame then keep(pos,expires) else expiring=true end
        elseif oil then keep(pos,-1) end
    end
    for x,y,deadline in old:gmatch("(-?%d+),(-?%d+),(-?%d+)") do
        local pos,expires=x..","..y,tonumber(deadline)
        if not seen[pos] and (expires<0 or expires>frame) then
            x,y=tonumber(x),tonumber(y)
            if not DoesWorldExistAt(x-32,y-32,x+32,y+32) then keep(pos,expires)
            elseif oil and expires<0 then lostIdle=lostIdle+1 end
        end
    end
    table.sort(records)
    local saved=table.concat(records,";")
    if saved~=old then GlobalsSetValue(key,saved) end
    if oil then
        -- Activation runs in an entity VM; publish the latest working rig's
        -- deadline independently of idle rigs, even when its chunk unloads.
        local deadline=tostring(runningUntil)
        if GlobalsGetValue(running_rig_key,"0")~=deadline then GlobalsSetValue(running_rig_key,deadline) end
        local idle=tonumber(GlobalsGetValue(idle_key,"0")) or 0
        if lostIdle>0 then
            idle=math.max(0,idle-lostIdle)
            GlobalsSetValue(idle_key,tostring(idle))
        end
        -- Old saves already count idle rigs, even outside the loaded world.
        if idle>0 then hasIdle=true end
    end
    return hasIdle and math.huge or runningUntil,expiring
end

function M.available()
    local frame=GameGetFrameNum()
    local well=(well_until or 0)>frame
    return well,(rig_until or 0)>frame,
        GlobalsGetValue(prefix.."winter","")=="pending",GlobalsGetValue(prefix.."desert","")=="pending",
        well,(tonumber(GlobalsGetValue(running_rig_key,"0")) or 0)>frame
end

local function fitRig(e)
    if EntityGetFirstComponentIncludingDisabled(e,"SpriteComponent","cycle_storm_rig_body") then return end
    -- Old saves serialized both the full-size sprite and the text-only meter.
    for _,c in ipairs(EntityGetComponentIncludingDisabled(e,"SpriteComponent") or {}) do
        local image=ComponentGetValue2(c,"image_file")
        if image==root.."oil_drill.png" or image=="mods/cycle_storm/files/sites/oil_drill.png"
            or image=="data/props_gfx/excavationsite_machine_3b.png"
            or ComponentHasTag(c,"production_meter") then EntityRemoveComponent(e,c) end
    end
    EntityLoadToEntity(root.."rig_body.xml",e)
end

-- Streamed entities in existing runs retain the standalone mod's component paths.
local function restoreSites(tag,oil)
    local legacy="mods/cycle_storm/files/sites/"
    local entities=EntityGetWithTag(tag) or {}
    for _,e in ipairs(entities) do
        if not EntityHasTag(e,"nh_storm_site") then
            local tick=false
            for _,c in ipairs(EntityGetComponentIncludingDisabled(e,"LuaComponent") or {}) do
                local source=ComponentGetValue2(c,"script_source_file")
                if source==legacy.."tick.lua" then ComponentSetValue2(c,"script_source_file",root.."tick.lua"); tick=true end
                if source==root.."tick.lua" then tick=true end
                if ComponentGetValue2(c,"script_interacting")==legacy.."activate.lua" then
                    ComponentSetValue2(c,"script_interacting",root.."activate.lua")
                end
            end
            if not tick then EntityAddComponent2(e,"LuaComponent",{script_source_file=root.."tick.lua",execute_every_n_frame=15}) end
            if oil then
                fitRig(e)
            else
                local back=EntityGetFirstComponentIncludingDisabled(e,"SpriteComponent","tower_back")
                if back then
                    ComponentSetValue2(back,"image_file",root.."tower_back.png")
                    EntityRefreshSprite(e,back)
                end
                for _,child in ipairs(EntityGetAllChildren(e) or {}) do
                    local shape=EntityGetFirstComponentIncludingDisabled(child,"PhysicsImageShapeComponent")
                    if shape then
                        local path=ComponentGetValue2(shape,"image_file")
                        if path==legacy.."tower_structure.png" or path==legacy.."tower_collision.png" then
                            ComponentSetValue2(shape,"image_file",root..path:sub(#legacy+1))
                        end
                    end
                    if EntityHasTag(child,"storm_ripe_crystal") then
                        for _,c in ipairs(EntityGetComponentIncludingDisabled(child,"LuaComponent") or {}) do
                            if ComponentGetValue2(c,"script_damage_received")==legacy.."shatter.lua" then
                                ComponentSetValue2(c,"script_damage_received",root.."shatter.lua")
                            end
                        end
                    end
                end
            end
            EntityAddTag(e,"nh_storm_site")
        end
    end
    return entities
end

local function startDrilling(e)
    if not EntityGetFirstComponentIncludingDisabled(e,"AudioLoopComponent","cycle_storm_drilling") then
        EntityLoadToEntity(root.."rig_drilling.xml",e)
    end
end

local function rare(x,y,started,age,life,salt)
    local threshold=10+math.floor(90*math.min(1,age/life))
    return ProceduralRandomi(x+started+salt*137,y+salt*769,1,10000)<=threshold
end

function M.activate(player,rig)
    if not EntityHasTag(player,"player_unit") or get(rig,"started")>=0 then return end
    set(rig,"started",GameGetFrameNum())
    startDrilling(rig)
    local component=EntityGetFirstComponentIncludingDisabled(rig,"InteractableComponent")
    if component then EntityRemoveComponent(rig,component) end
    local n=tonumber(GlobalsGetValue(idle_key,"0")) or 0
    GlobalsSetValue(idle_key,tostring(math.max(0,n-1)))
    rig_until=trackSites(true,GameGetFrameNum(),EntityGetWithTag("cycle_storm_rig") or {})
end

local function spawnEnemies(kind,count,x,y,mark)
    for i=1,count do
        local side=(i+mark)%2==0 and 1 or -1
        local dx=side*ProceduralRandomi(x+mark+i,y+17,90,165)
        local sx=x+dx
        if DoesWorldExistAt(sx-6,y-63,sx+6,y+72) then
            local hit,_,sy=RaytraceSurfaces(sx,y-60,sx,y+70)
            if hit and not RaytraceSurfaces(sx,sy-22,sx,sy-2)
                and #(EntityGetInRadiusWithTag(sx,sy-7,48,"player_unit") or {})==0 then
                EntityLoad("data/entities/animals/"..kind..".xml",sx,sy-7)
            end
        end
    end
end

local function waves(e,oil,age,x,y)
    local interval=(oil and 60 or 180)*60
    local n=math.floor(age/interval)
    if n<=get(e,"wave") then return end
    set(e,"wave",n)
    -- Skip missed waves after the area streams back in.
    if age%interval>=60 or #(EntityGetInRadiusWithTag(x,y,450,"player_unit") or {})==0 then return end
    local mark=n*97+math.floor(x)
    if oil then
        spawnEnemies("goblin_bomb",ProceduralRandomi(mark,y,1,2),x,y,mark)
        spawnEnemies("miner_fire",ProceduralRandomi(mark+1,y,2,3),x,y,mark+17)
        if n==3 then spawnEnemies("firemage_weak",1,x,y,mark+29) end
    else
        spawnEnemies("shotgunner",ProceduralRandomi(mark,y,3,4),x,y,mark)
        spawnEnemies("miner",ProceduralRandomi(mark+1,y,4,6),x,y,mark+17)
        if n==3 then spawnEnemies("icemage",1,x,y,mark+29) end
    end
end

local function fillCans(e,x,y,started,age)
    local count=get(e,"produced")
    while count<19 and M.canTime(count+1)*60<=age do
        local nextCan=count+1
        local premium=rare(x,y,started,M.canTime(nextCan),300,nextCan)
        local kind=premium and "storm_mercury_pressure" or "storm_mercury"
        local sx,sy=x+16+nextCan%3,y-14
        -- Keep the whole can above the surface, even on a rising slope.
        for dx=-5,5,5 do
            local hit,_,floor=RaytraceSurfaces(sx+dx,y-38,sx+dx,y+8)
            if hit then sy=math.min(sy,floor-8) end
        end
        local can=loaded(items..kind..".xml",sx,sy)
        if not can then return false end
        count=nextCan
        set(e,"produced",count)
        EntityAddComponent2(can,"LuaComponent",{script_source_file=root.."eject_can.lua",execute_every_n_frame=1})
    end
    return true
end

-- Old saves serialize the original one-piece physics body. Only exchange an
-- existing frame, once its footprint is loaded and the player has stepped clear.
local function upgradeTowerFrame(e,x,y)
    if EntityHasTag(e,"nh_segmented_tower") then return end
    if not DoesWorldExistAt(x-53,y-231,x+53,y+1) then return end
    for _,child in ipairs(EntityGetAllChildren(e) or {}) do
        local shape=EntityGetFirstComponentIncludingDisabled(child,"PhysicsImageShapeComponent")
        if shape then
            local file=ComponentGetValue2(shape,"image_file")
            if file==root.."tower_structure.png" or file=="mods/cycle_storm/files/sites/tower_structure.png" then
                if #(EntityGetInRadiusWithTag(x,y-115,140,"player_unit") or {})>0 then return end
                local shell=loaded(root.."shell.xml",x-tower_origin_x,y-tower_origin_y)
                if not shell then return end
                EntityAddChild(e,shell)
                EntityKill(child)
                break
            end
        end
    end
    EntityAddTag(e,"nh_segmented_tower")
end

local function grow(e,x,y,started,frame)
    if not EntityHasTag(e,"nh_crystal_target_checked") then
        -- A mature crystal can stay in its port throughout a mod upgrade.
        for _,child in ipairs(EntityGetAllChildren(e) or {}) do
            if EntityHasTag(child,"storm_ripe_crystal") then
                EntityAddTag(child,"hittable")
                local hitbox=EntityGetFirstComponentIncludingDisabled(child,"HitboxComponent")
                if hitbox then
                    ComponentSetValue2(hitbox,"aabb_min_y",-8)
                    ComponentSetValue2(hitbox,"aabb_max_y",8)
                end
                if not EntityGetFirstComponentIncludingDisabled(child,"ParticleEmitterComponent","nh_ripe_glow") then
                    EntityLoadToEntity(root.."crystal_glow.xml",child)
                end
                local sprite=EntityGetFirstComponent(child,"SpriteComponent")
                if sprite then
                    local kind=get(child,"pure")==1 and "storm_mana_pure" or "storm_mana"
                    ComponentSetValue2(sprite,"image_file",items..kind..".png")
                    ComponentSetValue2(sprite,"offset_x",8)
                    ComponentSetValue2(sprite,"offset_y",8)
                    EntityRefreshSprite(child,sprite)
                end
            end
        end
        EntityAddTag(e,"nh_crystal_target_checked")
    end
    local tower=EntityGetFirstComponentIncludingDisabled(e,"SpriteComponent","tower_back")
    if tower then upgradeTowerFrame(e,x,y) end
    for i,pos in ipairs(tower and tanks or prototype_ports) do
        local dx,dy=pos[1],pos[2]
        if tower then dx,dy=dx-tower_origin_x,dy-tower_origin_y end
        local name="port"..i
        local due=get(e,name)
        if due==0 then
            due=started+grow_frames
            set(e,name,due)
        end
        local bud=EntityGetFirstComponentIncludingDisabled(e,"SpriteComponent",name.."_bud")
        if bud and due>frame then
            local scale=math.max(0.125,math.floor(8*(1-(due-frame)/grow_frames))/8)
            if ComponentGetValue2(bud,"special_scale_x")~=scale or not ComponentGetIsEnabled(bud)
                or ComponentGetValue2(bud,"image_file")~=items.."storm_mana.png" then
                ComponentSetValue2(bud,"image_file",items.."storm_mana.png")
                ComponentSetValue2(bud,"special_scale_x",scale)
                ComponentSetValue2(bud,"special_scale_y",scale)
                ComponentSetValue2(bud,"offset_x",8-dx/scale)
                ComponentSetValue2(bud,"offset_y",8-dy/scale)
                EntitySetComponentIsEnabled(e,bud,true)
                EntityRefreshSprite(e,bud)
            end
        end
        if due>0 and frame>=due then
            local crystal=loaded(root.."crystal.xml",x+dx,y+dy)
            if crystal then
                set(crystal,"port",i)
                if rare(x,y,started,due-started,600*60,i+due-started) then
                    set(crystal,"pure",1)
                    local sprite=EntityGetFirstComponent(crystal,"SpriteComponent")
                    ComponentSetValue2(sprite,"image_file",items.."storm_mana_pure.png")
                    EntityRefreshSprite(crystal,sprite)
                end
                EntityAddChild(e,crystal)
                set(e,name,-1)
                if bud then EntitySetComponentIsEnabled(e,bud,false) end
            end
        end
    end
end

function M.shatter(e)
    local i=get(e,"port")
    local well=EntityGetParent(e)
    if i<1 or not well or well==0 then return end
    local now=GameGetFrameNum()
    if now>=get(well,"started")+well_life then EntityKill(e); return end
    local x,y=EntityGetTransform(e)
    local pure=get(e,"pure")==1
    local kind=pure and "storm_mana_pure" or "storm_mana"
    local drops={}
    for j=1,2 do
        local drop=loaded(items..kind..".xml",x+(2*j-3)*4,y)
        if not drop then
            for _,id in ipairs(drops) do EntityKill(id) end
            return
        end
        drops[j]=drop
    end
    set(e,"port",0)
    set(well,"port"..i,now+grow_frames)
    for j,id in ipairs(drops) do PhysicsApplyForce(id,(2*j-3)*30,-40) end
    EntityLoad(root.."crystal_burst.xml",x,y)
    EntityKill(e)
end

function M.tick(e)
    local oil=EntityHasTag(e,"cycle_storm_rig")
    if oil then fitRig(e) end
    local started=get(e,"started")
    if started<0 then return end
    local now=GameGetFrameNum()
    local age=now-started
    local x,y=EntityGetTransform(e)
    if oil and not fillCans(e,x,y,started,math.min(age,rig_life)) then return end
    if age>=(oil and rig_life or well_life) then
        EntityLoad("data/entities/particles/dust_explosion.xml",x,y)
        for _,child in ipairs(EntityGetAllChildren(e) or {}) do EntityKill(child) end
        EntityKill(e)
        return
    end
    if oil then startDrilling(e) else grow(e,x,y,started,now) end
    waves(e,oil,age,x,y)
end

-- Probe the loaded surface outside the view, including the whole structure.
local function site(x,y,biome,halfWidth,height)
    if not DoesWorldExistAt(x,y-140,x,y+130) then return end
    local hit,_,ground=RaytraceSurfaces(x,y-140,x,y+130)
    if not hit or BiomeMapGetName(x,ground+4)~=biome or GameGetSkyVisibility(x,ground-16)<0.35 then return end
    if not DoesWorldExistAt(x-halfWidth,ground-height,x+halfWidth,ground+8) then return end
    if locations.shipOverlaps(x-halfWidth,ground-height,x+halfWidth,ground+8) then return end
    for i=0,4 do
        local sx=x-halfWidth+math.floor(i*halfWidth/2)
        if RaytraceSurfaces(sx,ground-height,sx,ground-3) then return end
        if not RaytraceSurfaces(sx,ground-3,sx,ground+8) then return end
    end
    return ground-1
end

local function place(biome,x,y)
    if biome=="$biome_desert" then
        local sites={}
        for i=1,3 do
            local sx=x+(i-2)*rig_spacing
            local sy=site(sx,y,biome,rig_half_width,26)
            if not sy then return false end
            sites[i]={sx,sy}
        end
        local rigs={}
        for _,p in ipairs(sites) do
            local e=loaded(root.."rig.xml",p[1],p[2])
            if not e then
                for _,id in ipairs(rigs) do EntityKill(id) end
                return false
            end
            rigs[#rigs+1]=e
        end
        GlobalsSetValue(idle_key,tostring(#rigs))
    else
        local sy=site(x,y,biome,53,231)
        if not sy then return false end
        local e=loaded(root.."well.xml",x,sy)
        if not e then return false end
        local shell=loaded(root.."shell.xml",x-tower_origin_x,sy-tower_origin_y)
        if not shell then EntityKill(e); return false end
        EntityAddChild(e,shell)
        set(e,"started",GameGetFrameNum())
    end
    return true
end

local function confirmSites(round)
    local rigs=tonumber(GlobalsGetValue(idle_key,"0"))==0
    GlobalsSetValue(prefix.."desert",rigs and "pending" or "placed")
    GlobalsSetValue(prefix.."winter","pending")
    GlobalsSetValue(prefix.."round",round)
    local detail=rigs and "$nh_storm_sites_pending_both" or "$nh_storm_sites_pending_well"
    GamePrintImportant("$nh_storm_sites_confirmed",detail,"data/ui_gfx/decorations_biome_modifier/freezing.png")
    lastForecast=GameGetFrameNum()
end

local function announceLanding(key,decoration,frame)
    local desc=key.."_desc"
    -- Keep an immediate landing from covering the core-entry forecast.
    if lastForecast and frame>=lastForecast and frame-lastForecast<180 then
        GamePrint(GameTextGetTranslatedOrNot(desc))
    else
        GamePrintImportant(key,desc,"data/ui_gfx/decorations_biome_modifier/"..decoration..".png")
    end
end

local function tryPlace(frame)
    local player=(EntityGetWithTag("player_unit") or {})[1]
    if not player then return end
    local px,py=EntityGetTransform(player)
    local biome=BiomeMapGetName(px,py)
    local region
    if biome=="$biome_desert" then region="desert" elseif biome=="$biome_winter" then region="winter" else return end
    local key=prefix..region
    if GlobalsGetValue(key,"")~="pending" then return end
    local left,_,width=GameGetCameraBounds()
    local extent=region=="desert" and rig_spacing+rig_half_width or 53
    for i=1,2 do
        local distance=extent+12+ProceduralRandomi(frame+i,px,0,48)
        local sx=i==1 and left+width+distance or left-distance
        if math.abs(sx-px)>extent+32 and place(biome,math.floor(sx),math.floor(py)) then
            GlobalsSetValue(key,"placed")
            return region
        end
    end
end

function M.update(phase,age,retiringShips)
    local frame=GameGetFrameNum()
    local round=phase==4 and tostring(frame-age)
    local newRound=round and GlobalsGetValue(prefix.."round","")~=round
    local arrivalPoll=frame%60==0 or (phase==4 and frame%60==30)
    if not arrivalPoll and well_until~=nil and not newRound then return end
    local expiringRigs,expiringWells
    rig_until,expiringRigs=trackSites(true,frame,restoreSites("cycle_storm_rig",true))
    well_until,expiringWells=trackSites(false,frame,restoreSites("cycle_storm_well",false))
    if newRound then confirmSites(round) end
    -- Their normal entity ticks finish production and remove the expired roots.
    if expiringRigs or expiringWells then return true end
    if retiringShips or frame%60~=0 then return end
    local region=tryPlace(frame)
    if region=="desert" then
        rig_until=trackSites(true,frame,EntityGetWithTag("cycle_storm_rig") or {})
        announceLanding("$nh_storm_rigs_arrive","hot",frame)
    elseif region=="winter" then
        well_until=trackSites(false,frame,EntityGetWithTag("cycle_storm_well") or {})
        announceLanding("$nh_storm_tower_arrives","freezing",frame)
    end
end

return M
