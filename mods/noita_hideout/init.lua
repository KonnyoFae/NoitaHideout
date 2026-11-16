local files = "mods/noita_hideout/files/"
dofile_once(files .. "store.lua")
dofile_once(files .. "wand.lua")
dofile_once(files .. "potion.lua")
dofile_once(files .. "transfers.lua")
dofile_once(files .. "native_items.lua")
dofile_once(files .. "doses.lua")
dofile_once(files .. "ui.lua")
NHNative.registerTranslations()

function OnModInit()
    NHWand.registerTemplates()
    NHPotion.readTemplates()
end

local run_key = "noita_hideout_run_v1"
local home_x_key, home_y_key = "noita_hideout_origin_x", "noita_hideout_origin_y"
local state, run_id, home_x, home_y, player_id
local popup
local opened, mouse_release, case_open = false, false, nil
local lang, status, last_error = "en", "", nil
local model_cache, next_attempt = nil, 0
local last_dose_frame = -1

local function tr(zh, en)
    return lang == "zh" and zh or en
end

local error_translations = {
    ["Hold a wand or flask first."] = "请先拾取并切换到手中的魔杖或药瓶。",
    ["This item has no storage adapter."] = "仓库尚未适配这件物品。",
    ["Inventory slot changed."] = "目标栏位已变动。",
    ["Slot unavailable."] = "目标格无法接收这件物品。",
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
    ["Only a recognized ordinary flask can be stored"] = "未能识别这个瓶子的类型。",
    ["This flask has attachments that cannot be restored"] = "药瓶带有无法还原的附件，已保留原瓶。",
    ["This flask still has a shop price"] = "这只药瓶仍带有商店价格。",
    ["Flask contains a quantity that cannot be restored exactly"] = "这瓶药水的余量无法精确还原，已保留原瓶。",
    ["Unsupported wand template"] = "未适配的魔杖模板",
    ["Unknown wand template"] = "未能识别魔杖模板",
    ["Unsupported wand script"] = "魔杖带有无法还原的脚本",
    ["Unsupported wand component"] = "魔杖带有无法还原的组件",
    ["Unsupported wand variable"] = "魔杖带有无法还原的状态",
    ["Wand is still generating"] = "魔杖仍在生成，请稍后重试",
    ["Cannot store a wand with an outstanding shop price"] = "这根魔杖仍带有商店价格。",
    ["Missing flask component"] = "瓶子缺少必要组件",
    ["Unsupported wand attachment"] = "魔杖带有无法还原的附件",
    ["Unsupported spell script"] = "法术带有无法还原的脚本",
    ["Unsupported spell attachment"] = "法术带有无法还原的附件",
    ["Unsupported spell variable"] = "法术带有无法还原的状态",
}

local function report(problem)
    local raw = tostring(problem)
    local reason = raw:gsub('^.-%.lua"?%]?:%d+:%s*', "")
    status = reason
    if lang == "zh" then
        local key, detail = reason:match("^(.-): (.+)$")
        if error_translations[reason] then status = error_translations[reason]
        elseif key and error_translations[key] then status = error_translations[key] .. "（" .. detail .. "）" end
    end
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
    feedback(tr("已注射，剩余耐久 ","Injected. Durability ") .. reason .. "/" .. NHStore.doseDurability)
end

local function item_label(entry)
    local item = entry.item
    if item.kind == "potion" then return NHPotion.label(item, lang) end
    if item.kind == "dose" then return tr("耐火激活剂","Fire injector") end
    if item.kind == "spell" then
        return GameTextGetTranslatedOrNot("$action_" .. item.card.id:lower()) .. (item.card.stack and (" ×" .. item.card.stack) or "")
    end
    local name = item.name or ""
    if name ~= "" then name = GameTextGetTranslatedOrNot(name) end
    if item.kind~="wand" then return name~="" and name or item.kind end
    if not name or name == "" then name = tr("魔杖", "Wand") end
    return name .. " (" .. #(item.cards or {}) .. tr(" 个法术)", " spells)")
end

local function stored_view(entry)
    local item=entry.item
    return {id=entry.id,kind=item.kind,name=item_label(entry),icon=item.icon or (item.sprite and item.sprite.image_file),
        remaining=item.remaining,count=item.count}
end

local function inventory_view()
    if model_cache and model_cache.revision == state.revision then return model_cache end
    local model = {revision = state.revision, loot = {}, secure_loot = {}, warehouse = {}, warehouse_last = {}, recipe_indices = {}}
    local function warehouse_slot(kind,slot,view)
        local category=NHStore.category(kind)
        model.warehouse[category]=model.warehouse[category] or {}
        model.warehouse[category][slot]=view
        model.warehouse_last[category]=math.max(model.warehouse_last[category] or 0,slot)
    end
    for i, entry in ipairs(state.warehouse) do
        local view=stored_view(entry)
        warehouse_slot(entry.item.kind,entry.slot or i,view)
        model.loot[i] = view.name
        if entry.item.kind == "potion" and NHPotion.can_refine(entry.item) then
            model.recipe_indices[#model.recipe_indices + 1] = i
        end
    end
    model.capacity = NHStore.safeCapacity(state)
    for _, entry in ipairs(state.safe) do
        model.secure_loot[entry.slot or 1] = stored_view(entry)
    end
    local pouch={kind="pouch",name=tr("针剂包","Injector pouch"),icon=NHNative.icons.pouch}
    if state.pouch.location=="safe" then model.secure_loot[state.pouch.slot]=pouch
    elseif state.pouch.location=="warehouse" then warehouse_slot("pouch",state.pouch.slot,pouch) end
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
    model.cells,model.pouchCapacity,model.maxUses=state.pouch.cells,NHStore.pouchCapacity,NHStore.doseDurability
    model.order_active = state.order ~= false
    model.order = state.order and tr("已投料，等待一次通关", "Paid; waiting for one clear") or tr("空闲", "Idle")
    model.reward_spent = state.rewardedThrough >= run_id
    model_cache = model
    return model
end

-- Quick wands and tools have independent x coordinates. Loose cards use
-- the full inventory's actual row and column; children of wands are excluded.
local function native_slots(player)
    local inv = EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    if not inv then return {} end
    local slots = {}
    for _, parent in ipairs(EntityGetAllChildren(player) or {}) do
        local name = EntityGetName(parent)
        local full = name == "inventory_full"
        if full or name == "inventory_quick" then
            local columns = full and ComponentGetValue2(inv,"full_inventory_slots_x") or 8
            local rows = full and ComponentGetValue2(inv,"full_inventory_slots_y") or 1
            local grid = {}
            for y=0,rows-1 do
                for col=0,columns-1 do
                    local lane = full and "spell" or (col<4 and "wand" or "tool")
                    local x = lane=="tool" and col-4 or col
                    local slot = {key="native", lane=lane, parent=parent, xslot=x, yslot=y, col=col}
                    slots[#slots+1] = slot
                    grid[y*columns+col] = slot
                end
            end
            for _, id in ipairs(EntityGetAllChildren(parent) or {}) do
                local item = EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
                if item then
                    local kind = NHNative.kind(id) or NHTransfers.item_kind(id) or "other"
                    local x,y = ComponentGetValue2(item,"inventory_slot")
                    if x and y and x>=0 and y>=0 and x<(full and columns or 4) and y<rows then
                        local slot = grid[y*columns+x+(not full and kind~="wand" and 4 or 0)]
                        if slot then
                            slot.entity,slot.kind = id,kind
                            if kind=="dose" then slot.remaining=NHDoses.remaining(state,id) end
                            slot.icon = ComponentGetValue2(item,"ui_sprite")
                        end
                    end
                end
            end
        end
    end
    return slots
end

local function matching_slot(player, wanted)
    for _, slot in ipairs(native_slots(player)) do
        if slot.parent==wanted.parent and slot.lane==wanted.lane and
            slot.xslot==wanted.xslot and slot.yslot==wanted.yslot then return slot end
    end
end

local function place_in_slot(player, id, slot)
    local live = matching_slot(player,slot)
    if not live or live.entity or EntityGetRootEntity(id) ~= id then return false end
    local item = EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
    if not item then return false end
    local kind = NHTransfers.item_kind(id)
    local lane = kind=="spell" and "spell" or (kind=="wand" and "wand" or "tool")
    if lane ~= slot.lane then return false end
    if lane=="spell" then
        EntityAddChild(slot.parent,id)
    else
        GamePickUpInventoryItem(player,id,false)
        if EntityGetParent(id)~=slot.parent then return false end
    end
    ComponentSetValue2(item,"inventory_slot",slot.xslot,slot.yslot)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_hand",false)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_world",false)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_inventory",true)
    local inv = EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    ComponentSetValue2(inv,"mForceRefresh",true)
    local x,y = ComponentGetValue2(item,"inventory_slot")
    return EntityGetParent(id)==slot.parent and x==slot.xslot and y==slot.yslot
end

local function popup_accessible(player)
    if not popup then return false end
    if popup.slot then
        return state.pouch.location==popup.container and state.pouch.slot==popup.slot and GameIsInventoryOpen()
            and (popup.container=="safe" or near_home(player))
    end
    return EntityGetIsAlive(popup.entity) and NHDoses.isPouch(state,popup.entity)
        and EntityGetRootEntity(popup.entity)==player
end

local function close_panel()
    popup=nil
    opened, case_open, mouse_release = false, nil, true
end

local function transfer_error(err, item)
    if item and item ~= 0 and EntityGetIsAlive(item) then
        print(("[noita_hideout] deposit declined: name=%s file=%s tags=%s reason=%s"):format(
            EntityGetName(item) or "", EntityGetFilename(item) or "", EntityGetTags(item) or "", tostring(err)))
    end
    local latest, read_error = NHStore.load()
    if latest and latest.profile == state.profile and latest.runSerial == run_id then
        state, model_cache = latest, nil
    else invalidate() end
    report(read_error or err)
end

local function dispatch(player, action, index)
    if action == "close" then close_panel(); return end
    if not opened or not active_run() then return end
    if case_open or popup then
        if action=="close_container" then
            popup=nil
            if not case_open then close_panel() end
            return
        end
        if type(index)~="table" then return end
        local container=index.container or "safe"
        if container~="safe" and container~="warehouse" then return end
        if container=="warehouse" and not (case_open and GameIsInventoryOpen() and near_home(player)) then return end
        if action=="open_container" then
            local owner
            if index.safeSlot and state.pouch.location==container and state.pouch.slot==index.safeSlot then owner={slot=index.safeSlot,container=container}
            elseif index.entity and NHDoses.isPouch(state,index.entity) and EntityGetRootEntity(index.entity)==player then owner={entity=index.entity} end
            if owner then popup=owner end
            return
        end
        if action=="unpack_dose" or action=="pack_dose" or action=="move_cell" then
            if not popup_accessible(player) then return end
            local ok,reason
            if action=="move_cell" then ok,reason=NHDoses.moveCell(state,index.sourceCell,index.targetCell)
            else ok,reason=NHDoses.moveDose(state,index.safeSlot,action=="unpack_dose",index.sourceCell or index.targetCell,container) end
            if not ok then report(reason) else status="" end
            return
        end
        if action=="move_safe_dose" then
            local ok,reason=NHDoses.moveSafeDose(state,index.from,index.safeSlot,container)
            if not ok then report(reason) else status="" end
            return
        end
        if action=="move_pouch" then
            if state.pouch.location==container and state.pouch.slot==index.from then
                commit_edit(function(draft)
                    if not NHStore.freeSlot(draft,container,index.safeSlot,"pouch") then return false,"Secure valuables slot is full." end
                    draft.pouch.slot=index.safeSlot
                    return true
                end)
            end
            return
        end
        if action=="move_warehouse" and container=="warehouse" then
            commit_edit(function(draft)
                local i=NHStore.slotIndex(draft,container,index.from,index.kind)
                if not i or draft.warehouse[i].id~=index.entity or not NHStore.freeSlot(draft,container,index.safeSlot,index.kind) then
                    return false,"Inventory slot changed."
                end
                draft.warehouse[i].slot=index.safeSlot
                return true
            end)
            return
        end
        if not GameIsInventoryOpen() and not popup_accessible(player) then return end
        local slot = matching_slot(player,index)
        if not slot then return end
        local ok,result
        if action=="place" or action=="cancel_native" then
            local id = index.entity
            if not id or not EntityGetIsAlive(id) then return end
            -- Vanilla can complete its outside-inventory throw before the post
            -- callback. Reclaim only this drag's original entity and empty slot.
            if not slot.entity and EntityGetRootEntity(id)==id then
                if not place_in_slot(player,id,slot) then return end
            elseif slot.entity~=id then return end
            local inv = EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
            if ComponentGetValue2(inv,"mThrowItem")==id then ComponentSetValue2(inv,"mThrowItem",0) end
            if action=="cancel_native" then return end
            local kind = NHNative.kind(id)
            if kind=="pouch" and index.safeSlot then ok,result=NHDoses.storePouch(state,player,id,index.safeSlot,container)
            elseif kind=="dose" then
                if not index.safeSlot and not (index.intoContainer and popup_accessible(player)) then return end
                ok,result=NHDoses.deposit(state,player,id,index.safeSlot,index.targetCell,container)
            else ok,result=NHTransfers.deposit(state,player,container,id,index.safeSlot) end
        else
            if slot.entity then return end
            local function deliver(id) return place_in_slot(player,id,slot) end
            if action=="take_pouch" then
                if state.pouch.location~=container or state.pouch.slot~=index.safeSlot then return end
                ok,result=NHDoses.takePouch(state,player,deliver)
            elseif action=="take_dose" then
                if not popup_accessible(player) then return end
                ok,result=NHDoses.withdraw(state,player,deliver,popup.entity,nil,index.sourceCell)
            elseif action=="secure_withdraw" then
                local row = NHStore.slotIndex(state,container,index.safeSlot,index.kind)
                if not row or state[container][row].id~=index.storedId then return end
                if state[container][row].item.kind=="dose" then
                    ok,result=NHDoses.withdraw(state,player,deliver,nil,index.safeSlot,nil,container)
                else ok,result=NHTransfers.withdraw(state,player,row,container,deliver) end
            else return end
        end
        if not ok then transfer_error(result,action=="place" and index.entity)
        else status="" end
        return
    end
    if not near_home(player) then close_panel(); return end
    if action == "order" then
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
    case_open,popup = nil,nil
    NHNative.resetInput()
    model_cache, status, last_error = nil, "", nil
    lang = GameTextGet("$current_language") == "简体中文" and "zh" or "en"
end

function OnPlayerSpawned(player)
    player_id = player
    set_home(player, true)
    attach()
end

local function current_player()
    if player_id and EntityGetIsAlive(player_id) and EntityHasTag(player_id, "player_unit") then return player_id end
    player_id = (EntityGetWithTag("player_unit") or {})[1]
    return player_id
end

function OnWorldPreUpdate()
    if not opened and not mouse_release then return end
    local player = current_player()
    if GameIsInventoryOpen() then return end
    if not player then
        opened, case_open, mouse_release = false, nil, false
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
    if not player or not active_run() then opened, case_open = false, nil; return end
    local inventory_open = GameIsInventoryOpen()
    local used = NHNative.pressed(player, inventory_open or opened or mouse_release)
    local frame = GameGetFrameNum()
    if frame % 60 == 0 then
        local ok, err = NHTransfers.reconcile(state, player)
        if ok then ok, err = NHDoses.reconcile(state, player) end
        if not ok then invalidate(); report(err); return end
    end
    local nearby = near_home(player)
    local was_open = opened
    if popup and not popup_accessible(player) then
        popup=nil
        if not case_open then close_panel() end
    end
    if inventory_open then
        opened,case_open=true,true
    elseif case_open then
        close_panel()
    elseif popup then
        if InputIsKeyJustDown(41) then close_panel() end
    elseif opened then
        local out_of_reach = not case_open and not nearby
        if out_of_reach or InputIsKeyJustDown(11) then close_panel() end
    elseif InputIsKeyJustDown(11) and nearby then -- H: spawn hideout
        opened, case_open = true, nil
    elseif used then
        local item = NHNative.held(player)
        local kind = NHNative.kind(item)
        if kind == "pouch" and NHDoses.isPouch(state, item) then
            opened,popup = true,{entity=item}
        elseif kind == "dose" then use_dose(player, item) end
    end
    if not active_run() then return end
    local model = opened and inventory_view() or {}
    if opened and (case_open or popup) then model.native_slots = native_slots(player) end
    model.popup = popup ~= nil
    model.mode = case_open and "case" or (popup and "container" or "home")
    model.open, model.near, model.lang, model.status = opened, nearby, lang, status

    model.debug = opened and ModSettingGet("noita_hideout.test_tools") ~= false
    model.active = opened and find_stimulant(player) ~= nil
    NHUI.draw(model, function(action, index)
        -- Ignore transfers on the frame that opens the panel.
        if was_open and opened then dispatch(player, action, index) end
    end)
end

function OnPlayerDied()
    popup=nil
    opened, case_open = false, nil
    if GlobalsGetValue(run_key, "") == "" then return end
    next_attempt = 0
    if not attach() or not active_run() then return end
    if GameHasFlagRun("ending_game_completed") then complete() end
    if active_run() then commit_edit(NHStore.endRun, nil, nil, run_id) end
end
