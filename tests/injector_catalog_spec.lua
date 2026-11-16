local injectors=dofile("mods/noita_hideout/files/injectors.lua")
local base="mods/noita_hideout/files/"
local entities,updating={},nil
local function read(path)
    local f=assert(io.open(path,"rb"))
    local bytes=f:read("*a")
    f:close()
    return bytes
end
local function entity(tag)
    local id=#entities+1
    entities[id]={alive=true,tag=tag,components={},children={}}
    return id
end
local function component(id,kind,fields)
    local list=entities[id].components[kind] or {}
    entities[id].components[kind]=list
    list[#list+1]=fields
    return fields
end
function EntityGetAllChildren(id,tag)
    local live={}
    for _,child in ipairs(entities[id].children) do
        if entities[child].alive and (not tag or tag==entities[child].tag) then live[#live+1]=child end
    end
    return live
end
function EntityLoad(path)
    local xml=read(path)
    local id=entity(assert(xml:match('<Entity [^>]*tags="([^"]+)"')))
    for kind,attributes in xml:gmatch("<(%w+Component)%s+([^>]+)/>") do
        local fields={}
        for name,value in attributes:gmatch('([%w_]+)="([^"]*)"') do fields[name]=tonumber(value) or value end
        component(id,kind,fields)
    end
    return id
end
function EntityKill(id) entities[id].alive=false end
function EntityGetParent(id) return entities[id].parent end
function EntityHasTag(id,tag) return entities[id].tag==tag end
function EntityGetTransform() return 0,0 end
function EntityAddChild(id,child)
    entities[child].parent=id
    table.insert(entities[id].children,child)
end
function EntityGetComponent(id,kind) return entities[id].components[kind] end
function EntityGetFirstComponentIncludingDisabled(id,kind) return (EntityGetComponent(id,kind) or {})[1] end
function ComponentGetValue2(c,key) return c[key] end
function ComponentSetValue2(c,key,value) c[key]=value end
function GetUpdatedEntityID() return updating end
local player=entity("player_unit")
local damage=component(player,"DamageModelComponent",{hp=1,max_hp=5})
local paid=0
local function pay() paid=paid+1; return true,2 end
local function reject() return nil,"rejected" end
local function active(id) return EntityGetAllChildren(player,injectors.get(id).tag)[1] end
local native={fire="PROTECTION_FIRE",lightning="PROTECTION_ELECTRICITY",frost="PROTECTION_FREEZE",
    shield="CUSTOM",haste="MOVEMENT_FASTER",invisible="INVISIBILITY",rage="BERSERK",physical="PROTECTION_MELEE",
    poison="PROTECTION_RADIOACTIVITY",resist_all="PROTECTION_ALL"}
for _,id in ipairs(injectors.order) do
    local d=injectors.get(id)
    local item=read(base.."items/"..d.filename..".xml")
    assert(item:find('ui_sprite="'..d.icon..'"',1,true) and item:find("noita_hideout_dose,",1,true),id)
    assert(read(d.icon):sub(1,8)=="\137PNG\r\n\26\n")
    if id~="quick_heal" then
        local ok,reason=injectors.use(player,id,reject)
        assert(not ok and reason=="rejected" and not active(id) and not entities[#entities].alive,id)
        local previous=paid
        ok,reason=injectors.use(player,id,pay)
        assert(ok and reason==2 and paid==previous+1,id)
        local effect=assert(active(id))
        local timer=EntityGetFirstComponentIncludingDisabled(effect,"VariableStorageComponent")
        local field=timer and "value_int" or "frames"
        timer=timer or EntityGetFirstComponentIncludingDisabled(effect,"GameEffectComponent")
        local full=field=="frames" and d.seconds*60 or d.seconds
        assert(timer[field]==full,id)
        if native[id] then assert(timer.effect==native[id]) end
        timer[field]=1
        assert(not injectors.use(player,id,reject) and timer[field]==1,id)
        assert(injectors.use(player,id,pay) and timer[field]==full and paid==previous+2,id)
        assert(#EntityGetAllChildren(player,d.tag)==1 and active(id)==effect,id)
    end
end
local previous=paid
assert(not injectors.use(player,"quick_heal",reject) and damage.hp==1)
assert(injectors.use(player,"quick_heal",pay) and damage.hp==2)
damage.hp=4.8
assert(injectors.use(player,"quick_heal",pay) and damage.hp==5)
assert(not injectors.use(player,"quick_heal",pay) and paid==previous+2)
local mana=EntityGetFirstComponentIncludingDisabled(active("regen_mana"),"GameEffectComponent")
assert(mana.effect=="MANA_REGENERATION" and mana.frames==-1)
for _,id in ipairs({"healing_2","regen_mana"}) do
    damage.hp,damage.max_hp=1,10
    updating=assert(active(id))
    for i=1,60 do dofile(base.."bread_regeneration.lua") end
    local expected=id=="healing_2" and 60 or 30
    assert(math.abs(damage.hp-1-expected/25)<1e-8 and not entities[updating].alive,id)
end
assert(active("healing") and active("haste") and active("poison"))
local shield=read(base.."stimulant_shield.xml")
assert(shield:find('file="data/entities/misc/perks/shield.xml"',1,true))

-- A non-poison effect on the same child, items, and permanent effects survive.
updating=assert(active("poison"))
function GameGetGameEffectCount(target,id) assert(target==player and id=="POISON"); return 1 end
local mixed=entity("status")
EntityAddChild(player,mixed)
local toxin=component(mixed,"GameEffectComponent",{effect="POISON",frames=400})
local haste=component(mixed,"GameEffectComponent",{effect="MOVEMENT_FASTER",frames=300})
local permanent=component(mixed,"GameEffectComponent",{effect="POISON",frames=-1})
local held=entity("item")
EntityAddChild(player,held)
component(held,"ItemComponent",{})
local onItem=component(held,"GameEffectComponent",{effect="POISON",frames=100})
local onPlayer=component(player,"GameEffectComponent",{effect="POISON",frames=50})
dofile(base.."injector_antitoxin.lua")
assert(toxin.frames==1 and onPlayer.frames==1 and permanent.frames==-1 and onItem.frames==100 and haste.frames==300)
print("Injector catalog: native and stored assets, transactional refresh, quick healing, regeneration, shield and selective antitoxin passed.")
