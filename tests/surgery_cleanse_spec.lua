local M=dofile("mods/noita_hideout/files/surgery_cleanse.lua")
local function entity(path,tags)
    return {path=path or "",tags=tags or "",components={},children={}}
end
local function component(owner,kind,fields)
    fields=fields or {}
    fields.kind=kind
    owner.components[#owner.components+1]=fields
    return fields
end
local player=entity("data/entities/player.xml")
local function attach(path,tags)
    local child=entity(path,tags)
    player.children[#player.children+1]=child
    return child
end
local function native(name) return attach("data/entities/misc/"..name..".xml") end
local function effect(owner,id,frames,tags)
    return component(owner,"GameEffectComponent",{effect=id,frames=frames,tags=tags})
end
function EntityGetComponentIncludingDisabled(e,kind)
    local found={}
    for _,c in ipairs(e.components) do if not c.removed and c.kind==kind then found[#found+1]=c end end
    return found
end
function EntityGetFirstComponentIncludingDisabled(e,kind) return EntityGetComponentIncludingDisabled(e,kind)[1] end
function EntityGetAllComponents(e) return e.components end
function EntityGetAllChildren(e)
    local found={}
    for _,child in ipairs(e.children) do if not child.dead then found[#found+1]=child end end
    return found
end
function EntityGetTags(e) return e.tags end
function EntityHasTag(e,tag) return (","..e.tags..","):find(","..tag..",",1,true)~=nil end
function EntityGetFilename(e) return e.path end
function ComponentGetTags(c) return c.tags end
function ComponentGetIsEnabled(c) return not c.disabled end
function ComponentGetTypeName(c) return c.kind end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function EntityKill(e) assert(e~=player); e.dead=true end
function EntityRemoveComponent(e,c)
    for i,owned in ipairs(e.components) do
        if c==owned then table.remove(e.components,i); c.removed=true; return end
    end
    error("wrong component owner")
end
local slimeSafe=false
function GameGetGameEffectCount(e,id) assert(e==player and id=="NO_SLIME_SLOWDOWN"); return slimeSafe and 1 or 0 end

-- Native arrays start with NONE. Repeated Lua definitions for intensity
-- thresholds refer to a single status ID and occupy a single native slot.
local ids={"WET","BERSERK","INGESTION_DRUNK","TRIP","NIGHTVISION","FOOD_POISONING","POISONED","PROTECTION_POLYMORPH","SLIMY","OILED","HYDRATED"}
local raw={WET=2,BERSERK=3,INGESTION_DRUNK=4,TRIP=5,NIGHTVISION=6,FOOD_POISONING=7,POISONED=8,PROTECTION_POLYMORPH=9,SLIMY=10,OILED=11,HYDRATED=12}
function dofile_once(path)
    assert(path=="data/scripts/status_effects/status_list.lua")
    status_effects={}
    for _,id in ipairs(ids) do
        local levels=(id=="INGESTION_DRUNK" or id=="TRIP") and 4 or 1
        for _=1,levels do status_effects[#status_effects+1]={id=id} end
    end
end
local stats=component(player,"StatusEffectDataComponent",{stain_effects={},ingestion_effects={}})
local removed={}
function EntityRemoveStainStatusEffect(e,id,delay)
    assert(e==player and delay==0 and stats.stain_effects[raw[id]]>0)
    stats.stain_effects[raw[id]]=0
    removed[#removed+1]="stain:"..id
end
function EntityRemoveIngestionStatusEffect(e,id)
    assert(e==player and stats.ingestion_effects[raw[id]]>0)
    stats.ingestion_effects[raw[id]]=0
    removed[#removed+1]="drink:"..id
end
local damage=component(player,"DamageModelComponent",{mIsOnFire=false,mFireFramesLeft=0,hp=1,max_hp=3})
local function coating(id) stats.stain_effects[raw[id]]=0.8 end
local function consumed(id) stats.ingestion_effects[raw[id]]=0.5 end
coating("WET"); coating("BERSERK"); coating("OILED"); consumed("HYDRATED"); consumed("PROTECTION_POLYMORPH"); consumed("NIGHTVISION"); consumed("TRIP")
assert(not M.has(player) and not M.cleanse(player) and #removed==0)
coating("POISONED"); consumed("FOOD_POISONING"); consumed("INGESTION_DRUNK")
assert(M.has(player) and #removed==0 and stats.ingestion_effects[raw.FOOD_POISONING]==0.5)
assert(M.cleanse(player) and not M.has(player) and #removed==3)
assert(stats.stain_effects[raw.WET]==0.8 and stats.stain_effects[raw.BERSERK]==0.8 and stats.stain_effects[raw.OILED]==0.8)
assert(stats.ingestion_effects[raw.TRIP]==0.5 and stats.ingestion_effects[raw.NIGHTVISION]==0.5
    and stats.ingestion_effects[raw.PROTECTION_POLYMORPH]==0.5 and stats.ingestion_effects[raw.HYDRATED]==0.5)

local perk=attach("data/entities/misc/effect_worm_attractor.xml","perk_entity")
local perkEffect=effect(perk,"WORM_ATTRACTOR",-1)
local ordinaryPermanent=effect(player,"WORM_ATTRACTOR",-1)
local modPerk=effect(player,"WORM_ATTRACTOR",400,"noita_hideout_perk_effect")
local equipment=attach(); component(equipment,"ItemComponent"); local itemEffect=effect(equipment,"CONFUSION",100)
local pet=attach(); component(pet,"DamageModelComponent"); local petEffect=effect(pet,"POISON",220)
local injector=attach("mods/noita_hideout/files/stimulant.xml","noita_hideout_stimulant")
local injectorEffect=effect(injector,"PROTECTION_FIRE",1877)
local food=attach("mods/noita_hideout/files/effect_food_mana.xml","noita_hideout_effect_food_mana")
local foodEffect=effect(food,"MANA_REGENERATION",2355)
local taggedFood=attach("","noita_hideout_effect_future_food"); local futureBuff=effect(taggedFood,"DRUNK",322)
local biome=attach("data/entities/misc/effect_no_heal_in_meat_biome.xml","no_heal_in_meat_biome")
local biomeRule=effect(biome,"NO_HEAL",-1)
local poly=effect(player,"POLYMORPH",480)
local greed=attach("data/entities/misc/greed_curse/greed_effect.xml")
component(greed,"LuaComponent",{script_source_file="data/scripts/magic/greed_curse/spawn_meteors.lua"})
assert(not M.has(player))
local burning=effect(player,"ON_FIRE",26)
damage.mIsOnFire,damage.mFireFramesLeft=true,130
local blind=native("effect_blindness"); effect(blind,"BLINDNESS",10)
local intoxicated=native("effect_drunk_01"); effect(intoxicated,"DRUNK",120); effect(intoxicated,"FOOD_POISONING",120)
local trip=native("effect_trip_03")
local psychedelic=effect(trip,"CUSTOM",600); psychedelic.custom_effect_id="TRIP_00"
local poison=effect(trip,"FOOD_POISONING",150)
local mixed=native("effect_poison"); local mixedPoison=effect(mixed,"POISON",80)
local positiveScript=component(mixed,"LuaComponent",{script_source_file="mods/example/food_healing.lua",clock=42})
local mixed2=native("effect_confusion"); local confused=effect(mixed2,"CONFUSION",130)
local resist=component(mixed2,"ShotEffectComponent",{extra_modifier="mana_reduce"})
local rootImmune=effect(player,"PROTECTION_FREEZE",230)
local curseCloud=native("effect_curse_cloud_02")
local cloud=effect(curseCloud,"CUSTOM",-1); cloud.custom_effect_id="CURSE_CLOUD_02"
component(curseCloud,"LuaComponent",{script_source_file="data/scripts/status_effects/effect_curse_cloud.lua"})
local scripted={}
for name,script in pairs({effect_hearty="hearty_end",effect_wither="wither_end",effect_twitchy="twitchy",effect_weaken="weaken_end"}) do
    local child=native(name); component(child,"LifetimeComponent",{lifetime=1200})
    component(child,"LuaComponent",{script_source_file="data/scripts/status_effects/"..script..".lua"})
    scripted[#scripted+1]=child
end
local neutral=native("neutralized"); component(neutral,"LuaComponent",{script_shot="data/scripts/projectiles/neutralized.lua"})
local gravity=native("gravity_field_enemy_short"); component(gravity,"ProjectileComponent"); component(gravity,"VelocityComponent")
component(gravity,"LuaComponent",{script_source_file="data/scripts/projectiles/projectile_gravity_small.lua"})
local homing=native("effect_homing_shooter"); component(homing,"ShotEffectComponent",{extra_modifier="projectile_homing_shooter_wizard"})
local foreign=attach("mods/example/health_extension.xml"); local frozen=effect(foreign,"FROZEN",90)
local streamed=attach(""); component(streamed,"UIIconComponent",{name="$status_hearty"})
component(streamed,"LuaComponent",{script_source_file="data/scripts/status_effects/hearty_end.lua"})
local streamedHoming=attach("data/entities/unknown.xml"); component(streamedHoming,"UIIconComponent",{name="$status_homing_shooter"})
component(streamedHoming,"ShotEffectComponent",{extra_modifier="projectile_homing_shooter_wizard"})
local lookalike=attach(""); component(lookalike,"UIIconComponent",{name="$status_hearty"})
local unrelatedScript=component(lookalike,"LuaComponent",{script_source_file="mods/example/health.lua"})
assert(M.has(player) and not blind.dead and not poison.removed and damage.mIsOnFire and not homing.dead)
assert(M.cleanse(player) and not M.has(player))
assert(not damage.mIsOnFire and damage.mFireFramesLeft==0 and damage.hp==1 and damage.max_hp==3)
assert(burning.removed and blind.dead and intoxicated.dead and curseCloud.dead and neutral.dead and gravity.dead and homing.dead)
assert(streamed.dead and streamedHoming.dead and not lookalike.dead and not unrelatedScript.removed)
for _,child in ipairs(scripted) do assert(child.dead) end
assert(not trip.dead and poison.removed and not psychedelic.removed and psychedelic.frames==600)
assert(not mixed.dead and mixedPoison.removed and not positiveScript.removed and positiveScript.clock==42)
assert(not mixed2.dead and confused.removed and not resist.removed and not foreign.dead and frozen.removed)
for _,c in ipairs({ordinaryPermanent,modPerk,perkEffect,itemEffect,petEffect,rootImmune,injectorEffect,foodEffect,futureBuff,biomeRule,poly}) do
    assert(not c.removed and not c.disabled)
end
assert(not greed.dead and not equipment.dead and not pet.dead and not food.dead and not injector.dead and not perk.dead)
assert(injectorEffect.frames==1877 and foodEffect.frames==2355 and not M.cleanse(player))

slimeSafe=true
coating("SLIMY")
local slime=native("effect_slimy"); local slimed=effect(slime,"SLIMY",200)
assert(not M.has(player) and not M.cleanse(player) and stats.stain_effects[raw.SLIMY]==0.8 and not slimed.removed and not slime.dead)
slimeSafe=false
assert(M.has(player) and M.cleanse(player) and slime.dead and stats.stain_effects[raw.SLIMY]==0)
print("Surgical cleanse: both status vectors, fire, timed curses, mixed carriers and positive effect ownership passed.")
