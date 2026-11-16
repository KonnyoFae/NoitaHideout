-- Simulate the game callbacks with real store, HUD case and syringe modules.
local settings, flags, world = {}, {}, {}
local frame, keys, fire, fire_stamp, inventory_open = 1, {}, false, 0, false
local opened_click, model, ending, fail_effect, fail_commit = nil, nil, false, false, false
local player, quick = 1, 2
local entities, next_id, held
local function reset_entities()
    entities = {
        [player] = {tags={player_unit=true}, x=227, y=-85, parent=0, comps={}},
        [3] = {tags={}, x=0,y=0,parent=player,name="inventory_full",comps={}},
        [quick] = {tags={}, x=0, y=0, parent=player, name="inventory_quick", comps={}},
    }
    next_id, held = 100, 0
end
reset_entities()
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v)
    if fail_commit and k:match("^noita_hideout%.p%d+_[ab]$") then return end
    settings[k] = v
end
function HasFlagPersistent(k) return flags[k] == true end
function AddFlagPersistent(k) flags[k] = true end
function GlobalsGetValue(k,d) return world[k] or d end
function GlobalsSetValue(k,v) world[k] = v end
function GameGetFrameNum() return frame end
function GameTextGet() return "English" end
function GameTextGetTranslatedOrNot(k) return k end
function CellFactory_GetType() return -1 end
function ModTextFileGetContent() return nil end
function GamePrint() end
function MagicNumbersGetValue(k) return k:sub(-1) == "X" and "227" or "-85" end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
function DoesWorldExistAt() return true end
function EntityHasTag(id,tag) return entities[id] ~= nil and entities[id].tags[tag] == true end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityGetIsAlive(id) return entities[id] ~= nil end
function EntityGetParent(id) return entities[id].parent end
function EntityGetName(id) return entities[id].name or "" end
function EntityGetRootEntity(id)
    if EntityGetParent(id) == 0 then return id end
    return EntityGetRootEntity(EntityGetParent(id))
end
function EntityGetWithTag(tag)
    local list={}
    for id in pairs(entities) do if EntityHasTag(id,tag) then list[#list+1]=id end end
    return list
end
function EntityGetInRadiusWithTag(x,y,r,tag)
    local list={}
    for _,id in ipairs(EntityGetWithTag(tag)) do
        local ex,ey=EntityGetTransform(id)
        if (ex-x)^2+(ey-y)^2<=r^2 then list[#list+1]=id end
    end
    return list
end
function EntityGetAllChildren(parent)
    local list={}
    for id,e in pairs(entities) do if e.parent==parent then list[#list+1]=id end end
    table.sort(list)
    return list
end
function GameGetAllInventoryItems() return EntityGetAllChildren(quick) end
function EntityAddComponent2(id,kind,fields)
    entities[id].comps[kind .. (fields._tags or "")] = fields
    return fields
end
local controls = {}
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    if id==player and kind=="ControlsComponent" then return controls end
    if id==player and kind=="Inventory2Component" then return {mActiveItem=held,full_inventory_slots_x=16,full_inventory_slots_y=1} end
    local e=entities[id]
    return e and e.comps[kind .. (tag or "")]
end
function ComponentGetValue2(c,key)
    if c==controls then
        if key=="mButtonDownFire" then return fire end
        if key=="mButtonFrameFire" then return fire_stamp end
        return false
    end
    if key=="inventory_slot" then return c.slotX or 0,c.slotY or 0 end
    return c[key]
end
function ComponentSetValue2(c,key,v,y)
    if key=="inventory_slot" then c.slotX,c.slotY=v,y elseif c~=controls then c[key]=v end
end
function EntitySetComponentsWithTagEnabled() end
function EntityLoad(path,x,y)
    local file=path:match("([^/]+)%.xml$")
    if file=="stimulant" and fail_effect then return 0 end
    next_id=next_id+1
    entities[next_id]={x=x,y=y,parent=0,tags={["noita_hideout_"..file]=true},comps={}}
    if file=="stimulant" then EntityAddComponent2(next_id,"GameEffectComponent",{frames=3600})
    else EntityAddComponent2(next_id,"ItemComponent",{item_name=file,ui_sprite=""}) end
    return next_id
end
function EntityKill(id)
    entities[id]=nil
    if held==id then held=0 end
end
function GameKillInventoryItem(p,id) assert(EntityGetRootEntity(id)==p); EntityKill(id) end
function GamePickUpInventoryItem(_,id) entities[id].parent=quick end
function EntityAddChild(p,id) entities[id].parent=p end
function GameIsInventoryOpen() return inventory_open end
function InputIsKeyJustDown(key) return keys[key] end
function InputIsMouseButtonDown() return fire end
function GameHasFlagRun(flag) return flag=="ending_game_completed" and ending end
function dofile_once(path) dofile(path) end
local function boot()
    dofile("mods/noita_hideout/init.lua")
    NHUI.draw=function(m,dispatch)
        model=m
        if opened_click then dispatch(unpack(opened_click)) end
    end
    OnWorldInitialized()
    OnPlayerSpawned(player)
end
local function tick(key,action,arg,down)
    frame=frame+1
    keys=key and {[key]=true} or {}
    if down and not fire then fire_stamp=frame end
    fire=down or false
    model=nil
    opened_click=action and {action,arg}
    OnWorldPreUpdate()
    OnWorldPostUpdate()
    return model
end
local function state() return assert(NHStore.load()) end
local function starter()
    local saved=state()
    return saved.pouches[saved.starterPouchId]
end
local function new_world()
    world,ending,fire,inventory_open={},false,false,false
    reset_entities()
    boot()
end
boot()
assert(#EntityGetWithTag("noita_hideout_case")==0)
OnPlayerSpawned(player)
assert(#EntityGetWithTag("noita_hideout_case")==0 and state().runSerial==1)
tick()
local function tool(id,slot)
    return {parent=quick,lane="tool",xslot=2,yslot=0,entity=id,safeSlot=slot,intoContainer=not slot,pouchId=state().starterPouchId}
end
inventory_open=true
assert(tick(nil,"take_dose",tool()).mode=="case" and starter().doses==2) -- opening click cannot withdraw
tick(nil,"take_dose",tool())
assert(starter().doses==2)
tick(nil,"open_container",{pouchId=state().starterPouchId,safeSlot=2})
tick(nil,"unpack_dose",{pouchId=state().starterPouchId,safeSlot=1})
assert(starter().doses==1 and state().safe[1].item.kind=="dose")
tick(nil,"pack_dose",{pouchId=state().starterPouchId,safeSlot=1})
assert(starter().doses==2 and #state().safe==0)
tick(nil,"take_dose",tool())
local dose=assert(EntityGetWithTag("noita_hideout_dose")[1])
assert(starter().doses==1 and EntityGetRootEntity(dose)==player)
held=0 -- drag a specific item while another slot is active
tick(nil,"place",tool(dose))
assert(not EntityGetIsAlive(dose) and starter().doses==2)
tick(nil,"take_dose",tool())
dose=assert(EntityGetWithTag("noita_hideout_dose")[1])
inventory_open=false
tick()
held=dose
tick(13) -- J no longer spends a dose
assert(EntityGetIsAlive(dose) and #EntityGetWithTag("noita_hideout_stimulant")==0)
inventory_open=true
tick(nil,nil,nil,true)
inventory_open=false
tick(nil,nil,nil,true)
assert(EntityGetIsAlive(dose))
tick()
fail_effect=true
tick(nil,nil,nil,true)
assert(EntityGetIsAlive(dose) and #EntityGetWithTag("noita_hideout_stimulant")==0)
tick()
fail_effect,fail_commit=false,true
tick(nil,nil,nil,true)
assert(EntityGetIsAlive(dose) and #EntityGetWithTag("noita_hideout_stimulant")==0)
tick()
fail_commit=false
tick(nil,nil,nil,true)
tick(nil,nil,nil,true)
assert(EntityGetIsAlive(dose) and NHDoses.remaining(state(),dose)==2)
tick()
tick(nil,nil,nil,true)
assert(NHDoses.remaining(state(),dose)==1)
tick()
tick(nil,nil,nil,true)
assert(not EntityGetIsAlive(dose) and #EntityGetWithTag("noita_hideout_stimulant")==1 and starter().doses==1)
boot()
assert(state().runSerial==1 and starter().doses==1)
-- The HUD opens away from spawn, and the pouch is a real quickbar entity.
entities[player].x=500
tick()
assert(not tick(10).open)
inventory_open=true
assert(tick().mode=="case")
tick(nil,"take_pouch",tool(nil,2))
local pouch=assert(EntityGetWithTag("noita_hideout_pouch")[1])
assert(EntityGetRootEntity(pouch)==player and starter().location=="bag")
held=pouch
tick(nil,"place",tool(pouch,1))
assert(not EntityGetIsAlive(pouch) and starter().slot==1)
tick(nil,"take_pouch",tool(nil,1))
assert(starter().location=="bag")
pouch=assert(EntityGetWithTag("noita_hideout_pouch")[1])
inventory_open=false
tick()
entities[pouch].parent=0
held=0
tick()
GamePickUpInventoryItem(player,pouch)
held=pouch
tick(nil,nil,nil,true)
assert(starter().doses==1 and #EntityGetWithTag("noita_hideout_dose")==0)
assert(tick().mode=="container")
local emptyTool=tool()
emptyTool.xslot=3
tick(nil,"take_dose",emptyTool)
assert(starter().doses==0 and #EntityGetWithTag("noita_hideout_dose")==1)
OnPlayerDied()
assert(state().closedThrough==1 and not starter())
new_world()
assert(not tick(11,"restock").open and not starter())
inventory_open=true
tick()
tick(nil,"restock")
assert(state().runSerial==2 and starter().location=="safe")
function CellFactory_GetAllLiquids() return {"magic_liquid_teleportation"} end
function CellFactory_GetAllSands() return {"sand"} end
function CellFactory_GetType(name) return name=="magic_liquid_teleportation" and 7 or -1 end
function CellFactory_GetUIName() return "$mat_teleport" end
-- Workshop spends loose stock and delivers material without creating a container.
local s=state()
s.warehouse[1]={id=s.nextItemId,item={kind="potion",materials={}}}
s.materials={slime=250,magic_liquid_unstable_teleportation=250}
s.nextItemId=s.nextItemId+1
assert(NHStore.commit(s))
boot()
inventory_open=true
tick(nil,"order")
assert(not state().order)
entities[player].x=1200
tick(nil,"order")
assert(not state().order and state().materials.slime==250)
entities[player].x=227
inventory_open=false
tick(nil,"order")
assert(not state().order)
inventory_open=true
tick()
tick(nil,"order")
assert(state().order and not next(state().materials))
ending=true
OnPlayerDied()
OnPlayerDied()
assert(state().finished==1 and #state().warehouse==1 and state().materials.magic_liquid_teleportation==500 and starter().doses==2)
new_world()
settings["noita_hideout.test_tools"]=false
inventory_open=true
tick()
tick(nil,"simulate")
assert(state().rewardedThrough==2)
settings["noita_hideout.test_tools"]=true
tick(nil,"simulate")
tick(nil,"simulate")
assert(state().rewardedThrough==3 and state().finished==1)
print("Controller: HUD case, inventory transfer, click gating, failed injection, consume, access, death and orders passed.")


-- Simulate the native outside-inventory drop before our release callback.
function EntityGetComponentIncludingDisabled(id,kind)
    local first=EntityGetFirstComponentIncludingDisabled(id,kind)
    return first and {first} or {}
end
function CreateItemActionEntity(action,x,y)
    local id=EntityLoad("spell.xml",x,y)
    EntityAddComponent2(id,"ItemActionComponent",{action_id=action})
    EntityAddComponent2(id,"ItemComponent",{item_name="Bomb",ui_sprite="data/ui_gfx/gun_actions/bomb.png",
        permanently_attached=false,uses_remaining=3,is_frozen=false,is_identified=true,has_been_picked_by_player=true})
    return id
end
local expanded=state()
assert(NHStore.expandSafe(expanded,5))
assert(NHStore.commit(expanded))
boot()
inventory_open=true
tick()
local card=CreateItemActionEntity("BOMB",200,-80)
EntityAddChild(3,card)
local item=EntityGetFirstComponentIncludingDisabled(card,"ItemComponent")
ComponentSetValue2(item,"inventory_slot",5,0)
tick()
entities[card].parent=0
tick(nil,"place",{parent=3,lane="spell",xslot=5,yslot=0,entity=card,safeSlot=5})
local row=state().safe[1]
assert(row.slot==5 and row.item.card.id=="BOMB" and not EntityGetIsAlive(card))
local target={parent=3,lane="spell",xslot=9,yslot=0,safeSlot=5,storedId=row.id}
fail_commit=true
tick(nil,"secure_withdraw",target)
assert(#state().safe==1 and #EntityGetAllChildren(3)==0)
fail_commit=false
tick(nil,"secure_withdraw",target)
local delivered=assert(EntityGetAllChildren(3)[1])
item=EntityGetFirstComponentIncludingDisabled(delivered,"ItemComponent")
assert(item.slotX==9 and item.slotY==0 and item.uses_remaining==3 and #state().safe==0)

local stash={parent=3,lane="spell",xslot=9,yslot=0,entity=delivered,safeSlot=1,container="warehouse",kind="spell"}
entities[player].x=1000
tick(nil,"place",stash)
assert(EntityGetIsAlive(delivered))
entities[player].x=227
tick(nil,"place",stash)
local view=tick()
local card_row=assert(view.warehouse.spell[1])
assert(view.warehouse.containers[1] and not EntityGetIsAlive(delivered))
stash.storedId,stash.xslot=card_row.id,7
fail_commit=true
tick(nil,"secure_withdraw",stash)
assert(tick().warehouse.spell[1].id==card_row.id and #EntityGetAllChildren(3)==0)
fail_commit=false
tick(nil,"secure_withdraw",stash)
local native_card=assert(EntityGetAllChildren(3)[1])
local native_item=EntityGetFirstComponentIncludingDisabled(native_card,"ItemComponent")
assert(native_item.slotX==7 and native_item.uses_remaining==3 and not tick().warehouse.spell)
-- A stored pouch opens only from its own container, in reach.
tick(nil,"take_pouch",tool(nil,starter().slot))
local bag=assert(EntityGetWithTag("noita_hideout_pouch")[1])
local to_stash=tool(bag,1)
to_stash.container="warehouse"
tick(nil,"place",to_stash)
local stored_bag=tick()
assert(starter().location=="warehouse" and stored_bag.warehouse.equipment[1].kind=="pouch")
assert(not stored_bag.warehouse.supplies and #EntityGetWithTag("noita_hideout_pouch")==0)
tick(nil,"open_container",{pouchId=state().starterPouchId,safeSlot=1,container="warehouse"})
assert(tick().popup)
-- The same number can hold a loose injector and its pouch in separate categories.
tick(nil,"unpack_dose",{pouchId=state().starterPouchId,container="warehouse",safeSlot=1,sourceCell=1})
local separated=tick()
assert(separated.warehouse.supplies[1].kind=="dose" and separated.warehouse.equipment[1].kind=="pouch")
tick(nil,"pack_dose",{pouchId=state().starterPouchId,container="warehouse",safeSlot=1,targetCell=1})
local packed_count=starter().doses
entities[player].x=1000
assert(not tick().popup)

-- Move an empty flask from the stash and fill it with the workshop output, then
-- return the same container with its new exact contents to a warehouse cell.
entities[player].x=227
tick(nil,"move_pouch",{pouchId=state().starterPouchId,source="warehouse",destination="warehouse",from=1,safeSlot=2})
boot()
local moved=tick()
assert(moved.warehouse.equipment[2].kind=="pouch" and not moved.warehouse.equipment[1])
local take_bag=tool(nil,2)
take_bag.container="warehouse"
tick(nil,"take_pouch",take_bag)
local bags=EntityGetWithTag("noita_hideout_pouch")
assert(#bags==1 and EntityGetRootEntity(bags[1])==player and not tick().warehouse.equipment)
tick(nil,"place",tool(bags[1],2))
assert(tick().secure_loot[2].kind=="pouch" and starter().doses==packed_count)
local product=state().warehouse[1]
assert(product)
local dock_move={container="docks",source="warehouse",destination="docks",from=product.slot,safeSlot=2,entity=product.id}
tick(nil,"move_dock",dock_move)
assert(#state().docks==0)
dock_move.safeSlot=1
tick(nil,"move_dock",dock_move)
assert(tick().docks[1].used==0)
local req={container="docks",slot=1,storedId=product.id,material="magic_liquid_teleportation",amount=1}
entities[player].x=1200
tick(nil,"material_transfer",req)
assert(state().materials.magic_liquid_teleportation==500)
entities[player].x=227
local hud=tick()
assert(hud.docks[1].used==0 and hud.materials[1].amount==500 and hud.materials[1].slot==1)
req.unload,req.material,req.amount=false,hud.materials[1].key,1
tick(nil,"material_transfer",req)
assert(tick().docks[1].used==1)
dock_move.source,dock_move.destination,dock_move.from,dock_move.safeSlot="docks","warehouse",1,product.slot
tick(nil,"move_dock",dock_move)
local final=state()
local stored=final.warehouse[assert(NHStore.slotIndex(final,"warehouse",product.slot,"potion"))]
assert(#final.docks==0 and stored.id==product.id and stored.item.materials[req.material]==1 and final.materials[req.material]==499)

-- Start a separate profile to exercise the same confirmation requests emitted by
-- the middle panel, with enough loose stock to fund even a duplicate payment.
settings,flags={},{}
new_world()
local funded=state()
funded.materials={sand=3000,slime=1800,water=2000,blood=100,lava=100,oil=500,gunpowder=300}
assert(NHStore.commit(funded))
boot()
local request={id="safe",level=0}
local function has_project(list,id)
    for _,entry in ipairs(list) do if entry.id==id then return entry end end
end
inventory_open=true
local preview=tick(nil,"buy_upgrade",request)
local upgrade=assert(has_project(preview.progression.upgrade,"safe"))
assert(upgrade.canBuy and upgrade.current=="2 slots" and upgrade.next=="3 slots")
assert(state().safeCapacity==2 and state().materials.sand==3000)
entities[player].x=900
tick(nil,"buy_upgrade",request)
entities[player].x=227
inventory_open=false
tick(nil,"buy_upgrade",request)
assert(state().safeCapacity==2 and state().materials.slime==1800)
inventory_open=true
tick()
settings["noita_hideout.test_tools"]=false
tick(nil,"buy_upgrade",request)
tick(nil,"buy_upgrade",request)
local bought=state()
assert(bought.safeCapacity==3 and bought.levels.safe==1 and bought.materials.sand==2750 and bought.materials.slime==1650)
assert(tick().capacity==3)
tick(nil,"buy_upgrade",{id="warehouse_spell",level=0})
local expanded_view=tick()
assert(expanded_view.warehouse_capacity.spell==72 and expanded_view.warehouse_capacity.wand==48)
local equip_project=assert(has_project(expanded_view.progression.expansion,"warehouse_equipment"))
assert(equip_project.canBuy and expanded_view.warehouse_capacity.equipment==48)
tick(nil,"buy_upgrade",{id="warehouse_equipment",level=0})
assert(tick().warehouse_capacity.equipment==72 and tick().warehouse_capacity.supplies==48)

-- Locked recipes remain readable in their own category; the backend rechecks access.
local catalog=tick().recipes
assert(#catalog==5)
local alchemy=assert(has_project(catalog,"stable"))
assert(alchemy.category=="alchemy" and alchemy.unlocked and not alchemy.ready and alchemy.reason)
local expected_category={medical="medical",injector="medical",grenade="weapons",pouch="equipment"}
for _,id in ipairs({"medical","injector","grenade","pouch"}) do
    local locked=assert(has_project(catalog,id))
    assert(locked.category==expected_category[id] and not locked.unlocked and not locked.ready)
    assert(locked.facility_name and locked.reason:find(locked.facility_name,1,true))
    tick(nil,"craft",{id=id})
    assert(not state().order)
end
local first_product
local products={
    {recipe="medical",kind="medkit",name="Medkit",ingredients={water=100,blood=50}},
    {recipe="injector",kind="dose",name="Fire injector",ingredients={water=100,lava=25}},
    {recipe="grenade",kind="grenade",name="Magic grenade",ingredients={sand=100,slime=50}},
}
for n,expected in ipairs(products) do
    tick(nil,"buy_upgrade",{id=expected.recipe,level=0})
    local recipe=assert(has_project(tick().recipes,expected.recipe))
    assert(recipe.unlocked and recipe.ready and recipe.category==expected_category[expected.recipe])
    assert(recipe.name==expected.name and #recipe.inputs==2)
    local before=state()
    entities[player].x=900
    tick(nil,"craft",{id=expected.recipe})
    assert(not state().order)
    entities[player].x=227
    tick(nil,"craft",{id=expected.recipe})
    tick(nil,"craft",{id=expected.recipe})
    local queued=state()
    local reserved=queued.order.output.slot
    assert(queued.order.recipe==expected.recipe and #queued.warehouse==n-1)
    for input,amount in pairs(expected.ingredients) do
        assert((queued.materials[input] or 0)==before.materials[input]-amount)
    end
    local working=tick()
    assert(working.order_name==expected.name and working.warehouse.supplies[reserved].kind=="reserved")
    for _,busy in ipairs(working.recipes) do assert(not busy.ready and busy.reason) end
    if first_product then
        tick(nil,"move_warehouse",{container="warehouse",kind="medkit",from=first_product.slot,entity=first_product.id,safeSlot=reserved})
        local still_reserved=tick().warehouse.supplies
        assert(still_reserved[first_product.slot].id==first_product.id and still_reserved[reserved].kind=="reserved")
    end
    -- The reservation outlives a reload and can only be credited once.
    boot()
    assert(tick().warehouse.supplies[reserved].kind=="reserved")
    ending=true
    tick()
    tick()
    local delivered=state()
    assert(not delivered.order and delivered.finished==n and #delivered.warehouse==n)
    local crafted=assert(tick().warehouse.supplies[reserved])
    assert(crafted.kind==expected.kind)
    if n<3 then assert(crafted.remaining==3) end
    if n==1 then first_product={slot=reserved,id=crafted.id} end
    OnPlayerDied()
    OnPlayerDied()
    assert(state().finished==n and #state().warehouse==n)
    new_world()
    inventory_open=true
    tick()
end

local function stash_spell(action)
    local id=CreateItemActionEntity(action,200,-80)
    EntityAddChild(3,id)
    tick(nil,"place",{parent=3,lane="spell",xslot=0,yslot=0,entity=id,safeSlot=1,container="warehouse",kind="spell"})
    return assert(tick().warehouse.spell[1])
end
local to_salvage=stash_spell("BOMB")
local salvage={id=to_salvage.id,kind="spell",slot=1}
tick(nil,"salvage",salvage)
assert(tick().warehouse.spell[1].id==salvage.id and not state().resources.arcane_scrap)
tick(nil,"buy_upgrade",{id="salvage",level=0})
local unlocked=tick()
assert(unlocked.salvage_enabled and unlocked.warehouse.spell[1].salvage_yield==1)
entities[player].x=900
tick(nil,"salvage",salvage)
entities[player].x=227
assert(tick().warehouse.spell[1].id==salvage.id)
tick(nil,"salvage",salvage)
assert(state().resources.arcane_scrap==1 and not tick().warehouse.spell)
local replacement=stash_spell("LIGHT")
tick(nil,"salvage",salvage)
assert(replacement.id~=salvage.id and tick().warehouse.spell[1].id==replacement.id and state().resources.arcane_scrap==1)
tick(nil,"buy_upgrade",{id="perk_pack",level=0})
assert(state().levels.perk_pack==1 and not state().resources.arcane_scrap)
print("Controller: gated purchases, independent capacity, crafted item reservations, delivery and salvage confirmed.")

-- Check the controller's range gate separately from the perk transfer journal.
local load_template=EntityLoad
function EntityLoad(path,x,y)
    local id=load_template(path,x,y)
    if path:match("/perk_fire%.xml$") then
        EntityAddTag(id,"noita_hideout_perk_card")
        EntityAddComponent2(id,"VariableStorageComponent",{_tags="noita_hideout_perk_type",value_string="PROTECTION_FIRE",value_int=0})
    end
    return id
end
function EntityRemoveFromParent(id) entities[id].parent=0 end
function EntityRemoveComponent(id,component)
    for key,value in pairs(entities[id].comps) do
        if value==component then entities[id].comps[key]=nil; return end
    end
end
tick(nil,"buy_upgrade",{id="perk_slots",level=0})
assert(tick().perkCapacity==1)
local perk=EntityLoad("mods/noita_hideout/files/items/perk_fire.xml",227,-85)
EntityAddChild(quick,perk)
local deposit={parent=quick,lane="tool",xslot=0,yslot=0,entity=perk,safeSlot=1,container="safe"}
tick(nil,"place",deposit)
local stored=assert(tick().secure_loot[1])
assert(stored.kind=="perk")
local equip={storageSlot=1,perkSlot=1,entity=stored.id,container="safe"}
entities[player].x=900
tick(nil,"equip_stored_perk",equip)
local equipped=assert(tick().perkCells[1])
assert(not tick().secure_loot[1] and equipped.entity~=perk)
local put_back={storageSlot=4,perkSlot=1,entity=equipped.entity,container="warehouse"}
tick(nil,"store_equipped_perk",put_back)
assert(tick().perkCells[1].entity==equipped.entity)
entities[player].x=227
tick(nil,"store_equipped_perk",put_back)
local protected=assert(tick().warehouse.supplies[4])
assert(protected.kind=="perk" and not tick().perkCells[1])
OnPlayerDied()
new_world()
inventory_open=true
assert(tick().warehouse.supplies[4].id==protected.id)
print("Controller: field equip from safe, home-only return to stash and perk persistence passed.")

-- A funded recipe stays unavailable while its output category is full.
local full=state()
full.materials.water,full.materials.blood=100,50
for slot=1,NHStore.warehouseCapacity(full,"supplies") do
    if not NHStore.slotIndex(full,"warehouse",slot,"dose") then
        table.insert(full.warehouse,{id=full.nextItemId,slot=slot,item={kind="dose",remaining=3,count=1}})
        full.nextItemId=full.nextItemId+1
    end
end
assert(NHStore.commit(full))
boot()
local unavailable=assert(has_project(tick().recipes,"medical"))
assert(unavailable.unlocked and not unavailable.ready and unavailable.reason)
tick(nil,"craft",{id="medical"})
assert(not state().order and state().materials.water==100 and state().materials.blood==50)
print("Controller: workshop categories, unlocks, readiness and equipment slots passed.")

-- Reopening a different physical pouch need not change the profile revision.
-- Cells must follow the selected ID, including when a prior drag is replayed.
local pair=state()
local first_id=pair.starterPouchId
local first_pouch=assert(pair.pouches[first_id])
first_pouch.cells={[1]={remaining=2,count=1},[2]={remaining=3,count=1}}
first_pouch.doses=2
local second_id=NHPouches.create(pair,"warehouse",1,0)
assert(NHStore.commit(pair))
boot()
local both=tick()
assert(both.secure_loot[first_pouch.slot].id==first_id and both.warehouse.equipment[1].id==second_id)
local open_first={safeSlot=first_pouch.slot,pouchId=first_id}
local open_second={safeSlot=1,container="warehouse",pouchId=second_id}
tick(nil,"open_container",open_first)
assert(tick().cells[1].remaining==2)
local cell=tool()
cell.sourceCell=1
tick(nil,"take_dose",cell)
local injector=assert(EntityGetWithTag("noita_hideout_dose")[1])
assert(NHDoses.remaining(state(),injector)==2)
tick(nil,"open_container",open_second)
local second_view=tick()
assert(second_view.pouchId==second_id and not next(second_view.cells))
tick(nil,"place",tool(injector)) -- stale target, retained in quick inventory
assert(EntityGetIsAlive(injector) and state().pouches[second_id].doses==0)
local insert=tool(injector)
insert.pouchId,insert.targetCell=second_id,4
tick(nil,"place",insert)
assert(not EntityGetIsAlive(injector) and tick().cells[4].remaining==2)
tick(nil,"open_container",open_first)
local first_view=tick()
assert(first_view.pouchId==first_id and first_view.cells[2].remaining==3 and not first_view.cells[4])
tick(nil,"open_container",{pouchId=second_id,safeSlot=first_pouch.slot})
assert(tick().pouchId==first_id) -- stale record cannot open a new occupant of that slot
boot()
tick()
tick(nil,"open_container",open_second)
assert(tick().cells[4].remaining==2 and state().pouches[first_id].doses==1)
local to_case={pouchId=second_id,container="warehouse",source="warehouse",destination="safe",from=1,safeSlot=1}
tick(nil,"move_pouch",to_case)
local after_move=tick()
assert(after_move.secure_loot[1].id==second_id and after_move.pouchId==second_id and after_move.cells[4].remaining==2)
local return_to_stash={pouchId=second_id,container="safe",source="safe",destination="warehouse",from=1,safeSlot=2}
entities[player].x=900
tick(nil,"move_pouch",return_to_stash)
assert(state().pouches[second_id].location=="safe")
entities[player].x=227
return_to_stash.pouchId=first_id
tick(nil,"move_pouch",return_to_stash)
assert(state().pouches[second_id].location=="safe")
return_to_stash.pouchId=second_id
tick(nil,"move_pouch",return_to_stash)
local returned=tick()
assert(returned.warehouse.equipment[2].id==second_id and returned.pouchId==second_id and returned.cells[4].remaining==2)
print("Controller: independent selected pouches, durability, stale drag cancellation and reload passed.")
