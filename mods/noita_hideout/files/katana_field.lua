local files="mods/noita_hideout/files/"
local freeze=dofile_once(files.."stasis.lua")
local targets=dofile_once(files.."field_targets.lua")
local M={radius=90,maxTargets=192}
local tag,clockTag="nh_katana_field","nh_katana_field_clock"
local function component(entity,kind,key)
    if key then return EntityGetFirstComponentIncludingDisabled(entity,kind,key) end
    return EntityGetFirstComponentIncludingDisabled(entity,kind)
end
local registeredHerds
local function knownHerd(id)
    if type(id)~="number" or id~=id or id<0 or id>2147483647 or id~=math.floor(id) then return false end
    if not registeredHerds then
        registeredHerds={}
        -- The virtual CSV includes every enabled mod's registered herds.
        -- Read it lazily after mod initialization, once per Lua VM. This API
        -- is available in component scripts as well as init.lua.
        local header=(ModTextFileGetContent("data/genome_relations.csv") or ""):match("[^\r\n]+") or ""
        for name in (header:match("^[^,]*,(.*)$") or ""):gmatch("[^,]+") do
            name=name:match("^%s*(.-)%s*$")
            if name~="" and name~="-1" then
                local herd=StringToHerdId(name)
                if type(herd)=="number" and herd==herd and herd>=0 and herd<=2147483647 and herd==math.floor(herd) then
                    registeredHerds[herd]=true
                end
            end
        end
    end
    return registeredHerds[id]==true
end
local function hostileProjectile(player,shot)
    local shooter=ComponentGetValue2(shot,"mWhoShot")
    if shooter and shooter~=0 and EntityGetIsAlive(shooter) then
        return not targets.friendly(player,EntityGetRootEntity(shooter))
    end
    local genome=component(player,"GenomeDataComponent")
    if not genome then return false end
    local playerHerd=ComponentGetValue2(genome,"herd_id")
    local shotHerd=ComponentGetValue2(shot,"mShooterHerdId")
    -- A dead shooter may leave a valid modded herd on its projectile. Native
    -- herd APIs can abort the process for an unregistered ID, so never use a
    -- numeric range alone or probe an unknown ID through HerdIdToString.
    return knownHerd(shotHerd) and knownHerd(playerHerd) and GetHerdRelation(playerHerd,shotHerd)<40
end
local function held(player)
    local inventory=component(player,"Inventory2Component")
    return inventory and ComponentGetValue2(inventory,"mActiveItem")
end
local function wielding(player,weapon)
    return weapon and weapon~=0 and EntityGetIsAlive(weapon) and held(player)==weapon
        and EntityHasTag(weapon,"noita_hideout_katana") and EntityGetRootEntity(weapon)==player
end
local function number(value,lo,hi)
    return type(value)=="number" and value==value and value>=lo and value<=hi
end
local function owner(field)
    local c=component(field,"VariableStorageComponent","nh_katana_field_owner")
    if not c then return end
    return ComponentGetValue2(c,"value_int"),ComponentGetValue2(c,"value_float"),ComponentGetValue2(c,"value_bool")
end
function M.active(field)
    if not field or field==0 or not EntityGetIsAlive(field) then return false end
    local c=component(field,"VariableStorageComponent",clockTag)
    if not c or ComponentGetValue2(c,"value_int")<=GameGetFrameNum() then return false end
    local player,weapon,remote=owner(field)
    if not player or player==0 or not EntityGetIsAlive(player) or EntityHasTag(player,"polymorphed_player")
        or EntityHasTag(player,"ew_notplayer") or EntityHasTag(player,"nh_ew_waiting") then return false end
    local health=component(player,"DamageModelComponent")
    if health and ComponentGetValue2(health,"hp")<=0 then return false end
    if remote then return (EntityHasTag(player,"player_unit") or EntityHasTag(player,"ew_client")) and wielding(player,weapon) end
    return EntityHasTag(player,"player_unit") and dofile_once(files.."ew.lua").localBody(player)
        and wielding(player,weapon)
end
function M.affects(field,entity)
    if not M.active(field) or not EntityGetIsAlive(entity) or not targets.canAffect(entity,ModIsEnabled("quant.ew"))
        or EntityHasTag(entity,tag) or component(entity,"ItemComponent") then return false end
    local player=owner(field)
    local shot=component(entity,"ProjectileComponent")
    if shot then return hostileProjectile(player,shot) end
    return (EntityHasTag(entity,"enemy") or EntityHasTag(entity,"mortal")) and not targets.friendly(player,entity)
end
local function create(player,weapon,x,y,radius,duration,token,remote)
    local field=EntityLoad(files.."katana_field.xml",x,y)
    if not field or field==0 then return end
    local now=GameGetFrameNum()
    local clock=component(field,"VariableStorageComponent",clockTag)
    local source=freeze.source(field,"katana",now+duration,radius,token)
    local binding=EntityAddComponent2(field,"VariableStorageComponent",{_tags="nh_katana_field_owner",
        value_int=player,value_float=weapon or 0,value_bool=remote==true})
    if not clock or not source or not binding or binding==0 then EntityKill(field); return end
    ComponentSetValue2(clock,"value_int",now+duration)
    ComponentSetValue2(clock,"value_float",radius)
    ComponentSetValue2(clock,"value_string",tostring(now))
    local boundary=component(field,"SpriteComponent","nh_katana_boundary")
    if boundary then
        ComponentSetValue2(boundary,"special_scale_x",radius/32)
        ComponentSetValue2(boundary,"special_scale_y",radius/32)
    end
    return field
end
function M.activate(player,options,pay)
    options=options or {}
    if not player or player==0 or not EntityGetIsAlive(player) or not EntityHasTag(player,"player_unit")
        or not dofile_once(files.."ew.lua").localBody(player) then return nil,"Item unavailable." end
    local weapon=options.weapon or held(player)
    if not weapon or weapon==0 or not EntityGetIsAlive(weapon) or held(player)~=weapon
        or not EntityHasTag(weapon,"noita_hideout_katana") or EntityGetRootEntity(weapon)~=player then return nil,"Item unavailable." end
    for _,existing in ipairs(EntityGetWithTag(tag) or {}) do
        local caster,_,remote=owner(existing)
        if caster==player and not remote and M.active(existing) then return nil,"Field already active." end
    end
    -- A shield-funded field gets its deadline from the successful payment.
    -- Prepare its components first so a failed entity load cannot spend shield.
    local now=GameGetFrameNum()
    local maxDuration=2147483647-now
    local radius,duration=options.radius or M.radius,options.duration or 1
    if not number(radius,1,180) or not number(duration,1,maxDuration) then return nil,"Item unavailable." end
    local x,y=EntityGetTransform(player)
    local field=create(player,weapon,x,y,radius,math.floor(duration))
    if not field then return nil,"Item unavailable." end
    if pay then
        local ok,paidDuration=pay()
        if not ok then M.cancel(field); return nil,"Item unavailable." end
        if paidDuration then
            duration=math.min(maxDuration,paidDuration)
            ComponentSetValue2(component(field,"VariableStorageComponent",clockTag),"value_int",now+duration)
            freeze.source(field,"katana",now+duration,radius)
        end
    end
    M.tick(field)
    return field,duration
end
function M.cancel(field)
    if not field or field==0 or not EntityGetIsAlive(field) then return end
    local c=component(field,"VariableStorageComponent",clockTag)
    if c then ComponentSetValue2(c,"value_int",0) end
    freeze.cancelSource(field)
    EntityKill(field)
end
function M.tick(field,fresh)
    if not field or field==0 or not EntityGetIsAlive(field) then return end
    local c=component(field,"VariableStorageComponent",clockTag)
    local now=GameGetFrameNum()
    if not M.active(field) or (fresh and now>(tonumber(ComponentGetValue2(c,"value_string")) or -2)+1) then
        M.cancel(field); return
    end
    local x,y=EntityGetTransform(field)
    local radius=ComponentGetValue2(c,"value_float")
    -- Both the runtime and the entity can tick this source in one frame.
    if ComponentGetValue2(c,"name")==tostring(now) then return end
    ComponentSetValue2(c,"name",tostring(now))
    local nearby=EntityGetInRadius(x,y,radius) or {}
    local count=#nearby
    if count>0 then
        -- A rotating bounded slice prevents a dense fight from permanently
        -- starving the tail of the native query. Never enumerate world enemies.
        local start=(now*M.maxTargets)%count
        for offset=1,math.min(count,M.maxTargets) do
            local entity=nearby[(start+offset-1)%count+1]
            if M.affects(field,entity) then freeze.acquire(entity,field)
            elseif EntityHasTag(entity,"nh_hourglass_still") then freeze.checkTarget(entity) end
        end
    end
end
function M.applyRemote(player,token,x,y,radius,remaining)
    if type(token)~="string" or token=="" or #token>180 or not number(x,-10000000,10000000)
        or not number(y,-10000000,10000000) or not number(radius,1,180) or not number(remaining,1,2147483647-GameGetFrameNum())
        or not player or player==0 or not EntityGetIsAlive(player) then return end
    local weapon=held(player)
    if not wielding(player,weapon) then return end
    local duration=math.min(30,math.floor(remaining))
    local sourceToken="katana_remote:"..token
    for _,field in ipairs(EntityGetWithTag(tag) or {}) do
        local c=component(field,"VariableStorageComponent","nh_stasis_source")
        if c and ComponentGetValue2(c,"value_string")==sourceToken then
            local caster,boundWeapon,remote=owner(field)
            if not remote or caster~=player or boundWeapon~=weapon then return end
            local clock=component(field,"VariableStorageComponent",clockTag)
            ComponentSetValue2(clock,"value_int",GameGetFrameNum()+duration)
            freeze.source(field,"katana",GameGetFrameNum()+duration,ComponentGetValue2(clock,"value_float"))
            M.tick(field)
            return field
        end
    end
    local field=create(player,weapon,x,y,radius,duration,sourceToken,true)
    if field then M.tick(field) end
    return field
end
function M.cancelRemote(token)
    for _,field in ipairs(EntityGetWithTag(tag) or {}) do
        local c=component(field,"VariableStorageComponent","nh_stasis_source")
        if c and ComponentGetValue2(c,"value_string")=="katana_remote:"..token then M.cancel(field) end
    end
end
return M
