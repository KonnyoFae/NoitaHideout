local settings,flags={},{}
local fail_head=false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v)
    if fail_head and k:match("_revision$") then return end
    settings[k]=v
end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
function GlobalsGetValue(_,fallback) return fallback end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
local state=assert(NHStore.load())
NHStore.newRun(state)
state.levels.farmland=1
state.summons={farm=31,livestock=62,pending={}}
assert(NHFarm.plant(state,{plot=1,token=0,crop="fiber"},0))
local request={plot=1,token=1,crop="fiber"}
local ok,awards=NHFarm.harvest(state,request,120*60)
assert(ok and #awards==1 and awards[1]=="dryad" and state.resources.fiber==6)
assert(state.warehouse[1].item.kind=="summon_card" and NHStore.category("summon_card")=="collection")
assert(state.warehouse[1].item.remaining==80)
assert(not NHFarm.harvest(state,request,120*60) and #state.warehouse==1)
local graze=NHCompanions.reward(state,"livestock",1)
assert(#graze==1 and graze[1]=="griffin")
assert(NHStore.commit(state))
local before=assert(NHStore.load())
local one=assert(NHStore.load())
local batch=NHCompanions.reward(before,"livestock",40)
local total=0
for _=1,40 do total=total+#NHCompanions.reward(one,"livestock",1) end
assert(total==#batch and before.summons.livestock==one.summons.livestock)

-- Used cards each occupy a slot. Capturing another species at capacity queues
-- its reward; full copies of an already stored species still join their stack.
local max=NHStore.warehouseCapacity(state,"collection")
while #state.warehouse<max do
    local worn=NHCompanions.withCount({species="dryad",remaining=79},1)
    assert(NHCompanions.put(state,"warehouse",#state.warehouse+1,nil,worn))
end
state.summons.farm=31
assert(#NHCompanions.reward(state,"farm",1)==1 and state.warehouse[1].item.count==2 and #state.warehouse==max)
state.summons.farm=62
local pending=NHCompanions.reward(state,"farm",1)
assert(#pending==1 and state.summons.pending.flower_fairy==1 and #state.warehouse==max)
assert(NHCompanions.rewardText(pending,"zh",state):find("腾出",1,true))
assert(NHStore.commit(state))
local changed={}
for k,v in pairs(state) do changed[k]=v end
changed.warehouse={}
for i=2,#state.warehouse do changed.warehouse[i-1]=state.warehouse[i] end
local nextId=state.nextItemId
fail_head=true
assert(not NHStore.commit(changed))
assert(#changed.warehouse==max-1 and changed.nextItemId==nextId and state.summons.pending.flower_fairy==1)
assert(assert(NHStore.load()).summons.pending.flower_fairy==1)
fail_head=false
assert(NHStore.commit(changed))
assert(#changed.warehouse==max and changed.nextItemId==nextId+1 and not next(changed.summons.pending))
state=assert(NHStore.load())
assert(state.warehouse[max].item.species=="flower_fairy" and state.warehouse[max].slot==1)
assert(NHStore.commit(state) and state.nextItemId==nextId+1)

-- Stage a 0.22-shaped snapshot: cards used to be individual equipment rows,
-- including slots beyond the capacity of a fresh collection.
state.collectionSlots=nil
state.levels.warehouse_equipment=1
state.warehouse={{id=nextId,slot=67,item=NHCompanions.withCount({species="griffin",remaining=2},1)}}
state.nextItemId=nextId+1
NHStore.itemCategories.summon_card="equipment"
assert(NHStore.commit(state))
NHStore.itemCategories.summon_card="collection"
state=assert(NHStore.load())
assert(state.warehouse[1].id==nextId and state.warehouse[1].slot==1 and state.warehouse[1].item.remaining==2)
assert(NHCompanions.grantSet(state))
local full=state.warehouse[2].item
assert(full.species=="dryad" and full.remaining==80 and state.warehouse[1].item.remaining==2)
state.summons.pending.dryad=4000000000
assert(NHStore.commit(state))
state=assert(NHStore.load())
assert(state.warehouse[2].item.count==4000000001 and #state.warehouse==5 and not next(state.summons.pending))
assert(not NHCompanions.validCard({species="dryad",remaining=79,count=2}))
assert(not NHCompanions.validCard({species="dryad",remaining=80,count=0}))

local entities,serial={},0
local function create(x,y,tags)
    serial=serial+1
    entities[serial]={x=x,y=y,rotation=0,scaleX=1,scaleY=1,parent=0,tags=tags or {},components={}}
    return serial
end
local player=create(0,0,{player_unit=true})
local function put(id,kind,values,tag)
    entities[id].components[kind..(tag or "")]=values
    return values
end
local hp=put(player,"DamageModelComponent",{hp=1,max_hp=4})
put(player,"GenomeDataComponent",{herd_id=3})
local held,open,failed=false,false,false
local rejectParent,missingTag=false,nil
local spawned,shots,gifts={},{},{}
function EntityGetTransform(id)
    local e=entities[id]
    return e.x,e.y,e.rotation,e.scaleX,e.scaleY
end
function EntitySetTransform(id,x,y,rotation,sx,sy)
    local e=entities[id]
    e.x,e.y,e.rotation,e.scaleX,e.scaleY=x,y or 0,rotation or 0,sx or 1,sy or 1
end
function EntityGetParent(id) return entities[id].parent end
function EntityAddChild(id,child)
    if not rejectParent then entities[child].parent=id end
end
function EntityRemoveFromParent(id) entities[id].parent=0 end
function EntityHasTag(id,tag) return entities[id] and entities[id].tags[tag] end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetAllChildren(id,tag)
    local out={}
    for child,e in pairs(entities) do if e.parent==id and e.tags[tag] then out[#out+1]=child end end
    return out
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return entities[id].components[kind..(tag or "")] end
function ComponentGetValue2(c,key) return c[key] end
function ComponentSetValue2(c,key,v,b) c[key]=v;if b then c.yVelocity=b end end
function EntityKill(id) entities[id]=nil end
function GameKillInventoryItem(who,id) assert(who==player and held==id);EntityKill(id) end
function GameIsInventoryOpen() return open end
function GamePrint() end
function GameTextGetTranslatedOrNot(k) return k end
function GameGetFrameNum() return 200 end
function ProceduralRandomi() return 4 end
function EntityLoad(path,x,y)
    local name=path:match("([^/]+)%.xml$")
    if failed then return 0 end
    local id=create(x,y)
    local e=entities[id]
    if name:match("^card_") then
        local species=name:sub(6)
        e.tags.noita_hideout_summon_card=true
        e.tags["nh_companion_"..species]=true
        put(id,"ItemComponent",{uses_remaining=80})
    elseif NHCompanions.species[name] then
        e.tags.noita_hideout_companion=true
        put(id,"VariableStorageComponent",{value_int=0,value_string=name},"nh_companion_clock")
        for _,t in ipairs({"nh_trip","nh_position","nh_gifts"}) do
            if t~=missingTag then put(id,"VariableStorageComponent",{value_int=0,value_float=0},t) end
        end
        spawned[#spawned+1]=id
    elseif name:match("^effect_") then put(id,"GameEffectComponent",{frames=-1})
    elseif name=="bolt" then put(id,"ProjectileComponent",{});put(id,"VelocityComponent",{})
    else gifts[#gifts+1]=name end
    return id
end
local targets={}
local function target(x,herd,charm)
    local id=create(x,0)
    entities[id].herd,entities[id].charm=herd,charm
    put(id,"GenomeDataComponent",{})
    targets[#targets+1]=id
end
target(20,100,0);target(35,10,0);target(55,10,1);target(65,10,0)
function EntityGetInRadiusWithTag() return targets end
function EntityGetHerdRelation(_,id) return entities[id].herd end
function EntityGetFirstHitboxCenter(id)
    local x,y=EntityGetTransform(id)
    return x==65 and x+3 or x,y
end
function GameGetGameEffectCount(id) return entities[id].charm end
function RaytracePlatforms(_,_,tx) return tx==35 end
function GameShootProjectile(who,_,_,tx,_,id)
    assert(who==player and tx==68)
    shots[#shots+1]=id
end
NHNative={held=function() return held end}
local adapter
NHTransfers={registerItem=function(kind,_,codec) assert(kind=="summon_card");adapter=codec end}
NHCompanions.registerItems()
local raw=assert(adapter.restore({kind="summon_card",species="flower_fairy",remaining=2},10,20))
held=raw
open=true
assert(not NHCompanions.use(player,raw,"en"))
open,failed=false,true
assert(not NHCompanions.use(player,raw,"en") and adapter.capture(raw).remaining==2)
failed=false
assert(NHCompanions.use(player,raw,"en") and adapter.capture(raw).remaining==1)
local pet=spawned[1]
local restored=assert(adapter.restore(adapter.capture(raw),0,0))
assert(adapter.capture(restored).remaining==1 and adapter.capture(restored).species=="flower_fairy")
assert(not adapter.restore({kind="summon_card",species="griffin",remaining=81},0,0))
assert(not adapter.restore({kind="summon_card",species="missing",remaining=1},0,0))

-- A bad replacement must leave the current follower and the new card intact.
held=assert(adapter.restore({kind="summon_card",species="minotaur",remaining=80},0,0))
failed=true
assert(not NHCompanions.use(player,held,"en"))
failed=false
missingTag="nh_trip"
assert(not NHCompanions.use(player,held,"en") and not EntityGetIsAlive(spawned[#spawned]))
missingTag=nil
rejectParent=true
assert(not NHCompanions.use(player,held,"en") and not EntityGetIsAlive(spawned[#spawned]))
rejectParent=false
assert(adapter.capture(held).remaining==80 and EntityGetIsAlive(pet))
assert(entities[pet].scaleX==0.5 and entities[pet].scaleY==0.5)
assert(#EntityGetAllChildren(player,"noita_hideout_companion")==1)

function dofile_once(path) dofile(path) end
dofile("mods/noita_hideout/files/companions/behavior.lua")
NHCompanions.update(pet)
assert(#shots==1)
local shot=entities[shots[1]].components.ProjectileComponent
assert(shot.mWhoShot==player and shot.mShooterHerdId==3 and shot.damage==0.16)
targets={}
for _=1,119 do NHCompanions.update(pet) end
assert(hp.hp>1 and #gifts==0 and entities[pet].components.VariableStorageComponentnh_trip.value_int==0)
-- A large teleport brings the companion along without earning travel credit.
entities[player].x=1010
NHCompanions.update(pet)
assert(math.abs(entities[pet].x-1010)<20 and entities[pet].components.VariableStorageComponentnh_trip.value_int==0)
for cycle=1,3 do
    entities[pet].components.VariableStorageComponentnh_gifts.value_int=4
    for _=1,300 do entities[player].x=entities[player].x+2;NHCompanions.update(pet) end
end
assert(#gifts==2 and gifts[1]=="bandage")
while EntityGetIsAlive(pet) do NHCompanions.update(pet) end
held=raw
assert(NHCompanions.use(player,raw,"en") and not EntityGetIsAlive(raw))
local last=spawned[#spawned]
local oldAura
local vanilla=EntityLoad("data/entities/misc/effect_protection_melee.xml",0,0)
EntityAddChild(player,vanilla)
local food=EntityLoad("mods/noita_hideout/files/effect_food_levitation.xml",0,0)
EntityAddTag(food,"noita_hideout_effect_food_levitation")
EntityAddChild(player,food)
for _,species in ipairs({"dryad","flower_fairy","minotaur","griffin"}) do
    held=assert(adapter.restore({kind="summon_card",species=species,remaining=3},0,0))
    assert(NHCompanions.use(player,held,"en"))
    assert(adapter.capture(held).remaining==2 and not EntityGetIsAlive(last))
    if oldAura then assert(not EntityGetIsAlive(oldAura)) end
    local current=spawned[#spawned]
    assert(#EntityGetAllChildren(player,"noita_hideout_companion")==1)
    local body=entities[current]
    assert(body.scaleX==0.5 and body.scaleY==0.5 and body.x==entities[player].x+12 and body.y==entities[player].y-8)
    NHCompanions.update(current)
    assert(body.scaleX==0.5 and body.scaleY==0.5)
    entities[player].x=entities[player].x-40
    NHCompanions.update(current)
    assert(body.scaleX==-0.5 and body.scaleY==0.5)
    entities[player].x=entities[player].x+80
    NHCompanions.update(current)
    assert(body.scaleX==0.5 and body.scaleY==0.5)
    assert(entities[player].scaleX==1 and entities[player].scaleY==1)
    local effect=NHCompanions.species[species].effect
    local auras=EntityGetAllChildren(player,"noita_hideout_companion_aura")
    if effect then
        assert(#auras==1 and EntityHasTag(auras[1],"nh_companion_"..effect))
        assert(entities[auras[1]].components.GameEffectComponent.frames==70)
    else
        assert(#auras==0)
    end
    last,oldAura=current,auras[1]
end
-- Recasting a card for the same species also spends one charge and starts a fresh visit.
local legacyAura=create(0,0,{nh_companion_effect_protection_radioactivity=true})
EntityAddChild(player,legacyAura)
local tierAura=create(0,0,{noita_hideout_companion_aura=true})
EntityAddChild(player,tierAura)
assert(NHCompanions.use(player,held,"en") and adapter.capture(held).remaining==1)
assert(not EntityGetIsAlive(last) and not EntityGetIsAlive(oldAura))
assert(not EntityGetIsAlive(legacyAura) and not EntityGetIsAlive(tierAura))
local replacement=spawned[#spawned]
assert(#EntityGetAllChildren(player,"noita_hideout_companion")==1 and EntityGetParent(replacement)==player)
assert(entities[replacement].components.VariableStorageComponentnh_companion_clock.value_int==0)
assert(EntityGetIsAlive(vanilla) and EntityGetIsAlive(food))
assert(NHCompanions.use(player,held,"en") and not EntityGetIsAlive(held))
assert(not EntityGetIsAlive(replacement) and #EntityGetAllChildren(player,"noita_hideout_companion")==1)
print("Summon rewards, card durability, replacement rollback, source-scoped auras, travel gifts and expiration passed.")
