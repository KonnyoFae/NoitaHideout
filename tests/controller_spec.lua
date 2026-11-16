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
local function tool(id,slot) return {parent=quick,lane="tool",xslot=2,yslot=0,entity=id,safeSlot=slot,intoContainer=not slot} end
inventory_open=true
assert(tick(nil,"take_dose",tool()).mode=="case" and state().pouch.doses==2) -- opening click cannot withdraw
tick(nil,"take_dose",tool())
assert(state().pouch.doses==2)
tick(nil,"open_container",{safeSlot=2})
tick(nil,"unpack_dose",{safeSlot=1})
assert(state().pouch.doses==1 and state().safe[1].item.kind=="dose")
tick(nil,"pack_dose",{safeSlot=1})
assert(state().pouch.doses==2 and #state().safe==0)
tick(nil,"take_dose",tool())
local dose=assert(EntityGetWithTag("noita_hideout_dose")[1])
assert(state().pouch.doses==1 and EntityGetRootEntity(dose)==player)
held=0 -- drag a specific item while another slot is active
tick(nil,"place",tool(dose))
assert(not EntityGetIsAlive(dose) and state().pouch.doses==2)
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
assert(not EntityGetIsAlive(dose) and #EntityGetWithTag("noita_hideout_stimulant")==1 and state().pouch.doses==1)
boot()
assert(state().runSerial==1 and state().pouch.doses==1)
-- The HUD opens away from spawn, and the pouch is a real quickbar entity.
entities[player].x=500
tick()
assert(not tick(10).open)
inventory_open=true
assert(tick().mode=="case")
tick(nil,"take_pouch",tool(nil,2))
local pouch=assert(EntityGetWithTag("noita_hideout_pouch")[1])
assert(EntityGetRootEntity(pouch)==player and state().pouch.location=="bag")
held=pouch
tick(nil,"place",tool(pouch,1))
assert(not EntityGetIsAlive(pouch) and state().pouch.slot==1)
tick(nil,"take_pouch",tool(nil,1))
assert(state().pouch.location=="bag")
pouch=assert(EntityGetWithTag("noita_hideout_pouch")[1])
inventory_open=false
tick()
entities[pouch].parent=0
held=0
tick()
GamePickUpInventoryItem(player,pouch)
held=pouch
tick(nil,nil,nil,true)
assert(state().pouch.doses==1 and #EntityGetWithTag("noita_hideout_dose")==0)
assert(tick().mode=="container")
local emptyTool=tool()
emptyTool.xslot=3
tick(nil,"take_dose",emptyTool)
assert(state().pouch.doses==0 and #EntityGetWithTag("noita_hideout_dose")==1)
OnPlayerDied()
assert(state().closedThrough==1 and state().pouch.location=="lost")
new_world()
tick(11)
tick(nil,"restock")
assert(state().runSerial==2 and state().pouch.location=="safe")
-- The old production path remains accessible exclusively at spawn.
local s=state()
s.warehouse[1]={id=s.nextItemId,item={kind="potion",materials={slime=250,magic_liquid_unstable_teleportation=250}}}
s.nextItemId=s.nextItemId+1
assert(NHStore.commit(s))
boot()
tick(11)
tick(nil,"order",1)
assert(state().order and not next(state().warehouse[1].item.materials))
ending=true
OnPlayerDied()
OnPlayerDied()
assert(state().finished==1 and #state().warehouse==2 and state().pouch.doses==2)
new_world()
settings["noita_hideout.test_tools"]=false
tick(11)
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
