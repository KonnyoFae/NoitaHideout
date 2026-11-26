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
function GameSetPostFxParameter() end
function GlobalsSetValue(k,v) world[k] = v end
function GameGetFrameNum() return frame end
function SessionNumbersGetValue() return "0" end
-- The weather cycle and its HUD are exercised in storm_rain_spec.
function GameIsIntroPlaying() return true end
function GameTextGet() return "English" end
function GameTextGetTranslatedOrNot(k) return k end
function CellFactory_GetType() return -1 end
function ModTextFileGetContent() return nil end
function GamePrint() end
function GamePlaySound() end
local rain_preload_calls=0
function GameEntityPlaySoundLoop(id,tag,intensity)
    assert(id~=player and intensity==0 and EntityGetFirstComponentIncludingDisabled(id,"AudioLoopComponent",tag))
    rain_preload_calls=rain_preload_calls+1
end
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
function LoadPixelScene(mask)
    assert(mask=="mods/noita_hideout/files/terminals/shelter_materials.png"
        or mask=="mods/noita_hideout/files/travel/cabin_materials.png")
end
function RaytraceSurfaces() return false end
function RaytracePlatforms(x,y,tx,ty)
    if y < -26000 and tx==x then
        local cabin=dofile("mods/noita_hideout/files/travel/cabin.lua")
        for _,offset in ipairs({60,144}) do
            local floor=cabin.top+offset
            if y<=floor and ty>=floor then return true,x,floor end
        end
    end
    if tx==x and ty-y==48 then return true,x,y+18 end
    if tx==x and ty-y==5 then return true,x,y+2 end
    return false
end
function RaytraceSurfacesAndLiquiform() return false end
function EntityRefreshSprite() end
function ComponentObjectSetValue2(c,k,m,v) c[k]=c[k] or {}; c[k][m]=v end
function EntityHasTag(id,tag) return entities[id] ~= nil and entities[id].tags[tag] == true end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityRemoveTag(id,tag) entities[id].tags[tag]=nil end
function EntityCreateNew(name)
    next_id=next_id+1
    entities[next_id]={name=name,x=0,y=0,parent=0,tags={},comps={}}
    return next_id
end
function EntityGetIsAlive(id) return entities[id] ~= nil end
function EntityGetParent(id) return entities[id].parent end
function EntityRemoveFromParent(id) entities[id].parent=0 end
function EntityGetName(id) return entities[id].name or "" end
function EntityGetFilename(id) return entities[id].file or "" end
function EntityGetTags(id)
    local list={}
    for tag in pairs(entities[id].tags) do list[#list+1]=tag end
    return table.concat(list,",")
end
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
    for _,area in pairs(entities) do
        if area.biome and math.abs(x-area.x)<=120 and math.abs(y-area.y)<=120 then return area.biome end
    end
    return "$biome_coalmine"
end
function BiomeMapGetSize() return 70,48 end
function GetParallelWorldPosition(x) return math.floor(x/(BiomeMapGetSize()*512)+0.5),0 end
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
function ComponentHasTag(c,tag) return c.tags and c.tags[tag] or false end
function ComponentAddTag(c,tag) c.tags=c.tags or {}; c.tags[tag]=true end
function ComponentRemoveTag(c,tag) c.tags[tag]=nil end
function EntitySetComponentIsEnabled(_,c,enabled) c.disabled=not enabled end
function ComponentGetIsEnabled(c) return not c.disabled end
function ComponentSetValue2(c,key,v,y)
    if key=="inventory_slot" then c.slotX,c.slotY=v,y else c[key]=v end
end
function EntitySetComponentsWithTagEnabled() end
function EntityLoad(path,x,y)
    local file=path:match("([^/]+)%.xml$")
    if file:match("^stimulant") and fail_effect then return 0 end
    next_id=next_id+1
    entities[next_id]={x=x,y=y,parent=0,tags={["noita_hideout_"..file]=true},comps={}}
    if file=="station" then EntityAddTag(next_id,"nh_home_terminal") end
    if file=="console" then EntityAddTag(next_id,"nh_travel_console") end
    if file=="gate" then EntityAddTag(next_id,"nh_travel_gate") end
    if file=="transit_protection" then EntityAddTag(next_id,"nh_transit_protection") end
    if file=="remote" then
        EntityAddTag(next_id,"nh_remote_station")
        EntityAddComponent2(next_id,"VariableStorageComponent",{_tags="nh_remote_deadline",value_int=0})
    end
    if file=="stimulant_healing" or file=="stimulant_healing_2" or file=="stimulant_regen_mana" then
        EntityAddComponent2(next_id,"VariableStorageComponent",{value_int=60,value_float=file=="stimulant_healing_2" and 1 or 2})
        if file=="stimulant_regen_mana" then EntityAddComponent2(next_id,"GameEffectComponent",{effect="MANA_REGENERATION",frames=-1}) end
    elseif file:match("^stimulant") then EntityAddComponent2(next_id,"GameEffectComponent",{frames=3600})
    elseif file:match("^dose_") then
        EntityAddTag(next_id,"noita_hideout_dose")
        EntityAddComponent2(next_id,"ItemComponent",{item_name=file,ui_sprite=file..".png"})
    elseif file:match("^card_wallet") or file:match("^pouch") then
        local kind=file:match("^card_wallet") and "card_wallet" or "pouch"
        EntityAddTag(next_id,"noita_hideout_"..kind)
        EntityAddComponent2(next_id,"ItemComponent",{item_name=file,ui_sprite="mods/noita_hideout/files/items/"..file..".png"})
    elseif file:match("^card_") then
        EntityAddTag(next_id,"noita_hideout_summon_card")
        EntityAddTag(next_id,"nh_companion_"..file:sub(6))
        EntityAddComponent2(next_id,"ItemComponent",{item_name=file,ui_sprite=file..".png",uses_remaining=NHCompanions.cardCapacity(file:sub(6))})
    elseif path:find("/companions/",1,true) and NHCompanions.species[file] then
        EntityAddTag(next_id,"noita_hideout_companion")
        EntityAddComponent2(next_id,"VariableStorageComponent",{_tags="nh_companion_clock",value_string=file,value_int=0})
        for _,tag in ipairs({"nh_gifts","nh_trip","nh_position"}) do
            EntityAddComponent2(next_id,"VariableStorageComponent",{_tags=tag,value_int=0,value_float=0})
        end
    elseif file=="scatter_revolver" or file=="marksman_rifle" or file=="battle_staff" or file=="hunting_bow" then
        local size=({battle_staff=120,hunting_bow=60,scatter_revolver=6,marksman_rifle=10})[file]
        EntityAddTag(next_id,"wand")
        EntityAddTag(next_id,"nh_firearm")
        EntityAddComponent2(next_id,"ItemComponent",{item_name=file,ui_sprite=file..".png"})
        EntityAddComponent2(next_id,"AbilityComponent",{mana=size,use_gun_script=true})
        EntityAddComponent2(next_id,"VariableStorageComponent",{_tags="nh_magazine",name=file,value_int=size,value_string="-1"})
        if file=="battle_staff" then EntityAddComponent2(next_id,"VariableStorageComponent",{_tags="nh_staff_clock",value_int=0}) end
        if file=="hunting_bow" then EntityAddComponent2(next_id,"VariableStorageComponent",{_tags="nh_bow_clock",value_int=0}) end
    elseif file=="tarot_life" or file=="effect_invisibility" or file=="effect_stains_drop_faster" then
        EntityAddComponent2(next_id,"GameEffectComponent",{effect=file=="tarot_life" and "RESPAWN" or file,frames=-1})
    elseif file=="lost_gold_case" then
        EntityAddComponent2(next_id,"VariableStorageComponent",{_tags="nh_lost_gold",value_string=""})
    elseif file:match("ammo_rig$") then
        EntityAddComponent2(next_id,"ItemComponent",{item_name=file,ui_sprite=file..".png"})
        EntityAddComponent2(next_id,"VariableStorageComponent",{_tags="nh_reserve",value_int=0})
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
function GameGetIsGamepadConnected() return false end
function DEBUG_GetMouseWorld() local x,y=EntityGetTransform(player); return x+100,y end
function InputIsKeyJustDown(key) return keys[key] end
function InputIsKeyDown(key) return keys[key] or false end
function InputIsMouseButtonDown(button) return (button==1 and left_mouse) or (button==2 and right_mouse) or false end
function GameHasFlagRun(flag) return flag=="ending_game_completed" and ending end
function dofile_once(path) dofile(path) end
local function boot()
    dofile("mods/noita_hideout/init.lua")
    NHUI.draw=function(m,dispatch)
        model=m
        if opened_click then dispatch(unpack(opened_click)) end
    end
    local previous=rain_preload_calls
    OnWorldInitialized()
    assert(rain_preload_calls==previous+2)
    OnPlayerSpawned(player)
    assert(rain_preload_calls==previous+2)
end
local function tick(key,action,arg,button)
    frame=frame+1
    keys=key and {[key]=true} or {}
    local left=button=="left" or button=="both" or button=="unbound_click"
    local fire=button=="bound_fire" or (left and button~="unbound_click")
    local right=button=="right" or button=="both"
    if fire and not (left_mouse or controls.mButtonDownFire) then controls.mButtonFrameFire=frame end
    if right and not right_mouse then controls.mButtonFrameThrow=frame end
    left_mouse,right_mouse=left,right
    controls.mButtonDownFire,controls.mButtonDownLeftClick=fire,left
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
assert(EntityGetIsAlive(dose) and NHDoses.remaining(state(),dose)==4)
tick()
tick(nil,nil,nil,"right")
assert(NHDoses.remaining(state(),dose)==3)
for left=2,1,-1 do tick(); tick(nil,nil,nil,"right"); assert(NHDoses.remaining(state(),dose)==left) end
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
assert(not state().order and state().finished==1 and state().materials.magic_liquid_teleportation==500)
local revision=tick().revision
advance(120)
assert(tick().revision==revision)
ending=true
tick()
OnPlayerDied()
OnPlayerDied()
assert(not state().order and state().finished==1 and starter().doses==2)
new_world()
inventory_open=true
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

do
    local members,getEnabled,setEnabled=ComponentGetMembers,ComponentGetIsEnabled,EntitySetComponentIsEnabled
    local enabled={}
    function ComponentGetMembers(c) return c end
    function ComponentGetIsEnabled(c) return enabled[c]~=false end
    function EntitySetComponentIsEnabled(_,c,value) enabled[c]=value end
    for _,action in ipairs({"DISC_BULLET","DISC_BULLET_BIG"}) do
        local disc=CreateItemActionEntity(action,200,-80)
        local fx="data/scripts/items/shop_effect.lua"
        EntityAddComponent2(disc,"LuaComponent",{script_item_picked_up=fx,mTimesExecuted=1})
        EntityAddChild(3,disc)
        ComponentSetValue2(EntityGetFirstComponentIncludingDisabled(disc,"ItemComponent"),"inventory_slot",4,0)
        local req={parent=3,lane="spell",xslot=4,yslot=0,entity=disc,safeSlot=1,container="warehouse",kind="spell"}
        tick(nil,"place",req)
        local entry=assert(tick().warehouse.spell[1])
        assert(not EntityGetIsAlive(disc) and state().warehouse[NHStore.slotIndex(state(),"warehouse",1,"spell")].item.card.id==action)
        req.storedId=entry.id
        tick(nil,"secure_withdraw",req)
        assert(not tick().warehouse.spell)
        local copy=assert(EntityGetAllChildren(3)[2])
        assert(ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(copy,"ItemActionComponent"),"action_id")==action)
        assert(ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(copy,"ItemComponent"),"inventory_slot")==4)
        assert(ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(copy,"LuaComponent"),"script_item_picked_up")==fx)
        EntityKill(copy)
    end
    ComponentGetMembers,ComponentGetIsEnabled,EntitySetComponentIsEnabled=members,getEnabled,setEnabled
end
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
local catalogView=tick()
local catalog=catalogView.recipes
assert(#catalog+#NHStormProducts.recipes==#NHStore.recipes)
for _,recipe in ipairs(NHStore.recipes) do
    local menu=recipe.category=="storm_products" and catalogView.shopGoods or catalog
    local entry=assert(has_project(menu,recipe.id),recipe.id)
    if recipe.id:match("^ammo_mod_") then
        assert(entry.icon==recipe.item.icon and recipe.item.kind=="spell",recipe.id)
    elseif recipe.id=="battle_staff" then
        assert(entry.icon=="mods/noita_hideout/files/items/staff_icon.png" and recipe.item.rounds==120)
    elseif recipe.id=="hunting_bow" then
        assert(entry.icon=="mods/noita_hideout/files/items/hunting_bow_icon.png" and recipe.item.rounds==60 and recipe.item.mode==1)
    elseif recipe.item and NHKatanas.types[recipe.item.kind] then
        assert(entry.icon==NHKatanas.types[recipe.item.kind].icon and NHKatanas.valid(recipe.item))
    elseif recipe.category=="weapons" or (recipe.category=="medical" and recipe.item.kind~="dose") then
        assert(entry.icon=="mods/noita_hideout/files/items/"..recipe.item.kind..".png",recipe.id)
    end
    if recipe.category=="alchemy" then
        assert(entry.category=="alchemy" and entry.alchemyMode==recipe.alchemyMode,recipe.id)
        assert(entry.duration==0)
        local extra=recipe.goldCost and 1 or 0
        for _ in pairs(recipe.resources or {}) do extra=extra+1 end
        assert(#entry.inputs==#recipe.inputs+extra and #entry.outputs>0)
        for i,input in ipairs(recipe.inputs) do
            local sources,_,labelEn=NHStore.ingredientSources(input)
            local name=#sources>1 and (labelEn or NHPotion.materialName(input.name)).." (total)" or NHPotion.materialName(input.name,"en")
            assert(entry.inputs[i].name==name and entry.inputs[i].amount==input.amount)
        end
        local shown={}
        for _,output in ipairs(entry.outputs) do shown[output.key]=output.amount end
        for name,amount in pairs(recipe.materials or recipe.resourceYield) do assert(shown[name]==amount,recipe.id) end
    else
        assert(entry.alchemyMode==nil,recipe.id)
    end
end
local alchemy=assert(has_project(catalog,"stable"))
assert(alchemy.category=="alchemy" and alchemy.unlocked and not alchemy.ready and alchemy.reason)
local reverse=assert(has_project(catalog,"reverse_stable"))
assert(reverse.category=="alchemy" and reverse.unlocked and #reverse.inputs==1 and #reverse.outputs==2)
local expected_category={medical="medical",injector="medical",injector_lightning="medical",injector_frost="medical",injector_healing="medical",
    grenade="weapons",grenade_essence="weapons",pouch="containers"}
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
    {recipe="grenade",kind="magic_tube",name="Cement launcher",ingredients={sand=64,slime=32}},
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
    local delivered=state()
    assert(not delivered.order and delivered.finished==n and #delivered.warehouse==n)
    local reserved=delivered.warehouse[n].slot
    for input,amount in pairs(expected.ingredients) do
        local stock=expected.stock or "materials"
        assert((delivered[stock][input] or 0)==before[stock][input]-amount)
    end
    -- Delivery is already committed; loading must never award another copy.
    boot()
    tick()
    assert(state().finished==n and #state().warehouse==n)
    local crafted=assert(tick().warehouse.supplies[reserved])
    assert(crafted.kind==expected.kind)
    if n<3 then assert(crafted.remaining==(n==1 and 8 or 5)) end
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
assert(not tick().perkCapacity)
tick(nil,"buy_upgrade",{id="perk_pack",level=0})
assert(not state().levels.perk_pack and state().resources.arcane_scrap==1)
NHPerks.enabled=true -- retain integration coverage for the dormant perk bar
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
local second_id=NHPouches.create(pair,"warehouse",1,0,3)
assert(NHStore.commit(pair))
boot()
local both=tick()
assert(both.secure_loot[first_pouch.slot].id==first_id and both.warehouse.equipment[1].id==second_id)
assert(both.warehouse.equipment[1].icon==NHEquipment.get("pouch",3).icon and both.warehouse.equipment[1].capacity==12)
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
assert(second_view.pouchId==second_id and second_view.pouchCapacity==12 and not next(second_view.cells))
tick(nil,"place",tool(injector)) -- stale target, retained in quick inventory
assert(EntityGetIsAlive(injector) and state().pouches[second_id].doses==0)
local insert=tool(injector)
insert.pouchId,insert.targetCell=second_id,12
tick(nil,"place",insert)
assert(not EntityGetIsAlive(injector) and tick().cells[12].remaining==2)
tick(nil,"open_container",open_first)
local first_view=tick()
assert(first_view.pouchId==first_id and first_view.pouchCapacity==4 and first_view.cells[2].remaining==3 and not first_view.cells[12])
tick(nil,"open_container",{pouchId=second_id,safeSlot=first_pouch.slot})
assert(tick().pouchId==first_id) -- stale record cannot open a new occupant of that slot
boot()
tick()
tick(nil,"open_container",open_second)
assert(tick().cells[12].remaining==2 and state().pouches[first_id].doses==1)
local to_case={pouchId=second_id,container="warehouse",source="warehouse",destination="safe",from=1,safeSlot=1}
tick(nil,"move_pouch",to_case)
local after_move=tick()
assert(after_move.secure_loot[1].id==second_id and after_move.pouchId==second_id and after_move.cells[12].remaining==2)
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
assert(returned.warehouse.equipment[2].id==second_id and returned.pouchId==second_id and returned.cells[12].remaining==2)
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
assert(not state().order and state().finished==1)
stand(1000,2048)
assert(receipts()==1)
stand(1000,4096)
assert(receipts()==2)
stand(1000,3600)
stand(1000,4096)
assert(receipts()==2)
boot()
stand(1000,4096)
assert(receipts()==2)
stand(1000,6144)
local complete_batch=state()
assert(receipts()==3 and not complete_batch.order and complete_batch.finished==1)
assert(complete_batch.materials.honey==50 and complete_batch.materials.diamond==50)
stand(227,-85)
tick(nil,"craft",{id="ambrosia"})
assert(not state().order and state().finished==2)
entities[player].tags.player_unit=nil
tick()
advance(2*NHStore.productionFrames())
assert(not state().order and state().finished==2)
entities[player].tags.player_unit=true
local poly=EntityLoad("polymorph.xml",227,-85)
EntityAddTag(poly,"polymorphed_player")
entities[player].tags.player_unit=nil
tick()
mountain(1000,8192,holy)
entities[poly].x,entities[poly].y=1000,8192
for i=1,11 do tick() end
assert(receipts()==4 and not state().order)
EntityKill(poly)
entities[player].tags.player_unit=true
assert(not tick().order_active and state().finished==2)
print("Controller: timers, suspension, polymorph, Holy Mountain hitboxes, checkpoint deduplication and reverse alchemy passed.")

do
    settings,flags={},{}
    new_world()
    local tag="noita_hideout_mountain_storage"
    local function altar(x,y,biome)
        local id=mountain(x,y,biome)
        local hitbox=EntityGetFirstComponentIncludingDisabled(id,"HitboxComponent")
        hitbox.aabb_min_x,hitbox.aabb_min_y,hitbox.aabb_max_x,hitbox.aabb_max_y=-453,-44,531,166
        return x-18,y+84,id
    end
    local x,y,firstRoom=altar(1100,2048,holy)
    local secondX,secondY=altar(-35800,4096,holy)
    local bossX,bossY=altar(1100,12288,"$biome_boss_arena")
    local old=state()
    old.checkpoints["1100,2048"]=true
    assert(NHStore.commit(old))
    boot()
    local atLocker=stand(x,y)
    assert(atLocker.near and atLocker.at_station and not atLocker.open and #EntityGetWithTag(tag)==1)
    local first=EntityGetWithTag(tag)[1]
    assert(entities[first].x==x and entities[first].y==y)
    assert(#EntityGetWithTag("noita_hideout_home_wand_edit")==1)
    inventory_open=true
    tick()
    local pouchId=state().starterPouchId
    local deposit={pouchId=pouchId,source="safe",destination="warehouse",from=2,safeSlot=1}
    local withdraw={pouchId=pouchId,source="warehouse",destination="safe",from=1,safeSlot=2}
    tick(nil,"move_pouch",deposit)
    assert(starter().location=="warehouse" and tick().warehouse.equipment[1].id==pouchId)
    tick(nil,"open_container",{pouchId=pouchId,container="warehouse",safeSlot=1})
    assert(tick().pouchId==pouchId)
    entities[player].x=x+49
    assert(not tick(nil,"move_pouch",withdraw).near and not tick().pouchId and starter().location=="warehouse")
    -- The vanilla exit kills the wand-edit workshop, leaving workshop_aabb in place.
    local editRoom=EntityLoad("workshop.xml",x,y)
    EntityAddTag(editRoom,"workshop")
    EntityKill(editRoom)
    boot()
    assert(stand(x+48,y).near and #EntityGetWithTag(tag)==1 and EntityGetIsAlive(first))
    assert(stand(secondX,secondY).at_station and #EntityGetWithTag(tag)==2)
    tick(nil,"move_pouch",withdraw)
    assert(starter().location=="safe")
    EntityKill(firstRoom)
    boot()
    assert(stand(x,y).at_station and #EntityGetWithTag(tag)==2)
    entities[player].x=x+49
    tick(nil,"move_pouch",deposit)
    assert(starter().location=="safe")
    assert(not stand(bossX,bossY).near and #EntityGetWithTag(tag)==2)
    -- The secret room has a permanent co-op marker instead of a workshop hitbox.
    local secret=EntityLoad("coop_respawn.xml",8000,3000)
    EntityAddTag(secret,"coop_respawn")
    entities[secret].biome=holy
    assert(stand(8104,3034).at_station and #EntityGetWithTag(tag)==3)
    assert(not state().checkpoints["8000,3000"] and #EntityGetWithTag("noita_hideout_home_wand_edit")==1)
    local cabin=dofile("mods/noita_hideout/files/travel/cabin.lua")
    local cx,cy=cabin.point(cabin.terminal)
    world["nh_travel.built"]=cabin.revision
    EntityLoad("console.xml",cx,cy)
    inventory_open=false
    assert(stand(cx,cy-6).travel.groups[2].world==-1)
    inventory_open=true
    local menu=tick(nil,"travel_to",1)
    assert(menu.mode=="case" and menu.near and #EntityGetWithTag("nh_travel_gate")==0)
    local west=menu.travel.groups[2].routes[1]
    tick(nil,"travel_to",west.index)
    assert(tick().travel.gateX==secondX and #EntityGetWithTag("nh_travel_gate")==1)
    tick(nil,"travel_to",1)
    assert(tick().travel.gateKind=="home" and #EntityGetWithTag("nh_travel_gate")==1)
    local ix,iy=cabin.point(cabin.infirmary)
    assert(not stand(ix,iy).travel and tick().near)
    local gate=world["nh_travel.gate"]
    tick(nil,"travel_to",west.index)
    assert(world["nh_travel.gate"]==gate)
    print("Controller: local Holy Mountain lockers, shared transfers, saved rooms, revisit, parallel and secret altars passed.")
end

do
    settings,flags={},{}
    new_world()
    tick() -- Let the starting terminal stream in before visiting the landmarks.
    local ray,platform,liquid,sky,stream=RaytraceSurfaces,RaytracePlatforms,RaytraceSurfacesAndLiquiform,GameGetSkyVisibility,DoesWorldExistAt
    local surfaceLoaded,light=true,1
    local function floorAt(x)
        x=x-GetParallelWorldPosition(x)*BiomeMapGetSize()*512
        if math.abs(x+9700)<420 then return -35 end
        if math.abs(x-8660)<420 then return 19 end
    end
    function DoesWorldExistAt(x,y,tx,ty) return (not floorAt(x) or surfaceLoaded) and stream(x,y,tx,ty) end
    function RaytracePlatforms(x,y,tx,ty)
        local floor=floorAt(x)
        if floor then return x==tx and y<=floor and ty>=floor,x,floor end
        return platform(x,y,tx,ty)
    end
    function RaytraceSurfaces(x,y,tx,ty)
        if floorAt(x) then return RaytracePlatforms(x,y,tx,ty) end
        return ray(x,y,tx,ty)
    end
    function RaytraceSurfacesAndLiquiform(x,y,tx,ty)
        -- A tree on the first snowy candidate must shift it inland.
        if floorAt(x) then return math.abs(x+9700)<6 and y< -35 end
        return liquid(x,y,tx,ty)
    end
    function GameGetSkyVisibility() return light end
    local function visit(x,y)
        EntitySetTransform(player,x,y)
        local m
        for _=1,17 do m=tick() end
        return m
    end
    local tag="nh_landmark_terminal"
    visit(-9700,-45)
    assert(#EntityGetWithTag(tag)==0,"skip a world layout without the landmark")
    for _,s in ipairs({{-9970,768,"$biome_vault_frozen"},{9984,-640,"$biome_pyramid"}}) do
        entities[EntityLoad("test.xml",s[1],s[2])].biome=s[3]
    end
    surfaceLoaded=false; visit(-9700,-45)
    surfaceLoaded,light=true,0; visit(-9700,-45)
    assert(#EntityGetWithTag(tag)==0,"need loaded terrain and open sky")
    light=1
    visit(-9460,-42)
    local cliff=assert(EntityGetWithTag("nh_landmark_snowcliff")[1])
    local cx,cy=EntityGetTransform(cliff)
    assert(cx> -9700 and cy==-42 and not EntityHasTag(cliff,"nh_home_terminal"))
    assert(not world["nh_travel.snowcliff_unlocked"],"streaming a terminal is not discovery")
    local m=visit(cx,cy)
    assert(m.near and m.landmarkName[1]=="冻结避难所东崖" and world["nh_travel.snowcliff_unlocked"]=="1")
    assert(not m.at_station and next(state().checkpoints)==nil)
    inventory_open=true
    assert(tick().warehouse and #EntityGetWithTag("noita_hideout_home_wand_edit")==1)
    inventory_open=false
    visit(8660,12)
    assert(world["nh_travel.pyramid_unlocked"]=="1" and #EntityGetWithTag(tag)==2)
    boot(); visit(8660,12)
    assert(#EntityGetWithTag(tag)==2 and #EntityGetWithTag("nh_home_terminal")==1)
    -- Recall from desert; choose the snowy cliff from the real inventory dispatch.
    for i=1,37 do tick(10) end
    local gate=assert(EntityGetWithTag("nh_travel_gate")[1])
    visit(EntityGetTransform(gate))
    local cabin=dofile("mods/noita_hideout/files/travel/cabin.lua")
    local sx,sy=cabin.point(cabin.terminal)
    visit(sx,sy-6)
    inventory_open=true
    local stops=tick().travel.groups[1].routes
    assert(#stops==3 and stops[1].kind=="home" and stops[2].name[1]=="冻结避难所东崖" and stops[3].name[1]=="金字塔西麓")
    tick(nil,"travel_to",stops[2].index); inventory_open=false; tick()
    local gx,gy=cabin.point(cabin.gate)
    visit(gx,gy)
    local px,py=EntityGetTransform(player)
    assert(math.abs(px-cx)<=44 and py==-41 and world["nh_travel.trip"]=="" and tick().near)
    for i=1,37 do tick(10) end
    visit(EntityGetTransform(assert(EntityGetWithTag("nh_travel_gate")[1])))
    visit(sx,sy-6)
    inventory_open=true
    stops=tick().travel.groups[1].routes
    tick(nil,"travel_to",stops[3].index); inventory_open=false; tick()
    visit(gx,gy)
    px,py=EntityGetTransform(player)
    assert(math.abs(px-8660)<=44 and py==13 and tick().landmarkName[1]=="金字塔西麓")
    -- A 0.42.5 save has only the main world's keys. Each newly visited copy
    -- checks its own terrain and is listed even if it has no Holy Mountains.
    local width=BiomeMapGetSize()*512
    local east,west=width,-2*width
    assert(not visit(east+8660,12).near and #EntityGetWithTag(tag)==2)
    for _,s in ipairs({{east+9984,-640,"$biome_pyramid"},{west-9970,768,"$biome_vault_frozen"},
        {west+9984,-640,"$biome_pyramid"}}) do entities[EntityLoad("test.xml",s[1],s[2])].biome=s[3] end
    assert(visit(east+8860,12).landmarkName==nil and #EntityGetWithTag(tag)==3)
    visit(sx,sy-6); inventory_open=true
    assert(#tick().travel.groups==1,"undiscovered world must stay hidden")
    inventory_open=false
    assert(visit(east+8660,12).near and not visit(east-9700,-42).near)
    assert(visit(west-9700,-42).near and visit(west+8660,12).near)
    boot(); visit(west+8660,12); assert(#EntityGetWithTag(tag)==5)
    visit(sx,sy-6); inventory_open=true
    local groups=tick().travel.groups
    assert(#groups==3 and #groups[1].routes==3 and groups[2].world==1 and #groups[2].routes==1)
    assert(groups[3].world==-2 and #groups[3].routes==2 and groups[3].routes[1].name[1]=="冻结避难所东崖")
    tick(nil,"travel_to",groups[2].routes[1].index); inventory_open=false; tick(); visit(gx,gy)
    px,py=EntityGetTransform(player)
    assert(math.abs(px-east-8660)<=44 and py==13 and tick().near)
    for i=1,37 do tick(10) end
    visit(EntityGetTransform(assert(EntityGetWithTag("nh_travel_gate")[1])))
    px,py=EntityGetTransform(player)
    assert(cabin.inside(px,py) and world["nh_travel.trip"]=="")
    -- NG+ uses a narrower biome map and separate run globals.
    local originalSize,originalCycle=BiomeMapGetSize,SessionNumbersGetValue
    function BiomeMapGetSize() return 64,48 end
    function SessionNumbersGetValue() return "1" end
    boot()
    local ngEast=64*512
    entities[EntityLoad("test.xml",ngEast+9984,-640)].biome="$biome_pyramid"
    assert(visit(ngEast+8660,12).near and world["nh_travel.ng1.world1.pyramid_unlocked"]=="1")
    assert(not world["nh_travel.ng1.pyramid_unlocked"])
    BiomeMapGetSize,SessionNumbersGetValue=originalSize,originalCycle
    RaytraceSurfaces,RaytracePlatforms,RaytraceSurfacesAndLiquiform,GameGetSkyVisibility,DoesWorldExistAt=ray,platform,liquid,sky,stream
end

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
    assert(not unfinanced.ready and unfinanced.price==5 and unfinanced.quantity==250)
    buy("water")
    assert(wallet.money==400 and not state().materials.water)
    tick(nil,"bank_transfer",{direction="deposit",amount=320})
    local view=tick()
    assert(view.bankGold==320 and view.walletGold==80 and #view.shopGoods==18+5)
    for _,offer in ipairs(NHStormProducts.offers) do
        local entry=has_project(view.shopGoods,offer.id)
        assert(entry.category=="storm_products" and entry.icon==offer.icon and entry.resourceStock==0 and not entry.ready)
        assert(entry.resourceName==NHStore.alchemyResources[offer.resource].en and entry.quantity==1)
    end
    for _,recipe in ipairs(NHStormProducts.recipes) do
        assert(not has_project(view.recipes,recipe.id))
        local entry=has_project(view.shopGoods,recipe.id)
        assert(entry.category=="storm_products" and entry.icon==recipe.icon and #entry.inputs==1)
        assert(entry.inputs[1].amount==1 and entry.inputs[1].available==0)
        for _,out in ipairs(entry.outputs) do assert(out.amount==20) end
    end
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
    assert(settled.bankGold==185 and wallet.money==80 and wallet.money_spent==0)
    assert(state().materials.water==250 and settled.warehouse.supplies[1].kind=="medkit")
    assert(settled.warehouse.supplies[2].kind=="dose" and settled.warehouse.supplies[2].remaining==5)
    local recent=state()
    assert(NHStore.spendGold(recent,181) and NHStore.commit(recent))
    assert(has_project(settled.shopGoods,"water").ready)
    buy("water") -- recheck the price against the latest profile
    assert(state().bankGold==4 and state().materials.water==250)
    assert(not has_project(tick().shopGoods,"water").ready)
    boot()
    local resumed=tick()
    assert(resumed.bankGold==4 and not has_project(resumed.shopGoods,"water").ready)
    assert(#state().warehouse==2 and wallet.money==80)
    local kit=resumed.warehouse.supplies[1]
    local sell={id=kit.id,kind=kit.kind,slot=1,mode="sell",quantity=1,count=kit.trade.count,remaining=kit.trade.remaining}
    assert(kit.trade.oneGold==25)
    fail_commit=true
    tick(nil,"supply_trade",sell)
    fail_commit=false
    assert(state().bankGold==4 and #state().warehouse==2)
    boot(); tick()
    tick(nil,"supply_trade",sell)
    tick(nil,"supply_trade",sell)
    assert(state().bankGold==29 and #state().warehouse==1)
end
testShop()
do
    settings,flags={},{}
    new_world()
    EntityAddComponent2(player,"WalletComponent",{money=0})
    local profile=state()
    for slot,kind in ipairs({"storm_mercury_pressure","storm_mana_pure"}) do
        local product=NHStormProducts.types[kind]
        profile.warehouse[slot]={id=profile.nextItemId,slot=slot,item={kind=kind,count=1,name=product.en,icon=product.icon}}
        profile.nextItemId=profile.nextItemId+1
    end
    assert(NHStore.commit(profile))
    boot()
    inventory_open=true
    local view=tick()
    for slot,kind in ipairs({"storm_mercury_pressure","storm_mana_pure"}) do
        local row=view.warehouse.supplies[slot]
        assert(row.kind==kind and row.trade.units==50 and not row.trade.oneGold)
        tick(nil,"supply_trade",{id=row.id,slot=slot,kind=kind,count=1,quantity=1,mode="convert"})
    end
    view=tick()
    assert(has_project(view.shopGoods,"sell_red_mercury").resourceStock==50)
    assert(has_project(view.shopGoods,"sell_crystallized_mana").resourceStock==50)
    for _,recipe in ipairs(NHStormProducts.recipes) do
        assert(has_project(view.shopGoods,recipe.id).ready)
        tick(nil,"craft",{id=recipe.id})
    end
    tick(nil,"shop_buy",{id="sell_red_mercury"})
    tick(nil,"shop_buy",{id="sell_crystallized_mana"})
    boot()
    local saved=state()
    assert(#saved.warehouse==0 and saved.bankGold==1000)
    assert(saved.resources.nh_red_mercury==48 and saved.resources.nh_crystallized_mana==47)
    assert(saved.materials.midas==20 and saved.resources.nh_elixir_of_immortality==20)
    assert(saved.resources.arcane_scrap==20 and saved.resources.container_scrap==20)
end
print("Controller: shop previews, range, deposits, commit failure, stale funds and reload passed.")

local function testPowderSeparation()
    settings,flags={},{}
    new_world()
    local profile=state()
    profile.materials={gunpowder_unstable=80,gunpowder=140,oil=100}
    assert(NHStore.commit(profile))
    function CellFactory_GetAllLiquids() return {"magic_liquid_hp_regeneration"} end
    function CellFactory_GetAllSands() return {"purifying_powder","gunpowder","gunpowder_unstable"} end
    boot()
    inventory_open=true
    local view=tick()
    local split=assert(has_project(view.recipes,"separate_gunpowder"))
    assert(split.alchemyMode=="decomposition" and split.ready and split.inputs[1].available==220)
    assert(split.inputs[1].name=="Gunpowder (total)")
    assert(split.inputs[1].detail:find("Alchemical gunpowder  80 / 80\nRegular gunpowder  140 / 120",1,true))
    local station=assert(has_project(view.progression.expansion,"grenade"))
    local powder=station.costs[1]
    assert(station.canBuy and powder.name==split.inputs[1].name and powder.available==220 and powder.amount==150)
    assert(powder.detail:find("Alchemical gunpowder  80 / 80\nRegular gunpowder  140 / 70",1,true))
    assert(view.materials[1].name=="Regular gunpowder" and view.materials[2].name=="Alchemical gunpowder")
    tick(nil,"craft",{id=split.id})
    assert(state().materials.gunpowder==20 and not state().materials.gunpowder_unstable)
    station=assert(has_project(tick().progression.expansion,"grenade"))
    assert(not station.canBuy and station.costs[1].available==20)
    advance(split.duration*60)
    local stock={}
    for _,material in ipairs(tick().materials) do stock[material.key]=material end
    assert(stock.magic_liquid_hp_regeneration.amount==100 and stock.magic_liquid_hp_regeneration.slot==1)
    assert(stock.purifying_powder.amount==100 and stock.purifying_powder.slot==2)
end
testPowderSeparation()
print("Controller: combined gunpowder stock, separated inputs and liquid/powder delivery passed.")

do
    local function testBulkSupplies()
        settings,flags={},{}
        new_world()
        local profile=state()
        profile.levels.grenade,profile.levels.medical=1,1
        profile.materials={sandstone=180,sandstone_surface=25,sand_surface=33,sand_petrify=1,sand_blue=1,
            water_fading=100,water_temp=100,water_swamp=500,slime_green=125,slime_yellow=125,blood_fading=50,
            magic_liquid_unstable_teleportation=250,magic_liquid_mana_regeneration=1}
        assert(NHStore.commit(profile))
        boot()
        inventory_open=true
        local view=tick()
        local warehouse=has_project(view.progression.expansion,"warehouse_wand")
        local grenade=has_project(view.recipes,"grenade")
        assert(warehouse.canBuy and warehouse.costs[1].available==240 and warehouse.costs[2].available==200)
        assert(grenade.ready and grenade.inputs[1].name==warehouse.costs[1].name and grenade.inputs[1].available==240)
        assert(warehouse.costs[1].detail:find("Stock / payment",1,true)
            and warehouse.costs[1].detail:find("Surface sandstone  25 / 20",1,true))
        assert(warehouse.materialPayment.sandstone==180 and warehouse.materialPayment.sandstone_surface==20)
        local safe=has_project(view.progression.upgrade,"safe")
        assert(not safe.canBuy and not safe.materialPayment and safe.costs[2].available==250)
        assert(safe.costs[2].detail:find("Green slime  125\nYellow slime  125",1,true))
        assert(has_project(view.recipes,"grenade").ready and has_project(view.recipes,"medical").ready)
        local mana=has_project(view.recipes,"mana")
        assert(not mana.ready and mana.inputs[1].available==0 and not mana.inputs[1].detail)
        local stable=has_project(view.recipes,"stable")
        assert(not stable.ready and stable.inputs[2].available==0 and not stable.inputs[2].detail)
        tick(nil,"buy_upgrade",{id="warehouse_wand",level=0})
        local stock=state().materials
        assert(not stock.sandstone and stock.sandstone_surface==5 and not stock.water_fading and stock.water_temp==100)
        grenade=has_project(tick().recipes,"grenade")
        assert(not grenade.ready and grenade.inputs[1].available==40)
        tick(nil,"craft",{id="medical"})
        stock=state().materials
        assert(not stock.blood_fading and not stock.water_temp and stock.water_swamp==500)
    end
    testBulkSupplies()
end

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
    assert(midas.duration==0 and #midas.outputs==1 and midas.outputs[1].amount==100 and midas.outputs[1].key=="midas")
    assert(not has_project(menu,"mana").ready and has_project(menu,"mana").reason=="Missing catalyst.")
    for _,recipe in ipairs(menu) do
        for _,result in ipairs(recipe.outputs) do assert(result.key~="gold") end
    end
    tick(nil,"craft",{id="midas"})
    boot()
    local inProgress=has_project(tick().recipes,"midas")
    assert(inProgress.catalysts[1].held==0 and inProgress.catalysts[1].available==101)
    assert(inProgress.outputs[1].amount==100 and state().materials.midas==101)
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
    assert(not view.order_active and not state().order)
    assert(not has_project(view.recipes,"medkit_essence") and view.warehouse.supplies[1].kind=="medkit")
    boot()
    tick()
    assert(state().finished==1 and #state().warehouse==1)
    local delivered=state()
    assert(not delivered.order and delivered.warehouse[1].item.kind=="medkit")
    assert(tick().warehouse.supplies[1].icon=="mods/noita_hideout/files/items/medkit.png")
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
    local switchedAt=state().farm.time
    view=advance(3*3600)
    local minuteEnd=math.floor(NHFarm.observe(state(),frame)/3600)*3600
    assert(state().resources.grain==math.floor((minuteEnd-switchedAt)*2/3600))
    assert(state().farm.plots[1].readyAt==nextAt+NHFarm.crops.grain.frames)
    assert(view.farm.crops[1].stock==6 and not state().materials.fiber)
    assert(has_project(view.recipes,"bread").ready,"the open workshop must see a passive deposit immediately")
    local bandage=has_project(view.recipes,"bandage")
    local kit=has_project(view.recipes,"field_medkit")
    assert(bandage.duration==0 and kit.duration==0 and has_project(view.recipes,"medical").duration==0)
    assert(bandage.ready and bandage.output==4 and bandage.inputs[1].available==6 and bandage.inputs[1].amount==4)
    assert(bandage.inputs[2].available==2 and bandage.inputs[2].amount==2)
    assert(kit.inputs[1].available==2 and kit.inputs[2].available==0 and not kit.ready)
    assert(kit.inputs[2].detail:find("fewest charges",1,true))
    assert(has_project(view.recipes,"bread").category=="food" and has_project(view.recipes,"sugar_cube").category=="food")
    tick(nil,"craft",{id="bandage"})
    assert(not state().order and state().resources.fiber==2 and not state().resources.sugar)
    view=tick()
    assert(view.warehouse.supplies[1].kind=="bandage" and view.warehouse.supplies[1].count==4)
    kit=has_project(view.recipes,"field_medkit")
    assert(kit.ready and kit.inputs[2].available==4 and kit.inputs[2].amount==1)
    tick(nil,"craft",{id="field_medkit"})
    assert(not state().order)
    boot()
    view=tick()
    assert(view.warehouse.supplies[1].count==3)
    assert(view.warehouse.supplies[2].kind=="medkit" and view.warehouse.supplies[2].remaining==8)
    assert(not state().resources.herb and has_project(view.recipes,"field_medkit").inputs[2].available==3)
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
    assert(has_project(twoFields.crops,"grain").perMinute==4.08 and has_project(twoFields.crops,"fiber").perMinute==0)
    tick(nil,"farm_plant",{plot=2,token=twoFields.plots[2].token,crop="fiber"})
    local switched=tick().farm
    assert(has_project(switched.crops,"grain").perMinute==2.04 and has_project(switched.crops,"fiber").perMinute==3.06)
end
testFarmController()
print("Controller: passive field deposits, retry, crop switching, live workshop stock and crafting passed.")

do
    settings,flags={},{}
    new_world()
    local seeded=state()
    seeded.bankGold=100
    seeded.levels.farmland=1
    assert(NHFarm.plant(seeded,{plot=1,token=0,crop="grain"},0))
    assert(NHStore.commit(seeded))
    boot()
    local wallet=EntityAddComponent2(player,"WalletComponent",{money=0})
    local commit=NHStore.commit
    local attempts,limit=0,"Prototype profile exceeds 1 MiB"
    NHStore.commit=function(draft,...)
        if limit and draft.farm.time>=3600 then
            attempts=attempts+1
            return false,limit
        end
        return commit(draft,...)
    end
    inventory_open=true
    assert(advance(3600).mode=="case" and attempts==1 and not state().resources.grain)
    assert(advance(3600).mode=="case" and attempts==1)
    OnPausedChanged(true,false)
    assert(attempts==1 and state().farm.time==0)
    tick(nil,"bank_transfer",{direction="withdraw",amount="all"})
    assert(wallet.money==100 and state().bankGold==0 and attempts==1)
    limit=nil
    tick()
    assert(state().resources.grain==4)

    limit="Hideout profile needs room to finish its deposit (1 MiB)"
    advance(3600)
    assert(attempts==2 and state().resources.grain==4)
    local external=state()
    external.bankGold=1
    assert(commit(external))
    limit=nil
    advance(60-frame%60)
    assert(state().resources.grain==6 and state().bankGold==1)
    NHStore.commit=commit
end

do
    settings,flags={},{}
    new_world()
    local s=state()
    local bag=s.pouches[s.starterPouchId]
    for i,kind in ipairs({"lightning","frost","healing"}) do assert(NHStore.putPouchDose(bag,5,i+1,kind)) end
    assert(NHStore.commit(s))
    boot()
    local effects={}
    for i,kind in ipairs({"fire","lightning","frost","healing"}) do
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
        assert(EntityGetParent(effects[kind])==player and NHDoses.remaining(state(),syringe)==4)
        local timer=kind=="healing" and "VariableStorageComponent" or "GameEffectComponent"
        local field=kind=="healing" and "value_int" or "frames"
        local component=EntityGetFirstComponentIncludingDisabled(effects[kind],timer)
        ComponentSetValue2(component,field,1)
        tick()
        tick(nil,nil,nil,"right")
        assert(#EntityGetWithTag(d.tag)==1 and ComponentGetValue2(component,field)==(kind=="healing" and 60 or 3600))
        tick()
        tick(nil,nil,nil,"right")
        assert(NHDoses.remaining(state(),syringe)==2)
        for j=1,2 do tick(); tick(nil,nil,nil,"right") end
        assert(not EntityGetIsAlive(syringe))
    end
    for _,effect in pairs(effects) do assert(EntityGetIsAlive(effect)) end
    local health=EntityAddComponent2(player,"DamageModelComponent",{hp=1,max_hp=5})
    function GetUpdatedEntityID() return effects.healing end
    for tickNo=1,60 do
        dofile("mods/noita_hideout/files/bread_regeneration.lua")
        assert(math.abs(health.hp-(1+0.05*math.floor(tickNo/2)))<1e-8)
    end
    assert(not EntityGetIsAlive(effects.healing))
    print("Controller: four distinct injectors, refresh, concurrent protection and 30% of maximum HP per healing dose passed.")
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
    assert(state().bankGold==149 and state().resources.sugar==21 and state().resources.spice==8)
    assert(not state().dragonLoot)
    local settlement=math.ceil(firstTreasure/3600)*3600
    advance(settlement-NHFarm.observe(state(),frame))
    s=state()
    local gold=math.floor((settlement-firstTreasure+NHLivestock.species.dragon_egg.period)*30/3600)
    assert(s.bankGold==gold and #s.warehouse+NHDragonLoot.pendingCount(s)>=1)
    assert(s.farm.herds.dragon_egg.adults==1 and s.farm.herds.dragon_egg.progress==settlement-firstTreasure)
    local treasureSeed=s.dragonLoot.seed
    boot()
    tick()
    assert(state().bankGold==gold and state().dragonLoot.seed==treasureSeed)
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
    assert(state().resources.herb==3 and not state().resources.spice)
    local settlement=math.ceil(first/3600)*3600
    advance(settlement-NHFarm.observe(s,frame))
    s=state()
    assert(s.resources.herb==4 and s.resources.fiber==7 and s.resources.spice==1)
    local dose,card
    for _,row in ipairs(s.warehouse) do
        if row.item.kind=="dose" then dose=row end
        if row.item.species=="slime" then card=row end
    end
    assert(dose and dose.item.remaining==5 and card and card.item.remaining==80)
    boot()
    entities[player].x=227
    inventory_open=true
    tick()
    assert(state().resources.spice==1 and state().farm.herds.gel_pool.progress==settlement-first)
    local pouch=starter()
    tick(nil,"open_container",{pouchId=pouch.id,safeSlot=pouch.slot,container="safe"})
    tick(nil,"pack_dose",{pouchId=pouch.id,container="warehouse",safeSlot=dose.slot,targetCell=4})
    local cell=assert(starter().cells[4])
    assert(cell.remaining==5 and (cell.subtype or "fire")==dose.item.subtype)
    tick(nil,"use_inventory",{container="pouch",pouchId=pouch.id,cell=4,kind="dose",
        count=1,remaining=5,subtype=dose.item.subtype})
    assert(starter().cells[4].remaining==4)
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
    assert(state().resources.herb==3 and state().resources.fiber==5)
    tick()
    assert(state().resources.herb==3 and state().resources.fiber==5,"between settlements only the rare work phase advances")
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
    for _,species in ipairs({"bee","dragon","slime","cat","dog"}) do
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
    advance(3600-frame%3600)
    assert(state().affinity.dryad==354)
    assert(NHAffinity.follow("dryad",6)==10)
    NHAffinity.follow("griffin",6)
    boot()
    assert(NHAffinity.points(state(),"dryad")==10)
    local revision=state().revision
    OnPausedChanged(true,true)
    OnPausedChanged(false,false)
    assert(state().revision==revision)
    OnPausedChanged(true,false)
    assert(state().affinity.dryad==360 and state().affinity.griffin==6)
    OnPausedChanged(true,false)
    assert(state().revision==revision+1)
    new_world()
    assert(state().runSerial==2 and NHAffinity.points(state(),"dryad")==10)
    NHAffinity.follow("griffin",6)
    OnPlayerDied()
    assert(state().affinity.griffin==12)
    new_world()
    assert(NHAffinity.points(state(),"dryad")==10)
    for _=1,58 do NHAffinity.follow("griffin",6) end
    assert(NHAffinity.points(state(),"griffin")==10)
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
    assert(not state().order and not state().resources.essence_healing)
    boot()
    tick()
    local card=tick().warehouse.spell[1]
    assert(card.spell_uses==20 and card.essence.amount==175 and state().finished==1)
    tick(nil,"salvage",{id=card.id,kind="spell",slot=1,mode="essence"})
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
        assert(recipe.ready and recipe.category=="medical" and recipe.duration==0)
        assert(recipe.medkit.uses==uses and recipe.medkit.healPercent==percent)
        assert(recipe.inputs[1].essence=="essence_healing" and recipe.inputs[1].amount==need)
        assert(recipe.inputs[2].amount==herbs)
        local input=recipe.inputs[3]
        assert(input.name==ingredient and input.available==count and input.amount==1)
        assert(input.detail:find("fewest charges",1,true))
    end
    checkRecipe("tactical_medkit",60,6,25,2,4,"Medkit (1/8)",2)
    tick(nil,"craft",{id="tactical_medkit"})
    assert(not state().order and state().resources.essence_healing==3 and state().resources.herb==8)
    assert(tick().warehouse.supplies[1].remaining==8)
    local built=state()
    local tactical=assert(tick().warehouse.supplies[2])
    assert(tactical.kind=="tactical_medkit" and tactical.remaining==6 and tactical.count==4)
    for _,row in ipairs(built.warehouse) do
        if row.id==tactical.id then row.item.remaining=5 end
    end
    assert(NHStore.commit(built))
    boot()
    checkRecipe("advanced_medkit",180,6,40,3,8,"Tactical medkit (5/6)",4)
    tick(nil,"craft",{id="advanced_medkit"})
    assert(not state().order and not state().resources.essence_healing and not state().resources.herb)
    boot()
    local advanced=tick().warehouse.supplies[3]
    assert(advanced.kind=="advanced_medkit" and advanced.remaining==6 and advanced.count==4 and state().finished==2)
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
    local built=tick().warehouse.supplies[1]
    assert(built.kind==recipe.id and built.remaining==8 and built.count==4)
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
    assert(tick().surgery.elapsed==101 and health.mIsOnFire and buff.frames==7200)
    health.hp=0.8
    assert(advance(78).surgery.elapsed==179 and entities[held].comps.ItemComponent.uses_remaining==32)
    local kit=held
    assert(not tick().surgery and EntityGetIsAlive(kit) and entities[kit].comps.ItemComponent.uses_remaining==31 and health.hp==8.8)
    assert(not health.mIsOnFire and health.mFireFramesLeft==0 and EntityGetIsAlive(food) and buff.frames==7200)
end
testSurgeryFromWorkshop()
print("Controller: a crafted kit completes surgery under fire damage and spends one charge.")

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
    local bandage=stock("warehouse",1,"bandage",4)
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
    assert(health.hp==40 and stored(bandage).count==4)
    health.hp=1
    fail_commit=true
    right(bandage)
    advance(30)
    fail_commit=false
    assert(health.hp==1 and stored(bandage).count==4)
    advance(61)
    right(bandage)
    assert(advance(29).surgery.elapsed==29 and health.hp==1)
    assert(not tick().surgery and health.hp==3 and stored(bandage).count==4 and stored(bandage).remaining==7)
    right(bandage) -- The HUD still describes the eight-roll stack.
    assert(health.hp==3 and stored(bandage).count==4 and stored(bandage).remaining==7)
    right(secure)
    assert(not advance(30).surgery and health.hp==5 and stored(secure).count==3 and stored(secure).remaining==7)

    local native=withdraw(carried,1)
    local unused=EntityLoad("dummy.xml",227,-85)
    EntityAddChild(quick,unused)
    held=unused
    health.hp=1
    right(native)
    local charges=EntityGetFirstComponentIncludingDisabled(native.entity,"ItemComponent")
    assert(not advance(60).surgery and health.hp==7 and charges.uses_remaining==1 and held==unused)
    ComponentSetValue2(charges,"inventory_slot",2,0)
    right(native)
    assert(health.hp==7 and charges.uses_remaining==1 and held==unused)

    right(kit)
    assert(tick().surgery and stored(kit).remaining==1)
    EntitySetTransform(player,1000,-85)
    assert(not tick().surgery and stored(kit).remaining==1 and health.hp==7)
    EntitySetTransform(player,227,-85)
    right(kit)
    assert(advance(179).surgery.elapsed==179 and health.hp==7)
    assert(not tick().surgery and not stored(kit) and health.hp==15 and held==unused)
    right(movedKit)
    assert(tick().surgery)
    local movedNative=withdraw(movedKit,1)
    assert(not tick().surgery and not stored(movedKit) and health.hp==15)
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

local function testRemoteTerminal()
    settings,flags={},{}
    new_world()
    local saved=state()
    saved.resources.arcane_scrap,saved.bankGold=1,100
    local backup={id=saved.nextItemId,slot=1,item=NHEquipment.remoteItem()}
    backup.item.remaining=1
    saved.nextItemId=saved.nextItemId+1
    table.insert(saved.safe,backup)
    assert(NHStore.commit(saved))
    boot()
    inventory_open=true
    local recipe=assert(has_project(tick().recipes,"remote_terminal"))
    assert(recipe.category=="equipment" and recipe.ready and recipe.inputs[1].amount==1
        and recipe.inputs[2].amount==100 and recipe.inputs[2].available==100)
    local reserve={kind="remote_terminal",container="safe",slot=1,storedId=backup.id,remaining=1}
    tick(nil,"move_terminal",{source="safe",from=1,entity=backup.id,destination="warehouse",safeSlot=1})
    local parked=assert(tick().warehouse.equipment[1])
    assert(parked.id==backup.id and parked.remaining==1)
    tick(nil,"move_terminal",{source="warehouse",from=1,entity=parked.id,destination="safe",safeSlot=1})
    tick(nil,"use_inventory",reserve)
    assert(state().safe[1].item.remaining==1 and not tick().remote_linked)
    tick(nil,"craft",{id=recipe.id})
    local ready=advance(recipe.duration*60)
    local function retrieve(view)
        local record=view.warehouse.equipment[1]
        tick(nil,"secure_withdraw",{kind="remote_terminal",container="warehouse",storedId=record.id,
            safeSlot=1,parent=quick,lane="tool",xslot=0,yslot=0})
        for _,slot in ipairs(tick().native_slots) do
            if slot.kind=="remote_terminal" then slot.container="native"; return slot end
        end
        error("Terminal did not arrive in the native inventory")
    end
    local function charges(id)
        return ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(id,"ItemComponent"),"uses_remaining")
    end
    local terminal=retrieve(ready)
    assert(charges(terminal.entity)==20)
    inventory_open=false
    EntitySetTransform(player,1000,-85)
    held=terminal.entity
    tick()
    local pending=tick(nil,nil,nil,"right")
    assert(pending.remote_linked and not pending.open and pending.near and charges(held)==19)
    tick(nil,nil,nil,"right")
    tick()
    tick(nil,nil,nil,"right")
    assert(charges(held)==19)
    inventory_open=true
    assert(tick().near and tick().remote_linked)
    tick(nil,"use_inventory",terminal)
    assert(charges(held)==19 and #EntityGetWithTag("noita_hideout_home_wand_edit")==1)
    local pouch=state().starterPouchId
    local deposit={pouchId=pouch,source="safe",destination="warehouse",from=2,safeSlot=2}
    local withdraw={pouchId=pouch,source="warehouse",destination="safe",from=2,safeSlot=2}
    -- Keep transferring after the terminal itself is put away.
    tick(nil,"place",{container="warehouse",safeSlot=1,entity=held,parent=quick,lane="tool",xslot=0,yslot=0})
    assert(not EntityGetIsAlive(terminal.entity) and tick().warehouse.equipment[1].remaining==19)
    tick(nil,"move_pouch",deposit)
    assert(starter().location=="warehouse" and tick().near)
    inventory_open=false
    assert(tick().remote_linked and #EntityGetWithTag("noita_hideout_home_wand_edit")==1)
    boot()
    assert(tick().near and tick().remote_linked and #EntityGetWithTag("nh_remote_station")==1)
    EntitySetTransform(player,1100,-85)
    inventory_open=true
    assert(not tick().near and #EntityGetWithTag("noita_hideout_home_wand_edit")==0)
    tick(nil,"move_pouch",withdraw)
    assert(starter().location=="warehouse")
    EntitySetTransform(player,1000,-85)
    assert(tick().near)
    EntitySetTransform(player,1200,-85)

    -- The equipped link can deploy directly. Failed payment preserves the link.
    tick(nil,"move_gear",{kind="remote_terminal",source="safe",from=1,entity=backup.id,destination="gear"})
    reserve={kind="remote_terminal",container="gear",storedId=backup.id,remaining=1}
    assert(state().gearLink.id==backup.id)
    fail_commit=true
    tick(nil,"use_inventory",reserve)
    fail_commit=false
    assert(not advance(61).remote_linked and state().gearLink.item.remaining==1)
    assert(#EntityGetWithTag("nh_remote_station")==1)
    tick(nil,"use_inventory",reserve)
    assert(tick().remote_linked and not state().gearLink)
    assert(#EntityGetWithTag("nh_remote_station")==2)
    tick(nil,"move_pouch",withdraw)
    assert(starter().location=="safe")
    terminal=retrieve(tick())
    assert(charges(terminal.entity)==19)
    boot()
    assert(tick().near and tick().remote_linked)
    -- Deadlines expire even when the entity's own Lua tick was not running.
    advance(36001)
    assert(not tick().near and not tick().remote_linked and #EntityGetWithTag("nh_remote_station")==0)
    assert(#EntityGetWithTag("noita_hideout_home_wand_edit")==0)

    -- The throw edge is captured before the engine switches the inventory on.
    inventory_open=false
    held=terminal.entity
    tick()
    tick()
    local post=OnWorldPostUpdate
    OnWorldPostUpdate=function() inventory_open=true; post() end
    local linked=tick(nil,nil,nil,"right")
    OnWorldPostUpdate=post
    assert(linked.near and linked.remote_linked and charges(held)==18)
    EntitySetTransform(player,1400,-85)
    inventory_open=false
    tick()
    tick()
    ComponentSetValue2(EntityGetFirstComponentIncludingDisabled(held,"ItemComponent"),"uses_remaining",1)
    pending=tick(nil,nil,nil,"right")
    assert(pending.remote_linked and not EntityGetIsAlive(terminal.entity))
    inventory_open=true
    assert(tick().near)
    tick(nil,"move_pouch",deposit)
    assert(starter().location=="warehouse")
    OnPlayerDied()
    new_world()
    EntitySetTransform(player,1000,-85)
    inventory_open=true
    assert(not tick().near and not tick().remote_linked)
end
testRemoteTerminal()
print("Controller: remote deployment, payment rollback, range access, save/continue, expiry and last-charge use passed.")
do
    settings,flags={},{}
    new_world()
    tick()
    local original=EntityLoad
    local shots=0
    function EntityLoad(path,x,y)
        local id=original(path,x,y)
        if path==NHGuns.types.derringer.projectile then
            EntityAddComponent2(id,"ProjectileComponent",{})
            EntityAddComponent2(id,"VelocityComponent",{})
        end
        return id
    end
    function DEBUG_GetMouseWorld() return 320,-85 end
    function GameShootProjectile() shots=shots+1 end
    local id=EntityLoad("mods/noita_hideout/files/items/derringer.xml",227,-85)
    GamePickUpInventoryItem(player,id)
    held=id
    local item=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
    item.uses_remaining=4
    inventory_open=true
    tick(nil,nil,nil,"left")
    inventory_open=false
    tick(nil,nil,nil,"left")
    assert(shots==0)
    tick()
    for i=1,4 do
        tick(nil,nil,nil,"left")
        tick(nil,nil,nil,"left")
        assert(shots==i)
        if i<4 then assert(item.uses_remaining==4-i and EntityGetIsAlive(id)) end
        tick()
    end
    assert(not EntityGetIsAlive(id))
    EntityLoad=original
end
do
    settings,flags={},{}
    new_world()
    inventory_open=true
    tick()
    local target
    NHUI.quickTarget=function() return target end
    function InputIsKeyDown(key) return keys[key] end
    local function click(slot,key)
        target=slot
        tick()
        return tick(key or 225,nil,nil,"left")
    end
    local function carried(id)
        for _,slot in ipairs(model.native_slots) do if slot.entity==id then return slot end end
    end
    local function stock(container)
        local row=state()[container][1]
        return {key=container=="safe" and "valuable" or "warehouse",entity=row.id,kind=row.item.kind,safeSlot=row.slot}
    end
    local id=EntityLoad("mods/noita_hideout/files/items/fire_tube.xml",227,-85)
    GamePickUpInventoryItem(player,id)
    entities[id].comps.ItemComponent.uses_remaining=14
    tick()
    click(carried(id))
    assert(not EntityGetIsAlive(id) and state().warehouse[1].item.count==3)
    click(stock("warehouse"),229)
    local toolId=GameGetAllInventoryItems(player)[1]
    assert(entities[toolId].comps.ItemComponent.uses_remaining==2 and state().warehouse[1].item.count==2)
    tick(229,nil,nil,"left")
    assert(state().warehouse[1].item.count==2 and not controls.mButtonDownLeftClick)
    for x=1,3 do
        local filler=EntityLoad("mods/noita_hideout/files/items/bandage.xml",227,-85)
        GamePickUpInventoryItem(player,filler)
        entities[filler].comps.ItemComponent.slotX=x
    end
    fail_commit=true
    click(stock("warehouse"))
    fail_commit=false
    assert(state().warehouse[1].item.count==2 and entities[toolId].comps.ItemComponent.uses_remaining==2)
    click(stock("warehouse"))
    assert(#state().safe==0 and state().warehouse[1].item.count==1 and entities[toolId].comps.ItemComponent.uses_remaining==8)
    EntitySetTransform(player,1000,-85)
    tick()
    click(carried(toolId))
    assert(#state().safe==1 and state().safe[1].item.remaining==2 and state().safe[1].item.count==2 and state().warehouse[1].item.count==1)
    click(stock("safe"))
    assert(#state().safe==0 and #GameGetAllInventoryItems(player)==4)
end
print("Shift-click routes between inventory, warehouse and safe, splits one worn tube and claims each press once.")

do
    settings,flags={},{}
    new_world()
    tick()
    dofile("mods/noita_hideout/files/bag_pickup.lua")
    function EntityGetInRadius(x,y,r)
        local list={}
        for id,e in pairs(entities) do
            if (x-e.x)^2+(y-e.y)^2<=r*r then list[#list+1]=id end
        end
        return list
    end
    local function bag(kind,count,slot)
        local id=EntityLoad("mods/noita_hideout/files/items/"..kind..".xml",227,-85)
        local c=entities[id].comps.ItemComponent
        c.uses_remaining,c.is_pickable,c.next_frame_pickable,c.item_pickup_radius=count,true,0,14.1
        if slot then
            GamePickUpInventoryItem(player,id)
            c.slotX=slot
        end
        return id
    end
    local function press(shift)
        controls.mButtonDownInteract=true
        controls.mButtonFrameInteract=frame+1
        tick(shift and 225)
        controls.mButtonDownInteract=false
    end
    local pack=bag("travel_pack",3,0)
    local satchel=bag("travel_satchel",7,1)
    bag("bandage",1,2)
    local extra=bag("travel_satchel",2,3)
    item_pickup(extra,player)
    assert(entities[satchel].comps.ItemComponent.uses_remaining==7)
    tick()
    assert(not entities[extra] and entities[satchel].comps.ItemComponent.uses_remaining==9)
    bag("bandage",1,3)
    local ground=bag("travel_pack",2)
    press()
    assert(not entities[ground] and entities[pack].comps.ItemComponent.uses_remaining==5)
    local box=bag("loot_case",3)
    press()
    assert(not entities[box] and state().safe[1].item.kind=="loot_case" and state().safe[1].item.count==3)
    EntityKill(satchel)
    box=bag("loot_case",2)
    press()
    assert(not entities[box] and state().safe[1].item.count==5)
    box=bag("loot_case",1)
    fail_commit=true
    press(true)
    fail_commit=false
    assert(entities[box] and state().safe[1].item.count==5)
    press(true)
    assert(not entities[box] and state().safe[1].item.count==6)
    ground=bag("travel_pack",1)
    press(true)
    assert(entities[ground] and entities[pack].comps.ItemComponent.uses_remaining==5)
    EntityAddComponent2(ground,"ItemCostComponent",{cost=20})
    press()
    assert(entities[ground] and entities[pack].comps.ItemComponent.uses_remaining==5)

    inventory_open=true
    tick()
    local target
    NHUI.quickTarget=function() return target end
    local function shiftClick(container)
        local row=state()[container][1]
        target={key=container=="safe" and "valuable" or "warehouse",entity=row.id,kind=row.item.kind,safeSlot=row.slot}
        tick()
        tick(225,nil,nil,"left")
    end
    shiftClick("safe")
    local heldBox=bag("loot_case",3,1)
    fail_commit=true
    shiftClick("warehouse")
    fail_commit=false
    assert(state().warehouse[1].item.count==6 and entities[heldBox].comps.ItemComponent.uses_remaining==3)
    shiftClick("warehouse")
    assert(state().warehouse[1].item.count==5 and entities[heldBox].comps.ItemComponent.uses_remaining==4)
    assert(entities[pack].comps.ItemComponent.uses_remaining==5)

    inventory_open=false
    EntityKill(ground)
    EntityKill(heldBox)
    tick()
    local medicine=bag("bandage",3)
    local neighbour=bag("loot_case",2)
    local post=OnWorldPostUpdate
    OnWorldPostUpdate=function()
        controls.mButtonDownInteract,controls.mButtonFrameInteract=true,frame
        GamePickUpInventoryItem(player,medicine)
        local c=entities[medicine].comps.ItemComponent
        c.slotX,c.mFramePickedUp=1,frame
        post()
    end
    tick(225)
    OnWorldPostUpdate=post
    assert(not entities[medicine] and state().safe[1].item.kind=="bandage" and state().safe[1].item.count==1 and state().safe[1].item.remaining==3)
    tick()
    assert(entities[neighbour] and state().safe[1].item.remaining==3)
end
print("Mixed ground pickups, full quickbar, secure stacks, explicit secure pickup and rollback passed.")

do
    settings,flags={},{}
    new_world()
    local s=state()
    local row={id=s.nextItemId,slot=1,item=NHLootBags.item("loot_case",2)}
    s.nextItemId=s.nextItemId+1
    s.warehouse={row}
    assert(NHStore.commit(s))
    boot()
    local rng=ProceduralRandomi
    local rolls
    function ProceduralRandomi(x,y,lo,hi)
        if not rolls then return rng(x,y,lo,hi) end
        local result=table.remove(rolls,1)
        assert(result and result>=lo and result<=hi)
        return result
    end
    local function open(action,ref)
        tick()
        -- Regen-mana dose and a salvage bell, with neither optional card.
        rolls={100,2,100,100,1,1}
        tick(nil,action,ref,"right")
        assert(#rolls==0)
        rolls=nil
    end
    inventory_open=true
    tick()
    local ref={container="warehouse",slot=1,storedId=row.id,kind="loot_case",count=2}
    fail_commit=true
    open("use_inventory",ref)
    fail_commit=false
    assert(state().warehouse[1].item.count==2 and #EntityGetWithTag("noita_hideout_dose")==0)
    assert(#EntityGetWithTag("noita_hideout_salvage_bell")==0)
    advance(61)
    open("use_inventory",ref)
    local dose=assert(EntityGetWithTag("noita_hideout_dose")[1])
    local left,subtype=NHDoses.remaining(state(),dose)
    assert(left==5 and subtype=="regen_mana" and state().warehouse[1].item.count==1)
    assert(#EntityGetWithTag("noita_hideout_salvage_bell")==1)
    local source={container="warehouse",kind="loot_case",safeSlot=1,storedId=row.id,parent=quick,lane="tool",xslot=0,yslot=0}
    tick(nil,"secure_withdraw",source)
    held=assert(EntityGetWithTag("noita_hideout_loot_case")[1])
    inventory_open=false
    tick()
    open()
    assert(not EntityGetIsAlive(held) and #EntityGetWithTag("noita_hideout_dose")==2)
    assert(#EntityGetWithTag("noita_hideout_salvage_bell")==2)
    assert(NHDoses.reconcile(state(),player) and #EntityGetWithTag("noita_hideout_dose")==2)
    GamePickUpInventoryItem(player,dose)
    held=dose
    for expected=4,0,-1 do
        tick()
        tick(nil,nil,nil,"right")
        if expected>0 then assert(NHDoses.remaining(state(),dose)==expected) end
    end
    assert(not EntityGetIsAlive(dose))
    ProceduralRandomi=rng
end

do
    settings,flags={},{}
    new_world()
    local nativeLoad=EntityLoad
    function EntityLoad(path,x,y)
        local id=nativeLoad(path,x,y)
        local e=entities[id]
        if path:find("/relic_effects/",1,true) then
            e.name=path:match("([^/]+)%.xml$")
            EntityAddTag(id,"nh_chain_effect")
        elseif path:find("data/entities/items/pickup/",1,true) then
            e.file=path
            EntityAddTag(id,"item_physics")
            if path:match("/safe_haven%.xml$") then
                EntityAddComponent2(id,"VariableStorageComponent",{name="throw_time",value_int=-1})
                e.comps.ItemComponent.item_name="$item_safe_haven"
                e.comps.ItemComponent.ui_sprite="data/ui_gfx/items/safe_haven.png"
            else EntityAddTag(id,"item_pickup") end
            if path:match("/physics_gold_orb%.xml$") then
                EntityAddComponent2(id,"VariableStorageComponent",{_tags="kick_count",name="kick_count",value_int=0})
            end
        elseif path:find("data/entities/items/books/",1,true) then
            e.file=path
            local forged=path:find("base_forged",1,true)
            EntityAddTag(id,"tablet")
            EntityAddTag(id,forged and "forged_tablet" or "normal_tablet")
            local comp=e.comps.ItemComponent
            comp.item_name=forged and "$booktitle01" or "$booktitle07"
            comp.ui_description=forged and "$bookdesc01" or "$bookdesc07"
            comp.ui_sprite="data/ui_gfx/items/"..(forged and "laboratory" or "emerald").."_tablet.png"
            EntityAddComponent2(id,"AbilityComponent",{throw_as_item=true})
            EntityAddComponent2(id,"UIInfoComponent",{})
        end
        return id
    end
    local s=state()
    s.bankGold,s.resources.fiber=25,2
    assert(NHStore.startOrder(s,"relic_chain") and s.bankGold==0 and not s.resources.fiber)
    assert(NHStore.advanceProduction(s,{run=s.runSerial,orderId=s.order.id,progress=s.order.required}))
    local chain=s.warehouse[1]
    assert(chain.item.kind=="relic_chain" and NHStore.commit(s))
    boot()
    inventory_open=true
    tick()
    local function storeChain(from,to)
        tick(nil,"move_relic",{container=from,source=from,destination=to,kind="relic_chain",from=1,safeSlot=1,entity=chain.id})
    end
    local function openChain()
        tick(nil,"open_container",{kind="relic_chain",container="safe",entity=chain.id,safeSlot=1})
        assert(tick().chainId==chain.id)
    end
    local function effects() return #EntityGetAllChildren(player,"nh_chain_effect") end
    local function toolSlot(id)
        return {parent=quick,lane="tool",xslot=0,yslot=0,entity=id,chainId=chain.id,targetCell=1}
    end
    storeChain("warehouse","safe")
    openChain()
    assert(model.pouchCapacity==1 and not model.perkCapacity)
    local poop=EntityLoad("data/entities/items/pickup/poopstone.xml",227,-85)
    GamePickUpInventoryItem(player,poop)
    assert(NHTransfers.item_kind(poop)~="relic")
    tick(nil,"reject_relic",toolSlot(poop))
    assert(EntityGetRootEntity(poop)==player and not state().safe[1].item.cells[1])
    EntityKill(poop)
    local fire=EntityLoad("data/entities/items/pickup/brimstone.xml",227,-85)
    GamePickUpInventoryItem(player,fire)
    assert(NHTransfers.item_kind(fire)=="relic")
    local ok
    fail_commit=true
    ok=NHTransfers.deposit(state(),player,"safe",fire,1,nil,{container="safe",slot=1,id=chain.id})
    fail_commit=false
    assert(not ok and EntityGetRootEntity(fire)==player and not state().safe[1].item.cells[1])
    tick(nil,"place",toolSlot(fire))
    local socket=assert(state().safe[1].item.cells[1])
    assert(not entities[fire] and socket.item.relic=="brimstone" and effects()==1)
    assert(tick().secure_loot[1].relics[1]=="1. "..GameTextGetTranslatedOrNot(socket.item.name))
    storeChain("safe","warehouse")
    assert(effects()==0 and not tick().chainId and state().warehouse[1].item.cells[1].id==socket.id)
    assert(model.warehouse.equipment[1].relics[1]=="1. "..GameTextGetTranslatedOrNot(socket.item.name))
    local native={parent=quick,lane="tool",xslot=0,yslot=0,container="warehouse",kind="relic_chain",storedId=chain.id,safeSlot=1}
    tick(nil,"secure_withdraw",native)
    local carried=assert(EntityGetWithTag("noita_hideout_relic_chain")[1])
    native.entity,native.container=carried,"safe"
    tick(nil,"place",native)
    assert(state().safe[1].id==chain.id and effects()==1)
    OnPlayerDied()
    assert(effects()==0)
    new_world()
    inventory_open=true
    tick()
    openChain()
    assert(effects()==1 and model.cells[1].id==socket.id)
    local take={parent=quick,lane="tool",xslot=0,yslot=0,chainId=chain.id,sourceCell=1,storedId=socket.id}
    tick(nil,"take_relic",take)
    assert(effects()==0 and not state().safe[1].item.cells[1])
    local result=assert(EntityGetAllChildren(quick)[1])
    assert(EntityGetFilename(result)=="data/entities/items/pickup/brimstone.xml")
    native.entity,native.container,native.kind=result,"warehouse","relic"
    tick(nil,"place",native)
    local stored=assert(state().warehouse[1])
    local move={source="warehouse",container="warehouse",from=1,entity=stored.id,targetCell=1,chainId=chain.id}
    entities[player].x=900
    tick(nil,"move_chain_relic",move)
    assert(state().warehouse[1].id==stored.id and effects()==0)
    entities[player].x=227
    tick(nil,"move_chain_relic",move)
    assert(not state().warehouse[1] and state().safe[1].item.cells[1].id==stored.id and effects()==1)
    move={destination="warehouse",container="warehouse",safeSlot=1,entity=stored.id,sourceCell=1,chainId=chain.id}
    tick(nil,"move_chain_relic",move)
    assert(state().warehouse[1].id==stored.id and effects()==0)
    for _,path in ipairs({"data/entities/items/pickup/brimstone.xml","data/entities/items/pickup/wandstone.xml",
        "data/entities/items/pickup/safe_haven.xml","data/entities/items/pickup/beamstone.xml",
        "data/entities/items/pickup/physics_gold_orb.xml","mods/noita_hideout/files/items/relic_chain.xml",
        "data/entities/items/books/book_07.xml","data/entities/items/books/base_forged.xml"}) do
        settings,flags={},{}
        new_world()
        inventory_open=true
        local function shiftClick(slot)
            assert(slot)
            NHUI.quickTarget=function() return slot end
            tick()
            tick(225,nil,nil,"left")
        end
        local physical={}
        for x=0,1 do
            local id=EntityLoad(path,227,-85)
            if path:match("/physics_gold_orb%.xml$") then
                entities[id].comps.VariableStorageComponentkick_count.value_int=4+x
            elseif path:match("/safe_haven%.xml$") then
                entities[id].file="data/entities/player.xml"
            end
            if EntityHasTag(id,"forged_tablet") then
                local number=x==0 and "02" or "10"
                entities[id].comps.ItemComponent.item_name="$booktitle"..number
                entities[id].comps.ItemComponent.ui_description="$bookdesc"..number.."_forged"
            end
            GamePickUpInventoryItem(player,id)
            entities[id].comps.ItemComponent.slotX=x
            physical[x+1]=id
        end
        for i,id in ipairs(physical) do
            local slot
            for _,entry in ipairs(tick().native_slots) do if entry.entity==id then slot=entry end end
            shiftClick(slot)
            assert(not EntityGetIsAlive(id) and #state().warehouse==i)
            if i==1 then assert(EntityGetIsAlive(physical[2])) end
        end
        local rows=state().warehouse
        assert(rows[1].slot~=rows[2].slot and rows[1].id~=rows[2].id)
        if rows[1].item.kind=="native_valuable" then
            local row=rows[1]
            tick(nil,"move_relic",{kind=row.item.kind,entity=row.id,source="warehouse",destination="safe",from=row.slot,safeSlot=1})
            assert(state().safe[1].id==row.id)
            tick(nil,"move_relic",{kind=row.item.kind,entity=row.id,source="safe",destination="warehouse",from=1,safeSlot=row.slot})
            assert(#state().safe==0 and #state().warehouse==2)
        end
        for i,row in ipairs(rows) do
            boot()
            tick()
            assert(model.warehouse.equipment[row.slot].id==row.id)
            shiftClick({key="warehouse",entity=row.id,kind=row.item.kind,safeSlot=row.slot})
            assert(#GameGetAllInventoryItems(player)==i and #state().warehouse==2-i)
        end
        boot()
        tick()
        assert(#GameGetAllInventoryItems(player)==2 and #state().warehouse==0)
        if path:match("/physics_gold_orb%.xml$") then
            local counts={}
            for _,id in ipairs(GameGetAllInventoryItems(player)) do
                counts[entities[id].comps.VariableStorageComponentkick_count.value_int]=true
                assert(EntityGetFilename(id)==path)
            end
            assert(counts[4] and counts[5])
        elseif path:match("/safe_haven%.xml$") then
            local id=GameGetAllInventoryItems(player)[1]
            entities[id].comps.VariableStorageComponent.value_int=GameGetFrameNum()
            assert(not NHTransfers.deposit(state(),player,"warehouse",id))
            assert(EntityGetIsAlive(id) and #state().warehouse==0)
        end
        if path:find("/books/",1,true) then
            local descriptions={}
            for _,id in ipairs(GameGetAllInventoryItems(player)) do
                assert(NHTransfers.item_kind(id)=="tablet" and EntityGetFilename(id)==path)
                assert(entities[id].comps.AbilityComponent.throw_as_item)
                local item=entities[id].comps.ItemComponent
                descriptions[item.ui_description]=true
                if EntityHasTag(id,"forged_tablet") then assert(entities[id].comps.UIInfoComponent.name==item.item_name) end
            end
            if path:find("base_forged",1,true) then assert(descriptions["$bookdesc02_forged"] and descriptions["$bookdesc10_forged"])
            else assert(descriptions["$bookdesc07"]) end
        end
    end
    local key=EntityLoad("data/entities/items/pickup/key.xml",227,-85)
    assert(not NHTransfers.item_kind(key))
    settings,flags={},{}
    new_world()
    tick()
    for x=0,3 do
        local id=EntityLoad("mods/noita_hideout/files/items/bandage.xml",227,-85)
        GamePickUpInventoryItem(player,id)
        entities[id].comps.ItemComponent.slotX=x
        entities[id].comps.ItemComponent.uses_remaining=8
    end
    local function pickup()
        controls.mButtonDownInteract=true
        controls.mButtonFrameInteract=frame+1
        tick()
        controls.mButtonDownInteract=false
    end
    local function groundStone()
        local id=EntityLoad("data/entities/items/pickup/brimstone.xml",227,-85)
        local item=entities[id].comps.ItemComponent
        item.is_pickable,item.next_frame_pickable,item.item_pickup_radius=true,0,14
        return id
    end
    local first=groundStone()
    pickup()
    local row=assert(state().safe[1])
    assert(not EntityGetIsAlive(first) and row.item.relic=="brimstone")
    local second=groundStone()
    pickup()
    assert(EntityGetIsAlive(second) and #state().safe==1)
    inventory_open=true
    tick()
    NHUI.quickTarget=function() return {key="valuable",entity=row.id,kind="relic",safeSlot=row.slot} end
    tick(225,nil,nil,"left")
    assert(#state().safe==0 and state().warehouse[1].id==row.id)
    inventory_open=false
    tick()
    pickup()
    boot()
    tick()
    local saved=state()
    assert(not EntityGetIsAlive(second) and saved.safe[1].item.relic=="brimstone"
        and saved.warehouse[1].item.relic=="brimstone" and saved.safe[1].id~=saved.warehouse[1].id)
    EntityLoad=nativeLoad
end
print("Relic chain crafting, rejection, transfer rollback, contents, effects and death persistence passed.")

do
    settings,flags={},{}
    new_world()
    inventory_open=true
    local shown
    NHUI.showTransfer=function(container,kind,slot)
        assert(kind=="potion")
        shown=container.."/"..slot
    end
    NHPotion.capture=function(id) return entities[id].record end
    NHPotion.restore=function(record,x,y)
        local path="data/entities/items/pickup/"..(record.variant or "potion")..".xml"
        local id=EntityLoad(path,x,y)
        entities[id].file,entities[id].record=path,record
        EntityAddTag(id,"potion")
        return id
    end
    local function click(slot)
        assert(slot)
        shown=nil
        NHUI.quickTarget=function() return slot end
        tick()
        tick(225,nil,nil,"left")
        return shown
    end
    local function carried(variant)
        local id=NHPotion.restore({kind="potion",variant=variant,capacity=1000,materials={water=25}},227,-85)
        GamePickUpInventoryItem(player,id)
        for _,slot in ipairs(tick().native_slots) do if slot.entity==id then return slot end end
    end
    local function stored(container,row)
        return {key=container,entity=row.id,kind=row.item.kind,safeSlot=row.slot}
    end
    local flask=carried("jar")
    fail_commit=true
    assert(not click(flask) and EntityGetIsAlive(flask.entity) and #state().docks==0)
    fail_commit=false
    assert(click(flask)=="docks/1")
    assert(click(carried("powder_stash"))=="docks/2")
    assert(click(carried(nil))=="warehouse/1")
    local s=state()
    assert(#s.docks==2 and s.docks[1].item.variant=="jar" and s.docks[2].item.variant=="powder_stash")
    assert(s.warehouse[1].item.materials.water==25 and not next(s.materials))
    local dock=s.docks[1]
    assert(not click(stored("docks",dock)) and #state().docks==1 and #GameGetAllInventoryItems(player)==1)
    entities[player].x=1000
    local hand
    for _,slot in ipairs(tick().native_slots) do if slot.entity then hand=slot end end
    assert(click(hand)=="safe/1")
    entities[player].x=227
    assert(click(stored("valuable",state().safe[1]))=="docks/1")
    entities[player].x=1000
    assert(click(carried("powder_stash"))=="safe/1")
    entities[player].x=227
    assert(click(stored("valuable",state().safe[1]))=="warehouse/2")
    assert(#state().safe==0 and #state().warehouse==2 and #state().docks==2)
end
print("Shift-click docks compatible containers, falls back to storage and reveals only committed placements.")

do
    settings,flags={},{}
    new_world()
    inventory_open=true
    function ComponentObjectGetValue2(c,group,key) return c[group][key] end
    function ComponentObjectSetValue2(c,group,key,v) c[group]=c[group] or {}; c[group][key]=v end
    function GetUpdatedEntityID() return player end
    local mana=false
    function GameGetGameEffectCount(_,effect) return effect=="MANA_REGENERATION" and mana and 1 or 0 end
    local dm=EntityAddComponent2(player,"DamageModelComponent",{hp=4,max_hp=4,damage_multipliers={ice=.5,poison=1}})
    local s=state()
    s.insuranceActive,s.insuranceSerial=true,1
    s.resources.arcane_scrap,s.bankGold=13,10
    for _,id in ipairs({"shield_frost","shield_charger"}) do
        assert(NHStore.startOrder(s,id))
        assert(NHStore.advanceProduction(s,{run=s.runSerial,orderId=s.order.id,progress=s.order.required}))
    end
    for _,row in ipairs(s.warehouse) do row.item.icon=NHShields.legacyIcons[row.item.kind] end
    assert(NHStore.commit(s))
    boot()
    tick()
    local sh,ch=s.warehouse[1],s.warehouse[2]
    local function equip(row)
        tick(nil,"move_gear",{source="warehouse",destination="gear",container="warehouse",kind=row.item.kind,from=row.slot,entity=row.id})
    end
    local shown
    NHUI.showTransfer=function(dest) shown=dest end
    local function quickEquip(row)
        NHUI.quickTarget=function() return {key="warehouse",safeSlot=row.slot,kind=row.item.kind,entity=row.id} end
        tick()
        tick(225,nil,nil,"left")
        assert(shown=="gear")
        shown=nil
    end
    quickEquip(sh)
    quickEquip(ch)
    assert(tick().shield.cells==4 and model.shield.maxHp==dm.max_hp and model.gear.charger.count==1 and state().warehouse[1].item.count==3)
    assert(model.gear.shield.icon==NHShields.types.shield_frost.icon and model.gear.charger.icon==NHShields.chargers.shield_charger.icon)
    NHUI.quickTarget=function() return {key="warehouse",safeSlot=ch.slot,kind=ch.item.kind,entity=ch.id} end
    tick(225,nil,nil,"left")
    assert(state().warehouse[1].item.count==2 and state().gearCharger.item.count==1)
    local spare=assert(GameGetAllInventoryItems(player)[1])
    GameKillInventoryItem(player,spare)
    assert(dm.damage_multipliers.ice==0 and dm.damage_multipliers.poison==0 and EntityHasTag(player,"polymorphable_NOT"))
    local hook=assert(EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_shield_damage"))
    local shieldModule=dofile("mods/noita_hideout/files/shield_runtime.lua")
    local originalCount=GameGetGameEffectCount
    GameGetGameEffectCount=function(_,kind) return kind=="PROTECTION_POLYMORPH" and 2 or 0 end
    assert(not shieldModule.allowMimic(player) and EntityHasTag(player,"polymorphable_NOT"))
    GameGetGameEffectCount=originalCount
    assert(shieldModule.canMimic(player) and EntityHasTag(player,"polymorphable_NOT"))
    assert(shieldModule.allowMimic(player) and not EntityHasTag(player,"polymorphable_NOT"))
    assert(#(EntityGetAllChildren(player,"nh_shield_poly") or {})==0 and dm.damage_multipliers.ice==0)
    assert(tick().shield.charge==NHShields.cell*4 and EntityHasTag(player,"polymorphable_NOT"))
    do
        local equipped=state()
        local bare=state()
        bare.gearShield=nil
        local function join(id)
            assert(NHCompanions.summon(player,id,"en",function() return true end))
        end
        local function leave()
            local _,pet=NHCompanions.active(player)
            NHCompanions.clearSupport(player)
            EntityRemoveFromParent(pet)
            EntityKill(pet)
        end
        -- Shield first, companion first, and removal of either layer.
        for _,id in ipairs({"dog","bee"}) do
            local key=id=="dog" and "ice" or "poison"
            local baseline=id=="dog" and 0.5 or 1
            join(id)
            shieldModule.sync(bare,player)
            assert(dm.damage_multipliers[key]==0)
            leave()
            assert(dm.damage_multipliers[key]==baseline)
            join(id)
            shieldModule.sync(equipped,player)
            leave()
            assert(dm.damage_multipliers[key]==0)
            shieldModule.sync(bare,player)
            assert(dm.damage_multipliers[key]==baseline)
            shieldModule.sync(equipped,player)
        end
        join("minotaur")
        assert(#EntityGetAllChildren(player,"nh_shield_poly")==1)
        shieldModule.sync(bare,player)
        assert(EntityHasTag(player,"polymorphable_NOT") and shieldModule.allowMimic(player))
        shieldModule.sync(bare,player)
        assert(EntityHasTag(player,"polymorphable_NOT"))
        shieldModule.sync(equipped,player)
        assert(shieldModule.allowMimic(player) and not EntityHasTag(player,"polymorphable_NOT"))
        shieldModule.sync(equipped,player)
        leave()
        assert(EntityHasTag(player,"polymorphable_NOT"))
        shieldModule.sync(bare,player)
        EntityAddTag(player,"polymorphable_NOT")
        join("minotaur")
        assert(not shieldModule.allowMimic(player))
        leave()
        assert(EntityHasTag(player,"polymorphable_NOT"))
        EntityRemoveTag(player,"polymorphable_NOT")
        shieldModule.sync(equipped,player)
    end
    dofile(hook.script_damage_received)
    local function hit(amount)
        dm.hp=dm.hp-amount
        damage_received(amount)
    end
    hit(28)
    assert(dm.hp==4 and tick().shield.charge==NHShields.cell/2 and state().insuranceActive)
    local restart=frame
    boot()
    assert(tick().shield.charge==NHShields.cell/2)
    while frame<restart+179 do assert(tick().shield.charge==NHShields.cell/2) end
    mana=true
    for i=1,30 do tick() end
    assert(model.shield.charge==NHShields.cell)
    for i=1,359 do tick() end
    assert(model.shield.charge==NHShields.cell and model.shield.repair==359)
    assert(tick().shield.charge==2*NHShields.cell)
    hit(17)
    assert(dm.hp==3 and dm.damage_multipliers.ice==.5 and dm.damage_multipliers.poison==1 and EntityHasTag(player,"polymorphable_NOT"))
    mana=false
    local ref={kind="shield_charger",container="gear",storedId=state().gearCharger.id,count=1,remaining=8}
    tick(nil,"use_inventory",ref)
    advance(299)
    assert(model.surgery and model.surgery.elapsed==299 and state().gearCharger.item.remaining==8)
    fail_commit=true
    tick()
    fail_commit=false
    for i=1,65 do tick() end
    assert(state().gearCharger.item.remaining==8 and model.shield.charge==0)
    tick(nil,"use_inventory",ref)
    advance(300)
    assert(model.shield.charge==NHShields.cell and model.gear.charger.remaining==7 and dm.damage_multipliers.ice==0)
    local to={source="gear",destination="warehouse",container="warehouse",kind=sh.item.kind,entity=sh.id,safeSlot=1}
    tick(nil,"move_gear",to)
    assert(not tick().shield and not EntityHasTag(player,"polymorphable_NOT") and dm.damage_multipliers.ice==.5)
    assert(state().warehouse[NHStore.slotIndex(state(),"warehouse",1,sh.item.kind)].item.charge==NHShields.cell)
    local slot={parent=quick,lane="tool",xslot=0,yslot=0,container="warehouse",kind=sh.item.kind,storedId=sh.id,safeSlot=1}
    tick(nil,"secure_withdraw",slot)
    slot.entity=assert(GameGetAllInventoryItems(player)[1])
    slot.container,slot.intoGear="safe",true
    tick(nil,"place",slot)
    assert(tick().shield.charge==NHShields.cell and not EntityGetIsAlive(slot.entity))
    slot.storedId,slot.entity,slot.intoGear=state().gearShield.id,nil,nil
    tick(nil,"take_gear",slot)
    assert(not tick().shield and #GameGetAllInventoryItems(player)==1)
    for _,kind in ipairs({"shield_fire","shield_electric","shield_storm"}) do
        local profile=state()
        profile.resources.arcane_scrap=NHShields.types[kind].scrap
        assert(NHStore.startOrder(profile,kind))
        assert(NHStore.advanceProduction(profile,{run=profile.runSerial,orderId=profile.order.id,progress=profile.order.required}))
        assert(NHStore.commit(profile))
        boot()
        tick()
        equip(profile.warehouse[#profile.warehouse])
        local child=assert(EntityGetAllChildren(player,"nh_shield_elements")[1])
        assert(EntityGetName(child)==kind and (EntityHasTag(player,"polymorphable_NOT")== (kind=="shield_storm")))
        if kind~="shield_storm" then
            local effect=EntityGetFirstComponentIncludingDisabled(child,"GameEffectComponent")
            assert(effect.effect==(kind=="shield_fire" and "PROTECTION_FIRE" or "PROTECTION_ELECTRICITY"))
        end
    end
    mana=false
    hit(32) -- Four 2-HP cells with 75% resistance.
    assert(tick().shield.charge==0 and not EntityGetAllChildren(player,"nh_shield_elements")[1])
    local spice=EntityLoad("mods/noita_hideout/files/meal_spice.xml",0,0)
    EntityAddTag(spice,"noita_hideout_meal_spice")
    EntityAddChild(player,spice)
    for i=1,539 do tick() end
    assert(model.shield.charge==NHShields.cell and EntityGetAllChildren(player,"nh_shield_elements")[1])

    local profile=state()
    local old=profile.gearCharger
    assert(NHShields.move(profile,{source="gear",destination="warehouse",safeSlot=ch.slot,entity=old.id,kind=old.item.kind}))
    assert(NHStore.commit(profile))
    boot()
    tick()
    local kind="advanced_shield_charger"
    local physical=EntityLoad("mods/noita_hideout/files/items/"..kind..".xml",227,-85)
    GamePickUpInventoryItem(player,physical)
    local component=entities[physical].comps.ItemComponent
    component.slotX,component.uses_remaining,component.ui_sprite=1,19,NHShields.legacyIcons[kind]
    tick()
    assert(component.ui_sprite==NHShields.chargers[kind].icon and component.uses_remaining==19)
    local drag={entity=physical,parent=quick,lane="tool",xslot=1,yslot=0,intoGear=true,safeSlot=2,container="safe",kind=kind}
    fail_commit=true
    tick(nil,"place",drag)
    fail_commit=false
    assert(not state().gearCharger and EntityGetIsAlive(physical) and component.uses_remaining==19)
    tick(nil,"place",drag)
    assert(not EntityGetIsAlive(physical) and state().gearCharger.item.remaining==3)
    local remainder
    for _,slot in ipairs(tick().native_slots) do if slot.kind==kind then remainder=slot end end
    assert(remainder and remainder.xslot==1 and remainder.count==2 and remainder.remaining==8)
    local native={container="native",kind=kind,parent=quick,entity=remainder.entity,lane="tool",xslot=1,yslot=0,count=2,remaining=8}
    tick(nil,"use_inventory",native)
    advance(119)
    assert(model.surgery and model.surgery.elapsed==119 and entities[native.entity].comps.ItemComponent.uses_remaining==16)
    tick()
    assert(model.shield.charge==4*NHShields.cell and entities[native.entity].comps.ItemComponent.uses_remaining==15)
    tick(nil,"use_inventory",native)
    assert(not model.surgery and state().gearCharger.item.remaining==3)
end
print("Shield controller: equip, damage, reload, mana recharge, paid repair, typed immunity and physical transfer passed.")

do
    settings,flags={},{}
    new_world()
    inventory_open=true
    local profile=state()
    EntityAddComponent2(player,"DamageModelComponent",{hp=4,max_hp=4})
    profile.resources.arcane_scrap,profile.bankGold=20,10
    for _,id in ipairs({"scatter_revolver","marksman_rifle","ammo_rig","ammo_pack"}) do
        assert(NHStore.startOrder(profile,id))
        assert(NHStore.advanceProduction(profile,{run=profile.runSerial,orderId=profile.order.id,progress=profile.order.required}))
    end
    assert(profile.resources.arcane_scrap==0 or not profile.resources.arcane_scrap)
    assert(profile.bankGold==0 and #profile.warehouse==4 and NHStore.commit(profile))
    boot()
    tick()
    local function shift(row)
        NHUI.quickTarget=function() return {key="warehouse",safeSlot=row.slot,kind=row.item.kind,entity=row.id} end
        tick()
        tick(225,nil,nil,"left")
    end
    for _,row in ipairs(profile.warehouse) do shift(row) end
    assert(state().gearRig.item.reserve==0 and state().gearAmmo.item.count==1 and state().warehouse[1].item.count==3)
    local revolver,rifle
    for _,slot in ipairs(tick().native_slots) do
        if slot.kind=="scatter_revolver" then assert(slot.lane=="wand" and slot.rounds==36); revolver=slot end
        if slot.kind=="marksman_rifle" then assert(slot.lane=="wand" and slot.rounds==60); rifle=slot end
    end
    held=assert(revolver).entity
    assert(rifle and tick().ammo.rounds==36)
    do
        local icon=NHFirearms.items.scatter_revolver.icon
        local sprite=EntityAddComponent2(held,"SpriteComponent",{_tags="enabled_in_hand",image_file="mods/noita_hideout/files/items/scatter_revolver_world.png"})
        local item=entities[held].comps.ItemComponent
        item.ui_sprite=icon
        NHFirearms.repairGunSprite(held,"scatter_revolver")
        assert(sprite.has_special_scale and sprite.offset_x==4 and sprite.offset_y==8 and sprite.image_file==icon)
        assert(entities[held].comps.AbilityComponent.sprite_file==sprite.image_file and item.ui_sprite==icon)
        local previous=GetUpdatedEntityID
        GetUpdatedEntityID=function() return held end
        for _,pose in ipairs({{1,-1},{-1,1},{1,1}}) do
            entities[held].scaleX,entities[held].scaleY=pose[1],pose[2]
            dofile("mods/noita_hideout/files/equipment_sprite_mirror.lua")
            assert(sprite.special_scale_x==pose[1]*0.5 and sprite.special_scale_y==pose[2]*0.5)
        end
        local rifleSprite=EntityAddComponent2(rifle.entity,"SpriteComponent",{_tags="enabled_in_hand",image_file=NHFirearms.items.marksman_rifle.icon})
        NHFirearms.repairGunSprite(rifle.entity,"marksman_rifle")
        assert(rifleSprite.image_file=="mods/noita_hideout/files/items/rifle.png" and rifleSprite.offset_x==11 and rifleSprite.offset_y==10)
        GetUpdatedEntityID=function() return rifle.entity end
        entities[rifle.entity].scaleY=-1
        rifleSprite.special_scale_y=0.75
        dofile("mods/noita_hideout/files/equipment_sprite_mirror.lua")
        assert(rifleSprite.special_scale_y==-0.75 and rifleSprite.special_scale_x==0.5)
        GetUpdatedEntityID=previous
    end
    local cards=EntityGetAllChildren(held)
    assert(#cards==1 and entities[cards[1]].comps.ItemComponent.is_frozen)
    assert(entities[cards[1]].comps.ItemActionComponent.action_id=="NH_SCATTER_REVOLVER")
    do
        local lock=entities[cards[1]].comps.ItemComponent
        assert(lock.permanently_attached)
        lock.permanently_attached=false -- Old save with the original card still in place.
        local loose=EntityGetAllChildren(rifle.entity)[1]
        EntityRemoveFromParent(loose)
        advance(60-frame%60)
        assert(lock.permanently_attached and EntityGetAllChildren(held)[1]==cards[1])
        local repaired=EntityGetAllChildren(rifle.entity)
        assert(#repaired==1 and repaired[1]~=loose and EntityGetParent(loose)==0)
        local core=entities[repaired[1]].comps
        assert(core.ItemActionComponent.action_id=="NH_MARKSMAN_RIFLE" and core.ItemComponent.permanently_attached and core.ItemComponent.is_frozen)
        advance(60)
        assert(#EntityGetAllChildren(rifle.entity)==1 and EntityGetAllChildren(rifle.entity)[1]==repaired[1])
    end
    local paid=0
    function item_pickup(entity,owner)
        assert(owner==player)
        paid=paid+2*entities[entity].comps.VariableStorageComponent.value_int
        EntityKill(entity)
    end
    dofile("mods/noita_hideout/files/ammo_gold.lua")
    local function pickupGold(value)
        local gold=EntityLoad("gold.xml",227,-85)
        EntityAddTag(gold,"gold_nugget")
        EntityAddComponent2(gold,"VariableStorageComponent",{name="gold_value",value_int=value})
        item_pickup(gold,player)
    end
    pickupGold(5)
    pickupGold(45)
    assert(tick().ammo.reserve==50 and paid==100)
    boot()
    tick()
    assert(state().gearRig.item.reserve==50)
    local function usePack()
        local row=state().gearAmmo
        tick(nil,"use_inventory",{container="gear",kind=row.item.kind,storedId=row.id,count=1,remaining=row.item.remaining})
    end
    usePack()
    advance(119)
    assert(model.surgery and state().gearRig.item.reserve==50 and state().gearAmmo.item.remaining==8)
    tick()
    assert(state().gearRig.item.reserve==170 and state().gearAmmo.item.remaining==7)
    usePack()
    advance(120)
    assert(state().gearRig.item.reserve==240 and state().gearAmmo.item.remaining==6)
    usePack()
    assert(not tick().surgery and state().gearAmmo.item.remaining==6)

    actions={}
    dofile("mods/noita_hideout/files/firearm_actions.lua")
    local bullets=0
    function add_projectile(path)
        assert(path:find("mods/noita_hideout/files/projectiles/multi_",1,true))
        bullets=bullets+1
    end
    local function shot(n)
        c={spread_degrees=0,game_effect_entities="",extra_entities="",speed_multiplier=1}
        actions[n].action()
    end
    inventory_open=false
    tick()
    reflecting=true; shot(1); reflecting=false
    assert(tick().ammo.rounds==36)
    shot(1)
    advance(120)
    assert(model.ammo.rounds==35 and model.ammo.reserve==240)
    tick(21); advance(54)
    assert(model.ammo.rounds==36 and model.ammo.reserve==239)
    tick(5); tick(); tick(5); tick()
    assert(model.ammo.index==3)
    for count=1,6 do shot(1) end
    assert(tick().ammo.rounds==0 and bullets==50)
    advance(53)
    assert(model.ammo.rounds==0)
    tick()
    assert(model.ammo.rounds==36 and model.ammo.reserve==203)
    shot(1)
    held=rifle.entity; tick()
    for count=1,3 do shot(2) end
    assert(tick().ammo.rounds==57)
    inventory_open=true
    tick()
    local put={parent=quick,lane="wand",entity=revolver.entity,xslot=revolver.xslot,yslot=0,container="warehouse",safeSlot=1,kind="scatter_revolver"}
    tick(nil,"place",put)
    local at=assert(NHStore.slotIndex(state(),"warehouse",1,put.kind))
    local stored=state().warehouse[at]
    assert(stored.item.rounds==30 and stored.item.mode==3 and not EntityGetIsAlive(revolver.entity))
    boot(); tick(); shift(stored)
    for _,slot in ipairs(tick().native_slots) do if slot.kind==put.kind then held=slot.entity end end
    assert(tick().ammo.rounds==30 and model.ammo.index==3)
    for _,tier in ipairs({
        {"improved_ammo_rig","advanced_ammo_pack",480,360,9,30},
        {"advanced_ammo_rig","improved_ammo_pack",720,240,11,20},
    }) do
        settings,flags={},{}
        new_world()
        inventory_open=true
        EntityAddComponent2(player,"DamageModelComponent",{hp=4,max_hp=4})
        local s=state()
        s.resources.arcane_scrap,s.bankGold=tier[5],tier[6]
        for _,kind in ipairs({tier[1],tier[2]}) do
            assert(NHStore.startOrder(s,kind))
            assert(NHStore.advanceProduction(s,{run=s.runSerial,orderId=s.order.id,progress=s.order.required}))
        end
        assert(s.bankGold==0 and (s.resources.arcane_scrap or 0)==0 and NHStore.commit(s))
        boot()
        tick()
        for _,row in ipairs(s.warehouse) do shift(row) end
        tick()
        assert(model.gear.rig.icon==NHFirearms.rigs[tier[1]].icon and model.gear.ammo.icon==NHFirearms.packs[tier[2]].icon)
        assert(state().gearAmmo.item.count==1 and state().warehouse[1].item.count==3)
        usePack()
        advance(120)
        assert(state().gearRig.item.reserve==tier[4] and state().gearAmmo.item.remaining==7)
        pickupGold(1000)
        tick()
        assert(state().gearRig.item.reserve==tier[3])
        usePack()
        assert(not tick().surgery and state().gearAmmo.item.remaining==7)
        local slot={parent=quick,lane="tool",xslot=0,yslot=0,storedId=state().gearRig.id,kind=tier[1]}
        tick(nil,"take_gear",slot)
        slot.entity=assert(GameGetAllInventoryItems(player)[1])
        assert(NHTransfers.item_kind(slot.entity)==tier[1] and not state().gearRig)
        assert(EntityGetFirstComponentIncludingDisabled(slot.entity,"VariableStorageComponent","nh_reserve").value_int==tier[3])
        slot.container,slot.intoGear,slot.safeSlot="safe",true,3
        tick(nil,"place",slot)
        boot()
        assert(tick().gear.rig.reserve==tier[3] and state().gearAmmo.item.remaining==7)
        local box=EntityLoad("mods/noita_hideout/files/items/ammo_pack.xml",227,-85)
        GamePickUpInventoryItem(player,box)
        local item=EntityGetFirstComponentIncludingDisabled(box,"ItemComponent")
        item.ui_sprite,item.uses_remaining=NHFirearms.legacyIcons.ammo_pack,7
        tick()
        assert(item.ui_sprite==NHFirearms.packs.ammo_pack.icon and item.uses_remaining==7)
    end
    -- Store real workshop cards in the gun, withdraw it, and switch a full
    -- magazine through the player's key binding. Partial conversions never pay.
    settings,flags={},{}
    new_world()
    inventory_open=true
    local s=state()
    s.resources.arcane_scrap,s.bankGold=40,100
    for _,id in ipairs({"marksman_rifle","ammo_rig","ammo_mod_frost","ammo_mod_pierce"}) do
        assert(NHStore.startOrder(s,id))
        assert(NHStore.advanceProduction(s,{run=s.runSerial,orderId=s.order.id,progress=s.order.required}))
    end
    assert(NHStore.commit(s))
    boot()
    tick()
    local gun,rig,core,flight=unpack(s.warehouse)
    shift(rig)
    tick(nil,"open_container",{container="warehouse",entity=gun.id,kind=gun.item.kind,safeSlot=gun.slot})
    assert(tick().gunId==gun.id)
    local function fit(row,cell)
        tick(nil,"move_gun_attachment",{gunId=gun.id,container="warehouse",entity=row.id,from=row.slot,targetCell=cell})
    end
    fit(flight,1)
    assert(not tick().cells[1])
    fit(core,1)
    fit(flight,2)
    assert(tick().cells[1].id=="frost" and model.cells[2].id=="pierce")
    tick(nil,"move_gun_attachment",{gunId=gun.id,container="warehouse",entity="pierce",sourceCell=2,safeSlot=flight.slot})
    assert(not tick().cells[2])
    local returned=state().warehouse[2]
    assert(returned.item.card.id=="NH_AMMO_PIERCE")
    fit(returned,2)
    shift(gun)
    for _,slot in ipairs(tick().native_slots) do if slot.kind=="marksman_rifle" then held=slot.entity end end
    local profile=NHFirearms.profileComponent(held)
    assert(profile.name=="frost/pierce" and profile.value_string=="")
    inventory_open=false
    tick()
    assert(tick().ammo.rounds==60 and state().gearRig.item.reserve==0)
    tick(5); tick()
    assert(model.ammo.index==2 and profile.name=="frost/pierce")
    local mag=EntityGetFirstComponentIncludingDisabled(held,"VariableStorageComponent","nh_magazine")
    ComponentSetValue2(mag,"value_int",54)
    pickupGold(10); tick()
    assert(tick(21).ammo.loading==72)
    advance(72)
    assert(model.ammo.rounds==60 and model.ammo.reserve==4 and profile.name=="frost/pierce")
end
print("Firearms: recipes, shift equip, locked actions, nugget denominations, timed packs, both reload modes and storage passed.")

do
    settings,flags={},{}
    new_world()
    inventory_open=true
    local s=state()
    s.resources.arcane_scrap,s.bankGold=2,0
    assert(NHStore.commit(s))
    local dm=EntityAddComponent2(player,"DamageModelComponent",{hp=4,max_hp=4})
    local wallet=EntityAddComponent2(player,"WalletComponent",{money=153,mHasReachedInf=false})
    boot()
    tick()
    tick(nil,"shop_buy",{id="rescue_policy"})
    assert(state().insuranceActive and state().bankGold==0 and state().resources.arcane_scrap==1)
    assert(tick().rescue.insured and not model.rescue.species and model.rescue.kept==0)
    tick(nil,"shop_buy",{id="rescue_policy"})
    assert(state().resources.arcane_scrap==1)
    boot()
    tick()
    inventory_open=false
    assert(tick().rescue.insured, "Insurance HUD must remain visible outside inventory")
    EntitySetTransform(player,650,150)
    local hook=EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_shield_damage")
    assert(hook.script_damage_about_to_be_received==hook.script_damage_received)
    dofile(hook.script_damage_received)
    local life=EntityLoad("mods/noita_hideout/files/tarot_life.xml",650,150)
    EntityAddChild(player,life)
    local effect=EntityAddComponent2(life,"GameEffectComponent",{effect="RESPAWN",frames=-1,mIsSpent=false})
    local hit,critical=damage_about_to_be_received(7,0,0,0,25)
    assert(hit==7 and critical==25 and not ComponentGetIsEnabled(effect) and not effect.mIsSpent)
    dm.hp=-3
    damage_received(7)
    assert(dm.hp==2 and wallet.money==0)
    tick()
    local x,y=EntityGetTransform(player)
    local cabin=dofile("mods/noita_hideout/files/travel/cabin.lua")
    local mx,my=cabin.point(cabin.infirmary)
    assert(x==mx and y==my and not state().insuranceActive and state().closedThrough<state().runSerial)
    assert(ComponentGetIsEnabled(effect) and not effect.mIsSpent)
    local cases=EntityGetWithTag("noita_hideout_lost_gold_case")
    local case=assert(cases[1])
    assert(#cases==1 and entities[case].x==650 and entities[case].y==150)
    assert(EntityGetFirstComponentIncludingDisabled(case,"VariableStorageComponent","nh_lost_gold").value_string=="153")
    boot()
    tick()
    assert(not dm.wait_for_kill_flag_on_death and #EntityGetWithTag("noita_hideout_lost_gold_case")==1)
end
print("Insurance shop, reload, damage callback, preserved run and exact lost-gold cache passed.")

do
    settings,flags={},{}
    new_world()
    local s=state()
    s.safe={}
    s.warehouse={{id=s.nextItemId,slot=1,item=NHCompanions.withCount({species="tarot_garden",remaining=40},2)}}
    s.nextItemId=s.nextItemId+1
    local shield=NHShields.order[1]
    s.gearShield={id=s.nextItemId,item={kind=shield,charge=0,repair=0,delay=0}}
    s.gearRig={id=s.nextItemId+1,item={kind="ammo_rig",reserve=0}}
    s.nextItemId=s.nextItemId+2
    assert(NHStore.commit(s))
    local dm=EntityAddComponent2(player,"DamageModelComponent",{hp=2,max_hp=4,max_hp_cap=0})
    boot()
    inventory_open=true
    tick()
    local card=state().warehouse[1]
    tick(nil,"use_inventory",{container="warehouse",slot=1,storedId=card.id,kind="summon_card",species="tarot_garden",remaining=40,count=2})
    assert(dm.max_hp==6 and dm.hp==4)
    s=state()
    assert(s.warehouse[1].item.count==1 and s.warehouse[1].item.remaining==40)
    assert(s.warehouse[2].item.count==1 and s.warehouse[2].item.remaining==39)
    assert(s.gearRig.item.reserve==240)
    local meter=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_equipped_shield")
    assert(meter.value_int==NHShields.types[shield].cells*NHShields.cell)
    -- A worn tarot card survives physical withdrawal and can be used again.
    local target=tool()
    target.safeSlot,target.storedId,target.container=2,s.warehouse[2].id,"warehouse"
    target.kind="summon_card"
    tick(nil,"secure_withdraw",target)
    local physical=assert(EntityGetWithTag("nh_companion_tarot_garden")[1])
    assert(entities[physical].comps.ItemComponent.uses_remaining==39)
    held=physical
    inventory_open=false
    tick()
    tick(nil,nil,nil,"right")
    assert(entities[physical].comps.ItemComponent.uses_remaining==38 and dm.max_hp==9)
end
print("Tarot controller: stored and carried use consume one charge, refill gear and preserve worn cards.")

for _,location in ipairs({"warehouse","held"}) do
    settings,flags={},{}
    new_world()
    local s=state()
    local kind="advanced_supply_pack"
    local row={id=s.nextItemId,slot=1,item=NHLootBags.item(kind,2)}
    s.warehouse={row}
    s.gearShield={id=row.id+1,item={kind="shield_basic",charge=0,repair=0,delay=0}}
    s.gearRig={id=row.id+2,item={kind="ammo_rig",reserve=0}}
    s.nextItemId=row.id+3
    assert(NHStore.commit(s))
    boot()
    inventory_open=true
    tick()
    local rng=ProceduralRandomi
    function ProceduralRandomi(_,_,lo,hi) return hi end
    if location=="warehouse" then
        tick(nil,"use_inventory",{container=location,slot=1,storedId=row.id,kind=kind,count=2})
        assert(state().warehouse[1].item.count==1)
    else
        local target=tool()
        target.safeSlot,target.storedId,target.container,target.kind=1,row.id,"warehouse",kind
        tick(nil,"secure_withdraw",target)
        held=assert(EntityGetWithTag("noita_hideout_"..kind)[1])
        inventory_open=false
        tick()
        tick(nil,nil,nil,"right")
        assert(entities[held].comps.ItemComponent.uses_remaining==1)
    end
    ProceduralRandomi=rng
    assert(state().gearRig.item.reserve==240)
    assert(tick().shield.charge==NHShields.types.shield_basic.cells*NHShields.cell)
    assert(#EntityGetWithTag("noita_hideout_advanced_shield_charger")==1 and #EntityGetWithTag("noita_hideout_advanced_ammo_pack")==1)
end

do
    settings,flags={},{}
    new_world()
    local s=state()
    s.bankGold=5000
    s.materials={midas=1,water=200}
    s.resources={arcane_scrap=1,container_scrap=1}
    assert(NHStore.commit(s))
    boot()
    inventory_open=true
    local offer=assert(has_project(tick().recipes,"philosopher_stone"))
    assert(offer.alchemyMode=="rubedo" and offer.ready and #offer.inputs==4 and offer.outputs[1].amount==10)
    tick(nil,"craft",{id="philosopher_stone"})
    assert(state().bankGold==0 and state().resources.nh_philosopher_stone==10 and not state().materials.midas)
    tick(nil,"craft",{id="rubedo_immortality"})
    boot()
    local view=tick()
    local materials={}
    for _,row in ipairs(view.materials) do materials[row.key]=row end
    assert(not materials.nh_elixir_of_immortality and not materials.nh_philosopher_stone)
    assert(has_project(view.recipes,"rubedo_immortality").outputs[1].stock==100)
    assert(has_project(view.recipes,"philosopher_stone").outputs[1].stock==9)
end
print("Rubedo controller: localized prices and outputs, immediate craft, persistent hideout-only stock passed.")

do
    settings,flags={},{}
    new_world()
    inventory_open=true
    local profile=state()
    profile.resources.arcane_scrap=12
    assert(NHStore.startOrder(profile,"battle_staff"))
    assert(NHStore.advanceProduction(profile,{run=profile.runSerial,orderId=profile.order.id,progress=profile.order.required}))
    assert(NHStore.commit(profile))
    boot(); tick()
    local target
    NHUI.quickTarget=function() return target end
    local function shift(slot) target=slot; tick(); tick(225,nil,nil,"left"); tick() end
    local row=state().warehouse[1]
    shift({key="warehouse",safeSlot=row.slot,kind=row.item.kind,entity=row.id})
    local staff=assert(EntityGetWithTag("noita_hideout_battle_staff")[1])
    local staffCore=entities[EntityGetAllChildren(staff)[1]].comps
    assert(staffCore.ItemActionComponent.action_id=="NH_BATTLE_STAFF" and staffCore.ItemComponent.permanently_attached)
    local mag=entities[staff].comps.VariableStorageComponentnh_magazine
    mag.value_int,mag.value_float=65,4
    local ability,item=entities[staff].comps.AbilityComponent,entities[staff].comps.ItemComponent
    ability.sprite_file="data/items_gfx/wands/wand_0064.png"
    local sprite=EntityAddComponent2(staff,"SpriteComponent",{_tags="enabled_in_hand"})
    NHFirearms.repairStaff(staff,player)
    assert(sprite.image_file=="mods/noita_hideout/files/items/staff_angles.xml" and sprite.image_file==ability.sprite_file)
    assert(sprite.visible and sprite.special_scale_x==0.5 and sprite.offset_x==0 and item.ui_sprite==NHFirearms.items.battle_staff.icon)
    local mirror=assert(entities[staff].comps["LuaComponentenabled_in_hand,enabled_in_world,nh_equipment_mirror"])
    assert(mirror.script_source_file=="mods/noita_hideout/files/equipment_sprite_mirror.lua")
    assert(mag.value_int==65 and mag.value_float==4)
    ability.use_gun_script,item.is_frozen=false,true
    local wands={}
    for col=0,3 do
        local wand=EntityLoad("test.xml",0,0)
        EntityAddTag(wand,"wand");GamePickUpInventoryItem(player,wand)
        EntityAddComponent2(wand,"ItemComponent",{slotX=col,slotY=0})
        wands[col]=wand
    end
    NHFirearms.repairStaff(staff,player)
    assert(not ability.use_gun_script and not item.is_frozen and NHFirearms.nativeLane("battle_staff",staff)=="tool")
    EntityKill(wands[2]);NHFirearms.repairStaff(staff,player)
    assert(ability.use_gun_script and item.slotX==2 and #EntityGetAllChildren(staff)==1)
    EntityRemoveFromParent(staff); ability.use_gun_script=false
    NHFirearms.repairStaff(staff,player); assert(ability.use_gun_script and item.slotX==2)
    GamePickUpInventoryItem(player,staff)
    for _,slot in ipairs(tick().native_slots) do
        if slot.entity==staff then assert(slot.lane=="wand" and slot.xslot==2); shift(slot); break end
    end
    row=assert(state().warehouse[1]);assert(row.item.kind=="battle_staff" and row.item.mode==4 and row.item.rounds==65 and not EntityGetIsAlive(staff))
    shift({key="warehouse",safeSlot=row.slot,kind=row.item.kind,entity=row.id})
    staff=assert(EntityGetWithTag("noita_hideout_battle_staff")[1]);EntityRemoveFromParent(staff)
    item=entities[staff].comps.ItemComponent
    item.is_pickable,item.next_frame_pickable,item.item_pickup_radius=true,0,18
    EntitySetTransform(staff,EntityGetTransform(player))
    local filler=EntityLoad("test.xml",0,0)
    EntityAddTag(filler,"wand"); GamePickUpInventoryItem(player,filler)
    EntityAddComponent2(filler,"ItemComponent",{slotX=2,slotY=0})
    local inRadius=EntityGetInRadius
    EntityGetInRadius=function() return EntityGetIsAlive(staff) and {staff} or {} end
    inventory_open=false;tick()
    controls.mButtonDownInteract,controls.mButtonFrameInteract=true,frame+1
    tick();controls.mButtonDownInteract=false
    EntityGetInRadius=inRadius
    local saved=assert(state().safe[1]).item
    assert(not EntityGetIsAlive(staff) and saved.kind=="battle_staff" and saved.rounds==65 and saved.mode==4)
end
print("Battle staff: warehouse quick transfer, full and freed wand lanes, old drops and ammo/mode round trip passed.")

do
    settings,flags={},{}
    new_world()
    inventory_open=true
    local profile=state()
    profile.resources.arcane_scrap=12
    assert(NHStore.startOrder(profile,"hunting_bow"))
    assert(NHStore.advanceProduction(profile,{run=profile.runSerial,orderId=profile.order.id,progress=profile.order.required}))
    assert(NHStore.commit(profile))
    boot(); tick()
    local target
    NHUI.quickTarget=function() return target end
    local function shift(slot) target=slot; tick(); tick(225,nil,nil,"left"); tick() end
    local function equip()
        local row=assert(state().warehouse[1])
        shift({key="warehouse",safeSlot=row.slot,kind=row.item.kind,entity=row.id})
        return assert(EntityGetWithTag("noita_hideout_hunting_bow")[1])
    end
    local bow=equip()
    local core=entities[EntityGetAllChildren(bow)[1]].comps
    assert(core.ItemComponent.permanently_attached and core.ItemActionComponent.action_id=="NH_HUNTING_BOW")
    local mag=entities[bow].comps.VariableStorageComponentnh_magazine
    mag.value_int,mag.value_float=1,4
    for _,slot in ipairs(tick().native_slots) do
        if slot.entity==bow then assert(slot.lane=="wand"); shift(slot); break end
    end
    local stored=assert(state().warehouse[1]).item
    assert(stored.kind=="hunting_bow" and stored.rounds==1 and stored.mode==4)
    mag=entities[equip()].comps.VariableStorageComponentnh_magazine
    assert(mag.value_int==1 and mag.value_float==4)
end

do
    settings,flags={},{}
    new_world()
    local profile=state()
    local slot=assert(NHStore.freeSafeSlot(profile))
    local id=profile.nextItemId
    profile.safe[1]={slot=slot,id=id,item=NHFirearms.recipe("battle_staff").item}
    profile.nextItemId=id+1
    assert(NHStore.commit(profile));boot()
    local poly=EntityLoad("polymorph.xml",227,-85)
    EntityAddTag(poly,"polymorphed_player");EntityAddComponent2(poly,"DamageModelComponent",{hp=2,max_hp=2})
    local effect={frames=3600,tags={nh_staff_mimic=true}}
    local previous=GameGetGameEffect
    GameGetGameEffect=function(body,kind) return body==poly and kind=="POLYMORPH" and effect or 0 end
    entities[player].tags.player_unit=nil
    assert(tick().mimicFrames==3600 and tick(43).mimicFrames==3600)
    effect.frames=240;assert(tick(40).mimicFrames==240)
    EntityAddTag(poly,"nh_staff_mimic_hit");assert(not tick() and effect.frames==1)
    entities[player].tags.player_unit=true;EntityKill(poly)
    assert(not tick().mimicFrames and state().safe[1].slot==slot and state().safe[1].id==id)
    GameGetGameEffect=previous
end
print("Mimic controller: native timer, hit release and untouched inventory passed.")

do
    new_world()
    local profile=state()
    profile.gearLink={id=profile.nextItemId,item={kind="remote_terminal",remaining=2}}
    profile.nextItemId=profile.nextItemId+1
    assert(NHStore.commit(profile))
    boot()
    local bell=EntityLoad("mods/noita_hideout/files/items/salvage_bell.xml",227,-85)
    EntityAddTag(bell,"nh_red_relic")
    GamePickUpInventoryItem(player,bell)
    held=bell
    local item=EntityGetFirstComponentIncludingDisabled(bell,"ItemComponent")
    item.uses_remaining=90
    local animate,activate,enabled=GamePlayAnimation,NHSalvageBell.activate,controls.enabled
    GamePlayAnimation=function() end
    NHSalvageBell.activate=function(p,pay) assert(p==player); return pay() end
    controls.enabled=true
    tick()
    tick(nil,nil,nil,"unbound_click")
    assert(item.uses_remaining==90)
    tick(nil,nil,nil,"bound_fire")
    tick(nil,nil,nil,"bound_fire")
    assert(item.uses_remaining==89,"holding mapped fire activated a second time")
    tick()
    inventory_open=true
    tick(nil,nil,nil,"bound_fire")
    inventory_open=false
    tick(nil,nil,nil,"bound_fire")
    assert(item.uses_remaining==89,"holding through inventory close activated the bell")
    tick()
    tick(224,nil,nil,"bound_fire")
    assert(not controls.mButtonDownFire,"support command menu did not capture input")
    tick(nil,nil,nil,"bound_fire")
    assert(item.uses_remaining==89,"closing support commands replayed the held fire")
    tick()
    tick(nil,nil,nil,"left")
    assert(item.uses_remaining==88,"default bound mouse fire stopped working")
    tick()
    -- Changing slots during a held action cannot start a new activation and
    -- a non-mouse binding must not trigger other items' existing fire path.
    local other=EntityLoad("mods/noita_hideout/files/items/heavy_mg.xml",227,-85)
    GamePickUpInventoryItem(player,other)
    held=other
    local fireHeld=NHProducts.fireHeld
    NHProducts.fireHeld=function() error("rebound fire entered the launcher path") end
    tick(nil,nil,nil,"bound_fire")
    held=bell
    tick(nil,nil,nil,"bound_fire")
    assert(item.uses_remaining==88)
    NHProducts.fireHeld=fireHeld
    -- Activating a different quick slot preserves the selected item and charges once.
    tick()
    held=other
    entities[other].comps.ItemComponent.slotX=1
    entities[other].comps.ItemComponent.uses_remaining=12
    inventory_open=true
    local source
    for _,entry in ipairs(tick().native_slots) do if entry.entity==bell then source=entry end end
    assert(source and source.remaining==88)
    source.container="native"
    tick(nil,"use_inventory",source)
    assert(item.uses_remaining==87 and held==other and EntityGetParent(bell)==quick)
    tick(nil,"use_inventory",source)
    assert(item.uses_remaining==87,"stale quick-slot click spent twice")
    inventory_open=false
    controls.enabled,GamePlayAnimation,NHSalvageBell.activate=enabled,animate,activate
    tick()
end

do
    settings,flags={},{}
    new_world()
    local profile=state()
    for _,container in ipairs({"safe","warehouse"}) do
        profile[container]={{slot=1,id=profile.nextItemId,item={kind="salvage_bell",remaining=1}}}
        profile.nextItemId=profile.nextItemId+1
    end
    assert(NHStore.commit(profile))
    boot()
    inventory_open=true
    tick()
    local previous,notify,activations,lastMessage=NHSalvageBell.activate,NHUI.notify,0,nil
    NHUI.notify=function(message) lastMessage=message end
    NHSalvageBell.activate=function(p,pay)
        assert(p==player)
        if not pay() then return false end
        activations=activations+1
        return true
    end
    for _,container in ipairs({"safe","warehouse"}) do
        local row=state()[container][1]
        local ref={container=container,kind=row.item.kind,slot=row.slot,storedId=row.id,remaining=1}
        local before=activations
        fail_commit=true
        tick(nil,"use_inventory",ref)
        fail_commit=false
        assert(activations==before and state()[container][1].item.remaining==1,"failed commit granted effect or spent charge")
        assert(lastMessage and lastMessage:find("Settings readback failed",1,true),"lost the storage error")
        advance(61)
        tick(nil,"use_inventory",ref)
        local used=state()[container][1]
        assert(used.id==row.id and used.item.remaining==0 and activations==before+1,container)
        tick(nil,"use_inventory",ref)
        ref.remaining=0
        tick(nil,"use_inventory",ref)
        assert(state()[container][1].id==row.id and activations==before+1,"exhausted relic reused or deleted")
    end
    assert(#GameGetAllInventoryItems(player)==0,"using stored relics materialized an item")
    boot()
    assert(state().safe[1].item.remaining==0 and state().warehouse[1].item.remaining==0)
    NHSalvageBell.activate,NHUI.notify=previous,notify
end
print("Relic controller: non-held activation, selected slot, stored payment, stale clicks and persisted zero durability passed.")

do
    local path = "data/entities/misc/healthbar_dummy.xml"
    local template = '<Entity><LifetimeComponent lifetime="1" />' ..
        '<DamageModelComponent hp="0" wait_for_kill_flag_on_death="1" other_mod="keep">' ..
        '<damage_multipliers fire="0" /></DamageModelComponent><BossHealthBarComponent in_world="1" /></Entity>'
    local enabled, xml, reads, writes = false, nil, 0, 0
    function ModIsEnabled(id) assert(id == "new_enemies"); return enabled end
    function ModDoesFileExist(file) return enabled and file == path and xml ~= nil end
    function ModTextFileGetContent(file)
        if file ~= path then return nil end
        reads = reads + 1
        return xml
    end
    function ModTextFileSetContent(file, value) assert(file == path); writes = writes + 1; xml = value end
    OnModPostInit()
    enabled = true
    OnModPostInit()
    assert(reads == 0 and writes == 0)
    xml = template
    OnModPostInit()
    local script = assert(xml:match('<LuaComponent script_source_file="([^"]+)" execute_every_n_frame="1" />'))
    local expected = template:gsub('lifetime="1"', 'lifetime="2"'):gsub('hp="0"', 'hp="1" max_hp="1"')
        :gsub('<BossHealthBarComponent in_world="1" />', '<BossHealthBarComponent _enabled="0" gui="0" in_world="0" />' ..
            '<LuaComponent script_source_file="' .. script .. '" execute_every_n_frame="1" />')
    assert(xml == expected and writes == 1)
    OnModPostInit()
    xml = template:gsub('hp="0"', 'hp="0" max_hp="10"')
    OnModPostInit()
    xml = template:gsub('lifetime="1"', 'lifetime="5"')
    OnModPostInit()
    xml = template:gsub("BossHealthBarComponent", "SpriteComponent")
    OnModPostInit()
    assert(writes == 1)

    local check = assert(loadfile(script))
    local damage, bar = {hp=750, max_hp=1000}, {enabled=false, gui=false, in_world=false}
    setfenv(check, {
        GetUpdatedEntityID=function() return 11 end,
        EntityGetFirstComponentIncludingDisabled=function(id, kind)
            assert(id == 11)
            if kind == "DamageModelComponent" then return damage end
            assert(kind == "BossHealthBarComponent")
            return bar
        end,
        ComponentGetValue2=function(component, key) assert(component == damage); return component[key] end,
        ComponentSetValue2=function(component, key, value)
            assert(component == bar and (key == "gui" or key == "in_world"))
            component[key] = value
        end,
        EntitySetComponentIsEnabled=function(id, component, value)
            assert(id == 11 and component == bar)
            bar.enabled = value
        end,
    })
    check()
    assert(bar.enabled and bar.gui and bar.in_world and damage.hp == 750 and damage.max_hp == 1000)
    for _, max in ipairs({0, -90000}) do
        damage, bar = {hp=0, max_hp=max}, {enabled=false, gui=false, in_world=false}
        check()
        assert(not bar.enabled and not bar.gui and not bar.in_world and damage.max_hp == max)
    end
end
print("New Enemies: valid and retired boss proxies, optional mod and unchanged custom templates passed.")

-- A continued EW game can start with only a spectator. Require the actual
-- controller to publish its issuer before the host can acknowledge the run.
do
    world={}
    reset_entities()
    entities[player].tags={nh_ew_waiting=true,polymorphed_player=true,ew_notplayer=true}
    function ModIsEnabled(id) return id=="quant.ew" end
    function ModDoesFileExist() return false end
    function ModTextFileGetContent() end
    function GameHasFlagRun(flag) return flag=="ew_flag_notplayer_active" end
    local profile=state().profile
    settings["noita_hideout.ew_owner_"..profile]="observer"
    boot()
    world["nh_ew.local_peer"]="0000000000000001"
    OnWorldPostUpdate()
    assert(world["nh_ew.issuer"]=="observer" and not NHEW.ready())
    frame=frame+65
    world["nh_ew.world_mark"]="observerRoom"
    world["nh_ew.status"]="1|observerRoom|0|g|0|"..frame
    OnWorldPostUpdate()
    assert(state().ewActive=="observerRoom" and not NHEW.localBody(player))
end
print("EW spectator resumes the correct expedition without a playable body.")
