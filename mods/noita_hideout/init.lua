local files = "mods/noita_hideout/files/"
dofile_once(files .. "store.lua")
dofile_once(files .. "bank.lua")
dofile_once(files .. "workshop_clock.lua")
dofile_once(files .. "home_wand_edit.lua")
dofile_once(files .. "wand.lua")
dofile_once(files .. "potion.lua")
dofile_once(files .. "transfers.lua")
NHCompanions.registerItems()
NHCardWallets.registerItem()
dofile_once(files .. "products.lua")
dofile_once(files .. "perks.lua")
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
local next_room_check,pending_visit=0,nil
local bank_synced=false

local function tr(zh, en)
    return lang == "zh" and zh or en
end

local error_translations = {
    ["Card wallet changed."] = "卡片夹已移动，请重新选择。",
    ["Card wallet slot unavailable."] = "卡片夹栏位已改变，或此格无法叠放该卡。",
    ["Invalid card wallet."] = "卡片夹记录无效。",
    ["Could not create card wallet."] = "未能生成卡片夹。",
    ["Select a carried summon card."] = "请从原版道具栏选择一张召唤卡。",
    ["Hold a wand or flask first."] = "请先拾取并切换到手中的魔杖或药瓶。",
    ["This item has no storage adapter."] = "仓库尚未适配这件物品。",
    ["Wrong loading slot."] = "请将药瓶和粉末袋放入各自的装卸格。",
    ["Incompatible material."] = "这个容器无法装载该物料。",
    ["Container is empty."] = "容器已经为空。",
    ["No stock or free capacity."] = "库存已用尽或容器已满。",
    ["Inventory slot changed."] = "目标栏位已变动。",
    ["Slot unavailable."] = "目标格无法接收这件物品。",
    ["Item is no longer in this container."] = "物品已移出该容器。",
    ["Material storage is full."] = "物料库的种类格已满。",
    ["Construction unavailable."] = "这项建设尚未开放。",
    ["Upgrade level changed."] = "项目等级已变动，请重新查看。",
    ["Not enough construction resources."] = "建设所需的库存不足。",
    ["Facility is locked."] = "请先扩建对应的工位。",
    ["Spell not unlocked in this save."] = "请先在当前存档中解锁这张原版法术。",
    ["Product storage is full."] = "成品所属仓库没有可预留的空格。",
    ["Perk already equipped."] = "已装备同一种特质。",
    ["No packable perk nearby."] = "附近没有可封装的特质。",
    ["Could not activate perk."] = "未能激活这项特质。",
    ["Could not create packed perk."] = "未能生成特质物品。",
    ["Another order is active."] = "工坊已有一张在制订单。",
    ["Not enough bulk ingredients."] = "物料库存中的原料不足。",
    ["Not enough workshop resources."] = "仓库中的制造资源不足。",
    ["Missing stored ingredient."] = "消耗品仓库中缺少所需成品。",
    ["Farm plot changed."] = "田块已变化，请重新选择。",
    ["Unknown crop."] = "无法识别这种作物。",
    ["Farm equipment is required."] = "种植这类作物需要先扩建农业设备。",
    ["A farm plot is required."] = "请先开垦一块田。",
    ["Livestock equipment is required."] = "请先扩建畜牧设备。",
    ["No matching pen is free."] = "这种幼畜的栏舍已满。",
    ["Livestock collection changed."] = "栏舍已变化，请重新选择。",
    ["Missing catalyst."] = "物料库中缺少所需的催化样品。",
    ["Invalid gold transfer."] = "无法识别这笔存取操作。",
    ["Invalid gold amount."] = "请输入有效的金币数额。",
    ["Not enough carried gold."] = "随身金币不足。",
    ["Not enough stored gold."] = "存钱罐余额不足。",
    ["Unknown shop item."] = "商店没有这件商品。",
    ["Supplies storage is full."] = "消耗品仓库没有空格。",
    ["Equipment storage is full."] = "装备仓库没有空格。",
    ["Item ID limit reached."] = "藏身处无法再分配新的物品编号。",
    ["Wallet is full."] = "钱包余额已达上限。",
    ["Piggy bank is full."] = "存钱罐余额已达上限。",
    ["Wallet unavailable."] = "当前钱包无法存取金币。",
    ["Gold transfer exceeds the exact integer range."] = "这笔转账超过可精确记录的金额。",
    ["Invalid wallet receipt."] = "钱包转账记录异常。",
    ["Could not record the wallet transfer."] = "钱包转账记录写入失败，将重试。",
    ["Could not update the wallet."] = "钱包写入失败，将重试。",
    ["Waiting for wallet settlement."] = "待随身金币或钱包空间足够后，将继续结算。",
    ["Not enough empty containers."] = "容器仓库里可用的空容器不足。",
    ["Only empty containers can be dismantled."] = "只能拆解仓库内已清空的普通物料容器。",
    ["No essence for this spell."] = "这张法术没有对应的精华。",
    ["Resource storage is full."] = "这项资源的库存已满。",
    ["Invalid salvage mode."] = "无法识别所选的拆解方式。",
    ["The selected item is no longer in your quick inventory."] = "这件物品已经离开快捷栏。",
    ["The case is already in your inventory."] = "安全箱就在你的道具栏里。",
    ["The case is already within reach."] = "安全箱就在附近，可按 G 开箱。",
    ["No dose available."] = "针剂包已空。",
    ["Pouch unavailable."] = "这只针剂包已不在原处。",
    ["Could not mark the pouch."] = "未能标记这只针剂包。",
    ["Hold your injector pouch first."] = "请先取回这只针剂包。",
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
    bank_synced=false
    next_attempt = GameGetFrameNum() + 60
end

local function save(draft,only_time)
    local cached=only_time and model_cache
    if cached and cached.profile_revision~=draft.revision then cached=nil end
    NHAffinity.sync(draft)
    local ok, err = NHStore.commit(draft)
    if not ok then invalidate(); report(err); return false end
    if cached then cached.profile_revision=draft.revision end
    state, model_cache = draft, cached or nil
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
    if draft.closedThrough<serial then NHAffinity.bind(draft) end
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

local function active_draft()
    local draft, err = NHStore.load()
    if not draft then report(err); return end
    if draft.profile ~= state.profile or draft.runSerial ~= run_id or draft.closedThrough >= run_id then
        invalidate()
        report(tr("远征档案已经改变。", "The active run has changed."))
        return
    end
    return draft
end

local function commit_edit(edit, zh, en, arg)
    -- Edit a detached snapshot; a failed write must not leave changed fields in the HUD.
    local draft=active_draft()
    if not draft then return false end
    local changed, reason = edit(draft, arg)
    if not changed then
        if draft.revision~=state.revision then
            local latest=active_draft()
            if latest then state,model_cache=latest,nil end
        end
        report(reason)
        return false
    end
    if not save(draft) then return false end
    if zh then feedback(tr(zh, en)) end
    return true
end

local function update_workshop(player,frame,farm_time)
    local order=state.order
    local elapsed=NHClock.observe(state,frame)
    if frame>=next_room_check and not pending_visit then
        next_room_check=frame+10
        local key=NHClock.mountainAt(player)
        if key and not state.checkpoints[key] then pending_visit=key end
    end
    -- World globals carry sub-checkpoint progress through save/continue.
    -- Avoid serializing the entire warehouse every frame or interrupting a drag.
    local farm_due=NHFarm.due(state,farm_time)
    local affinity_due=frame%360==0 and NHAffinity.changed(state)
    if not pending_visit and not farm_due and not affinity_due and (not order or (elapsed<order.required and elapsed-order.progress<600)) then return true end
    local draft=active_draft()
    if not draft then return false end
    local changed,done=NHStore.advanceProduction(draft,{run=run_id,orderId=order and order.id or false,
        progress=elapsed,checkpoint=pending_visit})
    local farm_changed,produced,cards
    if farm_due then farm_changed,produced,cards=NHFarm.sync(draft,farm_time) end
    if changed or farm_changed or affinity_due then
        if not save(draft,not done and not produced) then return false end
        if done and pending_visit and elapsed<order.required then
            feedback(tr("圣山加速完成了订单，成品已入库。","Holy Mountain boost completed the order. Output delivered."))
        elseif done then feedback(tr("订单完成，成品已入库。","Order complete. Output delivered to storage."))
        elseif pending_visit and order then
            feedback(string.format(tr("首次抵达圣山，生产加速 %d 秒。","Holy Mountain reached. Production advanced by %d seconds."),
                NHStore.checkpointFrames/60))
        end
        if cards and #cards>0 then feedback(NHCompanions.rewardText(cards,lang,state)) end
    elseif draft.revision~=state.revision then
        state,model_cache=draft,nil
    end
    pending_visit=nil
    NHClock.observe(state,frame)
    return true
end

local function find_stimulant(player,tag,component)
    for _, child in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityHasTag(child,tag) then
            local effect = EntityGetFirstComponentIncludingDisabled(child,component)
            if effect then return effect end
        end
    end
end

local function use_dose(player, item)
    local frame = GameGetFrameNum()
    if last_dose_frame == frame then return end
    last_dose_frame = frame
    local remaining,subtype=NHDoses.remaining(state,item)
    if not remaining then report("This syringe is no longer available."); return end
    local d=NHInjectors.get(subtype)
    local healing=d.id=="healing"
    local component=healing and "VariableStorageComponent" or "GameEffectComponent"
    local effect = find_stimulant(player,d.tag,component)
    local created
    if not effect then
        local x, y = EntityGetTransform(player)
        created = EntityLoad(files .. d.effect..".xml", x, y)
        if created and created ~= 0 then
            effect = EntityGetFirstComponentIncludingDisabled(created,component)
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
    ComponentSetValue2(effect,healing and "value_int" or "frames",healing and 60 or 3600)
    if created then EntityAddChild(player, created) end
    mouse_release = true
    feedback(tr("已注射，剩余耐久 ","Injected. Durability ") .. reason .. "/" .. NHStore.doseDurability)
end

local spell_names={
    DISC_BULLET_BIGGER="$action_omega_disc_bullet",LANCE_HOLY="$action_holy",
    LASER_LUMINOUS_DRILL="$action_luminous_drill_timer",TELEPORT_PROJECTILE_CLOSER="$action_teleport_closer",
    FUNKY_SPELL="???",
}
local function translated(key)
    if not key or key=="" then return end
    local value=GameTextGetTranslatedOrNot(key)
    if value and value~="" and value:sub(1,1)~="$" then return value end
end

local function item_label(entry)
    local item = entry.item
    if item.kind == "potion" then return NHPotion.label(item, lang) end
    if item.kind == "dose" then
        local d=NHInjectors.get(item.subtype)
        return tr(d.zh,d.en)
    end
    if item.kind == "spell" then
        local id=item.card.id
        local name=item.name and item.name:match("^%$action_") and translated(item.name)
        name=name or translated(spell_names[id] or "$action_"..id:lower()) or translated(item.name) or id
        return name .. (item.card.stack and (" ×" .. item.card.stack) or "")
    end
    local name = item.name or ""
    if name ~= "" then name = GameTextGetTranslatedOrNot(name) end
    if item.kind=="medkit" then return name.." ("..(item.remaining or 3).."/3)" end
    if item.kind=="summon_card" then return translated(item.name) or tr(NHCompanions.species[item.species].zh,NHCompanions.species[item.species].en) end
    if item.kind~="wand" then return name~="" and name or item.kind end
    if not name or name == "" then name = tr("魔杖", "Wand") end
    return name .. " (" .. #(item.cards or {}) .. tr(" 个法术)", " spells)")
end

local function stored_view(entry)
    local item=entry.item
    local potion=item.kind=="potion" and item or nil
    return {id=entry.id,kind=item.kind,name=item_label(entry),potion=potion,
        icon=potion and NHPotion.inventoryIcon(potion) or (item.kind=="dose" and NHInjectors.get(item.subtype).icon)
            or item.icon or (item.sprite and item.sprite.image_file),
        remaining=item.remaining,count=item.count,subtype=item.subtype,species=item.species,dockSlot=NHPotion.dockSlot(item)}
end

local function pouch_name(id)
    return tr("针剂包","Injector pouch").." #"..id
end

local function inventory_view()
    if model_cache and model_cache.profile_revision == state.revision then return model_cache end
    local model = {revision = state.revision, profile_revision=state.revision, secure_loot = {}, warehouse = {}}
    model.affinityPoints=function(species) return NHAffinity.points(state,species) end
    model.essences={}
    for _,key in ipairs(NHEssences.order) do
        local kind=NHEssences.types[key]
        model.essences[#model.essences+1]={key=key,name=tr(kind.zh,kind.en),amount=state.resources[key] or 0}
    end
    model.docks,model.materials={},{}
    for _,row in ipairs(state.docks) do
        local view=stored_view(row)
        view.used,view.capacity=NHPotion.fillLevel(row.item)
        model.docks[row.slot]=view
    end
    for name,amount in pairs(state.materials) do
        model.materials[#model.materials+1]={key=name,name=NHPotion.materialName(name,lang),amount=amount,slot=NHPotion.materialSlot(name)}
    end
    table.sort(model.materials,function(a,b) return a.key<b.key end)
    local function warehouse_slot(kind,slot,view)
        local category=NHStore.category(kind)
        model.warehouse[category]=model.warehouse[category] or {}
        model.warehouse[category][slot]=view
    end
    for i, entry in ipairs(state.warehouse) do
        local view=stored_view(entry)
        local amount,resource=NHStore.salvageYield(entry.item)
        if amount then
            view.salvage_yield=amount
            view.salvage_name=resource=="container_scrap" and tr("容器碎片","Container scrap") or tr("奥术碎片","Arcane scrap")
            view.salvage_stock=state.resources[resource] or 0
        end
        if entry.item.kind=="spell" then
            local card=entry.item.card
            view.spell_uses=card.item and card.item.uses_remaining
            local count,key=NHStore.salvageYield(entry.item,"essence")
            if count then
                local kind=NHEssences.types[key]
                local profile=NHEssences.healingProfiles[card.id]
                view.essence={key=key,name=tr(kind.zh,kind.en),amount=count,stock=state.resources[key] or 0,
                    per_card=NHEssences.values[card.id],basis=profile and tr(profile.zh,profile.en)}
            end
        end
        warehouse_slot(entry.item.kind,entry.slot or i,view)
    end
    if state.order and state.order.output.item then
        warehouse_slot(state.order.output.item.kind,state.order.output.slot,{
            kind="reserved",name=tr("工坊成品预留格","Reserved for workshop output")})
    end
    model.capacity = NHStore.safeCapacity(state)
    for _, entry in ipairs(state.safe) do
        model.secure_loot[entry.slot or 1] = stored_view(entry)
    end
    for id,pouch in pairs(state.pouches) do
        local view={id=id,kind="pouch",name=pouch_name(id),icon=NHNative.icons.pouch,doses=pouch.doses}
        if pouch.location=="safe" then model.secure_loot[pouch.slot]=view
        elseif pouch.location=="warehouse" then warehouse_slot("pouch",pouch.slot,view) end
    end
    model.progression=NHStore.progressMenu(state,lang)
    model.warehouse_capacity={}
    for _,category in ipairs({"wand","spell","containers","supplies","equipment","collection","materials"}) do
        model.warehouse_capacity[category]=NHStore.warehouseCapacity(state,category)
    end
    model.salvage_enabled=NHStore.level(state,"salvage")>0
    model.shopGoods={}
    for _,good in ipairs(NHStore.shopGoods) do
        local ready,reason=NHStore.canBuyGood(state,good)
        if not bank_synced then ready,reason=false,"Waiting for wallet settlement." end
        model.shopGoods[#model.shopGoods+1]={id=good.id,category=good.category,name=tr(good.zh,good.en),
            pen=good.animal and ready and reason or nil,
            quantity=good.quantity,price=good.price,ready=ready,
            reason=not ready and ((lang=="zh" and error_translations[reason]) or reason) or nil}
    end
    local facility_names={}
    for _,project in ipairs(model.progression.expansion) do facility_names[project.id]=project.name end
    model.recipes,model.spellRecipes,model.spellFamilies={},{},{}
    for _,recipe in ipairs(NHStore.recipes) do
        local ready,reason,payment=NHStore.canStartBatch(state,recipe)
        local view={id=recipe.id,category=recipe.category,alchemyMode=recipe.alchemyMode,
            name=tr(recipe.zh,recipe.en),output=recipe.count or 1,
            inputs={},outputs={},catalysts={},note=recipe.noteZh and tr(recipe.noteZh,recipe.noteEn),
            duration=math.ceil(NHStore.productionFrames(recipe)/60),
            ready=ready,unlocked=reason~="Facility is locked." and reason~="Spell not unlocked in this save.",
            facility_name=facility_names[recipe.facility] or recipe.facility}
        if recipe.category=="spell" then
            local card=recipe.item
            view.actionId=card.card.id
            view.name=translated(card.name) or view.name
            view.spellType=recipe.spellType
            view.icon=card.icon
            local family=NHEssences.byAction[view.actionId]
            local list=model.spellRecipes[family]
            if not list then list={}; model.spellRecipes[family]=list end
            list[#list+1]=view
        end
        if reason=="Facility is locked." then
            view.reason=tr("需要先建造","Build first: ")..view.facility_name
        elseif not ready then
            view.reason=(lang=="zh" and error_translations[reason]) or reason
        end
        for _,input in ipairs(recipe.inputs) do
            local name=NHPotion.materialName(input.name,lang)
            local detail
            if input.alternatives then
                local group=input.labelZh and tr(input.labelZh,input.labelEn) or NHPotion.materialName(input.name)
                name=group..tr("（合计）"," (total)")
                local lines={payment and tr("库存 / 本批扣料","Stock / used this batch")
                    or tr("可混用，按优先顺序列出","Combined stock, in preferred order")}
                for _,key in ipairs(input.alternatives) do
                    local amount=string.format("%.0f",state.materials[key] or 0)
                    if payment then amount=amount..string.format(" / %.0f",payment[key] or 0) end
                    lines[#lines+1]=NHPotion.materialName(key,lang).."  "..amount
                end
                detail=table.concat(lines,"\n")
            end
            table.insert(view.inputs,{name=name,amount=input.amount,detail=detail,available=NHStore.ingredientStock(state,input)})
        end
        local resources={}
        for key in pairs(recipe.resources or {}) do resources[#resources+1]=key end
        table.sort(resources)
        for _,key in ipairs(resources) do
            local kind=NHEssences.types[key] or NHFarm.crops[key] or NHLivestock.resources[key]
            table.insert(view.inputs,{name=tr(kind.zh,kind.en),amount=recipe.resources[key],available=state.resources[key] or 0,
                essence=NHEssences.types[key] and key})
        end
        if recipe.storedIngredient then
            local kind=recipe.storedIngredient
            table.insert(view.inputs,{name=GameTextGetTranslatedOrNot("$nh_hideout_"..kind),amount=1,
                available=NHStore.warehouseIngredientCount(state,kind),detail=tr("消耗品仓库","Supplies storage")})
        end
        local held=state.order and state.order.recipe==recipe.id and state.order.catalysts
        for _,sample in ipairs(recipe.catalysts or {}) do
            table.insert(view.catalysts,{name=NHPotion.materialName(sample.name,lang),amount=sample.amount,
                available=state.materials[sample.name] or 0,held=held and held[sample.name] or 0})
        end
        for name,amount in pairs(recipe.materials or {}) do
            table.insert(view.outputs,{key=name,name=NHPotion.materialName(name),amount=amount})
        end
        table.sort(view.outputs,function(a,b) return a.key<b.key end)
        if recipe.emptyContainers then
            table.insert(view.inputs,{name=tr("仓库空容器","Empty containers"),amount=recipe.emptyContainers,
                available=NHStore.emptyContainerCount(state)})
        end
        table.insert(model.recipes,view)
        if state.order and recipe.id==(state.order.recipe or "stable") then model.order_name=view.name end
    end
    for _,entry in ipairs(model.essences) do
        if model.spellRecipes[entry.key] then
            model.spellFamilies[#model.spellFamilies+1]={id=entry.key,name=entry.name}
        end
    end
    if state.order and not model.order_name then
        local product=state.order.output.item
        model.order_name=translated(product and product.name) or tr("工坊订单","Workshop order")
    end
    model.pouchCapacity,model.maxUses=NHStore.pouchCapacity,NHStore.doseDurability
    model.order_active = state.order ~= false
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
                            if kind=="dose" then slot.remaining,slot.subtype=NHDoses.remaining(state,id) end
                            if kind=="pouch" then slot.pouchId=NHDoses.isPouch(state,id) end
                            if kind=="card_wallet" then
                                local row=NHCardWallets.carried(state,player,id)
                                slot.walletId=row and row.id
                            elseif kind=="summon_card" then
                                local card=NHCompanions.captureCard(id)
                                if card then slot.remaining,slot.species=card.remaining,card.species end
                            end
                            slot.icon = ComponentGetValue2(item,"ui_sprite")
                            if kind=="potion" then
                                slot.dockSlot=(EntityHasTag(id,"powder_stash") or slot.icon=="data/ui_gfx/items/material_pouch.png") and 2 or 1
                            end
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
    if popup.kind=="card_wallet" then
        return (not popup.slot or (GameIsInventoryOpen() and (popup.container=="safe" or near_home(player))))
            and NHCardWallets.get(state,player,popup)~=nil
    end
    local pouch=state.pouches[popup.id]
    if not pouch then return false end
    if popup.slot then
        return pouch.location==popup.container and pouch.slot==popup.slot and GameIsInventoryOpen()
            and (popup.container=="safe" or near_home(player))
    end
    return EntityGetIsAlive(popup.entity) and NHDoses.isPouch(state,popup.entity)==popup.id
        and EntityGetRootEntity(popup.entity)==player
end

local function matches_popup(player,id)
    return popup and popup.kind~="card_wallet" and popup.id==id and popup_accessible(player)
end

local function matches_wallet(player,id)
    return popup and popup.kind=="card_wallet" and popup.id==id and popup_accessible(player)
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

local function workshop_action(player,action,index)
    if not case_open or not GameIsInventoryOpen() or not near_home(player) then return end
    if action=="bank_transfer" and type(index)=="table" then
        local draft=active_draft()
        if not draft then return end
        local reason
        bank_synced,reason=NHBank.reconcile(draft,player)
        if not bank_synced then report(reason); return end
        local amount,problem=NHBank.prepare(draft,player,index)
        if not amount then report(problem); return end
        if not save(draft) then return end
        bank_synced,reason=NHBank.reconcile(state,player)
        if not bank_synced then report(reason); return end
        last_error,status=nil,""
    elseif action=="shop_buy" and type(index)=="table" then
        if not bank_synced then report("Waiting for wallet settlement."); return end
        if NHLivestock.species[index.id] then
            local now=NHFarm.observe(state,GameGetFrameNum())
            commit_edit(function(draft) return NHStore.buyGood(draft,index,now) end,
                "购买成功，幼畜已送入栏舍。","Purchased and delivered to the pen.")
        else commit_edit(NHStore.buyGood,"购买成功，商品已入库。","Purchased and delivered to storage.",index) end
    elseif action=="buy_upgrade" and type(index)=="table" then
        commit_edit(NHStore.buyUpgrade,"建设完成。","Construction complete.",index)
    elseif action=="farm_plant" and type(index)=="table" then
        local frame=GameGetFrameNum()
        local now=NHFarm.observe(state,frame)
        if commit_edit(function(draft) return NHFarm.plant(draft,index,now) end) then
            local crop=NHFarm.crops[index.crop]
            feedback(string.format(tr("田地 %d 下轮产出%s。","Field %d will produce %s next."),index.plot,tr(crop.zh,crop.en)))
            NHFarm.observe(state,frame)
        end
    elseif action=="salvage" and type(index)=="table" then
        if index.mode=="essence" then
            commit_edit(NHStore.salvage,"提取完成，精华已入库。","Essence extracted and stored.",index)
        else
            commit_edit(NHStore.salvage,"拆解完成，碎片已入库。","Item dismantled. Scrap stored.",index)
        end
    elseif action=="order" or (action=="craft" and index and index.id) then
        if commit_edit(NHStore.startOrder,"已扣除原料，开始生产。","Ingredients consumed. Production started.",index and index.id) then
            NHClock.observe(state,GameGetFrameNum())
        end
    elseif ModSettingGet("noita_hideout.test_tools") ~= false then
        if action == "restock" then
            commit_edit(NHStore.restock, "测试针剂包已重发，内有两支。", "Test pouch reissued with two doses.")
        elseif action == "test_cards" then
            if commit_edit(NHCompanions.grantSet) then
                feedback(NHCompanions.rewardText(NHCompanions.order,lang,state))
            end
        elseif action == "test_wallet" then
            commit_edit(NHStore.grantTestWallet,"空卡片夹已放入装备库。","Empty card wallet delivered to equipment storage.")
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

local function dispatch(player, action, index)
    if not opened or not active_run() then return end
    if case_open or popup then
        if action=="close_container" then
            popup=nil
            if not case_open then close_panel() end
            return
        end
        if type(index)~="table" or action=="buy_upgrade" or action=="craft" or action=="salvage"
            or action=="bank_transfer" or action=="shop_buy" or action=="farm_plant" then
            workshop_action(player,action,index)
            return
        end
        if action=="equip_perk" or action=="unequip_perk" or action=="pack_perk" then
            if not case_open or not GameIsInventoryOpen() then return end
            if action=="pack_perk" then
                local ok,reason=NHPerks.pack(state,player,index.entity)
                if ok then feedback(tr("特质已封装，可在脚边拾取。","Packed perk dropped at your feet."))
                else report(reason) end
                return
            end
        end
        local container=index.container or "safe"
        if container~="safe" and container~="warehouse" and container~="docks" then return end
        if container~="safe" and not (case_open and GameIsInventoryOpen() and near_home(player)) then return end
        if action=="equip_stored_perk" or action=="store_equipped_perk" then
            if not case_open or not GameIsInventoryOpen() or (container~="safe" and container~="warehouse") then return end
            local move=action=="equip_stored_perk" and NHPerks.equipStored or NHPerks.storeEquipped
            local ok,reason=move(state,player,index)
            if not ok then transfer_error(reason) else status="" end
            return
        end
        if container=="docks" then
            if action=="material_transfer" then
                commit_edit(NHPotion.transferMaterial,nil,nil,index)
                return
            elseif action=="move_dock" then
                local from,to=index.source,index.destination
                if not ((from=="docks" and (to=="safe" or to=="warehouse"))
                    or (to=="docks" and (from=="safe" or from=="warehouse"))) then return end
                commit_edit(function(draft)
                    local i=NHStore.slotIndex(draft,from,index.from,"potion")
                    local row=i and draft[from][i]
                    if not row or row.id~=index.entity or row.item.kind~="potion"
                        or not NHStore.freeSlot(draft,to,index.safeSlot,"potion") then return false,"Inventory slot changed." end
                    if to=="docks" and NHPotion.dockSlot(row.item)~=index.safeSlot then return false,"Wrong loading slot." end
                    table.remove(draft[from],i)
                    row.slot=index.safeSlot
                    table.insert(draft[to],row)
                    return true
                end)
                return
            elseif action~="cancel_native" and not ((action=="place" or action=="secure_withdraw") and index.kind=="potion") then return end
        end
        if action=="open_container" then
            if index.kind=="card_wallet" then
                local ref={kind="card_wallet",id=index.walletId,slot=index.safeSlot,container=container}
                if not ref.slot then ref.entity=index.entity end
                if ref.id and (not ref.slot or (case_open and GameIsInventoryOpen())) and NHCardWallets.get(state,player,ref) then popup=ref end
                return
            end
            if not index.pouchId then return end
            if index.safeSlot then
                local pouch=NHPouches.at(state,container,index.safeSlot)
                if case_open and GameIsInventoryOpen() and pouch and pouch.id==index.pouchId then
                    popup={id=pouch.id,slot=pouch.slot,container=container}
                end
            elseif index.entity and NHDoses.isPouch(state,index.entity)==index.pouchId and EntityGetRootEntity(index.entity)==player then
                popup={id=index.pouchId,entity=index.entity}
            end
            return
        end
        if action=="move_wallet_card" then
            if not matches_wallet(player,index.walletId) then return end
            if (not index.sourceCell or not index.targetCell) and not (case_open and GameIsInventoryOpen()) then return end
            local source=index.sourceCell and {cell=index.sourceCell,species=index.species,remaining=index.remaining,count=index.count}
                or {container=container,slot=index.from,id=index.entity}
            local target=index.targetCell and {cell=index.targetCell} or {container=container,slot=index.safeSlot}
            local ok,reason=NHCardWallets.move(state,player,popup,source,target)
            if ok then status="" else transfer_error(reason) end
            return
        end
        if action=="move_stored_card" or action=="move_wallet" then
            local from,to=index.source,index.destination
            if not case_open or not GameIsInventoryOpen() or (from~="safe" and from~="warehouse")
                or (to~="safe" and to~="warehouse") or ((from=="warehouse" or to=="warehouse") and not near_home(player)) then return end
            if action=="move_stored_card" then
                commit_edit(function(draft)
                    return NHCompanions.moveCard(draft,from,index.from,to,index.safeSlot,index.entity)
                end)
            else
                local moved=commit_edit(function(draft)
                    local at=NHStore.slotIndex(draft,from,index.from,"card_wallet")
                    local row=at and draft[from][at]
                    if not row or row.id~=index.entity or row.item.kind~="card_wallet"
                        or not NHStore.freeSlot(draft,to,index.safeSlot,"card_wallet") then return false,"Inventory slot changed." end
                    table.remove(draft[from],at)
                    row.slot=index.safeSlot
                    table.insert(draft[to],row)
                    return true
                end)
                if moved and popup and popup.kind=="card_wallet" and popup.id==index.entity then
                    popup={kind="card_wallet",id=index.entity,container=to,slot=index.safeSlot}
                end
            end
            return
        end
        if action=="unpack_dose" or action=="pack_dose" or action=="move_cell" then
            if not matches_popup(player,index.pouchId) then return end
            local ok,reason
            if action=="move_cell" then ok,reason=NHDoses.moveCell(state,index.sourceCell,index.targetCell,popup.id)
            else ok,reason=NHDoses.moveDose(state,index.safeSlot,action=="unpack_dose",index.sourceCell or index.targetCell,container,popup.id) end
            if not ok then report(reason) else status="" end
            return
        end
        if action=="move_safe_dose" then
            local ok,reason=NHDoses.moveSafeDose(state,index.from,index.safeSlot,container)
            if not ok then report(reason) else status="" end
            return
        end
        if action=="move_pouch" then
            local from,to=index.source,index.destination
            if not case_open or not GameIsInventoryOpen() or not index.safeSlot
                or (from~="warehouse" and from~="safe") or (to~="warehouse" and to~="safe")
                or ((from=="warehouse" or to=="warehouse") and not near_home(player)) then return end
            local moved=commit_edit(function(draft)
                local pouch=NHPouches.at(draft,from,index.from)
                if not pouch or pouch.id~=index.pouchId or not NHStore.freeSlot(draft,to,index.safeSlot,"pouch") then
                    return false,"Inventory slot changed."
                end
                pouch.location,pouch.slot=to,index.safeSlot
                return true
            end)
            if moved and popup and popup.id==index.pouchId then
                popup={id=index.pouchId,container=to,slot=index.safeSlot}
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
        if action=="place" or action=="cancel_native" or action=="equip_perk" then
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
            if action=="equip_perk" then
                ok,result=NHPerks.equip(state,player,id,index.safeSlot,slot)
                if not ok then report(result) else status="" end
                return
            end
            local kind = NHNative.kind(id)
            if index.walletId and index.targetCell then
                if not matches_wallet(player,index.walletId) then return end
                ok,result=NHCardWallets.move(state,player,popup,{entity=id},{cell=index.targetCell})
            elseif container=="docks" then ok,result=NHTransfers.deposit(state,player,container,id,index.safeSlot)
            elseif kind=="pouch" and index.safeSlot then ok,result=NHDoses.storePouch(state,player,id,index.safeSlot,container)
            elseif kind=="dose" then
                if not index.safeSlot and not (index.intoContainer and matches_popup(player,index.pouchId)) then return end
                ok,result=NHDoses.deposit(state,player,id,index.safeSlot,index.targetCell,container,index.pouchId)
            else ok,result=NHTransfers.deposit(state,player,container,id,index.safeSlot) end
        else
            if slot.entity then return end
            local function deliver(id) return place_in_slot(player,id,slot) end
            if action=="unequip_perk" then
                ok,result=NHPerks.unequip(state,player,index.safeSlot,index.storedId,slot)
                if not ok then report(result) else status="" end
                return
            elseif action=="take_pouch" then
                local pouch=NHPouches.at(state,container,index.safeSlot)
                if not pouch or pouch.id~=index.pouchId then return end
                ok,result=NHDoses.takePouch(state,player,deliver,pouch.id)
            elseif action=="take_card" then
                if not matches_wallet(player,index.walletId) then return end
                ok,result=NHCardWallets.move(state,player,popup,
                    {cell=index.sourceCell,species=index.species,remaining=index.remaining,count=index.count},{deliver=deliver})
            elseif action=="take_dose" then
                if not matches_popup(player,index.pouchId) then return end
                ok,result=NHDoses.withdraw(state,player,deliver,popup.entity,nil,index.sourceCell,container,popup.id)
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
    NHClock.reset()
    NHFarm.resetClock()
    NHHomeWandEdit.reset()
    bank_synced=false
    next_room_check,pending_visit=0,nil
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
    NHHomeWandEdit.update(player,near_home(player))
    if attach() and active_run() then
        NHClock.observe(state,GameGetFrameNum())
        NHFarm.observe(state,GameGetFrameNum())
        NHPerks.update(state,player)
    end
end

function OnPausedChanged(is_paused,is_inventory_pause)
    -- The pause menu can start a fresh world before the next regular checkpoint.
    if not is_paused or is_inventory_pause or not active_run() then return end
    local now=NHFarm.observe(state,GameGetFrameNum())
    if now<=state.farm.time and not NHFarm.due(state,now) and not NHAffinity.changed(state) then return end
    local draft=active_draft()
    if not draft then return end
    local _,produced,cards=NHFarm.sync(draft,now)
    if save(draft,not produced) and cards and #cards>0 then feedback(NHCompanions.rewardText(cards,lang,state)) end
end

local function current_player()
    if player_id and EntityGetIsAlive(player_id) and EntityHasTag(player_id, "player_unit") then return player_id end
    player_id = (EntityGetWithTag("player_unit") or {})[1]
    return player_id
end

function OnWorldPreUpdate()
    local player = current_player()
    if player then set_home(player,false) end
    NHHomeWandEdit.update(player,player and (not state or active_run()) and near_home(player))
    if not opened and not mouse_release then return end
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
    local traveler=player or (EntityGetWithTag("polymorphed_player") or {})[1]
    if not run_id and not traveler then return end
    if not attach() or not active_run() then return end
    local frame = GameGetFrameNum()
    if not traveler then NHClock.suspend(); NHFarm.suspendClock(); opened,case_open=false,nil; return end
    if player and not bank_synced then
        local reason
        bank_synced,reason=NHBank.reconcile(state,player)
        if bank_synced then model_cache=nil else report(reason) end
    end
    local farm_time=NHFarm.observe(state,frame)
    if not update_workshop(traveler,frame,farm_time) then return end
    if not player then opened,case_open=false,nil; return end
    local inventory_open = GameIsInventoryOpen()
    local used = NHNative.pressed(player, inventory_open or opened or mouse_release)
    if frame % 60 == 0 then
        local ok, err = NHTransfers.reconcile(state, player)
        if ok then ok, err = NHDoses.reconcile(state, player) end
        if ok then NHPerks.update(state,player) end
        if not ok then invalidate(); report(err); return end
    end
    local nearby = near_home(player)
    local was_open,was_case_open = opened,case_open
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
    elseif used then
        local item = NHNative.held(player)
        local kind = NHNative.kind(item)
        if kind == "pouch" then
            local id=NHDoses.isPouch(state,item)
            if id then opened,popup=true,{id=id,entity=item} end
        elseif item and EntityHasTag(item,"noita_hideout_card_wallet") then
            local row=NHCardWallets.carried(state,player,item)
            if row then opened,popup=true,{kind="card_wallet",id=row.id,entity=item} end
        elseif kind == "dose" then use_dose(player, item)
        elseif item and (NHCompanions.use(player,item,lang) or NHProducts.use(player,item)) then mouse_release=true end
    end
    if not active_run() then return end
    -- Discoveries made outside the hideout can unlock vanilla spells without changing its inventory.
    if case_open and (not was_case_open or (nearby and model_cache and not model_cache.near)) then model_cache=nil end
    local model = opened and inventory_view() or {}
    if opened and nearby then
        model.bankGold=state.bankGold
        model.walletGold,model.walletInfinite=NHBank.wallet(player)
        if not bank_synced then model.walletGold=nil end
        model.farm=NHFarm.view(state,lang,farm_time)
    end
    if opened and state.order then
        model.order_remaining=math.ceil((state.order.required-NHClock.observe(state,frame))/60)
    end
    if opened and (case_open or popup) then model.native_slots = native_slots(player) end
    model.popup = popup ~= nil
    model.walletId,model.pouchId,model.cells,model.pouchName=nil,nil,nil,nil
    if popup and popup.kind=="card_wallet" then
        local wallet=NHCardWallets.get(state,player,popup)
        model.walletId,model.pouchName=popup.id,tr("卡片夹","Card wallet").." #"..popup.id
        model.cells=wallet.item.cells or {}
        model.walletCapacity=NHCardWallets.capacity
    elseif popup then
        model.pouchId,model.pouchName=popup.id,pouch_name(popup.id)
        model.cells=state.pouches[popup.id].cells
    end
    model.mode = case_open and "case" or (popup and "container" or "closed")
    model.open, model.near, model.lang, model.status = opened, nearby, lang, status

    if case_open then NHPerks.view(state,player,model) end
    model.debug = opened and ModSettingGet("noita_hideout.test_tools") ~= false
    model.active = opened and find_stimulant(player) ~= nil
    NHUI.draw(model, function(action, index)
        -- Ignore transfers on the frame that opens the panel.
        if was_open and opened and (not case_open or was_case_open) then dispatch(player, action, index) end
    end)
end

function OnPlayerDied()
    NHHomeWandEdit.update(nil,false)
    popup=nil
    opened, case_open = false, nil
    if GlobalsGetValue(run_key, "") == "" then return end
    next_attempt = 0
    if not attach() or not active_run() then return end
    local elapsed=NHClock.observe(state,GameGetFrameNum())
    local farm_time=NHFarm.observe(state,GameGetFrameNum())
    local order_id=state.order and state.order.id or false
    commit_edit(function(draft)
        NHStore.advanceProduction(draft,{run=run_id,orderId=order_id,progress=elapsed,checkpoint=pending_visit})
        NHFarm.sync(draft,farm_time)
        return NHStore.endRun(draft,run_id)
    end)
end
