NHUI = {}

local gui
local tab = "stash"
local stash_page = 1
local recipe_choice = 1
local panel_width, panel_height = 314, 196
local white = { 0.96, 0.93, 0.84 }
local gold = { 1.00, 0.83, 0.47 }
local muted = { 0.76, 0.80, 0.78 }
local green = { 0.62, 0.95, 0.75 }
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

function NHUI.draw(model, dispatch)
    if not gui then gui = GuiCreate() end
    GuiStartFrame(gui)
    GuiZSet(gui, -80)

    local sw, sh = GuiGetScreenDimensions(gui)
    local function tr(zh, en) return model.lang == "zh" and zh or en end
    if not model.open then
        local caption = tr("[G] 安全箱", "[G] Secure case")
        local w = GuiGetTextDimensions(gui, caption)
        if GuiButton(gui, 2, sw - w - 9, sh - 16, caption) then dispatch("open_case") end
        if not model.near then return end
        local caption = tr("[H] 藏身处", "[H] Hideout")
        local text_w = GuiGetTextDimensions(gui, caption)
        local x = math.floor((sw - text_w) / 2)
        local y = sh - 20
        GuiZSetForNextWidget(gui, -79)
        GuiImageNinePiece(gui, 1, x - 5, y - 2, text_w + 10, 15, 0.96)
        tint(gold)
        GuiText(gui, x, y, caption)
        return
    end

    local case = model.mode == "case"
    local pw, ph = case and 153 or panel_width, case and 108 or panel_height
    local s = math.min(1, (sw - 10) / pw, (sh - 10) / ph)
    if s <= 0 then return end
    local ox = case and sw - pw*s - 5 or math.floor((sw - pw*s)/2)
    local oy = case and sh - ph*s - 5 or math.floor((sh - ph*s)/2)
    GuiZSetForNextWidget(gui, -79)
    GuiImageNinePiece(gui, 10, ox, oy, pw*s, ph*s, 1)

    local function label(x, y, value, w, color)
        local txt, truncated = fit(value, w * s, s)
        tint(color or white)
        GuiText(gui, ox + x * s, oy + y * s, txt, s)
        if truncated then GuiTooltip(gui, tostring(value), "") end
    end
    local function button(id, x, y, txt, color)
        tint(color or gold)
        local clicked = GuiButton(gui, id, ox + x * s, oy + y * s, txt, s)
        return clicked
    end
    local next_action, param
    local function command(id, x, y, txt, action, arg)
        if button(id, x, y, txt) then next_action, param = action, arg end
    end

    label(9, 5, case and tr("安全箱", "Secure case") or tr("藏身处", "Hideout"), case and 98 or 198, white)
    command(11, case and 119 or 252, 5, tr("关闭", "Close"), "close")
    if case then
        local protected = model.pouch_location == "safe"
        local name = protected and tr("针剂包 ×", "Pouch ×") .. (model.case_count or 0) or tr("针剂包格 · 空", "Pouch slot · empty")
        GuiImage(gui, 29, ox+5*s, oy+20*s, "data/ui_gfx/inventory/quick_inventory_box.png", 1, s)
        if protected then
            GuiImage(gui, 30, ox+8*s, oy+24*s, "mods/noita_hideout/files/items/pouch.png", 1, s)
            command(31, 28, 23, name, "take_pouch")
            if model.case_count > 0 then command(32, 9, 39, tr("取一支针剂", "Take one injector"), "take_dose") end
        else label(28, 23, name, 116, muted) end
        local valuable = (model.secure_loot or {})[1]
        if valuable then command(33, 9, 55, fit(valuable, 134*s, s), "secure_withdraw", 1)
        else label(9, 55, tr("贵重物品格 · 空", "Valuable slot · empty"), 134, muted) end
        command(34, 9, 71, tr("存入手持物品", "Store held item"), "place")
        if model.status ~= "" then label(9, 89, model.status, 134, green) end
        if next_action then dispatch(next_action, param) end
        return
    end

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

    if tab == "stash" then
        local items = model.loot or {}
        local per_page = 4
        local pages = math.max(1, math.ceil(#items / per_page))
        stash_page = math.min(math.max(1, stash_page), pages)
        command(40, 10, 44, tr("存入手持物品", "Deposit held item"), "deposit")
        label(132, 44, tr("物品数  ", "Items  ") .. #items, 80, muted)
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
