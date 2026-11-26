local root="mods/noita_hideout/files/"
local K={order={"hf_blade","hf_murasama","dragon_king"},types={}}
-- shieldCostFraction is measured against one HUD shield cell.
K.zandatsu={chargeFrames=36,shieldPointsPerSecond=5,radius=160,shieldCostFraction=0.5,
    shieldRewardFraction=0.1,ammoReward=5,healthRewardFraction=0.05}
local modeZh="长按右键 0.6 秒固定消耗半格护盾，进入静滞斩夺。余额不足半格时无法启动。每格为最大生命的一半，初始每格 50 点，扣 25 点可维持 5 秒。每消耗 5 点护盾可维持 1 秒。期间移动受限。按住左键连续快斩，再按右键可提前退出。斩夺亲手击杀敌人恢复最大护盾的 10%、5 点弹挂备弹和最大生命的 5%。"
local modeEn="Hold right-click for 0.6 seconds to spend half of one shield cell and enter stasis Blade Mode. You need at least half a cell to activate it. One cell holds half your maximum HP (initially 50 points), so paying 25 points grants 5 seconds. Every 5 shield points spent grants 1 second. Movement is restricted. Hold left-click to slash repeatedly and press right-click again to leave early. Each direct Blade Mode kill restores 10% of maximum shield, 5 reserve ammo points and 5% of maximum HP."
K.types.hf_blade={zh="高频振动刀",en="High-frequency blade",scrap=12,chargeAttack="heavy",chargeFrames=30,
    quickDamage=2,quickReach=36,quickFxReach=30,quickLunge=10,quickLungeFrames=3,quickWidth=12,quickFrames=5,quickCooldown=10,
    heavyDamage=6,heavyReach=70,heavyFxReach=58,heavyLunge=32,heavyLungeFrames=4,heavyWidth=18,heavyFrames=7,heavyCooldown=24,
    noteZh="点按左键快斩，长按左键蓄力，松开重击。"..modeZh,
    noteEn="Tap left-click for a quick slash. Hold left-click and release for a charged heavy strike. "..modeEn}
K.types.hf_murasama={zh="高频村雨刀",en="High-frequency Murasama",scrap=24,chargeAttack="dash",chargeFrames=36,
    quickDamage=2.4,quickReach=39,quickFxReach=32,quickLunge=12,quickLungeFrames=3,quickWidth=12,quickFrames=5,quickCooldown=10,
    dashDamage=6,dashReach=60,dashFxReach=50,dashDistance=120,dashFrames=6,dashWidth=16,dashCooldown=24,ammoCost=5,
    noteZh="点按左键快斩；长按左键蓄满后，消耗 5 点已装备弹挂备弹，自动向准星疾冲拔刀。"..modeZh,
    noteEn="Tap left-click for a quick slash. Fully charge left-click to spend 5 points from the equipped ammo rig and automatically dash-slash toward the reticle. "..modeEn}
K.types.dragon_king={zh="龙王",en="Dragon King",durability=90,warehouseCategory="collection",
    chargeAttack="stasis_dash",chargeFrames=18,shortStasisFrames=120,
    quickDamage=3,quickReach=54,quickFxReach=46,quickLunge=14,quickLungeFrames=3,quickWidth=18,quickFrames=5,quickCooldown=10,
    dashDamage=8,dashReach=80,dashFxReach=68,dashDistance=160,dashFrames=8,dashWidth=20,dashCooldown=24,
    plunderDurationFrames=1800,plunderDurabilityCost=1,radius=160,freeMovement=true,
    noteZh="遗物太刀，无碎片制作配方。点按左键大范围快斩；长按左键 0.3 秒展开最多 2 秒的短暂静滞，松开向准星疾冲斩，全程免费。长按右键 0.6 秒仅消耗 1 点耐久，进入可自由移动的 30 秒静滞斩夺；按住左键连续快斩，再按右键提前退出。斩夺亲手击杀恢复最大护盾的 10%、5 点弹挂备弹和最大生命的 5%。耐久耗尽仍可快斩和使用免费左键技能。",
    noteEn="Relic katana; no scrap crafting recipe. Tap left-click for a wide slash. Hold left-click for 0.3 seconds to create up to 2 seconds of brief stasis; release to dash-slash toward the reticle, at no resource cost. Hold right-click for 0.6 seconds to spend only 1 durability for 30 seconds of stasis Blade Mode with free movement. Hold left-click to slash repeatedly; press right-click again to exit. Each direct Blade Mode kill restores 10% of maximum shield, 5 reserve ammo and 5% of maximum HP. At zero durability, quick slashes and the free left-click skill remain available."}
for kind,d in pairs(K.types) do
    d.kind=kind
    d.noteZh=d.noteZh.." 所有斩击都能把接触刀刃的子弹沿刀尖方向弹出，包括自己和友军的子弹。"
    d.noteEn=d.noteEn.." Any slash can deflect shots along the blade, including your own and your allies' shots."
    d.file=root.."items/"..kind..".xml"
    d.icon=root.."items/"..kind.."_icon.png"
    d.sprite=root.."items/"..kind.."_sprite.xml"
    d.gripX,d.gripY,d.scale=56,32,0.5
    d.action="NH_"..kind:upper()
end

function K.item(kind)
    local d=K.types[kind]
    if d then return {kind=kind,name="$nh_hideout_"..kind,icon=d.icon,remaining=d.durability} end
end

function K.valid(item)
    if type(item)~="table" or not K.types[item.kind] or (item.count~=nil and item.count~=1)
        or item.rounds~=nil or item.reserve~=nil then return false end
    local maximum=K.types[item.kind].durability
    if not maximum then return item.remaining==nil end
    local n=item.remaining
    return type(n)=="number" and n>=0 and n<=maximum and n==math.floor(n)
end

function K.recipe(kind)
    local d=assert(K.types[kind],"Unknown katana")
    if not d.scrap then return end
    return {id=kind,category="weapons",zh=d.zh,en=d.en,inputs={},resources={arcane_scrap=d.scrap},
        durationFrames=d.scrap*60,item=K.item(kind),noteZh=d.noteZh,noteEn=d.noteEn}
end

function K.kind(entity)
    if not entity or entity==0 then return end
    for _,kind in ipairs(K.order) do
        if EntityHasTag(entity,"noita_hideout_"..kind) then return kind end
    end
end

-- Keep the native wand lane and hand anchor, but let only the katana
-- controller use this item. An empty permanent action still starts vanilla's
-- gun/reload cycle when click_to_use is left at its default true value.
-- Repair the same entity so old saves keep their slot, cards and durability.
function K.repairNative(entity,kind)
    local actual=K.kind(entity)
    if not actual or (kind and actual~=kind) then return false end
    local ability=EntityGetFirstComponentIncludingDisabled(entity,"AbilityComponent")
    if not ability or not ComponentGetValue2(ability,"use_gun_script") then return false end
    ComponentSetValue2(ability,"click_to_use",false)
    ComponentObjectSetValue2(ability,"gun_config","reload_time",0)
    ComponentSetValue2(ability,"reload_time_frames",0)
    ComponentSetValue2(ability,"mReloadFramesLeft",0)
    ComponentSetValue2(ability,"mReloadNextFrameUsable",0)
    return true
end

-- The native gun system owns the weapon slot, while the katana runtime owns
-- combat. A permanent empty action prevents accidental native projectiles.
function K.ensureBuiltInAction(entity,kind)
    kind=kind or K.kind(entity)
    local d=K.types[kind]
    if not d or not K.repairNative(entity,kind) then return false end
    local card,item
    for _,child in ipairs(EntityGetAllChildren(entity) or {}) do
        local action=EntityGetFirstComponentIncludingDisabled(child,"ItemActionComponent")
        if action and ComponentGetValue2(action,"action_id")==d.action then
            card=child
            item=EntityGetFirstComponentIncludingDisabled(card,"ItemComponent")
            if not item then return false end
            if ComponentGetValue2(item,"permanently_attached") and ComponentGetValue2(item,"is_frozen") then return true end
            break
        end
    end
    if not card then
        local x,y=EntityGetTransform(entity)
        card=CreateItemActionEntity(d.action,x,y)
        if not card or card==0 then return false end
        item=EntityGetFirstComponentIncludingDisabled(card,"ItemComponent")
        if not item then EntityKill(card); return false end
        EntityAddChild(entity,card)
        EntitySetComponentsWithTagEnabled(card,"enabled_in_world",false)
        EntitySetComponentsWithTagEnabled(card,"enabled_in_hand",false)
    end
    ComponentSetValue2(item,"inventory_slot",0,0)
    ComponentSetValue2(item,"permanently_attached",true)
    ComponentSetValue2(item,"is_frozen",true)
    local owner=EntityGetRootEntity(entity)
    local inventory=EntityGetFirstComponentIncludingDisabled(owner,"Inventory2Component")
    if inventory then ComponentSetValue2(inventory,"mForceRefresh",true) end
    return true
end

function K.registerItems()
    for _,id in ipairs(K.order) do
        local kind=id
        local d=K.types[kind]
        NHProducts.icons[kind]=d.icon
        NHTransfers.registerItem(kind,function(entity) return EntityHasTag(entity,"noita_hideout_"..kind) end,{
            warehouseCategory=d.warehouseCategory or "wand",
            capture=function(entity)
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                local ability=EntityGetFirstComponentIncludingDisabled(entity,"AbilityComponent")
                if not item or not ability or not ComponentGetValue2(ability,"use_gun_script")
                    or EntityGetFirstComponentIncludingDisabled(entity,"ItemCostComponent") then return nil,"Katana unavailable." end
                -- The immutable katana record has no spell payload. Refuse
                -- foreign cards rather than destroying them during storage.
                for _,child in ipairs(EntityGetAllChildren(entity) or {}) do
                    local action=EntityGetFirstComponentIncludingDisabled(child,"ItemActionComponent")
                    if action and ComponentGetValue2(action,"action_id")~=d.action then
                        return nil,"Remove added spells before storing this katana."
                    end
                end
                local record=K.item(kind)
                if d.durability then record.remaining=ComponentGetValue2(item,"uses_remaining") end
                if not K.valid(record) then return nil,"Invalid katana durability." end
                return record
            end,
            restore=function(record,x,y)
                if not K.valid(record) or record.kind~=kind then return nil,"Invalid katana." end
                local entity=EntityLoad(d.file,x,y)
                if not entity or entity==0 then return nil,"Katana unavailable." end
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                local ability=EntityGetFirstComponentIncludingDisabled(entity,"AbilityComponent")
                if not item or not ability or not ComponentGetValue2(ability,"use_gun_script") or not K.ensureBuiltInAction(entity,kind) then
                    EntityKill(entity)
                    return nil,"Katana unavailable."
                end
                if d.durability then ComponentSetValue2(item,"uses_remaining",record.remaining) end
                return entity
            end,
        })
    end
end
return K
