-- Each expedition saves the transaction number and its keys once. The reverse
-- lookup is needed only while reconciling physical items and lives in RAM.
local H={}
local indexes=setmetatable({},{__mode="k"})
local function copy(t)
    local out={}
    for k,v in pairs(t or {}) do out[k]=v end
    return out
end
local function validKey(k)
    if #k>156 then return false end
    local gid=k:match("^g/(%d+)$")
    return (gid and #gid<=20) or k:match("^t/ew/%w+/r/%d+/%d+/%d+/%d+/%d+/%d+$")~=nil
end
local function keys(packed)
    if type(packed)~="string" then return end
    local first,second=packed:match("^([^,]+),([^,]+)$")
    if first then
        if first<second and validKey(first) and validKey(second) then return first,second end
    elseif validKey(packed) then return packed end
end
local function parts(token)
    if type(token)~="string" then return end
    local world,owner,tx=token:match("^([%w_-]+)|(%w+)|([1-9]%d*)$")
    if world and #world<=170 and #owner<=40 and #tx<=15 then return world,owner,tx end
end

function H.compact(history,world)
    if not history or not world or history.owners then return history end
    local owners={}
    for token,value in pairs(history) do
        local scope,owner,tx=parts(token)
        if scope then
            if scope~=world then return history end
            if value~="cancelled" then
                local a,b=keys(value)
                if not a or history[a]~=token or (b and history[b]~=token) then return history end
            end
            local entries=owners[owner] or {}
            owners[owner]=entries
            if value=="cancelled" then entries[tx]=false else entries[tx]=value end
        else
            -- Keep an unfamiliar legacy ledger exactly as read. Do not
            -- create new cleanup authority from a missing or stale index.
            local a,b=keys(history[value])
            if not a or (token~=a and token~=b) or not parts(value) then return history end
        end
    end
    return {world=world,owners=owners}
end

function H.add(history,world,owner,tx,itemKeys)
    local packed=itemKeys and table.concat(itemKeys,",") or false
    history=H.compact(history,world) or {world=world,owners={}}
    if not history.owners then
        local nextHistory=copy(history)
        local token=world.."|"..owner.."|"..tx
        nextHistory[token]=packed or "cancelled"
        for _,key in ipairs(itemKeys or {}) do nextHistory[key]=token end
        return nextHistory
    end
    assert(history.world==world,"Deposit history belongs to another world")
    local owners=copy(history.owners)
    if owners[owner] and owners[owner][tx]==packed then return history end
    local entries=copy(owners[owner])
    owners[owner]=entries
    entries[tx]=packed
    return {world=world,owners=owners}
end

function H.outcome(history,world,owner,tx)
    if not history then return end
    if not history.owners then return history[world.."|"..owner.."|"..tx] end
    if history.world~=world then return end
    local entries=history.owners[owner]
    if entries then
        if entries[tx]==false then return "cancelled" end
        return entries[tx]
    end
end

function H.lookup(history,world,owner,key)
    if not history or not key then return end
    if not history.owners then
        local token=history[key]
        local scope,who,tx=parts(token)
        if scope==world and who==owner then
            local a,b=keys(history[token])
            if key==a or key==b then return tx end
        end
        return
    end
    local entries=history.world==world and history.owners[owner]
    if not entries then return end
    local index=indexes[entries]
    if not index then
        index={}
        for tx,packed in pairs(entries) do
            local a,b=keys(packed)
            if a then
                -- An ambiguous identifier cannot prove a completed transfer.
                if index[a]==nil then index[a]=tx else index[a]=false end
                if b then
                    if index[b]==nil then index[b]=tx else index[b]=false end
                end
            end
        end
        indexes[entries]=index
    end
    return index[key] or nil
end
return H
