-- EW 1.6.8 loads its systems after mod initialization. Only edit the game's
-- virtual sources after every anchor has been checked, including repeat calls.
local M = {}
local base = "mods/quant.ew/files/"
local marker = 'local nh_wait_peer = dofile_once("mods/noita_hideout/files/ew_wait_peer_hooks.lua")\n'
local function add(old, before)
    return {old, before .. "\n" .. old}
end
local function after(old, extra)
    return {old, old .. "\n" .. extra}
end
local changes = {
    {"system/player_sync.lua", {
        add("local function undc(ent)", "nh_wait_peer.installPeerEvents(net.net_handling.proxy)"),
        after("local function undc(ent)", [=[    if nh_wait_peer.waiting(ent) then
        EntityAddTag(ent, "ew_client")
        return
    end]=]),
        add("    if input_data ~= nil then", [=[    if nh_wait_peer.waiting(player_data.entity) then
        nh_wait_peer.receiveState(player_data, input_data, pos_data)
        return
    end]=]),
        add("            local children = EntityGetAllChildren(ent) or {}",
            "            if nh_wait_peer.waiting(ent) then goto continue end"),
        after("local was_polied = false", "local nh_was_waiting = false"),
        {"        if was_polied ~= ctx.my_player.currently_polymorphed then",
         [[        local nh_is_waiting = nh_wait_peer.waiting(ctx.my_player.entity) or EntityHasTag(ctx.my_player.entity, "nh_ew_wait_upgrade")
        if was_polied ~= ctx.my_player.currently_polymorphed and not (nh_is_waiting or nh_was_waiting) then]]},
        after("        was_polied = ctx.my_player.currently_polymorphed", "        nh_was_waiting = nh_is_waiting"),
    }},
    {"system/notplayer_ai/notplayer_ai.lua", {
        {'if active and EntityGetIsAlive(ctx.my_player.entity) and EntityHasTag(ctx.my_player.entity, "ew_notplayer") then',
         'if active and EntityGetIsAlive(ctx.my_player.entity) and EntityHasTag(ctx.my_player.entity, "ew_notplayer") and not nh_wait_peer.waiting(ctx.my_player.entity) and not EntityHasTag(ctx.my_player.entity, "nh_ew_wait_upgrade") then'},
    }},
    {"system/spectate/spectate.lua", {
        after("local function cant_spectate(ent, peer_id)",
            "    if nh_wait_peer.excludeCamera(ent, peer_id) then return true end"),
        add("    for _, item in ipairs(EntityGetAllChildren(inv) or {}) do",
            "    if inv == nil and nh_wait_peer.waiting(entity) then return end"),
        {"alive = { peer_id, i }\n        if peer_id == ctx.my_id then",
         "alive = { peer_id, i }\n        if peer_id == ctx.my_id or nh_wait_peer.waiting(ctx.my_player.entity) then"},
        {"    camera_player_id, camera_player = get_me()\nend\n\nlocal function number_of_players()",
         "    camera_player_id, camera_player = get_me()\n    if nh_wait_peer.waiting(ctx.my_player.entity) then re_cam = true end\nend\n\nlocal function number_of_players()"},
        {[[if ctx.my_player.entity ~= cam_target.entity then
            inventory_target = EntityAddComponent2]], [[if ctx.my_player.entity ~= cam_target.entity and not nh_wait_peer.waiting(ctx.my_player.entity) then
            inventory_target = EntityAddComponent2]]},
        {"        if inv_spec ~= nil then", "        if inv_spec ~= nil and not nh_wait_peer.waiting(ctx.my_player.entity) then"},
        {[[            camera_player = player_fns.get_player_data_by_local_entity_id(ent)
            camera_player_id = camera_player.peer_id
            update_i()
            re_cam = true]], [[            local selected = player_fns.get_player_data_by_local_entity_id(ent)
            if selected and not nh_wait_peer.excludeCamera(selected.entity, selected.peer_id) then
                camera_player = selected
                camera_player_id = selected.peer_id
                update_i()
                re_cam = true
            end]]},
        after("    if camera_player == -1 then",
            "        if nh_wait_peer.waiting(ctx.my_player.entity) then ctx.spectating_over_peer_id = nil end"),
    }},
    {"system/spectator_helps/spectator_helps.lua", {
        after("function rpc.add_shield(target, rgbc)", [=[    if ctx.rpc_player_data and nh_wait_peer.waiting(ctx.rpc_player_data.entity) then
        remove_shield(ctx.rpc_peer_id)
        return
    end]=]),
        after("function module.on_world_update()", [=[    if nh_wait_peer.waiting(ctx.my_player.entity) then
        if shield_entities[ctx.my_id] then rpc.del_shield() end
        return
    end]=]),
    }},
    {"system/map/map.lua", {
        {'and not EntityHasTag(data.entity, "polymorphed_cessation") and not data.dc then',
         'and not EntityHasTag(data.entity, "polymorphed_cessation") and not data.dc and not nh_wait_peer.waiting(data.entity) then'},
    }},
}

local function unique(source, snippet)
    local first, last = source:find(snippet, 1, true)
    if first and not source:find(snippet, last + 1, true) then return first, last end
end

function M.install()
    local version = base .. "version.lua"
    if not ModDoesFileExist(version) or dofile_once(version) ~= "1.6.8" then return false end
    local pending = {}
    for _, file in ipairs(changes) do
        local path = base .. file[1]
        local source = ModTextFileGetContent(path)
        if type(source) ~= "string" then return false end
        source = source:gsub("\r\n", "\n")
        local patched = source:sub(1, #marker) == marker
        for _, edit in ipairs(file[2]) do
            if patched then
                if not unique(source, edit[2]) then return false end
            else
                local first, last = unique(source, edit[1])
                if not first then return false end
                source = source:sub(1, first - 1) .. edit[2] .. source:sub(last + 1)
            end
        end
        if not patched then pending[#pending + 1] = {path, marker .. source} end
    end
    for _, file in ipairs(pending) do ModTextFileSetContent(file[1], file[2]) end
    return true
end

return M
