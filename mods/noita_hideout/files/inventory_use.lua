-- Operations on an NHStore.load() draft. The caller commits the charge before
-- applying the effect. No inventory item needs to be spawned or equipped.
local M={}
local equipment=NHEquipment or dofile("mods/noita_hideout/files/equipment.lua")
local bags=NHLootBags or dofile("mods/noita_hideout/files/loot_bags.lua")
local foods={}
for _,food in ipairs(dofile("mods/noita_hideout/files/cooking.lua")) do foods[food.id]=true end

function M.supports(kind)
    return (NHShields and NHShields.supply(kind)~=nil) or bags.types[kind]~=nil or foods[kind] or kind=="bandage" or kind=="dose" or kind=="summon_card" or equipment.links[kind]~=nil
        or NHMedkits.types[kind]~=nil or NHSurgeryKits.types[kind]~=nil or NHThrowables.types[kind]~=nil
end

local function maxUses(kind,species)
    if foods[kind] then return NHFoods.byId[kind].uses end
    if kind=="dose" then return NHStore.doseDurability end
    if kind=="summon_card" then return NHCompanions.cardCapacity(species) end
    if equipment.links[kind] then return equipment.links[kind].uses end
    local kit=NHMedkits.types[kind] or NHSurgeryKits.types[kind] or (NHShields and NHShields.supply(kind))
    return kit and kit.uses
end

local function location(state,player,ref)
    if not state or state.runSerial<=state.closedThrough or type(ref)~="table" or not M.supports(ref.kind) then return end
    local item,cells,index,pouch,wallet
    if ref.container=="warehouse" or ref.container=="safe" then
        if not ref.slot or not ref.storedId then return end
        index=NHStore.slotIndex(state,ref.container,ref.slot,ref.kind)
        local row=index and state[ref.container][index]
        if not row or row.id~=ref.storedId then return end
        item=row.item
    elseif ref.container=="gear" then
        local row=state[NHShields.field(ref.kind)]
        if not row or row.id~=ref.storedId then return end
        item=row.item
    elseif ref.container=="pouch" and ref.cell and ref.kind=="dose" then
        pouch=state.pouches[ref.pouchId]
        if not pouch then return end
        cells,index=pouch.cells,ref.cell
        local cell=cells[index]
        if cell then item={kind="dose",subtype=cell.subtype,remaining=cell.remaining,count=cell.count} end
    elseif ref.container=="card_wallet" and ref.cell and ref.kind=="summon_card" then
        local row=NHCardWallets.get(state,player,ref.wallet)
        if not row then return end
        wallet=row.item
        cells,index=wallet.cells,ref.cell
        item=cells[index]
    end
    if not item or item.kind~=ref.kind or (ref.count or 1)~=(item.count or 1) then return end
    local full=maxUses(item.kind,item.species)
    local remaining=equipment.linkUses(item.kind,item.remaining) or item.remaining or full
    if (ref.remaining or full)~=remaining then return end
    if item.kind=="dose" and (item.subtype or "fire")~=(ref.subtype or "fire") then return end
    if item.kind=="summon_card" and item.species~=ref.species then return end
    return item,index,cells,pouch,wallet
end

function M.peek(state,player,ref)
    local item=location(state,player,ref)
    return item
end

local function freeCell(cells,capacity)
    for slot=1,capacity do if not cells[slot] then return slot end end
end

-- In a full container, other full-condition stacks can absorb the untouched
-- units and leave the clicked cell available for the partially used one.
local function mergeUntouched(state,ref,item,sourceIndex,cells,cellCapacity,quantity)
    local rows=state[ref.container]
    local moves={}
    for i=1,cellCapacity or #rows do
        local other
        if cells then other=cells[i] else other=rows[i].item end
        if i~=sourceIndex and other and (not other.kind or other.kind==item.kind) then
            local compatible=item.kind=="dose" and NHStore.acceptsDose(other,NHStore.doseDurability,item.subtype)
                or item.kind=="summon_card" and NHCompanions.canStack(other,item)
            if compatible then
                local take=math.min(quantity,NHStore.maxResourceAmount-(other.count or 1))
                moves[#moves+1]={item=other,count=(other.count or 1)+take}
                quantity=quantity-take
                if quantity==0 then
                    for _,move in ipairs(moves) do move.item.count=move.count end
                    return true
                end
            end
        end
    end
    return false
end

function M.spend(draft,player,ref)
    local item,index,cells,pouch,wallet=location(draft,player,ref)
    if not item then return nil,"Inventory slot changed." end
    local count=item.count or 1
    local remaining=equipment.linkUses(item.kind,item.remaining) or item.remaining or maxUses(item.kind,item.species) or 1
    local source=cells and cells[index] or item
    if NHMedkits.capacity(item.kind) then
        local left=NHMedkits.charges(item)-1
        if left>0 then NHMedkits.unpack(item,left)
        elseif ref.container=="gear" then draft[NHShields.field(ref.kind)]=nil
        else table.remove(draft[ref.container],index) end
    elseif foods[item.kind] and NHFoods.bites(item)>1 then
        NHFoods.setBites(item,NHFoods.bites(item)-1)
    elseif count>1 and remaining>1 then
        -- Only full syringes and summon cards can stack. Keep the untouched
        -- units in place and put the worn one in the same container.
        local slot,capacity
        if cells then
            capacity=pouch and NHEquipment.get("pouch",pouch.tier).capacity or NHEquipment.get("card_wallet",wallet.tier).capacity
            slot=freeCell(cells,capacity)
        else
            slot=NHStore.freeSlot(draft,ref.container,nil,item.kind)
        end
        if not slot or (not cells and draft.nextItemId>=NHStore.maxResourceAmount) then
            if mergeUntouched(draft,ref,item,index,cells,capacity,count-1) then
                source.count,source.remaining=1,remaining-1
                return true
            end
            return nil,slot and "Item ID limit reached." or "Need a free slot for the used item."
        end
        local worn={}
        for k,v in pairs(source) do worn[k]=v end
        worn.count,worn.remaining=1,remaining-1
        source.count=count-1
        if cells then cells[slot]=worn
        else
            table.insert(draft[ref.container],{id=draft.nextItemId,slot=slot,item=worn})
            draft.nextItemId=draft.nextItemId+1
        end
    elseif remaining>1 then
        source.remaining=remaining-1
    elseif count>1 then
        source.count=count-1
    elseif ref.container=="gear" then
        draft[NHShields.field(ref.kind)]=nil
    elseif cells then
        cells[index]=nil
        if pouch then pouch.doses=pouch.doses-1 end
    else
        table.remove(draft[ref.container],index)
    end
    return true
end

return M
