-- Wallet contents travel with their warehouse row. While carried, the issued
-- entry in the transfer journal owns that row, including changes made in the field.
NHCardWallets={}

function NHCardWallets.empty(tier)
    local d=NHEquipment.get("card_wallet",tier)
    return {kind="card_wallet",tier=d.tier,cells={},icon=d.icon,name=d.name}
end

local function validCell(item,slot)
    return type(slot)=="number" and slot==math.floor(slot) and slot>=1 and slot<=NHEquipment.get("card_wallet",item.tier).capacity
end

function NHCardWallets.valid(item)
    if type(item)~="table" or item.kind~="card_wallet" or type(item.cells)~="table" or not NHEquipment.get("card_wallet",item.tier) then return false end
    for slot,card in pairs(item.cells) do
        if not validCell(item,slot) or type(card)~="table" or card.kind~="summon_card" or not NHCompanions.validCard(card) then return false end
    end
    return true
end

local function copy(data)
    local out={}
    for k,v in pairs(data) do out[k]=v end
    return out
end

function NHCardWallets.registerItem()
    NHTransfers.registerItem("card_wallet",function(entity) return EntityHasTag(entity,"noita_hideout_card_wallet") end,{
        warehouseCategory="equipment",
        capture=function(entity,state)
            local release=NHTransfers.issuedRecord(state,entity)
            if release then return release.row.item end
            for tier,d in ipairs(NHEquipment.card_wallet) do
                if tier>1 and EntityHasTag(entity,"noita_hideout_"..d.filename) then return NHCardWallets.empty(tier) end
            end
            return NHCardWallets.empty(1)
        end,
        restore=function(item,x,y)
            if not NHCardWallets.valid(item) then return nil,"Invalid card wallet." end
            local entity=EntityLoad("mods/noita_hideout/files/items/"..NHEquipment.get("card_wallet",item.tier).filename..".xml",x,y)
            if not entity or entity==0 then return nil,"Could not create card wallet." end
            return entity
        end,
    })
end

function NHCardWallets.carried(s,player,entity)
    if not entity or entity==0 or not EntityGetIsAlive(entity) or EntityGetRootEntity(entity)~=player
        or not EntityHasTag(entity,"noita_hideout_card_wallet") then return end
    local release,token=NHTransfers.issuedRecord(s,entity)
    if release and release.row.item.kind=="card_wallet" then return release.row,token end
end

local function locate(s,player,ref)
    if type(ref)~="table" or not ref.id then return end
    if ref.entity then
        local row,token=NHCardWallets.carried(s,player,ref.entity)
        if row and row.id==ref.id then return row,"issued",token end
    elseif (ref.container=="warehouse" or ref.container=="safe") and ref.slot then
        local index=NHStore.slotIndex(s,ref.container,ref.slot,"card_wallet")
        local row=s[ref.container][index]
        if row and row.id==ref.id and row.item.kind=="card_wallet" then return row,ref.container,index end
    end
end

function NHCardWallets.get(s,player,ref)
    local row=locate(s,player,ref)
    return row
end

local function replace(s,row,location,key,cells)
    local updated=copy(row)
    updated.item=copy(row.item)
    updated.item.cells=cells
    if location=="issued" then
        local release=copy(s.transit.issued[key])
        release.row=updated
        s.transit.issued[key]=release
    else
        s[location][key]=updated
    end
end

local function addToCell(wallet,cells,slot,item)
    if not validCell(wallet,slot) then return false end
    local current=cells[slot]
    if current and not NHCompanions.canStack(current,item) then return false end
    cells[slot]=NHCompanions.withCount(item,(current and (current.count or 1) or 0)+1)
    return true
end

-- Only modifies a detached journal draft. Both endpoints share one commit.
-- Native endpoints use take/put with the same cell operations and receipt journal.
function NHCardWallets.take(s,player,ref,source)
    local row,location,key=locate(s,player,ref)
    local slot=source.cell
    if not row or not validCell(row.item,slot) then return end
    local item=row.item.cells[slot]
    if not item or (source.species and source.species~=item.species)
        or (source.remaining and source.remaining~=item.remaining)
        or (source.count and source.count~=(item.count or 1)) then return end
    local cells=copy(row.item.cells)
    local count=item.count or 1
    cells[slot]=count>1 and NHCompanions.withCount(item,count-1) or nil
    replace(s,row,location,key,cells)
    return NHCompanions.withCount(item,1)
end

function NHCardWallets.put(s,player,ref,slot,card)
    local row,location,key=locate(s,player,ref)
    if not row or not card or card.kind~="summon_card" or not NHCompanions.validCard(card) or (card.count or 1)~=1 then return false end
    local cells=copy(row.item.cells)
    if not addToCell(row.item,cells,slot,card) then return false end
    replace(s,row,location,key,cells)
    return true
end

local function originalWallet(s,id)
    for _,container in ipairs({"safe","warehouse"}) do
        for i,row in ipairs(s[container]) do
            if row.id==id and row.item.kind=="card_wallet" then return row,container,i end
        end
    end
    for token,release in pairs(s.transit.issued) do
        local row=release.row
        if row.id==id and row.item.kind=="card_wallet" then return row,"issued",token end
    end
end

function NHCardWallets.recover(s,release)
    local item=release.row.item
    local row,location,key=originalWallet(s,release.walletId)
    if row then
        local cells=copy(row.item.cells)
        if addToCell(row.item,cells,release.cell,item) then
            replace(s,row,location,key,cells)
            return true
        end
        for slot=1,NHEquipment.get("card_wallet",row.item.tier).capacity do
            if addToCell(row.item,cells,slot,item) then
                replace(s,row,location,key,cells)
                return true
            end
        end
    end
    local slot,index=NHCompanions.cardSlot(s,"warehouse",nil,item)
    if not slot then return false end
    return NHCompanions.put(s,"warehouse",slot,index,item,release.row.id)
end

function NHCardWallets.move(s,player,ref,source,target)
    local row=NHCardWallets.get(s,player,ref)
    if s.runSerial<=s.closedThrough or not row
        or type(source)~="table" or type(target)~="table" then return nil,"Card wallet changed." end
    if source.entity and validCell(row.item,target.cell) then
        return NHTransfers.depositWalletCard(s,player,ref,source.entity,target.cell)
    elseif validCell(row.item,source.cell) and type(target.deliver)=="function" then
        return NHTransfers.withdrawWalletCard(s,player,ref,source,target.deliver)
    end
    return NHTransfers.moveWalletCard(s,player,ref,source,target)
end
