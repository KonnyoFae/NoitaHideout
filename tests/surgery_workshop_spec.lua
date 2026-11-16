local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local recipes={}
for _,recipe in ipairs(NHStore.recipes) do recipes[recipe.id]=recipe end
local function addItem(state,slot,item)
    local row={id=state.nextItemId,slot=slot,item=item}
    state.nextItemId=state.nextItemId+1
    state.warehouse[#state.warehouse+1]=row
    return row
end

local adapters={}
NHTransfers={registerItem=function(kind,match,adapter) adapters[kind]={match=match,adapter=adapter} end}
dofile("mods/noita_hideout/files/products.lua")
local entity
function EntityLoad(path)
    entity={path=path,kind=path:match("/([%w_]+)%.xml$"),item={uses_remaining=-1}}
    return entity
end
function EntityHasTag(e,tag) return tag=="noita_hideout_"..e.kind end
function EntityGetFirstComponentIncludingDisabled(e,kind) if kind=="ItemComponent" then return e.item end end
function ComponentGetValue2(c,key) return c[key] end
function ComponentSetValue2(c,key,value) c[key]=value end
local translations=",en,ru,pt-br,es-es,de,fr-fr,it,pl,zh-cn,jp,ko"
function ModTextFileGetContent() return translations end
function ModTextFileSetContent(_,value) translations=value end
dofile("mods/noita_hideout/files/native_items.lua")
NHNative.registerTranslations()
local registered=translations
NHNative.registerTranslations()
assert(translations==registered)

local tiers={
    {id="field_surgery_kit",ingredient="medkit",herbs=3,essence=2,work=30,cast=3,heal=20},
    {id="tactical_surgery_kit",ingredient="tactical_medkit",herbs=5,essence=3,work=90,cast=4,heal=35},
    {id="advanced_surgery_kit",ingredient="advanced_medkit",herbs=8,essence=4,work=180,cast=5,heal=50},
}
for _,tier in ipairs(tiers) do
    local id=tier.id
    local recipe=assert(recipes[id])
    local kit=assert(NHSurgeryKits.types[id])
    assert(recipe.category=="medical" and recipe.facility=="medical" and NHStore.category(id)=="supplies")
    assert(recipe.storedIngredient==tier.ingredient and NHStore.productionFrames(recipe)==tier.work*60)
    assert(kit.uses==1 and kit.castFrames==tier.cast*60 and kit.healPercent==tier.heal)
    assert(recipe.item.kind==id and recipe.item.remaining==1)
    for _,good in ipairs(NHStore.shopGoods) do assert(not good.item or good.item.kind~=id) end
    local desc=assert(translations:match("\nnh_hideout_"..id.."_desc,([^\n]+)"))
    assert(desc:find("受伤",1,true) and desc:find(tier.cast.." 秒",1,true) and desc:find(tier.heal.."%",1,true))
    assert(select(2,desc:gsub(",",""))==10)

    settings,flags={},{}
    local state=assert(NHStore.load())
    local run=NHStore.newRun(state)
    local full=addItem(state,1,NHMedkits.item(tier.ingredient))
    local worn=NHMedkits.item(tier.ingredient)
    worn.remaining=1
    addItem(state,2,worn)
    for slot=3,NHStore.warehouseCapacity(state,"supplies") do addItem(state,slot,{kind="grenade"}) end
    state.resources={herb=tier.herbs,essence_healing=tier.essence}
    assert(not NHStore.startOrder(state,id) and not state.order)
    state.levels.medical=1
    state.resources.essence_healing=tier.essence-1
    assert(not NHStore.startOrder(state,id) and state.resources.herb==tier.herbs and state.warehouse[2].item==worn)
    state.resources.essence_healing=tier.essence
    assert(NHStore.startOrder(state,id) and state.order.output.slot==2)
    assert((state.resources.herb or 0)==0 and (state.resources.essence_healing or 0)==0)
    assert(state.warehouse[1]==full and not NHStore.startOrder(state,id) and NHStore.commit(state))
    state=assert(NHStore.load())
    local step={orderId=state.order.id,run=run,progress=state.order.required}
    local changed,done=NHStore.advanceProduction(state,step)
    assert(changed and done and NHStore.commit(state))
    state=assert(NHStore.load())
    assert(not NHStore.advanceProduction(state,step))
    local output=state.warehouse[assert(NHStore.slotIndex(state,"warehouse",2,id))].item
    assert(output.kind==id and output.remaining==1)

    local handler=assert(adapters[id])
    local pack=assert(handler.adapter.restore(output,0,0))
    assert(handler.match(pack) and pack.item.uses_remaining==1)
    local saved=assert(handler.adapter.capture(pack))
    assert(saved.kind==id and saved.remaining==1 and saved.icon==recipe.item.icon)
    pack.item.uses_remaining=0
    assert(not handler.adapter.capture(pack))
    output.remaining=2
    assert(not handler.adapter.restore(output,0,0) and not NHStore.commit(state))
    assert(assert(NHStore.load()).warehouse[assert(NHStore.slotIndex(state,"warehouse",2,id))].item.remaining==1)
end
print("Workshop surgery kits: all three recipes, fixed costs, worn inputs, delivery, physical adapters and localization passed.")
