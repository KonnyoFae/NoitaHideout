local M={}

-- Full-item retail prices in gold. Healing is valued at the same rate as the
-- 120 HP in a 50-gold medkit. Percentage healing uses a fixed 100 HP baseline.
local hpPrice=50/120
local function retail(value)
    return 2*math.max(1,math.floor(value/2+0.5))
end

local function foodPrice(food)
    local perBite=2+(food.healPercent or 0)*hpPrice
    for _,effect in ipairs(food.effects) do
        if effect.key=="grain" or effect.key=="sugar" then
            local interval=effect.key=="grain" and 4 or 1
            perBite=perBite+effect.seconds/interval*effect.strength*hpPrice
        else
            perBite=perBite+effect.seconds*effect.strength/12
        end
    end
    return retail(food.uses*perBite),food.uses
end

local function injectorPrice(d)
    local heal=d.healPercent or 0
    local perUse=d.cost*2/3+d.seconds/5+heal*hpPrice
    return retail(NHInjectors.uses*perUse),NHInjectors.uses
end

function M.price(item)
    local kind=item.kind
    local kit=NHMedkits.types[kind] or NHSurgeryKits.types[kind]
    if kit then
        return retail(kit.uses*(kit.healPercent*hpPrice+(NHSurgeryKits.types[kind] and 5 or 0))),kit.uses
    end
    if kind=="dose" then
        local d=NHInjectors.get(item.subtype)
        if d then return injectorPrice(d) end
    end
    local food=NHFoods.byId[kind]
    if food then return foodPrice(food) end
    local thrown=NHThrowables.types[kind]
    if thrown then return retail(thrown.workSeconds+(thrown.radius or 0)/5),1 end
    local gun=NHGuns.types[kind]
    if gun then
        local price=gun.gold or (gun.isTube and 48) or (80+math.min(120,gun.capacity))
        return retail(price),gun.capacity
    end
    local turret=NHTurrets.types[kind]
    if turret then return turret.essence and 70 or 60,1 end
end

function M.quote(item)
    if NHStore.category(item.kind)~="supplies" then return end
    local count=item.count or 1
    local storm=NHStormProducts.types[item.kind]
    if storm then
        return {count=count,resource=storm.resource,units=storm.units}
    end
    local price,capacity=M.price(item)
    if not price then return end
    local remaining=item.remaining or capacity
    local full=price/2
    local one=math.max(1,math.floor(full*remaining/capacity))
    return {count=count,remaining=remaining,capacity=capacity,oneGold=one,allGold=one+(count-1)*full}
end

function M.apply(state,request)
    local index=NHStore.slotIndex(state,"warehouse",request.slot,request.kind)
    local row=index and state.warehouse[index]
    if not row or row.id~=request.id or row.item.kind~=request.kind then return false,"Inventory slot changed." end
    local quote=M.quote(row.item)
    if not quote or quote.count~=request.count or quote.remaining~=request.remaining
        or (request.quantity~=1 and request.quantity~=quote.count) then return false,"Inventory slot changed." end
    local quantity=request.quantity
    if request.mode=="convert" and quote.resource then
        local key=quote.resource
        local stock=state.resources[key] or 0
        local reserved=state.order and state.order.output.resources
        local amount=quote.units*quantity
        if amount>NHStore.maxResourceAmount-stock-(reserved and reserved[key] or 0) then return false,"Resource storage is full." end
        state.resources[key]=stock+amount
    elseif request.mode=="sell" and quote.oneGold then
        local ok,reason=NHStore.creditGold(state,quantity==1 and quote.oneGold or quote.allGold)
        if not ok then return false,reason end
    else return false,"Invalid supply trade." end
    if quantity==quote.count then table.remove(state.warehouse,index)
    else
        row.item.count=quote.count-quantity
        if row.item.remaining then row.item.remaining=quote.capacity end
    end
    return true
end

return M
