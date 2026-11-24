-- EW 1.6.8 tracks dropped items in DES. Its throw hook survives in inventory,
-- and the next throw creates a new GID. Never write these fields back on issue.
NHEWItems = {}
local E = NHEWItems
E.lockTag="nh_ew_deposit_lock"
local des = "mods/quant.ew/files/system/entity_sync_helper/"
local callbacks = {
    script_death=des.."death_notify.lua",
    script_throw_item=des.."item_notify.lua",
}

function E.enabled()
    return NHEW and NHEW.enabled()
end

function E.ready()
    return NHEW.ready() and NHEW.issuer()
end

function E.gid(entity)
    local gid,owned
    for _,c in ipairs(EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent") or {}) do
        if ComponentGetValue2(c,"name")=="ew_gid_lid" then
            local value=ComponentGetValue2(c,"value_string")
            if gid or (ComponentGetTags(c) or "")~="" or type(value)~="string" or #value>20 or not value:match("^%d+$") then return nil,true end
            gid=value
            owned=ComponentGetValue2(c,"value_bool")
        end
    end
    return gid,false,owned
end

-- A remote DES copy has the body of an item but is never a warehouse source.
-- A newly picked replica keeps ew_des until EW processes its native pickup.
function E.held(player,id,attached)
    if not E.ready() or not id or id==0 or not EntityGetIsAlive(id)
        or not NHEW.localBody(player) or EntityGetRootEntity(id)~=player
        or EntityHasTag(id,"ew_des") or EntityHasTag(id,"ew_client") then return false end
    local parent=EntityGetParent(id)
    if attached and parent==player then return true end
    if not parent or parent==0 or EntityGetParent(parent)~=player then return false end
    local name=EntityGetName(parent)
    return name=="inventory_quick" or name=="inventory_full"
end

function E.scope(token)
    return type(token)=="string" and token:match("^ew/([%w]+)/") or nil
end

function E.ticket(token)
    if not E.enabled() then return token end
    local issuer=E.ready()
    if issuer then return "ew/"..issuer.."/"..token end
end

function E.claimKeys(entity,source)
    local gid,bad=E.gid(entity)
    if bad or (source~=nil and type(source)~="string") then return nil,"Item ownership could not be verified." end
    -- A warehouse release may be dropped several times, receiving a different
    -- DES GID each time. Check its earlier identity first so a stale copy
    -- cannot reserve the new GID against the already confirmed recipient.
    local existing
    if source and source:match("^ew/[%w]+/r/") then
        existing="t/"..source
    else
        -- A mark left by a failed profile write retains the earlier ground GID.
        local prior=source and source:match("^ew/[%w]+/g/(%d+)$")
        if prior and prior~=gid then existing="g/"..prior end
    end
    local keys={}
    if existing then keys[#keys+1]=existing end
    if gid and existing~="g/"..gid then keys[#keys+1]="g/"..gid end
    for _,key in ipairs(keys) do
        local ground=key:match("^g/(%d+)$")
        if not ((ground and #ground<=20) or (#key<=156 and key:match("^t/ew/%w+/r/%d+/%d+/%d+/%d+/%d+/%d+$"))) then
            return nil,"Item ownership could not be verified."
        end
    end
    return keys
end
function E.source(entity,route)
    local tags={"noita_hideout_transfer_id","noita_hideout_dose_token","noita_hideout_pouch_token"}
    if route=="dose" then tags={"noita_hideout_dose_token"}
    elseif route=="pouch" then tags={"noita_hideout_pouch_token"} end
    for _,tag in ipairs(tags) do
        local c=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",tag)
        if c then return ComponentGetValue2(c,"value_string") end
    end
end
-- Only a single genuine warehouse release component can identify an item
-- independently of its current GID. A pouch or dose's private token cannot.
function E.releaseKey(entity)
    local tag="noita_hideout_transfer_id"
    local marked=EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent") or {}
    local source
    for _,c in ipairs(marked) do
        local tags=ComponentGetTags(c) or ""
        if ComponentGetValue2(c,"name")==tag or (","..tags..","):find(","..tag..",",1,true) then
            if source or tags~=tag or ComponentGetValue2(c,"name")~=tag then return end
            source=ComponentGetValue2(c,"value_string")
            if type(source)~="string" then return end
        end
    end
    if type(source)=="string" and #source<=154 and source:match("^ew/%w+/r/%d+/%d+/%d+/%d+/%d+/%d+$") then
        return "t/"..source
    end
end
function E.containsPlayer(id)
    if EntityHasTag(id,"polymorphed_player") or EntityHasTag(id,"ew_client") then return true end
    for _,child in ipairs(EntityGetAllChildren(id) or {}) do
        if EntityGetParent(child)==id and E.containsPlayer(child) then return true end
    end
    return false
end
function E.lockInfo(entity)
    local c=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",E.lockTag)
    if c then
        local token=ComponentGetValue2(c,"value_string")
        if ComponentGetValue2(c,"name")~=E.lockTag or ComponentGetTags(c)~=E.lockTag or type(token)~="string"
            or not token:match("^[%w_%-]+|%w+|[1-9]%d*$") then return "",nil,c end
        return token,ComponentGetValue2(c,"value_bool"),c
    end
end
function E.originalPermanent(entity,value)
    local stamp,original=E.lockInfo(entity)
    if stamp and NHEWDeposit and NHEWDeposit.acceptsLock(stamp) then return original end
    return value
end

local desTags={ew_des_lua=true,ew_remove_on_send=true,enabled_in_hand=true,enabled_in_world=true,enabled_in_inventory=true}
local luaDefaults={execute_on_added=false,execute_on_removed=false,call_init_function=false,remove_after_executed=false,
    execute_every_n_frame=1,execute_times=0,limit_how_many_times_per_frame=-1,limit_to_every_n_frame=-1,
    limit_all_callbacks=false,enable_coroutines=false}

function E.metadata(c,kind,seen)
    if not E.enabled() then return false end
    if kind=="VariableStorageComponent" then
        local name=ComponentGetValue2(c,"name")
        if name==E.lockTag then
            if (seen and seen[name]) or ComponentGetTags(c)~=name
                or ComponentGetValue2(c,"value_int")~=0 or ComponentGetValue2(c,"value_float")~=0
                or not NHEWDeposit or not NHEWDeposit.acceptsLock(ComponentGetValue2(c,"value_string")) then return false end
            if seen then seen[name]=true end
            return true
        end
        if name~="ew_gid_lid" and name~="ew_no_ground" and name~="ew_was_stealable" then return false end
        -- EW creates all three variables without tags. Its item lifecycle tags
        -- belong to the separate notification script, including on replicas.
        if (ComponentGetTags(c) or "")~="" or (seen and seen[name]) then return false end
        if seen then seen[name]=true end
        if name=="ew_gid_lid" then
            local gid=ComponentGetValue2(c,"value_string")
            return type(gid)=="string" and #gid<=20 and gid:match("^%d+$")~=nil
                and ComponentGetValue2(c,"value_float")==0
        end
        return ComponentGetValue2(c,"value_string")=="" and ComponentGetValue2(c,"value_int")==0
            and ComponentGetValue2(c,"value_float")==0 and not ComponentGetValue2(c,"value_bool")
    end
    if kind~="LuaComponent" then return false end
    local immortal=ComponentHasTag(c,"ew_immortal")
    if not immortal and not (ComponentHasTag(c,"ew_des_lua") and ComponentHasTag(c,"ew_remove_on_send")) then return false end
    for tag in (ComponentGetTags(c) or ""):gmatch("[^,]+") do
        if not (immortal and tag=="ew_immortal" or not immortal and desTags[tag]) then return false end
    end
    local members=ComponentGetMembers(c)
    if not members then return false end
    local found=false
    for field in pairs(members) do
        if luaDefaults[field]~=nil and ComponentGetValue2(c,field)~=luaDefaults[field] then
            return false
        elseif field:match("^script_") then
            local file=ComponentGetValue2(c,field)
            if type(file)=="string" and file~="" then
                local expected=immortal and field=="script_damage_about_to_be_received" and des.."immortal.lua"
                if file~=(expected or (not immortal and callbacks[field])) then return false end
                found=true
            end
        end
    end
    return found
end

function E.runtimeTag(entity,tag)
    if not E.enabled() or (tag~="ew_des" and tag~="polymorphable_NOT") then return false end
    local gid,_,owned=E.gid(entity)
    return gid~=nil and (tag=="ew_des" or owned==false)
end
