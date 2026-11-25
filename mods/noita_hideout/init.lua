local files = "mods/noita_hideout/files/"
NHEW=dofile(files.."ew.lua")
if ModIsEnabled and ModIsEnabled("quant.ew") and dofile(files.."ew_wait_peer.lua").install() then
    dofile(files.."ew_reinforce_patch.lua").install()
end
local expeditions=dofile(files.."ew_expeditions.lua")
dofile_once(files.."ew_items.lua")
local storm = dofile(files .. "storm/runtime.lua")
dofile_once(files .. "store.lua")
dofile_once(files .. "bank.lua")
dofile_once(files .. "workshop_clock.lua")
local mountain_storage=dofile(files .. "mountain_storage.lua")
local terminals=dofile(files .. "terminals/station.lua")
local remoteTerminal=dofile(files .. "terminals/remote.lua")
local travel=dofile(files.."travel/network.lua")
travel.setMultiplayer(NHEW)
local terminalAccess=dofile(files.."terminals/access.lua")
local fireSupport=dofile(files.."fire_support.lua")
dofile_once(files .. "home_wand_edit.lua")
dofile_once(files .. "wand.lua")
dofile_once(files .. "potion.lua")
dofile_once(files .. "transfers.lua")
dofile_once(files .. "ew_deposit.lua")
NHInventoryUse=dofile(files .. "inventory_use.lua")
NHCompanions.registerItems()
NHCardWallets.registerItem()
NHRelics.registerItems()
NHTablets.register()
NHNativeValuables.register()
NHRedRelics.register()
NHSalvageBell=dofile(files.."salvage_bell.lua")
NHRewind=dofile(files.."rewind_watch.lua")
NHStormProducts.register()
dofile_once(files .. "products.lua")
NHFirearms.registerItems()
NHKatanas.registerItems()
NHSurgeryCleanse=dofile(files .. "surgery_cleanse.lua")
NHSurgery=dofile(files .. "surgery.lua")
dofile_once(files .. "perks.lua")
dofile_once(files .. "native_items.lua")
dofile_once(files .. "doses.lua")
local pickup=dofile(files .. "pickup.lua")
local migrateGroundItems,migrateSupportGuns
local deliverGift=dofile(files.."companions/gifts.lua")
local rescue=dofile(files.."rescue.lua")
local turretRuntime=dofile(files.."turret_runtime.lua")
local tarotRuntime=dofile(files.."tarot_runtime.lua")
local tarotSight=dofile(files.."tarot_sight.lua")
local shieldRuntime=dofile(files .. "shield_runtime.lua")
local ammoRuntime=dofile(files .. "ammo_runtime.lua")
local katanaRuntime=dofile(files.."katana_runtime.lua")
dofile_once(files .. "ui.lua")
NHNative.registerTranslations()

local deathScript=files.."enemy_loot.lua"
-- EW enumerates extra modules in its OnModInit, including when it loads first.
function OnModPreInit()
    if ModIsEnabled("quant.ew") then
        local modules="mods/quant.ew/files/api/extra_modules.lua"
        ModLuaFileAppend(modules,files.."ew_module.lua")
        ModLuaFileAppend(modules,files.."ew_claim.lua")
        ModLuaFileAppend(modules,files.."ew_reinforce_rpc.lua")
        ModLuaFileAppend(modules,files.."ew_reinforce_fx.lua")
        ModLuaFileAppend(modules,files.."tarot_vitality_ew.lua")
        ModLuaFileAppend(modules,files.."tarot_shared_health_ew.lua")
        ModLuaFileAppend(modules,files.."salvage_bell_ew.lua")
        ModLuaFileAppend(modules,files.."loot_bonuses_ew.lua")
        ModLuaFileAppend(modules,files.."katana_ew.lua")
    end
end
function OnModInit()
    dofile(files .. "storm/register.lua")
    ModRegisterAudioEventMappings(files.."reactor_audio/events.txt")
    dofile(files .. "loot_spawn_sources.lua")()
    ammoRuntime.registerStaff()
    NHFirearms.modes.register(NHFirearms.mods)
    ModLuaFileAppend("data/scripts/gun/gun_actions.lua",files.."firearm_actions.lua")
    ModLuaFileAppend("data/scripts/items/gold_pickup.lua",files.."ammo_gold.lua")
    for _,base in ipairs({"basic","flying","robot","robot_boss_limbs"}) do
        local path="data/entities/base_enemy_"..base..".xml"
        local xml=ModTextFileGetContent(path)
        if xml and xml:match("</Entity>%s*$") and not xml:find(deathScript,1,true) then
            local hook='<LuaComponent _tags="nh_bag_drop" script_death="'..deathScript..'" execute_every_n_frame="-1" />'
            ModTextFileSetContent(path,(xml:gsub("</Entity>%s*$",hook.."</Entity>")))
        end
    end
    NHWand.registerTemplates()
    NHPotion.readTemplates()
end

function OnModPostInit()
    dofile(files.."tarot_sight_shader.lua")
    if not ModIsEnabled("new_enemies") then return end
    dofile(files.."tarot_sight_ne.lua")()
    local path = "data/entities/misc/healthbar_dummy.xml"
    if not ModDoesFileExist(path) then return end
    local xml = ModTextFileGetContent(path)
    if not xml then return end

    -- New Enemies fills the proxy after EntityLoad returns. Its old one-frame
    -- lifetime ends before a LuaComponent can check what the registry supplied.
    local seeded = xml:gsub("<DamageModelComponent%s[^>]*>", function(tag)
        if tag:find('%swait_for_kill_flag_on_death="1"') and not tag:find("%smax_hp%s*=") then
            return (tag:gsub('%shp="0"', ' hp="1" max_hp="1"', 1))
        end
    end, 1)
    if seeded == xml then return end
    local fixed, lifetime = seeded:gsub('(<LifetimeComponent%s+)lifetime="1"(%s*/>)', '%1lifetime="2"%2', 1)
    local guard = '<LuaComponent script_source_file="' .. files .. 'enemy_proxy_healthbar.lua" execute_every_n_frame="1" />'
    local bars
    fixed, bars = fixed:gsub('<BossHealthBarComponent%s+in_world="1"%s*/>',
        '<BossHealthBarComponent _enabled="0" gui="0" in_world="0" />' .. guard, 1)
    if lifetime == 1 and bars == 1 then ModTextFileSetContent(path, fixed) end
end

local run_key = "noita_hideout_run_v1"
local home_x_key, home_y_key = "noita_hideout_origin_x", "noita_hideout_origin_y"
local state, run_id, home_x, home_y, player_id
local popup
local opened, mouse_release, case_open = false, false, nil
local lang, status, last_error = "en", "", nil
local model_cache, next_attempt = nil, 0
local last_dose_frame = -1
local left_down,fire_request=false,nil
local collectible_fire_down=false
local quick_click_player
local last_pickup_press
local right_use
-- A paid link belongs to this player and lasts through one opening of the native inventory.
local inventory_aim={x=1,y=0}
local next_room_check,pending_visits=0,{}
local blocked_production
local bank_synced=false
local wallet_allowed
local waiting_since,waiting_notice,waiting_profile

local function tr(zh, en)
    return lang == "zh" and zh or en
end

local error_translations = {
    ["A charged shield is required."]="请装备至少还有半格充能的护盾。",
    ["Not enough shield charge."]="护盾充能不足，开启斩夺需要半格护盾。",
    ["Pick up this item before storing it."]="请先用原版交互拾取，再从自己的物品栏存入。",
    ["The original owner must handle this legacy item."]="这件旧物品的来源无法在联机中确认，已保留原物。",
    ["This container belongs to another profile."]="这只容器的内容保存在另一位玩家的档案中，已保留原物。",
    ["A free personal inventory slot is required."]="请先腾出一个个人物品栏位。",
    ["Waiting for item ownership. Try again."]="正在等待房主确认物品归属，请稍后重试。",
    ["Another player claimed this item."]="另一位玩家已预留或存入这件物品。",
    ["Another deposit is pending."]="已有一件物品正在入库，请先完成或取消。",
    ["Could not lock this item for deposit."]="无法锁定这件物品，已停止入库。",
    ["Not enough room in the hideout profile to finish this deposit."]="藏身处档案空间不足，无法完成这次入库。",
    ["The item could not be stored."]="这件物品未能入库。",
    ["The selected item changed before deposit."]="物品已发生变化，已停止入库。",
    ["The item could not be located."]="未找到申请入库的原物。",
    ["Could not verify a local deposit receipt. The item remains locked."]="暂时无法核实本机的入库记录，物品仍由藏身处保管。",
    ["Storage access is no longer available."]="已离开存取范围，入库申请已撤销。",
    ["Destination is no longer accessible."]="当前无法使用原先选定的存入位置。",
    ["Item ownership could not be verified."]="无法核实这件物品的联机归属，已保留原物。",
    ["Entangled Worlds handles player death."]="EW 接管联机死亡判定，已有保单和同伴会保留。",
    ["Wallet transfers are unavailable with shared gold."]="EW 共享金币或连接待确认期间，私人银行暂停存取。",
    ["Spell recipe unavailable."]="尚未解锁此法术的合成配方。",
    ["Fire support unavailable."]="请装备数据链并建造火力支援站。",
    ["No clear strike path."]="目标附近没有可用弹道，请重新标记。",
    ["Supply support unavailable."]="请装备数据链并建造补给支援站。",
    ["Not enough supply logistics packs."]="补给资源包不足。",
    ["Not enough intel logistics packs."]="情报资源包不足。",
    ["Not enough reinforcement logistics packs."]="增援资源包不足。",
    ["No room for reinforcement."]="身边没有足够空间部署增援。",
    ["Reinforcement deployment failed."]="增援部署失败。",
    ["Support station level too low."]="当前支援站等级不足。",
    ["Radar already active."]="该雷达已生效。",
    ["Recon scan failed."]="探查启动失败。",
    ["Data link unavailable."]="数据链连接已中断。",
    ["This Kammi has already been activated."]="卡密已经启动。",
    ["Item unavailable."]="物品当前无法存取。",
    ["No clear supply landing site."]="附近没有可供补给舱降落的空地。",
    ["Supply pod could not open."]="补给箱未能全部弹出，本次投送未扣费。",
    ["Not enough strike logistics packs."]="轰炸资源包不足，轰炸未发射。",
    ["Kennel is required."] = "请先建造狗窝。",
    ["Cattery is required."] = "请先建造猫窝。",
    ["Invalid loot stack."] = "战利品容器数量无效。",
    ["Invalid bandage count."] = "绷带的剩余卷数无效。",
    ["Invalid throwable count."] = "投掷物的剩余数量无效。",
    ["Need a free slot for the used item."] = "需要一个空格存放使用后的物品。",
    ["Invalid medkit."] = "医疗包的剩余次数无效。",
    ["Invalid surgery kit."] = "手术包的使用次数无效。",
    ["Equipment slot occupied."] = "装备槽已占用，请先取出。",
    ["Shield or charger unavailable."] = "请先装上护盾和充能器。",
    ["No broken shield cell."] = "护盾没有碎格，已保留充能器。",
    ["Invalid shield equipment."] = "护盾的储能记录无效。",
    ["Relic unavailable."] = "此物品无法装入这个遗物插槽。",
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
    ["No free destination slot."] = "没有可接收这件物品的栏位。",
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
    ["Beehive is required."] = "请先建造蜂箱。",
    ["Dragon nest is required."] = "请先建造龙巢。",
    ["Gel pool is required."] = "请先建造凝胶池。",
    ["No matching pen is free."] = "这种幼畜的栏舍已满。",
    ["Livestock collection changed."] = "栏舍已变化，请重新选择。",
    ["Missing catalyst."] = "物料库中缺少所需的催化样品。",
    ["Invalid gold transfer."] = "无法识别这笔存取操作。",
    ["Invalid gold amount."] = "请输入有效的金币数额。",
    ["Not enough carried gold."] = "随身金币不足。",
    ["Not enough stored gold."] = "存钱罐余额不足。",
    ["Unknown shop item."] = "找不到这项转化。",
    ["Not enough hideout resources."] = "藏身处资源不足，请先在消耗品页转入资源。",
    ["Invalid supply trade."] = "此物品不支持这项交易。",
    ["Supplies storage is full."] = "消耗品仓库没有空格。",
    ["Equipment storage is full."] = "装备仓库没有空格。",
    ["Item ID limit reached."] = "藏身处无法再分配新的物品编号。",
    ["Wallet is full."] = "钱包余额已达上限。",
    ["Piggy bank is full."] = "存钱罐余额已达上限。",
    ["Wallet unavailable."] = "当前钱包无法存取金币。",
    ["Gold transfer exceeds the exact integer range."] = "这笔转账超过可精确记录的金额。",
    ["Already insured."] = "已投保，一次救援后可再次购买。",
    ["Not enough arcane scrap."] = "奥术碎片不足。",
    ["Insurance policy changed."] = "保单已变更。",
    ["Invalid wallet receipt."] = "钱包转账记录异常。",
    ["Could not record the wallet transfer."] = "钱包转账记录写入失败，将重试。",
    ["Could not update the wallet."] = "钱包写入失败，将重试。",
    ["Waiting for wallet settlement."] = "待随身金币或钱包空间足够后，将继续结算。",
    ["Not enough empty containers."] = "容器仓库里可用的空容器不足。",
    ["Only empty containers can be dismantled."] = "只能拆解仓库内已清空的普通物料容器。",
    ["No essence for this spell."] = "这张法术没有对应的精华。",
    ["Resource storage is full."] = "这项资源的库存已满。",
    ["Invalid salvage mode."] = "无法识别所选的拆解方式。",
    ["Collectible exhausted."] = "这件藏品的耐久已耗尽，仍可在藏品页全额分解。",
    ["Collection needs room for the reward cards."] = "藏品页空间不足，请为奖励卡腾出位置后重试。",
    ["Rewind already active."] = "倒流表已经启动。",
    ["Field already active."] = "这件遗物的领域仍在生效。",
    ["Reactor already active."] = "堆芯直通仍在生效。",
    ["Shared health cannot be rewound."] = "EW 共享血量模式下无法启动倒流表。",
    ["Rewind unavailable."] = "当前无法记录倒流锚点。",
    ["Bell sync unavailable."] = "联机打捞钟尚未就绪，请稍后重试。",
    ["The selected item is no longer in your quick inventory."] = "这件物品已经离开快捷栏。",
    ["The case is already in your inventory."] = "安全箱就在你的道具栏里。",
    ["The case is already within reach."] = "安全箱就在附近，可按 G 开箱。",
    ["No dose available."] = "针剂包已空。",
    ["Pouch unavailable."] = "这只针剂包已不在原处。",
    ["Could not mark the pouch."] = "未能标记这只针剂包。",
    ["Hold your injector pouch first."] = "请先取回这只针剂包。",
    ["Secure valuables slot is full."] = "贵重物品格已满。",
    ["This syringe is no longer available."] = "这支针剂已经用掉或收回。",
    ["Could not create the stimulant effect."] = "无法创建激活剂效果。",
    ["Health is full."] = "生命值已满。",
    ["Unknown hideout item."] = "未能识别这件藏身处物品。",
    ["Only a recognized ordinary flask can be stored"] = "未能识别这个瓶子的类型。",
    ["This flask has attachments that cannot be restored"] = "药瓶带有无法还原的附件，已保留原瓶。",
    ["Unsupported flask script"] = "药瓶带有无法还原的脚本，已保留原瓶",
    ["Unsupported flask state"] = "药瓶带有无法还原的自定义状态，已保留原瓶",
    ["Unsupported flask component"] = "药瓶带有无法还原的组件，已保留原瓶",
    ["Duplicate ItemAIKnowledgeComponent"] = "物品带有重复的 AI 识别组件，无法确认应使用哪一份。",
    ["Cannot inspect ItemAIKnowledgeComponent"] = "无法读取物品的 AI 识别组件。",
    ["Unsupported item AI field"] = "物品的 AI 识别组件包含尚未支持的字段",
    ["Invalid item AI field"] = "无法准确读取物品的 AI 识别字段",
    ["Invalid stored item AI knowledge"] = "库存中的物品 AI 识别记录无效。",
    ["Could not restore ItemAIKnowledgeComponent"] = "无法在取出的物品上还原 AI 识别组件。",
    ["Item AI readback mismatch"] = "取出时 AI 识别状态未能正确还原",
    ["Unsupported flask tag"] = "药瓶带有无法还原的标签，已保留原瓶",
    ["Cannot inspect flask components"] = "无法检查药瓶的组件，已保留原瓶。",
    ["Cannot inspect flask script"] = "无法检查药瓶脚本，已保留原瓶。",
    ["This flask still has a shop price"] = "这只药瓶仍带有商店价格。",
    ["Flask contains a quantity that cannot be restored exactly"] = "这瓶药水的余量无法精确还原，已保留原瓶。",
    ["Unsupported wand template"] = "未适配的魔杖模板",
    ["Unknown wand template"] = "未能识别魔杖模板",
    ["Unsupported wand script"] = "魔杖带有无法还原的脚本",
    ["Duplicate wand shop pickup effect."] = "魔杖带有重复的商店拾取特效。",
    ["Could not verify the shop pickup effect."] = "无法核实商店拾取特效。",
    ["Invalid wand shop pickup state."] = "魔杖的商店拾取特效状态无效。",
    ["Unsupported wand component"] = "魔杖带有无法还原的组件",
    ["Unsupported wand variable"] = "魔杖带有无法还原的状态",
    ["Wand is still generating"] = "魔杖仍在生成，请稍后重试",
    ["Cannot store a wand with an outstanding shop price"] = "这根魔杖仍带有商店价格。",
    ["Missing flask component"] = "瓶子缺少必要组件",
    ["Unsupported wand attachment"] = "魔杖带有无法还原的附件",
    ["Unsupported spell script"] = "法术带有无法还原的脚本",
    ["Unsupported spell attachment"] = "法术带有无法还原的附件",
    ["Unsupported spell variable"] = "法术带有无法还原的状态",
    ["Could not verify the original hitbox after Unseen."] = "无法确认原碰撞框，已保留原物。",
    ["Wait for Unseen or Swallowed to wear off before storing this item."] = "请等隐形或吞噬效果结束后再存入。",
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
        NHUI.notify(status,true)
        GamePrint("[Hideout] " .. status)
        print("[noita_hideout] " .. raw)
    end
end

local function feedback(message)
    last_error, status = nil, message
    NHUI.notify(message)
end

local function surgery_feedback(result,kind)
    if NHMedkits.types[kind] then
        if result=="completed" then feedback(tr("包扎完成。","Treatment complete."))
        elseif result=="interrupted" then feedback(tr("治疗中断，使用次数已保留。","Treatment interrupted. Use kept.")) end
        return
    end
    if NHFirearms.packs[kind] then
        if result=="completed" then feedback(tr("备弹已补入弹挂。","Ammo rig resupplied."))
        elseif result=="interrupted" then feedback(tr("补弹中断，已保留耐久。","Resupply interrupted. Use kept.")) end
        return
    end
    if NHShields.chargers[kind] then
        if result=="interrupted" then feedback(tr("充能中断，已保留耐久。","Charging interrupted. Use kept."))
        elseif result=="completed" then feedback(tr("碎盾已修复。","Shield repaired."))
        elseif result=="unneeded" then feedback(tr("没有碎盾需要修复。","No broken shield cell.")) end
        return
    end
    if result=="interrupted" then feedback(tr("手术中断，手术包已保留。","Surgery interrupted. Kit kept."))
    elseif result=="completed" then feedback(tr("手术完成。","Surgery complete."))
    elseif result=="unneeded" then feedback(tr("生命已满，无需手术。","At full health with no condition to treat.")) end
end

local function invalidate()
    state, run_id, model_cache = nil, nil, nil
    bank_synced=false
    next_attempt = GameGetFrameNum() + 60
end

local function save(draft,only_time,passive)
    local cached=only_time and model_cache
    if cached and cached.profile_revision~=draft.revision then cached=nil end
    NHAffinity.sync(draft)
    shieldRuntime.snapshot(draft,player_id)
    local ok, err = NHStore.commit(draft)
    if not ok then
        if passive and tostring(err):find("1 MiB",1,true) then
            blocked_production={profile=draft.profile,run=draft.runSerial,revision=draft.revision}
            if state.revision~=draft.revision then
                local saved=NHStore.load()
                if saved and saved.profile==draft.profile and saved.runSerial==draft.runSerial
                    and saved.ewActive==draft.ewActive then state,model_cache=saved,nil end
            end
            report(tr("个人档案已达 1 MiB 上限。生产进度已暂存，取出仓库物品腾出空间后将重新结算。",
                "Profile at its 1 MiB limit. Production is queued. Withdraw stored items to make room."))
            return false,"capacity"
        end
        invalidate(); report(err); return false
    end
    NHCompanions.checkpointProduction(draft)
    if cached then cached.profile_revision=draft.revision end
    state, model_cache = draft, cached or nil
    return true
end

local function confirmed_world(profile)
    if NHEW.bind(profile) and NHEW.ready() then return NHEW.world() end
    local frame=GameGetFrameNum()
    waiting_since=waiting_since or frame
    if frame-waiting_since>=300 and not waiting_notice then
        GamePrint(tr("藏身处等待联机确认，请检查双方的 EW 和藏身处版本。",
            "Hideout is waiting for the host. Check that everyone's EW and Hideout versions match."))
        waiting_notice=true
    end
end

-- A solo run stages its token before allocating a serial. A multiplayer run
-- selects a local expedition journal after the host confirms its world.
local function attach()
    if state and run_id then
        local world=NHEW.enabled() and NHEW.world()
        if not world or state.ewActive==world then return true end
        invalidate()
        next_attempt=0
        NHClock.reset()
        NHFarm.resetClock()
        NHCompanions.resetProduction()
        pending_visits,blocked_production,popup,case_open,opened={},nil,nil,nil,false
    end
    if GameGetFrameNum() < next_attempt then return false end
    next_attempt = GameGetFrameNum() + 60
    local scope
    if waiting_profile then
        scope=confirmed_world(waiting_profile)
        if not scope then return false end
    end
    local draft, err = NHStore.load()
    if not draft then report(err); return false end
    if NHEW.enabled() and waiting_profile~=draft.profile then
        waiting_profile=draft.profile
        scope=confirmed_world(waiting_profile)
        if not scope then return false end
    end
    if expeditions.select(draft,scope) then
        local ok,reason=NHStore.commit(draft)
        if not ok then report(reason); return false end
    end
    local token = scope and draft.profile.."/"..draft.runSerial or GlobalsGetValue(run_key, "")
    if scope then GlobalsSetValue(run_key,token) end
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
    last_error,status=nil,""
    waiting_since,waiting_notice,waiting_profile=nil,nil,nil
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

local function near_home(x,y,hx,hy)
    return hx and hy and (x-hx)^2+(y-hy)^2<=80^2
end

local function resolve_access(player,x,y,hx,hy)
    local station=mountain_storage.inRange(player,x,y)
    local landmark=travel.landmarkName(player,x,y)
    local remote=remoteTerminal.inRange(player,x,y)
    local nearby=station or landmark~=nil or remote or near_home(x,y,hx,hy) or travel.inCabin(player,x,y)
    return nearby,station,landmark,remote
end

local function near_hideout(player)
    return terminalAccess.access(player,home_x,home_y,resolve_access)
end

function NHEWDeposit.canAccess(s,player,intent)
    if intent.dest=="warehouse" or intent.dest=="docks" then return near_hideout(player) end
    return intent.dest=="safe" or intent.dest=="gear" or intent.dest=="bag"
end

local function active_run()
    if not state or not run_id or state.closedThrough>=run_id then return false end
    local scope=NHEW.enabled() and NHEW.world()
    return not scope or scope==state.ewActive
end

NHCompanions.onProductionSummon=function(player)
    if not active_run() then return end
    local frame=GameGetFrameNum()
    NHCompanions.observeProduction(state,NHFarm.observe(state,frame),frame,player)
end

local function active_draft()
    local draft, err = NHStore.load()
    if not draft then report(err); return end
    if draft.profile ~= state.profile or draft.ewActive~=state.ewActive or draft.runSerial ~= run_id or draft.closedThrough >= run_id then
        invalidate()
        report(tr("远征档案已经改变。", "The active run has changed."))
        return
    end
    return draft
end

NHEWReinforce=dofile(files.."ew_reinforce.lua")(function() return state end,active_draft,save,tr,feedback)

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

local function productionBlocked(frame)
    if not blocked_production then return false end
    local b=blocked_production
    if b.profile==state.profile and b.run==run_id and b.revision==state.revision
        and (frame%60~=0 or NHStore.publishedRevision(b.profile)==b.revision) then return true end
    blocked_production=nil
    return false
end

local function update_workshop(player,frame,farm_time)
    local order=state.order
    local elapsed=order and order.required or 0
    if frame>=next_room_check then
        next_room_check=frame+10
        local key,ax,ay=NHClock.mountainAt(player)
        mountain_storage.update(player,ax,ay)
        terminalAccess.invalidateAccess()
        if key and not state.checkpoints[key] then pending_visits[key]=true end
    end
    if productionBlocked(frame) then return true end
    local pending_visit=next(pending_visits)
    -- Finish already-paid legacy orders on the first update. New crafts settle immediately.
    -- Farm production and Holy Mountain discovery keep their own existing clocks.
    local farm_due=NHFarm.due(state,farm_time)
    -- A running farm checkpoints affinity with its minute payment. A player
    -- with no active producers still checkpoints companionship once a minute.
    local affinity_due=not farm_due and farm_time==state.farm.time and frame%3600==0 and NHAffinity.changed(state)
    if not pending_visit and not farm_due and not affinity_due and (not order or (elapsed<order.required and elapsed-order.progress<600)) then return true end
    local draft=active_draft()
    if not draft then return false end
    local changed,done=NHStore.advanceProduction(draft,{run=run_id,orderId=order and order.id or false,
        progress=elapsed,checkpoint=pending_visit})
    local farm_changed,produced,cards
    if farm_due then farm_changed,produced,cards=NHFarm.sync(draft,farm_time) end
    if changed or farm_changed or affinity_due then
        local saved,reason=save(draft,not done and not produced,true)
        if not saved then return reason=="capacity" end
        if done then feedback(tr("旧订单已立即完成，成品已入库。","Previous order completed immediately. Output delivered to storage.")) end
        if cards and #cards>0 then feedback(NHCompanions.rewardText(cards,lang,state)) end
    elseif draft.revision~=state.revision then
        state,model_cache=draft,nil
    end
    if pending_visit then pending_visits[pending_visit]=nil end
    NHClock.observe(state,frame)
    return true
end

local function inject(player,subtype,pay)
    local frame = GameGetFrameNum()
    if last_dose_frame == frame then return end
    last_dose_frame = frame
    local consumed, reason = NHInjectors.use(player,subtype,pay)
    if not consumed then
        if reason then report(reason) end
        return
    end
    mouse_release = true
    feedback(tr("已注射，剩余耐久 ","Injected. Durability ") .. reason .. "/" .. NHStore.doseDurability)
    return true
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
    local storm=NHStormProducts.types[item.kind]
    if storm then return tr(storm.zh,storm.en) end
    local shield=NHShields.types[item.kind] or NHShields.chargers[item.kind] or NHFirearms.items[item.kind]
    if shield then return tr(shield.zh,shield.en) end
    if item.kind=="relic_chain" then return tr("遗物链","Relic chain") end
    if item.kind == "potion" then return NHPotion.label(item, lang) end
    if item.kind=="card_wallet" or NHEquipment.links[item.kind] then
        local d=NHEquipment.get(item.kind,item.tier)
        return tr(d.zh,d.en)
    end
    if item.kind == "dose" then
        local d=NHInjectors.get(item.subtype)
        return tr(d.zh,d.en)
    end
    if item.kind=="bandage" then return translated(item.name) or tr("绷带","Bandage") end
    local throwable=NHThrowables.types[item.kind]
    if throwable then return tr(throwable.zh,throwable.en) end
    local kit=NHMedkits.types[item.kind] or NHSurgeryKits.types[item.kind]
    if kit then return translated(item.name) or tr(kit.zh,kit.en) end
    if item.kind == "spell" then
        local id=item.card.id
        local name=item.name and item.name:match("^%$action_") and translated(item.name)
        name=name or translated(spell_names[id] or "$action_"..id:lower()) or translated(item.name) or id
        return name .. (item.card.stack and (" ×" .. item.card.stack) or "")
    end
    local name = item.name or ""
    if name ~= "" then name = GameTextGetTranslatedOrNot(name) end
    if item.kind=="summon_card" then return translated(item.name) or tr(NHCompanions.cardDefinition(item.species).zh,NHCompanions.cardDefinition(item.species).en) end
    if item.kind~="wand" then return name~="" and name or item.kind end
    if not name or name == "" then name = tr("魔杖", "Wand") end
    return name .. " (" .. #(item.cards or {}) .. tr(" 个法术)", " spells)")
end

local function stored_view(entry)
    local item=entry.item
    local potion=item.kind=="potion" and item or nil
    local wallet=item.kind=="card_wallet" and NHEquipment.get(item.kind,item.tier)
    local equipment=NHEquipment.links[item.kind] or NHShields.types[item.kind] or NHShields.chargers[item.kind] or NHFirearms.items[item.kind]
    local relics
    if item.kind=="relic_chain" then
        relics={}
        for cell=1,4 do
            local row=item.cells[cell]
            if row then relics[#relics+1]=cell..". "..item_label(row) end
        end
    end
    return {id=entry.id,kind=item.kind,name=item_label(entry),potion=potion,relic=item.relic,capacity=wallet and wallet.capacity,
        actionId=item.card and item.card.id,relics=relics,charge=item.charge,reserve=item.reserve,rounds=item.rounds,
        icon=potion and NHPotion.inventoryIcon(potion) or (item.kind=="dose" and NHInjectors.get(item.subtype).icon)
            or (wallet and wallet.icon) or (equipment and equipment.icon) or (NHLootBags.types[item.kind] or {}).icon
            or (NHStormProducts.types[item.kind] or {}).icon or item.icon or (item.sprite and item.sprite.image_file) or NHProducts.icons[item.kind],
        remaining=(NHRedRelics.types[item.kind] and item.remaining) or NHEquipment.linkUses(item.kind,item.remaining) or NHMedkits.remaining(item) or (NHFoods.byId[item.kind] and NHFoods.byId[item.kind].uses),count=item.count or ((item.kind=="bandage" or item.kind=="grenade") and 1 or nil),
        subtype=item.subtype,species=item.species,dockSlot=NHPotion.dockSlot(item)}
end

local function inventory_view()
    if model_cache and model_cache.profile_revision == state.revision then return model_cache end
    local model = {revision = state.revision, profile_revision=state.revision, secure_loot = {}, warehouse = {}}
    model.workshopOutput=state.order and state.order.output
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
        view.trade=NHStore.supplyTrade.quote(entry.item)
        local amount,resource=NHStore.salvageYield(entry.item)
        if not amount and entry.item.kind=="potion" then
            amount,resource=NHStore.salvageYield(entry.item,"store_contents")
            if amount then
                view.store_contents={}
                for key,n in pairs(entry.item.materials) do
                    table.insert(view.store_contents,{key=key,name=NHPotion.materialName(key,lang),amount=n})
                end
                table.sort(view.store_contents,function(a,b) return a.key<b.key end)
                view.materials_fit=NHStore.canStockMaterials(state,entry.item.materials)
            end
        end
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
                view.quick_essence=NHStore.canRecraftSpell(entry.item)
                view.essence={key=key,name=tr(kind.zh,kind.en),amount=count,stock=state.resources[key] or 0,
                    per_card=NHEssences.values[card.id],basis=profile and tr(profile.zh,profile.en)}
            end
        end
        warehouse_slot(entry.item.kind,entry.slot or i,view)
    end
    if state.order and state.order.output.item and not NHStore.slotIndex(state,"warehouse",state.order.output.slot,state.order.output.item.kind) then
        warehouse_slot(state.order.output.item.kind,state.order.output.slot,{
            kind="reserved",name=tr("工坊成品预留格","Reserved for workshop output")})
    end
    model.capacity = NHStore.safeCapacity(state)
    for _, entry in ipairs(state.safe) do
        model.secure_loot[entry.slot or 1] = stored_view(entry)
    end
    for id,pouch in pairs(state.pouches) do
        local d=NHEquipment.get("pouch",pouch.tier)
        local view={id=id,kind="pouch",name=tr(d.zh,d.en).." #"..id,icon=d.icon,doses=pouch.doses,capacity=d.capacity}
        if pouch.location=="safe" then model.secure_loot[pouch.slot]=view
        elseif pouch.location=="warehouse" then warehouse_slot("pouch",pouch.slot,view) end
    end
    local function source_detail(sources,payment)
        local lines={payment and tr("库存 / 本次扣料","Stock / payment")
            or tr("可混用，按优先顺序列出","Combined stock, in preferred order")}
        for _,key in ipairs(sources) do
            local amount=string.format("%.0f",state.materials[key] or 0)
            if payment then amount=amount..string.format(" / %.0f",payment[key] or 0) end
            lines[#lines+1]=NHPotion.materialName(key,lang).."  "..amount
        end
        return table.concat(lines,"\n")
    end
    model.progression=NHStore.progressMenu(state,lang)
    for _,projects in pairs(model.progression) do
        for _,project in ipairs(projects) do
            for _,cost in ipairs(project.costs) do
                if cost.alternatives then cost.detail=source_detail(cost.alternatives,project.materialPayment) end
            end
        end
    end
    model.warehouse_capacity={}
    for _,category in ipairs({"wand","spell","containers","supplies","equipment","collection","materials"}) do
        model.warehouse_capacity[category]=NHStore.warehouseCapacity(state,category)
    end
    model.salvage_enabled=NHStore.level(state,"salvage")>0
    model.shopGoods={}
    local facility_names={}
    for _,project in ipairs(model.progression.expansion) do facility_names[project.id]=project.name end
    model.recipes,model.spellRecipes,model.spellFamilies={},{},{}
    for _,recipe in ipairs(NHStore.recipes) do
        local ready,reason,payment=NHStore.canStartBatch(state,recipe)
        local view={id=recipe.id,category=recipe.category,alchemyMode=recipe.alchemyMode,
            name=tr(recipe.zh,recipe.en),icon=recipe.icon,output=recipe.count or 1,
            inputs={},outputs={},catalysts={},note=recipe.noteZh and tr(recipe.noteZh,recipe.noteEn),
            duration=0,
            ready=ready,unlocked=reason~="Facility is locked." and reason~="Spell not unlocked in this save.",
            facility_name=facility_names[recipe.facility] or recipe.facility}
        local kit=recipe.item and (NHMedkits.types[recipe.item.kind] or NHSurgeryKits.types[recipe.item.kind])
        if kit and kit.healPercent then view.medkit=kit end
        if recipe.item and recipe.item.kind=="dose" then
            view.icon=NHInjectors.get(recipe.item.subtype).icon
        elseif recipe.item and (recipe.category=="food" or recipe.category=="medical" or recipe.category=="weapons" or recipe.category=="equipment") then
            view.icon=recipe.item.icon
        end
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
            local sources,labelZh,labelEn=NHStore.ingredientSources(input,recipe.category)
            if #sources>1 then
                local group=labelZh and tr(labelZh,labelEn) or NHPotion.materialName(input.name)
                name=group..tr("（合计）"," (total)")
                detail=source_detail(sources,payment)
            end
            table.insert(view.inputs,{name=name,amount=input.amount,detail=detail,available=NHStore.ingredientStock(state,input,recipe.category)})
        end
        local resources={}
        for key in pairs(recipe.resources or {}) do resources[#resources+1]=key end
        table.sort(resources)
        for _,key in ipairs(resources) do
            local kind=NHStore.alchemyResources[key] or NHEssences.types[key] or NHFarm.crops[key] or NHLivestock.resources[key]
            local name=key=="arcane_scrap" and tr("奥术碎片","Arcane scrap")
                or key=="container_scrap" and tr("容器碎片","Container scrap") or tr(kind.zh,kind.en)
            table.insert(view.inputs,{name=name,amount=recipe.resources[key],available=state.resources[key] or 0,
                essence=NHEssences.types[key] and key})
        end
        if recipe.goldCost then
            table.insert(view.inputs,{name=tr("存钱罐金币","Piggy bank gold"),amount=recipe.goldCost,available=state.bankGold})
        end
        if recipe.storedIngredient then
            local kind=recipe.storedIngredient
            local count,ingredientIndex=NHStore.warehouseIngredientCount(state,kind)
            local inputKit=NHMedkits.types[kind]
            local name=inputKit and tr(inputKit.zh,inputKit.en) or GameTextGetTranslatedOrNot("$nh_hideout_"..kind)
            local detail=tr("消耗品仓库","Supplies storage")
            if inputKit then
                detail=tr("优先使用消耗品仓库中剩余次数最少的一包，精华用量固定。",
                    "Uses the kit with the fewest charges in supplies storage. Essence cost is fixed.")
                local row=ingredientIndex and state.warehouse[ingredientIndex]
                if row then
                    local remaining=NHMedkits.remaining(row.item)
                    name=name.." ("..remaining.."/"..inputKit.uses..")"
                end
            end
            table.insert(view.inputs,{name=name,amount=1,available=count,detail=detail})
        end
        local held=state.order and state.order.recipe==recipe.id and state.order.catalysts
        for _,sample in ipairs(recipe.catalysts or {}) do
            table.insert(view.catalysts,{name=NHPotion.materialName(sample.name,lang),amount=sample.amount,
                available=state.materials[sample.name] or 0,held=held and held[sample.name] or 0})
        end
        for name,amount in pairs(recipe.materials or {}) do
            table.insert(view.outputs,{key=name,name=NHPotion.materialName(name,lang),amount=amount})
        end
        for key,amount in pairs(recipe.resourceYield or {}) do
            local kind=NHStore.alchemyResources[key]
            table.insert(view.outputs,{key=key,name=tr(kind.zh,kind.en),amount=amount,stock=state.resources[key] or 0})
        end
        table.sort(view.outputs,function(a,b) return a.key<b.key end)
        if recipe.emptyContainers then
            table.insert(view.inputs,{name=tr("仓库空容器","Empty containers"),amount=recipe.emptyContainers,
                available=NHStore.emptyContainerCount(state)})
        end
        local menu=recipe.category=="storm_products" and model.shopGoods or model.recipes
        table.insert(menu,view)
        if state.order and recipe.id==(state.order.recipe or "stable") then model.order_name=view.name end
    end
    for _,good in ipairs(NHStore.shopGoods) do
        local ready,reason=NHStore.canBuyGood(state,good)
        local resource=NHStore.alchemyResources[good.resource]
        if not good.insurance and NHEW.walletAllowed() and not bank_synced then ready,reason=false,"Waiting for wallet settlement." end
        model.shopGoods[#model.shopGoods+1]={id=good.id,category=good.category,name=tr(good.zh,good.en),
            pen=good.animal and ready and reason or nil, yield=good.yield,
            icon=good.icon,resourceName=resource and tr(resource.zh,resource.en),
            resourceStock=resource and (state.resources[good.resource] or 0),
            quantity=good.quantity,price=good.price,scrap=good.scrap,insured=good.insurance and state.insuranceActive,ready=ready,
            reason=not ready and ((lang=="zh" and error_translations[reason]) or reason) or nil}
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
    model.maxUses=NHStore.doseDurability
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
                        local slot = grid[y*columns+x+(not full and NHFirearms.nativeLane(kind,id)~="wand" and 4 or 0)]
                        if slot then
                            slot.entity,slot.kind = id,kind
                            local firearm=NHFirearms.items[kind]
                            if firearm and not firearm.uses then
                                local meter=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent",firearm.magazine and "nh_magazine" or "nh_reserve")
                                if meter then slot[firearm.magazine and "rounds" or "reserve"]=firearm.magazine and ComponentGetValue2(meter,"value_int") or NHFirearms.reserve(meter) end
                            end
                            if kind=="dose" then slot.remaining,slot.subtype=NHDoses.remaining(state,id) end
                            if NHFoods.byId[kind] then
                                local bites=ComponentGetValue2(item,"uses_remaining")
                                if bites==-1 then bites=NHFoods.byId[kind].uses end
                                if NHStore.validBandageCount(bites) then NHFoods.setBites(slot,bites) end
                            end
                            if NHMedkits.capacity(kind) then
                                local n=ComponentGetValue2(item,"uses_remaining")
                                NHMedkits.unpack(slot,kind=="bandage" and n==-1 and 1 or n)
                            end
                            if NHEquipment.links[kind] then slot.remaining=NHEquipment.linkUses(kind,ComponentGetValue2(item,"uses_remaining")) end
                            if NHRedRelics.types[kind] then slot.remaining=ComponentGetValue2(item,"uses_remaining") end
                            if NHGuns.types[kind] then NHGuns.unpack(slot,NHGuns.physicalRounds(kind,id,item)) end
                            if NHLootBags.types[kind] or NHTurrets.types[kind] then slot.count=ComponentGetValue2(item,"uses_remaining") end
                            if NHStormProducts.types[kind] then slot.count=NHStormProducts.worldCount(item) end
                            if kind=="pouch" then slot.pouchId=NHDoses.isPouch(state,id) end
                            if kind=="card_wallet" then
                                local row=NHCardWallets.carried(state,player,id)
                                slot.walletId=row and row.id
                            elseif kind=="summon_card" then
                                local card=NHCompanions.captureCard(id)
                                if card then slot.remaining,slot.species=card.remaining,card.species end
                            end
                            slot.icon = ComponentGetValue2(item,"ui_sprite")
                            local legacy=NHShields.legacyIcons[kind] or NHFirearms.legacyIcons[kind] or (NHLootBags.types[kind] or {}).legacyIcon
                            if legacy and slot.icon==legacy then
                                slot.icon=NHNative.refreshArt(id,item,NHProducts.icons[kind])
                            end
                            if kind=="potion" then
                                slot.dockSlot=NHPotion.carriedDockSlot(id,item)
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
    local lane = NHFirearms.lane(kind)
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
    if popup.kind=="firearm" then
        return case_open and GameIsInventoryOpen() and (popup.container=="safe" or near_hideout(player)) and NHFirearms.stored(state,popup)~=nil
    end
    if popup.kind=="relic_chain" then return case_open and GameIsInventoryOpen() and NHRelics.chain(state,popup)~=nil end
    if popup.kind=="card_wallet" then
        return (not popup.slot or (GameIsInventoryOpen() and (popup.container=="safe" or near_hideout(player))))
            and NHCardWallets.get(state,player,popup)~=nil
    end
    local pouch=state.pouches[popup.id]
    if not pouch then return false end
    if popup.slot then
        return pouch.location==popup.container and pouch.slot==popup.slot and GameIsInventoryOpen()
            and (popup.container=="safe" or near_hideout(player))
    end
    return EntityGetIsAlive(popup.entity) and NHDoses.isPouch(state,popup.entity)==popup.id
        and EntityGetRootEntity(popup.entity)==player
end

local function matches_popup(player,id)
    return popup and not popup.kind and popup.id==id and popup_accessible(player)
end

local function matches_wallet(player,id)
    return popup and popup.kind=="card_wallet" and popup.id==id and popup_accessible(player)
end

local function connect_remote(player,pay)
    if near_hideout(player) then
        GamePrint(tr("附近已有藏身处存取点。","A local hideout access point is in range."))
        return
    end
    local ok,reason=remoteTerminal.deploy(player,pay)
    if not ok then
        if reason=="spawn" then GamePrint(tr("无法部署小型终端，未消耗耐久。","Could not deploy terminal; no charge consumed."))
        elseif reason=="blocked" then GamePrint(tr("此处无法部署：需要可到达的空旷地面。","Cannot deploy here: clear, reachable ground is required.")) end
        return
    end
    terminalAccess.invalidateAccess()
    NHHomeWandEdit.update(player,true)
    model_cache,last_error,status=nil,nil,""
    GamePrint(tr("已部署小型终端，可使用 10 分钟。在附近打开物品栏即可存取。",
        "Small terminal deployed for 10 minutes. Open inventory nearby to access storage."))
end

local function start_charger(player,kind,available,source,payPhysical)
    shieldRuntime.snapshot(state,player)
    local shield=state.gearShield
    if not shield or NHShields.broken(shield)==0 then surgery_feedback("unneeded",kind); return end
    local id,epoch=shield.id,shield.epoch
    local function matches(s)
        return s and s.gearShield and s.gearShield.id==id and s.gearShield.epoch==epoch
    end
    NHSurgery.beginUse(player,kind,NHShields.chargers[kind].castFrames,function()
        return matches(state) and available()
    end,function()
        shieldRuntime.snapshot(state,player)
        if NHShields.broken(state.gearShield)==0 then return "unneeded" end
        local ok=commit_edit(function(draft)
            if not matches(draft) then return false,"Inventory slot changed." end
            shieldRuntime.snapshot(draft,player)
            local repaired,reason=NHShields.repair(draft,kind)
            if not repaired then return false,reason end
            if source then return NHInventoryUse.spend(draft,player,source) end
            return true
        end)
        if not ok then return "interrupted" end
        if payPhysical then payPhysical() end
        shieldRuntime.sync(state,player)
        return "completed"
    end)
end

local function start_ammo_pack(player,kind,available,source,payPhysical)
    local row=state.gearRig
    local capacity=row and NHFirearms.rigs[row.item.kind].capacity
    local pack=NHFirearms.packs[kind]
    if not row or row.item.reserve>=capacity then
        feedback(row and tr("弹挂已满。","Ammo rig full.") or tr("请先装备弹挂。","Equip an ammo rig first."))
        return
    end
    local id=row.id
    NHSurgery.beginUse(player,kind,pack.castFrames,function()
        return state and state.gearRig and state.gearRig.id==id and available()
    end,function()
        if state.gearRig.item.reserve>=capacity then return "interrupted" end
        local ok=commit_edit(function(draft)
            local rig=draft.gearRig
            if not rig or rig.id~=id or rig.item.reserve>=capacity then return false,"Inventory slot changed." end
            rig.item.reserve=math.min(capacity,rig.item.reserve+pack.refill)
            if source then return NHInventoryUse.spend(draft,player,source) end
            return true
        end)
        if not ok then return "interrupted" end
        if payPhysical then payPhysical() end
        return "completed"
    end)
end

local function relic_feedback(ok,kind)
    if not ok then report(kind)
    elseif kind=="rewind_watch" then feedback(tr("倒流锚点已记录。60 秒内首次受击，5 秒后闪回。","Anchor set. A hit within 60 seconds triggers a rewind 5 seconds later."))
    elseif kind=="salvage_bell" then feedback(tr("打捞钟已鸣响，掉落加成持续 15 分钟。","Salvage Bell rung. Drop bonus active for 15 minutes."))
    elseif kind=="stasis_hourglass" then feedback(tr("静滞领域已展开，持续 30 秒。","Stasis field opened for 30 seconds."))
    elseif kind=="dustless_duster" then feedback(tr("无尘领域已展开，接下来 60 秒将随你移动。","Repulsion field active around you for 60 seconds."))
    elseif kind=="mana_reactor" then feedback(tr("堆芯直通已启动，持续 90 秒。","Reactor direct power active for 90 seconds.")) end
end

local function use_carried(player,entity,slot)
    local kind=NHNative.kind(entity) or NHTransfers.item_kind(entity)
    if NHEquipment.links[kind] then
        connect_remote(player,function()
            local draft=active_draft()
            if not draft then return false end
            local ok,reason=NHTransfers.reconcile(draft,player)
            if not ok then report(reason); return false end
            if draft.revision~=state.revision then state,model_cache=draft,nil end
            return NHProducts.spendRemoteCharge(player,entity)
        end)
    elseif kind=="pouch" then
        local id=NHDoses.isPouch(state,entity)
        if id then opened,popup=true,{id=id,entity=entity} end
    elseif kind=="card_wallet" then
        local row=NHCardWallets.carried(state,player,entity)
        if row then opened,popup=true,{kind=kind,id=row.id,entity=entity} end
    elseif kind=="dose" then
        local remaining,subtype=NHDoses.remaining(state,entity)
        if not remaining then report("This syringe is no longer available."); return end
        inject(player,subtype,function() return NHDoses.consume(state,player,entity,slot~=nil) end)
    elseif NHRedRelics.types[kind] then
        relic_feedback(NHRedRelics.activate(state,player,entity,slot))
    elseif kind=="summon_card" then
        local card=NHCompanions.captureCard(entity)
        local ok=NHCompanions.use(player,entity,lang,slot~=nil,function() return commit_edit(NHTarot.refillDraft) end)
        if ok and card and NHTarot.types[card.species] then
            shieldRuntime.sync(state,player)
            NHTarot.refillGuns(player)
            rescue.arm(state,player)
            ammoRuntime.reset()
            feedback(tr("塔罗牌已生效。","Tarot card activated."))
        end
    elseif NHFirearms.packs[kind] then
        local available,pay=NHSurgery.physicalSource(player,entity,slot,4*NHFirearms.packs[kind].uses)
        start_ammo_pack(player,kind,available,nil,pay)
    elseif NHShields.chargers[kind] then
        local maximum=kind==NHShields.charger and 2147483647 or 4*NHShields.chargers[kind].uses
        local available,pay=NHSurgery.physicalSource(player,entity,slot,maximum)
        start_charger(player,kind,available,nil,pay)
    elseif NHSurgeryKits.types[kind] then
        local _,reason=NHSurgery.start(player,entity,slot)
        surgery_feedback(reason)
    else
        NHProducts.use(player,entity,slot,slot and inventory_aim,function(dose,subtype)
            return commit_edit(function(draft)
                if NHLootBags.types[kind].loot then NHTarot.refillDraft(draft) end
                if dose then return NHDoses.registerLoot(draft,dose,subtype) end
                return true
            end)
        end)
    end
end

local function inventory_access(player,source)
    if not active_run() then return false end
    if source.container=="warehouse" then return near_hideout(player) end
    if source.container=="pouch" then return matches_popup(player,source.pouchId) end
    if source.container=="card_wallet" then return matches_wallet(player,source.walletId) end
    return source.container=="safe" or source.container=="gear"
end

local function use_inventory(player,source)
    if source.container=="native" then
        local slot=matching_slot(player,source)
        if slot and slot.entity==source.entity and slot.kind==source.kind and EntityGetRootEntity(slot.entity)==player then
            if (NHEquipment.links[slot.kind] or NHRedRelics.types[slot.kind]) and slot.remaining~=source.remaining then return end
            use_carried(player,slot.entity,slot)
        end
        return
    end
    if not inventory_access(player,source) then return end
    if source.container=="safe" or source.container=="warehouse" or source.container=="gear" then
        if not case_open or not GameIsInventoryOpen() then return end
        if source.kind=="pouch" then
            local pouch=NHPouches.at(state,source.container,source.slot)
            if pouch and pouch.id==source.storedId then popup={id=pouch.id,container=source.container,slot=pouch.slot} end
            return
        elseif source.kind=="relic_chain" then
            local ref={kind="relic_chain",container=source.container,slot=source.slot,id=source.storedId}
            if NHRelics.chain(state,ref) then popup=ref end
            return
        elseif source.kind=="card_wallet" then
            local ref={kind="card_wallet",id=source.storedId,slot=source.slot,container=source.container}
            if NHCardWallets.get(state,player,ref) then popup=ref end
            return
        end
    elseif source.container=="card_wallet" then source.wallet=popup end
    local item=NHInventoryUse.peek(state,player,source)
    if not item then return end
    local function pay(dose,subtype)
        if not inventory_access(player,source) then return false end
        return commit_edit(function(draft)
            local ok,err=NHInventoryUse.spend(draft,player,source)
            if ok and NHLootBags.types[item.kind] and NHLootBags.types[item.kind].loot then NHTarot.refillDraft(draft) end
            if ok and item.kind=="summon_card" and NHTarot.types[item.species] then NHTarot.refillDraft(draft) end
            if ok and dose then return NHDoses.registerLoot(draft,dose,subtype,true) end
            return ok,err
        end)
    end
    if NHEquipment.links[item.kind] then
        connect_remote(player,pay)
    elseif item.kind=="dose" then
        local left=(item.remaining or NHStore.doseDurability)-1
        inject(player,item.subtype,function()
            if pay() then return true,left end
        end)
    elseif NHRedRelics.types[item.kind] then
        local paid
        local ok,reason=NHRedRelics.activateStored(state,player,item,function()
            paid=pay()
            return paid
        end)
        -- A rejected commit has already reported the precise storage error.
        if paid~=false then relic_feedback(ok,reason) end
    elseif item.kind=="summon_card" then
        local ok=NHCompanions.summon(player,item.species,lang,pay)
        if ok and NHTarot.types[item.species] then
            shieldRuntime.sync(state,player)
            NHTarot.refillGuns(player)
            rescue.arm(state,player)
            ammoRuntime.reset()
            feedback(tr("塔罗牌已生效。","Tarot card activated."))
        end
    elseif NHFirearms.packs[item.kind] then
        start_ammo_pack(player,item.kind,function()
            return inventory_access(player,source) and NHInventoryUse.peek(state,player,source)~=nil
        end,source)
    elseif NHShields.chargers[item.kind] then
        start_charger(player,item.kind,function()
            return inventory_access(player,source) and NHInventoryUse.peek(state,player,source)~=nil
        end,source)
    elseif NHSurgeryKits.types[item.kind] or NHMedkits.types[item.kind] then
        local _,reason=NHSurgery.begin(player,item.kind,function()
            return inventory_access(player,source) and NHInventoryUse.peek(state,player,source)~=nil
        end,pay)
        surgery_feedback(reason,item.kind)
    else
        NHProducts.apply(player,item.kind,pay,inventory_aim)
    end
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
    if not case_open or not GameIsInventoryOpen() or not near_hideout(player) then return end
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
        if index.id~="rescue_policy" and NHEW.walletAllowed() and not bank_synced then report("Waiting for wallet settlement."); return end
        if index.id=="rescue_policy" then
            commit_edit(NHStore.buyGood,"已投保，可救援一次。","Insured for one rescue.",index)
        elseif NHLivestock.species[index.id] then
            local now=NHFarm.observe(state,GameGetFrameNum())
            commit_edit(function(draft) return NHStore.buyGood(draft,index,now) end,
                "转化完成，幼畜已送入设施。","Conversion complete. Youngstock delivered.")
        else commit_edit(NHStore.buyGood,"转化完成。","Conversion complete.",index) end
    elseif action=="buy_upgrade" and type(index)=="table" then
        local now=NHFarm.observe(state,GameGetFrameNum())
        commit_edit(function(draft) return NHStore.buyUpgrade(draft,index,now) end,"建设完成。","Construction complete.")
    elseif action=="farm_plant" and type(index)=="table" then
        local frame=GameGetFrameNum()
        local now=NHFarm.observe(state,frame)
        if commit_edit(function(draft) return NHFarm.plant(draft,index,now) end) then
            local crop=NHFarm.crops[index.crop]
            feedback(string.format(tr("田地 %d 下轮产出%s。","Field %d will produce %s next."),index.plot,tr(crop.zh,crop.en)))
            NHFarm.observe(state,frame)
        end
    elseif action=="organize_warehouse" and type(index)=="table" then
        commit_edit(NHStore.organizeWarehouse,"当前仓库页已整理。","Stash tab sorted.",index)
    elseif action=="supply_trade" and type(index)=="table" then
        commit_edit(NHStore.supplyTrade.apply,index.mode=="sell" and "已出售，金币已存入存钱罐。" or "产物已计入资源库存。",
            index.mode=="sell" and "Sold. Gold deposited." or "Product added to resource stock.",index)
    elseif action=="salvage" and type(index)=="table" then
        if index.mode=="collectible" then
            commit_edit(NHRedRelics.salvage,"分解完成，四种资源包、塔罗牌和同伴卡已入库。","Four types of logistics packs, tarot cards and companion cards stored.",index)
        elseif index.mode=="essence" or index.mode=="quick_essence" then
            commit_edit(NHStore.salvage,"提取完成，精华已入库。","Essence extracted and stored.",index)
        elseif index.mode=="store_contents" then
            commit_edit(NHStore.salvage,"物料已入库，容器已拆成碎片。","Contents stored and container dismantled.",index)
        else
            commit_edit(NHStore.salvage,"拆解完成，碎片已入库。","Item dismantled. Scrap stored.",index)
        end
    elseif action=="order" or (action=="craft" and index and index.id) then
        if commit_edit(NHStore.craft,"合成完成，成品已入库。","Craft complete. Output delivered to storage.",index and index.id) then
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
    terminalAccess.invalidateAccess()
    if not opened or not active_run() then return end
    if action=="cancel_deposit" then
        local ok,reason=NHEWDeposit.cancel(state,index)
        if not ok and reason then report(reason) end
        return
    end
    if action=="travel_to" then
        if case_open then travel.choose(player,index) end
        return
    end
    if case_open or popup then
        if action=="use_inventory" then
            if type(index)=="table" then use_inventory(player,index) end
            return
        end
        if action=="close_container" then
            popup=nil
            if not case_open then close_panel() end
            return
        end
        if type(index)~="table" or action=="buy_upgrade" or action=="craft" or action=="salvage"
            or action=="bank_transfer" or action=="shop_buy" or action=="farm_plant" or action=="organize_warehouse" or action=="supply_trade" then
            workshop_action(player,action,index)
            return
        end
        if action=="equip_perk" or action=="unequip_perk" or action=="pack_perk" then
            if not NHPerks.enabled then return end
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
        if container~="safe" and not (case_open and GameIsInventoryOpen() and near_hideout(player)) then return end
        if action=="move_gear" then
            if not case_open or not GameIsInventoryOpen() then return end
            if (index.source=="warehouse" or index.destination=="warehouse") and not near_hideout(player) then return end
            local ok=commit_edit(function(draft)
                shieldRuntime.snapshot(draft,player)
                return NHShields.move(draft,index)
            end)
            if ok then shieldRuntime.sync(state,player) end
            return
        end
        if action=="equip_stored_perk" or action=="store_equipped_perk" then
            if not NHPerks.enabled then return end
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
        if index.chainId and not (popup and popup.kind=="relic_chain" and popup.id==index.chainId and popup_accessible(player)) then return end
        if action=="move_gun_attachment" then
            if popup and popup.kind=="firearm" and popup_accessible(player) then
                commit_edit(function(draft) return NHFirearms.socket(draft,popup,index) end)
            end
            return
        end
        if action=="open_container" then
            if NHFirearms.items[index.kind] and NHFirearms.items[index.kind].magazine then
                local ref={kind="firearm",id=index.entity,slot=index.safeSlot,container=container}
                if case_open and GameIsInventoryOpen() and NHFirearms.stored(state,ref) then popup=ref end
                return
            end
            if index.kind=="relic_chain" then
                local ref={kind="relic_chain",id=index.entity,slot=index.safeSlot,container=container}
                if case_open and GameIsInventoryOpen() and NHRelics.chain(state,ref) then popup=ref end
                return
            end
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
        if action=="move_chain_relic" then
            if not index.chainId or ((index.source=="warehouse" or index.destination=="warehouse") and not near_hideout(player)) then return end
            commit_edit(function(draft) return NHRelics.move(draft,popup,index) end)
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
        if action=="move_food" or action=="move_stored_card" or action=="move_wallet" or action=="move_terminal" or action=="move_relic" or action=="move_firearm" then
            local from,to=index.source,index.destination
            if not case_open or not GameIsInventoryOpen() or (from~="safe" and from~="warehouse")
                or (to~="safe" and to~="warehouse") or ((from=="warehouse" or to=="warehouse") and not near_hideout(player)) then return end
            if action=="move_food" then
                commit_edit(function(draft)
                    local at=NHStore.slotIndex(draft,from,index.from,index.kind)
                    local row=at and draft[from][at]
                    if not row or row.id~=index.entity or row.item.kind~=index.kind or not NHStore.stackUnits(row.item)
                        or not index.safeSlot or (from==to and index.from==index.safeSlot) then return false,"Inventory slot changed." end
                    if NHStormProducts.types[index.kind] then
                        local dest=NHStore.slotIndex(draft,to,index.safeSlot,index.kind)
                        local target=dest and draft[to][dest].item
                        if target and target.kind==index.kind then
                            local n=row.item.count or 1
                            local take=math.min(n,NHStormProducts.stackLimit-(target.count or 1))
                            if take==0 then return false,"Inventory slot changed." end
                            target.count=(target.count or 1)+take
                            if take==n then table.remove(draft[from],at) else row.item.count=n-take end
                            return true
                        end
                    end
                    local _,dest=NHStore.stackSlot(draft,to,row.item,index.safeSlot)
                    if dest then
                        local target=draft[to][dest].item
                        NHStore.mergeStack(target,row.item)
                    elseif NHStore.freeSlot(draft,to,index.safeSlot,index.kind) then
                        row.slot=index.safeSlot
                        table.insert(draft[to],row)
                    else return false,"Inventory slot changed." end
                    table.remove(draft[from],at)
                    return true
                end)
            elseif action=="move_stored_card" then
                commit_edit(function(draft)
                    return NHCompanions.moveCard(draft,from,index.from,to,index.safeSlot,index.entity)
                end)
            else
                local kind=action=="move_wallet" and "card_wallet" or "remote_terminal"
                if action=="move_terminal" and index.kind then
                    if not NHEquipment.links[index.kind] then return end
                    kind=index.kind
                elseif action=="move_relic" then
                    if index.kind~="relic" and index.kind~="relic_chain" and index.kind~="tablet" and index.kind~="native_valuable"
                        and not NHRedRelics.types[index.kind] then return end
                    kind=index.kind
                elseif action=="move_firearm" then
                    if not NHFirearms.items[index.kind] or NHFirearms.packs[index.kind] then return end
                    kind=index.kind
                end
                local moved=commit_edit(function(draft)
                    local at=NHStore.slotIndex(draft,from,index.from,kind)
                    local row=at and draft[from][at]
                    if not row or row.id~=index.entity or row.item.kind~=kind
                        or not NHStore.freeSlot(draft,to,index.safeSlot,kind) then return false,"Inventory slot changed." end
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
                or ((from=="warehouse" or to=="warehouse") and not near_hideout(player)) then return end
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
            return moved
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
        if action=="place" or action=="cancel_native" or action=="reject_relic" or action=="equip_perk" then
            local id = index.entity
            if not id or not EntityGetIsAlive(id) then return end
            -- Vanilla can complete its outside-inventory throw before the post
            -- callback. Reclaim only this drag's original entity and empty slot.
            if not slot.entity and EntityGetRootEntity(id)==id then
                if NHEW.enabled() then report("Pick up this item before storing it."); return end
                if not place_in_slot(player,id,slot) then return end
            elseif slot.entity~=id then return end
            local inv = EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
            if ComponentGetValue2(inv,"mThrowItem")==id then ComponentSetValue2(inv,"mThrowItem",0) end
            if action=="reject_relic" then report("Relic unavailable."); return end
            if action=="cancel_native" then return end
            if action=="equip_perk" then
                ok,result=NHPerks.equip(state,player,id,index.safeSlot,slot)
                if not ok then report(result) else status="" end
                return
            end
            local kind = NHNative.kind(id)
            if index.intoGear then
                ok,result=NHTransfers.deposit(state,player,"gear",id,index.safeSlot)
                if ok then shieldRuntime.sync(state,player) end
            elseif index.chainId and index.targetCell then
                ok,result=NHTransfers.deposit(state,player,"safe",id,index.targetCell,nil,popup)
            elseif index.walletId and index.targetCell then
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
            if action=="take_gear" then
                shieldRuntime.snapshot(state,player)
                ok,result=NHTransfers.withdrawGear(state,player,index.storedId,index.kind,deliver)
                if ok then shieldRuntime.sync(state,player) end
            elseif action=="unequip_perk" then
                ok,result=NHPerks.unequip(state,player,index.safeSlot,index.storedId,slot)
                if not ok then report(result) else status="" end
                return
            elseif action=="take_pouch" then
                local pouch=NHPouches.at(state,container,index.safeSlot)
                if not pouch or pouch.id~=index.pouchId then return end
                ok,result=NHDoses.takePouch(state,player,deliver,pouch.id)
            elseif action=="take_relic" and index.chainId then
                ok,result=NHTransfers.withdrawRelic(state,player,popup,index.sourceCell,index.storedId,deliver)
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

local function quick_warehouse(dockSlot)
    if dockSlot and NHStore.freeSlot(state,"docks",dockSlot,"potion") then return "docks",dockSlot end
    return "warehouse"
end

local function quick_deposit(player,source,nearby)
    local live=matching_slot(player,source)
    if not live or live.entity~=source.entity or live.kind~=source.kind then return nil,"Inventory slot changed." end
    local dest,preferred="safe",nil
    if nearby then dest,preferred=quick_warehouse(live.dockSlot) end
    local kind,id=live.kind,live.entity
    if kind~="dose" and kind~="pouch" then
        return NHTransfers.deposit(state,player,dest,id,preferred,nearby and "safe" or nil)
    end
    local slot=NHTransfers.storageSlot(state,dest,live)
    if not slot and nearby then
        dest="safe"
        slot=NHTransfers.storageSlot(state,dest,live)
    end
    if not slot then return nil,"No free destination slot." end
    local ok,reason
    if kind=="dose" then ok,reason=NHDoses.deposit(state,player,id,slot,nil,dest)
    else ok,reason=NHDoses.storePouch(state,player,id,slot,dest) end
    return ok,reason,dest,slot
end

local function pickup_press(player,after_update)
    local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    local stamp=controls and ComponentGetValue2(controls,"mButtonFrameInteract")
    local frame=GameGetFrameNum()
    if type(stamp)~="number" or stamp<=0 or stamp==last_pickup_press or math.abs(frame-stamp)>1
        or not ComponentGetValue2(controls,"mButtonDownInteract") then return end
    last_pickup_press=stamp
    local toSafe=NHUI.shiftDown()
    -- Some input reaches ControlsComponent during the engine update. If vanilla
    -- already picked an item, route that exact entity instead of its neighbour.
    if after_update then
        for _,slot in ipairs(native_slots(player)) do
            local item=slot.entity and EntityGetFirstComponentIncludingDisabled(slot.entity,"ItemComponent")
            local picked=item and ComponentGetValue2(item,"mFramePickedUp")
            if picked==frame or picked==stamp then
                local safeStack=NHLootBags.types[slot.kind] and NHStore.stackSlot(state,"safe",slot)
                    and not pickup.stackTarget(state,player,slot.kind,slot.count,slot.entity)
                if (toSafe or safeStack) and slot.kind~="other" and not EntityGetFirstComponentIncludingDisabled(slot.entity,"ItemCostComponent") then
                    local ok,err=quick_deposit(player,slot,false)
                    if not ok then transfer_error(err)
                    elseif err~="Item deposit queued." then feedback(tr("已拾取到安全箱。","Picked up into the secure case.")) end
                end
                return
            end
        end
    end
    local claimed,err,stored=pickup.interact(state,player,toSafe,native_slots)
    if claimed then
        ComponentSetValue2(controls,"mButtonDownInteract",false)
        ComponentSetValue2(controls,"mButtonFrameInteract",-1)
        if err then transfer_error(err) elseif stored then feedback(tr("已拾取到安全箱。","Picked up into the secure case.")) end
    end
end

local function quick_stored(player,source,nearby)
    local src=source.key=="valuable" and "safe" or source.key
    if src~="safe" and not nearby then return nil,"Slot unavailable." end
    local kind=source.kind
    local index=NHStore.slotIndex(state,src,source.safeSlot,kind)
    local row=index and state[src][index]
    local pouch=kind=="pouch" and NHPouches.at(state,src,source.safeSlot)
    if kind=="pouch" then
        if not pouch or pouch.id~=source.entity then return nil,"Inventory slot changed." end
    elseif not row or row.id~=source.entity or row.item.kind~=kind then return nil,"Inventory slot changed." end

    local field=NHShields.field(kind)
    if src=="warehouse" and field and not state[field] then
        local ok=commit_edit(function(draft)
            if draft[field] then
                return false,"Inventory slot changed."
            end
            return NHShields.move(draft,{source=src,destination="gear",kind=kind,from=source.safeSlot,entity=row.id})
        end)
        if ok then
            shieldRuntime.sync(state,player)
            return true,nil,"gear",NHShields.slot(kind)
        end
        return false
    end
    local dest,preferred="safe",nil
    if src=="safe" then dest,preferred=quick_warehouse(row and NHPotion.dockSlot(row.item)) end
    local slot
    if pouch then slot=NHStore.freeSlot(state,dest,nil,kind)
    elseif src=="safe" and nearby then slot=NHTransfers.storageSlot(state,dest,row.item,preferred) end
    if src~="safe" or not nearby or not slot then
        local stackDelivery=row and pickup.stackDelivery(state,player,row.item,src=="warehouse")
        if stackDelivery then return NHTransfers.withdraw(state,player,index,src,stackDelivery,src=="warehouse") end
        local lane=NHFirearms.lane(kind)
        for _,native in ipairs(native_slots(player)) do
            if not native.entity and native.lane==lane then
                local function deliver(id) return place_in_slot(player,id,native) end
                if pouch then return NHDoses.takePouch(state,player,deliver,pouch.id) end
                if kind=="dose" then return NHDoses.withdraw(state,player,deliver,nil,source.safeSlot,nil,src) end
                return NHTransfers.withdraw(state,player,index,src,deliver,src=="warehouse")
            end
        end
        if src=="safe" then return nil,"No free destination slot." end
    end
    if pouch then
        if not slot then return nil,"No free destination slot." end
        local ok=dispatch(player,"move_pouch",{source=src,destination=dest,container=src,
            from=source.safeSlot,safeSlot=slot,pouchId=pouch.id})
        return ok,nil,dest,slot
    end
    return NHTransfers.moveStored(state,src,index,dest,src=="warehouse",preferred)
end

-- Only suppress transient button state while the panel owns input.
local function suppress_item_input(player)
    local c = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
    if not c then return end
    for _, key in ipairs({"Fire", "Fire2", "Throw", "Kick"}) do
        ComponentSetValue2(c, "mButtonDown" .. key, false)
        ComponentSetValue2(c, "mButtonFrame" .. key, -1)
    end
end

function OnWorldInitialized()
    tarotSight.reset(true)
    storm.preloadAudio()
    local newBagsOnly = "noita_hideout.floating_bags_from_start"
    local newCardsOnly = "noita_hideout.floating_cards_from_start"
    local newGunArt = "noita_hideout.support_art_from_start"
    if GameGetFrameNum() <= 1 and GlobalsGetValue(run_key, "") == "" then
        GlobalsSetValue(newBagsOnly, "1")
        GlobalsSetValue(newCardsOnly, "1")
        GlobalsSetValue(newGunArt, "1")
    end
    local oldBags, oldCards = GlobalsGetValue(newBagsOnly, "") ~= "1", GlobalsGetValue(newCardsOnly, "") ~= "1"
    migrateGroundItems = (oldBags or oldCards) and dofile(files .. "legacy_loot_bags.lua")(oldBags, oldCards) or nil
    migrateSupportGuns = GlobalsGetValue(newGunArt, "") ~= "1" and NHProducts.repairNearbySupportWeapons or nil
    NHEW.reset()
    NHEWDeposit.reset()
    if NHEW.enabled() then
        for _,key in ipairs({"status","issuer","local_peer","item_request","reinforce_mode","reinforce_targets","reinforce_request",
            "reinforce_sponsor_offer","reinforce_sponsor_reply","reinforce_redirect"}) do GlobalsSetValue("nh_ew."..key,"") end
    end
    wallet_allowed=nil
    waiting_since,waiting_notice,waiting_profile=nil,nil,nil
    travel.reset()
    fireSupport.reset()
    ammoRuntime.reset()
    katanaRuntime.reset(true)
    NHSurgery.reset()
    right_use=nil
    inventory_aim.x,inventory_aim.y=1,0
    NHClock.reset()
    mountain_storage.reset()
    terminals.reset()
    NHFarm.resetClock()
    NHCompanions.resetProduction()
    NHHomeWandEdit.reset()
    NHRelics.reset()
    bank_synced=false
    next_room_check,pending_visits,blocked_production=0,{},nil
    state, run_id, home_x, home_y, player_id = nil, nil, nil, nil, nil
    opened, mouse_release, next_attempt, last_dose_frame = false, false, 0, -1
    case_open,popup = nil,nil
    collectible_fire_down=false
    quick_click_player=nil
    last_pickup_press=nil
    NHNative.resetInput()
    model_cache, status, last_error = nil, "", nil
    lang = NHNative.language()
end

function OnPlayerSpawned(player)
    if not NHEW.localBody(player) then return end
    katanaRuntime.reset(true)
    tarotSight.sync(player)
    NHSurgery.reset(player)
    player_id = player
    set_home(player, true)
    local x,y=EntityGetTransform(player)
    NHHomeWandEdit.update(player,near_home(x,y,home_x,home_y))
    if attach() and active_run() then
        NHClock.observe(state,GameGetFrameNum())
        local frame=GameGetFrameNum()
        NHCompanions.observeProduction(state,NHFarm.observe(state,frame),frame,player)
        NHPerks.update(state,player,not NHPerks.enabled)
        NHRelics.update(state,player)
        shieldRuntime.sync(state,player)
        rescue.arm(state,player)
        tarotRuntime.refreshLifeIcons(player)
    end
end

function OnPausedChanged(is_paused,is_inventory_pause)
    -- The pause menu can start a fresh world before the next regular checkpoint.
    if not is_paused or is_inventory_pause or not active_run() then return end
    local frame=GameGetFrameNum()
    if productionBlocked(frame) then return end
    local now=NHFarm.observe(state,frame)
    if now<=state.farm.time and not NHFarm.due(state,now) and not NHAffinity.changed(state) then return end
    local draft=active_draft()
    if not draft then return end
    local _,produced,cards=NHFarm.sync(draft,now)
    if save(draft,not produced,true) and cards and #cards>0 then feedback(NHCompanions.rewardText(cards,lang,state)) end
end

local function local_body_with_tag(tag)
    for _,id in ipairs(EntityGetWithTag(tag) or {}) do
        if NHEW.localBody(id) then return id end
    end
end
local function current_player()
    if player_id and EntityGetIsAlive(player_id) and EntityHasTag(player_id,"player_unit") and NHEW.localBody(player_id) then return player_id end
    local previous=player_id
    player_id=local_body_with_tag("player_unit")
    if player_id~=previous then
        if player_id then tarotSight.sync(player_id) else tarotSight.reset() end
    end
    return player_id
end

function OnWorldPreUpdate()
    local stormRound=storm.update()
    if stormRound then travel.scheduleRepair(stormRound) end
    local player = current_player()
    remoteTerminal.update()
    if player and GameGetFrameNum()%60==0 then
        if migrateGroundItems then migrateGroundItems() end
        if migrateSupportGuns and GameGetFrameNum()%180==0 then migrateSupportGuns(player) end
        NHNative.refreshLinkArt()
        NHStormProducts.refreshLegacyItems(player)
        for _,kind in ipairs({"scatter_revolver","marksman_rifle","battle_staff","hunting_bow"}) do
            for _,id in ipairs(EntityGetWithTag("noita_hideout_"..kind) or {}) do
                NHFirearms.ensureBuiltInAction(id,kind)
                if kind=="battle_staff" then NHFirearms.repairStaff(id,player)
                else NHFirearms.repairGunSprite(id,kind) end
            end
        end
    end
    if player then
        set_home(player,false)
        terminals.home(player,home_x,home_y)
        if active_run() then rescue.arm(state,player) end
    elseif active_run() then
        local body=local_body_with_tag("polymorphed_player")
        if body then
            if ammoRuntime.guardMimic(body) then NHRewind.polymorph(body,state)
            else rescue.polymorph(state,body) end
        end
    end
    -- Covers existing worlds and enemies with independent entity templates.
    if player and GameGetFrameNum()%15==0 then
        for _,enemy in ipairs(EntityGetWithTag("enemy") or {}) do
            if not EntityGetFirstComponentIncludingDisabled(enemy,"LuaComponent","nh_bag_drop") then
                EntityAddComponent2(enemy,"LuaComponent",{_tags="nh_bag_drop",script_death=deathScript,execute_every_n_frame=-1})
            end
        end
    end
    local inventory_open=GameIsInventoryOpen()
    NHHomeWandEdit.update(player,player and (not state or active_run()) and near_hideout(player))
    local menu=inventory_open or opened
    -- Read the native Fire binding before a menu can suppress it. A held
    -- trigger must be released before it can activate a collectible again.
    local controls=player and EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    local boundFire=controls and ComponentGetValue2(controls,"mButtonDownFire")==true or false
    local collectiblePress=boundFire and not collectible_fire_down
    collectible_fire_down=boundFire
    local supportInput=fireSupport.input(active_run() and state,player,menu or mouse_release)
    local katanaInput=katanaRuntime.capture(player,menu or mouse_release or supportInput or not active_run())
    if player and not menu and active_run() then pickup_press(player,false) end
    local pressed=InputIsMouseButtonDown(1)
    if not pressed or player~=quick_click_player then quick_click_player=nil end
    if player and inventory_open and case_open and active_run() and pressed and not left_down and NHUI.shiftDown() then
        local source=NHUI.quickTarget()
        if source then
            quick_click_player=player
            local transfer=source.key=="native" and quick_deposit or quick_stored
            local ok,err,dest,slot=transfer(player,source,near_hideout(player))
            if ok then
                status=""
                if dest and err~="Item deposit queued." then NHUI.showTransfer(dest,source.kind,slot) end
            elseif err then transfer_error(err) end
        end
    end
    ammoRuntime.bind(player and active_run() and state or nil)
    if quick_click_player and controls then
        for _,action in ipairs({"Fire","LeftClick"}) do
            ComponentSetValue2(controls,"mButtonDown"..action,false)
            ComponentSetValue2(controls,"mButtonFrame"..action,-1)
        end
    end
    local trigger=(pressed or collectiblePress) and player and not menu and not mouse_release and not supportInput
        and not katanaInput and NHNative.held(player) or nil
    fire_request=NHGuns.trigger(pressed and trigger or nil,pressed and not left_down,GameGetFrameNum())
    if trigger and EntityHasTag(trigger,"nh_red_relic") then fire_request=collectiblePress and trigger or nil end
    left_down=pressed
    right_use=NHNative.prepareRightUse(player,menu,menu and NHUI.useTarget() or nil)
    if katanaInput and not menu then right_use=nil end
    if supportInput then right_use=nil end
    if type(right_use)=="number" then right_use=NHNative.heldUseSlot(player,right_use) end
    if controls and not menu then
        local x,y=ComponentGetValue2(controls,"mAimingVectorNormalized")
        if type(x)=="number" and type(y)=="number" and x*x+y*y>0.000001 then
            local length=math.sqrt(x*x+y*y)
            inventory_aim.x,inventory_aim.y=x/length,y/length
        end
    end
    if not opened and not mouse_release then return end
    if GameIsInventoryOpen() then return end
    if not player then
        opened, case_open, mouse_release = false, nil, false
        return
    end
    if not opened and not InputIsMouseButtonDown(1) and not InputIsMouseButtonDown(2) then
        mouse_release = controls and (ComponentGetValue2(controls, "mButtonDownFire") or ComponentGetValue2(controls, "mButtonDownFire2"))
    end
    if opened or mouse_release then suppress_item_input(player) end
end

function OnWorldPostUpdate()
    local player = current_player()
    if not player then katanaRuntime.reset() end
    fireSupport.finishInput()
    local inventory_open=GameIsInventoryOpen()
    if not inventory_open and not opened and not case_open then storm.draw(player,lang) end
    NHHomeWandEdit.update(player,player and (not state or active_run()) and near_hideout(player))
    local gun=fire_request
    fire_request=nil
    local used=right_use
    right_use=nil
    surgery_feedback(NHSurgery.update(player))
    if player then set_home(player, false) end
    local traveler=player or local_body_with_tag("polymorphed_player")
    -- A saved spectator has no playable body. Its profile still has to bind
    -- to this EW peer before the host can authorize a reinforcement.
    if not run_id and not traveler and not (NHEW.enabled() and GameHasFlagRun("ew_flag_notplayer_active")) then return end
    if not attach() or not active_run() then return end
    local frame = GameGetFrameNum()
    NHRewind.update(state,player,commit_edit)
    if not active_run() then return end
    if state.ewDepositPending and NHEW.enabled() then
        local event,reason=NHEWDeposit.update(state,player,NHEWDeposit.canAccess)
        if event then
            model_cache=nil
            if event=="stored" then feedback(tr("物品已入库。","Item deposited."))
            elseif event=="cancelled" then feedback(tr("入库申请已撤销。","Deposit cancelled."))
            elseif reason then report(reason) end
        end
    end
    if state.ewReinforcePending and frame%10==0 then
        NHEWReinforce.settle()
        if not state then return end
    end
    if frame%10==0 and NHEW.enabled() and (state.ewReinforceSponsors or GlobalsGetValue("nh_ew.reinforce_sponsor_offer","")~="") then
        NHEWReinforce.updateSponsor()
        if not state then return end
    end
    if frame%60==0 then
        turretRuntime.upgradeEmplacements()
        turretRuntime.upgradeWorkshopDecoys()
    end
    if player and frame%60==0 then tarotRuntime.refreshLifeIcons(player) end
    local mimicFrames
    if not player then
        NHRelics.update(state,nil)
        local active,frames=ammoRuntime.guardMimic(traveler)
        if active then mimicFrames=frames; NHRewind.polymorph(traveler,state)
        else rescue.polymorph(state,traveler) end
    end
    if not traveler then
        NHCompanions.observeProduction(state,nil,frame,nil)
        NHClock.suspend(); NHFarm.suspendClock(); opened,case_open=false,nil
        return
    end
    local wallet_now=NHEW.walletAllowed()
    if wallet_now~=wallet_allowed then
        wallet_allowed,bank_synced,model_cache=wallet_now,false,nil
    end
    if player and wallet_now and not bank_synced then
        local reason
        bank_synced,reason=NHBank.reconcile(state,player)
        if bank_synced then model_cache=nil else report(reason) end
    end
    if player then
        rescue.arm(state,player)
        local source,kept,lost=rescue.settle(state,player,home_x,home_y,commit_edit,travel.rescue)
        if not state then return end
        if source then
            local who=source=="policy" and tr("保险","Insurance") or tr(NHCompanions.species[source].zh,NHCompanions.species[source].en)
            local msg=tr("救援，正在转送母舰。保留 %d 金，遗落 %d 金。"," rescue en route to the mothership. Kept %d gold, lost %d.")
            GamePrint(who..msg:format(kept,lost))
            rescue.arm(state,player)
        end
        travel.update(player,home_x,home_y,inventory_open or opened)
    end
    local farm_time=NHFarm.observe(state,frame)
    NHCompanions.observeProduction(state,farm_time,frame,player)
    if not update_workshop(traveler,frame,farm_time) then return end
    if not player then
        opened,case_open=false,nil
        if mimicFrames and mimicFrames>0 then NHUI.draw({mimicFrames=mimicFrames,lang=lang}) end
        return
    end
    deliverGift(player,lang,active_draft,save)
    if not state then return end
    if not inventory_open and not opened then pickup_press(player,true) end
    if not ammoRuntime.gold(state,commit_edit) then return end
    local katanaView=katanaRuntime.update(state,player,commit_edit,not inventory_open and not opened)
    if not state then return end
    local ammoKey=tonumber(ModSettingGet("noita_hideout.ammo_key")) or 5
    if ammoKey==21 then ammoKey=5 end
    local ammoView,castMimic=ammoRuntime.update(state,player,commit_edit,{enabled=not inventory_open and not opened,canMimic=shieldRuntime.canMimic,
        pressed=InputIsKeyJustDown(ammoKey),down=InputIsKeyDown and InputIsKeyDown(ammoKey),reload=InputIsKeyJustDown(21),keyName=string.char(65+ammoKey-4)})
    if not state then return end
    pickup.finishPickups(state,player)
    fireSupport.update(state,player,commit_edit,report)
    if not active_run() then return end
    if not inventory_open and not opened then
        local held=NHNative.held(player)
        if gun and gun==held and EntityHasTag(held,"nh_red_relic") then
            relic_feedback(NHRedRelics.activate(state,player,held))
        elseif gun and gun==held then NHProducts.fireHeld(player)
        else NHProducts.poseSupportGun(player,held) end
    end
    local restored
    if used and (used.container=="held" or used.container=="native") then
        restored=NHNative.recoverUseSlot(player,used,place_in_slot)
    end
    if frame % 60 == 0 then
        local ok, err = NHTransfers.reconcile(state, player)
        if ok then ok, err = NHDoses.reconcile(state, player) end
        if ok then NHPerks.update(state,player,not NHPerks.enabled) end
        if not ok then invalidate(); report(err); return end
    end
    local was_open,was_case_open = opened,case_open
    if popup and not popup_accessible(player) then
        popup=nil
        if not case_open then close_panel() end
    end
    if inventory_open then
        opened,case_open=true,true
        -- A held right click can reach us just as the engine opens the inventory.
        if used and used.container=="held" and used.owner==player and (NHNative.held(player)==used.entity or restored)
            and NHEquipment.links[NHTransfers.item_kind(used.entity)] then use_carried(player,used.entity,used) end
    elseif case_open then
        close_panel()
    elseif popup then
        if InputIsKeyJustDown(41) then close_panel() end
    elseif used and used.container=="held" and used.owner==player then
        if NHNative.held(player)==used.entity then use_carried(player,used.entity)
        elseif restored then use_carried(player,used.entity,used) end
    end
    if not active_run() then return end
    local nearby,at_station,landmark_name,remote_linked=near_hideout(player)
    -- Discoveries made outside the hideout can unlock vanilla spells without changing its inventory.
    if case_open and (not was_case_open or (nearby and model_cache and not model_cache.near)) then model_cache=nil end
    local model = opened and inventory_view() or {}
    model.fireSupport=not opened and fireSupport.view(state,player) or nil
    model.travel=(case_open or not opened) and travel.view() or nil
    model.ammo=ammoView
    model.katana=katanaView
    model.shield=shieldRuntime.sync(state,player)
    model.rescue=rescue.view(state,player)
    model.deployment=not opened and (turretRuntime.heldPreview(player) or remoteTerminal.heldPreview(player,nearby)) or nil
    if case_open then
        model.gear={shield=state.gearShield and stored_view(state.gearShield),charger=state.gearCharger and stored_view(state.gearCharger),
            rig=state.gearRig and stored_view(state.gearRig),ammo=state.gearAmmo and stored_view(state.gearAmmo),
            link=state.gearLink and stored_view(state.gearLink)}
        if model.gear.shield and model.shield then model.gear.shield.charge=model.shield.charge end
    else model.gear=nil end
    if opened and nearby then
        model.bankGold=state.bankGold
        model.walletGold,model.walletInfinite=NHBank.wallet(player)
        model.ewWalletPaused=not wallet_now
        if not bank_synced then model.walletGold=nil end
        model.farm=NHFarm.view(state,lang,farm_time)
    end
    if opened and state.order then
        model.order_remaining=math.ceil((state.order.required-NHClock.observe(state,frame))/60)
    end
    if opened and (case_open or popup) then model.native_slots=native_slots(player) end
    model.rightUse=used and used.container~="held" and used or nil
    model.popup = popup ~= nil
    model.gunId=nil
    model.walletId,model.pouchId,model.cells,model.pouchName=nil,nil,nil,nil
    model.walletCapacity,model.pouchCapacity,model.chainId=nil,nil,nil
    if popup and popup.kind=="firearm" then
        local gun=NHFirearms.stored(state,popup)
        local a,b=NHFirearms.mods.parse(gun.configured)
        model.gunId,model.pouchCapacity,model.cells=popup.id,2,{a,b}
        model.pouchName=tr("枪械配件","Gun attachments")
    elseif popup and popup.kind=="relic_chain" then
        local chain=NHRelics.chain(state,popup)
        model.chainId,model.pouchName=chain.id,tr("遗物链","Relic chain")
        model.pouchCapacity,model.cells=NHRelics.capacity(state),{}
        for cell,row in pairs(chain.item.cells) do model.cells[cell]=stored_view(row) end
    elseif popup and popup.kind=="card_wallet" then
        local wallet=NHCardWallets.get(state,player,popup)
        local d=NHEquipment.get("card_wallet",wallet.item.tier)
        model.walletId,model.pouchName=popup.id,tr(d.zh,d.en).." #"..popup.id
        model.cells=wallet.item.cells or {}
        model.walletCapacity=d.capacity
    elseif popup then
        local pouch=state.pouches[popup.id]
        local d=NHEquipment.get("pouch",pouch.tier)
        model.pouchId,model.pouchName=popup.id,tr(d.zh,d.en).." #"..popup.id
        model.cells,model.pouchCapacity=pouch.cells,d.capacity
    end
    model.mode = case_open and "case" or (popup and "container" or "closed")
    model.ewDeposit=state.ewDepositPending and NHEWDeposit.view(state) or nil
    model.open, model.near, model.lang, model.status = opened, nearby, lang, status
    model.at_station=at_station
    model.landmarkName=not opened and landmark_name or nil
    model.remote_linked=remote_linked
    model.terminals=remoteTerminal.view()
    model.turretStatus=not opened and not model.fireSupport and turretRuntime.status(player) or nil
    model.surgery=NHSurgery.view()

    if case_open and NHPerks.enabled then NHPerks.view(state,player,model) end
    model.debug = opened and ModSettingGet("noita_hideout.test_tools") ~= false
    NHUI.draw(model, function(action, index)
        -- Ignore transfers on the frame that opens the panel.
        if was_open and opened and (not case_open or was_case_open) then dispatch(player, action, index) end
    end)
    if state then NHRelics.update(state,player) end
    if state and castMimic then castMimic(shieldRuntime,state) end
end

OnWorldPreUpdate=terminalAccess.duringUpdate(OnWorldPreUpdate)
OnWorldPostUpdate=terminalAccess.duringUpdate(OnWorldPostUpdate)

function OnPlayerDied()
    tarotSight.reset()
    fireSupport.reset()
    ammoRuntime.reset()
    NHRelics.update(state,nil)
    NHSurgery.reset()
    NHHomeWandEdit.update(nil,false)
    popup=nil
    opened, case_open = false, nil
    -- EW can revive this same player. A death callback alone cannot close
    -- the expedition or discard their carried injector pouch.
    if NHEW.enabled() then return end
    if GlobalsGetValue(run_key, "") == "" then return end
    next_attempt = 0
    if not attach() or not active_run() then return end
    if not ammoRuntime.gold(state,commit_edit) then return end
    local elapsed=NHClock.observe(state,GameGetFrameNum())
    local farm_time=NHFarm.observe(state,GameGetFrameNum())
    local order_id=state.order and state.order.id or false
    commit_edit(function(draft)
        NHStore.advanceProduction(draft,{run=run_id,orderId=order_id,progress=elapsed,checkpoint=next(pending_visits)})
        NHFarm.sync(draft,farm_time)
        return NHStore.endRun(draft,run_id)
    end)
end
