local migration=dofile("mods/noita_hideout/files/legacy_loot_bags.lua")
local migrate=migration(true,false)
local entities={}
local physics={"PhysicsBodyComponent","PhysicsImageShapeComponent","PhysicsKeepInWorldComponent",
    "PhysicsThrowableComponent","VelocityComponent"}
local function bag(kind)
    local id=#entities+1
    local icon="mods/noita_hideout/files/items/"..kind..".png"
    local e={id=id,root=id,x=17+id,y=-25-id,group="nh_loot_bag",kindTag="noita_hideout_"..kind,physical=true,writes=0,comps={}}
    entities[id]=e
    local function part(t,fields)
        fields.owner=e
        e.comps[t]={fields}
        return fields
    end
    e.item=part("ItemComponent",{item_name="$nh_hideout_"..kind,is_pickable=true,uses_remaining=id+2})
    e.sprite=part("SpriteComponent",{tags={enabled_in_hand=true},image_file=icon,enabled=false})
    e.custom=part("VariableStorageComponent",{name="other_mod_data",value_int=41})
    for _,t in ipairs(physics) do part(t,{enabled=true}) end
    e.body=e.comps.PhysicsBodyComponent[1]
    e.body.uid,e.body.kills_entity,e.body.is_enabled=1,true,true
    local shape=e.comps.PhysicsImageShapeComponent[1]
    shape.body_id,shape.image_file=1,icon
    return e
end

function EntityGetWithTag(tag)
    local result={}
    for i,e in ipairs(entities) do if e.group==tag then result[#result+1]=i end end
    return result
end
function EntityHasTag(id,tag)
    local e=entities[id]
    return (tag=="item_physics" and e.physical) or tag==e.kindTag
end
function EntityGetRootEntity(id) return entities[id].root end
function EntityGetComponentIncludingDisabled(id,kind) return entities[id].comps[kind] end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    for _,c in ipairs(entities[id].comps[kind] or {}) do
        if not tag or (c.tags and c.tags[tag]) then return c end
    end
end
function EntityGetFirstComponent(id,kind)
    local c=EntityGetFirstComponentIncludingDisabled(id,kind)
    if c and c.enabled~=false then return c end
end
function ComponentGetValue2(c,k) return c[k] end
local function write(c,k,v)
    c.owner.writes=c.owner.writes+1
    c[k]=v
end
ComponentSetValue2=write
function ComponentAddTag(c,tag) c.tags[tag]=true; c.owner.writes=c.owner.writes+1 end
function EntitySetComponentIsEnabled(id,c,enabled)
    assert(c.owner==entities[id])
    write(c,"enabled",enabled)
end
function EntityRemoveComponent(id,c)
    local e=entities[id]
    assert(c.owner==e)
    for kind,list in pairs(e.comps) do
        if list[1]==c then
            if kind=="PhysicsBodyComponent" then
                assert(c.kills_entity==false and c.on_death_leave_physics_body==false)
            end
            e.comps[kind]=nil
            e.writes=e.writes+1
            return
        end
    end
    error("attempted to remove an unknown component")
end
function EntityRemoveTag(id,tag)
    assert(tag=="item_physics" and entities[id].physical)
    entities[id].physical=false
    entities[id].writes=entities[id].writes+1
end

local held=bag("travel_satchel")
held.root=999
local customShape=bag("travel_pack")
customShape.comps.PhysicsImageShapeComponent[1].image_file="mods/other/custom.png"
local customBody=bag("loot_case")
customBody.body.uid=7
local extraBody=bag("loot_case")
extraBody.comps.PhysicsBody2Component={{}}
local duplicate=bag("travel_pack")
table.insert(duplicate.comps.VelocityComponent,{})
local joint=bag("loot_case")
joint.comps.PhysicsJointComponent={{}}
local mimic=bag("travel_pack")
mimic.kindTag="other_mod_pack"
local unpickable=bag("travel_satchel")
unpickable.item.is_pickable=false
local crate=bag("supply_pack")
local current=bag("loot_case")
current.physical=false
for _,kind in ipairs(physics) do current.comps[kind]=nil end
current.sprite.enabled,current.sprite.tags.enabled_in_world=true,true
local excluded={held,customShape,customBody,extraBody,duplicate,joint,mimic,unpickable,crate,current}
local originals={}
for i=1,11 do
    originals[i]=bag(({"travel_satchel","travel_pack","loot_case"})[(i-1)%3+1])
end

local function converted(e)
    assert(not e.physical and e.sprite.enabled and e.sprite.tags.enabled_in_world and e.sprite.tags.enabled_in_hand)
    assert(entities[e.id]==e and e.x==17+e.id and e.y==-25-e.id)
    assert(e.comps.ItemComponent[1]==e.item and e.item.uses_remaining==e.id+2 and e.item.is_pickable)
    assert(e.comps.VariableStorageComponent[1]==e.custom and e.custom.value_int==41)
    for _,kind in ipairs(physics) do assert(not e.comps[kind],kind) end
end

migrate()
for i,e in ipairs(originals) do
    if i<=8 then converted(e) else assert(e.physical and e.writes==0) end
end
migrate()
local writes={}
for i,e in ipairs(originals) do converted(e); writes[i]=e.writes end
migrate()
for i,e in ipairs(originals) do assert(e.writes==writes[i]) end
for _,e in ipairs(excluded) do assert(e.writes==0) end

held.root=held.id
local streamed=bag("travel_pack")
migrate()
converted(held)
converted(streamed)

NHCompanions={order={"slime","dog"}}
NHTarot={order={"tarot_devil"}}
local function card(species)
    local e=bag("card_"..species)
    e.group,e.kindTag="noita_hideout_summon_card","nh_companion_"..species
    e.item.item_name="$nh_card_"..species
    if species:sub(1,6)~="tarot_" then
        e.sprite.image_file=e.sprite.image_file:gsub("%.png$","_world.png")
        e.comps.PhysicsImageShapeComponent[1].image_file=e.sprite.image_file
    end
    return e
end
local oldCards=migration(false,true)
local dog,tarot,heldCard=card("dog"),card("tarot_devil"),card("slime")
local otherCard,customCard,otherBag=card("foreign"),card("dog"),bag("loot_case")
heldCard.root=555
customCard.comps.PhysicsImageShapeComponent[1].image_file="mods/other/shape.png"
oldCards()
converted(dog)
converted(tarot)
assert(heldCard.writes==0 and otherCard.writes==0 and customCard.writes==0 and otherBag.writes==0)
heldCard.root=heldCard.id
local before=dog.writes
oldCards()
converted(heldCard)
assert(dog.writes==before)
local cards={}
for i=1,8 do cards[i]=card("tarot_devil") end
local all=migration(true,true)
all()
converted(otherBag)
for i=1,7 do converted(cards[i]) end
assert(cards[8].writes==0)
all()
converted(cards[8])
print("Legacy bags and collectible cards: bounded batches, original IDs, durability, saved state, held/streamed items and custom physics passed.")
