local files = "mods/noita_hideout/files/"
dofile_once(files .. "store.lua")
dofile_once(files .. "wand.lua")
dofile_once(files .. "potion.lua")
dofile_once(files .. "transfers.lua")
dofile_once(files .. "native_items.lua")
dofile_once(files .. "case_item.lua")
dofile_once(files .. "doses.lua")
dofile_once(files .. "ui.lua")
NHNative.registerTranslations()

local run_key = "noita_hideout_run_v1"
local home_x_key, home_y_key = "noita_hideout_origin_x", "noita_hideout_origin_y"
local state, run_id, home_x, home_y, player_id
local opened, mouse_release, case_entity = false, false, nil
local lang, status, last_error = "en", "", nil
local model_cache, next_attempt = nil, 0
local last_dose_frame = -1

local function tr(zh, en)
    return lang == "zh" and zh or en
end

local function report(problem)
    local raw = tostring(problem)
    local translations = {
        ["Hold a wand or flask first."] = "请先拾取并切换到手中的魔杖或药瓶。",
        ["Only supported wands and flasks can be deposited."] = "此格接受已适配的魔杖和普通药瓶。",
        ["Item is no longer in this container."] = "物品已移出该容器。",
        ["Another order is active."] = "工坊已有一张在制订单。",
        ["Not enough ingredients across warehouse flasks."] = "仓库药瓶里的原料不足。",
        ["The selected item is no longer in your quick inventory."] = "这件物品已经离开快捷栏。",
        ["The case is already in your inventory."] = "安全箱就在你的道具栏里。",
        ["The case is already within reach."] = "安全箱就在附近，可按 G 开箱。",
        ["No dose available."] = "针剂包已空。",
        ["Pouch lost."] = "针剂包已遗失，可到出生点重发测试包。",
        ["Secure valuables slot is full."] = "贵重物品格已满。",
        ["This syringe is no longer available."] = "这支针剂已经用掉或收回。",
    }
    status = (lang == "zh" and translations[raw]) or raw
    if raw ~= last_error then
        last_error = raw
        GamePrint("[Hideout] " .. status)
        print("[noita_hideout] " .. raw)
    end
end

local function feedback(message)
    last_error, status = nil, message
    GamePrint(message)
end

local function invalidate()
    state, run_id, model_cache = nil, nil, nil
    next_attempt = GameGetFrameNum() + 60
end

local function save(draft)
    local ok, err = NHStore.commit(draft)
    if not ok then invalidate(); report(err); return false end
    state, model_cache = draft, nil
    return true
end

-- The run token lives in the world save, the inventory in the save-slot profile.
-- Stage the token first so an interrupted allocation can retry the same serial.
local function attach()
    if state and run_id then return true end
    if GameGetFrameNum() < next_attempt then return false end
    next_attempt = GameGetFrameNum() + 60
    local draft, err = NHStore.load()
    if not draft then report(err); return false end
    local token = GlobalsGetValue(run_key, "")
    if token == "" then
        token = draft.profile .. "/" .. (draft.runSerial + 1)
        GlobalsSetValue(run_key, token)
    end
    local profile, serial = token:match("^(%d+)/(%d+)$")
    serial = tonumber(serial)
    if tonumber(profile) ~= draft.profile or not serial or serial < 1
        or serial < draft.runSerial or serial > draft.runSerial + 1 then
        report(tr("世界与藏身处的远征编号不符。请开启新战局。", "World and hideout run IDs differ. Start a new run."))
        return false
    end
    if serial == draft.runSerial + 1 then
        NHStore.newRun(draft)
        if not save(draft) then return false end
    end
    state, run_id = draft, serial
    return true
end

local function set_home(player, spawned)
    if home_x and home_y then return end
    home_x = tonumber(GlobalsGetValue(home_x_key, ""))
    home_y = tonumber(GlobalsGetValue(home_y_key, ""))
    if home_x and home_y then return end
    local x, y = EntityGetTransform(player)
    local origin_x = tonumber(MagicNumbersGetValue("DESIGN_PLAYER_START_POS_X"))
    local origin_y = tonumber(MagicNumbersGetValue("DESIGN_PLAYER_START_POS_Y"))
    -- Enabling the prototype on a continued game must not move the warehouse underground.
    if origin_x and origin_y and (not spawned or (x-origin_x)^2 + (y-origin_y)^2 > 192^2) then
        x, y = origin_x, origin_y
    end
    home_x, home_y = x, y
    GlobalsSetValue(home_x_key, tostring(x))
    GlobalsSetValue(home_y_key, tostring(y))
end

local function near_home(player)
    local x, y = EntityGetTransform(player)
    return home_x and (x - home_x)^2 + (y - home_y)^2 <= 80^2
end

local function active_run()
    return state and run_id and state.closedThrough < run_id
end

local function commit_edit(edit, zh, en, arg)
    -- Edit a detached snapshot; a failed write must not leave changed fields in the HUD.
    local draft, err = NHStore.load()
    if not draft then report(err); return false end
    if draft.profile ~= state.profile or draft.runSerial ~= run_id or draft.closedThrough >= run_id then
        invalidate()
        report(tr("远征档案已经改变。", "The active run has changed."))
        return false
    end
    local changed, reason = edit(draft, arg)
    if not changed then report(reason); return false end
    if not save(draft) then return false end
    if zh then feedback(tr(zh, en)) end
    return true
end

local function complete()
    if not active_run() or state.rewardedThrough >= run_id then return end
    local had_order = state.order ~= false
    commit_edit(NHStore.reward,
        had_order and "订单完成，稳定传送液已入库。" or "已记录本局通关，没有在制订单。",
        had_order and "Order complete. Refined teleportatium is in the stash." or "Run completion recorded. No active order.",
        run_id)
end

local function find_stimulant(player)
    for _, child in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityHasTag(child, "noita_hideout_stimulant") then
            local effect = EntityGetFirstComponentIncludingDisabled(child, "GameEffectComponent")
            if effect then return effect end
        end
    end
end

local function use_dose(player, item)
    local frame = GameGetFrameNum()
    if last_dose_frame == frame then return end
    last_dose_frame = frame
    local effect = find_stimulant(player)
    local created
    if not effect then
        local x, y = EntityGetTransform(player)
        created = EntityLoad(files .. "stimulant.xml", x, y)
        if created and created ~= 0 then
            effect = EntityGetFirstComponentIncludingDisabled(created, "GameEffectComponent")
        end
        if not effect or effect == 0 then
            if created and created ~= 0 then EntityKill(created) end
            report(tr("无法创建激活剂效果。", "Could not create the stimulant effect.")); return
        end
    end
    local consumed, reason = NHDoses.consume(state, player, item)
    if not consumed then
        if created then EntityKill(created) end
        report(reason)
        return
    end
    ComponentSetValue2(effect, "frames", 3600)
    if created then EntityAddChild(player, created) end
    mouse_release = true
    feedback(tr("已注射耐火激活剂。", "Fire immunity injector used."))
end

local function item_label(entry)
    local item = entry.item
    if item.kind == "potion" then return NHPotion.label(item, lang) end
    local name = item.name or ""
    if name ~= "" then name = GameTextGetTranslatedOrNot(name) end
    if not name or name == "" then name = tr("魔杖", "Wand") end
    return name .. " (" .. #(item.cards or {}) .. tr(" 个法术)", " spells)")
end

local function inventory_view()
    if model_cache and model_cache.revision == state.revision then return model_cache end
    local model = {revision = state.revision, loot = {}, secure_loot = {}, recipe_indices = {}}
    for i, entry in ipairs(state.warehouse) do
        model.loot[i] = item_label(entry)
        if entry.item.kind == "potion" and NHPotion.can_refine(entry.item) then
            model.recipe_indices[#model.recipe_indices + 1] = i
        end
    end
    for i, entry in ipairs(state.safe) do model.secure_loot[i] = item_label(entry) end
    if state.safe[1] then model.secure_kind = state.safe[1].item.kind end
    local plan = NHStore.planBatch(state)
    model.batch_available = plan ~= nil
    if plan then
        local lines = {}
        for _, part in ipairs(plan) do
            local material = part.material == "slime" and tr("黏液", "Slime") or tr("不稳定传送液", "Unstable teleportatium")
            lines[#lines + 1] = "#" .. part.index .. "  " .. material .. "  " .. part.amount
        end
        model.batch_sources = table.concat(lines, "\n")
    end
    model.case_count, model.pouch_location = state.pouch.doses, state.pouch.location
    model.order_active = state.order ~= false
    model.order = state.order and tr("已投料，等待一次通关", "Paid; waiting for one clear") or tr("空闲", "Idle")
    model.reward_spent = state.rewardedThrough >= run_id
    model_cache = model
    return model
end

local function carried_view(player, model)
    local ids = NHTransfers.carried(player)
    local key = table.concat(ids, ",")
    if model.carried_key == key then return end
    model.carried_key, model.carried = key, {}
    for _, id in ipairs(ids) do
        local kind = NHNative.kind(id)
        if not kind then
            if EntityHasTag(id, "wand") then kind = "wand"
            elseif EntityHasTag(id, "potion") then kind = "potion" end
        end
        if kind == "wand" or kind == "potion" or kind == "dose" then
            local c = EntityGetFirstComponentIncludingDisabled(id, "ItemComponent")
            local name, icon
            if c then
                name = ComponentGetValue2(c, "item_name")
                icon = ComponentGetValue2(c, "ui_sprite")
            end
            if kind == "wand" and c and not ComponentGetValue2(c, "always_use_item_name_in_ui") then
                local ability = EntityGetFirstComponentIncludingDisabled(id, "AbilityComponent")
                if ability then name = ComponentGetValue2(ability, "ui_name") end
            end
            if name and name ~= "" then name = GameTextGetTranslatedOrNot(name) end
            if kind == "dose" then
                name, icon = tr("耐火激活剂", "Fire immunity injector"), NHNative.icons.dose
            elseif not name or name == "" then
                name = kind == "wand" and tr("魔杖", "Wand") or tr("药瓶", "Flask")
            end
            if kind == "potion" then
                local material = GetMaterialInventoryMainMaterial(id)
                if material and material > 0 then
                    local liquid = GameTextGetTranslatedOrNot(CellFactory_GetUIName(material))
                    if liquid and liquid ~= "" then name = name .. " · " .. liquid end
                end
            end
            if icon and not icon:match("%.png$") then icon = nil end
            model.carried[#model.carried + 1] = {entity = id, kind = kind, name = name, icon = icon}
        end
    end
end

local function collect_item(player, id)
    -- Vanilla has separate sets of four wand and item slots. A full row leaves
    -- the delivery at the player's feet rather than displacing another item.
    local is_wand = EntityHasTag(id, "wand")
    local occupied = 0
    for _, item in ipairs(NHTransfers.carried(player)) do
        if EntityHasTag(item, "wand") == is_wand then occupied = occupied + 1 end
    end
    if occupied < 4 then GamePickUpInventoryItem(player, id, false) end
    return EntityGetRootEntity(id) == player
end

local function close_panel()
    opened, case_entity, mouse_release = false, nil, true
end

local function transfer_error(err)
    local latest, read_error = NHStore.load()
    if latest and latest.profile == state.profile and latest.runSerial == run_id then
        state, model_cache = latest, nil
    else invalidate() end
    report(read_error or err)
end

local function dispatch(player, action, index)
    if action == "close" then close_panel(); return end
    if not opened or not active_run() then return end
    if case_entity then
        if not NHCase.accessible(state, player, case_entity) then close_panel(); return end
        if action == "move" then
            commit_edit(NHStore.movePouch, "针剂包已移动。", "Pouch moved.")
            return
        end
        local ok, result
        if action == "take_dose" then
            ok, result = NHDoses.withdraw(state, player)
            if ok then
                local collected = collect_item(player, result)
                feedback(collected and tr("针剂已放进快捷栏，选中后点击注射。", "Injector on your belt. Select it and use it.")
                    or tr("针剂在脚边，可按拾取键拿起。", "Injector at your feet. Pick it up when ready."))
            end
        elseif action == "place" then
            if not index or not EntityGetIsAlive(index) then
                report(tr("所选物品已移走。", "Selected item is no longer available.")); return
            end
            if NHNative.kind(index) == "dose" then
                ok, result = NHDoses.deposit(state, player, index)
            else
                ok, result = NHTransfers.deposit(state, player, "safe", index)
            end
            if ok then feedback(tr("已放入。", "Item stored.")) end
        elseif action == "secure_withdraw" then
            ok, result = NHTransfers.withdraw(state, player, index, "safe")
            if ok then
                local collected = collect_item(player, result)
                feedback(collected and tr("已取到快捷栏。", "Moved to your quick inventory.")
                    or tr("已取出，请在脚边拾取。", "Withdrawn. Pick it up at your feet."))
            end
        else return end
        if not ok then transfer_error(result) end
        return
    end
    if not near_home(player) then close_panel(); return end
    if action == "recall_case" then
        local ok, err = NHCase.recall(state, player, home_x, home_y)
        if ok then feedback(tr("安全箱已送回出生点。", "Secure case returned to spawn.")) else report(err) end
    elseif action == "deposit" or action == "withdraw" then
        local deposit = action == "deposit"
        local ok, err
        if deposit then ok, err = NHTransfers.deposit(state, player, "warehouse")
        else ok, err = NHTransfers.withdraw(state, player, index, "warehouse") end
        if not ok then transfer_error(err); return end
        feedback(deposit and tr("已存入。", "Item stored.") or tr("已取出，请在脚边拾取。", "Withdrawn. Pick it up at your feet."))
    elseif action == "order" then
        commit_edit(NHStore.startOrder, "已扣除两种原料，订单已排入。", "Both ingredients consumed. Order queued.", index)
    elseif ModSettingGet("noita_hideout.test_tools") ~= false then
        if action == "simulate" then
            if state.rewardedThrough >= run_id then
                report(tr("本局通关奖励已经领取。", "This run's clear reward has been used."))
            else complete() end
        elseif action == "restock" then
            commit_edit(NHStore.restock, "测试针剂包已重发，内有两支。", "Test pouch reissued with two doses.")
        elseif action == "preview_items" then
            local x, y = EntityGetTransform(player)
            local wand, err = NHWand.sample(x - 9, y - 5)
            if not wand then report(err); return end
            local flask, problem = NHPotion.sample(x + 9, y - 5)
            if not flask then EntityKill(wand); report(problem); return end
            feedback(tr("扫帚杖和半瓶混合液已放在脚边。", "Sample broom and half-full flask dropped nearby."))
        end
    end
end

-- Keep world input transient. A save made with the panel open never leaves
-- the player's control component disabled in the next session.
local function suppress_item_input(player)
    local c = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
    if not c then return end
    for _, key in ipairs({"Fire", "Fire2", "Throw", "Kick"}) do
        ComponentSetValue2(c, "mButtonDown" .. key, false)
        ComponentSetValue2(c, "mButtonFrame" .. key, -1)
    end
end

function OnWorldInitialized()
    state, run_id, home_x, home_y, player_id = nil, nil, nil, nil, nil
    opened, mouse_release, next_attempt, last_dose_frame = false, false, 0, -1
    case_entity = nil
    NHNative.resetInput()
    model_cache, status, last_error = nil, "", nil
    lang = GameTextGet("$current_language") == "简体中文" and "zh" or "en"
end

function OnPlayerSpawned(player)
    player_id = player
    set_home(player, true)
    if attach() and active_run() then
        local ok, err = NHCase.ensure(state, player, home_x, home_y)
        if not ok then report(err) end
    end
end

local function current_player()
    if player_id and EntityGetIsAlive(player_id) and EntityHasTag(player_id, "player_unit") then return player_id end
    player_id = (EntityGetWithTag("player_unit") or {})[1]
    return player_id
end

function OnWorldPreUpdate()
    if not opened and not mouse_release then return end
    local player = current_player()
    if not player or GameIsInventoryOpen() then
        opened, case_entity, mouse_release = false, nil, false
        return
    end
    if not opened and not InputIsMouseButtonDown(1) and not InputIsMouseButtonDown(2) then
        local c = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
        mouse_release = c and (ComponentGetValue2(c, "mButtonDownFire") or ComponentGetValue2(c, "mButtonDownFire2"))
    end
    if opened or mouse_release then suppress_item_input(player) end
end

function OnWorldPostUpdate()
    local player = current_player()
    if player then set_home(player, false) end
    if not run_id and not player then return end
    if not attach() or not active_run() then return end
    if state.rewardedThrough < run_id and GameHasFlagRun("ending_game_completed") then complete() end
    if not player or not active_run() then opened, case_entity = false, nil; return end
    local inventory_open = GameIsInventoryOpen()
    local used = NHNative.pressed(player, inventory_open or opened or mouse_release)
    if inventory_open then opened, case_entity = false, nil; return end
    local frame = GameGetFrameNum()
    if frame % 30 == 0 then
        local ok, err = NHCase.ensure(state, player, home_x, home_y)
        if not ok then report(err) end
    end
    if frame % 60 == 0 then
        local ok, err = NHTransfers.reconcile(state, player)
        if ok then ok, err = NHDoses.reconcile(state, player) end
        if not ok then invalidate(); report(err); return end
    end
    local nearby = near_home(player)
    local ground_case = NHCase.nearby(state, player)
    local was_open = opened
    if opened then
        local out_of_reach = case_entity and not NHCase.accessible(state, player, case_entity)
            or not case_entity and not nearby
        if out_of_reach or InputIsKeyJustDown(11) or (case_entity and InputIsKeyJustDown(10)) then close_panel() end
    elseif InputIsKeyJustDown(11) and nearby then -- H: spawn hideout
        opened, case_entity = true, nil
    elseif InputIsKeyJustDown(10) and ground_case then -- G: placed case
        opened, case_entity = true, ground_case
    elseif used then
        local item = NHNative.held(player)
        local kind = NHNative.kind(item)
        if kind == "case" and NHCase.accessible(state, player, item) then opened, case_entity = true, item
        elseif kind == "dose" then use_dose(player, item) end
    end
    if not active_run() then return end
    if not opened and not nearby and not ground_case then return end
    local model = opened and inventory_view() or {}
    model.mode, model.ground_case = case_entity and "case" or "home", ground_case ~= nil
    model.open, model.near, model.lang, model.status = opened, nearby, lang, status
    if opened and case_entity then carried_view(player, model) end
    model.debug = opened and ModSettingGet("noita_hideout.test_tools") ~= false
    model.active = opened and find_stimulant(player) ~= nil
    NHUI.draw(model, function(action, index)
        -- The opening click belongs to the held case, not the button underneath it.
        if was_open and opened then dispatch(player, action, index) end
    end)
end

function OnPlayerDied()
    opened, case_entity = false, nil
    if GlobalsGetValue(run_key, "") == "" then return end
    next_attempt = 0
    if not attach() or not active_run() then return end
    if GameHasFlagRun("ending_game_completed") then complete() end
    if active_run() then commit_edit(NHStore.endRun, nil, nil, run_id) end
end
