-- The item remains on its owner until that owner's normal storage adapter
-- commits the contents and the receipt in one revision of the personal profile.
NHEWDeposit={}
local D=NHEWDeposit
local escrow=dofile("mods/noita_hideout/files/ew_deposit_escrow.lua")
local historyCodec=dofile("mods/noita_hideout/files/ew_deposit_history.lua")
local tracked,held,lastFrame,checking
local queued="Item deposit queued."
local changedItem="The selected item changed before deposit."
local missing="The item could not be located."
local profileFull="Not enough room in the hideout profile to finish this deposit."
local function depositError(why)
    if type(why)~="string" then return why and "The item could not be stored." end
    if why:find("1 MiB",1,true) then return profileFull end
    return #why<=96 and why or "The item could not be stored."
end
local function copy(t)
    local out={}
    for k,v in pairs(t or {}) do out[k]=v end
    return out
end
local function clone(v)
    if type(v)~="table" then return v end
    local out={};for k,x in pairs(v) do out[k]=clone(x) end;return out
end
function D.same(a,b)
    if a==b then return true end
    if type(a)~="table" or type(b)~="table" then return false end
    for k,v in pairs(a) do if not D.same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function D.reset() tracked,held,lastFrame,checking=nil,nil,nil,nil end
function D.acceptsLock(ticket) return tracked~=nil and ticket==tracked end
local function stamp(p) return p.world.."|"..p.issuer.."|"..p.tx end
local function ours(s,p)
    return p and s.ewActive==p.world and NHEW.issuer()==p.issuer
end
local function authenticated(s,p)
    return ours(s,p) and NHEW.world()==p.world and NHEW.ready()
end
local function save(s,p,history)
    local draft=copy(s)
    draft.ewDepositPending=p
    if history then draft.ewDepositHistory=history end
    local ok,why=NHStore.commit(draft,s.ewDepositPending~=nil)
    if not ok then return nil,why end
    for k,v in pairs(draft) do s[k]=v end
    s.ewDepositPending=p
    return true
end
local function keysFor(item,source)
    local keys,why=NHEWItems.claimKeys(item,source)
    if keys then table.sort(keys) end
    return keys,why
end
local function owned(player,item,attached)
    if not item or item==0 or not EntityGetIsAlive(item) then return false end
    if NHEWItems.held(player,item,attached) then return true end
    if not NHEW.localBody(player) or EntityHasTag(item,"ew_des") or EntityHasTag(item,"ew_client")
        or EntityGetRootEntity(item)~=player then return false end
    if escrow.box(player,item) then return true end
    if tracked and NHEWItems.lockInfo(item)==tracked then
        local slot=escrow.slot(player,item)
        return slot~=nil and (attached or slot.bag~="attached")
    end
    return false
end
local function sameIdentity(p,item)
    local source=NHEWItems.source(item,p.intent.route)
    if source~=p.source then
        -- A failed storage attempt can have stamped a previously unmarked
        -- DES object before the profile write. Its ground identity is stable.
        local gid=NHEWItems.gid(item)
        if p.source or not gid or source~="ew/"..p.issuer.."/g/"..gid then return false end
    end
    return D.same(keysFor(item,source),p.keys)
end
local function locate(p,player)
    local attached=not p.intent or p.intent.route=="perk"
    local token=stamp(p)
    if owned(player,held,attached) and NHEWItems.lockInfo(held)==token then return held end
    local found,locked,ambiguous,duplicateLocked
    local visited={}
    local function inspect(id)
        if visited[id] or not owned(player,id,attached) then return end
        visited[id]=true
        local mark=NHEWItems.lockInfo(id)
        if mark==token then
            if locked then duplicateLocked=true end
            locked=id
        elseif not mark and p.intent and sameIdentity(p,id) then
            if found then ambiguous=true end
            found=id
        end
    end
    for _,id in ipairs(GameGetAllInventoryItems(player) or {}) do inspect(id) end
    escrow.each(player,inspect)
    for _,child in ipairs(EntityGetAllChildren(player) or {}) do
        local name=EntityGetName(child)
        if name=="inventory_quick" or name=="inventory_full" then
            for _,id in ipairs(EntityGetAllChildren(child) or {}) do inspect(id) end
        elseif attached then inspect(child) end
    end
    if not duplicateLocked then held=locked or (not ambiguous and found or nil);return held end
end
local function lock(p,id)
    local token=stamp(p)
    local mark,original=NHEWItems.lockInfo(id)
    if mark and (mark~=token or original~=p.original) then return false end
    local c=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
    if (c~=nil)~=p.hadItem then return false end
    if not mark then
        if c and ComponentGetValue2(c,"permanently_attached")~=p.original then return false end
        local tag=NHEWItems.lockTag
        EntityAddComponent2(id,"VariableStorageComponent",{_tags=tag,name=tag,value_string=token,value_bool=p.original})
        if NHEWItems.lockInfo(id)~=token then return false end
    end
    if c and not ComponentGetValue2(c,"permanently_attached") then ComponentSetValue2(c,"permanently_attached",true) end
    return not c or ComponentGetValue2(c,"permanently_attached")==true
end
local function unlock(id,token)
    local mark,original,marker=NHEWItems.lockInfo(id)
    if mark~=token then return false end
    local c=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
    if c then
        ComponentSetValue2(c,"permanently_attached",original)
        if ComponentGetValue2(c,"permanently_attached")~=original then return false end
    end
    EntityRemoveComponent(id,marker)
    return NHEWItems.lockInfo(id)==nil
end
local function cancellation(s,p,reason)
    -- Only the receipt and the exact original identities can still matter
    -- after asking for cancellation. The adapter must never replay this form.
    local waiting={world=p.world,issuer=p.issuer,tx=p.tx,phase="cancel",keys=p.keys,reserved=p.reserved,reason=depositError(reason)}
    return save(s,waiting)
end
function D.begin(s,player,item,source,intent,record)
    if not NHEWItems.enabled() then return false end
    if not NHEWItems.ready() then return nil,"Waiting for item ownership. Try again." end
    if NHEWItems.lockInfo(item) then return nil,"Could not lock this item for deposit." end
    local keys,why=keysFor(item,source)
    if not keys then return nil,why end
    if #keys==0 then return false end
    if s.ewDepositPending then return nil,"Another deposit is pending." end
    local issuer,world=NHEW.issuer(),NHEW.world()
    if not world or world~=s.ewActive or not issuer or not owned(player,item,intent.route=="perk") then return nil,changedItem end
    if s.revision>=999999999999999 then return nil,"Inventory slot changed." end
    local c=EntityGetFirstComponentIncludingDisabled(item,"ItemComponent")
    local slot=escrow.slot(player,item)
    if not slot then return nil,"Could not lock this item for deposit." end
    local p={world=world,issuer=issuer,tx=("%.0f"):format(s.revision+1),phase="prepare",keys=keys,reserved=true,
        run=s.runSerial,source=source,intent=clone(intent),record=clone(record),hadItem=c~=nil,slot=slot,
        original=c and ComponentGetValue2(c,"permanently_attached")==true or false}
    local ok,err=save(s,p)
    if not ok then return nil,depositError(err) end
    tracked,held,lastFrame=stamp(p),item,nil
    if not lock(p,item) or not escrow.stash(player,item,tracked,slot) then
        local why="Could not lock this item for deposit."
        cancellation(s,p,why)
        return nil,why
    end
    return true,queued
end
function D.view(s)
    local p=s and s.ewDepositPending
    if not p or not ours(s,p) then return end
    local committed=s.ewDepositReceipt==stamp(p)
    local verifying=checking and checking.token==stamp(p)
    return {tx=p.tx,phase=committed and "commit" or (p.phase~="return" and verifying and "verify" or p.phase),
        canCancel=not committed and not verifying and p.phase=="prepare"}
end
function D.cancel(s,tx)
    local p=s and s.ewDepositPending
    if not p or tostring(tx)~=p.tx or not ours(s,p) or s.ewDepositReceipt==stamp(p)
        or p.phase=="verify" or p.phase=="return" or (checking and checking.token==stamp(p)) then return false end
    if p.phase=="cancel" then return true end
    lastFrame=nil
    return cancellation(s,p)
end
local function clean(s,player,id,token)
    if NHEWItems.containsPlayer(id) or not escrow.release(player,id,token,true) then return false end
    return NHTransfers.cleanupEWDeposit(s,player,id,token)
end
function D.recoverEscrow(s,player)
    if not s or not (s.ewDepositHistory or s.ewDepositPending) or not NHEW.localBody(player) then return end
    escrow.each(player,function(id) D.reconcileItem(s,player,id) end)
end
local function portableWhole(id)
    local kind=NHTransfers.item_kind(id)
    return kind and kind~="card_wallet" and kind~="relic_chain" and kind~="pouch" and kind~="dose"
        and not NHShields.supply(kind)
end
-- Only the local player can dispose of a carried entity. A returned proof
-- names a ticket, never an entity ID, because both DES IDs and holders change.
function D.reconcileItem(s,player,id)
    local history,p=s.ewDepositHistory,s.ewDepositPending
    local world,issuer=s.ewActive,NHEWItems.ready()
    if not world or not issuer or NHEW.world()~=world or not owned(player,id,true) then return false end
    local prefix=world.."|"..issuer.."|"
    local token=NHEWItems.lockInfo(id)
    if p and ours(s,p) and s.ewDepositReceipt==stamp(p)
        and (token==stamp(p) or (not token and p.intent and sameIdentity(p,id))) then
        clean(s,player,id,stamp(p))
        return true
    end
    if token then
        if token:sub(1,#prefix)~=prefix then return false end
        local serial=token:sub(#prefix+1)
        local result=historyCodec.outcome(history,world,issuer,serial)
        if result=="cancelled" then
            if not escrow.release(player,id,token,true) then return true end
            unlock(id,token);return false
        end
        local first=type(result)=="string" and result:match("^([^,]+)")
        if not first or historyCodec.lookup(history,world,issuer,first)~=serial then return false end
        clean(s,player,id,token)
        return true
    end
    local source=NHEWItems.source(id)
    if not history and not source then return false end
    local keys=keysFor(id,source)
    if not keys or #keys==0 then return false end
    local key
    if source and source:match("^ew/%w+/r/") then
        key=NHEWItems.releaseKey(id)
        if key~="t/"..source then return false end
    end
    local tx=historyCodec.lookup(history,world,issuer,keys[1])
    if tx and historyCodec.outcome(history,world,issuer,tx)==table.concat(keys,",") then
        clean(s,player,id,prefix..tx)
        return true -- the cleanup handler owns any deferred split remainder
    end
    if not key then return false end
    tx=historyCodec.lookup(history,world,issuer,key)
    if tx then
        clean(s,player,id,prefix..tx)
        return true
    end
    -- The other owner's personal split/remainder and container data are
    -- unavailable here. Only a whole transferable item is safe to remove.
    if not portableWhole(id) then return false end
    local winner,serial=NHEW.releaseWinner(world,issuer,key)
    if winner and winner~=issuer and s.ewActive==world and NHEW.world()==world and NHEWItems.ready()==issuer
        and NHEWItems.held(player,id,true) and not NHEWItems.lockInfo(id) and NHEWItems.releaseKey(id)==key then
        clean(s,player,id,world.."|"..winner.."|"..serial)
        return true
    end
    return false
end
local diskProof
local function finish(s,p,status,player)
    local token=stamp(p)
    if status~="done" then
        -- Keep a durable return instruction while the backpack is full or the
        -- owner is down. The lock/box already contains the original slot and
        -- attachment flag, so the large item snapshot is no longer needed.
        if p.phase~="return" or p.intent then
            local waiting={world=p.world,issuer=p.issuer,tx=p.tx,phase="return",outcome=status,reserved=p.reserved,reason=depositError(p.reason)}
            if not save(s,waiting) then diskProof(s,p);return end
            p=waiting
        end
        local canReturn=player and EntityGetIsAlive(player) and NHEW.localBody(player)
        local id=canReturn and locate(p,player)
        if not canReturn or (not id and not authenticated(s,p)) or (id and not escrow.release(player,id,token,true)) then return end
        if id and NHEWItems.lockInfo(id)==token and not unlock(id,token) then return end
    end
    local history=historyCodec.add(s.ewDepositHistory,p.world,p.issuer,p.tx,status=="done" and p.keys or false)
    local ok=save(s,nil,history)
    if not ok then diskProof(s,p);return end
    if player and NHEW.localBody(player) then
        local id=locate(p,player)
        if id then D.reconcileItem(s,player,id) end
    end
    D.reset()
    if status=="done" then return "stored" end
    if p.reason then return "failed",p.reason end
    if status=="denied" then return "failed","Another player claimed this item." end
    return "cancelled","Item deposit cancelled."
end
diskProof=function(s,p)
    local disk=NHStore.load()
    if not disk or disk.profile~=s.profile or disk.ewActive~=p.world then return end
    local token=stamp(p)
    local past=historyCodec.outcome(disk.ewDepositHistory,p.world,p.issuer,p.tx)
    local proof
    if disk.ewDepositPending and stamp(disk.ewDepositPending)==token and disk.ewDepositPending.phase=="return" then proof="return"
    elseif past=="cancelled" then proof="closedCancel"
    elseif p.keys and past==table.concat(p.keys,",") then proof="closedDone"
    elseif disk.ewDepositReceipt==token then proof="receipt"
    elseif disk.ewDepositPending and stamp(disk.ewDepositPending)==token then proof="open"
    else return end
    for k in pairs(s) do s[k]=nil end
    for k,v in pairs(disk) do s[k]=v end
    return proof
end
local function verify(s,p,player,hostDone,why)
    local token=stamp(p)
    checking={token=token,hostDone=hostDone,reason=why}
    local proof=diskProof(s,p)
    if proof=="closedDone" or proof=="closedCancel" then
        D.reset()
        if proof=="closedDone" then return "stored" end
        return "cancelled","Item deposit cancelled."
    elseif proof=="receipt" then
        checking=nil
        if NHEW.itemTransaction(p.tx,"commit",p.keys)=="done" then return finish(s,p,"done",player) end
    elseif proof=="open" then
        p=s.ewDepositPending
        if hostDone then
            if p.phase~="verify" then
                local disputed={world=p.world,issuer=p.issuer,tx=p.tx,phase="verify",keys=p.keys,reserved=p.reserved}
                if save(s,disputed) then return "failed","Could not verify a local deposit receipt. The item remains locked." end
            end
        elseif cancellation(s,p,why) then checking=nil end
    end
end
function D.update(s,player,canAccess)
    local p=s and s.ewDepositPending
    if not p or not ours(s,p) then return end
    local current=NHEW.world()
    if current then
        if current~=p.world or not NHEW.ready() then return end
    elseif p.phase~="return" or GlobalsGetValue("nh_ew.world_mark","")~=p.world then return end
    local f=GameGetFrameNum()
    if stamp(p)~=tracked then tracked,held,lastFrame,checking=stamp(p),nil,nil,nil end
    local interval=p.phase=="verify" and 180 or 12
    if lastFrame and f>=lastFrame and f-lastFrame<interval then return end
    lastFrame=f
    local token=stamp(p)
    if p.phase=="return" then return finish(s,p,p.outcome,player) end
    if s.ewDepositReceipt==token then
        if NHEW.itemTransaction(p.tx,"commit",p.keys)=="done" then return finish(s,p,"done",player) end
        return
    end
    if p.phase=="verify" or checking then return verify(s,p,player,p.phase=="verify" or checking.hostDone,checking and checking.reason) end
    if p.phase=="cancel" then
        local status=NHEW.itemTransaction(p.tx,"cancel",p.keys)
        if status=="cancelled" or status=="denied" then return finish(s,p,status,player) end
        if status=="done" then return verify(s,p,player,true) end
        return
    end
    if GameHasFlagRun("ew_flag_notplayer_active") or s.runSerial~=p.run then return verify(s,p,player,false,missing) end
    if not player or not EntityGetIsAlive(player) then return end
    if not NHEW.localBody(player) then cancellation(s,p,missing);return end
    local access=canAccess or D.canAccess
    if access and not access(s,player,p.intent) then cancellation(s,p,"Storage access is no longer available.");return end
    local id=locate(p,player)
    if not id then return verify(s,p,player,false,missing) end
    local slot=p.slot or escrow.slot(player,id)
    if not sameIdentity(p,id) or not lock(p,id) or not escrow.stash(player,id,token,slot) then cancellation(s,p,changedItem);return end
    local status=NHEW.itemTransaction(p.tx,"prepare",p.keys)
    if status=="denied" or status=="cancelled" then return finish(s,p,status,player) end
    if status=="done" then return verify(s,p,player,true) end
    if status~="granted" then return end
    if not escrow.release(player,id,token,true) then cancellation(s,p,"Inventory slot changed.");return end
    local called,ok,reason=pcall(NHTransfers.resumeEW,s,player,id,p.intent,p.record,token)
    if s.ewDepositReceipt==token then
        if NHEW.itemTransaction(p.tx,"commit",p.keys)=="done" then return finish(s,p,"done",player) end
    else
        if owned(player,id,p.intent.route=="perk") and NHEWItems.lockInfo(id)==token then escrow.stash(player,id,token,slot) end
        return verify(s,p,player,false,called and not ok and reason or changedItem)
    end
end
return D
