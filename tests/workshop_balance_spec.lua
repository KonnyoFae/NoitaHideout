-- Revision 1 from v0.34.0: a paid mana order two seconds in, started with
-- 350 water and one mana sample. Keep the original bytes and checksum so
-- loading this test exercises the same path as loading an existing save.
local oldSnapshot="NH1:1012333631:{s7:versionn1:1s8:revisionn1:1s9:runSerialn1:1s15:collectionSlotst"
    .."s7:profilen1:1s8:finishedn1:0s14:starterPouchIdn1:1s11:sharedSlotsts11:storageBase{}"
    .."s12:safeCapacityn1:2s5:docks{}s7:pouches{n1:1{s5:dosesn1:2s2:idn1:1s8:locations4:safe"
    .."s4:slotn1:2s5:cells{n1:1{s5:countn1:2s9:remainingn1:3}}}}s8:bankGoldn1:0"
    .."s9:materials{s5:watern3:100}s4:farm{s4:timen1:0s7:passivets5:plots{}}s9:warehouse{}"
    .."s10:nextItemIdn1:2s13:bankWalletNetn1:0s9:resources{}s6:levels{}s13:closedThroughn1:0"
    .."s11:checkpoints{}s5:order{s6:recipes4:manas9:catalysts{s30:magic_liquid_mana_regenerationn1:1}"
    .."s2:idn1:1s8:progressn3:120s8:requiredn4:7200s6:output{s9:materials{"
    .."s30:magic_liquid_mana_regenerationn3:251}}}s4:safe{}}"
local settings={["noita_hideout.profile_count"]=1,["noita_hideout.p1_revision"]=1,["noita_hideout.p1_a"]=oldSnapshot}
local flags={noita_hideout_profile_1=true,noita_hideout_profile_bound=true}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key]==true end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")

local byId={}
for _,recipe in ipairs(NHStore.recipes) do
    local frames=recipe.durationFrames
    assert(type(frames)=="number" and frames>=60 and frames<=180*60 and frames%60==0,
        recipe.id.." needs an explicit duration in whole seconds between 1 and 180")
    assert(NHStore.productionFrames(recipe)==frames,recipe.id)
    byId[recipe.id]=recipe
end
for _,id in ipairs({"bandage","medical","field_medkit","bread","sugar_cube","card_wallet","pouch",
    "flare_gun","sedative_launcher","derringer","grenade","grenade_essence","fire_grenade","frost_grenade","shock_grenade",
    "mana","stable","reverse_stable","spell_LIGHT_BULLET","spell_BOMB"}) do
    assert(byId[id] and byId[id].durationFrames<=10*60,id.." must complete a batch within 10 seconds")
end

local s=assert(NHStore.load())
local function persist()
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
end
local function advance(id,frames)
    return NHStore.advanceProduction(s,{run=1,orderId=id,progress=frames})
end
local mana="magic_liquid_mana_regeneration"
assert(s.order.recipe=="mana" and s.order.progress==120 and s.order.required==120*60)
assert(s.order.catalysts[mana]==1 and s.order.output.materials[mana]==251)
assert(s.materials.water==100 and not s.materials[mana])
local changed,done=advance(1,120*60-1)
assert(changed and not done)
persist()
assert(s.order.progress==120*60-1 and not s.materials[mana])
changed,done=advance(1,120*60)
assert(changed and done)
persist()
assert(not advance(1,120*60) and s.finished==1 and s.materials.water==100 and s.materials[mana]==251)

-- Use the 100 water left by the old order to buy the smaller current batch.
assert(NHStore.startOrder(s,"mana"))
persist()
assert(s.order.id==2 and s.order.required==8*60 and s.order.catalysts[mana]==1)
assert(not s.materials.water and s.materials[mana]==250 and s.order.output.materials[mana]==101)
changed,done=advance(2,8*60-1)
assert(changed and not done and s.materials[mana]==250)
changed,done=advance(2,8*60)
assert(changed and done)
persist()
assert(not advance(2,8*60) and not s.order and s.finished==2 and s.materials[mana]==351)
print(("Workshop balance: %d recipes and both prepaid and newly quoted catalyst deliveries passed."):format(#NHStore.recipes))
