NHCompanions={durability=80,order={"dryad","flower_fairy","minotaur","griffin","bee","dragon","slime","dog","cat"}}
NHTarot=NHTarot or dofile("mods/noita_hideout/files/tarot.lua")
function NHCompanions.cardDefinition(id) return NHCompanions.species[id] or NHTarot.types[id] end
function NHCompanions.cardCapacity(id) return NHTarot.types[id] and NHTarot.durability or NHCompanions.durability end
local items="mods/noita_hideout/files/items/"
local pets="mods/noita_hideout/files/companions/"
NHCompanions.species={
    cat={zh="猫娘",en="Cat maiden",role="support",
        combatZh="黑焰之道，诅咒靠近玩家的敌人",combatEn="Casts Path of Dark Flame and curses nearby enemies"},
    dog={zh="犬娘",en="Hound maiden",role="melee",radius=22,
        combatZh="连锁魔弹，敌人靠近时召唤魔法护卫",combatEn="Fires Chain Bolt and summons Magic Guard at close range"},
    dryad={zh="树精",en="Dryad",role="support",effect="effect_protection_radioactivity",
        combatZh="召唤岩石精灵，敌人靠近时发射终结锯刃",combatEn="Summons a rock spirit and fires an Omega Sawblade at close range"},
    flower_fairy={zh="花妖",en="Flower fairy",role="support",
        combatZh="在远敌上方降下酸雨，近身时改用花粉阻挡",combatEn="Calls acid rain over distant foes and switches to pollen at close range"},
    minotaur={zh="米诺陶少女",en="Minotaur maiden",role="melee",radius=34,shield=true,
        combatZh="神圣投枪狙击，敌人靠近时召唤大型魔法护卫",combatEn="Snipes with Holy Lance and summons Big Magic Guard at close range"},
    griffin={zh="狮鹫少女",en="Griffin maiden",role="flight",lift=30,fuel=8,
        combatZh="发射球状闪电，以强气流击退近敌",combatEn="Fires Ball Lightning and repels nearby foes with bursts of air"},
    bee={zh="蜂娘",en="Bee maiden",role="flight",lift=15,fuel=10,effect="effect_movement_faster",
        combatZh="召唤五只黄蜂追敌，三只护卫蜂环绕玩家挡弹",combatEn="Sends five wasps after foes while three guard bees orbit you"},
    dragon={zh="龙娘",en="Dragon maiden",role="flight",lift=20,fuel=6,shield=true,
        combatZh="喷吐龙息，跟随玩家攻击释放物质吞噬力场",combatEn="Breathes dragon fire and fires a matter-eating field when you attack"},
    slime={zh="凝胶少女",en="Gel maiden",role="support",
        combatZh="召唤萤火虫群，敌人靠近时释放冰冷凝视",combatEn="Summons firebugs and casts Freezing Gaze at close range"},
}
-- Percentages refer to max HP, max flight fuel or the player's unmodified speed.
NHCompanions.bonuses={
    [0]={giftLevel=1,heal=0.5,speed=10,mana=2,lift=0,fuel=0,fieldDamage=12,meleeResist=20,shieldRecharge=0},
    [1]={giftLevel=1,heal=1,speed=15,mana=4,lift=5,fuel=3,fieldDamage=16,meleeResist=30,shieldRecharge=0.08},
    [2]={giftLevel=2,heal=1.5,speed=20,mana=6,lift=10,fuel=6,fieldDamage=20,meleeResist=40,shieldRecharge=0.15},
    [3]={giftLevel=3,heal=2,speed=30,mana=8,lift=15,fuel=9,fieldDamage=24,meleeResist=50,shieldRecharge=0.22},
}
function NHCompanions.giftMinutes(spec) return spec.role=="support" and 2 or 3 end
local families={cat_house={"cat"},dog_kennel={"dog"},farm={"dryad","flower_fairy"},livestock={"minotaur","griffin"},beehive={"bee"},gel_pool={"slime"}}
local seedOffsets={cat_house=87109,dog_kennel=79190,farm=126,livestock=7918,beehive=15836,gel_pool=23754}
local modulus=2147483647

function NHCompanions.cardIcon(id)
    return items.."card_"..id..".png"
end

local function card(id,remaining)
    return {kind="summon_card",species=id,remaining=remaining,name="$nh_card_"..id,icon=NHCompanions.cardIcon(id)}
end

function NHCompanions.withCount(item,count)
    local result=card(item.species,item.remaining)
    if count>1 then result.count=count end
    return result
end

function NHCompanions.validCard(item)
    local n=item.remaining
    local count=item.count
    return NHCompanions.cardDefinition(item.species)~=nil and type(n)=="number" and n==math.floor(n) and n>=1 and n<=NHCompanions.cardCapacity(item.species)
        and (count==nil or (type(count)=="number" and count==math.floor(count) and count>=1 and count<=NHStore.maxResourceAmount
            and (n==NHCompanions.cardCapacity(item.species) or count==1)))
end

function NHCompanions.canStack(target,source)
    return target and source and target.kind=="summon_card" and source.kind=="summon_card"
        and target.species==source.species and target.remaining==NHCompanions.cardCapacity(target.species)
        and source.remaining==NHCompanions.cardCapacity(source.species) and (target.count or 1)<NHStore.maxResourceAmount
end

-- A specified storage slot must accept the card; automatic deposits prefer
-- an existing full-condition stack even when every storage slot is occupied.
function NHCompanions.cardSlot(s,container,preferred,item,quantity)
    if container~="warehouse" and container~="safe" then return end
    local function fits(target)
        return NHCompanions.canStack(target,item) and (quantity or 1)<=NHStore.maxResourceAmount-(target.count or 1)
    end
    if preferred then
        local index=NHStore.slotIndex(s,container,preferred,"summon_card")
        if index then
            if fits(s[container][index].item) then return preferred,index end
            return
        end
    else
        local slot,at
        for i,row in ipairs(s[container]) do
            if fits(row.item) and (not slot or (row.slot or i)<slot) then
                slot,at=row.slot or i,i
            end
        end
        if at then return slot,at end
    end
    return NHStore.freeSlot(s,container,preferred,"summon_card")
end

-- Replace rows to keep shallow transfer drafts isolated until their commit succeeds.
function NHCompanions.put(s,container,slot,index,item,id,origin)
    if not slot then return false end
    local rows=s[container]
    if index then
        local row=rows[index]
        local count=row.item.count or 1
        local added=item.count or 1
        if not NHCompanions.canStack(row.item,item) or added>NHStore.maxResourceAmount-count then return false end
        rows[index]={id=row.id,origin=row.origin,slot=slot,item=NHCompanions.withCount(item,count+added)}
    else
        if not id then
            if s.nextItemId>=NHStore.maxResourceAmount then return false end
            id=s.nextItemId
            s.nextItemId=id+1
        end
        rows[#rows+1]={id=id,origin=origin,slot=slot,item=item}
    end
    return true
end

function NHCompanions.take(s,container,index)
    local rows=s[container]
    local row=rows[index]
    if not row or row.item.kind~="summon_card" then return end
    local count=row.item.count or 1
    if count==1 then return table.remove(rows,index) end
    if s.nextItemId>=NHStore.maxResourceAmount then return end
    rows[index]={id=row.id,origin=row.origin,slot=row.slot,item=NHCompanions.withCount(row.item,count-1)}
    local one={id=s.nextItemId,slot=row.slot,item=NHCompanions.withCount(row.item,1)}
    s.nextItemId=s.nextItemId+1
    return one
end

function NHCompanions.moveCard(s,from,sourceSlot,to,targetSlot,expectedId)
    if (from~="warehouse" and from~="safe") or (to~="warehouse" and to~="safe")
        or not targetSlot or (from==to and sourceSlot==targetSlot) then return false,"Inventory slot changed." end
    local index=NHStore.slotIndex(s,from,sourceSlot,"summon_card")
    local row=index and s[from][index]
    if not row or row.id~=expectedId or row.item.kind~="summon_card" then return false,"Inventory slot changed." end
    local slot,stack=NHCompanions.cardSlot(s,to,targetSlot,row.item)
    if not slot then return false,"Inventory slot changed." end
    local one=NHCompanions.take(s,from,index)
    if not one then return false,"Inventory slot changed." end
    if stack and from==to then stack=NHStore.slotIndex(s,to,targetSlot,"summon_card") end
    return NHCompanions.put(s,to,slot,stack,one.item,one.id,one.origin)
end

function NHCompanions.validate(state,whole)
    if state.giftRun~=nil or state.giftFrame~=nil then
        assert(whole(state.giftRun) and state.giftRun<=state.runSerial and whole(state.giftFrame),"Invalid companion gift receipt")
    end
    if not state.summons then return end
    for source in pairs(families) do
        local seed=state.summons[source]
        assert(seed==nil or (whole(seed) and seed>0 and seed<modulus),"Invalid summon reward sequence")
    end
    for id,amount in pairs(state.summons.pending) do
        assert(NHCompanions.species[id] and whole(amount) and amount>0,"Invalid pending summon cards")
    end
end

function NHCompanions.deliver(state)
    local pending=state.summons and state.summons.pending
    if not pending or not next(pending) then return end
    for _,id in ipairs(NHCompanions.order) do
        while pending[id] do
            local item=card(id,NHCompanions.durability)
            local slot,index=NHCompanions.cardSlot(state,"warehouse",nil,item)
            if not slot then break end
            local amount=pending[id]
            if index then amount=math.min(amount,NHStore.maxResourceAmount-(state.warehouse[index].item.count or 1)) end
            if not NHCompanions.put(state,"warehouse",slot,index,NHCompanions.withCount(item,amount)) then break end
            pending[id]=pending[id]>amount and pending[id]-amount or nil
        end
    end
end

-- Transfer drafts share their parent's reward book. Stage any delivery into
-- detached tables until the settings commit pointer has been published.
function NHCompanions.stageDelivery(state)
    local book=state.summons
    if not book or not next(book.pending) then return end
    local pending={}
    for id,n in pairs(book.pending) do pending[id]=n end
    state.summons={pending=pending}
    for source in pairs(families) do state.summons[source]=book[source] end
    local rows={}
    for i,row in ipairs(state.warehouse) do rows[i]=row end
    state.warehouse=rows
    NHCompanions.deliver(state)
end

function NHCompanions.grantSet(state)
    local book=state.summons or {pending={}}
    for _,id in ipairs(NHCompanions.order) do
        if (book.pending[id] or 0)>=NHStore.maxResourceAmount then return false,"Resource storage is full." end
    end
    state.summons=book
    for _,id in ipairs(NHCompanions.order) do book.pending[id]=(book.pending[id] or 0)+1 end
    NHCompanions.deliver(state)
    return true
end

-- One persistent roll per successful crop or animal production cycle, in the
-- same transaction as its produce, even when multiple batches are due.
function NHCompanions.income(state,source,units,found)
    local player=EntityGetWithTag and (EntityGetWithTag("player_unit") or {})[1]
    if not player then return end
    local id=NHCompanions.active(player)
    if not id then return end
    local eligible=source=="dragon"
    for _,candidate in ipairs(families[source] or {}) do
        if candidate==id then eligible=true end
    end
    if not eligible then return end
    local chance=NHAffinity.incomeBasisPoints(NHAffinity.points(state,id))
    if chance==0 then return end
    local seed=state.companionIncomeSeed or (1+state.profile*15485863%(modulus-1))
    local book=state.summons or {pending={}}
    state.summons=book
    for _=1,units do
        seed=seed*48271%modulus
        if seed%10000<chance and (book.pending[id] or 0)<NHStore.maxResourceAmount then
            book.pending[id]=(book.pending[id] or 0)+1
            found[#found+1]=id
        end
    end
    state.companionIncomeSeed=seed
end

function NHCompanions.reward(state,source,units)
    local family=assert(families[source])
    local book=state.summons or {pending={}}
    state.summons=book
    local seed=book[source]
    if not seed then
        local world=StatsGetValue and tonumber(StatsGetValue("world_seed")) or 0
        seed=1+(world%modulus+state.profile*15485863+seedOffsets[source])%(modulus-1)
    end
    local found={}
    for _=1,units do
        seed=seed*48271%modulus
        if seed%100<3 then
            if #family>1 then seed=seed*48271%modulus end
            local id=family[1+seed%#family]
            book.pending[id]=(book.pending[id] or 0)+1
            found[#found+1]=id
        end
    end
    book[source]=seed
    NHCompanions.income(state,source,units,found)
    NHCompanions.deliver(state)
    return found
end

function NHCompanions.rewardText(ids,lang,state)
    local names,hasTarot={},false
    local zh=lang=="zh"
    for _,id in ipairs(ids) do
        names[#names+1]=NHCompanions.cardDefinition(id)[zh and "zh" or "en"]
        if NHTarot.types[id] then hasTarot=true end
    end
    local label=hasTarot and (zh and "获得卡牌：" or "Cards found: ") or (zh and "获得召唤卡：" or "Summon cards: ")
    local message=label..table.concat(names,zh and "、" or ", ")
    if (state.summons and next(state.summons.pending)) or (NHDragonLoot and NHDragonLoot.pendingCards(state)>0) then
        return message..(zh and "。藏品库已满，腾出栏位后自动入库。" or ". Waiting for a free collection slot.")
    end
    return message
end

local function speciesOf(entity)
    for _,id in ipairs(NHTarot.order) do
        if EntityHasTag(entity,"nh_companion_"..id) then return id end
    end
    for _,id in ipairs(NHCompanions.order) do
        if EntityHasTag(entity,"nh_companion_"..id) then return id end
    end
end

function NHCompanions.captureCard(entity)
    local id=speciesOf(entity)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    if id and item then
        local record=card(id,ComponentGetValue2(item,"uses_remaining"))
        if NHCompanions.validCard(record) then return record end
    end
    return nil,"Invalid summon card."
end

function NHCompanions.registerItems()
    NHTransfers.registerItem("summon_card",function(entity) return EntityHasTag(entity,"noita_hideout_summon_card") end,{
        warehouseCategory="collection",
        capture=NHCompanions.captureCard,
        restore=function(record,x,y)
            if not NHCompanions.validCard(record) then return nil,"Invalid summon card." end
            local entity=EntityLoad(items.."card_"..record.species..".xml",x,y)
            if not entity or entity==0 then return nil,"Summon card could not be created." end
            local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
            if not item then EntityKill(entity); return nil,"Invalid summon card." end
            ComponentSetValue2(item,"uses_remaining",record.remaining)
            return entity
        end,
    })
end

function NHCompanions.active(player)
    for _,pet in ipairs(EntityGetAllChildren(player,"noita_hideout_companion") or {}) do
        local clock=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_companion_clock")
        if clock and ComponentGetValue2(clock,"value_int")<15*60*60 then
            local id=ComponentGetValue2(clock,"value_string")
            if NHCompanions.species[id] then return id,pet end
        end
    end
end

local function dismiss(entity)
    EntityRemoveFromParent(entity)
    EntityKill(entity)
end

-- Older worlds have only the per-effect tags. Native perks, food and
-- injectors with the same GameEffectComponent do not carry these tags.
local supportTags={"noita_hideout_companion_aura","nh_companion_effect_protection_radioactivity",
    "nh_companion_effect_protection_melee","nh_companion_effect_faster_levitation"}
local modifiers=dofile(pets.."modifiers.lua")
NHCompanions.immunities=dofile(pets.."immunities.lua")
NHCompanions.applyModifier=modifiers.apply
function NHCompanions.clearSupport(player)
    local hook=EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_dragon_shot")
    if hook then EntityRemoveComponent(player,hook) end
    NHCompanions.immunities.apply(player,nil)
    modifiers.clear(player)
    for _,tag in ipairs(supportTags) do
        for _,aura in ipairs(EntityGetAllChildren(player,tag) or {}) do
            dismiss(aura)
        end
    end
end

function NHCompanions.summon(player,id,lang,pay)
    if NHTarot.types[id] then return dofile("mods/noita_hideout/files/tarot_runtime.lua").apply(player,id,pay) end
    if not NHCompanions.species[id] then return end
    local previous=EntityGetAllChildren(player,"noita_hideout_companion") or {}
    local x,y=EntityGetTransform(player)
    local pet=EntityLoad(pets..id..".xml",x+12,y-8)
    if not pet or pet==0 then return end
    local clock=EntityGetFirstComponentIncludingDisabled(pet,"VariableStorageComponent","nh_companion_clock")
    if not clock or ComponentGetValue2(clock,"value_string")~=id then
        EntityKill(pet)
        return
    end
    EntityAddChild(player,pet)
    if EntityGetParent(pet)~=player then EntityKill(pet); return end
    local paid,reason=pay()
    if not paid then dismiss(pet); return nil,reason end
    -- The 64-pixel source frames are displayed at half size in the world.
    EntitySetTransform(pet,x+12,y-8,0,0.5,0.5)
    for _,child in ipairs(previous) do
        if EntityGetIsAlive(child) then dismiss(child) end
    end
    NHCompanions.clearSupport(player)
    EntityAddTag(pet,"nh_companion_roles")
    NHCompanions.immunities.apply(player,id)
    local spec=NHCompanions.species[id]
    GamePrint(lang=="zh" and (spec.zh.."开始随行。") or (spec.en.." joined you."))
    return true
end

function NHCompanions.use(player,entity,lang,fromInventory,tarotPay)
    if not entity or not EntityHasTag(entity,"noita_hideout_summon_card") then return end
    if fromInventory then
        local parent=EntityGetParent(entity)
        if not parent or parent==0 or EntityGetParent(parent)~=player or EntityGetName(parent)~="inventory_quick" then return end
    elseif GameIsInventoryOpen() or NHNative.held(player)~=entity then return end
    local id=speciesOf(entity)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    local remaining=item and ComponentGetValue2(item,"uses_remaining")
    if not NHCompanions.validCard({species=id,remaining=remaining}) then return end
    return NHCompanions.summon(player,id,lang,function()
        if NHTarot.types[id] and tarotPay and not tarotPay() then return false end
        if remaining==1 then GameKillInventoryItem(player,entity)
        else ComponentSetValue2(item,"uses_remaining",remaining-1) end
        return true
    end)
end
