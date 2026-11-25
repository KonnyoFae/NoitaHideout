local files="mods/noita_hideout/files/"
local targets=dofile_once(files.."field_targets.lua")
local M={}
local still="nh_hourglass_still"
local paused="nh_hourglass_paused"
local slotTag="nh_hourglass_slot_"
local sourceTag,refTag="nh_stasis_source","nh_stasis_ref"
local fields,checkedFrame={},-1
local touched={}

-- Keep hitboxes, inventories, damage/death callbacks and the original entity.
-- Velocity stays in its component while its integrator is suspended.
local suspended={
    AIComponent=true, AIAttackComponent=true, AbilityComponent=true, AnimalAIComponent=true,
    AdvancedFishAIComponent=true, ArcComponent=true, AreaDamageComponent=true, BlackHoleComponent=true,
    BossDragonComponent=true, CardinalMovementComponent=true, CellEaterComponent=true,
    CharacterDataComponent=true, CharacterPlatformingComponent=true, ControllerGoombaAIComponent=true,
    CrawlerAnimalComponent=true, DamageNearbyEntitiesComponent=true, DieIfSpeedBelowComponent=true,
    DroneLauncherComponent=true, ExplosionComponent=true, FishAIComponent=true, FlyingComponent=true,
    GhostComponent=true, HomingComponent=true, IKLimbAttackerComponent=true, IKLimbsAnimatorComponent=true,
    LaserEmitterComponent=true, LifetimeComponent=true, LightningComponent=true, LimbBossComponent=true,
    MagicConvertMaterialComponent=true, MaterialSeaSpawnerComponent=true, ParticleEmitterComponent=true,
    PathFindingComponent=true, PhysicsAIComponent=true, ProjectileComponent=true, RotateTowardsComponent=true,
    SimplePhysicsComponent=true, SineWaveComponent=true, SpriteAnimatorComponent=true,
    SpriteParticleEmitterComponent=true, TeleportComponent=true, TeleportProjectileComponent=true,
    VelocityComponent=true, WormAIComponent=true, WormComponent=true,
}

function M.writableBody(entity)
    local body=EntityGetFirstComponent(entity,"PhysicsBodyComponent") or EntityGetFirstComponent(entity,"PhysicsBody2Component")
    if not body or ComponentGetValue2(body,"is_static") then return end
    local bodies=PhysicsBodyIDGetFromEntity(entity)
    if bodies and #bodies==1 then return bodies[1] end
end

local function capture(entity,deadline,now)
    local components=EntityGetAllComponents(entity) or {}
    local body=M.writableBody(entity)
    local vx,vy,spin
    if body then
        local bx,by,angle
        bx,by,angle,vx,vy,spin=PhysicsBodyIDGetTransform(body)
    end
    local record=EntityAddComponent2(entity,"VariableStorageComponent",{_tags=still,value_int=deadline})
    if not record or record==0 then return end
    local recovery=EntityAddComponent2(entity,"LuaComponent",{_tags=still,execute_every_n_frame=12,
        vm_type="SHARED_BY_MANY_COMPONENTS",
        script_source_file=files.."hourglass_resume.lua",script_item_picked_up=files.."hourglass_resume.lua"})
    if not recovery or recovery==0 then EntityRemoveComponent(entity,record); return end
    EntityAddTag(entity,still)
    local timers={}
    -- Use stable component tags for the original timers: component IDs change
    -- across saves, and another mod can remove a timer during the field.
    for _,c in ipairs(components) do
        if ComponentGetIsEnabled(c) then
            local kind=ComponentGetTypeName(c)
            if kind=="LuaComponent" then
                local interval=ComponentGetValue2(c,"execute_every_n_frame")
                if interval>0 and (ComponentGetValue2(c,"script_source_file") or "")~="" then
                    timers[#timers+1]="S"..interval
                    ComponentAddTag(c,slotTag..#timers)
                    ComponentSetValue2(c,"execute_every_n_frame",-1)
                end
            elseif suspended[kind] then
                if kind=="LifetimeComponent" then
                    local finish=ComponentGetValue2(c,"kill_frame")
                    local remaining=finish>0 and math.max(1,finish-now) or ComponentGetValue2(c,"lifetime")
                    timers[#timers+1]="L"..remaining
                    ComponentAddTag(c,slotTag..#timers)
                end
                ComponentAddTag(c,paused)
                EntitySetComponentIsEnabled(entity,c,false)
            end
        end
    end
    ComponentSetValue2(record,"value_string",table.concat(timers,","))
    if vx then
        ComponentSetValue2(record,"name",table.concat({vx,vy,spin},","))
        PhysicsSetStatic(entity,true)
    end
    return record
end

function M.release(entity,pickingUp)
    local record=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",still)
    if not record then return end
    local carried=pickingUp or EntityGetRootEntity(entity)~=entity
    local slot=0
    for kind,value in ComponentGetValue2(record,"value_string"):gmatch("([SL])(%-?%d+)") do
        slot=slot+1
        local tag=slotTag..slot
        local c=EntityGetFirstComponentIncludingDisabled(entity,kind=="S" and "LuaComponent" or "LifetimeComponent",tag)
        if c then
            local n=tonumber(value)
            if kind=="S" then
                if ComponentGetValue2(c,"execute_every_n_frame")==-1 then ComponentSetValue2(c,"execute_every_n_frame",n) end
            elseif n>=0 then ComponentSetValue2(c,"kill_frame",GameGetFrameNum()+n) end
            ComponentRemoveTag(c,tag)
        end
    end
    for _,c in ipairs(EntityGetAllComponents(entity) or {}) do
        if ComponentHasTag(c,paused) then
            ComponentRemoveTag(c,paused)
            -- Pickup changes the enabled flags itself. Preserve its choice of
            -- world, hand and inventory components whichever callback ran first.
            if not carried or not (ComponentHasTag(c,"enabled_in_world") or ComponentHasTag(c,"enabled_in_hand")
                or ComponentHasTag(c,"enabled_in_inventory")) then EntitySetComponentIsEnabled(entity,c,true) end
        end
    end
    local vx,vy,spin=ComponentGetValue2(record,"name"):match("^([^,]+),([^,]+),([^,]+)$")
    if vx then
        PhysicsSetStatic(entity,false)
        local body=not carried and M.writableBody(entity)
        if body then
            local x,y,angle=PhysicsBodyIDGetTransform(body)
            if x then PhysicsBodyIDSetTransform(body,x,y,angle,tonumber(vx),tonumber(vy),tonumber(spin)) end
        end
    end
    for _,ref in ipairs(EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent","nh_stasis_ref") or {}) do EntityRemoveComponent(entity,ref) end
    local recovery=EntityGetFirstComponentIncludingDisabled(entity,"LuaComponent",still)
    EntityRemoveTag(entity,still)
    EntityRemoveComponent(entity,record)
    if recovery then EntityRemoveComponent(entity,recovery) end
end


-- Sources and references use serialized tokens, never component or entity IDs.
-- The old snapshot tags remain readable by existing saves and repulsion fields.
function M.source(field,kind,deadline,radius,token)
    local c=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent",sourceTag)
    if not c then
        local serial=tonumber(GlobalsGetValue("nh_stasis_serial","0")) or 0
        serial=serial+1
        GlobalsSetValue("nh_stasis_serial",tostring(serial))
        token=token or (kind..":"..GameGetFrameNum()..":"..serial)
        c=EntityAddComponent2(field,"VariableStorageComponent",{_tags=sourceTag,name=kind,
            value_string=token,value_int=deadline,value_float=radius,value_bool=true})
        if not c or c==0 then return end
        EntityAddTag(field,"nh_stasis_field")
        checkedFrame=-1
    else
        ComponentSetValue2(c,"value_int",deadline)
        ComponentSetValue2(c,"value_float",radius)
    end
    return c
end

local function sources(refresh)
    local now=GameGetFrameNum()
    if refresh or checkedFrame~=now then
        fields,checkedFrame={},now
        -- A saved pre-shared hourglass may not have a source component yet.
        for _,field in ipairs(EntityGetWithTag("nh_hourglass_field") or {}) do
            local c=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent","nh_hourglass_clock")
            if c and not EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent",sourceTag) then
                M.source(field,"hourglass",ComponentGetValue2(c,"value_int"),ComponentGetValue2(c,"value_float"))
            end
        end
        for _,field in ipairs(EntityGetWithTag("nh_stasis_field") or {}) do
            local c=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent",sourceTag)
            if c then fields[ComponentGetValue2(c,"value_string")]={field,c} end
        end
        checkedFrame=now
    end
    return fields
end

local function covers(source,entity,now)
    if not source or not EntityGetIsAlive(source[1]) then return false end
    local field,c=source[1],source[2]
    if not ComponentGetValue2(c,"value_bool") or ComponentGetValue2(c,"value_int")<=now then return false end
    local x,y=EntityGetTransform(field)
    local ex,ey=EntityGetTransform(entity)
    local radius=ComponentGetValue2(c,"value_float")
    if (x-ex)^2+(y-ey)^2>radius*radius then return false end
    if ComponentGetValue2(c,"name")=="katana" then
        return dofile_once(files.."katana_field.lua").affects(field,entity)
    end
    return true
end

local function addReference(entity,field,c)
    local token=ComponentGetValue2(c,"value_string")
    for _,ref in ipairs(EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent",refTag) or {}) do
        if ComponentGetValue2(ref,"name")==token then
            ComponentSetValue2(ref,"value_int",ComponentGetValue2(c,"value_int"))
            return ref
        end
    end
    local ref=EntityAddComponent2(entity,"VariableStorageComponent",{_tags=refTag,name=token,
        value_int=ComponentGetValue2(c,"value_int")})
    if ref and ref~=0 then
        touched[token]=touched[token] or {}
        touched[token][entity]=true
        return ref
    end
end

local function adoptLegacy(entity,record)
    if ComponentGetValue2(record,"value_bool") then return end
    local now=GameGetFrameNum()
    if ComponentGetValue2(record,"value_int")>now then
        for _,source in pairs(sources()) do
            if ComponentGetValue2(source[2],"name")=="hourglass" and covers(source,entity,now) then
                addReference(entity,source[1],source[2])
            end
        end
    end
    ComponentSetValue2(record,"value_bool",true)
end

function M.acquire(entity,field)
    local c=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent",sourceTag)
    local now=GameGetFrameNum()
    if not c or not covers({field,c},entity,now) or not targets.canAffect(entity,ModIsEnabled("quant.ew")) then return false end
    local record=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",still)
    if record then adoptLegacy(entity,record)
    else
        record=capture(entity,ComponentGetValue2(c,"value_int"),now)
        if not record then return false end
        ComponentSetValue2(record,"value_bool",true)
    end
    if not addReference(entity,field,c) then M.checkTarget(entity); return false end
    ComponentSetValue2(record,"value_int",math.max(ComponentGetValue2(record,"value_int"),ComponentGetValue2(c,"value_int")))
    if ComponentGetValue2(c,"name")=="katana" then
        local recovery=EntityGetFirstComponentIncludingDisabled(entity,"LuaComponent",still)
        if recovery then ComponentSetValue2(recovery,"execute_every_n_frame",1) end
    end
    return true
end

function M.checkTarget(entity)
    local record=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",still)
    if not record then return end
    if not targets.canAffect(entity,ModIsEnabled("quant.ew")) then M.release(entity); return end
    adoptLegacy(entity,record)
    local now,held=GameGetFrameNum(),false
    local available=sources()
    for _,ref in ipairs(EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent",refTag) or {}) do
        local token=ComponentGetValue2(ref,"name")
        local source=available[token]
        if not source then available=sources(true); source=available[token] end
        if covers(source,entity,now) then held=true
        else EntityRemoveComponent(entity,ref) end
    end
    if not held then M.release(entity) end
end

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

-- Velocity components retain their base speed while disabled by stasis.
-- Do not infer a stopped projectile's outgoing speed from its world motion.
function M.getVelocity(entity)
    if not entity or entity==0 or not EntityGetIsAlive(entity) then return end
    local velocity=EntityGetFirstComponentIncludingDisabled(entity,"VelocityComponent")
    if not velocity then return end
    local vx,vy=ComponentGetValue2(velocity,"mVelocity")
    if finite(vx) and finite(vy) then return vx,vy end
end

-- Call after changing projectile ownership/herd. Friendly katana references
-- fall away immediately, but independent hourglass leases still hold the same
-- entity and resume it later with this velocity. Never force-enable motion.
function M.redirect(entity,vx,vy)
    if not finite(vx) or not finite(vy) or not entity or entity==0 or not EntityGetIsAlive(entity)
        or not targets.canAffect(entity,ModIsEnabled("quant.ew")) then return false end
    local velocity=EntityGetFirstComponentIncludingDisabled(entity,"VelocityComponent")
    if not velocity then return false end
    ComponentSetValue2(velocity,"mVelocity",vx,vy)
    M.checkTarget(entity)
    return true
end

function M.cancelSource(field)
    local c=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent",sourceTag)
    if not c then return end
    ComponentSetValue2(c,"value_bool",false)
    local token=ComponentGetValue2(c,"value_string")
    local x,y=EntityGetTransform(field)
    local pending=touched[token] or {}
    for _,entity in ipairs(EntityGetInRadiusWithTag(x,y,ComponentGetValue2(c,"value_float"),still) or {}) do pending[entity]=true end
    for entity in pairs(pending) do if EntityGetIsAlive(entity) then M.checkTarget(entity) end end
    touched[token]=nil
end

return M

