local settings,flags,failHead={},{},false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v)
    if failHead and k:match("_revision$") then error("interrupted commit") end
    settings[k]=v
end
function HasFlagPersistent(k) return flags[k]==true end
function AddFlagPersistent(k) flags[k]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

-- The entity codec has its own integration spec. Simulate its returned snapshot here.
NHWand={generateDiscovery=function(seed)
    return {kind="wand",template=("data/entities/items/wand_level_%02d.xml"):format(1+seed%3),
        ability={mana_max=seed},cards={{id="LIGHT_BULLET"},{id="SPITTER"}}}
end}
local function load() return assert(NHStore.load()) end
local recipes={}
for _,r in ipairs(NHStore.recipes) do recipes[r.id]=r end
local world=1729
function StatsGetValue(key) if key=="world_seed" then return tostring(world) end end
local first,other=load(),load()
NHDragonLoot.award(first,1)
world=937
NHDragonLoot.award(other,1)
assert(first.dragonLoot.seed~=other.dragonLoot.seed)
local continuation=first.dragonLoot.seed
NHDragonLoot.award(first,1)
world=27
other.dragonLoot.seed=continuation
NHDragonLoot.award(other,1)
assert(other.dragonLoot.seed==first.dragonLoot.seed)

local s=load()
local totals={spell=0,containers=0,bag=0,box=0,wand=0,tarot=0,card=0,dragon=0}
local seen,spellSeed,spellTemplate={}
-- The first 33 seeds permute the rare group and the next 67 the supply
-- group. Continue to exercise the real item selection for every variant.
for seed=1,10000 do
    s.warehouse={}
    s.dragonLoot={seed=seed,rareProgress=(seed-1)%100<33 and 99 or 0,pending={}}
    local cards=NHDragonLoot.award(s,1)
    assert(#s.warehouse==1 and NHDragonLoot.pendingCount(s)==0)
    local item=s.warehouse[1].item
    local category=NHStore.category(item.kind)
    local key
    if item.kind=="summon_card" then
        assert(item.remaining==NHCompanions.cardCapacity(item.species) and NHCompanions.validCard(item))
        if NHTarot.types[item.species] then
            assert(#cards==1 and cards[1]==item.species and NHCompanions.rewardText(cards,"en",s):find("Cards found",1,true))
            category="tarot"
        else
            assert(#cards==1 and cards[1]==item.species)
            category=item.species=="dragon" and "dragon" or "card"
        end
        key="card_"..item.species
    else
        assert(#cards==0)
        if item.kind=="spell" then
            key="spell_"..item.card.id
            local template=recipes[key].item
            assert(item.card.item.uses_remaining==template.card.item.uses_remaining and item.card.useDefaultPickups)
            assert(item.card~=template.card and item.card.item~=template.card.item and item.icon==template.icon)
            if item.card.id=="BOMB" then spellSeed,spellTemplate=seed,template end
        elseif item.kind=="potion" then
            key=next(item.materials)
            local capacity=(key=="sand" or key=="gunpowder") and 1500 or 1000
            assert(NHPotion.fillLevel(item)==capacity and item.capacity==capacity and not next(item.materials,key))
            assert(NHPotion.dockSlot(item)==((key=="sand" or key=="gunpowder") and 2 or 1))
        elseif item.kind=="wand" then
            key=item.template
            assert(not item.discovery and #item.cards==2)
        else
            key=item.kind
            assert(NHLootBags.types[key] and item.count==1 and item.icon)
            category=NHLootBags.types[key].loot and "box" or "bag"
        end
    end
    seen[key]=true
    if seed<=100 then totals[category]=totals[category]+1 end
end
assert(totals.spell==10 and totals.containers==32 and totals.bag==20 and totals.box==15 and totals.wand==5 and totals.tarot==10 and totals.card==5 and totals.dragon==3)
for _,species in ipairs(NHCompanions.order) do assert(seen["card_"..species],species) end
for _,species in ipairs(NHTarot.order) do assert(seen["card_"..species],species) end
for _,key in ipairs({"water","slime",
    "magic_liquid_unstable_teleportation","sand","gunpowder","travel_satchel","travel_pack","loot_case","supply_pack","improved_supply_pack","advanced_supply_pack"}) do
    assert(seen[key],key)
end

-- A missing progress field is a pre-upgrade book. Old completed cycles
-- retain their exact reward and do not advance the new economy.
do
    local draft=load()
    draft.dragonLoot={seed=100,pending={}}
    assert(NHDragonLoot.rareProgress(draft)==0)
    local legacy=NHDragonLoot.award(draft,1,true)
    assert(#legacy==1 and legacy[1]=="dragon" and NHDragonLoot.rareProgress(draft)==0)
    local rareCount,lastRare=0,0
    for i=1,100 do
        draft.warehouse={}
        NHDragonLoot.award(draft,1)
        local kind=draft.warehouse[1].item.kind
        local rare=kind=="summon_card" or kind=="spell" or kind=="wand"
        assert(rare==(math.floor(i*33/100)>math.floor((i-1)*33/100)))
        assert(NHDragonLoot.rareProgress(draft)==(33*i)%100)
        if rare then
            assert(i-lastRare==3 or i-lastRare==4)
            rareCount,lastRare=rareCount+1,i
        end
    end
    assert(rareCount==33)
    for _,invalid in ipairs({-1,0.5,100}) do
        draft.dragonLoot.rareProgress=invalid
        assert(not NHStore.commit(draft))
    end
end
-- The old slime-flask key and the new slime-maiden key must survive a
-- delayed delivery in the same snapshot and use their separate warehouses.
s=load()
s.dragonLoot={seed=100,pending={slime=1,sand=1,card_slime=1}}
assert(NHDragonLoot.pendingCards(s)==1)
assert(NHStore.commit(s))
s=load()
local flask=s.warehouse[assert(NHStore.slotIndex(s,"warehouse",1,"potion"))].item
local slimeCard=s.warehouse[assert(NHStore.slotIndex(s,"warehouse",1,"summon_card"))].item
assert(flask.materials.slime==1000 and slimeCard.species=="slime" and slimeCard.remaining==80)
local bag=s.warehouse[assert(NHStore.slotIndex(s,"warehouse",2,"potion"))].item
assert(bag.variant=="powder_stash" and bag.capacity==1500 and bag.materials.sand==1500)
-- The rest of this suite starts with an empty profile.
settings,flags={},{}

-- Occupy every spell slot, including the one reserved for an unfinished
-- workshop order. A due nest must retain this exact discovery across reloads.
s=load()
NHStore.newRun(s)
s.levels.salvage=1
s.resources.essence_high_energy=recipes.spell_BOMB.resources.essence_high_energy
local capacity=NHStore.warehouseCapacity(s,"spell")
for slot=1,capacity-1 do
    s.warehouse[slot]={id=s.nextItemId,slot=slot,item=recipes.spell_LIGHT_BULLET.item}
    s.nextItemId=s.nextItemId+1
end
assert(NHStore.startOrder(s,"spell_BOMB") and s.order.output.slot==capacity)
s.dragonLoot={seed=assert(spellSeed),rareProgress=99,pending={}}
assert(#NHDragonLoot.award(s,1)==0 and s.dragonLoot.pending.spell_BOMB==1)
local committedSeed=s.dragonLoot.seed
assert(NHStore.commit(s))
s=load()
assert(s.dragonLoot.seed==committedSeed and s.dragonLoot.pending.spell_BOMB==1 and #s.warehouse==capacity-1)
assert(NHDragonLoot.rareProgress(s)==32)
table.remove(s.warehouse,1)
failHead=true
assert(not NHStore.commit(s))
assert(s.dragonLoot.pending.spell_BOMB==1 and #s.warehouse==capacity-2)
assert(load().dragonLoot.pending.spell_BOMB==1 and #load().warehouse==capacity-1)
failHead=false
assert(NHStore.commit(s))
s=load()
local discovery=s.warehouse[assert(NHStore.slotIndex(s,"warehouse",1,"spell"))].item
assert(discovery.card.id==spellTemplate.card.id and discovery.card.item.uses_remaining==3)
assert(NHDragonLoot.pendingCount(s)==0 and s.dragonLoot.seed==committedSeed and NHDragonLoot.rareProgress(s)==32)
assert(NHStore.commit(s) and #load().warehouse==capacity-1)

-- A pending full-charge card merges into a compatible stack even in a full
-- collection. A worn card remains unchanged and each discovery counts once.
local collection=NHStore.warehouseCapacity(s,"collection")
for slot=1,collection do
    local remaining=slot==1 and 79 or 80
    local species=slot==2 and "dragon" or (slot==1 and "dragon" or "dryad")
    s.warehouse[#s.warehouse+1]={id=s.nextItemId,slot=slot,item=NHCompanions.withCount({species=species,remaining=remaining},1)}
    s.nextItemId=s.nextItemId+1
end
s.dragonLoot.pending={dragon=3,bee=1}
local beforeId=s.nextItemId
assert(NHStore.commit(s))
s=load()
assert(s.nextItemId==beforeId and NHDragonLoot.pendingCards(s)==1 and s.dragonLoot.pending.bee==1)
local function cardAt(slot) return s.warehouse[assert(NHStore.slotIndex(s,"warehouse",slot,"summon_card"))].item end
assert(cardAt(1).remaining==79 and (cardAt(1).count or 1)==1 and cardAt(2).count==4)
table.remove(s.warehouse,NHStore.slotIndex(s,"warehouse",collection,"summon_card"))
assert(NHStore.commit(s))
s=load()
assert(cardAt(collection).species=="bee" and NHDragonLoot.pendingCards(s)==0 and s.nextItemId==beforeId+1)
assert(NHStore.commit(s) and load().nextItemId==s.nextItemId)
print("Dragon nest: mutually exclusive loot, native records, reservations, full storage, racy commits and card delivery passed.")

-- Expand beyond the original eight, respect unlocks, and retain earned pending rewards.
do
    local ordinary,expected=0,0
    local extraSeen={}
    for _,r in ipairs(NHStore.recipes) do
        if r.category=="spell" then
            expected=expected+1
            if not r.unlockFlag then ordinary=ordinary+1 end
        end
    end
    assert(expected==158 and ordinary>100)
    local draft=load()
    for seed=1,25000 do
        draft.warehouse={}
        draft.dragonLoot={seed=seed,rareProgress=99,pending={}}
        NHDragonLoot.award(draft,1)
        local item=draft.warehouse[1].item
        if item.kind=="spell" then
            local r=assert(recipes["spell_"..item.card.id])
            assert(not r.unlockFlag or HasFlagPersistent(r.unlockFlag))
            extraSeen[item.card.id]=true
        end
    end
    local count=0
    for _ in pairs(extraSeen) do count=count+1 end
    assert(count==ordinary and extraSeen.HEAL_BULLET and extraSeen.BLACK_HOLE and extraSeen.TELEPORT_PROJECTILE and extraSeen.REGENERATION_FIELD)
    assert(not extraSeen.NUKE and not extraSeen.CLOUD_THUNDER)
    for _,r in ipairs(NHStore.recipes) do if r.unlockFlag then flags[r.unlockFlag]=true end end
    local all={}
    for seed=1,25000 do
        draft.warehouse={}
        draft.dragonLoot={seed=seed,rareProgress=99,pending={}}
        NHDragonLoot.award(draft,1)
        local item=draft.warehouse[1].item
        if item.kind=="spell" then all[item.card.id]=true end
    end
    count=0
    for _ in pairs(all) do count=count+1 end
    assert(count==expected and all.NUKE and all.CLOUD_THUNDER)
    local draft=load()
    draft.warehouse={}
    draft.dragonLoot={seed=17,pending={spell_NUKE=1,spell_HEAL_BULLET=1,spell_DISC_BULLET=1}}
    flags.card_unlocked_nuke=nil
    assert(NHStore.commit(draft))
    draft=load()
    local cards={}
    for _,row in ipairs(draft.warehouse) do if row.item.kind=="spell" then cards[row.item.card.id]=row.item.card.item.uses_remaining end end
    assert(cards.NUKE==1 and cards.HEAL_BULLET==20 and cards.DISC_BULLET==-1 and NHDragonLoot.pendingCount(draft)==0)
    print("Dragon spell diversity: "..ordinary.." default and "..expected.." fully unlocked spells; old/new pending rewards keep exact full charges.")
end

do
    local draft=load()
    draft.warehouse={}
    local function stock(item,slot)
        table.insert(draft.warehouse,{id=draft.nextItemId,slot=slot,item=item})
        draft.nextItemId=draft.nextItemId+1
    end
    stock(NHLootBags.item("travel_pack",5),1)
    for i=2,NHStore.warehouseCapacity(draft,NHStore.category("travel_pack")) do stock(NHLootBags.item("loot_case",1),i) end
    draft.dragonLoot={seed=2,pending={travel_pack=8,advanced_supply_pack=2,medical=1}}
    local original=draft.warehouse[1]
    assert(NHStore.commit(draft))
    assert(original.item.count==5 and draft.warehouse[1].item.count==13 and draft.dragonLoot.pending.advanced_supply_pack==2)
    table.remove(draft.warehouse,2)
    assert(NHStore.commit(draft))
    assert(not draft.dragonLoot.pending.advanced_supply_pack and draft.dragonLoot.pending.medical==1)
    table.remove(draft.warehouse,2)
    assert(NHStore.commit(draft))
    assert(not next(draft.dragonLoot.pending) and draft.warehouse[#draft.warehouse].item.kind=="medkit")
end

do
    local draft=load()
    draft.warehouse={}
    local capacity=NHStore.warehouseCapacity(draft,"wand")
    local before=7001
    for slot=1,capacity do
        draft.warehouse[slot]={slot=slot,id=draft.nextItemId,item=NHDragonLoot.wandItem("nest_wand_010")}
        draft.nextItemId=draft.nextItemId+1
    end
    draft.dragonLoot={seed=100,wandSeed=before,pending={random_wand=2,nest_wand_016=1}}
    assert(NHStore.commit(draft))
    draft=load()
    assert(draft.dragonLoot.wandSeed==before and NHDragonLoot.pendingCount(draft)==3)
    table.remove(draft.warehouse,1)
    local generator=NHWand.generateDiscovery
    NHWand.generateDiscovery=function() return nil,"missing entity" end
    -- The old fixed wand can still be delivered when generation fails.
    assert(NHStore.commit(draft))
    draft=load()
    assert(draft.dragonLoot.pending.random_wand==2 and draft.dragonLoot.wandSeed==before)
    assert(draft.warehouse[#draft.warehouse].item.discovery=="nest_wand_016")
    NHWand.generateDiscovery=generator
    table.remove(draft.warehouse,1)
    failHead=true
    assert(not NHStore.commit(draft) and draft.dragonLoot.wandSeed==before)
    failHead=false
    assert(NHStore.commit(draft))
    draft=load()
    assert(draft.warehouse[#draft.warehouse].item.ability.mana_max==before and draft.dragonLoot.pending.random_wand==1)
    local nextSeed=draft.dragonLoot.wandSeed
    assert(nextSeed~=before)
    table.remove(draft.warehouse,1)
    assert(NHStore.commit(draft))
    draft=load()
    assert(not next(draft.dragonLoot.pending) and draft.warehouse[#draft.warehouse].item.ability.mana_max==nextSeed)
end
