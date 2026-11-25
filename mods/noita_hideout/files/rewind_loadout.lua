-- The watch annotates the actual carried entities. Warehouse records and new
-- pickups never receive these markers. Engine component/entity IDs may change
-- when a save is loaded, so the markers themselves carry the snapshot.
local M={}
local tag="nh_rewind_equipment"
local hook="nh_rewind_throw"
local rigTag="nh_rewind_rig"
local shieldTag="nh_rewind_shield"
local shieldRuntime
local first=EntityGetFirstComponentIncludingDisabled
local get,set=ComponentGetValue2,ComponentSetValue2

local function shields()
    shieldRuntime=shieldRuntime or dofile("mods/noita_hideout/files/shield_runtime.lua")
    return shieldRuntime
end

local function scope(token)
    if token:match("^%d+/%d+/%w+/%d+$") then return token end
    -- Old records used a separate issuer prefix. During a continue the
    -- profile binding can be available before the EW handshake publishes it.
    local owner
    if NHEW and NHEW.enabled() then
        owner=NHEW.issuer()
        local profile=token:match("^(%d+)/")
        if not owner and profile and ModSettingGet then owner=ModSettingGet("noita_hideout.ew_owner_"..profile) end
    end
    return (type(owner)=="string" and owner:match("^%w+$") or "solo").."/"..token
end

local function attach(entity,kind,fields)
    local component=EntityAddComponent2(entity,kind,fields)
    return component and component~=0
end

local function rigKey(s)
    local row=s and s.gearRig
    return row and table.concat({s.profile,s.runSerial,row.id,row.epoch or 0,row.item.kind},"/") or ""
end

local function shieldKey(s)
    local row=s.gearShield
    -- The regular epoch also changes when a charger repairs the same shield.
    return row and table.concat({s.profile,s.runSerial,row.id,row.equippedAt or 0,row.item.kind},"/") or ""
end

local function inspect(entity,kind)
    local item=first(entity,"ItemComponent")
    if not item then return end
    if NHGuns.types[kind] then
        local n=NHGuns.physicalRounds(kind,entity,item)
        if NHStore.validBandageCount(n) then return n end
    elseif NHFirearms.items[kind] and NHFirearms.items[kind].magazine then
        local mag=first(entity,"VariableStorageComponent","nh_magazine")
        if mag and get(mag,"name")==kind then
            NHFirearms.prepareMagazine(entity,mag)
            return get(mag,"value_int")
        end
    end
end

local function unpackMark(c)
    local owner,serial,kind,picked,initial=get(c,"value_string"):match("^([^|]+)|(%d+)|(%w[%w_]*)|(-?%d+)|([^|]+)")
    return owner,serial,kind,tonumber(picked),tonumber(initial)
end

-- A reload appends the number of unspent loaded rounds to its stable identity.
-- value_float holds the subset that came from outside the opening reserve.
local function reloadBalance(c)
    local raw=get(c,"value_string")
    local identity,loaded=raw:match("^(.-)|r(%d+)$")
    return identity or raw,tonumber(loaded) or 0
end

-- Also called by the native throw callback, before the item can be picked up
-- by anyone (including its previous owner).
function M.abandon(entity)
    local mark=first(entity,"VariableStorageComponent",tag)
    if not mark then return end
    local _,_,kind=unpackMark(mark)
    local item=first(entity,"ItemComponent")
    local empty=kind~="wand" and item and get(mark,"value_bool") and get(item,"uses_remaining")==0
    EntityRemoveComponent(entity,mark)
    local callback=first(entity,"LuaComponent",hook)
    if callback then EntityRemoveComponent(entity,callback) end
    EntityRemoveTag(entity,tag)
    if empty then
        local owner=EntityGetRootEntity(entity)
        if owner~=entity and EntityHasTag(owner,"player_unit") then GameKillInventoryItem(owner,entity)
        else EntityKill(entity) end
    end
end

local function available(state,player,id)
    return EntityGetRootEntity(id)==player and not (NHEWItems and NHEWItems.lockInfo(id))
        and NHTransfers.available(state,player,id)
end

function M.capture(state,player,token)
    if state.gearShield then
        shields().snapshot(state,player)
        local item=state.gearShield.item
        if not attach(player,"VariableStorageComponent",{_tags=shieldTag,name=token,
            value_string=shieldKey(state).."|"..(item.delay or 0),value_int=item.charge,value_float=item.repair or 0}) then return false end
    end
    local rig=state.gearRig
    if rig and not attach(player,"VariableStorageComponent",{_tags=rigTag,
        name=token,value_string=rigKey(state),value_int=rig.item.reserve,value_float=0}) then return false end
    for i,id in ipairs(NHTransfers.carried(player)) do
        if available(state,player,id) then
            local kind=NHTransfers.item_kind(id)
            local n=inspect(id,kind)
            if n then
                if first(id,"VariableStorageComponent",tag) then M.abandon(id) end
                local picked=get(first(id,"ItemComponent"),"mFramePickedUp") or -1
                local data=table.concat({scope(token),i,kind,picked,("%.17g"):format(n)},"|")
                if not attach(id,"VariableStorageComponent",{_tags=tag,name=tag,value_string=data,
                    value_int=0,value_float=0,value_bool=NHGuns.types[kind]~=nil}) then return false end
                EntityAddTag(id,tag)
                if not attach(id,"LuaComponent",{_tags=hook..",enabled_in_world,enabled_in_hand,enabled_in_inventory",
                    script_throw_item="mods/noita_hideout/files/rewind_throw.lua",execute_every_n_frame=-1}) then return false end
            end
        end
    end
    return true
end

local function current(player,id,token)
    local mark=first(id,"VariableStorageComponent",tag)
    if not mark or EntityGetRootEntity(id)~=player then return end
    local owner,serial,kind,picked,initial=unpackMark(mark)
    local item=first(id,"ItemComponent")
    if owner==scope(token) and item and picked==(get(item,"mFramePickedUp") or -1)
        and not (NHEWItems and NHEWItems.lockInfo(id)) then return mark,serial,kind,initial end
end

local function activeMark(player,id)
    if not EntityHasTag(id,tag) or not EntityHasTag(player,"nh_rewind_armed") then return end
    local watch=first(player,"VariableStorageComponent","nh_rewind_snapshot")
    if watch then return current(player,id,get(watch,"name")) end
end

-- Called only after a projectile has actually been allocated and paid for.
-- Record just the shots attributable to the original stack. A later merge
-- keeps its added rounds and cannot expand this allowance.
function M.spentRound(player,id)
    local mark,_,_,limit=activeMark(player,id)
    if mark and get(mark,"value_bool") then
        set(mark,"value_int",math.min(limit,get(mark,"value_int")+1))
    end
end

function M.reloaded(state,player,id,amount,before)
    local watch=first(player,"VariableStorageComponent","nh_rewind_snapshot")
    if not watch then return end
    local token=get(watch,"name")
    local rig=first(player,"VariableStorageComponent",rigTag)
    local eligible=0
    if rig and get(rig,"name")==token and get(rig,"value_string")==rigKey(state) then
        -- Original reserve spent on a new or handed-off gun cannot be claimed
        -- by a later reload of a different gun.
        local debited=get(rig,"value_float") or 0
        eligible=math.min(amount,get(rig,"value_int")-debited)
        set(rig,"value_float",debited+eligible)
    end
    local mark=current(player,id,token)
    if not mark then return end
    local identity,loaded=reloadBalance(mark)
    set(mark,"value_string",identity.."|r"..(math.min(before,loaded)+amount))
    set(mark,"value_float",math.min(before,get(mark,"value_float") or 0)+amount-eligible)
    set(mark,"value_int",get(mark,"value_int")+eligible)
end

function M.cancel(player,token)
    local owner=scope(token)
    for _,id in ipairs(EntityGetWithTag(tag) or {}) do
        local mark=first(id,"VariableStorageComponent",tag)
        if mark and unpackMark(mark)==owner then M.abandon(id) end
    end
    local rig=first(player,"VariableStorageComponent",rigTag)
    if rig and get(rig,"name")==token then EntityRemoveComponent(player,rig) end
    local shield=first(player,"VariableStorageComponent",shieldTag)
    if shield and get(shield,"name")==token then EntityRemoveComponent(player,shield) end
end

local function settled(row,state,frame)
    return row.rewindRun==state.runSerial and (row.rewindFrame or -1)>=frame
end

function M.restore(state,player,token,commit)
    local matches,seen={},{}
    for _,id in ipairs(NHTransfers.carried(player)) do
        local mark,serial,kind,initial=current(player,id,token)
        if mark and available(state,player,id) and NHTransfers.item_kind(id)==kind then
            -- An externally cloned marker cannot redeem the same slot twice.
            matches[serial]=not seen[serial] and {id=id,mark=mark,kind=kind,initial=initial,serial=tonumber(serial)} or nil
            seen[serial]=true
        end
    end
    local slots={}
    local credit=0
    for _,slot in pairs(matches) do
        slots[#slots+1]=slot
        if NHFirearms.items[slot.kind] and NHFirearms.items[slot.kind].magazine then
            local mag=first(slot.id,"VariableStorageComponent","nh_magazine")
            if mag and get(mag,"name")==slot.kind then
                slot.mag=mag
                credit=credit+get(slot.mark,"value_int")
            end
        end
    end
    table.sort(slots,function(a,b) return a.serial<b.serial end)
    local rig=first(player,"VariableStorageComponent",rigTag)
    local frame=tonumber(token:match("/(%d+)$"))
    local shield=first(player,"VariableStorageComponent",shieldTag)
    local identity,delay
    if shield and get(shield,"name")==token then identity,delay=get(shield,"value_string"):match("^([^|]+)|(%d+)$") end
    local sameRig=rig and get(rig,"name")==token and get(rig,"value_string")==rigKey(state)
    local refund=credit>0 and frame and sameRig and not settled(state.gearRig,state,frame)
    local repair=identity and frame and identity==shieldKey(state) and not settled(state.gearShield,state,frame)
    local paidRig=sameRig and state.gearRig
    local restoredShield
    if refund or repair then
        if not commit(function(draft)
            sameRig=sameRig and rigKey(draft)==get(rig,"value_string")
            if refund and sameRig and not settled(draft.gearRig,draft,frame) then
                local row=draft.gearRig
                local capacity=NHFirearms.rigs[row.item.kind].capacity
                local total=row.item.reserve+math.min(credit,get(rig,"value_int"))
                row.item.reserve=math.min(capacity,total)
                row.rewindOverflow=total>capacity and total-capacity or nil
                row.rewindRun,row.rewindFrame=draft.runSerial,frame
                paidRig=row
            end
            if repair and identity==shieldKey(draft) and not settled(draft.gearShield,draft,frame) then
                local row=draft.gearShield
                row.item.charge,row.item.repair,row.item.delay=get(shield,"value_int"),get(shield,"value_float"),tonumber(delay)
                -- A new meter epoch makes the normal shield sync consume the
                -- committed values. A save cannot overwrite them with the old meter.
                row.epoch=draft.revision+1
                row.rewindRun,row.rewindFrame=draft.runSerial,frame
                restoredShield=draft
            end
            return true
        end) then return false end
        if restoredShield then shields().sync(restoredShield,player) end
    end
    -- When a resupply filled the rig, leave unspent overflow in the original
    -- magazines. The profile receipt and the surviving marker cover a retry.
    local overflow=0
    if sameRig and paidRig.rewindRun==state.runSerial and paidRig.rewindFrame==frame and paidRig.rewindOverflow then
        overflow=get(rig,"value_bool") and get(rig,"value_float") or paidRig.rewindOverflow
        set(rig,"value_bool",true)
        set(rig,"value_float",overflow)
    end
    for _,slot in ipairs(slots) do
        local id,kind=slot.id,slot.kind
        if NHGuns.types[kind] then
            local item=first(id,"ItemComponent")
            local now=get(item,"uses_remaining")
            if now>=0 then set(item,"uses_remaining",math.min(2147483647,now+get(slot.mark,"value_int"))) end
        elseif kind=="wand" then
            -- Only pending pre-0.42.43 settlements can have a marked wand.
            local ability=first(id,"AbilityComponent")
            if ability then set(ability,"mana",math.min(slot.initial,get(ability,"mana_max"))) end
        elseif slot.mag then
            local _,loaded=reloadBalance(slot.mark)
            local present=get(slot.mag,"value_int")
            local keep=math.min(present,sameRig and (get(slot.mark,"value_float") or 0) or loaded)
            local capacity=NHFirearms.items[kind].magazine
            local rounds=math.min(capacity,slot.initial+keep)
            if overflow>0 then
                local extra=math.min(overflow,math.min(loaded,present)-keep,capacity-rounds)
                rounds,overflow=rounds+extra,overflow-extra
                set(rig,"value_float",overflow)
            end
            set(slot.mag,"value_int",rounds)
            local ability=first(id,"AbilityComponent")
            if ability then set(ability,"mana",rounds) end
        end
        -- Retire each successful physical delivery before touching the next
        -- slot. A later failure cannot refund the first launcher twice.
        M.abandon(id)
    end
    M.cancel(player,token)
    return true
end
return M
