local root="mods/noita_hideout/files/"
local settings,flags={},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile(root.."store.lua")
local state=assert(NHStore.load())
NHStore.newRun(state)
local use=dofile(root.."inventory_use.lua")
for i,id in ipairs(NHTarot.order) do
    local card=NHCompanions.withCount({species=id,remaining=40},2)
    assert(NHCompanions.validCard(card) and NHCompanions.canStack(card,card))
    assert(not NHCompanions.validCard({species=id,remaining=41}))
    assert(not NHCompanions.validCard({species=id,remaining=39,count=2}))
    state.warehouse={{id=state.nextItemId,slot=1,item=card}}
    state.nextItemId=state.nextItemId+1
    local ref={container="warehouse",slot=1,storedId=state.warehouse[1].id,kind="summon_card",species=id,remaining=40,count=2}
    assert(use.spend(state,1,ref))
    assert(state.warehouse[1].item.count==1 and state.warehouse[1].item.remaining==40)
    assert(state.warehouse[2].item.remaining==39 and state.warehouse[2].item.count==1)
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    assert(state.warehouse[2].item.species==id)
    local wallet=NHCardWallets.empty()
    wallet.cells[1]=card
    assert(NHCardWallets.valid(wallet))
end

local entities,nextId,frame={},1,100
local function spawn(path)
    nextId=nextId+1
    entities[nextId]={path=path,parts={},tags={},parent=0}
    return nextId
end
entities[1]={parts={},tags={},parent=0}
function EntityGetComponentIncludingDisabled(id,kind,tag)
    local out={}
    for _,c in ipairs(entities[id].parts) do
        if c.kind==kind and (not tag or c._tags==tag) then out[#out+1]=c end
    end
    return out
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return EntityGetComponentIncludingDisabled(id,kind,tag)[1] end
function EntityAddComponent2(id,kind,c) c.kind=kind; table.insert(entities[id].parts,c); return c end
function EntityRemoveComponent(id,c)
    for i,v in ipairs(entities[id].parts) do if v==c then table.remove(entities[id].parts,i); return end end
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function ComponentObjectGetValue2(c,object,k) return c[object][k] end
function ComponentObjectSetValue2(c,object,k,v) c[object][k]=v end
function EntityGetTransform() return 10,20 end
function GameGetFrameNum() return frame end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetParent(id) return entities[id].parent end
function EntityGetRootEntity() return 1 end
function EntityGetName() return "inventory_quick" end
function EntityAddChild(parent,id) entities[id].parent=parent end
function EntityRemoveFromParent(id) entities[id].parent=0 end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityHasTag(id,tag) return entities[id].tags[tag] end
function EntityGetAllChildren(parent,tag)
    local out={}
    for id,e in pairs(entities) do if e.parent==parent and (not tag or e.tags[tag]) then out[#out+1]=id end end
    return out
end
function EntityKill(id) entities[id]=nil end
function GameGetGameEffectCount(player,effect)
    local n=0
    for _,id in ipairs(EntityGetAllChildren(player)) do
        local c=EntityGetFirstComponentIncludingDisabled(id,"GameEffectComponent")
        if c and c.effect==effect then n=n+1 end
    end
    return n
end
local failedPath
function EntityLoad(path)
    if path==failedPath then return 0 end
    local id=spawn(path)
    local effect=({[root.."tarot_life.xml"]="RESPAWN",
        ["data/entities/misc/effect_invisibility.xml"]="INVISIBILITY",
        ["data/entities/misc/effect_stains_drop_faster.xml"]="STAINS_DROP_FASTER"})[path]
    if effect then EntityAddComponent2(id,"GameEffectComponent",{effect=effect,frames=600}) end
    return id
end
local dm=EntityAddComponent2(1,"DamageModelComponent",{hp=2,max_hp=4,max_hp_cap=0,damage_multipliers={projectile=0.5,explosion=0.35}})
local native=EntityLoad("data/entities/misc/effect_invisibility.xml")
EntityAddChild(1,native)
local nativeHook=EntityAddComponent2(1,"LuaComponent",{script_damage_received="native_revenge"})
local R=dofile(root.."tarot_runtime.lua")
local paid=0
local function pay() paid=paid+1; return true end
for _,id in ipairs(NHTarot.order) do
    assert(not R.apply(1,id,function() return false end))
    assert(#EntityGetAllChildren(1)==1 and #entities[1].parts==2 and paid==0)
end
failedPath="data/entities/misc/perks/contact_damage.xml"
assert(not R.apply(1,"tarot_chariot",pay) and paid==0 and #EntityGetAllChildren(1)==1)
failedPath=nil
assert(R.apply(1,"tarot_garden",pay) and dm.hp==4 and dm.max_hp==6)
local lives=0
for _,id in ipairs(EntityGetAllChildren(1)) do
    local c=EntityGetFirstComponentIncludingDisabled(id,"GameEffectComponent")
    if c and c.effect=="RESPAWN" then assert(c.frames==-1); lives=lives+1 end
end
assert(lives==1)
local sprite=EntityAddComponent2(1,"SpriteComponent",{alpha=0.3})
assert(R.apply(1,"tarot_hermit",pay))
local c=EntityGetFirstComponentIncludingDisabled(1,"VariableStorageComponent","nh_tarot_hermit")
frame=frame+100
R.tick(1)
assert(c.value_int==NHTarot.duration-100)
assert(R.apply(1,"tarot_hermit",pay) and c.value_int==NHTarot.duration)
assert(#EntityGetAllChildren(1,"nh_tarot_hermit")==2)
assert(R.apply(1,"tarot_chariot",pay) and math.abs(dm.damage_multipliers.projectile-0.4)<0.00001)
assert(R.apply(1,"tarot_chariot",pay) and math.abs(dm.damage_multipliers.projectile-0.4)<0.00001)
assert(#EntityGetComponentIncludingDisabled(1,"LuaComponent","nh_tarot_revenge")==1)
-- A later permanent resistance upgrade must survive tarot expiry.
dm.damage_multipliers.projectile=dm.damage_multipliers.projectile*0.5
frame=frame+NHTarot.duration
dofile(root.."tarot_runtime.lua").tick(1)
assert(not EntityGetFirstComponentIncludingDisabled(1,"VariableStorageComponent","nh_tarot_hermit"))
assert(#EntityGetAllChildren(1,"nh_tarot_hermit")==0 and #EntityGetAllChildren(1,"nh_tarot_chariot")==0)
assert(entities[native] and nativeHook.script_damage_received=="native_revenge" and sprite.alpha==0.3)
EntityKill(native)
assert(R.apply(1,"tarot_hermit",pay))
frame=frame+NHTarot.duration
R.tick(1)
assert(sprite.alpha==1)
assert(#EntityGetComponentIncludingDisabled(1,"LuaComponent","nh_tarot_revenge")==0)
assert(math.abs(dm.damage_multipliers.projectile-0.25)<0.00001)
assert(R.apply(1,"tarot_tower",pay))
assert(entities[nextId].path=="data/entities/items/pickup/beamstone.xml" and entities[nextId].parent==0)
local shieldKind=NHShields.order[1]
local s={revision=7,gearShield={item={kind=shieldKind,charge=0,repair=2,delay=180}},
    gearRig={item={kind="ammo_rig",reserve=0}}}
assert(NHTarot.refillDraft(s))
assert(s.gearShield.item.charge==NHShields.types[shieldKind].cells*NHShields.cell and s.gearShield.epoch==8)
assert(s.gearShield.item.repair==0 and s.gearShield.item.delay==0 and s.gearRig.item.reserve==240)
local gun=spawn("gun")
local mag=EntityAddComponent2(gun,"VariableStorageComponent",{_tags="nh_magazine",name="marksman_rifle",value_int=1})
local ability=EntityAddComponent2(gun,"AbilityComponent",{mana=1})
function GameGetAllInventoryItems() return {gun} end
NHTarot.refillGuns(1)
assert(mag.value_int==60 and ability.mana==60)
print("Tarot cards: 40-use stacks, split use, persistence, rollback, permanent and timed effects, refill passed.")

-- Upgrade old garden effects in place; never refund consumed lives.
do
    function EntityGetFilename(id) return entities[id].path or "" end
    local old=EntityLoad(root.."tarot_life.xml")
    EntityAddChild(1,old)
    local effect=EntityGetFirstComponentIncludingDisabled(old,"GameEffectComponent")
    effect.frames,effect.mIsSpent=-1,false
    local hp=dm.max_hp
    R.refreshLifeIcons(1)
    local icon=assert(EntityGetFirstComponentIncludingDisabled(old,"UIIconComponent"))
    assert(icon.name=="$perk_respawn" and icon.is_perk and icon.display_in_hud)
    assert(icon.icon_sprite_file=="data/ui_gfx/perk_icons/respawn.png" and effect.frames==-1)
    R.refreshLifeIcons(1)
    assert(#EntityGetComponentIncludingDisabled(old,"UIIconComponent")==1 and dm.max_hp==hp)
    effect.mIsSpent=true
    R.refreshLifeIcons(1)
    assert(icon.icon_sprite_file=="data/ui_gfx/perk_icons/respawn_spent.png" and effect.mIsSpent)
    local vanilla=EntityLoad("data/entities/misc/effect_respawn.xml")
    EntityAddChild(1,vanilla)
    R.refreshLifeIcons(1)
    assert(not EntityGetFirstComponentIncludingDisabled(vanilla,"UIIconComponent"))
end
print("Garden life icons: new and legacy effects display once; spent lives stay spent; native perks untouched.")
