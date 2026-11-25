-- Real coordinator, identity codec, and two independent persistence domains.
local env=setmetatable({}, {__index=_G})
setfenv(1,env)
function dofile(file) return setfenv(assert(loadfile(file)),env)() end
local base="mods/noita_hideout/files/"
setfenv(assert(loadfile(base.."ew_items.lua")),env)()
local D=setfenv(assert(loadfile(base.."ew_deposit.lua")),env)()
local function copy(v)
    if type(v)~="table" then return v end
    local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t
end
local f,down,online,world,active=0,false,true,"roomA",true
local failWrite,lostMirror,deny,allow,ackCancel,ackCommit=false,false,false,false,false,false
local failRead,forceDone=false,false
local owner="Alice"
local host,calls,afterCommit={},0,0
local player={name="local",inv={full_inventory_slots_x=8,full_inventory_slots_y=4}}
local quick={name="inventory_quick",parent=player,children={}}
local full={name="inventory_full",parent=player,children={}}
player.children={quick,full}
local other={name="remote"}
local function create(gid,token,permanent,parent)
    local item={alive=true,vars={},name="wand",parent=parent or quick,data={uses=3},item={permanently_attached=permanent or false,x=0,y=0}}
    if item.parent.children then table.insert(item.parent.children,item) end
    if gid then item.vars[1]={name="ew_gid_lid",value_string=gid,value_bool=false} end
    if token then item.vars[#item.vars+1]={name="noita_hideout_transfer_id",_tags="noita_hideout_transfer_id",value_string=token} end
    return item
end
function GameGetFrameNum() return f end
function GlobalsGetValue(key,default) return key=="nh_ew.world_mark" and world or default end
function GameHasFlagRun(flag) return flag=="ew_flag_notplayer_active" and down end
function EntityGetIsAlive(e) return e~=nil and e.alive~=false end
function EntityGetParent(e) return e.parent end
function EntityGetRootEntity(e) while e.parent do e=e.parent end;return e end
function EntityGetName(e) return e.name end
function EntityGetAllChildren(e) return e.children end
function EntityCreateNew(name) return {name=name,children={},vars={},alive=true} end
function EntityAddTag(e,t) e[t]=true end
function EntityKill(e) e.alive=false;EntityRemoveFromParent(e) end
function EntityRemoveFromParent(e)
    if e.parent and e.parent.children then
        for i,v in ipairs(e.parent.children) do if v==e then table.remove(e.parent.children,i);break end end
    end
    e.parent=nil
end
function EntityAddChild(p,e) assert(not e.parent);e.parent=p;p.children[#p.children+1]=e end
function EntitySetComponentsWithTagEnabled() end
function CrossCall(name,p,id) assert(name=="ew_hideout_deposit_unselect" and p==player and NHEWItems.lockInfo(id)) end
function EntityHasTag(e,t) return e[t]==true end
local scans=0
function GameGetAllInventoryItems() scans=scans+1;return quick.children end
function EntityGetComponentIncludingDisabled(e,t) return t=="VariableStorageComponent" and e.vars or {} end
function EntityGetFirstComponentIncludingDisabled(e,t,tag)
    if t=="ItemComponent" then return e.item end
    if t=="Inventory2Component" then return e.inv end
    if t~="VariableStorageComponent" then return end
    for _,c in ipairs(e.vars or {}) do if c._tags==tag then return c end end
end
function EntityAddComponent2(e,t,c) e.vars[#e.vars+1]=c;return c end
function EntityRemoveComponent(e,c) for i,v in ipairs(e.vars) do if v==c then table.remove(e.vars,i);return end end end
function ComponentGetValue2(c,k)
    if k=="inventory_slot" then return c.x,c.y end
    if k=="value_int" or k=="value_float" then return c[k] or 0 end;return c[k]
end
function ComponentSetValue2(c,k,v,y)
    if k=="inventory_slot" then c.x,c.y=v,y else c[k]=v end
end
function ComponentGetTags(c) return c._tags or "" end
NHEW={enabled=function() return active end,ready=function() return online end,
    issuer=function() return owner end,world=function() return online and world or nil end,
    localBody=function(p) return p==player and not down end}
function NHEW.itemTransaction(tx,action,keys)
    calls=calls+1
    local t=host[tx] or {};host[tx]=t
    local k=table.concat(keys,",")
    assert(not t.keys or t.keys==k);t.keys=k
    if forceDone then return "done" end
    if action=="cancel" then if ackCancel then t.result="cancelled" end;return t.result end
    if action=="commit" then assert(t.granted);if ackCommit then t.result="done" end;return t.result end
    assert(action=="prepare")
    if deny then return "denied" end
    if allow then t.granted=true;return "granted" end
end
local s={profile=1,ewActive=world,revision=3,runSerial=7,total=0}
local disk=copy(s)
NHStore={}
function NHStore.commit(d)
    if failWrite then return nil,"write failed" end
    assert(disk.revision==d.revision)
    d.revision=d.revision+1;disk=copy(d);return true
end
function NHStore.load() if not failRead then return copy(disk) end end
function NHStore.adoptSnapshot(target, snapshot)
    for key in pairs(target) do target[key]=nil end
    for key,value in pairs(snapshot) do target[key]=value end
end
NHTransfers={}
function NHTransfers.item_kind(item) return item.kind or "wand" end
NHShields={supply=function(kind) return kind=="charger" end}
function NHTransfers.cleanupEWDeposit(_,p,item)
    assert(p==player and EntityGetRootEntity(item)==player and item.alive)
    item.alive=false;return true
end
local accessible=true
function D.canAccess() return accessible end
function NHTransfers.resumeEW(state,p,item,intent,record,tx)
    assert(D.canAccess() and p==player and EntityGetRootEntity(item)==p and item.alive and intent.dest=="warehouse")
    assert(item.item.permanently_attached and NHEWItems.metadata(select(3,NHEWItems.lockInfo(item)),"VariableStorageComponent"))
    if not D.same(item.data,record) then return nil,"contents changed" end
    local d=copy(state);d.total=d.total+1;d.ewDepositReceipt=tx
    local ok,why=NHStore.commit(d);if not ok then return nil,why end
    afterCommit=afterCommit+1
    if lostMirror then error("process interrupted after write") end
    state.total,state.revision,state.ewDepositReceipt=d.total,d.revision,tx
    item.alive=false
    return true
end
local function begin(item)
    if not s.ewDepositPending and item.parent==quick then
        for i=#quick.children,1,-1 do
            local previous=quick.children[i]
            if previous~=item then EntityRemoveFromParent(previous);previous.parent=other end
        end
    end
    return D.begin(s,player,item,NHEWItems.source(item),{dest="warehouse",route="item"},item.data)
end
local function tick() f=f+12;return D.update(s,player,D.canAccess) end
local passive=create(nil)
for _=1,60 do tick();assert(not D.view(s)) end
assert(calls==0 and scans==0 and not begin(passive))
active=false;assert(not begin(create("88")));active=true
local src="ew/Alice/r/1/1/2/3/4/5"
local a=create("120",src)
failWrite=true;assert(not begin(a) and not a.item.permanently_attached and not NHEWItems.lockInfo(a));failWrite=false
assert(begin(a) and a.item.permanently_attached and not NHEWItems.originalPermanent(a,true))
assert(a.parent.name=="nh_ew_deposit_escrow" and a.parent.parent==player and not NHEWItems.held(player,a))
for _,native in ipairs(quick.children) do assert(native~=a) end
local tx=s.ewDepositPending.tx
assert(#s.ewDepositPending.keys==2 and s.ewDepositPending.keys[1]=="g/120" and calls==0)
assert(not begin(create("121")) and D.view(s).canCancel)
tick();assert(a.alive and s.total==0)
local savedStamp,raw,marker=NHEWItems.lockInfo(a)
assert(raw==false and savedStamp==world.."|"..owner.."|"..tx)
allow,lostMirror=true,true;tick();assert(s.total==1 and s.ewDepositReceipt==savedStamp and a.alive)
assert(not D.view(s).canCancel and not D.cancel(s,tx))
D.reset();s=NHStore.load();online=false;tick();assert(a.alive)
online=true;ackCommit=true;assert(tick()=="stored" and not a.alive and afterCommit==1)
local rewind=create("120",src);assert(D.reconcileItem(s,player,rewind) and not rewind.alive)
local changedGid=create("999",src);assert(D.reconcileItem(s,player,changedGid) and not changedGid.alive)
local oldLocked=create("120",src)
oldLocked.vars[#oldLocked.vars+1]=copy(marker)
local broken={ewActive=world,ewDepositHistory={[savedStamp]="g/120"}}
assert(not D.reconcileItem(broken,player,oldLocked) and oldLocked.alive and NHEWItems.lockInfo(oldLocked)==savedStamp)
local unrelated=create("120","ew/Alice/r/1/1/2/3/4/6")
NHEW.releaseWinner=function() end
assert(not D.reconcileItem(s,player,unrelated) and unrelated.alive)
-- With no local history, another holder needs the host's exact completed
-- release ticket. A different GID is fine, private data and remainders stay.
do
    local outsider={ewActive=world}
    owner="Bob"
    local winner,requests=nil,0
    NHEW.releaseWinner=function(w,h,k)
        assert(w==world and h==owner and k=="t/"..src);requests=requests+1
        if winner then return winner,"4" end
    end
    local traded=create("111",src)
    assert(not D.reconcileItem(outsider,player,traded) and traded.alive and requests==1)
    winner="Bob";assert(not D.reconcileItem(outsider,player,traded) and traded.alive)
    winner="Alice";assert(D.reconcileItem(outsider,player,traded) and not traded.alive)
    for _,kind in ipairs({"charger","card_wallet","relic_chain","dose","pouch"}) do
        local special=create("333",src);special.kind=kind
        assert(not D.reconcileItem(outsider,player,special) and special.alive)
    end
    local carried=create("334",src)
    carried.children={{parent=carried,polymorphed_player=true}}
    assert(D.reconcileItem(outsider,player,carried) and carried.alive)
    local lookalike=create("111")
    assert(not D.reconcileItem(outsider,player,lookalike) and lookalike.alive)
    local duplicate=create("111",src);table.insert(duplicate.vars,copy(duplicate.vars[2]))
    assert(not D.reconcileItem(outsider,player,duplicate) and duplicate.alive and requests==4)
    local moved=create("111",src)
    NHEW.releaseWinner=function() world="roomB";return "Alice","4" end
    assert(not D.reconcileItem(outsider,player,moved) and moved.alive)
    world=outsider.ewActive
    owner="Alice"
end
local remote=create("120",src,false,other);assert(not D.reconcileItem(s,player,remote) and remote.alive)
local foreign=create("120",src);foreign.ew_des=true;assert(not D.reconcileItem(s,player,foreign) and foreign.alive)
local differentWorld=create("120",src);world="roomB";assert(not D.reconcileItem(s,player,differentWorld) and differentWorld.alive);world=s.ewActive
lostMirror,allow,ackCommit=false,false,false
local b=create("200",nil,true);assert(begin(b));tx=s.ewDepositPending.tx
assert(D.cancel(s,tx));tick();assert(b.alive and b.item.permanently_attached and NHEWItems.lockInfo(b))
down=true;ackCancel=true;assert(not tick() and D.view(s).phase=="return" and NHEWItems.lockInfo(b));down=false
assert(tick()=="cancelled" and b.parent==quick and b.alive and b.item.permanently_attached and not NHEWItems.lockInfo(b))
local c=create("201");assert(begin(c));allow=true;c.data.uses=0;tick()
assert(s.ewDepositPending.phase=="cancel" and c.item.permanently_attached and s.total==1)
assert(tick()=="failed" and c.alive and not c.item.permanently_attached)
local d=create("202");assert(begin(d));d.parent=other
assert(not tick() and s.ewDepositPending.phase=="cancel");assert(tick()=="failed" and d.alive)
assert(not D.reconcileItem(s,player,d) and NHEWItems.lockInfo(d));d.parent=quick
assert(not D.reconcileItem(s,player,d) and not NHEWItems.lockInfo(d))
local e=create("203");assert(begin(e));accessible=false;tick();assert(tick()=="failed" and e.alive);accessible=true
-- A world checkpoint can precede the physical lock. Locate one held copy by
-- the exact stable identity and validate its captured state before applying.
local pre=create("204");assert(begin(pre));pre.alive=false
local restored=create("204");s=NHStore.load();D.reset();ackCommit=true
assert(tick()=="stored" and not restored.alive and s.total==2)
local ambiguous=create("205");assert(begin(ambiguous));ambiguous.alive=false
local copy1,copy2=create("205"),create("205");D.reset();tick();assert(tick()=="failed" and copy1.alive and copy2.alive)
local refused=create("206");assert(begin(refused));deny=true
assert(tick()=="failed" and refused.alive and not refused.item.permanently_attached)
assert(s.total==2 and afterCommit==2)
deny=false;ackCommit=true
-- An adapter can throw after committing while the first readback also fails.
-- Losing the source in this window must never turn fulfillment into a cancel.
local missingAfterWrite=create("207");assert(begin(missingAfterWrite))
lostMirror,failRead=true,true;tick();missingAfterWrite.alive=false
assert(D.view(s).phase=="verify" and not D.view(s).canCancel and s.total==2)
local polls=calls;tick();assert(calls==polls and not D.cancel(s,s.ewDepositPending.tx))
failRead=false;assert(tick()=="stored" and s.total==3 and afterCommit==3)
-- A newer durable history can prove closure after an old main-VM state was
-- restored. An unrelated or missing receipt cannot unlock a contested item.
lostMirror=false
local conflict=create("208");assert(begin(conflict))
forceDone=true;local ev,why=tick()
assert(ev=="failed" and why:find("remains locked",1,true) and conflict.alive and conflict.item.permanently_attached)
assert(D.view(s).phase=="verify" and not D.cancel(s,s.ewDepositPending.tx))
polls=calls;for _=1,17 do tick() end
assert(calls==polls and s.total==3)
local history=dofile(base.."ew_deposit_history.lua")
disk.ewDepositHistory=history.add(disk.ewDepositHistory,world,owner,s.ewDepositPending.tx,false)
disk.ewDepositPending=nil;disk.revision=disk.revision+1
f=f+180;assert(tick()=="cancelled" and not D.view(s))
assert(not D.reconcileItem(s,player,conflict) and conflict.alive and not conflict.item.permanently_attached)
local final=create("209");assert(begin(final));assert(D.cancel(s,s.ewDepositPending.tx))
disk.ewDepositHistory=history.add(disk.ewDepositHistory,world,owner,s.ewDepositPending.tx,{"g/209"})
disk.ewDepositPending=nil;disk.total=disk.total+1;disk.revision=disk.revision+1
assert(tick()=="stored" and s.total==4 and D.reconcileItem(s,player,final) and not final.alive)
-- A confirmed cancel keeps the actual item until its original or another
-- same-lane slot exists. No extra host query or native throw target remains.
forceDone,allow=false,false
local waiting=create("300");assert(begin(waiting))
local fillers={}
for i=0,3 do local item=create(nil);item.item.x=i;fillers[i]=item end
assert(D.cancel(s,s.ewDepositPending.tx) and not s.ewDepositPending.record)
failWrite=true
assert(not tick() and D.view(s).phase=="cancel" and NHEWItems.lockInfo(waiting))
failWrite=false
assert(not tick() and D.view(s).phase=="return" and not s.ewDepositPending.keys and not s.ewDepositPending.record)
assert(waiting.parent.name=="nh_ew_deposit_escrow" and waiting.item.permanently_attached)
polls=calls;D.reset();s=NHStore.load();online=false
tick();assert(calls==polls and waiting.parent.name=="nh_ew_deposit_escrow")
EntityKill(fillers[2]);failWrite=true
assert(not tick() and waiting.parent==quick and waiting.item.x==2 and not waiting.item.permanently_attached)
assert(s.ewDepositPending.phase=="return" and not NHEWItems.lockInfo(waiting))
failWrite=false;online=true
assert(tick()=="cancelled" and not s.ewDepositPending and waiting.alive)
assert(s.total==4 and calls==polls)

-- Exercise the actual 1 MiB atomic two-slot store. Parked withdrawals of
-- multi-spell wands provide the bulk of a valid profile from before reserves.
do
    local settings,flags={},{}
    function ModSettingGet(k) return settings[k] end
    function ModSettingSet(k,v) settings[k]=v end
    function HasFlagPersistent(k) return flags[k] end
    function AddFlagPersistent(k) flags[k]=true end
    dofile(base.."store.lua")
    dofile(base.."potion.lua")
    local encode
    for i=1,40 do
        local name,value=debug.getupvalue(NHStore.commit,i)
        if name=="encode" then encode=value;break end
    end
    assert(encode)
    s=assert(NHStore.load())
    host={};s.ewActive=world;s.total=0
    local oldItem=create("501",src)
    assert(begin(oldItem))
    local oldTx=s.ewDepositPending.tx
    s.ewDepositPending.reserved=nil -- .27 stored the full capture without headroom
    s.levels.farmland=1
    s.farm={time=1800,passive=true,plots={[1]={token=1,crop="grain",readyAt=10800}}}
    local issued={}
    s.ewExpeditions={oldWorld={transit={run=1,issued=issued,retired={}}}}
    s.warehouse={{id=1,slot=1,item={kind="wand",name="fixture"}}}
    s.nextItemId=2
    local wand={kind="wand",template="data/entities/items/wand_level_03.xml",cards={}}
    for i=1,24 do
        wand.cards[i]={id="LIGHT_BULLET",x=i-1,y=0,item={uses_remaining=-1,permanently_attached=false}}
    end
    local cap=1024*1024
    local size=#encode(s)
    for i=1,1000 do
        local ticket="ew/Alice/r/1/1/"..i.."/1/1/1"
        local release={container="warehouse",row={id=i,slot=1,item=wand}}
        local bytes=#encode({[ticket]=release})-2
        if size+bytes>cap-4096 then break end
        issued[ticket]=release;size=size+bytes
    end
    assert(size>cap-10000)
    local function fit(profile,target)
        local item=profile.warehouse[1].item
        -- Keep the adjustment small and allow for the length prefix itself
        -- growing. The rest is actual encoded release history.
        local length=#item.name+target-#encode(profile)-8
        item.name=string.rep("w",length)
        item.name=item.name..string.rep("w",target-#encode(profile))
        assert(#encode(profile)==target)
    end
    fit(s,cap-20)
    assert(NHStore.commit(s));D.reset();s=assert(NHStore.load())
    assert(#encode(s)==cap-20 and not s.ewDepositPending.reserved)
    local oldDisk=copy(settings)
    -- An active farm from before minute settlements can require more than
    -- 20 free bytes to upgrade. Its failed payout must still permit unlocking
    -- the original item, and the old clock must remain available for retry.
    local production=assert(NHStore.load())
    assert(NHFarm.sync(production,3600) and production.resources.grain==2)
    assert(not NHStore.commit(production))
    local original=assert(NHStore.load())
    assert(#encode(original)==cap-20 and original.farm.time==1800 and not original.resources.grain)
    assert(D.cancel(s,oldTx) and not s.ewDepositPending.record)
    local squeezed=assert(NHStore.load())
    fit(squeezed,cap-12)
    assert(not NHStore.commit(squeezed))
    local occupied={}
    for i=0,3 do occupied[i]=create(nil);occupied[i].item.x=i end
    assert(not tick() and D.view(s).phase=="return" and oldItem.parent.name=="nh_ew_deposit_escrow")
    EntityKill(occupied[1])
    D.reset();s=assert(NHStore.load());polls=calls
    world="anotherRoom";tick()
    assert(calls==polls and oldItem.parent.name=="nh_ew_deposit_escrow" and NHEWItems.lockInfo(oldItem))
    online=false;tick()
    assert(calls==polls and oldItem.parent.name=="nh_ew_deposit_escrow" and NHEWItems.lockInfo(oldItem))
    world=s.ewActive
    assert(tick()=="cancelled" and calls==polls and oldItem.parent==quick and oldItem.item.x==1)
    assert(not NHEWItems.lockInfo(oldItem) and not s.ewDepositPending and history.outcome(s.ewDepositHistory,world,owner,oldTx)=="cancelled")
    tick();assert(oldItem.alive and calls==polls and s.total==0)
    online=true
    local resumed=assert(NHStore.load())
    fit(resumed,cap-2000)
    assert(NHFarm.sync(resumed,3600) and NHStore.commit(resumed))
    s=assert(NHStore.load())
    assert(s.resources.grain==2 and not NHFarm.sync(s,3600))

    -- An admitted request protects its closing space against unrelated writes
    -- even after the owning expedition is parked. A refused request never locks.
    fit(s,cap-600);assert(NHStore.commit(s))
    local candidate=create("502")
    local rev=s.revision
    local accepted,why=begin(candidate)
    assert(not accepted and why:find("Not enough room",1,true) and candidate.parent==quick and not candidate.item.permanently_attached)
    assert(not NHEWItems.lockInfo(candidate) and calls==polls and NHStore.load().revision==rev)
    fit(s,cap-2000);assert(NHStore.commit(s) and begin(candidate))
    local draft=assert(NHStore.load())
    fit(draft,cap-480)
    assert(not NHStore.commit(draft))
    local switch=dofile(base.."ew_expeditions.lua")
    assert(switch.select(draft,"newRoom"))
    assert(#encode(draft)<cap and not NHStore.commit(draft))
    assert(NHStore.load().ewDepositPending.tx==s.ewDepositPending.tx and NHEWItems.lockInfo(candidate))
    -- Even after a host grant, a larger adapter result can fail to fit.
    -- The local receipt and warehouse row must both stay absent.
    local adapter=NHTransfers.resumeEW
    NHTransfers.resumeEW=function(state,p,id,intent,record,token)
        assert(p==player and id==candidate and intent.dest=="warehouse" and D.same(record,id.data))
        local enlarged=assert(NHStore.load())
        enlarged.warehouse[2]={id=enlarged.nextItemId,slot=2,item=wand}
        enlarged.nextItemId=enlarged.nextItemId+1;enlarged.ewDepositReceipt=token
        return NHStore.commit(enlarged)
    end
    allow=true;assert(not tick() and s.ewDepositPending.phase=="cancel" and candidate.parent.name=="nh_ew_deposit_escrow")
    local failed,why=tick()
    assert(failed=="failed" and why:find("Not enough room",1,true) and candidate.alive and candidate.parent==quick)
    local restoredProfile=assert(NHStore.load())
    assert(not restoredProfile.ewDepositReceipt and not restoredProfile.ewDepositPending and #restoredProfile.warehouse==1)
    assert(not NHEWItems.lockInfo(candidate) and not candidate.item.permanently_attached)
    NHTransfers.resumeEW=adapter

    -- The old host can have accepted a receipt before the last snapshot.
    -- At the same size boundary, complete its history exactly once on reload.
    settings=oldDisk;s=assert(NHStore.load());D.reset()
    local captured=s.ewDepositPending
    local token=world.."|"..owner.."|"..oldTx
    fit(s,cap-256)
    s.ewDepositReceipt=token;s.total=1
    fit(s,cap-20);assert(NHStore.commit(s))
    s=assert(NHStore.load());host[oldTx]={granted=true};ackCommit=true
    assert(tick()=="stored" and not s.ewDepositPending and s.total==1)
    assert(history.outcome(s.ewDepositHistory,world,owner,oldTx)==table.concat(captured.keys,","))
    polls=calls;tick();assert(calls==polls and s.total==1)
end
print("EW deposit: durable intent, local lock, stable multi-key recovery, exact receipts, cancellation, changed contents, duplicate and realm guards passed.")
