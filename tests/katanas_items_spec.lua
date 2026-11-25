-- Exercise the real workshop and transfer journal, including failed delivery,
-- native weapon-lane selection, and immutable storage records for both blades.
local settings,flags,globals={},{},{}
local failSave,failAction,failLoad=false,false,false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) if failSave then error("injected write failure") end; settings[k]=v end
function HasFlagPersistent(k) return flags[k]==true end
function AddFlagPersistent(k) flags[k]=true end
function GlobalsGetValue(k,default) return globals[k] or default end
function GlobalsSetValue(k,v) globals[k]=v end
function GameGetFrameNum() return 100 end
function DoesWorldExistAt() return true end

local entities={
    [1]={alive=true,name="player",tags={player_unit=true},comps={Inventory2Component={mActiveItem=0}},x=20,y=30},
    [2]={alive=true,name="inventory_quick",parent=1,tags={},comps={},x=20,y=30},
}
local nextId=10
local function make(tags,comps,x,y)
    nextId=nextId+1
    entities[nextId]={alive=true,tags=tags or {},comps=comps or {},x=x or 20,y=y or 26}
    return nextId
end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive or false end
function EntityGetParent(id) return entities[id] and entities[id].parent or 0 end
function EntityGetRootEntity(id)
    local parent=EntityGetParent(id)
    return parent~=0 and EntityGetRootEntity(parent) or id
end
function EntityGetName(id) return entities[id] and entities[id].name or "" end
function EntityGetTransform(id) local e=entities[id]; return e.x,e.y end
function EntityGetAllChildren(id)
    local result={}
    for child,e in pairs(entities) do if e.alive and e.parent==id then result[#result+1]=child end end
    return result
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    local e=entities[id]
    return e and e.comps[kind..(tag or "")]
end
EntityGetFirstComponent=EntityGetFirstComponentIncludingDisabled
function EntityAddComponent2(id,kind,fields)
    entities[id].comps[kind..(fields._tags or "")]=fields
    return fields
end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,a,b) c[k]=b~=nil and {a,b} or a end
function ComponentObjectSetValue2(c,object,key,value)
    c[object]=c[object] or {};c[object][key]=value
end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityHasTag(id,tag) return entities[id] and entities[id].tags[tag] or false end
function EntityGetWithTag(tag)
    local result={}
    for id,e in pairs(entities) do if e.alive and e.tags[tag] then result[#result+1]=id end end
    return result
end
function EntitySetComponentsWithTagEnabled() end
function EntityAddChild(parent,child) entities[child].parent=parent end
function EntityRemoveFromParent(id) entities[id].parent=nil end
function EntityKill(id)
    for _,child in ipairs(EntityGetAllChildren(id)) do EntityKill(child) end
    entities[id].alive=false
end
function GameKillInventoryItem(player,id)
    assert(player==1 and EntityGetRootEntity(id)==player)
    EntityKill(id)
    if entities[1].comps.Inventory2Component.mActiveItem==id then entities[1].comps.Inventory2Component.mActiveItem=0 end
end
function GameGetAllInventoryItems() return EntityGetAllChildren(2) end
function GamePickUpInventoryItem(player,id)
    assert(player==1)
    EntityAddChild(2,id)
    entities[1].comps.Inventory2Component.mActiveItem=id
end
function CreateItemActionEntity(action,x,y)
    if failAction then return 0 end
    return make({}, {ItemActionComponent={action_id=action},ItemComponent={}},x,y)
end
function EntityLoad(path,x,y)
    if failLoad then return 0 end
    local kind=assert(path:match("/items/([%w_]+)%.xml$"))
    return make({wand=true,nh_katana=true,noita_hideout_katana=true,["noita_hideout_"..kind]=true},
        {ItemComponent={uses_remaining=kind=="dragon_king" and 90 or -2,is_pickable=true,auto_pickup=false,next_frame_pickable=0,item_pickup_radius=32},
            AbilityComponent={use_gun_script=true}},x,y)
end

dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/transfers.lua")
NHProducts={icons={}}
NHWand={capture=function() error("Katana routed to ordinary wand codec") end}
NHPotion={isFlask=function() return false end}
local adapters={}
local register=NHTransfers.registerItem
NHTransfers.registerItem=function(kind,match,adapter)
    adapters[kind]=adapter
    return register(kind,match,adapter)
end
NHRedRelics.register()
assert(not adapters.dragon_king,"Generic red relic codec claimed the katana")
NHKatanas.registerItems()
NHInventoryUse=dofile("mods/noita_hideout/files/inventory_use.lua")
dofile("mods/noita_hideout/files/native_items.lua")
local pickup=dofile("mods/noita_hideout/files/pickup.lua")
local s=assert(NHStore.load())
NHStore.newRun(s)
s.resources.arcane_scrap=36
for _,kind in ipairs(NHKatanas.order) do
    assert(NHStore.category(kind)==(NHKatanas.types[kind].warehouseCategory or "wand") and NHFirearms.lane(kind)=="wand")
    assert(not NHInventoryUse.supports(kind) and not NHNative.usableKind(kind))
    if NHKatanas.types[kind].scrap then
        local index=#s.warehouse+1
        assert(NHStore.craft(s,kind))
        local row=s.warehouse[index]
        assert(row.item.kind==kind and row.slot==index and NHKatanas.valid(row.item))
        assert(NHStore.stackUnits(row.item)==nil and not NHStore.stackSlot(s,"warehouse",row.item))
    else
        assert(not NHKatanas.recipe(kind) and not NHStore.craft(s,kind))
    end
end
assert(s.resources.arcane_scrap==nil and #s.warehouse==2)
assert(NHStore.commit(s))
s=assert(NHStore.load())
local original=s.warehouse[1].id

-- Failed creation or failed profile commit retains the one warehouse item.
for _,failure in ipairs({"action","load","save"}) do
    failAction,failLoad,failSave=failure=="action",failure=="load",failure=="save"
    assert(not NHTransfers.withdraw(s,1,1,"warehouse"))
    assert(#s.warehouse==2 and s.warehouse[1].id==original)
    assert(#EntityGetWithTag("noita_hideout_hf_blade")==0)
    failAction,failLoad,failSave=false,false,false
end

local issued
assert(NHTransfers.withdraw(s,1,1,"warehouse",function(id) issued=id; GamePickUpInventoryItem(1,id); return true end))
assert(#s.warehouse==1 and NHTransfers.item_kind(issued)=="hf_blade")
assert(NHFirearms.nativeLane("hf_blade",issued)=="wand")
local children=EntityGetAllChildren(issued)
assert(#children==1)
local action=entities[children[1]].comps
assert(action.ItemActionComponent.action_id=="NH_HF_BLADE" and action.ItemComponent.permanently_attached and action.ItemComponent.is_frozen)
assert(NHKatanas.ensureBuiltInAction(issued) and #EntityGetAllChildren(issued)==1)
-- A pre-fix saved blade can be mid-reload. Repair it in place even when its
-- frozen permanent action is already present; preserve the original slot and
-- resource value instead of replacing/re-picking the weapon.
local legacyAbility=entities[issued].comps.AbilityComponent
local legacyItem=entities[issued].comps.ItemComponent
legacyItem.inventory_slot={2,0}
legacyAbility.click_to_use,legacyAbility.reload_time_frames=true,40
legacyAbility.mReloadFramesLeft,legacyAbility.mReloadNextFrameUsable=40,140
legacyAbility.mNextFrameUsable=102 -- A support menu may still own this guard.
legacyAbility.gun_config={reload_time=40,deck_capacity=0}
local oldRemaining=legacyItem.uses_remaining
assert(NHKatanas.ensureBuiltInAction(issued))
assert(EntityGetParent(issued)==2 and entities[1].comps.Inventory2Component.mActiveItem==issued)
assert(legacyItem.inventory_slot[1]==2 and legacyItem.inventory_slot[2]==0 and legacyItem.uses_remaining==oldRemaining)
assert(legacyAbility.use_gun_script and legacyAbility.click_to_use==false and legacyAbility.gun_config.reload_time==0)
assert(legacyAbility.reload_time_frames==0 and legacyAbility.mReloadFramesLeft==0 and legacyAbility.mReloadNextFrameUsable==0)
assert(legacyAbility.mNextFrameUsable==102 and #EntityGetAllChildren(issued)==1)
local wandAbility={use_gun_script=true,click_to_use=true,gun_config={reload_time=40},mReloadFramesLeft=30}
local wand=make({wand=true},{ItemComponent={},AbilityComponent=wandAbility})
assert(not NHKatanas.repairNative(wand) and not NHKatanas.repairNative(wand,"hf_blade"))
assert(wandAbility.click_to_use and wandAbility.gun_config.reload_time==40 and wandAbility.mReloadFramesLeft==30)
EntityKill(wand)
-- A legacy/modded blade can still contain a foreign action despite the new
-- zero-slot definition. Refused storage must preserve both blade and card.
local foreign=CreateItemActionEntity("LIGHT_BULLET",20,30)
EntityAddChild(issued,foreign)
local revision=s.revision
assert(not NHTransfers.deposit(s,1,"safe",issued))
assert(EntityGetIsAlive(issued) and EntityGetIsAlive(foreign) and EntityGetParent(foreign)==issued)
assert(s.revision==revision and #s.safe==0 and #s.warehouse==1)
EntityRemoveFromParent(foreign)
assert(adapters.hf_blade.capture(issued))
assert(NHTransfers.deposit(s,1,"safe",issued))
assert(not EntityGetIsAlive(issued) and #s.safe==1 and s.safe[1].item.kind=="hf_blade")
s=assert(NHStore.load())
assert(NHKatanas.valid(s.safe[1].item) and s.safe[1].item.remaining==nil and s.safe[1].item.rounds==nil)
assert(NHTransfers.withdraw(s,1,1,"safe",function(id) issued=id; GamePickUpInventoryItem(1,id); return true end))
assert(#s.safe==0 and NHTransfers.item_kind(issued)=="hf_blade")
assert(NHTransfers.deposit(s,1,"warehouse",issued))
assert(#s.warehouse==2 and not EntityGetIsAlive(issued))

-- Ground pickup must recognize a free weapon slot. A free tool slot cannot
-- hold a katana; the normal full-inventory fallback stores it in the safe.
local ground=EntityLoad(NHKatanas.types.hf_murasama.file,20,30)
function EntityGetInRadius() return {ground} end
assert(pickup.interact(s,1,false,function() return {{lane="wand"}} end)==nil)
assert(EntityGetIsAlive(ground) and #s.safe==0)
local claimed,_,stored=pickup.interact(s,1,false,function() return {{lane="wand",entity=999},{lane="tool"}} end)
assert(claimed and stored and not EntityGetIsAlive(ground) and s.safe[1].item.kind=="hf_murasama")

for _,kind in ipairs(NHKatanas.order) do
    local xml=assert(io.open(NHKatanas.types[kind].file,"rb"))
    local source=xml:read("*a");xml:close()
    assert(source:find('deck_capacity="0"',1,true),"Katana exposed a normal editable spell slot")
    assert(source:find('click_to_use="0"',1,true) and source:find('reload_time="0"',1,true),"Katana still accepts native clicks/reloads")
    assert(not source:find("nh_red_relic",1,true),"Katana entered generic left-click relic activation")
    for _,extra in ipairs({{count=2},{remaining=NHKatanas.types[kind].durability and -1 or 1},{rounds=0},{reserve=0}}) do
        local bad=NHKatanas.item(kind)
        for k,v in pairs(extra) do bad[k]=v end
        assert(not NHKatanas.valid(bad) and not adapters[kind].restore(bad,20,26))
    end
    local blade=assert(adapters[kind].restore(NHKatanas.item(kind),20,26))
    assert(entities[blade].comps.AbilityComponent.click_to_use==false)
    local extra=CreateItemActionEntity("DAMAGE",20,26)
    EntityAddChild(blade,extra)
    assert(not adapters[kind].capture(blade) and EntityGetIsAlive(extra))
    EntityRemoveFromParent(extra)
    assert(adapters[kind].capture(blade))
    EntityKill(blade)
end
local other=EntityLoad(NHKatanas.types.hf_blade.file,20,30)
entities[other].comps.ItemCostComponent={cost=100}
assert(not adapters.hf_blade.capture(other))
entities[other].comps.ItemCostComponent=nil
entities[other].comps.AbilityComponent.use_gun_script=false
assert(not adapters.hf_blade.capture(other))
EntityKill(other)

-- Dragon King is a red collectible in storage and a native weapon in hand.
-- Its only finite resource survives issue/deposit and exhausted relic salvage.
assert(NHRedRelics.types.dragon_king.katana and adapters.dragon_king.warehouseCategory=="collection")
local pool=dofile("mods/noita_hideout/files/enemy_drops.lua").redPool
local red
for _,entry in ipairs(pool) do if entry.id=="dragon_king" then assert(not red);red=entry end end
assert(red and red.item.remaining==90 and red.item.icon==NHKatanas.types.dragon_king.icon)
local finds=dofile("mods/noita_hideout/files/pet_finds.lua")
assert(finds.known("red:dragon_king"))
for _,remaining in ipairs({90,1,0}) do
    s=assert(NHStore.load())
    local record=NHKatanas.item("dragon_king")
    record.remaining=remaining
    local id=s.nextItemId;s.nextItemId=id+1
    s.safe={};s.warehouse={{id=id,slot=1,item=record}}
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
    assert(NHTransfers.withdraw(s,1,1,"warehouse",function(e) issued=e;GamePickUpInventoryItem(1,e);return true end))
    assert(NHFirearms.nativeLane("dragon_king",issued)=="wand" and entities[issued].comps.ItemComponent.uses_remaining==remaining)
    assert(not NHRedRelics.activate(s,1,issued) and entities[issued].comps.ItemComponent.uses_remaining==remaining)
    assert(not NHRedRelics.activateStored(s,1,record,function() error("Generic relic activation charged a sword") end))
    failSave=true
    assert(not NHTransfers.deposit(s,1,"safe",issued))
    assert(EntityGetIsAlive(issued) and entities[issued].comps.ItemComponent.uses_remaining==remaining and #s.safe==0)
    failSave=false
    assert(NHTransfers.deposit(s,1,"safe",issued))
    s=assert(NHStore.load())
    assert(s.safe[1].item.remaining==remaining)
    local row=s.safe[1]
    local ref={container="safe",slot=row.slot,storedId=row.id,kind="dragon_king",remaining=remaining}
    assert(not NHInventoryUse.peek(s,1,ref) and not NHInventoryUse.spend(s,1,ref) and row.item.remaining==remaining)
    assert(NHTransfers.withdraw(s,1,1,"safe",function(e) issued=e;GamePickUpInventoryItem(1,e);return true end))
    assert(entities[issued].comps.ItemComponent.uses_remaining==remaining)
    assert(NHTransfers.deposit(s,1,"warehouse",issued))
    row=s.warehouse[1]
    assert(row.item.kind=="dragon_king" and row.item.remaining==remaining and not NHStore.supplyTrade.quote(row.item))
    local before={}
    for _,key in ipairs(NHRedRelics.resourceKeys) do before[key]=s.resources[key] or 0 end
    assert(NHRedRelics.salvage(s,{slot=row.slot,id=row.id,kind="dragon_king"}))
    assert(NHStore.commit(s))
    for _,key in ipairs(NHRedRelics.resourceKeys) do assert(s.resources[key]==before[key]+2400) end
    local cards={}
    for _,entry in ipairs(s.warehouse) do cards[entry.item.species]=entry.item.count end
    assert(cards.tarot_devil==4 and cards.dragon==4)
end
for _,remaining in ipairs({-1,91,1.5,"90"}) do
    local record=NHKatanas.item("dragon_king");record.remaining=remaining
    assert(not NHKatanas.valid(record) and not NHRedRelics.valid(record) and not adapters.dragon_king.restore(record,20,26))
end
local missing=NHKatanas.item("dragon_king");missing.remaining=nil
assert(not NHKatanas.valid(missing) and not NHRedRelics.valid(missing))

s.katanaRewardToken,s.katanaRewardSeen="1/1/test",12
assert(NHStore.commit(s))
local saved=assert(NHStore.load())
assert(saved.katanaRewardSeen==12 and saved.katanaRewardToken=="1/1/test")
for _,bad in ipairs({-1,0.5,2147483648}) do
    local rejected=assert(NHStore.load())
    rejected.katanaRewardSeen=bad
    assert(not NHStore.commit(rejected))
end
local rejected=assert(NHStore.load())
rejected.katanaRewardToken=string.rep("x",161)
assert(not NHStore.commit(rejected))

-- The built-in actions are inert even while the native gun script evaluates
-- a preview or a held trigger; only the dedicated runtime resolves damage.
actions={}
ACTION_TYPE_PROJECTILE,ACTION_TYPE_UTILITY,ACTION_TYPE_MODIFIER=0,1,2
dofile("mods/noita_hideout/files/firearm_actions.lua")
for _,kind in ipairs(NHKatanas.order) do
    local found
    for _,actionDef in ipairs(actions) do
        if actionDef.id==NHKatanas.types[kind].action then
            assert(actionDef.mana==0 and actionDef.spawn_probability=="0")
            actionDef.action()
            found=true
        end
    end
    assert(found)
end
print("Katanas: workshop costs, weapon lanes, safe/warehouse round trips, failed delivery, inert actions and reward receipt validation passed.")
