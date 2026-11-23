-- An injector belongs to one pouch cell, secure slot, or issued entity.
-- The live token list is authoritative even when a world save is older.
NHDoses = {}

local item_tag = "noita_hideout_dose"
local token_tag = "noita_hideout_dose_token"

local function copy(t)
    local result = {}
    for k, v in pairs(t or {}) do result[k] = v end
    return result
end

local function draft(state)
    local s = copy(state)
    s.warehouse = copy(state.warehouse)
    s.safe = copy(state.safe)
    s.pouches = copy(state.pouches)
    s.issuedDoses = copy(state.issuedDoses)
    return s
end

-- Only the selected bag's cells are edited in a transaction.
local function edit_pouch(s,id)
    local pouch=s.pouches[id]
    if not pouch then return end
    local p=copy(pouch)
    p.cells=copy(pouch.cells)
    s.pouches[id]=p
    return p
end

local function commit(state, changed)
    local ok, err = NHStore.commit(changed)
    if not ok then return nil, err end
    state.revision, state.nextItemId = changed.revision, changed.nextItemId
    state.warehouse = changed.warehouse
    state.summons, state.dragonLoot = changed.summons, changed.dragonLoot
    state.gelBonus,state.resources=changed.gelBonus,changed.resources
    state.safe = changed.safe
    state.pouches, state.issuedDoses = changed.pouches, changed.issuedDoses
    return true
end

local function token_of(entity,tag)
    local c = EntityGetFirstComponentIncludingDisabled(entity, "VariableStorageComponent", tag or token_tag)
    if c and c ~= 0 then return ComponentGetValue2(c, "value_string") end
end

local function receipt(token)
    return "noita_hideout.dose_delivered." .. token
end

local function dispose(player, entity)
    if EntityGetRootEntity(entity) == player then
        GameKillInventoryItem(player, entity)
    else
        EntityKill(entity)
    end
end

local function is_open_run(s)
    return s.runSerial > s.closedThrough
end

local pouch_tag = "noita_hideout_pouch_token"

function NHDoses.isPouch(s, entity)
    if not entity or entity==0 or not EntityGetIsAlive(entity) or NHNative.kind(entity)~="pouch" then return end
    local token=token_of(entity,pouch_tag)
    if not token then return end
    for id,p in pairs(s.pouches) do
        if p.location=="bag" and p.token==token then return id end
    end
end

function NHDoses.takePouch(s, player, deliver, pouchId)
    local pouch=s.pouches[pouchId]
    if not is_open_run(s) or not pouch or (pouch.location~="safe" and pouch.location~="warehouse") then return nil, "Pouch unavailable." end
    local x, y = EntityGetTransform(player)
    local id, err = NHNative.spawn("pouch", x, y - 4, pouch.tier)
    if not id then return nil, err end
    local changed = draft(s)
    local token = table.concat({s.profile,s.runSerial,s.nextItemId,GameGetFrameNum(),id}, "/")
    local c = EntityAddComponent2(id, "VariableStorageComponent", {_tags=pouch_tag, name=pouch_tag, value_string=token})
    if not c or c==0 or token_of(id,pouch_tag)~=token then
        EntityKill(id)
        return nil, "Could not mark the pouch."
    end
    changed.pouches[pouchId]={id=pouchId,location="bag",token=token,originContainer=pouch.location,
        slot=pouch.slot,x=x,y=y,tier=pouch.tier,doses=pouch.doses,cells=pouch.cells}
    changed.nextItemId = changed.nextItemId + 1
    if deliver and not deliver(id) then
        dispose(player, id)
        return nil, "Inventory slot changed."
    end
    local ok, reason = commit(s, changed)
    if not ok then dispose(player, id); return nil, reason end
    GlobalsSetValue(receipt(token), "1")
    return true, id
end

function NHDoses.storePouch(s, player, id, preferred, container, ground)
    container=container or "safe"
    local pouchId=NHDoses.isPouch(s,id)
    if not is_open_run(s) or not pouchId or EntityGetRootEntity(id) ~= (ground and id or player) then
        return nil, "Hold your injector pouch first."
    end
    local changed = draft(s)
    local slot = NHStore.freeSlot(s,container,preferred,"pouch")
    if not slot then return nil, "Secure valuables slot is full." end
    local pouch=s.pouches[pouchId]
    changed.pouches[pouchId]={id=pouchId,location=container,slot=slot,tier=pouch.tier,cells=pouch.cells,doses=pouch.doses}
    local ok, reason = commit(s, changed)
    if not ok then return nil, reason end
    dispose(player, id)
    return true
end

local function add_stored_dose(s,slot,remaining,container,subtype)
    container=container or "safe"
    local rows=s[container]
    local index=NHStore.slotIndex(s,container,slot,"dose")
    local row=index and rows[index]
    if row then
        if row.item.kind~="dose" or not NHStore.acceptsDose(row.item,remaining,subtype) then return false end
        row=copy(row)
        row.item={kind="dose",subtype=subtype,remaining=remaining,count=(row.item.count or 1)+1}
        rows[index]=row
    else
        if not NHStore.freeSlot(s,container,slot,"dose") then return false end
        table.insert(rows,{id=s.nextItemId,slot=slot,item={kind="dose",subtype=subtype,remaining=remaining,count=1}})
        s.nextItemId=s.nextItemId+1
    end
    return true
end

local function take_stored_dose(s,slot,container)
    container=container or "safe"
    local rows=s[container]
    local index=NHStore.slotIndex(s,container,slot,"dose")
    local row=index and rows[index]
    if not row or row.item.kind~="dose" then return end
    local remaining=row.item.remaining or NHStore.doseDurability
    local subtype=row.item.subtype
    if (row.item.count or 1)>1 then
        row=copy(row)
        row.item={kind="dose",subtype=subtype,remaining=remaining,count=row.item.count-1}
        rows[index]=row
    else table.remove(rows,index) end
    return remaining,subtype
end

function NHDoses.moveDose(s,slot,to_safe,cell,container,pouchId)
    if not is_open_run(s) or not s.pouches[pouchId] then return nil,"Pouch unavailable." end
    local changed=draft(s)
    local pouch=edit_pouch(changed,pouchId)
    local remaining,subtype
    if to_safe then
        remaining,subtype=NHStore.takePouchDose(pouch,cell or 1)
        if not remaining or not add_stored_dose(changed,slot,remaining,container,subtype) then return nil,"Slot unavailable." end
    else
        remaining,subtype=take_stored_dose(changed,slot,container)
        if not remaining or not NHStore.putPouchDose(pouch,remaining,cell,subtype) then return nil,"Slot unavailable." end
    end
    return commit(s,changed)
end

function NHDoses.moveSafeDose(s,source,target,container)
    if not is_open_run(s) or source==target then return nil,"Slot unavailable." end
    local changed=draft(s)
    local remaining,subtype=take_stored_dose(changed,source,container)
    if not remaining or not add_stored_dose(changed,target,remaining,container,subtype) then return nil,"Slot unavailable." end
    return commit(s,changed)
end

function NHDoses.moveCell(s,source,target,pouchId,targetPouchId)
    targetPouchId=targetPouchId or pouchId
    if not is_open_run(s) or (pouchId==targetPouchId and source==target) then return nil,"Slot unavailable." end
    local changed=draft(s)
    local from=edit_pouch(changed,pouchId)
    local to=pouchId==targetPouchId and from or edit_pouch(changed,targetPouchId)
    if not from or not to then return nil,"Pouch unavailable." end
    local remaining,subtype=NHStore.takePouchDose(from,source)
    if not remaining or not NHStore.putPouchDose(to,remaining,target,subtype) then return nil,"Slot unavailable." end
    return commit(s,changed)
end

function NHDoses.remaining(s,entity)
    local token=token_of(entity)
    local record=token and s.issuedDoses and s.issuedDoses[token]
    if record then return record.remaining or NHStore.doseDurability,record.subtype or "fire" end
end

local function show_remaining(entity,remaining)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    if item then ComponentSetValue2(item,"uses_remaining",remaining) end
end

-- The bag payment owns this draft. Only publish the reward if payment succeeds.
function NHDoses.registerLoot(s,entity,subtype,storedBag)
    local x,y=EntityGetTransform(entity)
    local token=table.concat({s.profile,s.runSerial,s.nextItemId,GameGetFrameNum(),entity},"/")
    local c=EntityAddComponent2(entity,"VariableStorageComponent",{_tags=token_tag,name=token_tag,value_string=token})
    if not c or token_of(entity)~=token then return false,"Could not mark the syringe." end
    s.issuedDoses=s.issuedDoses or {}
    s.issuedDoses[token]={x=x,y=y,loot=true,storedBag=storedBag,remaining=NHStore.doseDurability,subtype=subtype}
    s.nextItemId=s.nextItemId+1
    show_remaining(entity,NHStore.doseDurability)
    return true
end

function NHDoses.confirmLoot(entity)
    GlobalsSetValue(receipt(token_of(entity)),"1")
end

function NHDoses.withdraw(s, player, deliver, pouchEntity, safe_slot, cell, container, pouchId)
    if not is_open_run(s) then return nil,"Run already closed." end
    local changed=draft(s)
    local remaining,subtype
    if safe_slot then remaining,subtype=take_stored_dose(changed,safe_slot,container)
    else
        local pouch=edit_pouch(changed,pouchId)
        if not pouch then return nil,"Pouch unavailable." end
        if pouch.location=="bag" then
            local owner=pouchEntity or NHNative.held(player)
            if NHDoses.isPouch(s,owner)~=pouchId or EntityGetRootEntity(owner)~=player then return nil,"Hold your injector pouch first." end
        end
        remaining,subtype=NHStore.takePouchDose(pouch,cell or 1)
    end
    if not remaining then return nil,"No dose available." end
    local x, y = EntityGetTransform(player)
    y = y - 4
    local entity, err = NHNative.spawn("dose", x, y,subtype)
    if not entity or entity == 0 then return nil, err or "Could not create a syringe." end
    local token = table.concat({s.profile, s.runSerial, s.nextItemId, GameGetFrameNum(), entity}, "/")
    local c = EntityAddComponent2(entity, "VariableStorageComponent", {
        _tags = token_tag, name = token_tag, value_string = token,
    })
    if not c or c == 0 or token_of(entity) ~= token then
        EntityKill(entity)
        return nil, "Could not mark the syringe. It remains in the pouch."
    end
    changed.nextItemId = changed.nextItemId + 1
    changed.issuedDoses[token] = {x=x,y=y,safeSlot=safe_slot,container=container,
        pouchId=not safe_slot and pouchId or nil,cell=cell,remaining=remaining,subtype=subtype}
    show_remaining(entity,remaining)
    if deliver and not deliver(entity) then
        dispose(player, entity)
        return nil, "Inventory slot changed."
    end
    local ok, problem = commit(s, changed)
    if not ok then dispose(player, entity); return nil, problem end
    GlobalsSetValue(receipt(token), "1")
    return true, entity
end

local function retire(s, player, entity, to_pouch, fromInventory, slot, cell, container, pouchId, ground)
    if not is_open_run(s) then return nil, "Run already closed." end
    if not entity or entity == 0 or not EntityGetIsAlive(entity) or NHNative.kind(entity) ~= "dose" then
        return nil, "Select a syringe."
    end
    if to_pouch then
        if not slot and not s.pouches[pouchId] then return nil, "Pouch unavailable." end
        if EntityGetRootEntity(entity) ~= (ground and entity or player) then
            return nil, "The selected item is no longer in your quick inventory."
        end
    elseif (not fromInventory and NHNative.held(player) ~= entity) or EntityGetRootEntity(entity) ~= player then
        return nil, "Select a syringe."
    end
    local token = token_of(entity)
    if not token or not s.issuedDoses or not s.issuedDoses[token] then
        return nil, "This syringe is no longer available."
    end
    local changed = draft(s)
    local remaining=changed.issuedDoses[token].remaining or NHStore.doseDurability
    local subtype=changed.issuedDoses[token].subtype
    if not to_pouch and remaining>1 then
        local record=copy(changed.issuedDoses[token])
        record.remaining=remaining-1
        changed.issuedDoses[token]=record
        local ok,err=commit(s,changed)
        if not ok then return nil,err end
        show_remaining(entity,record.remaining)
        return true,record.remaining
    end
    if to_pouch then
        if slot then
            if not add_stored_dose(changed,slot,remaining,container,subtype) then return nil,"Slot unavailable." end
        elseif not NHStore.putPouchDose(edit_pouch(changed,pouchId),remaining,cell,subtype) then return nil,"Slot unavailable." end
    end
    changed.issuedDoses[token]=nil
    local ok,err=commit(s,changed)
    if not ok then return nil,err end
    dispose(player,entity)
    return true,0
end

function NHDoses.deposit(s,player,entity,slot,cell,container,pouchId,ground)
    return retire(s,player,entity,true,false,slot,cell,container,pouchId,ground)
end

function NHDoses.consume(s, player, entity, fromInventory)
    return retire(s,player,entity,false,fromInventory)
end

function NHDoses.reconcile(s, player)
    if not is_open_run(s) then return true end
    local issued = s.issuedDoses or {}
    local seen, visited = {}, {}
    local missing_pouches={}
    for _,p in pairs(s.pouches) do
        if p.location=="bag" and p.token then missing_pouches[p.token]=p end
    end
    local function inspect(entity)
        if visited[entity] or not EntityGetIsAlive(entity) then return end
        visited[entity] = true
        local kind = NHNative.kind(entity)
        if kind == "pouch" then
            local token=token_of(entity,pouch_tag)
            if token and missing_pouches[token] then
                missing_pouches[token]=nil
                if GlobalsGetValue(receipt(token),"")~="1" then GlobalsSetValue(receipt(token),"1") end
            else dispose(player, entity) end
            return
        end
        if kind ~= "dose" then return end
        local token = token_of(entity)
        if token and issued[token] and not seen[token] then
            seen[token] = true
            show_remaining(entity,issued[token].remaining or NHStore.doseDurability)
            if GlobalsGetValue(receipt(token), "") ~= "1" then GlobalsSetValue(receipt(token), "1") end
        else
            dispose(player, entity)
        end
    end
    -- Prioritize a carried copy when a rolled-back world reintroduces a twin.
    for _, id in ipairs(GameGetAllInventoryItems(player) or {}) do inspect(id) end
    for _, id in ipairs(EntityGetWithTag(item_tag) or {}) do inspect(id) end
    for _, id in ipairs(EntityGetWithTag("noita_hideout_pouch") or {}) do inspect(id) end
    if not next(issued) and not next(missing_pouches) then return true end
    local x, y = EntityGetTransform(player)
    local changed
    for token,pouch in pairs(missing_pouches) do
        if pouch.x and pouch.y and GlobalsGetValue(receipt(token), "") ~= "1"
            and math.abs(x-pouch.x) < 64 and math.abs(y-pouch.y) < 64
            and DoesWorldExistAt(math.floor(pouch.x)-16, math.floor(pouch.y)-16, math.ceil(pouch.x)+16, math.ceil(pouch.y)+16) then
            local container=pouch.originContainer or "safe"
            local current=changed or s
            local slot=NHStore.freeSlot(current,container,pouch.slot,"pouch") or NHStore.freeSlot(current,container,nil,"pouch")
            if slot then
                changed=changed or draft(s)
                changed.pouches[pouch.id]={id=pouch.id,location=container,slot=slot,tier=pouch.tier,cells=pouch.cells,doses=pouch.doses}
            end
        end
    end
    for token, origin in pairs(issued) do
        -- An apparently missing item may have been legitimately used or unloaded.
        -- Refund only if the delivery receipt itself was rewound, and its origin
        -- is nearby and loaded. The old token is retired in that same commit.
        if not seen[token] and GlobalsGetValue(receipt(token), "") ~= "1"
            and math.abs(x - origin.x) < 64 and math.abs(y - origin.y) < 64
            and DoesWorldExistAt(math.floor(origin.x) - 16, math.floor(origin.y) - 16,
                math.ceil(origin.x) + 16, math.ceil(origin.y) + 16)
            and (origin.loot or origin.safeSlot or s.pouches[origin.pouchId]) then
            local candidate=draft(changed or s)
            local remaining=origin.remaining or NHStore.doseDurability
            local recovered
            if origin.loot and not origin.storedBag then
                -- Rewinding the world also restores the unopened carried bag.
                recovered=true
            elseif origin.loot then
                local slot=NHTransfers.storageSlot(candidate,"warehouse",{kind="dose",remaining=remaining,subtype=origin.subtype})
                recovered=slot and add_stored_dose(candidate,slot,remaining,"warehouse",origin.subtype)
            elseif origin.safeSlot then
                recovered=add_stored_dose(candidate,origin.safeSlot,remaining,origin.container,origin.subtype)
                if not recovered then
                    local slot=NHStore.freeSlot(candidate,origin.container or "safe",nil,"dose")
                    recovered=slot and add_stored_dose(candidate,slot,remaining,origin.container,origin.subtype)
                end
            else
                local pouch=edit_pouch(candidate,origin.pouchId)
                recovered=NHStore.putPouchDose(pouch,remaining,origin.cell,origin.subtype)
                    or NHStore.putPouchDose(pouch,remaining,nil,origin.subtype)
            end
            if recovered then
                candidate.issuedDoses[token]=nil
                changed=candidate
            end
        end
    end
    if changed then return commit(s, changed) end
    return true
end
