-- A read-only view of the current local body. The effect owners persist their
-- clocks across save/continue. Nothing from this display is persisted.
local files="mods/noita_hideout/files/"
local tarot=dofile(files.."tarot_sight.lua")
local injectors={}
for _,id in ipairs(NHInjectors.order) do
    local def=NHInjectors.types[id]
    injectors[def.tag]=def
end
local rows={}
local owner,language,sampled,previous

local function add(icon,label,frames,order,frame)
    if frames and frames>0 then
        rows[#rows+1]={icon=icon,label=label,frames=frames,deadline=frame+frames,order=order}
    end
end

local function deadline(entity,tag,frame)
    local c=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",tag)
    return c and ComponentGetValue2(c,"value_int")-frame
end

-- Script-driven regeneration and meals store remaining pulses, including
-- the 12-frame quick heal. Only the fraction of the current pulse is elapsed.
local function pulseFrames(entity,interval,frame)
    local c=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent")
    if not c then return end
    local hook=EntityGetFirstComponentIncludingDisabled(entity,"LuaComponent")
    local last=hook and ComponentGetValue2(hook,"mLastExecutionFrame")
    local elapsed=last and last>=0 and math.min(interval-1,math.max(0,frame-last)) or 0
    return ComponentGetValue2(c,"value_int")*interval-elapsed
end

local function attached(player,lang,frame)
    for _,child in ipairs(EntityGetAllChildren(player) or {}) do
        local tags=","..(EntityGetTags(child) or "")..","
        local dose=injectors[tags:match(",(noita_hideout_stimulant[%w_]*),")]
        if dose then
            local left
            if dose.healPercent then
                left=pulseFrames(child,60*dose.seconds/(dose.timerTicks or dose.seconds),frame)
            else
                local c=EntityGetFirstComponentIncludingDisabled(child,"GameEffectComponent")
                left=c and ComponentGetValue2(c,"frames")
            end
            add(dose.icon,dose[lang],left,"4"..dose.id,frame)
        elseif tags:find(",noita_hideout_meal_",1,true) then
            local icon=EntityGetFirstComponentIncludingDisabled(child,"UIIconComponent")
            if icon then
                local name=ComponentGetValue2(icon,"name")
                add(ComponentGetValue2(icon,"icon_sprite_file"),GameTextGetTranslatedOrNot(name),
                    pulseFrames(child,60,frame),"5"..name,frame)
            end
        elseif tags:find(",nh_enemy_radar,",1,true) or tags:find(",nh_item_radar,",1,true) then
            local enemy=tags:find(",nh_enemy_radar,",1,true)
            local life=EntityGetFirstComponentIncludingDisabled(child,"LifetimeComponent")
            if life then
                local kind=enemy and "radar_enemy" or "radar_item"
                add("data/ui_gfx/perk_icons/"..kind..".png",GameTextGetTranslatedOrNot("$perk_"..kind),
                    ComponentGetValue2(life,"kill_frame")-frame,"6"..kind,frame)
            end
        end
    end
end

local function sample(player,lang,frame,locations)
    local species,_,follow=NHCompanions.active(player)
    if species then add(NHCompanions.cardIcon(species),NHCompanions.species[species][lang],follow,"1",frame) end
    for i,id in ipairs(NHTarot.timedOrder) do
        local left=tarot.framesLeft(player,"nh_"..id,frame)
        if left>0 then add(NHCompanions.cardIcon(id),NHTarot.types[id][lang],left,"2"..i,frame) end
    end
    local function relic(id,left,order)
        local def=NHRedRelics.types[id]
        add(def.item.icon,def[lang],left,order,frame)
    end
    relic("salvage_bell",NHSalvageBell.remaining(player),"31")
    relic("rewind_watch",NHRewind.remaining(player),"32")
    relic("stasis_hourglass",deadline(player,"nh_hourglass_cast",frame),"33")
    local duster=(EntityGetAllChildren(player,"nh_duster_field") or {})[1]
    if duster then relic("dustless_duster",deadline(duster,"nh_duster_until",frame),"34") end
    relic("mana_reactor",deadline(player,"nh_reactor_active",frame),"35")
    attached(player,lang,frame)
    add(files.."items/remote_terminal.png",lang=="zh" and "设施雷达" or "Site radar",locations.remaining(frame),"6site",frame)
    table.sort(rows,function(a,b) return a.order<b.order end)
end

return function(player,lang,frame,locations)
    if player~=owner or lang~=language or not sampled or frame<previous or frame-sampled>=15 then
        rows={}
        owner,language,sampled=player,lang,frame
        if player and player~=0 then sample(player,lang,frame,locations) end
    else
        for i=#rows,1,-1 do
            local row=rows[i]
            row.frames=row.deadline-frame
            if row.frames<=0 then table.remove(rows,i) end
        end
    end
    previous=frame
    return rows
end
