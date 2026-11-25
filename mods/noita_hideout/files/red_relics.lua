local relics={
    types={},
    resourceKeys={"supply_logistics","strike_logistics","reinforcement_logistics","intel_logistics"},
    resourceAmount=2400,
    cardCount=4,
}
for _,def in ipairs(dofile("mods/noita_hideout/files/red_collectibles.lua")) do relics.types[def.id]=def end

function relics.valid(item)
    local def=relics.types[item.kind]
    if def and def.katana then return (NHKatanas or dofile("mods/noita_hideout/files/katanas.lua")).valid(item) end
    local n=item.remaining
    return def~=nil and (item.count==nil or item.count==1) and type(n)=="number" and n>=0 and n<=def.item.remaining and n==math.floor(n)
end

local function register(def)
    NHTransfers.registerItem(def.id,function(id) return EntityHasTag(id,"noita_hideout_"..def.id) end,{
        warehouseCategory="collection",
        capture=function(id)
            local component=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
            if not component or EntityGetFirstComponentIncludingDisabled(id,"ItemCostComponent") then return nil,"Item unavailable." end
            local item={kind=def.id,name=def.item.name,icon=def.item.icon,remaining=ComponentGetValue2(component,"uses_remaining")}
            if relics.valid(item) then return item end
            return nil,"Item unavailable."
        end,
        restore=function(item,x,y)
            if item.kind~=def.id or not relics.valid(item) then return nil,"Item unavailable." end
            local entity=EntityLoad(def.file,x,y)
            if not entity or entity==0 then return nil,"Item unavailable." end
            local component=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
            if not component then EntityKill(entity); return nil,"Item unavailable." end
            ComponentSetValue2(component,"uses_remaining",item.remaining)
            return entity
        end,
    })
end

function relics.register()
    for _,def in pairs(relics.types) do if not def.katana then register(def) end end
end

local activations={
    salvage_bell=function(_,player,pay) return NHSalvageBell.activate(player,pay) end,
    rewind_watch=function(state,player,pay) return NHRewind.start(state,player,pay) end,
    stasis_hourglass=function(_,player,pay) return dofile_once("mods/noita_hideout/files/hourglass_field.lua").activate(player,pay) end,
    dustless_duster=function(_,player,pay) return dofile_once("mods/noita_hideout/files/duster_field.lua").activate(player,pay) end,
    mana_reactor=function(_,player,pay) return dofile_once("mods/noita_hideout/files/mana_reactor.lua").activate(player,pay) end,
}

-- Each effect calls pay once, after its fallible preparation and before its
-- first visible effect. Stored sources use the controller's exact-slot commit.
local function activate(state,player,item,pay)
    if not item or not relics.valid(item) or not pay then return false,"Item unavailable." end
    if not activations[item.kind] then return false,"Equip this weapon to use it." end
    if item.remaining==0 then return false,"Collectible exhausted." end
    local ok,reason=activations[item.kind](state,player,pay)
    if not ok then return false,reason or "Item unavailable." end
    return true,item.kind
end

function relics.activateStored(state,player,item,pay)
    -- A stored relic has no physical item to pass through NHTransfers.available.
    -- Use the same session/owner handshake as a carried relic.
    if NHEWItems and NHEWItems.enabled() and not NHEWItems.ready() then
        return false,"Waiting for item ownership. Try again."
    end
    return activate(state,player,item,pay)
end

function relics.activate(state,player,entity,slot)
    if not player or not entity or entity==0 or EntityGetRootEntity(entity)~=player
        or (not slot and NHNative.held(player)~=entity)
        or (NHEWItems and NHEWItems.lockInfo(entity)) then return false,"Item unavailable." end
    local ok,_,reason=NHTransfers.available(state,player,entity)
    if not ok then return false,reason end
    local kind=NHTransfers.item_kind(entity)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    local n=item and ComponentGetValue2(item,"uses_remaining")
    if EntityGetFirstComponentIncludingDisabled(entity,"ItemCostComponent") then return false,"Item unavailable." end
    if slot then
        if slot.entity~=entity or slot.kind~=kind or slot.remaining~=n or slot.parent~=EntityGetParent(entity) then
            return false,"Inventory slot changed."
        end
    end
    ok,reason=activate(state,player,{kind=kind,remaining=n},function()
        if ComponentGetValue2(item,"uses_remaining")~=n then return false end
        ComponentSetValue2(item,"uses_remaining",n-1)
        return true
    end)
    if ok and NHNative.held(player)==entity then GamePlayAnimation(entity,"activate",1,"default",0) end
    return ok,reason
end

function relics.salvage(state,request)
    local def=relics.types[request.kind]
    local index=def and NHStore.slotIndex(state,"warehouse",request.slot,request.kind)
    local row=index and state.warehouse[index]
    if not row or row.id~=request.id or row.item.kind~=request.kind or not relics.valid(row.item) then
        return false,"Inventory slot changed."
    end
    local reserved=state.order and state.order.output.resources
    for _,key in ipairs(relics.resourceKeys) do
        if relics.resourceAmount>NHStore.maxResourceAmount-(state.resources[key] or 0)-(reserved and reserved[key] or 0) then
            return false,"Resource storage is full."
        end
    end
    -- Place the reward cards in a draft that includes the slot released by the collectible.
    local draft=setmetatable({warehouse={},nextItemId=state.nextItemId},{__index=state})
    for i,entry in ipairs(state.warehouse) do
        if i~=index then
            if not entry.slot then
                local saved={slot=i}
                for key,value in pairs(entry) do saved[key]=value end
                entry=saved
            end
            draft.warehouse[#draft.warehouse+1]=entry
        end
    end
    for _,species in ipairs({def.tarot,def.companion}) do
        local card=NHCompanions.withCount({species=species,remaining=NHCompanions.cardCapacity(species)},1)
        for i=1,relics.cardCount do
            local slot,stack=NHCompanions.cardSlot(draft,"warehouse",nil,card)
            if not NHCompanions.put(draft,"warehouse",slot,stack,card) then return false,"Collection needs room for the reward cards." end
        end
    end
    state.warehouse,state.nextItemId=draft.warehouse,draft.nextItemId
    for _,key in ipairs(relics.resourceKeys) do
        state.resources[key]=(state.resources[key] or 0)+relics.resourceAmount
    end
    return true
end
return relics
