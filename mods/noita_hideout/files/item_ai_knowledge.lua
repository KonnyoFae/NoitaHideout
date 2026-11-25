-- Noita stores the AI's assessment on the item, including whether it is safe
-- to use. These are data fields, separate from the item's Lua callbacks.
local ai={kind="ItemAIKnowledgeComponent"}
local defaults={
    is_ranged_weapon=false,is_throwable_weapon=false,is_melee_weapon=false,
    is_self_healing=false,is_other_healing=false,is_self_buffing=false,is_other_buffing=false,
    is_weapon=false,is_known=false,is_safe=true,is_consumed=false,never_use=false,ranged_min_distance=0,
}

local function validField(key,value)
    if key=="tags" then return type(value)=="string" end
    if key=="enabled" then return type(value)=="boolean" end
    if key=="ranged_min_distance" then return type(value)=="number" and math.abs(value)<math.huge end
    return defaults[key]~=nil and type(value)=="boolean"
end

function ai.valid(data)
    if type(data)~="table" then return false end
    for key,value in pairs(data) do if not validField(key,value) then return false end end
    return true
end

local function sortedTags(csv)
    local tags={}
    for tag in (csv or ""):gmatch("[^,]+") do tags[#tags+1]=tag end
    table.sort(tags)
    return table.concat(tags,",")
end

function ai.capture(c,previous)
    assert(not previous,"Duplicate ItemAIKnowledgeComponent")
    -- Omit default values to keep the profile small. An empty record still
    -- represents a real component and is distinct from a missing component.
    local data={}
    for key in pairs(assert(ComponentGetMembers(c),"Cannot inspect ItemAIKnowledgeComponent")) do
        assert(defaults[key]~=nil,"Unsupported item AI field: "..key)
    end
    for key,default in pairs(defaults) do
        local value=ComponentGetValue2(c,key)
        assert(validField(key,value),"Invalid item AI field: "..key)
        if value~=default then data[key]=value end
    end
    if not ComponentGetIsEnabled(c) then data.enabled=false end
    local tags=sortedTags(ComponentGetTags(c))
    if tags~="" then data.tags=tags end
    return data
end

local nativeMarks={
    potion={is_consumed=true},
    wand={is_ranged_weapon=true,is_weapon=true},
}

local function inPlayerInventory(entity)
    local bag=EntityGetParent(entity)
    if not bag or bag==0 then return false end
    local owner=EntityGetParent(bag)
    if not owner or owner==0 or not EntityHasTag(owner,"player_unit") then return false end
    local name=EntityGetName(bag)
    return name=="inventory_quick" or name=="inventory_full"
end

-- Only project a captured record. NPCs may still reference the live component.
function ai.forStorage(data,kind,entity,templateOrVariant)
    local mark=nativeMarks[kind]
    if type(data)~="table" or not mark then return data end
    if kind=="potion" and templateOrVariant~=nil then return data end
    if kind=="wand" and (not templateOrVariant or templateOrVariant=="data/entities/items/wand_varpuluuta.xml") then return data end
    for key,value in pairs(mark) do
        if data[key]~=value then return data end
    end
    for key,value in pairs(data) do
        if key~="enabled" and mark[key]~=value then return data end
    end
    -- Noita can disable the untagged mark when an item enters the inventory.
    -- A matching but disabled component on the ground can be intentional.
    if data.enabled~=nil and (data.enabled~=false or not inPlayerInventory(entity)) then return data end
    return nil
end

function ai.restore(entity,data)
    if data==nil then return end
    assert(ai.valid(data),"Invalid stored item AI knowledge")
    local existing=EntityGetComponentIncludingDisabled(entity,ai.kind) or {}
    assert(#existing<=1,"Duplicate ItemAIKnowledgeComponent")
    local fields={_tags=data.tags or ""}
    for key,default in pairs(defaults) do
        fields[key]=data[key]
        if fields[key]==nil then fields[key]=default end
    end
    -- A template can already supply the component. Keep its identity and
    -- update the fresh item's fields without detaching it from the engine.
    local c=existing[1]
    if c then
        for key in pairs(defaults) do ComponentSetValue2(c,key,fields[key]) end
        local tags=ComponentGetTags(c) or ""
        if sortedTags(tags)~=sortedTags(data.tags) then
            for tag in tags:gmatch("[^,]+") do ComponentRemoveTag(c,tag) end
            for tag in fields._tags:gmatch("[^,]+") do ComponentAddTag(c,tag) end
        end
    else
        c=EntityAddComponent2(entity,ai.kind,fields)
    end
    assert(c and c~=0,"Could not restore ItemAIKnowledgeComponent")
    EntitySetComponentIsEnabled(entity,c,data.enabled~=false)
    for key in pairs(defaults) do
        assert(ComponentGetValue2(c,key)==fields[key],"Item AI readback mismatch: "..key)
    end
    assert(ComponentGetIsEnabled(c)==(data.enabled~=false),"Item AI readback mismatch: enabled")
    assert(sortedTags(ComponentGetTags(c))==sortedTags(data.tags),"Item AI readback mismatch: tags")
end
return ai
