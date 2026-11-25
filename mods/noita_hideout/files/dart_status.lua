local files="mods/noita_hideout/files/"
local D={attachedFrames=15*60}
local drugs={
    sedative={tag="nh_dart_sedative",linger=300*60},
    pheromone={tag="nh_dart_pheromone",linger=60*60},
}
local wakeTag="nh_dart_wake"

local function childWith(parent,tag)
    return (EntityGetAllChildren(parent,tag) or {})[1]
end

local function component(entity,kind,tag)
    if tag then return EntityGetFirstComponentIncludingDisabled(entity,kind,tag) end
    return EntityGetFirstComponentIncludingDisabled(entity,kind)
end

local function clock(effect)
    return component(effect,"VariableStorageComponent","nh_dart_clock")
end

function D.has(target,kind)
    local drug=drugs[kind]
    local effect=drug and childWith(target,drug.tag)
    local timer=effect and clock(effect)
    return timer~=nil and GameGetFrameNum()<ComponentGetValue2(timer,"value_int")+drug.linger
end

local function setLifetime(entity,duration,now)
    local life=component(entity,"LifetimeComponent")
    ComponentSetValue2(life,"lifetime",duration)
    ComponentSetValue2(life,"kill_frame",now+duration)
end

function D.attach(target,kind,hitX,hitY,heading)
    local drug=drugs[kind]
    if not drug or not target or target==0 or not EntityGetIsAlive(target) then return false end
    local dm=component(target,"DamageModelComponent")
    if not dm or ComponentGetValue2(dm,"hp")<=0 then return false end

    local now=GameGetFrameNum()
    local x,y=EntityGetTransform(target)
    local effect=childWith(target,drug.tag)
    local oldDetach=effect and ComponentGetValue2(clock(effect),"value_int")
    if effect and now>=oldDetach+drug.linger then
        -- An entity queued for removal cannot be revived by moving its timer.
        EntityRemoveTag(effect,drug.tag)
        EntityKill(effect)
        effect=nil
    end
    local fresh=not effect
    if fresh then
        -- Each shot source owns its effect entity. Native pheromone stains and
        -- other mods' charm entities keep their own durations.
        effect=EntityLoad(files.."projectiles/dart_"..kind.."_effect.xml",x,y)
        if not effect or effect==0 then return false end
    end
    local needle=childWith(effect,"nh_dart_needle")
    if needle and now>=oldDetach then
        EntityRemoveTag(needle,"nh_dart_needle")
        EntityKill(needle)
        needle=nil
    end
    local freshNeedle=not needle
    if freshNeedle then
        needle=EntityLoad(files.."projectiles/dart_needle.xml",x,y)
        if not needle or needle==0 then
            if fresh then EntityKill(effect) end
            return false
        end
    end
    if kind=="sedative" and not component(target,"LuaComponent",wakeTag) then
        local hook=EntityAddComponent2(target,"LuaComponent",{_tags=wakeTag,
            script_damage_received=files.."dart_damage.lua",execute_every_n_frame=120,
            script_source_file=files.."dart_cleanup.lua"})
        if not hook or hook==0 then
            if freshNeedle then EntityKill(needle) end
            if fresh then EntityKill(effect) end
            return false
        end
    end

    if fresh then EntityAddChild(target,effect) end
    if freshNeedle then
        local sprite=component(needle,"SpriteComponent")
        ComponentSetValue2(sprite,"image_file",files.."projectiles/"..kind.."_needle.png")
        EntityRefreshSprite(needle,sprite)
        EntityAddChild(effect,needle)
    end
    if hitX then
        -- The effect follows the target's position. Preserve the needle tip's
        -- offset from that position and its incoming angle as the target moves.
        local mount=component(needle,"InheritTransformComponent")
        ComponentSetValue2(mount,"Transform",hitX-x,hitY-y,1,1,heading)
        EntitySetTransform(needle,hitX,hitY,heading)
    end
    local duration=D.attachedFrames+drug.linger
    ComponentSetValue2(clock(effect),"value_int",now+D.attachedFrames)
    ComponentSetValue2(component(effect,"GameEffectComponent"),"frames",duration)
    setLifetime(effect,duration,now)
    setLifetime(needle,D.attachedFrames,now)
    return true
end

local function removeHook(target)
    local hook=component(target,"LuaComponent",wakeTag)
    if hook then EntityRemoveComponent(target,hook) end
end

function D.cleanup(target)
    if not D.has(target,"sedative") then removeHook(target) end
end

function D.damaged(target,damage)
    if damage<=0 then return end
    local effect=childWith(target,drugs.sedative.tag)
    if effect then
        if GameGetFrameNum()<ComponentGetValue2(clock(effect),"value_int") then return end
        EntityRemoveTag(effect,drugs.sedative.tag)
        EntityKill(effect)
    end
    removeHook(target)
end

return D
