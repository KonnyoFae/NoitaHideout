local entities={}
local function entity(id,parent,name,tags)
    entities[id]={parent=parent,name=name,tags=tags or {},components={},x=0,y=0}
    return id
end
local function part(id,kind,t)
    t=t or {}
    t.kind=kind
    table.insert(entities[id].components,t)
    return t
end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityHasTag(id,tag) return entities[id] and entities[id].tags[tag] end
function EntityGetParent(id) return entities[id].parent end
function EntityGetName(id) return entities[id].name end
function EntityGetAllChildren(id)
    local list={}
    for n,e in pairs(entities) do if e.parent==id then list[#list+1]=n end end
    return list
end
function EntityGetComponentIncludingDisabled(id,kind,tag)
    local list={}
    for _,c in ipairs(entities[id].components) do
        if c.kind==kind and (not tag or tag==c._tags) then list[#list+1]=c end
    end
    return list
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return EntityGetComponentIncludingDisabled(id,kind,tag)[1] end
function ComponentGetValue2(c,k)
    if k=="inventory_slot" then return c.slot or 0,0 end
    return c[k]
end
function ComponentSetValue2(c,k,v)
    if k=="inventory_slot" then c.slot=v else c[k]=v end
end
function EntityRemoveComponent(id,c)
    for i,v in ipairs(entities[id].components) do if v==c then table.remove(entities[id].components,i);return end end
end
function EntityAddComponent2(id,kind,c) return part(id,kind,c) end
function EntitySetComponentsWithTagEnabled() end
function EntityRemoveFromParent(id) entities[id].parent=0 end
function EntityAddChild(parent,id) entities[id].parent=parent end
function EntityGetTransform(id) return entities[id].x,entities[id].y end
function EntityGetInRadiusWithTag(x,y,r,tag)
    local list={}
    for id,e in pairs(entities) do
        if e.tags[tag] and (x-e.x)^2+(y-e.y)^2<=r^2 then list[#list+1]=id end
    end
    return list
end
function EntityGetWithTag(tag) return EntityGetInRadiusWithTag(0,0,100000,tag) end
function GameTextGetTranslatedOrNot(s) return s end
function SetRandomSeed() end
function Random() return 50 end
function GlobalsGetValue(_,d) return d end
function EntityKill(id) entities[id]=nil end
local open=true
function GameIsInventoryOpen() return open end
NHStore={level=function(s,k) return s[k] or 0 end}
dofile("mods/noita_hideout/files/transfers.lua")
dofile("mods/noita_hideout/files/perks.lua")
local nextid=12
function EntityLoad(path,x,y)
    local suffix=path:match("perk_([a-z]+)%.xml$")
    assert(suffix)
    nextid=nextid+1
    local id=entity(nextid,0,"card",{noita_hideout_perk_card=true})
    entities[id].x,entities[id].y=x,y
    part(id,"ItemComponent")
    part(id,"VariableStorageComponent",{_tags="noita_hideout_perk_type",value_string="PROTECTION_"..suffix:upper(),value_int=0})
    return id
end
local player=entity(1,0,"player")
part(player,"Inventory2Component")
local quick=entity(2,1,"inventory_quick")
local s={perk_slots=0,perk_pack=0}
local pickup=entity(3,0,"perk",{perk=true,item_perk=true})
part(pickup,"VariableStorageComponent",{name="perk_id",value_string="PROTECTION_FIRE"})
local other=entity(4,0,"perk",{perk=true,item_perk=true})
part(other,"VariableStorageComponent",{name="perk_id",value_string="EXTRA_HP"})
assert(not NHPerks.pack(s,player,pickup))
s.perk_pack=1
entities[pickup].x=40
local model={}
NHPerks.view(s,player,model)
assert(not model.packablePerk and model.perkCapacity==0)
entities[pickup].x=4
NHPerks.view(s,player,model)
assert(model.packablePerk.entity==pickup)
open=false
assert(not NHPerks.pack(s,player,pickup))
open=true
assert(not NHPerks.pack(s,player,other))
assert(NHPerks.pack(s,player,pickup) and not entities[pickup] and not entities[other])
local card=nextid
assert(not NHPerks.pack(s,player,pickup))
EntityAddChild(quick,card)
local source={lane="tool",xslot=0,yslot=0,parent=quick}
assert(not NHPerks.equip(s,player,card,1,source))
s.perk_slots=2
assert(NHPerks.equip(s,player,card,1,source))
assert(EntityGetParent(card)==player)
local function active(id) return EntityGetComponentIncludingDisabled(id,"GameEffectComponent","noita_hideout_perk_effect") end
assert(#active(card)==1 and active(card)[1].effect=="PROTECTION_FIRE")
NHPerks.update(s,player)
assert(#active(card)==1)
local native=part(player,"GameEffectComponent",{effect="PROTECTION_FIRE",frames=-1})
local second=EntityLoad("perk_fire.xml",0,0)
EntityAddChild(quick,second)
assert(not NHPerks.equip(s,player,second,2,source))
assert(not NHPerks.unequip(s,player,1,card,source))
local dest={lane="tool",xslot=2,yslot=0,parent=quick}
assert(not NHPerks.unequip(s,player,1,second,dest))
assert(NHPerks.unequip(s,player,1,card,dest) and EntityGetParent(card)==quick and #active(card)==0)
assert(ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(card,"ItemComponent"),"inventory_slot")==2)
assert(native.frames==-1 and #entities[player].components==2)

-- Exercise both directions through the real transfer journal, with a full
-- native inventory. An interrupted write must preserve the original owner.
dofile("mods/noita_hideout/files/store.lua")
local failed=false
NHStore.commit=function(draft)
    if failed then return nil,"write rejected" end
    draft.revision=draft.revision+1
    return true
end
function GameGetFrameNum() return 200 end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityGetRootEntity(id)
    local parent=EntityGetParent(id)
    if parent==0 then return id end
    return EntityGetRootEntity(parent)
end
local receipts={}
function GlobalsGetValue(k,d) return receipts[k] or d end
function GlobalsSetValue(k,v) receipts[k]=v end
function GameGetAllInventoryItems() return EntityGetAllChildren(quick) end
function DoesWorldExistAt() return true end
for _,empty in ipairs({1,3}) do
    local filler=EntityLoad("perk_melee.xml",0,0)
    EntityAddChild(quick,filler)
    ComponentSetValue2(EntityGetFirstComponentIncludingDisabled(filler,"ItemComponent"),"inventory_slot",empty)
end
assert(#EntityGetAllChildren(quick)==4)
local state={revision=0,nextItemId=18,runSerial=1,profile=1,safeCapacity=2,
    warehouse={{id=16,slot=1,item={kind="medkit"}}},docks={},levels={perk_slots=2},
    safe={{id=17,slot=1,item={kind="perk",perk="PROTECTION_FIRE"}}}}
local function ask(container,storageSlot,perkSlot,id)
    return {container=container,storageSlot=storageSlot,perkSlot=perkSlot,entity=id}
end
local input=ask("safe",1,1,17)
assert(not NHPerks.equipStored(state,player,ask("warehouse",1,1,16)))
assert(not NHPerks.equipStored(state,player,ask("safe",1,1,19)))
failed=true
assert(not NHPerks.equipStored(state,player,input))
NHPerks.view(state,player,model)
assert(not model.perkCells[1] and #state.safe==1 and state.revision==0 and not entities[nextid])
failed=false
local ok,worn=NHPerks.equipStored(state,player,input)
assert(ok and EntityGetParent(worn)==player and #active(worn)==1 and #state.safe==0)
assert(not NHPerks.equipStored(state,player,input))
local first=next(state.transit.issued)
assert(first and receipts["noita_hideout.delivered."..first]=="1")
assert(not NHPerks.storeEquipped(state,player,ask("warehouse",1,1,worn)))
assert(not NHPerks.storeEquipped(state,player,ask("docks",1,1,worn)))
assert(not NHPerks.storeEquipped(state,player,ask("warehouse",2,2,worn)))
local output=ask("warehouse",2,1,worn)
failed=true
assert(not NHPerks.storeEquipped(state,player,output))
assert(EntityGetParent(worn)==player and #active(worn)==1 and state.transit.issued[first] and #state.warehouse==1)
failed=false
assert(NHPerks.storeEquipped(state,player,output))
assert(not entities[worn] and not state.transit.issued[first] and state.transit.retired[first])
assert(not NHPerks.storeEquipped(state,player,output) and #state.warehouse==2)
local row=state.warehouse[2]
assert(row.item.perk=="PROTECTION_FIRE" and row.slot==2)
local second_ok,again=NHPerks.equipStored(state,player,ask("warehouse",row.slot,2,row.id))
assert(second_ok and EntityGetParent(again)==player and #active(again)==1)
assert(not NHPerks.storeEquipped(state,player,ask("safe",1,2,worn)))
assert(NHPerks.storeEquipped(state,player,ask("safe",1,2,again)) and not entities[again])
assert(#state.safe==1 and state.safe[1].item.perk=="PROTECTION_FIRE" and #state.warehouse==1)
-- A world rewind can reintroduce the equipped physical entity after its
-- deposit. Reconciliation retires only this marked copy.
local replay=EntityLoad("perk_fire.xml",0,0)
EntityAddChild(player,replay)
EntityAddTag(replay,"noita_hideout_transfer_item")
part(replay,"VariableStorageComponent",{_tags="noita_hideout_transfer_id",value_string=first})
assert(NHTransfers.reconcile(state,player) and not entities[replay])
assert(#EntityGetAllChildren(quick)==4 and native.frames==-1)
print("Perks: packing, native slots, direct storage, rollback and replay passed.")
