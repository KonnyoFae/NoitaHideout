local settings,flags={},{}
local fail_key
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value)
    if key==fail_key then error("Injected save failure") end
    settings[key]=value
end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local function spell(id,uses,stack)
    return {kind="spell",card={id=id,stack=stack,item={uses_remaining=uses}}}
end
local state=assert(NHStore.load())
local function deposit(item)
    local id=state.nextItemId
    state.nextItemId=id+1
    local slot=assert(NHStore.freeSlot(state,"warehouse",nil,item.kind))
    table.insert(state.warehouse,{item=item,slot=slot,id=id})
    return {id=id,kind=item.kind,slot=slot,mode="essence"}
end

local healing="essence_healing"
local bomb=deposit(spell("BOMB",0))
assert(not NHStore.salvage(state,bomb) and #state.warehouse==1)
state.levels.salvage=1
-- The request cannot choose the payout resource, amount or source spell.
bomb.resource,bomb.amount,bomb.action_id=healing,99,"HEAL_BULLET"
assert(NHStore.salvage(state,bomb) and state.resources.essence_high_energy==375)
assert(not state.resources[healing] and not state.resources.arcane_scrap)
for _,uses in ipairs({20,7,0,-1}) do
    local item=spell("HEAL_BULLET",uses)
    local amount,key=NHStore.salvageYield(item,"essence")
    assert(amount==175 and key==healing)
    assert(NHStore.salvage(state,deposit(item)))
end
assert(state.resources[healing]==700)

-- A captured spell stack counts cards. A replacement in the same slot keeps
-- its own ID even if a confirmation from the old card is replayed.
local stack=deposit(spell("ANTIHEAL",0,3))
assert(not NHStore.salvage(state,bomb))
assert(NHStore.salvage(state,stack) and state.resources[healing]==700+3*567)
assert(not NHStore.salvage(state,stack))
for _,id in ipairs({"RANDOM_PROJECTILE","ACID_TRAIL","SEA_ACID","MOD_SPELL"}) do
    local item=spell(id,0)
    local req=deposit(item)
    assert(not NHStore.salvageYield(item,"essence"))
    assert(not NHStore.salvage(state,req) and #state.warehouse==1)
    req.mode="scrap"
    assert(NHStore.salvage(state,req))
end
assert(state.resources.arcane_scrap==4)
local mapped=deposit(spell("CLOUD_ACID",0,2))
mapped.mode="bogus"
assert(not NHStore.salvage(state,mapped) and not state.resources.essence_acid)
mapped.mode=nil
assert(NHStore.salvage(state,mapped) and state.resources.arcane_scrap==6)
local wand={kind="wand",cards={spell("BOMB",0).card}}
assert(not NHStore.salvageYield(wand,"essence") and NHStore.salvageYield(wand)==3)

local cap=NHStore.maxResourceAmount
state.resources[healing]=cap-349
local near_cap=deposit(spell("HEAL_BULLET",0,2))
assert(not NHStore.salvage(state,near_cap) and #state.warehouse==1 and state.resources[healing]==cap-349)
state.resources[healing]=cap-350
assert(NHStore.commit(state))

-- A rejected commit preserves both the warehouse card and the old balance
-- in the profile. Retrying then reloading can credit the batch only once.
assert(NHStore.salvage(state,near_cap) and state.resources[healing]==cap)
fail_key="noita_hideout.p1_revision"
assert(not NHStore.commit(state))
fail_key=nil
state=assert(NHStore.load())
assert(#state.warehouse==1 and state.resources[healing]==cap-350)
assert(NHStore.salvage(state,near_cap) and NHStore.commit(state))
state=assert(NHStore.load())
assert(#state.warehouse==0 and state.resources[healing]==cap and not NHStore.salvage(state,near_cap))
assert(state.resources.essence_high_energy==375 and not state.materials[healing])
print("Essences: full-card values, real action IDs, stacks, scrap fallback, capacity and atomic save replay passed.")
