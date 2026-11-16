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
local totals={spell=0,containers=0,supplies=0,card=0,dragon=0}
local seen,spellSeed,spellTemplate={}
-- The first 100 seeds permute every percentile exactly once. Continue to
-- inspect every variant in the pool without relying on random test outcomes.
for seed=1,1500 do
    s.warehouse={}
    s.dragonLoot={seed=seed,pending={}}
    local cards=NHDragonLoot.award(s,1)
    assert(#s.warehouse==1 and NHDragonLoot.pendingCount(s)==0)
    local item=s.warehouse[1].item
    local category=NHStore.category(item.kind)
    local key
    if item.kind=="summon_card" then
        assert(#cards==1 and cards[1]==item.species and item.remaining==80 and NHCompanions.validCard(item))
        category=item.species=="dragon" and "dragon" or "card"
        key=item.species
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
            assert(NHPotion.fillLevel(item)==500 and item.capacity==1000 and not next(item.materials,key))
            assert(NHPotion.dockSlot(item)==((key=="sand" or key=="gunpowder") and 2 or 1))
        else
            key=item.kind
            assert((item.count or 1)==1 and item.icon and item.name)
            if NHMedkits.types[key] then assert(item.remaining==NHMedkits.types[key].uses) end
        end
    end
    seen[key]=true
    if seed<=100 then totals[category]=totals[category]+1 end
end
assert(totals.spell==40 and totals.containers==28 and totals.supplies==24 and totals.card==5 and totals.dragon==3)
for _,key in ipairs({"dryad","flower_fairy","minotaur","griffin","bee","dragon","water","slime",
    "magic_liquid_unstable_teleportation","sand","gunpowder","medkit","bandage","bread","sugar_cube","metal_knife","grenade"}) do
    assert(seen[key],key)
end

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
s.dragonLoot={seed=assert(spellSeed),pending={}}
assert(#NHDragonLoot.award(s,1)==0 and s.dragonLoot.pending.spell_BOMB==1)
local committedSeed=s.dragonLoot.seed
assert(NHStore.commit(s))
s=load()
assert(s.dragonLoot.seed==committedSeed and s.dragonLoot.pending.spell_BOMB==1 and #s.warehouse==capacity-1)
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
assert(NHDragonLoot.pendingCount(s)==0 and s.dragonLoot.seed==committedSeed)
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
