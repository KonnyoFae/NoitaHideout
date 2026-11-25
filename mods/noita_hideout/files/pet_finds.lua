local M={}
local dir="mods/noita_hideout/files/"
local reds=dofile(dir.."red_collectibles.lua")
local bags={travel_satchel=true,travel_pack=true,loot_case=true}
local pools,tools={},{}
for level,additions in ipairs({
    {"magic_tube","flare_gun","turret_pack","sedative_launcher"},
    {"fire_tube","frost_tube","rocket_turret_pack"},
    {"shock_tube","derringer","shield_turret_pack"},
}) do
    local pool={}
    for _,id in ipairs(pools[level-1] or {}) do pool[#pool+1]=id end
    for _,id in ipairs(additions) do tools[id]=true; pool[#pool+1]=id end
    pools[level]=pool
end
function M.toolPool(level) return pools[level] end
function M.hasRed() return #reds>0 end
function M.redKey(roll)
    if #reds>0 then return "red:"..reds[roll(#reds)].id end
end
local function collectible(key)
    for _,entry in ipairs(reds) do
        if key=="red:"..entry.id then return entry.item end
    end
end
function M.known(key) return bags[key] or tools[key] or collectible(key)~=nil end

local function unit(key)
    if bags[key] then return NHLootBags.item(key,1),2147483647 end
    if tools[key] then
        local gun=NHGuns.types[key]
        local item={kind=key,name="$nh_hideout_"..key,icon=dir.."items/"..key..".png",count=1}
        if gun then item.remaining=gun.capacity end
        return item,gun and 2147483647 or NHTurrets.stackLimit
    end
    return collectible(key),1
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for k,v in pairs(value) do result[k]=copy(v) end
    return result
end

-- Only full, single tools are awarded. A six-shot tube occupies six units
-- of ItemComponent capacity, while a decoy occupies one place in its stack.
-- A pending workshop order retains enough space in its reserved stack.
local function stackSpace(state,row,index,item,limit,units)
    if limit==1 or row.item.kind~=item.kind then return 0 end
    local gun=NHGuns.types[item.kind]
    if gun and not NHGuns.canCombine(gun,item.remaining,row.item.remaining) then return 0 end
    local space=limit-NHStore.stackUnits(row.item)
    local order=state.order and state.order.output
    if order and order.item and order.slot==(row.slot or index)
        and NHStore.category(order.item.kind)==NHStore.category(item.kind) then
        if order.item.kind~=item.kind then return 0 end
        space=space-NHStore.stackUnits(order.item)
    end
    return math.floor(space/units)
end

function M.canPay(state,key)
    local item,limit=unit(key)
    if not item then return false end
    if limit>1 then
        local units=NHStore.stackUnits(item)
        for i,row in ipairs(state.warehouse) do
            if stackSpace(state,row,i,item,limit,units)>0 then return true end
        end
    end
    return state.nextItemId<NHStore.maxResourceAmount and NHStore.freeSlot(state,"warehouse",nil,item.kind)~=nil
end

function M.payment(state,key,requested)
    local item,limit=unit(key)
    if not item or requested<=0 then return 0 end
    local units=limit==1 and 1 or NHStore.stackUnits(item)
    local left=math.min(requested,NHFarm.batchLimit)
    local budget=left
    local draft
    local function writable()
        if not draft then
            draft=setmetatable({warehouse={},nextItemId=state.nextItemId},{__index=state})
            for i,row in ipairs(state.warehouse) do draft.warehouse[i]=row end
        end
        return draft
    end
    if limit>1 then
        for i,row in ipairs(state.warehouse) do
            local take=math.min(left,stackSpace(state,row,i,item,limit,units))
            if take>0 then
                local updated=copy(row)
                local incoming=copy(item)
                incoming.count=take
                NHStore.mergeStack(updated.item,incoming)
                writable().warehouse[i]=updated
                left=left-take
                if left==0 then break end
            end
        end
    end
    while left>0 and (draft or state).nextItemId<NHStore.maxResourceAmount do
        local slot=NHStore.freeSlot(draft or state,"warehouse",nil,item.kind)
        if not slot then break end
        local take=math.min(left,math.floor(limit/units))
        local reward=copy(item)
        if limit>1 then reward.count=take end
        local dest=writable()
        dest.warehouse[#dest.warehouse+1]={id=dest.nextItemId,slot=slot,item=reward}
        dest.nextItemId=dest.nextItemId+1
        left=left-take
    end
    return budget-left,draft
end
return M
