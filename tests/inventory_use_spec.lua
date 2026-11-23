local settings,flags={},{}
local rejectWrite=false
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value)
    if not (rejectWrite and key:match("_revision$")) then settings[key]=value end
end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/transfers.lua")
local use=dofile("mods/noita_hideout/files/inventory_use.lua")
local state=assert(NHStore.load())
NHStore.newRun(state)
local player=21
local function save() assert(NHStore.commit(state)); state=assert(NHStore.load()) end
local function row(container,slot,item)
    local entry={slot=slot,id=state.nextItemId,item=item}
    state.nextItemId=state.nextItemId+1
    state[container][#state[container]+1]=entry
    return {container=container,slot=slot,storedId=entry.id,kind=item.kind,
        count=item.count,remaining=item.remaining,species=item.species,subtype=item.subtype}
end
local function spend(ref)
    assert(use.peek(state,player,ref) and use.spend(state,player,ref))
    save()
end

local kit=row("safe",1,{kind="medkit",remaining=3})
local bundle=row("warehouse",1,{kind="frost_grenade",count=8})
local old=row("warehouse",2,{kind="grenade"})
local food=row("warehouse",3,{kind="bread"})
local bandage=row("warehouse",4,{kind="bandage",count=4})
local surgery=row("warehouse",5,{kind="field_surgery_kit",remaining=1})
local dose=row("warehouse",6,{kind="dose",remaining=5,count=2})
save()
for _,ref in ipairs({bundle,old,food,bandage,kit,surgery,dose}) do
    assert(use.peek(state,player,ref) and use.supports(ref.kind))
end
assert(not use.supports("wand") and not use.supports("spell") and not use.supports("potion"))
spend(bundle); assert(not use.peek(state,player,bundle))
bundle.count=7; assert(use.peek(state,player,bundle).count==7)
spend(old); spend(food); spend(bandage)
bandage.remaining=7; assert(use.peek(state,player,bandage).count==4)
spend(kit); assert(not use.peek(state,player,kit))
kit.remaining=2; spend(kit); kit.remaining=1; spend(kit); assert(not use.peek(state,player,kit))
-- Surgery starts by retaining this ref and pays only on completion. Moving the
-- kit before the final pay invalidates the original row, even with a new kit there.
state.warehouse[NHStore.slotIndex(state,"warehouse",5,surgery.kind)].id=state.nextItemId
state.nextItemId=state.nextItemId+1
save()
assert(not use.spend(state,player,surgery))
spend(dose)
dose.count=1
assert(use.peek(state,player,dose).remaining==5)
local partial=state.warehouse[NHStore.slotIndex(state,"warehouse",2,"dose")]
assert(partial.item.remaining==4 and partial.id~=dose.storedId)

local pouchId=state.starterPouchId
local ref={container="pouch",pouchId=pouchId,kind="dose",cell=1,count=2}
local pouch=state.pouches[pouchId]
for i=2,4 do assert(NHStore.putPouchDose(pouch,1,i,"lightning")) end
local ok,why=use.spend(state,player,ref)
assert(not ok and why=="Need a free slot for the used item." and pouch.doses==5 and pouch.cells[1].count==2)
assert(not use.spend(state,player,{container="pouch",pouchId=pouchId,kind="dose",cell=2,subtype="frost",remaining=1}))
spend({container="pouch",pouchId=pouchId,kind="dose",cell=2,subtype="lightning",remaining=1})
spend(ref)
pouch=state.pouches[pouchId]
assert(pouch.cells[1].count==1 and pouch.cells[1].remaining==5 and pouch.cells[2].remaining==4 and pouch.doses==4)
-- A full pouch can reuse the clicked cell when its untouched syringes fit
-- into another compatible stack. No unrelated cell is displaced.
assert(NHStore.putPouchDose(pouch,5,1))
pouch.cells[4]={remaining=5,count=1}
spend(ref)
pouch=state.pouches[pouchId]
assert(pouch.cells[1].remaining==4 and pouch.cells[1].count==1 and pouch.cells[4].count==2 and pouch.doses==5)

local function card(species,remaining,count) return {kind="summon_card",species=species,remaining=remaining,count=count} end
local stored=row("warehouse",1,{kind="card_wallet",cells={[1]=card("griffin",80,2)}})
local wallet={id=stored.storedId,slot=1,container="warehouse"}
local cardRef={container="card_wallet",wallet=wallet,cell=1,kind="summon_card",species="griffin",remaining=80,count=2}
save()
spend(cardRef)
local cells=assert(NHCardWallets.get(state,player,wallet)).item.cells
assert(cells[1].remaining==80 and cells[1].count==1 and cells[2].remaining==79)
local token="r/"..state.profile.."/"..state.runSerial.."/1234/"..wallet.id.."/1/77"
state.transit={run=state.runSerial,retired={},issued={[token]={container="warehouse",
    row=table.remove(state.warehouse,NHStore.slotIndex(state,"warehouse",1,"card_wallet"))}}}
function EntityGetIsAlive(e) return e==77 end
function EntityHasTag(e,t) return e==77 and t=="noita_hideout_card_wallet" end
function EntityGetRootEntity(e) return e==77 and player or 0 end
function EntityGetFirstComponentIncludingDisabled(e,k,t) if e==77 and t=="noita_hideout_transfer_id" then return {value_string=token} end end
function ComponentGetValue2(c,k) return c[k] end
save()
assert(not use.peek(state,player,cardRef))
cardRef.wallet={id=wallet.id,entity=77}
cardRef.cell,cardRef.count,cardRef.remaining=2,1,79
assert(not use.peek(state,player+1,cardRef))
assert(use.spend(state,player,cardRef))
rejectWrite=true
assert(not NHStore.commit(state)); rejectWrite=false
state=assert(NHStore.load())
assert(NHCardWallets.carried(state,player,77).item.cells[2].remaining==79)
spend(cardRef)
assert(NHCardWallets.carried(state,player,77).item.cells[2].remaining==78)
assert(not use.spend(state,player,cardRef))

-- With the first row full, one right click can put the newly worn unit
-- into the final cell of a tier III container while the stack stays put.
local boxId=NHPouches.create(state,"warehouse",1,2,3)
for i=2,11 do assert(NHStore.putPouchDose(state.pouches[boxId],1,i,"fire")) end
spend({container="pouch",pouchId=boxId,kind="dose",cell=1,count=2,remaining=5})
assert(state.pouches[boxId].cells[12].remaining==4 and state.pouches[boxId].cells[1].count==1)
local large=NHCardWallets.empty(3)
large.cells[1]=card("dryad",80,2)
for i=2,11 do large.cells[i]=card("dryad",79,1) end
local entry=row("warehouse",2,large)
local largeRef={id=entry.storedId,slot=2,container="warehouse"}
spend({container="card_wallet",wallet=largeRef,cell=1,kind="summon_card",species="dryad",remaining=80,count=2})
local saved=assert(NHCardWallets.get(state,player,largeRef)).item
assert(saved.cells[12].remaining==79 and saved.cells[1].count==1)
print("Right-click payment: exact stacks and charges, old items, pouch splits, stale rows and issued wallet rollback passed.")
