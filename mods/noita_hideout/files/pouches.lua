-- Protected and carried pouches each retain their own stable ID and four cells.
NHPouches = {}

local function initial_cells(count)
    return count>0 and {{remaining=NHStore.doseDurability,count=count}} or {}
end

function NHPouches.create(s,container,slot,count)
    local id=s.nextItemId
    s.nextItemId=id+1
    count=count or 0
    s.pouches[id]={id=id,location=container,slot=slot,doses=count,cells=initial_cells(count)}
    return id
end

function NHPouches.at(s,container,slot)
    for _,p in pairs(s.pouches) do
        if p.location==container and p.slot==slot then return p end
    end
end

function NHPouches.adopt(s)
    if s.pouches then return end
    local old=assert(s.pouch,"Missing injector pouches")
    local id=s.nextItemId
    s.pouches,s.starterPouchId,s.nextItemId={},id,id+1
    if old.location~="lost" then
        old.id=id
        old.cells=old.cells or initial_cells(old.doses)
        s.pouches[id]=old
    end
    for _,origin in pairs(s.issuedDoses or {}) do
        if not origin.safeSlot then origin.pouchId=id end
    end
    s.pouch=nil
end

function NHPouches.validate(s,whole,validDose)
    assert(type(s.pouches)=="table","Invalid injector pouches")
    local occupied={safe={},warehouse={}}
    local tokens={}
    for id,p in pairs(s.pouches) do
        assert(whole(id) and id>0 and id<s.nextItemId and type(p)=="table" and p.id==id,"Invalid pouch identity")
        assert(type(p.cells)=="table" and whole(p.doses),"Invalid pouch contents")
        local total=0
        for slot,cell in pairs(p.cells) do
            assert(whole(slot) and slot>=1 and slot<=NHStore.pouchCapacity
                and type(cell)=="table" and validDose(cell.remaining,cell.count,cell.subtype),"Invalid pouch cell")
            total=total+cell.count
        end
        assert(total==p.doses,"Invalid injector count")
        if p.location=="bag" then
            if p.token then
                assert(type(p.token)=="string" and not tokens[p.token],"Invalid pouch token")
                tokens[p.token]=true
            end
        else
            local used=assert(occupied[p.location],"Invalid pouch location")
            if p.location=="warehouse" or s.sharedSlots then
                local capacity=p.location=="safe" and NHStore.safeCapacity(s) or NHStore.warehouseCapacity(s,"equipment")
                assert(whole(p.slot) and p.slot>=1 and p.slot<=capacity and not used[p.slot],"Invalid pouch slot")
                used[p.slot]=true
            end
        end
    end
end

function NHPouches.endRun(s)
    for id,p in pairs(s.pouches) do
        if p.location=="bag" then s.pouches[id]=nil end
    end
end

function NHPouches.restock(s)
    local previous=s.pouches[s.starterPouchId]
    local slot=previous and previous.location=="safe" and previous.slot or NHStore.freeSafeSlot(s)
    if not slot then return false,"Secure valuables slot is full." end
    if previous then s.pouches[previous.id]=nil end
    s.starterPouchId=NHPouches.create(s,"safe",slot,2)
    return true,"Two test doses placed in secure case."
end
