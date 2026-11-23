local settings,flags={},{}
local fail=false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) if not fail then settings[k]=v end end
function HasFlagPersistent(k) return flags[k] or false end
function AddFlagPersistent(k) flags[k]=true end
dofile("mods/noita_hideout/files/store.lua")
local s=assert(NHStore.load())
NHStore.newRun(s)
s.materials={slime=500,magic_liquid_unstable_teleportation=500}
assert(NHStore.commit(s))
-- The UI operates on a detached draft: failed persistence delivers and spends nothing.
local draft=assert(NHStore.load())
assert(NHStore.craft(draft,"stable") and not draft.order and draft.finished==1)
fail=true
assert(not NHStore.commit(draft))
fail=false
s=assert(NHStore.load())
assert(s.finished==0 and s.materials.slime==500 and not s.materials.magic_liquid_teleportation)
assert(NHStore.craft(s,"stable") and not s.order and s.materials.magic_liquid_teleportation==500)
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(s.finished==1 and not s.order)
-- A second click is immediately available, with no elapsed frames required.
assert(NHStore.craft(s,"stable") and s.finished==2 and not s.order)
assert(s.materials.magic_liquid_teleportation==1000 and not s.materials.slime)
assert(NHStore.commit(s))
assert(not NHStore.craft(s,"stable") and s.finished==2 and s.materials.magic_liquid_teleportation==1000)
s.closedThrough=s.runSerial
assert(not NHStore.craft(s,"stable"))
print("Instant crafting: atomic payment/delivery, failed-save rollback, consecutive batches, missing ingredients and closed runs passed.")
