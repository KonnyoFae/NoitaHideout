NHUI = {}

local gui
local tab = "stash"
local stash_page = 1
local carried_page = 1
local last_open_mode
local drag, opening_press, last_case_frame, last_mouse_end
local recipe_choice = 1
local panel_width, panel_height = 314, 196
local white = { 0.96, 0.93, 0.84 }
local gold = { 1.00, 0.83, 0.47 }
local muted = { 0.76, 0.80, 0.78 }
local green = { 0.62, 0.95, 0.75 }
local slot_sprite = "data/ui_gfx/inventory/quick_inventory_box.png"
local icons = {
    dose = "mods/noita_hideout/files/items/dose.png",
    wand = "data/items_gfx/handgun.png",
    potion = "data/items_gfx/potion.png",
}

local function tint(color)
    GuiColorSetForNextWidget(gui, color[1], color[2], color[3], 1)
end

-- Trim at character boundaries. The GUI can run with either Chinese or English game fonts.
local function fit(value, available, scale)
    local original = tostring(value or ""):gsub("[\r\n]+", " ")
    local width = GuiGetTextDimensions(gui, original, scale)
    if width <= available then return original, false end
    local chars = {}
    for char in original:gmatch("[^\128-\191][\128-\191]*") do
        chars[#chars + 1] = char
    end
    local lo, hi = 0, #chars
    while lo < hi do
        local n = math.ceil((lo + hi) / 2)
        local w = GuiGetTextDimensions(gui, table.concat(chars, "", 1, n) .. "...", scale)
        if w <= available then lo = n else hi = n - 1 end
    end
    return table.concat(chars, "", 1, lo) .. "...", true
end

local function inside(x, y, rx, ry, width, height)
    return x >= rx and x < rx + width and y >= ry and y < ry + height
end

function NHUI.draw(model, dispatch)
    if not model.open or model.mode ~= "case" then
        last_open_mode, drag, opening_press, last_case_frame, last_mouse_end = nil, nil, false, nil, nil
    end
    if not model.open and not model.near and not model.ground_case then return end
    if not gui then gui = GuiCreate() end
    GuiStartFrame(gui)
    GuiZSet(gui, -80)

    local sw, sh = GuiGetScreenDimensions(gui)
    local function tr(zh, en) return model.lang == "zh" and zh or en end
    if not model.open then
        local hints = {}
        if model.near then hints[#hints + 1] = tr("[H] 藏身处", "[H] Hideout") end
        if model.ground_case then hints[#hints + 1] = tr("[G] 打开地上的安全箱", "[G] Open nearby case") end
        local caption = table.concat(hints, "    ")
        local text_w = GuiGetTextDimensions(gui, caption)
        local x = math.floor((sw - text_w) / 2)
        local y = sh - 20
        GuiZSetForNextWidget(gui, -79)
        GuiImageNinePiece(gui, 1, x - 5, y - 2, text_w + 10, 15, 0.96)
        tint(gold)
        GuiText(gui, x, y, caption)
        return
    end

    local s = math.min(1, (sw - 10) / panel_width, (sh - 10) / panel_height)
    if s <= 0 then return end
    local ox = math.floor((sw - panel_width * s) / 2)
    local oy = math.floor((sh - panel_height * s) / 2)
    local case = model.mode == "case"
    local mouse_x, mouse_y, down, pressed, released, mouse_settling
    local slots = {}
    if case then
        local frame = GameGetFrameNum()
        down = InputIsMouseButtonDown(1)
        pressed, released = InputIsMouseButtonJustDown(1), InputIsMouseButtonJustUp(1)
        if last_case_frame ~= frame - 1 then
            drag, opening_press = nil, down -- held case was clicked to open this frame
            last_mouse_end = nil
        end
        mouse_settling = last_mouse_end == frame - 1
        last_case_frame = frame
        local world_x, world_y = DEBUG_GetMouseWorld()
        local cx, cy, cw, ch = GameGetCameraBounds()
        mouse_x = ((world_x - cx) * sw / cw - ox) / s
        mouse_y = ((world_y - cy) * sh / ch - oy) / s
    end
    GuiZSetForNextWidget(gui, -79)
    GuiImageNinePiece(gui, 10, ox, oy, panel_width * s, panel_height * s, 1)

    local function label(x, y, value, w, color)
        local txt, truncated = fit(value, w * s, s)
        tint(color or white)
        GuiText(gui, ox + x * s, oy + y * s, txt, s)
        if truncated then GuiTooltip(gui, tostring(value), "") end
    end
    local function button(id, x, y, txt, color)
        tint(color or gold)
        local clicked = GuiButton(gui, id, ox + x * s, oy + y * s, txt, s)
        return clicked and not drag and not opening_press and not mouse_settling
    end
    local next_action, param
    local function command(id, x, y, txt, action, arg)
        if button(id, x, y, txt) then next_action, param = action, arg end
    end

    if last_open_mode ~= model.mode then carried_page = 1 end
    last_open_mode = model.mode
    label(9, 5, case and tr("安全箱", "Secure case") or tr("藏身处", "Hideout"), 198, white)
    command(11, 252, 5, tr("关闭", "Close"), "close")

    local tabs = {
        { "stash", tr("仓库", "Stash") },
        { "orders", tr("生产", "Production") },
    }
    if model.debug then tabs[#tabs + 1] = { "samples", tr("测试物资", "Test supplies") } end
    if tab == "samples" and not model.debug then tab = "stash" end
    local tx = 9
    if not case then
        for i, t in ipairs(tabs) do
            local active = tab == t[1]
            local title = active and ("[" .. t[2] .. "]") or t[2]
            if button(20 + i, tx, 24, title, active and gold or muted) then tab = t[1] end
            tx = tx + GuiGetTextDimensions(gui, "[" .. t[2] .. "]", s) / s + 12
        end
    end

    if case then
        -- Use the game's quick-inventory tile. Both the item sprite and its name
        -- accept a click. World sprite sheets get a compact, type-specific icon.
        local function item_slot(id, x, y, w, icon, kind, name, action, arg, tip)
            local tile_x, tile_y = ox + x * s, oy + y * s
            GuiZSetForNextWidget(gui, -79)
            GuiImage(gui, id, tile_x, tile_y, slot_sprite, 1, s)
            local selected = false
            local shown_icon
            if icon or icons[kind] then
                local sprite = icon or icons[kind]
                local iw, ih = GuiGetImageDimensions(gui, sprite)
                if not iw or not ih or iw <= 0 or ih <= 0 or iw > 18 or ih > 16 then
                    sprite = icons[kind]
                    if sprite then iw, ih = GuiGetImageDimensions(gui, sprite) end
                end
                if sprite and iw and ih and iw > 0 and ih > 0 then
                    shown_icon = sprite
                    if action and iw <= 20 * s and ih <= 20 * s then
                        selected = GuiImageButton(gui, id + 1, tile_x + (20 * s - iw) / 2,
                            tile_y + (20 * s - ih) / 2, "", sprite)
                        GuiTooltip(gui, name, tip)
                    else
                        GuiImage(gui, id + 1, tile_x + (20 - iw) * s / 2,
                            tile_y + (20 - ih) * s / 2, sprite, action and 1 or 0.65, s)
                    end
                end
            end
            local title = fit(name, (w - 24) * s, s)
            if action then
                if button(id + 2, x + 24, y + 4, title) then selected = true end
            else
                label(x + 24, y + 4, title, w - 24, muted)
            end
            GuiTooltip(gui, name, tip)
            if action then
                slots[#slots + 1] = {x = x, y = y, w = w, id = id, kind = kind,
                    icon = shown_icon, action = action, arg = arg}
                -- Native GUI selection also supports the gamepad. Mouse operations
                -- wait for release so the same press can become a drag.
                if selected and not (down or pressed or released or drag or opening_press or mouse_settling) then
                    next_action, param = action, arg
                end
            end
        end

        local in_case = model.pouch_location == "safe" or model.pouch_location == "case"
        local lost = model.pouch_location == "lost"
        local left_w, right_x, right_w = 145, 166, 137
        local doses = model.case_count or 0
        local where = lost and tr("已遗失", "Lost")
            or (in_case and tr("箱内", "Protected") or tr("随身，死亡遗失", "Carried, lost on death"))
        label(10, 25, tr("针剂包 · ", "Pouch · ") .. where, left_w, white)
        label(right_x, 25, tr("随身物品 · 点击存入", "Carried · click to store"), right_w, white)
        local dose_name = tr("耐火激活剂", "Fire stimulant") .. " ×" .. doses
        item_slot(100, 10, 42, left_w, model.dose_icon, "dose", dose_name,
            (not lost and doses > 0) and "take_dose" or nil, nil,
            tr("取出一支，选中针剂后点击使用。", "Take one. Select the syringe and use it to inject."))
        if not lost then
            command(31, 10, 67, in_case and tr("将整包移至随身栏", "Carry whole pouch")
                or tr("将整包放回箱内", "Protect whole pouch"), "move")
        elseif model.debug then
            label(10, 67, tr("可在出生点重领针剂包。", "Reissue at spawn."), left_w, muted)
        end
        local valuable = (model.secure_loot or {})[1]
        label(10, 93, valuable and tr("贵重物品格 · 已满", "Valuable slot · full")
            or tr("贵重物品格", "Valuable slot"), left_w, white)
        item_slot(110, 10, 109, left_w, model.secure_icon, model.secure_kind,
            valuable or tr("空", "Empty"), valuable and "secure_withdraw" or nil, 1,
            valuable and tr("取至快捷栏，满格时放在脚边。", "Take into the quickbar, or at your feet if full.")
                or tr("可放入一根魔杖或一瓶药水。", "Holds one wand or flask."))
        local carried = model.carried or {}
        local per_page = 4
        local pages = math.max(1, math.ceil(#carried / per_page))
        carried_page = math.min(carried_page, pages)
        if #carried == 0 then
            label(right_x, 48, tr("没有可放入的物品", "No eligible items"), right_w, muted)
        end
        for row = 1, per_page do
            local item = carried[(carried_page - 1) * per_page + row]
            if item then
                local dose = item.kind == "dose"
                local allowed = (dose and not lost) or (not dose and not valuable)
                local tip
                if dose then
                    tip = lost and tr("需先领回针剂包。", "Reissue the pouch first.")
                        or tr("放回针剂包。", "Place in the pouch.")
                else
                    tip = valuable and tr("请先取出箱内的贵重物品。", "Empty the valuable slot first.")
                        or tr("放入贵重物品格。", "Place in the valuable slot.")
                end
                item_slot(120 + row * 4, right_x, 42 + (row-1) * 22, right_w,
                    item.icon, item.kind, item.name, allowed and "place" or nil, item.entity, tip)
            end
        end
        if pages > 1 then
            if carried_page > 1 and button(145, right_x, 134, "<") then carried_page = carried_page - 1 end
            label(right_x + 29, 134, carried_page .. " / " .. pages, 72, muted)
            if carried_page < pages and button(146, right_x + 103, 134, ">") then carried_page = carried_page + 1 end
        end
        label(10, 154, tr("点击物品，或将它拖至另一侧的对应栏位。", "Click an item, or drag it to the matching slot on the other side."), 293, muted)

        if opening_press then
            next_action, param = nil, nil
            if not down then opening_press, last_mouse_end = false, last_case_frame end
        else
            if pressed and not drag then
                for _, slot in ipairs(slots) do
                    if inside(mouse_x, mouse_y, slot.x, slot.y, slot.w, 20) then
                        drag = {id = slot.id, arg = slot.arg, start_x = mouse_x, start_y = mouse_y, moved = false}
                        break
                    end
                end
            end
            if drag then
                next_action, param = nil, nil
                -- Rediscover the same entity in the current frame: a lost item,
                -- full target or disappeared pouch invalidates the operation.
                local source
                for _, slot in ipairs(slots) do
                    if slot.id == drag.id and slot.arg == drag.arg then source = slot; break end
                end
                if not source then
                    drag, opening_press = nil, down
                else
                    local dx, dy = mouse_x - drag.start_x, mouse_y - drag.start_y
                    if dx * dx + dy * dy >= 16 then drag.moved = true end
                    local tx, ty, tw, th = right_x, 40, right_w, 90
                    if source.action == "place" then
                        tx, tw, th = 10, left_w, 39
                        ty = source.kind == "dose" and 25 or 92
                    end
                    local target = inside(mouse_x, mouse_y, tx, ty, tw, th)
                    if released or not down then
                        last_mouse_end = last_case_frame
                        local clicked_source = not drag.moved and inside(mouse_x, mouse_y, source.x, source.y, source.w, 20)
                        if released and (clicked_source or (drag.moved and target)) then
                            next_action, param = source.action, source.arg
                        end
                        drag = nil
                    elseif drag.moved then
                        tint(target and green or muted)
                        GuiZSetForNextWidget(gui, -79.5)
                        GuiImageNinePiece(gui, 150, ox + tx*s, oy + ty*s, tw*s, th*s, target and 0.65 or 0.32)
                        if source.icon then
                            GuiZSetForNextWidget(gui, -84)
                            GuiImage(gui, 151, ox + (mouse_x+3)*s, oy + (mouse_y+3)*s, source.icon, 0.85, s)
                        end
                    end
                end
            end
        end
    elseif tab == "stash" then
        local items = model.loot or {}
        local per_page = 4
        local pages = math.max(1, math.ceil(#items / per_page))
        stash_page = math.min(math.max(1, stash_page), pages)
        command(40, 10, 44, tr("存入手持物品", "Deposit held item"), "deposit")
        label(132, 44, tr("物品数  ", "Items  ") .. #items, 80, muted)
        command(47, 216, 44, tr("找回安全箱", "Recall case"), "recall_case")
        if #items == 0 then
            label(10, 65, tr("仓库为空。手持魔杖或药瓶后存入。", "Empty. Hold a wand or flask to deposit it."), 265, muted)
        end
        for row = 1, per_page do
            local index = (stash_page - 1) * per_page + row
            if items[index] then
                local y = 63 + (row - 1) * 17
                label(10, y, tostring(index) .. ". " .. tostring(items[index]), 201)
                command(40 + row, 216, y, tr("取到脚边", "Drop at feet"), "withdraw", index)
            end
        end
        if stash_page > 1 and button(45, 10, 138, tr("< 上页", "< Prev")) then stash_page = stash_page - 1 end
        label(108, 138, stash_page .. " / " .. pages, 85, muted)
        if stash_page < pages and button(46, 216, 138, tr("下页 >", "Next >")) then stash_page = stash_page + 1 end
    elseif tab == "orders" then
        label(10, 42, tr("稳定传送液   500 单位", "Stable teleportatium   500 units"), 293)
        label(10, 56, tr("每批投入不稳定传送液 250、黏液 250。", "One batch takes 250 unstable teleportatium and 250 slime."), 293, muted)
        label(10, 71, tr("订单   ", "Order   ") .. tostring(model.order or ""), 293, green)
        if not model.order_active then
            local choices = model.recipe_indices or {}
            local total = #choices + (model.batch_available and 1 or 0)
            recipe_choice = math.max(1, math.min(recipe_choice, total))
            if total == 0 then
                label(10, 89, tr("将两种原料存入仓库，可用同瓶或分瓶。", "Deposit both ingredients in one or more flasks."), 293, muted)
            else
                local index = choices[recipe_choice] or 0
                if index == 0 then
                    label(10, 88, tr("跨瓶取料", "From multiple flasks"), 228)
                    if model.batch_sources and model.batch_sources ~= "" then
                        GuiTooltip(gui, tr("投料瓶", "Source flasks"), model.batch_sources)
                    end
                else
                    local name = model.loot[index] or ""
                    label(10, 88, tr("投料瓶  #", "Source  #") .. index .. "  " .. name, 228)
                end
                if total > 1 then
                    if button(53, 252, 88, "<") then recipe_choice = (recipe_choice - 2) % total + 1 end
                    if button(54, 278, 88, ">") then recipe_choice = recipe_choice % total + 1 end
                end
                local start = index == 0 and tr("按仓库顺序投料", "Start batch in stash order")
                    or tr("用此瓶投料", "Start batch with this flask")
                command(50, 10, 105, start, "order", index)
            end
        end
        local timing = model.reward_spent and tr("本局奖励已结算，订单待下局通关后送入仓库。", "Clear the next run to deliver the flask to the stash.")
            or tr("完成普通结局后，成品药瓶进入仓库。", "Clear a normal ending to deliver the flask to the stash.")
        label(10, 122, timing, 293, muted)
        if model.debug then
            if model.reward_spent then
                command(52, 10, 140, tr("测试：再次模拟通关", "Test: repeat simulation"), "simulate")
                label(10, 154, tr("本局已结算，重复模拟不会追加奖励。", "Already settled. Repeating gives no extra reward."), 293, muted)
            else
                command(52, 10, 140, tr("测试：模拟本局通关", "Test: simulate clear"), "simulate")
                label(10, 154, tr("模拟会用掉本局唯一一次通关奖励。", "Simulation spends this run's one clear reward."), 293, muted)
            end
        end
    else
        command(62, 10, 45, tr("生成测试魔杖与混合药瓶", "Spawn sample wand and mixed flask"), "preview_items")
        label(10, 62, tr("从地上拾取，手持要测试的物品后打开仓库。", "Pick one up and hold it, then use Deposit in the stash."), 293, muted)
        command(60, 10, 89, tr("重发测试针剂包", "Reissue test pouch"), "restock")
        label(10, 106, tr("替换当前针剂包，在安全箱放入两支激活剂。", "Replaces your pouch with two doses in the secure case."), 293, muted)
    end
    if model.status and model.status ~= "" then label(10, 175, model.status, 293, green) end
    if next_action then dispatch(next_action, param) end
end
