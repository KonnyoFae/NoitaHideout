-- Shared by the controller and isolated entity-script Lua states.
if NHEW then return NHEW end
local M={}
NHEW=M
local enabled,installed,frame,status,owner,lastStatus
local lastItemTransaction

function M.reset()
    enabled,installed=nil,nil
    frame,status,owner,lastStatus=nil,nil,nil,nil
    lastItemTransaction=nil
end

function M.enabled()
    if enabled==nil then
        installed=ModIsEnabled and ModIsEnabled("quant.ew")
        enabled=installed or
            (GlobalsGetValue and GlobalsGetValue("nh_ew.world_mark","")~="") or false
    end
    return enabled
end

-- Ownership is bound once per local save-slot profile. Two fresh peers can
-- have the same profile number and start on the same second.
function M.bind(profile)
    if not M.enabled() or not installed then return end
    local key="noita_hideout.ew_owner_"..profile
    local id=ModSettingGet(key)
    if id==nil then
        local peer=GlobalsGetValue("nh_ew.local_peer","")
        if peer=="" or not peer:match("^%x+$") then return end
        local y,m,d,h,minute,s=GameGetDateAndTimeLocal()
        local micros=math.floor(GameGetRealWorldTimeSinceStarted()*1000000)%10000000
        local salt=("%d.%d.%d.%d.%d.%d.%d.%d"):format(y,m,d,h,minute,s,micros,profile)
        local hash=5381
        for i=1,#salt do hash=(hash*33+salt:byte(i))%2147483647 end
        id=("p%x%s%x"):format(profile,peer,hash)
        pcall(ModSettingSet,key,id)
        if ModSettingGet(key)~=id then return end
    end
    if type(id)~="string" or #id>40 or not id:match("^%w+$") then return end
    owner=id
    if GlobalsGetValue("nh_ew.issuer","")~=id then GlobalsSetValue("nh_ew.issuer",id) end
    return id
end

function M.issuer()
    return owner or (GlobalsGetValue and GlobalsGetValue("nh_ew.issuer",""):match("^([%w]+)$"))
end

local function session()
    if not M.enabled() or not installed then return end
    local now=GameGetFrameNum()
    if frame~=now then
        frame=now
        local raw=GlobalsGetValue("nh_ew.status","")
        if raw~=lastStatus then
            status,lastStatus=nil,raw
            local world,gold,role,cycle,beat=raw:match("^1|([%w_-]+)|([01])|([hg])|(%d+)|(%d+)$")
            if world and tonumber(cycle)==(tonumber(SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) or 0)
                and GlobalsGetValue("nh_ew.world_mark","")==world then
                status={world=world,gold=gold=="1",role=role,heartbeat=tonumber(beat)}
            end
        end
        if status and (now<status.heartbeat or now-status.heartbeat>45) then status=nil end
    end
    return status
end

function M.ready() return session()~=nil end
function M.world() local s=session(); return s and s.world end
function M.walletAllowed()
    if not M.enabled() then return true end
    local s=session()
    return s~=nil and not s.gold
end
function M.rescueAllowed() return not M.enabled() end
function M.localBody(entity)
    return entity and entity~=0 and (not M.enabled() or
        (not EntityHasTag(entity,"ew_client") and not EntityHasTag(entity,"ew_notplayer") and not EntityHasTag(entity,"nh_ew_waiting")))
end

function M.releaseWinner(world,holder,key)
    if not CrossCall or M.world()~=world or M.issuer()~=holder then return end
    -- Some EW CrossCall wrappers discard return values. This single
    -- synchronous reply slot also avoids persisting one global per ticket.
    local field="nh_ew.release_winner"
    if GlobalsGetValue(field,"")~="" then GlobalsSetValue(field,"") end
    if not pcall(CrossCall,"ew_hideout_release_winner",world,holder,key) then return end
    local winner=GlobalsGetValue(field,"")
    if winner~="" then
        GlobalsSetValue(field,"")
        return winner:match("^(%w+)|([1-9]%d*)$")
    end
end

-- Poll the same transaction through retries and reconnects. Only a host
-- receipt for this exact issuer, sequence and set of identities can settle it.
function M.itemTransaction(tx, action, keys)
    local s=session()
    local issuer=M.issuer()
    if not s or not issuer or type(keys)~="table" or #keys<1 or #keys>2 then return end
    if type(tx)=="number" and tx>=1 and tx<=999999999999999 and tx==math.floor(tx) then tx=("%.0f"):format(tx) end
    if type(tx)~="string" or #tx>15 or not tx:match("^[1-9]%d*$")
        or (action~="prepare" and action~="commit" and action~="cancel") then return end
    for i=1,#keys do
        if type(keys[i])~="string" or keys[i]=="" or keys[i]:find("[,|]") then return end
    end
    local identity=table.concat({s.world,issuer,tx,table.concat(keys,",")},"|")
    local field="nh_ew.item_tx_reply"
    -- A loaded world may still contain a grant from before the host settled
    -- this transaction. Re-read the durable host record on first use.
    if lastItemTransaction~=identity then
        lastItemTransaction=identity
        GlobalsSetValue(field,"")
    end
    local reply=GlobalsGetValue(field,"")
    local result=reply:sub(1,#identity+1)==identity.."|" and reply:sub(#identity+2)
    if result=="done" or result=="cancelled" or result=="denied" or (action=="prepare" and result=="granted") then
        return result
    end
    local request=identity.."|"..action
    if GlobalsGetValue("nh_ew.item_request","")~=request then GlobalsSetValue("nh_ew.item_request",request) end
end
return M
