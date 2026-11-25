local P={}

local function units(id,kind)
    local item=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
    if NHStormProducts.types[kind] then return NHStormProducts.worldCount(item),item end
    return item and ComponentGetValue2(item,"uses_remaining"),item
end

-- Search the actual quick inventory. Different loot tiers can occupy adjacent
-- slots and the first candidate of the same family need not be compatible.
function P.stackTarget(state,player,kind,amount,source)
    local gun=NHGuns.types[kind]
    local medical=NHMedkits.capacity(kind)
    if not (medical or gun or NHLootBags.types[kind] or NHTurrets.types[kind]) or not NHStore.validBandageCount(amount) then return end
    for _,id in ipairs(NHTransfers.carried(player)) do
        if id~=source and EntityHasTag(id,"noita_hideout_"..kind) and NHTransfers.available(state,player,id) then
            local count,item=units(id)
            if NHStore.validBandageCount(count) and count<=(NHTurrets.types[kind] and NHTurrets.stackLimit or 2147483647)-amount and
                (not medical or NHMedkits.canCombine(kind,count,amount)) and
                (not gun or NHGuns.canCombine(gun,(count-1)%gun.capacity+1,(amount-1)%gun.capacity+1)) then
                return item,count+amount
            end
        end
    end
end

local function finishMerge(player,id,left)
    local source=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
    ComponentSetValue2(source,"uses_remaining",left)
    if left==0 then
        if EntityGetRootEntity(id)==player then GameKillInventoryItem(player,id) else EntityKill(id) end
    end
    local inv=EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    if inv then ComponentSetValue2(inv,"mForceRefresh",true) end
end

-- Withdrawals apply their plan only after the profile write succeeds.
local function pickupPlan(state,player,kind,amount,source)
    if not NHStormProducts.types[kind] then
        local target,total=P.stackTarget(state,player,kind,amount,source)
        if target then return function(id)
            ComponentSetValue2(target,"uses_remaining",total)
            finishMerge(player,id,0)
        end,0 end
        return
    end
    if not amount or not NHStormProducts.count(amount) then return end
    local moves,left={},amount
    for _,id in ipairs(NHTransfers.carried(player)) do
        if id~=source and EntityHasTag(id,kind) and not EntityGetFirstComponentIncludingDisabled(id,"ItemCostComponent")
            and NHTransfers.available(state,player,id) then
            local n,item=units(id,kind)
            if n and n<NHStormProducts.stackLimit then
                local take=math.min(left,NHStormProducts.stackLimit-n)
                moves[#moves+1]={item=item,count=n+take}
                left=left-take
                if left==0 then break end
            end
        end
    end
    if left==amount then return end
    return function(id)
        for _,move in ipairs(moves) do ComponentSetValue2(move.item,"uses_remaining",move.count) end
        finishMerge(player,id,left)
    end,left
end

function P.stackDelivery(state,player,item,one)
    if NHEWItems and NHEWItems.enabled() then return end
    local kind=item.kind
    local amount=one and (item.remaining or NHMedkits.capacity(kind) or 1) or NHStore.stackUnits(item)
    local _,left=pickupPlan(state,player,kind,amount)
    if left~=0 then return end
    return function(id)
        local apply,remainder=pickupPlan(state,player,kind,units(id,kind),id)
        if remainder==0 then return true,function() apply(id) end end
    end
end

function P.finishPickups(state,player)
    if not EntityHasTag(player,"nh_has_merge_pickup") then return end
    EntityRemoveTag(player,"nh_has_merge_pickup")
    for _,id in ipairs(NHTransfers.carried(player)) do
        if EntityGetIsAlive(id) and EntityHasTag(id,"nh_merge_pickup") then
            EntityRemoveTag(id,"nh_merge_pickup")
            if not (NHEWItems and NHEWItems.enabled()) and not EntityGetFirstComponentIncludingDisabled(id,"ItemCostComponent") and NHTransfers.available(state,player,id) then
                local kind=NHTransfers.item_kind(id)
                local apply=pickupPlan(state,player,kind,units(id,kind),id)
                if apply then apply(id) end
            end
        end
    end
end

local function nearestItem(player)
    local x,y=EntityGetTransform(player)
    local best,nearest
    for _,id in ipairs(EntityGetInRadius(x,y,32) or {}) do
        local item=EntityGetRootEntity(id)==id and EntityGetFirstComponent(id,"ItemComponent")
        if item and ComponentGetValue2(item,"is_pickable") and not ComponentGetValue2(item,"auto_pickup")
            and ComponentGetValue2(item,"next_frame_pickable")<=GameGetFrameNum() then
            local ix,iy=EntityGetTransform(id)
            local d=(ix-x)^2+(iy-y)^2
            local radius=ComponentGetValue2(item,"item_pickup_radius")
            if d<=radius*radius and (not best or d<best or (d==best and id<nearest)) then
                nearest,best=id,d
            end
        end
    end
    return nearest
end

-- Return whether this press was claimed. Ordinary pickups with a free native
-- slot (and shop purchases) continue through the engine's own pickup path.
function P.interact(state,player,toSafe,nativeSlots)
    if NHEWItems and NHEWItems.enabled() then
        if toSafe and nearestItem(player) then return true,"Pick up this item before storing it." end
        return
    end
    local id=nearestItem(player)
    if not id or EntityGetFirstComponentIncludingDisabled(id,"ItemCostComponent") then return end
    local kind=NHNative.kind(id) or NHTransfers.item_kind(id)
    if not kind then return end
    if kind=="battle_staff" then NHFirearms.repairStaff(id,player) end
    local partial=false
    if not toSafe then
        local amount=units(id,kind)
        local apply,left=pickupPlan(state,player,kind,amount,id)
        if apply then
            if not NHTransfers.available(state,player,id) then return true end
            apply(id)
            if left==0 then return true end
            partial=true
        end
        local safeStack=NHLootBags.types[kind] and NHStore.validBandageCount(amount)
            and NHStore.stackSlot(state,"safe",{kind=kind,count=amount})
        if not safeStack then
            local lane=NHFirearms.lane(kind)
            for _,slot in ipairs(nativeSlots(player)) do
                if slot.lane==lane and not slot.entity then return end
            end
        end
    end
    local ok,err
    if kind=="dose" or kind=="pouch" then
        local record={kind=kind}
        if kind=="dose" then record.remaining,record.subtype=NHDoses.remaining(state,id) end
        local slot=NHTransfers.storageSlot(state,"safe",record)
        if not slot then err="No free destination slot."
        elseif kind=="pouch" then ok,err=NHDoses.storePouch(state,player,id,slot,"safe",true)
        else ok,err=NHDoses.deposit(state,player,id,slot,nil,"safe",nil,true) end
    else ok,err=NHTransfers.pickupToSafe(state,player,id) end
    if not ok and not toSafe and err=="No free destination slot." then return partial end
    return true,err,ok
end

return P
