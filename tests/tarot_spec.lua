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
function RaytracePlatforms() return false end
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
    if path:find(root.."items/",1,true)==1 then EntityAddComponent2(id,"ItemComponent",{uses_remaining=4}) end
    local effect=({[root.."tarot_life.xml"]="RESPAWN",
        ["data/entities/misc/effect_edit_wands_everywhere.xml"]="EDIT_WANDS_EVERYWHERE",
        ["data/entities/misc/effect_protection_fire.xml"]="PROTECTION_FIRE",
        ["data/entities/misc/effect_saving_grace.xml"]="SAVING_GRACE",
        ["data/entities/misc/effect_remove_fog_of_war.xml"]="REMOVE_FOG_OF_WAR",
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
-- A refresh only consumes a charge if the entire physical reward can be delivered.
assert(R.apply(1,"tarot_magician",pay))
local mageTimer=assert(EntityGetFirstComponentIncludingDisabled(1,"VariableStorageComponent","nh_tarot_magician"))
frame=frame+64
R.tick(1)
local mageLeft=mageTimer.value_int
frame=0 -- a loaded world's frame counter can rewind
dofile(root.."tarot_runtime.lua").tick(1)
assert(mageTimer.value_int==mageLeft)
local function countDrops()
    local count=0
    for _,e in pairs(entities) do
        if e.path and e.path:find(root.."items/",1,true)==1 then count=count+1 end
    end
    return count
end
local batchSize=10
assert(countDrops()==batchSize)
failedPath=root.."items/shock_tube.xml"
local before=paid
assert(not R.apply(1,"tarot_magician",pay) and paid==before)
assert(countDrops()==batchSize and mageTimer.value_int==mageLeft)
failedPath=nil
assert(not R.apply(1,"tarot_magician",function() return false end) and countDrops()==batchSize)
assert(R.apply(1,"tarot_magician",pay) and countDrops()==batchSize*2 and mageTimer.value_int==NHTarot.duration)
frame=frame+NHTarot.duration
R.tick(1)
assert(countDrops()==batchSize*2 and not EntityGetFirstComponentIncludingDisabled(1,"LuaComponent","nh_tarot_tick"))
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

do
    local globals,writes={},{}
    function GlobalsGetValue(k,default) return globals[k] or default end
    function GlobalsSetValue(k,value) globals[k]=value end
    function GameSetPostFxParameter(k,x,y,z,w)
        assert(k=="nh_tarot_sight" and y==0 and z==0 and w==0)
        writes[#writes+1]=x
    end
    function ComponentGetIsEnabled(c) return c.enabled~=false end
    function ComponentGetTypeName(c) return c.kind end
    function ComponentGetTags(c) return c._tags or "" end
    function ComponentHasTag(c,tag) return c._tags==tag end
    function ComponentAddTag(c,tag) c._tags=tag end
    function ComponentRemoveTag(c,tag) if c._tags==tag then c._tags=nil end end
    function EntityGetAllComponents(e) return entities[e].parts end
    function EntityGetTags(e)
        local tags={}
        for tag in pairs(entities[e].tags) do tags[#tags+1]=tag end
        return table.concat(tags,",")
    end
    local sight=dofile(root.."tarot_sight.lua")
    local function blind(path,frames)
        local e=spawn(path)
        EntityAddChild(1,e)
        EntityAddComponent2(e,"GameEffectComponent",{effect="BLINDNESS",frames=frames or 100})
        return e
    end
    local source="data/entities/misc/effect_blindness.xml"
    local pure=blind(source)
    local mixed=blind(source)
    EntityAddComponent2(mixed,"GameEffectComponent",{effect="CONFUSION",frames=211})
    local scripted=blind(source)
    EntityAddComponent2(scripted,"LuaComponent",{script_source_file="foreign_cleanup.lua"})
    local perk=blind(source);EntityAddTag(perk,"perk_entity")
    local tagged=blind(source);ComponentAddTag(entities[tagged].parts[1],"perk")
    local permanent=blind(source,-1)
    local streamed=blind("")
    EntityAddComponent2(streamed,"UIIconComponent",{name="$status_blindness",icon_sprite_file="data/ui_gfx/status_indicators/blindness.png"})
    local platform=EntityAddComponent2(1,"CharacterPlatformingComponent",{pixel_gravity=100})

    assert(not sight.sync(1) and #writes==0)
    assert(not R.apply(1,"tarot_sun",function()
        assert(not dofile(root.."tarot_sight.lua").active(1))
        return false
    end))
    assert(entities[pure] and #writes==0)
    assert(R.apply(1,"tarot_sun",pay) and sight.active(1) and writes[1]==1)
    assert(not entities[pure] and not entities[streamed])
    assert(entities[mixed] and entities[scripted] and entities[perk] and entities[tagged] and entities[permanent])
    assert(entities[mixed].parts[2].frames==211)
    local later=blind("data/entities/misc/effect_blindness_custom_short.xml",200)
    frame=frame+15;R.tick(1)
    assert(not entities[later] and #writes==1)
    assert(R.apply(1,"tarot_moon",pay) and R.apply(1,"tarot_moon",pay))
    assert(platform.pixel_gravity==60 and #writes==1)
    -- Independent script states and a rewound frame counter see the saved clocks.
    frame=0;R=dofile(root.."tarot_runtime.lua");R.tick(1)
    local restored=dofile(root.."tarot_sight.lua")
    assert(restored.active(1) and #writes==1)
    R.expire(1,"tarot_sun")
    assert(restored.active(1) and #writes==1)
    for _,tag in ipairs({"ew_client","ew_notplayer","nh_ew_waiting","polymorphed_player"}) do
        entities[1].tags[tag]=true
        assert(not restored.active(1) and not restored.sync(1) and not R.apply(1,"tarot_sun",pay))
        entities[1].tags[tag]=nil
    end
    restored.reset()
    assert(#writes==2 and writes[2]==0)
    sight.sync(1)
    assert(#writes==3 and writes[3]==1)
    local hook=assert(EntityGetFirstComponentIncludingDisabled(1,"LuaComponent","nh_tarot_tick"))
    assert(hook.execute_every_n_frame==15)
    frame=frame+NHTarot.duration-16
    R.tick(1)
    assert(hook.execute_every_n_frame==15)
    frame=frame+1
    hook.mNextExecutionTime=frame+40 -- restored coarse scheduler
    sight.sync(1)
    assert(hook.execute_every_n_frame==1 and hook.mNextExecutionTime==frame+1)
    for ahead=1,14 do
        frame=frame+1
        R.tick(1)
        assert(hook.execute_every_n_frame==1 and #writes==3 and restored.active(1))
    end
    frame=frame+1
    assert(not restored.active(1))
    R.tick(1)
    assert(#writes==4 and writes[4]==0 and platform.pixel_gravity==100)
    local after=blind(source)
    assert(not restored.sync(1) and entities[after] and #writes==4)
    restored.reset(true)
    assert(#writes==5 and writes[5]==0)
end
print("Sun and Moon sight: payment, overlap, expiry, native bodies, reload and dedicated blindness carriers passed.")
