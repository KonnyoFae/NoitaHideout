-- EW loads local_health before extra_modules. Give this audited version of
-- its normal restore path a separate entry for a Hideout drop pod.
local M={}
local source="mods/quant.ew/files/system/local_health/local_health.lua"
local shared="mods/quant.ew/files/system/damage/damage.lua"
local version="mods/quant.ew/files/version.lua"

local function replace(text,original,replacement,count)
    local parts,start={},1
    for i=1,count do
        local at=text:find(original,start,true)
        if not at then return end
        parts[i]=text:sub(start,at-1)
        start=at+#original
    end
    if text:find(original,start,true) then return end
    parts[count+1]=text:sub(start)
    return table.concat(parts,replacement)
end

function M.install()
    if not ModDoesFileExist(version) or dofile_once(version)~="1.6.8" then return end
    local text=ModTextFileGetContent(source)
    if type(text)~="string" or text:find("nh_reinforce_restore",1,true) then return end
    text=text:gsub("\r\n","\n")
    local death="local function player_died()"
    text=replace(text,death,[=[local nh_waiting = dofile_once("mods/noita_hideout/files/ew_waiting.lua")
local function player_died(force_native)]=],1)
    local ordinary="    local gold = get_gold()\n\n    rpc.remove_homing(false)"
    if text then text=replace(text,ordinary,[=[    if not force_native and ctx.cap.health.nh_reinforce_wait and ctx.cap.health.nh_reinforce_wait() then
        local entered, reason = nh_waiting.enter(ctx.my_player.entity)
        if not entered then
            GameRemoveFlagRun("ew_flag_notplayer_active")
            GamePrint(GameTextGet(reason or "$nh_hideout_ew_wait_failed"))
        end
        return
    end
]=]..ordinary,1) end
    local timer="if not ctx.proxy_opt.no_notplayer and not ctx.proxy_opt.perma_death and notplayer_active and hp_new <= 0 then"
    if text then text=replace(text,timer,timer:gsub(" then$"," and not nh_waiting.isAnchor(player_ent) then"),1) end
    if not text then return end
    -- Check for a pending pod before local_health samples the waiting body.
    local update="    local hp, max_hp = util.get_ent_health(player_ent)"
    text=replace(text,update,[=[    local hp, max_hp = util.get_ent_health(player_ent)
    if notplayer_active and hp <= 0 and ctx.cap.health.nh_reinforce_hold
        and ctx.cap.health.nh_reinforce_hold() then
        hp, max_hp = util.get_ent_health(player_ent)
    end]=],1)
    local head="    on_poly_death = function()"
    if not text then return end
    text=replace(text,head,[=[    nh_reinforce_native = function()
        if nh_waiting.restore(ctx.my_player.entity, false) then player_died(true) end
    end,
    nh_reinforce_restore = function()
        if nh_waiting.isAnchor(ctx.my_player.entity) then
            if not nh_waiting.restore(ctx.my_player.entity, true) then return false end
            remove_stuff()
            do_switch_effect(true)
            spectate.disable_throwing(false, ctx.my_player.entity)
            rpc.revive_message()
            return true
        end
        ctx.cap.health.on_poly_death(ctx.cap.health.nh_reinforce_restore)
    end,
    on_poly_death = function(request)
        if nh_waiting.isAnchor(ctx.my_player.entity) then return end
        local nh_reinforced = request ~= nil and request == ctx.cap.health.nh_reinforce_restore
        if not nh_reinforced and ctx.cap.health.nh_reinforce_hold and ctx.cap.health.nh_reinforce_hold() then return end]=],1)
    -- The original broadcasts terrain clearing to every peer, twice. A pod
    -- already has a landing site and needs neither the stamp nor the RPC.
    if text then text=replace(text,"            rpc.remove_homing(true)",
        "            if not nh_reinforced then rpc.remove_homing(true) end",2) end
    local nextLine="\n            spectate.disable_throwing(false, ctx.my_player.entity)"
    if text then text=replace(text,"            reduce_hp()"..nextLine,
        "            if not nh_reinforced then reduce_hp() end"..nextLine,1) end
    if text then
        ModTextFileSetContent(source,text)
        -- A LocalNormal waiting save can be reopened with shared health:
        -- the placeholder has no damage model until the original body returns.
        local other=ModTextFileGetContent(shared)
        if type(other)=="string" and other:find("local function do_health_diff(hp, max_hp)",1,true) then
            other=other:gsub("\r\n","\n")
            local head="function module.on_local_player_spawn(my_player)\n"
            local scoped=replace(other,head,head..'    if EntityHasTag(my_player.entity,"nh_ew_waiting") then return end\n',1)
            if scoped then ModTextFileSetContent(shared,scoped) end
        end
    end
end
return M
