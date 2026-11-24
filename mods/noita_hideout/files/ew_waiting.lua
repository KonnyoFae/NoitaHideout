-- Runs in EW's Lua state. Only the owner ever handles serialized player data.
local base64=dofile_once("mods/quant.ew/files/resource/base64.lua")
local polymorph=dofile_once("mods/quant.ew/files/system/polymorph/polymorph.lua")
local W={}
local asset="mods/noita_hideout/files/entities/ew_waiting.xml"
local snapshot="ew_local_player_dead"
local marker="nh_ew_reinforce_episode"
local carryingNotice="$nh_hideout_ew_wait_carrying_peer"
local function comp(e,t,tag)
    if tag then return EntityGetFirstComponentIncludingDisabled(e,t,tag) end
    return EntityGetFirstComponentIncludingDisabled(e,t)
end
function W.isAnchor(e) return e and EntityGetIsAlive(e) and EntityHasTag(e,"nh_ew_waiting") end
local function inv(e,name)
    for _,c in ipairs(EntityGetAllChildren(e) or {}) do if EntityGetName(c)==name then return c end end
end
local function hasPeer(item)
    if EntityHasTag(item,"ew_client") and EntityHasTag(item,"polymorphed_player") then return true end
    for _,child in ipairs(EntityGetAllChildren(item) or {}) do if hasPeer(child) then return true end end
    return false
end
local function carriedPeers(holder)
    local carried={}
    for _,name in ipairs({"inventory_quick","inventory_full"}) do
        local pocket=inv(holder,name)
        for _,item in ipairs(pocket and EntityGetAllChildren(pocket) or {}) do
            if hasPeer(item) then carried[#carried+1]={item=item,pocket=name} end
        end
    end
    return carried
end
local function legacy(e)
    if not e or not EntityGetIsAlive(e) or W.isAnchor(e) or EntityHasTag(e,"ew_client")
        or not EntityHasTag(e,"ew_notplayer") or not comp(e,"Inventory2Component")
        or not comp(e,"DamageModelComponent") or not inv(e,"inventory_quick") then return false end
    local c=comp(e,"VariableStorageComponent",marker)
    local room,owner,seq
    if c then room,owner,seq=ComponentGetValue2(c,"value_string"):match("^([%w_%-]+)|(%w+)|([1-9]%d*)$") end
    return room and #room<=170 and #owner<=40 and #seq<=15 and GlobalsGetValue(snapshot,"")~=""
end
local pendingLegacy
function W.pendingLegacy(e) return e~=nil and e==pendingLegacy and EntityGetIsAlive(e) end
function W.releaseLegacy(e)
    if W.pendingLegacy(e) then EntityRemoveTag(e,"nh_ew_wait_upgrade");pendingLegacy=nil end
end
local function wallet(e)
    local c=comp(e,"WalletComponent")
    return c and ComponentGetValue2(c,"money")
end
local function setGold(e,n)
    local c=comp(e,"WalletComponent")
    if c and n~=nil then ComponentSetValue2(c,"money",n) end
end
local function readPlayer(encoded,x,y)
    if encoded=="" then return end
    local ent=util.deserialize_entity(base64.decode(encoded),x,y)
    if ent and EntityGetIsAlive(ent) and comp(ent,"DamageModelComponent") and comp(ent,"Inventory2Component")
        and not EntityHasTag(ent,"ew_notplayer") then return ent end
    if ent and EntityGetIsAlive(ent) then EntityKill(ent) end
end
local function store(ent)
    local ok,encoded=pcall(function() return base64.encode(util.serialize_entity(ent)) end)
    if not ok or type(encoded)~="string" or encoded=="" then return false end
    GlobalsSetValue(snapshot,encoded)
    return GlobalsGetValue(snapshot,"")==encoded
end
local function destroyItems(e)
    local quick=inv(e,"inventory_quick")
    if quick then for _,item in ipairs(EntityGetAllChildren(quick) or {}) do EntityKill(item) end end
end
local function replace(old,new)
    np.SetPlayerEntity(new)
    ctx.my_player.entity=new
    EntityKill(old)
    polymorph.switch_entity(new)
end
local function newAnchor(x,y)
    local anchor=EntityLoad(asset,x,y)
    if W.isAnchor(anchor) then
        EntityAddComponent2(anchor,"VariableStorageComponent",{_tags="nh_ew_death_position",
            value_string=math.floor(x).."|"..math.floor(y)})
    end
    return anchor
end
function W.enter(old)
    -- A teammate polymorphed into a pickup is still an independently owned
    -- live player. Serializing the carrier would duplicate that player.
    if #carriedPeers(old)>0 then return false,carryingNotice end
    local x,y=EntityGetTransform(old)
    local anchor=newAnchor(x,y)
    if not W.isAnchor(anchor) then return false end
    if not store(old) then EntityKill(anchor); return false end
    setGold(anchor,wallet(old))
    destroyItems(old)
    replace(old,anchor)
    return true
end
-- Prior releases kept the quick slots on the fighting substitute and the
-- remainder on the serialized real player. Reunite those exact item entities
-- before serializing; never publish the temporary player or mark it alive.
function W.upgrade(old)
    if not legacy(old) then return false end
    local x,y=EntityGetTransform(old)
    local source=GlobalsGetValue(snapshot,"")
    if source=="" then return false end
    local ok,player=pcall(readPlayer,source,x,y)
    if not ok or not player then return false end
    local quick,original=inv(old,"inventory_quick"),inv(player,"inventory_quick")
    if not quick or not original then EntityKill(player);return false end
    local carried=carriedPeers(old)
    local anchor
    if #carried==0 then
        anchor=newAnchor(x,y)
        if not W.isAnchor(anchor) then EntityKill(player);return false end
    end
    local items=EntityGetAllChildren(quick) or {}
    local function move(parent)
        for _,item in ipairs(items) do EntityRemoveFromParent(item);EntityAddChild(parent,item) end
    end
    local gold=wallet(old)
    setGold(player,gold);if anchor then setGold(anchor,gold) end
    destroyItems(player)
    move(original)
    local active=comp(old,"Inventory2Component")
    active=active and ComponentGetValue2(active,"mActiveItem")
    if active and active~=0 and EntityGetParent(active)==original then np.SetActiveHeldEntity(player,active,false,false) end
    if #carried>0 then
        -- The older format split real inventory across bodies. Reassemble it
        -- live (never serialize a carried peer), as for a canceled new death.
        for _,entry in ipairs(carried) do
            if entry.pocket=="inventory_full" then
                local slot=inv(player,entry.pocket) or original
                EntityRemoveFromParent(entry.item);EntityAddChild(slot,entry.item)
            end
        end
        W.releaseLegacy(old)
        GameRemoveFlagRun("ew_flag_notplayer_active")
        replace(old,player);GlobalsSetValue(snapshot,"")
        GamePrint(GameTextGet(carryingNotice))
        return true,carryingNotice
    end
    if not store(player) then
        move(quick);GlobalsSetValue(snapshot,source);EntityKill(player);EntityKill(anchor);return false
    end
    local c=comp(old,"VariableStorageComponent",marker)
    if c then EntityAddComponent2(anchor,"VariableStorageComponent",{_tags=marker,
        value_string=ComponentGetValue2(c,"value_string"),value_bool=ComponentGetValue2(c,"value_bool")}) end
    destroyItems(player);EntityKill(player)
    W.releaseLegacy(old)
    replace(old,anchor)
    return true
end
function W.restore(anchor,full)
    if not W.isAnchor(anchor) then return false end
    local x,y=EntityGetTransform(anchor)
    local ok,player=pcall(readPlayer,GlobalsGetValue(snapshot,""),x,y)
    if not ok or not player then return false end
    setGold(player,wallet(anchor))
    local dm=comp(player,"DamageModelComponent")
    local health=ctx.cap.health
    if full then ComponentSetValue2(dm,"hp",ComponentGetValue2(dm,"max_hp"))
    elseif ctx.proxy_opt.game_mode~="local_health" and health and health.health then
        local hp=health.health()
        if type(hp)=="number" then ComponentSetValue2(dm,"hp",hp) end
    end
    GameRemoveFlagRun("ew_flag_notplayer_active")
    replace(anchor,player)
    GlobalsSetValue(snapshot,"")
    if not full and ctx.proxy_opt.game_mode=="shared_health" then
        local hook=comp(player,"LuaComponent","ew_player_damage")
        if hook and ComponentGetValue2(hook,"script_damage_received")=="mods/quant.ew/files/system/local_health/grab_damage_message.lua" then
            EntityRemoveComponent(player,hook)
        end
        dofile_once("mods/quant.ew/files/system/damage/damage.lua").on_local_player_spawn(ctx.my_player)
    end
    return true
end
-- EW 1.6.8 OnPlayerSpawned calls its "dont rejoin" lethal branch *after*
-- invoking extra modules. Limit this exception to our saved body and its
-- synchronous spawn callback; all ordinary spawns still use EW unchanged.
local resuming
local function isSavedWait(e)
    return GameHasFlagRun("ew_flag_notplayer_active") and GlobalsGetValue(snapshot,"")~=""
        and (W.isAnchor(e) or (legacy(e) and comp(e,"VariableStorageComponent",marker)))
end
local function finishSpawn(e)
    if not e then return end
    GameAddFlagRun("ew_flag_notplayer_active")
    if not GameHasFlagRun("ending_game_completed") then GameRemoveFlagRun("ew_kill_player") end
    if ctx.my_player and ctx.my_player.status then ctx.my_player.status.is_alive=false end
    if W.isAnchor(e) then
        EntityRemoveTag(e,"homing_target")
        EntityRemoveTag(e,"ew_peer")
        local controls=comp(e,"ControlsComponent")
        if controls then ComponentSetValue2(controls,"enabled",false);EntitySetComponentIsEnabled(e,controls,false) end
    end
    resuming=nil
end
function W.installSpawnGuard()
    if type(OnPlayerSpawned)~="function" then return end
    local original=OnPlayerSpawned
    local cosmetics=dofile_once("mods/quant.ew/files/system/player/player_cosmetics.lua")
    for _,name in ipairs({"player_color","player_cosmetics"}) do
        local draw=cosmetics[name]
        cosmetics[name]=function(e,...) if resuming~=e then return draw(e,...) end end
    end
    local setup=inventory_helper.setup_inventory
    inventory_helper.setup_inventory=function(...)
        finishSpawn(resuming)
        return setup(...)
    end
    OnPlayerSpawned=function(e)
        if not isSavedWait(e) then return original(e) end
        resuming=e
        local ok,why=pcall(original,e)
        finishSpawn(resuming)
        if not ok then error(why) end
    end
end
function W.onSpawn(p)
    if resuming==p.entity or isSavedWait(p.entity) then
        resuming=p.entity
        if legacy(resuming) then pendingLegacy=resuming;EntityAddTag(resuming,"nh_ew_wait_upgrade") end
        GameRemoveFlagRun("ew_flag_notplayer_active")
    end
end
return W
