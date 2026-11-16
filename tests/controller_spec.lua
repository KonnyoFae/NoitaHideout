-- Simulate the game callbacks with real store, HUD case and syringe modules.
local settings, flags, world = {}, {}, {}
local frame,keys,inventory_open=1,{},false
local left_mouse,right_mouse=false,false
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
function ProceduralRandomi(_,_,lo) return lo end
function MagicNumbersGetValue(k) return k:sub(-1) == "X" and "227" or "-85" end
function EntityGetTransform(id)
    local e=entities[id]
    return e.x,e.y,e.rotation or 0,e.scaleX or 1,e.scaleY or 1
end
function EntitySetTransform(id,x,y,rotation,sx,sy)
    local e=entities[id]
    e.x,e.y,e.rotation,e.scaleX,e.scaleY=x,y or 0,rotation or 0,sx or 1,sy or 1
end
function DoesWorldExistAt() return true end
function EntityHasTag(id,tag) return entities[id] ~= nil and entities[id].tags[tag] == true end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityGetIsAlive(id) return entities[id] ~= nil end
function EntityGetParent(id) return entities[id].parent end
function EntityRemoveFromParent(id) entities[id].parent=0 end
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
function EntityGetClosestWithTag(x,y,tag)
    local closest,distance=0,math.huge
    for _,id in ipairs(EntityGetWithTag(tag)) do
        local dx,dy=entities[id].x-x,entities[id].y-y
        local d=dx*dx+dy*dy
        if d<distance then closest,distance=id,d end
    end
    return closest
end
function BiomeMapGetName(x,y)
    for _,id in ipairs(EntityGetWithTag("workshop_aabb")) do
        local area=entities[id]
        if math.abs(x-area.x)<=120 and math.abs(y-area.y)<=120 then return area.biome end
    end
    return "$biome_coalmine"
end
function EntityGetAllChildren(parent,tag)
    local list={}
    for id,e in pairs(entities) do if e.parent==parent and (not tag or e.tags[tag]) then list[#list+1]=id end end
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
    if c==controls then return controls[key] or false end
    if key=="inventory_slot" then return c.slotX or 0,c.slotY or 0 end
    return c[key]
end
function ComponentSetValue2(c,key,v,y)
    if key=="inventory_slot" then c.slotX,c.slotY=v,y else c[key]=v end
end
function EntitySetComponentsWithTagEnabled() end
function EntityLoad(path,x,y)
    local file=path:match("([^/]+)%.xml$")
    if file:match("^stimulant") and fail_effect then return 0 end
    next_id=next_id+1
    entities[next_id]={x=x,y=y,parent=0,tags={["noita_hideout_"..file]=true},comps={}}
    if file=="stimulant_healing" then EntityAddComponent2(next_id,"VariableStorageComponent",{value_int=60,value_float=2})
    elseif file:match("^stimulant") then EntityAddComponent2(next_id,"GameEffectComponent",{frames=3600})
    elseif file:match("^dose_") then
        EntityAddTag(next_id,"noita_hideout_dose")
        EntityAddComponent2(next_id,"ItemComponent",{item_name=file,ui_sprite=file..".png"})
    elseif file:match("^card_") and file~="card_wallet" then
        EntityAddTag(next_id,"noita_hideout_summon_card")
        EntityAddTag(next_id,"nh_companion_"..file:sub(6))
        EntityAddComponent2(next_id,"ItemComponent",{item_name=file,ui_sprite=file..".png",uses_remaining=80})
    elseif path:find("/companions/",1,true) and NHCompanions.species[file] then
        EntityAddTag(next_id,"noita_hideout_companion")
        EntityAddComponent2(next_id,"VariableStorageComponent",{_tags="nh_companion_clock",value_string=file,value_int=0})
        for _,tag in ipairs({"nh_gifts","nh_trip","nh_position"}) do
            EntityAddComponent2(next_id,"VariableStorageComponent",{_tags=tag,value_int=0,value_float=0})
        end
    elseif file=="home_wand_edit" then EntityAddComponent2(next_id,"GameEffectComponent",{effect="EDIT_WANDS_EVERYWHERE",frames=3})
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
function InputIsMouseButtonDown(button) return (button==1 and left_mouse) or (button==2 and right_mouse) or false end
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
local function tick(key,action,arg,button)
    frame=frame+1
    keys=key and {[key]=true} or {}
    local left=button=="left" or button=="both"
    local right=button=="right" or button=="both"
    if left and not left_mouse then controls.mButtonFrameFire=frame end
    if right and not right_mouse then controls.mButtonFrameThrow=frame end
    left_mouse,right_mouse=left,right
    controls.mButtonDownFire,controls.mButtonDownLeftClick=left,left
    controls.mButtonDownThrow,controls.mButtonDownRightClick=right,right
    model=nil
    opened_click=action and {action,arg}
    OnWorldPreUpdate()
    OnWorldPostUpdate()
    return model
end
-- Skip unchanged frames while retaining the real unpaused frame number.
local function advance(frames)
    frame=frame+frames-1
    return tick()
end
local function state() return assert(NHStore.load()) end
local function starter()
    local saved=state()
    return saved.pouches[saved.starterPouchId]
end
local function new_world()
    world,ending,left_mouse,right_mouse,inventory_open={},false,false,false,false
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
local charges_before_left=NHDoses.remaining(state(),dose)
for i=1,4 do
    tick(nil,nil,nil,"left")
    assert(not controls.mButtonDownFire and NHDoses.remaining(state(),dose)==charges_before_left)
end
tick()
inventory_open=true
tick(nil,nil,nil,"right")
inventory_open=false
tick(nil,nil,nil,"right")
assert(EntityGetIsAlive(dose))
tick()
fail_effect=true
tick(nil,nil,nil,"right")
assert(EntityGetIsAlive(dose) and #EntityGetWithTag("noita_hideout_stimulant")==0)
tick()
fail_effect,fail_commit=false,true
tick(nil,nil,nil,"right")
assert(EntityGetIsAlive(dose) and #EntityGetWithTag("noita_hideout_stimulant")==0)
tick()
fail_commit=false
tick(nil,nil,nil,"right")
tick(nil,nil,nil,"right")
assert(EntityGetIsAlive(dose) and NHDoses.remaining(state(),dose)==2)
tick()
tick(nil,nil,nil,"right")
assert(NHDoses.remaining(state(),dose)==1)
tick()
tick(nil,nil,nil,"right")
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
tick(nil,nil,nil,"right")
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
local just_started=tick()
local initial_remaining,drag_revision=just_started.order_remaining,just_started.revision
assert(initial_remaining==8)
local advancing=advance(120)
assert(advancing.order_remaining==initial_remaining-2 and advancing.revision==drag_revision)
ending=true
tick()
OnPlayerDied()
OnPlayerDied()
local interrupted=state()
assert(interrupted.order and interrupted.order.progress>0 and interrupted.finished==0 and starter().doses==2)
frame=frame+interrupted.order.required*2
new_world()
inventory_open=true
local resumed=tick()
assert(resumed.order_active and math.abs(resumed.order_remaining-advancing.order_remaining)<=1)
advance(interrupted.order.required-interrupted.order.progress)
tick()
assert(not state().order and state().finished==1 and #state().warehouse==1 and state().materials.magic_liquid_teleportation==500)
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
funded.resources={active_herb=2,essence_fire=6}
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
assert(#catalog==#NHStore.recipes)
for _,recipe in ipairs(NHStore.recipes) do
    local entry=assert(has_project(catalog,recipe.id),recipe.id)
    if recipe.category=="alchemy" then
        assert(entry.category=="alchemy" and entry.alchemyMode==recipe.alchemyMode,recipe.id)
        assert(entry.duration==math.ceil(NHStore.productionFrames(recipe)/60))
        assert(#entry.inputs==#recipe.inputs and #entry.outputs>0)
        for i,input in ipairs(recipe.inputs) do
            local name=input.alternatives and (input.labelEn or NHPotion.materialName(input.name)).." (total)" or NHPotion.materialName(input.name,"en")
            assert(entry.inputs[i].name==name and entry.inputs[i].amount==input.amount)
        end
        local shown={}
        for _,output in ipairs(entry.outputs) do shown[output.key]=output.amount end
        for name,amount in pairs(recipe.materials) do assert(shown[name]==amount,recipe.id) end
    else
        assert(entry.alchemyMode==nil,recipe.id)
    end
end
local alchemy=assert(has_project(catalog,"stable"))
assert(alchemy.category=="alchemy" and alchemy.unlocked and not alchemy.ready and alchemy.reason)
local reverse=assert(has_project(catalog,"reverse_stable"))
assert(reverse.category=="alchemy" and reverse.unlocked and #reverse.inputs==1 and #reverse.outputs==2)
local expected_category={medical="medical",injector="medical",injector_lightning="medical",injector_frost="medical",injector_healing="medical",
    grenade="weapons",grenade_essence="weapons",pouch="equipment"}
assert(not has_project(catalog,"medkit_essence"))
for _,id in ipairs({"medical","injector","injector_lightning","injector_frost","injector_healing","grenade","grenade_essence","pouch"}) do
    local locked=assert(has_project(catalog,id))
    assert(locked.category==expected_category[id] and not locked.unlocked and not locked.ready)
    assert(locked.facility_name and locked.reason:find(locked.facility_name,1,true))
    tick(nil,"craft",{id=id})
    assert(not state().order)
end
local first_product
local products={
    {recipe="medical",kind="medkit",name="Medkit",ingredients={water=100,blood=50}},
    {recipe="injector",kind="dose",name="Fire injector",stock="resources",ingredients={active_herb=2,essence_fire=6}},
    {recipe="grenade",kind="grenade",name="Magic grenade",ingredients={sand=64,slime=32}},
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
        local stock=expected.stock or "materials"
        assert((queued[stock][input] or 0)==before[stock][input]-amount)
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
    advance(queued.order.required)
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

local function stash_spell(action,uses,name)
    local id=CreateItemActionEntity(action,200,-80)
    local item=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
    if uses~=nil then ComponentSetValue2(item,"uses_remaining",uses) end
    if name then ComponentSetValue2(item,"item_name",name) end
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
assert(unlocked.warehouse.spell[1].essence.key==NHEssences.byAction.BOMB and unlocked.warehouse.spell[1].spell_uses==3)
assert(unlocked.warehouse.spell[1].essence.per_card==NHEssences.values.BOMB)
entities[player].x=900
tick(nil,"salvage",salvage)
entities[player].x=227
assert(tick().warehouse.spell[1].id==salvage.id)
tick(nil,"salvage",salvage)
assert(state().resources.arcane_scrap==1 and not tick().warehouse.spell)
do
    local key=NHEssences.byAction.HEAL_BULLET
    local profile=NHEssences.healingProfiles.HEAL_BULLET
    for _,test in ipairs({{"grenade_essence","essence_high_energy",4},{"injector","essence_fire",6}}) do
        local recipe=assert(has_project(tick().recipes,test[1]))
        assert(recipe.unlocked and not recipe.ready and recipe.reason=="Not enough workshop resources.")
        local i=#recipe.inputs
        assert(i==(test[1]=="injector" and 2 or 1) and recipe.inputs[i].name==NHEssences.types[test[2]].en)
        assert(recipe.inputs[i].available==0 and recipe.inputs[i].amount==test[3])
    end
    for expected,uses in ipairs({0,2,20}) do
        local view=stash_spell("HEAL_BULLET",uses)
        local stock=(expected-1)*profile.amount
        assert(view.spell_uses==uses and view.essence.key==key and view.essence.amount==profile.amount and view.essence.stock==stock)
        assert(view.essence.per_card==profile.amount and view.essence.basis==profile.en)
        local request={id=view.id,kind="spell",slot=1,mode="essence"}
        tick(nil,"salvage",request)
        tick(nil,"salvage",request)
        assert(state().resources[key]==expected*profile.amount and state().resources.arcane_scrap==1 and not tick().warehouse.spell)
    end
    boot()
    local balances=tick().essences
    assert(#balances==17)
    for _,balance in ipairs(balances) do
        assert(balance.amount==(balance.key==key and 3*profile.amount or 0))
        assert(balance.name==NHEssences.types[balance.key].en)
    end
    assert(not has_project(tick().recipes,"medkit_essence"))
    local previous=GameTextGetTranslatedOrNot
    function GameTextGetTranslatedOrNot(key)
        if key=="$action_teleport_closer" then return "Homebringer Teleport Bolt" end
        if key=="$action_custom_name" then return "Stored card name" end
        return previous(key)
    end
    for _,test in ipairs({{"TELEPORT_PROJECTILE_CLOSER","$item_spell","Homebringer Teleport Bolt"},
        {"HEAL_BULLET","$action_custom_name","Stored card name"}}) do
        local view=stash_spell(test[1],1,test[2])
        assert(view.name==test[3])
        tick(nil,"salvage",{id=view.id,kind="spell",slot=1,mode="essence"})
    end
    GameTextGetTranslatedOrNot=previous
end
local replacement=stash_spell("FUNKY_SPELL",1,"$item_spell")
assert(replacement.name=="???" and not replacement.essence)
tick(nil,"salvage",{id=replacement.id,slot=1,kind="spell",mode="essence"})
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

-- Reach actual workshop hitboxes. A boundary in another biome, a nearby
-- workshop outside its hitbox, or an already-visited mountain grants nothing.
settings,flags={},{}
new_world()
inventory_open=true
tick()
local mountain=function(x,y,biome)
    local id=EntityLoad("workshop.xml",x,y)
    EntityAddTag(id,"workshop_aabb")
    entities[id].biome=biome
    EntityAddComponent2(id,"HitboxComponent",{aabb_min_x=-80,aabb_min_y=-32,aabb_max_x=80,aabb_max_y=32})
    return id
end
local function stand(x,y)
    entities[player].x,entities[player].y=x,y
    local view
    for i=1,11 do view=tick() end
    return view
end
local function receipts()
    local n=0
    for _ in pairs(state().checkpoints) do n=n+1 end
    return n
end
local holy="$biome_holymountain"
mountain(1000,2048,holy)
mountain(1000,4096,holy)
mountain(1000,6144,holy)
mountain(1000,400,"$biome_coalmine")
stand(1000,400)
stand(1000,2048+70)
assert(receipts()==0)
stand(1020,2048)
assert(receipts()==1 and not state().order)

local supplied=state()
supplied.materials={magic_liquid_protection_all=50,poison=50}
assert(NHStore.commit(supplied))
entities[player].x,entities[player].y=227,-85
boot()
tick()
tick(nil,"craft",{id="reverse_ambrosia"})
local normal=tick().order_remaining
assert(normal==90 and state().order)
local old_mountain=stand(1000,2048)
assert(receipts()==1 and old_mountain.order_remaining>=normal-1)
local accelerated=stand(1000,4096)
assert(receipts()==2 and math.abs(accelerated.order_remaining-(normal-60))<=1)
stand(1000,3600)
local repeat_visit=stand(1000,4096)
assert(receipts()==2 and math.abs(repeat_visit.order_remaining-accelerated.order_remaining)<=1)
boot()
local reloaded=stand(1000,4096)
assert(receipts()==2 and math.abs(reloaded.order_remaining-repeat_visit.order_remaining)<=1)
stand(1000,6144)
local complete_batch=state()
assert(receipts()==3 and not complete_batch.order and complete_batch.finished==1)
assert(complete_batch.materials.honey==50 and complete_batch.materials.diamond==50)
tick()
assert(state().finished==1)

-- No active player pauses elapsed time. A polymorphed player still explores
-- the world, earns active time and can discover a new checkpoint.
stand(227,-85)
tick(nil,"craft",{id="ambrosia"})
local before_absence=tick().order_remaining
entities[player].tags.player_unit=nil
tick()
advance(2*NHStore.productionFrames())
tick()
assert(state().order and state().finished==1)
entities[player].tags.player_unit=true
assert(tick().order_remaining==before_absence)
local poly=EntityLoad("polymorph.xml",227,-85)
EntityAddTag(poly,"polymorphed_player")
entities[player].tags.player_unit=nil
tick()
advance(700)
assert(state().order.progress>=700 and state().order.progress<800)
mountain(1000,8192,holy)
entities[poly].x,entities[poly].y=1000,8192
for i=1,11 do tick() end
assert(receipts()==4 and state().order.progress>=700+NHStore.checkpointFrames)
EntityKill(poly)
entities[player].tags.player_unit=true
assert(tick().order_remaining<50 and state().finished==1)
print("Controller: timers, suspension, polymorph, Holy Mountain hitboxes, checkpoint deduplication and reverse alchemy passed.")

-- Drive both sides through the inventory callback. Account for the native
-- wallet separately from the profile so a reload can expose a duplicate debit.
local function testBank()
    settings,flags={},{}
    new_world()
    local function addWallet(gold)
        return EntityAddComponent2(player,"WalletComponent",{
            money=gold,money_spent=17,mMoneyPrevFrame=31,mHasReachedInf=false})
    end
    local wallet=addWallet(135)
    local function transfer(direction,amount)
        tick(nil,"bank_transfer",{direction=direction,amount=amount})
    end
    local function balances(carried,stored)
        assert(wallet.money==carried,"Unexpected native gold: "..tostring(wallet.money))
        assert(state().bankGold==stored,"Unexpected bank balance: "..tostring(state().bankGold))
        assert(wallet.money_spent==17 and wallet.mMoneyPrevFrame==31)
    end
    inventory_open=true
    transfer("deposit",100) -- suppress the opening click
    balances(135,0)
    assert(tick().walletGold==135 and tick().bankGold==0)
    transfer("deposit",100)
    balances(35,100)
    transfer("deposit",1000)
    transfer("withdraw",101)
    for _,amount in ipairs({0,-1,0.5,"10",math.huge,0/0}) do transfer("deposit",amount) end
    transfer("bogus",10)
    balances(35,100)
    wallet.money=42 -- vanilla gold pickup, no profile revision
    assert(tick().walletGold==42)
    entities[player].x=800
    transfer("withdraw",10)
    transfer("deposit","all")
    balances(42,100)
    entities[player].x=227
    inventory_open=false
    transfer("deposit","all")
    inventory_open=true
    tick()
    balances(42,100)
    transfer("withdraw",10)
    balances(52,90)
    transfer("deposit","all")
    balances(0,142)
    transfer("deposit","all")
    transfer("withdraw","all")
    balances(142,0)
    transfer("withdraw","all")
    balances(142,0)
    local comps=entities[player].comps
    comps.WalletComponent=nil
    assert(tick().walletGold==nil)
    transfer("deposit",10)
    balances(142,0)
    comps.WalletComponent=wallet

    fail_commit=true
    transfer("deposit",42)
    fail_commit=false
    boot()
    tick()
    balances(142,0)
    transfer("deposit",42)
    balances(100,42)
    -- The profile has accepted the transfer, but the native component write
    -- is lost. Reload the same world twice; recovery must finish only once.
    local function failWalletWrite(direction,amount,oldGold,newBank)
        local set=ComponentSetValue2
        local touched=false
        function ComponentSetValue2(c,key,...)
            if c==wallet and key=="money" then touched=true; return end
            set(c,key,...)
        end
        transfer(direction,amount)
        ComponentSetValue2=set
        assert(touched,"No native gold transfer attempted")
        balances(oldGold,newBank)
        for i=1,2 do
            boot()
            tick()
            advance(120)
        end
    end
    failWalletWrite("withdraw",12,100,30)
    balances(112,30)
    failWalletWrite("deposit",28,112,58)
    balances(84,58)
    local function savedWorld()
        local copy={}
        for k,v in pairs(world) do copy[k]=v end
        return copy
    end
    local earlierWorld=savedWorld()
    transfer("deposit",20)
    transfer("withdraw",5)
    balances(69,73)
    world=earlierWorld
    wallet.money=84+7 -- restored native wallet plus gold earned outside the bank
    boot()
    tick()
    balances(76,73)
    local setWorld=GlobalsSetValue
    function GlobalsSetValue(k,v)
        if not k:match("^noita_hideout%.bank_wallet%.") then setWorld(k,v) end
    end
    transfer("deposit",5)
    balances(76,78)
    tick()
    balances(76,78) -- the receipt cannot be saved, so native money stays intact
    GlobalsSetValue=setWorld
    tick()
    balances(71,78)
    boot()
    tick()
    balances(71,78)
    transfer("withdraw",5)
    balances(76,73)
    -- Only the prepared world receipt survives. Test both a lost native write
    -- and a successful one whose rollback fails, then reload each twice.
    for _,credited in ipairs({false,true}) do
        local setMoney=ComponentSetValue2
        local beforeWallet,beforeBank=wallet.money,state().bankGold
        function GlobalsSetValue(k,v)
            if not k:match("^noita_hideout%.bank_wallet%.") or v:find("/",1,true) then setWorld(k,v) end
        end
        function ComponentSetValue2(c,k,v,...)
            if c~=wallet or k~="money" or (credited and v==beforeWallet+1) then setMoney(c,k,v,...) end
        end
        transfer("withdraw",1)
        balances(beforeWallet+(credited and 1 or 0),beforeBank-1)
        GlobalsSetValue,ComponentSetValue2=setWorld,setMoney
        for i=1,2 do
            boot()
            tick()
            balances(beforeWallet+1,beforeBank-1)
        end
        transfer("deposit",1)
        balances(76,73)
    end
    -- Replaying a much poorer native world never creates a negative wallet.
    -- Pickups settle the outstanding debit before withdrawals become possible.
    earlierWorld=savedWorld()
    transfer("deposit",30)
    balances(46,103)
    world,wallet.money=earlierWorld,4
    boot()
    assert(tick().walletGold==nil)
    balances(0,103)
    local pendingWater=has_project(tick().shopGoods,"water")
    assert(not pendingWater.ready and pendingWater.reason=="Waiting for wallet settlement.")
    tick(nil,"shop_buy",{id="water"})
    assert(not state().materials.water and state().bankGold==103)
    transfer("withdraw",10)
    balances(0,103)
    wallet.money=20
    assert(tick().walletGold==nil)
    balances(0,103)
    wallet.money=9
    assert(tick().walletGold==3)
    balances(3,103)
    assert(has_project(tick().shopGoods,"water").ready)
    transfer("withdraw",30)
    balances(33,73)
    boot()
    tick()
    balances(33,73)
    OnPlayerDied()
    new_world()
    wallet=addWallet(0)
    inventory_open=true
    tick()
    balances(0,73)
    transfer("withdraw","all")
    balances(73,0)
    -- Integer arithmetic at each destination limit. An all-transfer that
    -- exceeds headroom must leave both amounts and the original wallet intact.
    wallet.money=NHStore.maxGold
    transfer("deposit","all")
    balances(0,NHStore.maxGold)
    wallet.money=1
    transfer("deposit",1)
    transfer("deposit","all")
    transfer("withdraw","all")
    balances(1,NHStore.maxGold)
    boot()
    tick()
    balances(1,NHStore.maxGold)
    wallet.mHasReachedInf=true
    local infinite=tick()
    assert(infinite.walletInfinite and infinite.walletGold==nil)
    transfer("withdraw",1)
    balances(1,NHStore.maxGold)
    assert(wallet.mHasReachedInf)
end
testBank()
print("Controller: live wallet transfers, range, exact balances, recovery and cross-run bank savings passed.")

local function testShop()
    settings,flags={},{}
    new_world()
    local wallet=EntityAddComponent2(player,"WalletComponent",{money=400,money_spent=0,mHasReachedInf=false})
    local function buy(id) return tick(nil,"shop_buy",{id=id}) end
    inventory_open=true
    local unfinanced=has_project(buy("water").shopGoods,"water")
    assert(not unfinanced.ready and unfinanced.price==20 and unfinanced.quantity==250)
    buy("water")
    assert(wallet.money==400 and not state().materials.water)
    tick(nil,"bank_transfer",{direction="deposit",amount=320})
    local view=tick()
    assert(view.bankGold==320 and view.walletGold==80 and #view.shopGoods==11)
    assert(has_project(view.shopGoods,"medkit").category=="supplies")
    entities[player].x=900
    buy("water")
    entities[player].x=227
    inventory_open=false
    buy("water")
    inventory_open=true
    buy("water") -- opening the inventory cannot also confirm a purchase
    assert(state().bankGold==320 and not state().materials.water)
    fail_commit=true
    buy("water")
    fail_commit=false
    boot()
    tick()
    assert(state().bankGold==320 and not state().materials.water)
    buy("water")
    buy("medkit")
    buy("injector")
    local settled=tick()
    assert(settled.bankGold==20 and wallet.money==80 and wallet.money_spent==0)
    assert(state().materials.water==250 and settled.warehouse.supplies[1].kind=="medkit")
    assert(settled.warehouse.supplies[2].kind=="dose" and settled.warehouse.supplies[2].remaining==3)
    local recent=state()
    assert(NHStore.spendGold(recent,1) and NHStore.commit(recent))
    assert(has_project(settled.shopGoods,"water").ready)
    buy("water") -- recheck the price against the latest profile
    assert(state().bankGold==19 and state().materials.water==250)
    assert(not has_project(tick().shopGoods,"water").ready)
    boot()
    local resumed=tick()
    assert(resumed.bankGold==19 and not has_project(resumed.shopGoods,"water").ready)
    assert(#state().warehouse==2 and wallet.money==80)
end
testShop()
print("Controller: shop previews, range, deposits, commit failure, stale funds and reload passed.")

local function testPowderSeparation()
    settings,flags={},{}
    new_world()
    local profile=state()
    profile.materials={gunpowder_unstable=80,gunpowder=140}
    assert(NHStore.commit(profile))
    function CellFactory_GetAllLiquids() return {"magic_liquid_hp_regeneration"} end
    function CellFactory_GetAllSands() return {"purifying_powder","gunpowder","gunpowder_unstable"} end
    boot()
    inventory_open=true
    local view=tick()
    local split=assert(has_project(view.recipes,"separate_gunpowder"))
    assert(split.alchemyMode=="decomposition" and split.ready and split.inputs[1].available==220)
    assert(split.inputs[1].detail:find("Alchemical gunpowder  80 / 80\nRegular gunpowder  140 / 120",1,true))
    assert(view.materials[1].name=="Regular gunpowder" and view.materials[2].name=="Alchemical gunpowder")
    tick(nil,"craft",{id=split.id})
    assert(state().materials.gunpowder==20 and not state().materials.gunpowder_unstable)
    advance(split.duration*60)
    local stock={}
    for _,material in ipairs(tick().materials) do stock[material.key]=material end
    assert(stock.magic_liquid_hp_regeneration.amount==100 and stock.magic_liquid_hp_regeneration.slot==1)
    assert(stock.purifying_powder.amount==100 and stock.purifying_powder.slot==2)
end
testPowderSeparation()
print("Controller: combined gunpowder stock, separated inputs and liquid/powder delivery passed.")

local function testCatalyticWorkshop()
    settings,flags={},{}
    new_world()
    local stock=state()
    stock.materials={midas_precursor=500,midas=1,water=250}
    assert(NHStore.commit(stock))
    boot()
    inventory_open=true
    local menu=tick().recipes
    local midas=assert(has_project(menu,"midas"))
    assert(midas.ready and #midas.catalysts==1 and midas.catalysts[1].available==1)
    assert(midas.duration==180 and #midas.outputs==1 and midas.outputs[1].amount==100 and midas.outputs[1].key=="midas")
    assert(not has_project(menu,"mana").ready and has_project(menu,"mana").reason=="Missing catalyst.")
    for _,recipe in ipairs(menu) do
        for _,result in ipairs(recipe.outputs) do assert(result.key~="gold") end
    end
    tick(nil,"craft",{id="midas"})
    boot()
    local inProgress=has_project(tick().recipes,"midas")
    assert(inProgress.catalysts[1].held==1 and inProgress.catalysts[1].available==0)
    assert(inProgress.outputs[1].amount==100 and not state().materials.midas)
    advance(midas.duration*60)
    assert(state().materials.midas==101 and state().materials.midas_precursor==400)
    assert(not state().materials.gold and state().bankGold==0 and not state().order)
end
testCatalyticWorkshop()

local function testLegacyMedkitOrder()
    settings,flags={},{}
    new_world()
    local stock=state()
    stock.resources.essence_healing=25
    stock.order={id=stock.finished+1,recipe="medkit_essence",progress=60,required=180,
        output={slot=1,item={kind="medkit",remaining=3,name="$nh_hideout_medkit"}}}
    assert(NHStore.commit(stock))
    local previous=GameTextGetTranslatedOrNot
    function GameTextGetTranslatedOrNot(key)
        if key=="$nh_hideout_medkit" then return "Medkit" end
        return previous(key)
    end
    boot()
    inventory_open=true
    local view=tick()
    assert(view.order_active and view.order_name=="Medkit" and view.order_remaining==2)
    assert(not has_project(view.recipes,"medkit_essence") and view.warehouse.supplies[1].kind=="reserved")
    advance(60)
    assert(tick().order_remaining==1)
    advance(60)
    local delivered=state()
    assert(not delivered.order and delivered.warehouse[1].item.kind=="medkit")
    assert(delivered.resources.essence_healing==25)
    GameTextGetTranslatedOrNot=previous
end
testLegacyMedkitOrder()

local function testSafehouseWandEditing()
    new_world()
    local tag="noita_hideout_home_wand_edit"
    local function effects() return EntityGetAllChildren(player,tag) end
    assert(#effects()==1 and not inventory_open)
    local first=effects()[1]
    local native=EntityLoad("native_perk.xml",227,-85)
    EntityAddComponent2(native,"GameEffectComponent",{effect="EDIT_WANDS_EVERYWHERE",frames=-1})
    EntityAddChild(player,native)
    entities[player].x=227+80
    inventory_open=true
    assert(tick().near and effects()[1]==first)
    entities[player].x=227+81
    assert(not tick().near and #effects()==0 and EntityGetIsAlive(native))
    entities[player].x=227
    assert(tick().near and #effects()==1)
    boot()
    assert(#effects()==1)
    OnPlayerDied()
    tick()
    assert(#effects()==0 and EntityGetIsAlive(native))
end
testSafehouseWandEditing()
print("Controller: held catalyst, net delivery, field-only gold and native home wand editing passed.")

local function testFarmController()
    settings,flags={},{}
    new_world()
    local seeded=state()
    seeded.levels.medical=1
    seeded.materials={soil=50,soil_lush=100,water=100}
    seeded.resources={herb=2,sugar=2}
    assert(NHStore.commit(seeded))
    boot()
    inventory_open=true
    local view=tick()
    assert(#view.farm.plots==0 and not has_project(view.recipes,"bread").unlocked)
    assert(has_project(view.progression.expansion,"farmland").canBuy)
    tick(nil,"buy_upgrade",{id="farmland",level=0})
    view=tick()
    assert(#view.farm.plots==1 and has_project(view.recipes,"bread").unlocked)
    assert(not state().materials.water and not state().materials.soil_lush and not state().materials.soil)
    local function quote(crop)
        local plot=tick().farm.plots[1]
        return {plot=plot.id,token=plot.token,crop=crop}
    end
    tick(nil,"farm_plant",quote("active_herb"))
    assert(not state().farm.plots[1])
    local sow=quote("fiber")
    tick(nil,"farm_plant",sow)
    local switch=quote("grain")
    assert(not state().resources.fiber and state().farm.plots[1].crop=="fiber")
    local before=advance(360).farm.plots[1].remaining
    boot()
    assert(tick().farm.plots[1].remaining==before,"reloading retains partial growth")

    entities[player].x=227+81
    inventory_open=false
    fail_commit=true
    advance(NHFarm.crops.fiber.frames)
    assert(not state().resources.fiber,"a failed deposit must keep the batch due")
    fail_commit=false
    boot()
    assert(not tick().near and state().resources.fiber==6)
    local nextAt=state().farm.plots[1].readyAt
    inventory_open=true
    tick()
    tick(nil,"farm_plant",switch)
    entities[player].x=227
    inventory_open=false
    tick(nil,"farm_plant",switch)
    inventory_open=true
    tick(nil,"farm_plant",switch)
    assert(state().farm.plots[1].crop=="fiber","field settings require an open hideout inventory")
    tick(nil,"farm_plant",switch)
    tick(nil,"farm_plant",sow)
    view=tick()
    assert(view.farm.plots[1].crop=="grain" and state().farm.plots[1].readyAt==nextAt)
    view=advance(view.farm.plots[1].remaining*60)
    assert(state().resources.grain==6 and state().farm.plots[1].readyAt==nextAt+NHFarm.crops.grain.frames)
    assert(view.farm.crops[1].stock==6 and not state().materials.fiber)
    assert(has_project(view.recipes,"bread").ready,"the open workshop must see a passive deposit immediately")
    local bandage=has_project(view.recipes,"bandage")
    local kit=has_project(view.recipes,"field_medkit")
    assert(bandage.duration==3 and kit.duration==5 and has_project(view.recipes,"medical").duration==5)
    assert(bandage.ready and bandage.output==8 and bandage.inputs[1].available==6 and bandage.inputs[1].amount==4)
    assert(bandage.inputs[2].available==2 and bandage.inputs[2].amount==2)
    assert(kit.inputs[1].available==2 and kit.inputs[2].available==0 and not kit.ready)
    assert(kit.inputs[2].detail=="Supplies storage")
    assert(has_project(view.recipes,"bread").category=="food" and has_project(view.recipes,"sugar_cube").category=="food")
    tick(nil,"craft",{id="bandage"})
    assert(state().order.required==180 and state().resources.fiber==2 and not state().resources.sugar)
    view=advance(179)
    assert(view.order_remaining==1 and view.warehouse.supplies[1].kind=="reserved")
    view=tick()
    assert(view.warehouse.supplies[1].kind=="bandage" and view.warehouse.supplies[1].count==8)
    kit=has_project(view.recipes,"field_medkit")
    assert(kit.ready and kit.inputs[2].available==8 and kit.inputs[2].amount==1)
    tick(nil,"craft",{id="field_medkit"})
    assert(state().order.required==300)
    assert(advance(120).order_remaining==3)
    boot()
    assert(tick().order_remaining==3,"continue must keep time already spent on a five-second kit")
    view=advance(178)
    assert(view.order_remaining==1 and view.warehouse.supplies[1].count==7 and view.warehouse.supplies[2].kind=="reserved")
    view=tick()
    assert(view.warehouse.supplies[2].kind=="medkit" and view.warehouse.supplies[2].remaining==3)
    assert(not state().resources.herb and has_project(view.recipes,"field_medkit").inputs[2].available==7)
    advance(125)
    local elapsed=NHFarm.observe(state(),frame)
    local deadline=state().farm.plots[1].readyAt
    OnPausedChanged(true,false)
    assert(state().farm.time==elapsed)
    new_world()
    assert(NHFarm.observe(state(),frame)==elapsed and state().farm.plots[1].readyAt==deadline)
    local supplies=state()
    supplies.materials.soil,supplies.materials.water=300,200
    assert(NHStore.commit(supplies))
    boot()
    inventory_open=true
    tick()
    tick(nil,"buy_upgrade",{id="farmland",level=1})
    local second=tick().farm.plots[2]
    tick(nil,"farm_plant",{plot=2,token=second.token,crop="grain"})
    local twoFields=tick().farm
    assert(has_project(twoFields.crops,"grain").perMinute==4 and has_project(twoFields.crops,"fiber").perMinute==0)
    tick(nil,"farm_plant",{plot=2,token=twoFields.plots[2].token,crop="fiber"})
    local switched=tick().farm
    assert(has_project(switched.crops,"grain").perMinute==2 and has_project(switched.crops,"fiber").perMinute==3)
end
testFarmController()
print("Controller: passive field deposits, retry, crop switching, live workshop stock and crafting passed.")

do
    settings,flags={},{}
    new_world()
    local s=state()
    local bag=s.pouches[s.starterPouchId]
    for i,kind in ipairs({"lightning","frost","healing"}) do assert(NHStore.putPouchDose(bag,3,i+1,kind)) end
    assert(NHStore.commit(s))
    boot()
    local effects={}
    for i,kind in ipairs(NHInjectors.order) do
        local d=NHInjectors.get(kind)
        inventory_open=true
        tick()
        tick(nil,"open_container",{pouchId=s.starterPouchId,safeSlot=2})
        local slot=tool()
        slot.sourceCell=i
        tick(nil,"take_dose",slot)
        local syringe=assert(EntityGetWithTag("noita_hideout_"..d.filename)[1])
        assert(select(2,NHDoses.remaining(state(),syringe))==kind)
        inventory_open,held=false,syringe
        tick()
        tick() -- release the inventory's closing click before using the held item
        tick(nil,nil,nil,"right")
        effects[kind]=assert(EntityGetWithTag(d.tag)[1],kind)
        assert(EntityGetParent(effects[kind])==player and NHDoses.remaining(state(),syringe)==2)
        local timer=kind=="healing" and "VariableStorageComponent" or "GameEffectComponent"
        local field=kind=="healing" and "value_int" or "frames"
        local component=EntityGetFirstComponentIncludingDisabled(effects[kind],timer)
        ComponentSetValue2(component,field,1)
        tick()
        tick(nil,nil,nil,"right")
        assert(#EntityGetWithTag(d.tag)==1 and ComponentGetValue2(component,field)==(kind=="healing" and 60 or 3600))
        tick()
        tick(nil,nil,nil,"right")
        assert(not EntityGetIsAlive(syringe))
    end
    for _,effect in pairs(effects) do assert(EntityGetIsAlive(effect)) end
    local health=EntityAddComponent2(player,"DamageModelComponent",{hp=1,max_hp=5})
    function GetUpdatedEntityID() return effects.healing end
    for tickNo=1,60 do
        dofile("mods/noita_hideout/files/bread_regeneration.lua")
        assert(math.abs(health.hp-(1+0.04*math.floor(tickNo/2)))<1e-8)
    end
    assert(not EntityGetIsAlive(effects.healing))
    print("Controller: four distinct injectors, refresh, concurrent protection and 30 HP per healing dose passed.")
end

local function testLivestockController()
    settings,flags={},{}
    new_world()
    local s=state()
    s.materials={sand=200,water=150}
    s.summons={livestock=100,pending={}} -- First cycle awards a card.
    assert(NHStore.creditGold(s,400) and NHStore.commit(s))
    boot()
    inventory_open=true
    local view=tick()
    assert(not has_project(view.shopGoods,"chick").ready and #view.farm.pens==0)
    tick(nil,"buy_upgrade",{id="livestock",level=0})
    view=tick()
    assert(has_project(view.shopGoods,"chick").pen==1 and has_project(view.shopGoods,"calf").pen==2)
    tick(nil,"shop_buy",{id="chick",pen=1})
    advance(600)
    tick(nil,"shop_buy",{id="calf",pen=2})
    local herds=state().farm.herds
    local adulthood=herds.chick.young[1]
    local calfAdulthood=herds.calf.young[1]
    assert(state().bankGold==40 and calfAdulthood-NHLivestock.species.calf.growth>=600)
    local young=tick().farm.pens[1]
    assert(young.juveniles==1 and young.adults==0 and young.count==1 and young.capacity==2)
    local juveniles=advance(adulthood-NHFarm.observe(state(),frame)-1).farm.produce
    for _,product in ipairs(juveniles) do assert(product.perMinute==0) end
    local firstAdult=tick().farm.produce
    assert(firstAdult[1].perMinute==1 and firstAdult[2].perMinute==0 and firstAdult[3].perMinute==0.5)
    assert(firstAdult[1].stock==0 and firstAdult[3].stock==0,"maturity updates rates before the first deposit")
    entities[player].x=227+81
    inventory_open=false
    tick()
    advance(calfAdulthood-NHFarm.observe(state(),frame))
    assert(state().resources.egg==2 and state().resources.meat==1 and not state().resources.milk)
    assert(#state().warehouse==1 and state().warehouse[1].item.kind=="summon_card")
    entities[player].x=227
    inventory_open=true
    local adult=tick().farm.pens[1]
    assert(adult.adults==1 and adult.juveniles==0 and adult.remaining>0)
    local combined=tick().farm.produce
    assert(math.abs(combined[2].perMinute-2/3)<1e-9 and math.abs(combined[3].perMinute-7/6)<1e-9)
    assert(tick().status:find("Summon cards",1,true))
    local longTrip=5*NHLivestock.species.chick.period
    advance(longTrip)
    assert(state().resources.egg==12 and state().resources.milk==6 and state().resources.meat==12)
    boot()
    local farm=tick().farm
    assert(farm.produce[1].stock==12 and farm.pens[1].remaining>0 and farm.pens[2].remaining>0)
end
testLivestockController()
print("Controller: pens, staggered maturity, passive produce and card deposits, long trips and reload passed.")

local function testSpecialLivestock()
    settings,flags={},{}
    new_world()
    local s=state()
    s.resources={fiber=12,sugar=8}
    s.materials={slime=75,sandstone=400,gunpowder=100,oil=150}
    assert(NHStore.creditGold(s,3480) and NHStore.commit(s))
    boot()
    inventory_open=true
    local view=tick()
    assert(not has_project(view.shopGoods,"queen_bee").ready and not has_project(view.shopGoods,"dragon_egg").ready)
    tick(nil,"buy_upgrade",{id="beehive",level=0})
    tick(nil,"buy_upgrade",{id="dragon_nest",level=0})
    local bee=assert(has_project(tick().shopGoods,"queen_bee"))
    local egg=assert(has_project(tick().shopGoods,"dragon_egg"))
    assert(bee.ready and egg.ready and bee.price==480 and egg.price==3000)
    tick(nil,"shop_buy",{id=bee.id,pen=bee.pen})
    tick(nil,"shop_buy",{id=egg.id,pen=egg.pen})
    assert(state().bankGold==0 and #tick().farm.pens==2)
    local firstTreasure=state().farm.herds.dragon_egg.young[1]+NHLivestock.species.dragon_egg.period
    inventory_open=false
    entities[player].x=400
    advance(firstTreasure-1-NHFarm.observe(state(),frame))
    assert(state().bankGold==0 and state().resources.sugar==20 and state().resources.spice==8)
    tick()
    s=state()
    assert(s.bankGold==150 and #s.warehouse+NHDragonLoot.pendingCount(s)>=1)
    assert(s.farm.herds.dragon_egg.adults==1 and s.farm.herds.dragon_egg.progress==0)
    local treasureSeed=s.dragonLoot.seed
    boot()
    tick()
    assert(state().bankGold==150 and state().dragonLoot.seed==treasureSeed)
end
testSpecialLivestock()

local function testGelPoolProduction()
    settings,flags={},{}
    new_world()
    local s=state()
    s.materials={slime=250,water=150,soil=60,soil_lush=40}
    s.levels.farmland=1
    s.farm.plots[1]={token=1,crop="grain",readyAt=NHFarm.crops.grain.frames}
    assert(NHStore.commit(s))
    boot()
    inventory_open=true
    local view=tick()
    assert(has_project(view.progression.expansion,"gel_pool").canBuy)
    advance(210)
    tick(nil,"buy_upgrade",{id="gel_pool",level=0})
    s=state()
    local first=s.farm.time+240*60
    assert(s.farm.time==NHFarm.observe(s,frame) and s.farm.time>=210)
    assert(s.farm.herds.gel_pool.adults==1 and s.farm.herds.gel_pool.progress==0)
    assert(not next(s.materials) and not s.resources.herb and not s.resources.fiber)
    -- Both independent rolls win at the first deadline.
    s.gelBonus={seed=100,pending={}}
    s.summons={gel_pool=100,pending={}}
    assert(NHStore.commit(s))
    boot()
    inventory_open=false
    entities[player].x=400
    advance(first-NHFarm.observe(s,frame)-1)
    assert(not state().resources.herb and not state().resources.spice)
    tick()
    s=state()
    assert(s.resources.herb==4 and s.resources.fiber==6 and s.resources.spice==1)
    local dose,card
    for _,row in ipairs(s.warehouse) do
        if row.item.kind=="dose" then dose=row end
        if row.item.species=="slime" then card=row end
    end
    assert(dose and dose.item.remaining==3 and card and card.item.remaining==80)
    boot()
    entities[player].x=227
    inventory_open=true
    tick()
    assert(state().resources.spice==1 and state().farm.herds.gel_pool.progress==0)
    local pouch=starter()
    tick(nil,"open_container",{pouchId=pouch.id,safeSlot=pouch.slot,container="safe"})
    tick(nil,"pack_dose",{pouchId=pouch.id,container="warehouse",safeSlot=dose.slot,targetCell=4})
    local cell=assert(starter().cells[4])
    assert(cell.remaining==3 and (cell.subtype or "fire")==dose.item.subtype)
    tick(nil,"use_inventory",{container="pouch",pouchId=pouch.id,cell=4,kind="dose",
        count=1,remaining=3,subtype=dose.item.subtype})
    assert(starter().cells[4].remaining==2)
end
testGelPoolProduction()

do
    settings,flags={},{}
    new_world()
    local s=state()
    s.materials={slime=1500,water=900,soil=600}
    assert(NHStore.creditGold(s,2000) and NHStore.commit(s))
    boot()
    inventory_open=true
    tick()
    tick(nil,"buy_upgrade",{id="gel_pool",level=0})
    local start=state().farm.time
    local function view()
        return tick().farm.pens[1]
    end
    local function offer()
        return assert(has_project(tick().shopGoods,"gel_pool"))
    end
    local function buy(quoted)
        return tick(nil,"shop_buy",{id=quoted.id,pen=quoted.pen})
    end
    local pool=view()
    assert(pool.count==1 and pool.adults==1 and pool.capacity==2 and pool.effectivePeriod==240)
    advance(1200)
    local offer1=offer()
    assert(offer1.price==320 and offer1.ready)
    buy(offer1)
    buy(offer1)
    assert(state().bankGold==1680 and not offer().ready)
    pool=view()
    assert(pool.juveniles==1 and pool.adults==1 and pool.count==2 and pool.effectivePeriod==240)
    tick(nil,"buy_upgrade",{id="gel_pool",level=1})
    pool=view()
    assert(pool.capacity==4 and pool.count==2)
    buy(offer1)
    assert(state().bankGold==1680 and view().count==2)
    local mature=state().farm.herds.gel_pool.young[1]
    -- Only the resident works before maturity. Both finish the leftover work together.
    local first=mature+math.ceil((240*60-(mature-start))/2)
    advance(mature-NHFarm.observe(state(),frame))
    pool=view()
    assert(pool.adults==2 and pool.juveniles==0 and pool.effectivePeriod==120)
    assert(pool.remaining==math.ceil((first-NHFarm.observe(state(),frame))/60))
    entities[player].x=400
    inventory_open=false
    advance(first-NHFarm.observe(state(),frame)-1)
    assert(not state().resources.herb)
    tick()
    assert(state().resources.herb==4 and state().resources.fiber==6)
    boot()
    advance(120*60)
    assert(state().resources.herb==8 and state().resources.fiber==12)
    entities[player].x=227
    inventory_open=true
    tick()
    tick(nil,"buy_upgrade",{id="gel_pool",level=2})
    assert(view().capacity==6 and view().count==2)
    for _=1,4 do buy(offer()) end
    pool=view()
    assert(pool.count==6 and pool.adults==2 and pool.juveniles==4 and not offer().ready)
    local last=state().farm.herds.gel_pool.young[4]
    advance(last-NHFarm.observe(state(),frame))
    pool=view()
    assert(pool.adults==6 and pool.effectivePeriod==40 and state().bankGold==400)
end

local function testCardSupplies()
    settings,flags={},{}
    new_world()
    inventory_open=true
    settings["noita_hideout.test_tools"]=false
    tick()
    tick(nil,"test_cards")
    tick(nil,"test_wallet")
    settings["noita_hideout.test_tools"]=true
    entities[player].x=400
    tick(nil,"test_cards")
    tick(nil,"test_wallet")
    entities[player].x=227
    assert(#state().warehouse==0)
    fail_commit=true
    tick(nil,"test_cards")
    fail_commit=false
    boot()
    tick()
    assert(#state().warehouse==0)
    tick(nil,"test_cards")
    tick(nil,"test_cards")
    tick(nil,"test_wallet")
    local view=tick()
    local seen={}
    for _,card in pairs(view.warehouse.collection) do
        assert(card.kind=="summon_card" and card.remaining==80 and card.count==2 and not seen[card.species],
            ("grant showed %s, durability %s, count %s"):format(tostring(card.species),tostring(card.remaining),tostring(card.count)))
        seen[card.species]=true
    end
    for _,species in ipairs(NHCompanions.order) do assert(seen[species]) end
    assert(view.warehouse.equipment[1].kind=="card_wallet")
    assert(seen.slime and #state().warehouse==#NHCompanions.order+1 and view.warehouse_capacity.collection==48)
    boot()
    assert(#state().warehouse==#NHCompanions.order+1)
    tick()
    local lastPet
    for _,species in ipairs({"bee","dragon","slime"}) do
        local row
        for _,item in ipairs(state().warehouse) do
            if item.item.species==species then row=item; break end
        end
        tick(nil,"use_inventory",{container="warehouse",kind="summon_card",species=species,storedId=row.id,
            slot=row.slot,count=2,remaining=80})
        local pets=EntityGetAllChildren(player,"noita_hideout_companion")
        assert(#pets==1 and (not lastPet or not EntityGetIsAlive(lastPet)))
        local clock=EntityGetFirstComponentIncludingDisabled(pets[1],"VariableStorageComponent","nh_companion_clock")
        assert(ComponentGetValue2(clock,"value_string")==species)
        local full,worn=0,0
        for _,entry in ipairs(state().warehouse) do
            if entry.item.species==species then
                if entry.item.remaining==79 then worn=worn+1 end
                if entry.item.remaining==80 then full=full+1 end
            end
        end
        assert(full==1 and worn==1)
        lastPet=pets[1]
    end
end
testCardSupplies()
print("Controller: test-only supplies, failed delivery, all companion card stacks and card wallet passed.")

local function testCompanionSwitch()
    settings,flags={},{}
    new_world()
    inventory_open=true
    tick()
    tick(nil,"test_cards")
    local collection=tick().warehouse.collection
    for slot=2,4 do
        tick(nil,"secure_withdraw",{container="warehouse",kind="summon_card",storedId=collection[slot].id,
            safeSlot=slot,lane="tool",parent=quick,xslot=slot-1,yslot=0})
    end
    local cards={}
    for _,slot in ipairs(tick().native_slots) do
        if slot.kind=="summon_card" then cards[slot.species]=slot.entity end
    end
    local function summoned(species)
        local pets=EntityGetAllChildren(player,"noita_hideout_companion")
        assert(#pets==1)
        local clock=EntityGetFirstComponentIncludingDisabled(pets[1],"VariableStorageComponent","nh_companion_clock")
        assert(ComponentGetValue2(clock,"value_string")==species)
        local _,_,_,sx,sy=EntityGetTransform(pets[1])
        assert(sx==0.5 and sy==0.5)
        local _,_,_,playerScaleX,playerScaleY=EntityGetTransform(player)
        assert(playerScaleX==1 and playerScaleY==1)
        return pets[1]
    end
    local function remaining(species) return NHCompanions.captureCard(cards[species]).remaining end
    local first,second="minotaur","flower_fairy"
    inventory_open=false
    tick()
    tick()
    held=assert(cards[first])
    tick(nil,nil,nil,"right")
    local original=summoned(first)
    tick(nil,nil,nil,"right")
    assert(summoned(first)==original and remaining(first)==79)
    tick()
    held=assert(cards[second])
    tick(nil,nil,nil,"right")
    local replacement=summoned(second)
    assert(not EntityGetIsAlive(original) and remaining(first)==79 and remaining(second)==79)
    tick()
    tick(nil,nil,nil,"right")
    assert(summoned(second)~=replacement and not EntityGetIsAlive(replacement) and remaining(second)==78)
    tick()
    held=assert(cards.griffin)
    tick(nil,nil,nil,"right")
    assert(summoned("griffin") and remaining("griffin")==79 and remaining(second)==78)
end
testCompanionSwitch()
print("Controller: test cards reach the quickbar and each fresh use switches companions for one charge.")

local function testCardWalletController()
    settings,flags={},{}
    new_world()
    inventory_open=true
    tick()
    tick(nil,"test_wallet")
    tick(nil,"test_cards")
    tick(nil,"test_cards")
    local view=tick()
    local wallet=view.warehouse.equipment[1].id
    local card=view.warehouse.collection[1]
    tick(nil,"open_container",{kind="card_wallet",walletId=wallet,container="warehouse",safeSlot=1})
    assert(tick().walletId==wallet)
    tick(nil,"move_wallet_card",{walletId=wallet,from=1,entity=card.id,targetCell=3,container="warehouse"})
    view=tick()
    assert(view.cells[3].species==card.species and (view.warehouse.collection[1].count or 1)==1)
    tick(nil,"move_wallet",{source="warehouse",from=1,entity=wallet,destination="safe",safeSlot=1})
    view=tick()
    assert(view.walletId==wallet and view.secure_loot[1].kind=="card_wallet")
    local function tool(i)
        return {lane="tool",parent=quick,xslot=i,yslot=0}
    end
    local take=tool(0)
    take.container,take.storedId,take.kind,take.safeSlot="safe",wallet,"card_wallet",1
    tick(nil,"secure_withdraw",take)
    view=tick()
    local carried=view.native_slots[5]
    for _,slot in ipairs(view.native_slots) do if slot.walletId==wallet then carried=slot end end
    assert(carried.kind=="card_wallet" and carried.walletId==wallet and not view.popup)
    held=carried.entity
    inventory_open=false
    tick()
    tick()
    tick(nil,nil,nil,"right")
    view=tick()
    assert(view.mode=="container" and view.walletId==wallet and view.cells[3].species==card.species)
    local out=tool(1)
    out.walletId,out.sourceCell,out.remaining,out.species=wallet,3,80,card.species
    tick(nil,"take_card",out)
    view=tick()
    assert(not view.cells[3])
    local loose
    for _,slot in ipairs(view.native_slots) do if slot.kind=="summon_card" then loose=slot end end
    assert(loose and loose.species==card.species and loose.remaining==80 and loose.xslot==1)
    ComponentSetValue2(EntityGetFirstComponentIncludingDisabled(loose.entity,"ItemComponent"),"uses_remaining",79)
    local back=tool(1)
    back.entity,back.walletId,back.targetCell=loose.entity,wallet,2
    tick(nil,"place",back)
    view=tick()
    assert(view.cells[2].remaining==79 and not EntityGetIsAlive(loose.entity))
    boot()
    inventory_open=true
    tick()
    tick(nil,"open_container",{kind="card_wallet",walletId=wallet,entity=held})
    assert(tick().cells[2].remaining==79)
end
testCardWalletController()
print("Controller: open and carry a loaded wallet, transfer a worn card in the field and continue the game.")

local function testCompanionAffinity()
    settings,flags={},{}
    new_world()
    for _=1,59 do NHAffinity.follow("dryad",6) end
    advance(360-frame%360)
    assert(state().affinity.dryad==354)
    assert(NHAffinity.follow("dryad",6)==1)
    NHAffinity.follow("griffin",6)
    boot()
    assert(NHAffinity.points(state(),"dryad")==1)
    local revision=state().revision
    OnPausedChanged(true,true)
    OnPausedChanged(false,false)
    assert(state().revision==revision)
    OnPausedChanged(true,false)
    assert(state().affinity.dryad==360 and state().affinity.griffin==6)
    OnPausedChanged(true,false)
    assert(state().revision==revision+1)
    new_world()
    assert(state().runSerial==2 and NHAffinity.points(state(),"dryad")==1)
    NHAffinity.follow("griffin",6)
    OnPlayerDied()
    assert(state().affinity.griffin==12)
    new_world()
    assert(NHAffinity.points(state(),"dryad")==1)
    for _=1,58 do NHAffinity.follow("griffin",6) end
    assert(NHAffinity.points(state(),"griffin")==1)
end
testCompanionAffinity()
print("Controller: affinity checkpoints, pause and new game, continue and death retain each companion's exact progress.")

local function testSpellWorkshopController()
    settings,flags={},{}
    new_world()
    local saved=state()
    saved.levels.salvage=1
    saved.resources={essence_healing=175,essence_lightning=1000}
    assert(NHStore.commit(saved))
    boot()
    inventory_open=true
    local view=tick()
    assert(#view.spellFamilies==17)
    local healing=assert(has_project(view.spellRecipes.essence_healing,"spell_HEAL_BULLET"))
    assert(healing.ready and healing.actionId=="HEAL_BULLET" and healing.inputs[1].essence=="essence_healing")
    assert(healing.inputs[1].amount==175 and healing.inputs[1].available==175)
    assert(has_project(view.spellRecipes.essence_healing,"spell_REGENERATION_FIELD").spellType=="static_projectile")
    local cloud="spell_CLOUD_THUNDER"
    assert(not has_project(view.spellRecipes.essence_lightning,cloud).unlocked)
    inventory_open=false
    tick()
    AddFlagPersistent("card_unlocked_cloud_thunder")
    inventory_open=true
    assert(has_project(tick().spellRecipes.essence_lightning,cloud).ready)
    tick(nil,"craft",{id=healing.id})
    local order=state().order
    assert(order and not state().resources.essence_healing and tick().warehouse.spell[order.output.slot].kind=="reserved")
    boot()
    tick()
    advance(order.required)
    local card=tick().warehouse.spell[order.output.slot]
    assert(card.spell_uses==20 and card.essence.amount==175 and state().finished==1)
    tick(nil,"salvage",{id=card.id,kind="spell",slot=order.output.slot,mode="essence"})
    assert(state().resources.essence_healing==175 and #state().warehouse==0)
end
testSpellWorkshopController()
print("Controller: native discovery refresh, spell reservations, full-charge delivery and exact essence refund passed.")

local function testTieredMedkits()
    settings,flags={},{}
    new_world()
    local saved=state()
    saved.levels.medical=1
    saved.resources={essence_healing=5,herb=12}
    for slot=1,2 do
        local item=NHMedkits.item("medkit")
        item.remaining=slot==2 and 1 or nil
        saved.warehouse[slot]={id=saved.nextItemId,slot=slot,item=item}
        saved.nextItemId=saved.nextItemId+1
    end
    assert(NHStore.commit(saved))
    boot()
    inventory_open=true
    local function checkRecipe(id,duration,uses,percent,need,herbs,ingredient,count)
        local recipe=assert(has_project(tick().recipes,id))
        assert(recipe.ready and recipe.category=="medical" and recipe.duration==duration)
        assert(recipe.medkit.uses==uses and recipe.medkit.healPercent==percent)
        assert(recipe.inputs[1].essence=="essence_healing" and recipe.inputs[1].amount==need)
        assert(recipe.inputs[2].amount==herbs)
        local input=recipe.inputs[3]
        assert(input.name==ingredient and input.available==count and input.amount==1)
        assert(input.detail:find("fewest charges",1,true))
    end
    checkRecipe("tactical_medkit",60,9,15,2,4,"Medkit (1/3)",2)
    tick(nil,"craft",{id="tactical_medkit"})
    local order=state().order
    assert(order.required==3600 and state().resources.essence_healing==3 and state().resources.herb==8)
    assert(tick().warehouse.supplies[1].remaining==3 and tick().warehouse.supplies[order.output.slot].kind=="reserved")
    advance(order.required)
    local built=state()
    local tactical=assert(tick().warehouse.supplies[order.output.slot])
    assert(tactical.kind=="tactical_medkit" and tactical.remaining==9)
    for _,row in ipairs(built.warehouse) do
        if row.id==tactical.id then row.item.remaining=7 end
    end
    assert(NHStore.commit(built))
    boot()
    checkRecipe("advanced_medkit",180,12,25,3,8,"Tactical medkit (7/9)",1)
    tick(nil,"craft",{id="advanced_medkit"})
    order=state().order
    assert(order.required==10800 and not state().resources.essence_healing and not state().resources.herb)
    boot()
    local reserved=tick().warehouse.supplies[order.output.slot]
    assert(reserved.kind=="reserved")
    advance(order.required)
    local advanced=tick().warehouse.supplies[order.output.slot]
    assert(advanced.kind=="advanced_medkit" and advanced.remaining==12 and state().finished==2)
end
testTieredMedkits()
print("Controller: worn kits upgrade for fixed prices and both higher tiers arrive with full charges.")

local function testSurgeryFromWorkshop()
    settings,flags={},{}
    new_world()
    local saved=state()
    saved.levels.medical=1
    saved.resources={herb=3,essence_healing=2}
    local base=NHMedkits.item("medkit")
    base.remaining=1
    saved.warehouse={{id=saved.nextItemId,slot=1,item=base}}
    saved.nextItemId=saved.nextItemId+1
    assert(NHStore.commit(saved))
    boot()
    inventory_open=true
    local recipe=assert(has_project(tick().recipes,"field_surgery_kit"))
    assert(recipe.ready and recipe.medkit.castFrames==180 and recipe.medkit.healPercent==20)
    tick(nil,"craft",{id=recipe.id})
    local built=advance(state().order.required).warehouse.supplies[1]
    assert(built.kind==recipe.id and built.remaining==1)
    tick(nil,"secure_withdraw",{container="warehouse",kind=built.kind,storedId=built.id,safeSlot=1,
        parent=quick,lane="tool",xslot=1,yslot=0})
    for _,slot in ipairs(tick().native_slots) do
        if slot.kind==built.kind then held=slot.entity end
    end
    assert(EntityHasTag(held,"noita_hideout_field_surgery_kit"))
    inventory_open=false
    tick()
    tick()
    function EntityGetFirstComponent(id,kind,tag)
        local c=EntityGetFirstComponentIncludingDisabled(id,kind,tag)
        if c and not c.disabled then return c end
    end
    function EntityGetTags(id)
        local list={}
        for tag in pairs(entities[id].tags) do list[#list+1]=tag end
        return table.concat(list,",")
    end
    function EntityGetFilename(id) return entities[id].file or "" end
    function ComponentGetTags(c) return c._tags or "" end
    function ComponentGetIsEnabled(c) return not c.disabled end
    function GameGetGameEffectCount() return 0 end
    local health=EntityAddComponent2(player,"DamageModelComponent",{hp=1,max_hp=40,mIsOnFire=true,mFireFramesLeft=200})
    local food=EntityLoad("mods/noita_hideout/files/effect_sugar_cube.xml",0,0)
    EntityAddChild(player,food)
    local buff=EntityAddComponent2(food,"GameEffectComponent",{effect="MOVEMENT_FASTER",frames=7200})
    local status=tick(nil,nil,nil,"right").surgery
    assert(status and status.total==180 and status.elapsed==0)
    assert(advance(100).surgery.elapsed==100)
    health.hp=0.9
    assert(not tick().surgery and EntityGetIsAlive(held) and health.mIsOnFire and buff.frames==7200)
    assert(tick(nil,nil,nil,"right").surgery.elapsed==0)
    assert(advance(179).surgery.elapsed==179 and health.hp==0.9)
    local kit=held
    assert(not tick().surgery and not EntityGetIsAlive(kit) and health.hp==8.9)
    assert(not health.mIsOnFire and health.mFireFramesLeft==0 and EntityGetIsAlive(food) and buff.frames==7200)
end
testSurgeryFromWorkshop()
print("Controller: craft, withdraw, interrupt and complete surgery through the normal game callbacks.")

local function testInventoryRightClick()
    settings,flags={},{}
    new_world()
    local saved=state()
    local function stock(container,slot,kind,count,remaining)
        local id=saved.nextItemId
        saved.nextItemId=id+1
        table.insert(saved[container],{slot=slot,id=id,item={kind=kind,count=count,remaining=remaining}})
        return {container=container,slot=slot,storedId=id,kind=kind,count=count,remaining=remaining}
    end
    local bandage=stock("warehouse",1,"bandage",8)
    local secure=stock("safe",1,"bandage",3)
    local carried=stock("warehouse",2,"medkit",nil,2)
    local kit=stock("warehouse",3,"field_surgery_kit",nil,1)
    local grenade=stock("warehouse",4,"fire_grenade",8)
    local movedKit=stock("warehouse",5,"field_surgery_kit",nil,1)
    local function stored(ref)
        local s=state()
        local index=NHStore.slotIndex(s,ref.container,ref.slot,ref.kind)
        return index and s[ref.container][index].item
    end
    local function right(ref)
        tick()
        tick(nil,"use_inventory",ref,"right")
    end
    local function withdraw(ref,xslot)
        tick(nil,"secure_withdraw",{container=ref.container,kind=ref.kind,storedId=ref.storedId,safeSlot=ref.slot,
            parent=quick,lane="tool",xslot=xslot,yslot=0})
        for _,slot in ipairs(tick().native_slots) do
            if slot.kind==ref.kind and slot.xslot==xslot then
                slot.container="native"
                return slot
            end
        end
        error("Failed to withdraw "..ref.kind)
    end
    assert(NHStore.commit(saved))
    boot()
    local health=EntityAddComponent2(player,"DamageModelComponent",{hp=40,max_hp=40})
    inventory_open=true
    right(bandage)
    assert(health.hp==40 and stored(bandage).count==8)
    health.hp=1
    fail_commit=true
    right(bandage)
    fail_commit=false
    assert(health.hp==1 and stored(bandage).count==8)
    advance(61)
    right(bandage)
    assert(health.hp==1.2 and stored(bandage).count==7)
    right(bandage) -- The HUD still describes the eight-roll stack.
    assert(health.hp==1.2 and stored(bandage).count==7)
    right(secure)
    assert(health.hp==1.4 and stored(secure).count==2)

    local native=withdraw(carried,1)
    local unused=EntityLoad("dummy.xml",227,-85)
    EntityAddChild(quick,unused)
    held=unused
    health.hp=1
    right(native)
    local charges=EntityGetFirstComponentIncludingDisabled(native.entity,"ItemComponent")
    assert(health.hp==1.4 and charges.uses_remaining==1 and held==unused)
    ComponentSetValue2(charges,"inventory_slot",2,0)
    right(native)
    assert(health.hp==1.4 and charges.uses_remaining==1 and held==unused)

    right(kit)
    assert(tick().surgery and stored(kit).remaining==1)
    EntitySetTransform(player,1000,-85)
    assert(not tick().surgery and stored(kit).remaining==1 and health.hp==1.4)
    EntitySetTransform(player,227,-85)
    right(kit)
    assert(advance(179).surgery.elapsed==179 and health.hp==1.4)
    assert(not tick().surgery and not stored(kit) and health.hp==9.4 and held==unused)
    right(movedKit)
    assert(tick().surgery)
    local movedNative=withdraw(movedKit,1)
    assert(not tick().surgery and not stored(movedKit) and health.hp==9.4)
    assert(EntityGetFirstComponentIncludingDisabled(movedNative.entity,"ItemComponent").uses_remaining==1)

    local oldValue,oldLoad,oldShoot=ComponentGetValue2,EntityLoad,GameShootProjectile
    local ax,ay,shots,shotEntity=-3,4,0,nil
    function ComponentGetValue2(component,key)
        if component==controls and key=="mAimingVectorNormalized" then return ax,ay end
        return oldValue(component,key)
    end
    function EntityLoad(path,x,y)
        local entity=oldLoad(path,x,y)
        if path==NHThrowables.types.fire_grenade.projectile then
            EntityAddComponent2(entity,"ProjectileComponent",{})
            EntityAddComponent2(entity,"VelocityComponent",{})
            shotEntity=entity
        end
        return entity
    end
    function GameShootProjectile(shooter,x,y,targetX,targetY,entity)
        assert(shooter==player and entity==shotEntity)
        assert(math.abs(targetX-x+108)<0.001 and math.abs(targetY-y-144)<0.001)
        shots=shots+1
    end
    inventory_open=false
    tick()
    tick()
    inventory_open=true
    ax,ay=1,0
    fail_commit=true
    right(grenade)
    fail_commit=false
    assert(shotEntity and not EntityGetIsAlive(shotEntity) and shots==0 and stored(grenade).count==8)
    advance(61)
    right(grenade)
    assert(shots==1 and stored(grenade).count==7 and held==unused)
    ComponentGetValue2,EntityLoad,GameShootProjectile=oldValue,oldLoad,oldShoot
end
testInventoryRightClick()
print("Controller: right-click uses the exact stored or carried item, respects payment, and retains world aim.")
