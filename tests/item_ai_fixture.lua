-- Nondefault item AI traits from Noita's component documentation.
local fixture={}
local kind="ItemAIKnowledgeComponent"
local fields={
    is_ranged_weapon=true,is_throwable_weapon=true,is_melee_weapon=true,
    is_self_healing=true,is_other_healing=true,is_self_buffing=true,is_other_buffing=true,
    is_weapon=true,is_known=true,is_safe=false,is_consumed=true,never_use=true,
    ranged_min_distance=17.25,
}
-- Both item mocks keep a component's tag list in its _tags string.
function ComponentRemoveTag(c,tag)
    local keep={}
    for existing in (ComponentGetTags(c) or ""):gmatch("[^,]+") do
        if existing~=tag then keep[#keep+1]=existing end
    end
    ComponentSetValue2(c,"_tags",table.concat(keep,","))
end
function ComponentAddTag(c,tag)
    local tags=ComponentGetTags(c) or ""
    for existing in tags:gmatch("[^,]+") do if existing==tag then return end end
    ComponentSetValue2(c,"_tags",tags=="" and tag or tags..","..tag)
end
function fixture.add(entity,enabled)
    local values={_tags="test_ai_profile"}
    for key,value in pairs(fields) do values[key]=value end
    local c=assert(EntityAddComponent2(entity,kind,values))
    EntitySetComponentIsEnabled(entity,c,enabled)
    return c
end
local function stockValue(key,profile)
    if key=="ranged_min_distance" then return 0 end
    return key=="is_safe" or (profile=="potion" and key=="is_consumed")
        or (profile=="wand" and (key=="is_weapon" or key=="is_ranged_weapon"))
end
function fixture.addStock(entity,profile,enabled)
    local values={_tags=""}
    for key in pairs(fields) do values[key]=stockValue(key,profile) end
    local c=assert(EntityAddComponent2(entity,kind,values))
    EntitySetComponentIsEnabled(entity,c,enabled)
    return c
end
function fixture.checkStock(entity,c,profile,enabled)
    local list=EntityGetComponentIncludingDisabled(entity,kind) or {}
    assert(#list==1 and list[1]==c and ComponentGetIsEnabled(c)==enabled and (ComponentGetTags(c) or "")=="")
    for key in pairs(fields) do assert(ComponentGetValue2(c,key)==stockValue(key,profile),key) end
end
function fixture.check(entity,enabled)
    local list=EntityGetComponentIncludingDisabled(entity,kind) or {}
    assert(#list==1,"expected exactly one item AI component")
    local c=list[1]
    assert(ComponentGetIsEnabled(c)==enabled and ComponentGetTags(c)=="test_ai_profile")
    for key,value in pairs(fields) do assert(ComponentGetValue2(c,key)==value,key) end
end
return fixture
