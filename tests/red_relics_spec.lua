local dir="mods/noita_hideout/files/"
local settings,flags={},{}
local rejectWrite=false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) if not (rejectWrite and k:match("_revision$")) then settings[k]=v end end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile(dir.."store.lua")
local defs=dofile(dir.."red_collectibles.lua")
local state=assert(NHStore.load())
NHStore.newRun(state)
local adapters,entities,held={},{}
NHTransfers={registerItem=function(kind,match,adapter) adapters[kind]=adapter end,
    item_kind=function(e) return entities[e].kind end,available=function() return true end}
NHRedRelics.register()
assert(not adapters.dragon_king and NHRedRelics.types.dragon_king.katana,"Katana owns the dragon relic codec")
NHNative={held=function() return held end}
function EntityGetRootEntity(e) return 123 end
function EntityGetParent(e) return 456 end
function EntityGetFirstComponentIncludingDisabled(e,t) return t=="ItemComponent" and e or nil end
function ComponentGetValue2(e,key) assert(key=="uses_remaining"); return entities[e].n end
function ComponentSetValue2(e,key,n) assert(key=="uses_remaining"); entities[e].n=n end
function EntityLoad(path)
    local kind=path:match("/([^/]+)%.xml$")
    local e=#entities+1
    entities[e]={kind=kind,n=90}
    return e
end
local starts,effects,allowed,expected=0,0,true,nil
local function start(kind,player,pay)
    assert(player==123 and kind==expected)
    starts=starts+1
    if not allowed or not pay() then return false end
    effects=effects+1
    return true
end
NHRewind={start=function(s,p,pay) assert(s==state); return start("rewind_watch",p,pay) end}
NHSalvageBell={activate=function(p,pay) return start("salvage_bell",p,pay) end}
local fields={hourglass_field="stasis_hourglass",duster_field="dustless_duster",mana_reactor="mana_reactor"}
function dofile_once(path)
    local kind=assert(fields[path:match("([^/]+)%.lua$")])
    return {activate=function(p,pay) return start(kind,p,pay) end}
end
function GamePlayAnimation(e,anim) assert(held==e and anim=="activate") end
local resources={"supply_logistics","strike_logistics","reinforcement_logistics","intel_logistics"}
local rewardSpecies={salvage_bell={"tarot_moon","cat"},rewind_watch={"tarot_hermit","dryad"},
    stasis_hourglass={"tarot_tower","slime"},dustless_duster={"tarot_chariot","griffin"},mana_reactor={"tarot_sun","dragon"}}
local function balances()
    local snapshot={}
    for _,key in ipairs(resources) do snapshot[key]=state.resources[key] or 0 end
    return snapshot
end
local function checkBalances(snapshot,added)
    for _,key in ipairs(resources) do assert((state.resources[key] or 0)==snapshot[key]+added,key) end
end
for i,key in ipairs(resources) do if i>1 then state.resources[key]=i*7 end end
for _,def in ipairs(defs) do
    if not def.katana then
    expected=def.id
    local adapter=adapters[def.id]
    assert(adapter.warehouseCategory=="collection" and NHStore.category(def.id)=="collection")
    held=assert(adapter.restore(def.item,0,0))
    entities[held].n=1
    allowed=false
    assert(not NHRedRelics.activate(state,123,held) and entities[held].n==1)
    allowed=true
    NHEWItems={lockInfo=function() return "pending" end}
    local before=starts
    assert(not NHRedRelics.activate(state,123,held) and starts==before and entities[held].n==1)
    NHEWItems=nil
    assert(NHRedRelics.activate(state,123,held) and entities[held].n==0)
    before=starts
    assert(not NHRedRelics.activate(state,123,held) and starts==before)
    local spent=assert(adapter.capture(held))
    assert(spent.remaining==0 and entities[assert(adapter.restore(spent,0,0))].n==0)
    assert(not adapter.restore({kind=def.id,remaining=-1},0,0))
    local unheld=assert(adapter.restore({kind=def.id,remaining=2},0,0))
    local slot={entity=unheld,kind=def.id,parent=456,remaining=2}
    assert(not NHRedRelics.activate(state,123,unheld))
    assert(NHRedRelics.activate(state,123,unheld,slot) and entities[unheld].n==1 and entities[held].n==0)
    assert(not NHRedRelics.activate(state,123,unheld,slot) and entities[unheld].n==1)
    local use=dofile(dir.."inventory_use.lua")
    for _,container in ipairs({"safe","warehouse"}) do
        local id=state.nextItemId
        state.nextItemId=id+1
        state[container]={{id=id,slot=1,item={kind=def.id,remaining=1}}}
        assert(NHStore.commit(state))
        state=assert(NHStore.load())
        local ref={container=container,slot=1,storedId=id,kind=def.id,remaining=1}
        local stored=assert(use.peek(state,123,ref))
        local payments,previous=0,effects
        NHEWItems={enabled=function() return true end,ready=function() return false end}
        local ok,reason=NHRedRelics.activateStored(state,123,stored,function() error("charged while EW was reconnecting") end)
        assert(not ok and reason=="Waiting for item ownership. Try again." and effects==previous)
        NHEWItems=nil
        local function pay()
            payments=payments+1
            local draft=assert(NHStore.load())
            if not use.spend(draft,123,ref) or not NHStore.commit(draft) then return false end
            state=assert(NHStore.load())
            return true
        end
        allowed=false
        assert(not NHRedRelics.activateStored(state,123,stored,pay) and payments==0)
        allowed,rejectWrite=true,true
        assert(not NHRedRelics.activateStored(state,123,stored,pay) and effects==previous)
        assert(NHStore.load()[container][1].item.remaining==1)
        rejectWrite=false
        assert(NHRedRelics.activateStored(state,123,stored,pay) and payments==2 and effects==previous+1)
        local row=state[container][1]
        assert(row.id==id and row.item.remaining==0 and not use.peek(state,123,ref))
        assert(not NHRedRelics.activateStored(state,123,stored,pay) and effects==previous+1)
        assert(not NHRedRelics.activateStored(state,123,row.item,function() error("exhausted item charged") end))
        ref.remaining=0
        assert(not use.spend(state,123,ref) and row.item.remaining==0)
        state[container]={}
    end
    for _,item in ipairs({spent,def.item}) do
        local id=state.nextItemId
        state.nextItemId=id+1
        state.warehouse={{id=id,slot=1,item=item}}
        assert(NHStore.commit(state))
        state=assert(NHStore.load())
        local old=balances()
        local request={slot=1,id=id,kind=def.id}
        assert(NHRedRelics.salvage(state,request))
        assert(NHStore.commit(state))
        state=assert(NHStore.load())
        assert(not NHRedRelics.salvage(state,request))
        checkBalances(old,2400)
        assert(#state.warehouse==2)
        for i,species in ipairs(rewardSpecies[def.id]) do
            local card=state.warehouse[i].item
            assert(card.species==species and card.remaining==NHCompanions.cardCapacity(species) and card.count==4)
        end
    end
    end
end

local def=defs[1]
local cap=NHStore.warehouseCapacity(state,"collection")
state.warehouse={}
for slot=1,cap do
    state.warehouse[slot]={id=state.nextItemId,slot=slot,item=def.item}
    state.nextItemId=state.nextItemId+1
end
local req={slot=1,id=state.warehouse[1].id,kind=def.id}
local nextId,rows=state.nextItemId,state.warehouse
local function reject()
    local stock=balances()
    assert(not NHRedRelics.salvage(state,req))
    checkBalances(stock,0)
    assert(state.warehouse==rows and state.nextItemId==nextId and rows[1].id==req.id and rows[1].item==def.item)
end
-- Only the collectible's slot is free. The second reward fails after the first one was staged.
reject()
local limit=NHStore.maxResourceAmount
local fullTarot={species=def.tarot,remaining=NHCompanions.cardCapacity(def.tarot)}
rows[2].item=NHCompanions.withCount(fullTarot,limit-2)
rows[4].item=NHCompanions.withCount(fullTarot,limit-2)
rows[3].slot=nil
rows[3].origin="test/old-row"
for _,key in ipairs(resources) do state.resources[key]=limit-2400 end
for _,key in ipairs(resources) do
    state.resources[key]=limit-2399
    reject()
    assert(rows[2].item.count==limit-2 and rows[4].item.count==limit-2)
    state.resources[key]=limit-2400
end
-- A prepaid workshop order already owns part of the last 2400 units of headroom.
state.order={id=state.finished+1,recipe="intel_logistics",progress=0,required=60,output={resources={intel_logistics=50}}}
assert(NHStore.commit(state))
reject()
assert(state.order.output.resources.intel_logistics==50 and rows[2].item.count==limit-2 and rows[4].item.count==limit-2)
state.order=false
-- Two nearly full tarot stacks absorb two cards each, leaving the vacated slot for the four companion cards.
local before=balances()
assert(NHRedRelics.salvage(state,req))
checkBalances(before,2400)
assert(#state.warehouse==cap and state.warehouse[1].item.count==limit and state.warehouse[3].item.count==limit)
local companion=state.warehouse[NHStore.slotIndex(state,"warehouse",1,"summon_card")].item
assert(companion.species==def.companion and companion.count==4)
assert(state.warehouse[2].slot==3 and state.warehouse[2].origin=="test/old-row" and rows[3].slot==nil)
assert(NHStore.commit(state))
print("Collectibles: held use, durability, save/reload, four logistics balances and both four-card rewards passed.")
