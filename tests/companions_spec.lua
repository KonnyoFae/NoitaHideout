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
assert(NHCompanions.rewardText({"dragon"},"zh",state):find("龙娘",1,true))
state.levels.farmland=1
state.summons={farm=31,livestock=62,pending={}}
assert(NHFarm.plant(state,{plot=1,token=0,crop="fiber"},0))
local ok,produced,awards=NHFarm.sync(state,120*60)
assert(ok and produced and #awards==1 and awards[1]=="dryad" and state.resources.fiber==6)
assert(state.warehouse[1].item.kind=="summon_card" and NHStore.category("summon_card")=="collection")
assert(state.warehouse[1].item.remaining==80)
assert(not NHFarm.sync(state,120*60) and #state.warehouse==1)
local graze=NHCompanions.reward(state,"livestock",1)
assert(#graze==1 and graze[1]=="griffin")
assert(NHStore.commit(state))
local before=assert(NHStore.load())
local one=assert(NHStore.load())
local batch=NHCompanions.reward(before,"livestock",40)
local total=0
for _=1,40 do total=total+#NHCompanions.reward(one,"livestock",1) end
assert(total==#batch and before.summons.livestock==one.summons.livestock)
for _,source in ipairs({{"beehive","bee"},{"gel_pool","slime"}}) do
    local facility,companion=unpack(source)
    before.summons[facility],one.summons[facility]=31,31
    local batchCards=NHCompanions.reward(before,facility,100)
    local singleCards=0
    for _=1,100 do singleCards=singleCards+#NHCompanions.reward(one,facility,1) end
    assert(#batchCards>0 and #batchCards==singleCards and before.summons[facility]==one.summons[facility])
    for _,id in ipairs(batchCards) do assert(id==companion) end
end
assert(before.summons.farm==one.summons.farm and before.summons.livestock==one.summons.livestock)

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
state.summons.beehive=654
state.summons.gel_pool=912
assert(NHStore.commit(state))
state=assert(NHStore.load())
assert(state.warehouse[2].item.count==4000000001 and #state.warehouse==1+#NHCompanions.order and not next(state.summons.pending))
assert(state.summons.beehive==654 and state.summons.gel_pool==912)
for _,id in ipairs({"bee","dragon","slime"}) do
    local found=false
    for _,row in ipairs(state.warehouse) do
        if row.item.species==id then
            found=true
            assert(row.item.remaining==80 and row.item.icon==NHCompanions.cardIcon(id))
        end
    end
    assert(found)
end
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
local hp=put(player,"DamageModelComponent",{hp=1,max_hp=4,melee=1,slice=1,poison=1,ice=1,curse=1,air_needed=true})
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
function EntityRemoveTag(id,tag) entities[id].tags[tag]=nil end
function EntityCreateNew() return create(0,0) end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityGetAllChildren(id,tag)
    local out={}
    for child,e in pairs(entities) do if e.parent==id and e.tags[tag] then out[#out+1]=child end end
    return out
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return entities[id].components[kind..(tag or "")] end
function EntityGetComponentIncludingDisabled(id,kind)
    local list={}
    for name,c in pairs(entities[id].components) do
        if name:sub(1,#kind)==kind then list[#list+1]=c end
    end
    return list
end
function EntityAddComponent2(id,kind,c) return put(id,kind,c,c._tags) end
function EntityRemoveComponent(id,c) for k,v in pairs(entities[id].components) do if v==c then entities[id].components[k]=nil end end end
function ComponentObjectGetValue2(c,_,key) return c[key] end
function ComponentObjectSetValue2(c,_,key,value) c[key]=value end
function GameGetAllInventoryItems() return {} end
function ComponentGetValue2(c,key) return c[key] end
function ComponentSetValue2(c,key,v,b) c[key]=v;if b then c.yVelocity=b end end
function EntityKill(id) entities[id]=nil end
function GameKillInventoryItem(who,id) assert(who==player and held==id);EntityKill(id) end
function GameIsInventoryOpen() return open end
function GamePrint() end
function GameTextGetTranslatedOrNot(k) return k end
local frame=200
function GameGetFrameNum() return frame end
function ProceduralRandomi() return 4 end
function EntityLoad(path,x,y)
    local name=path:match("([^/]+)%.xml$")
    if failed then return 0 end
    local id=create(x,y)
    local e=entities[id]
    e.file=name
    if name:match("^card_") then
        local species=name:sub(6)
        e.tags.noita_hideout_summon_card=true
        e.tags["nh_companion_"..species]=true
        put(id,"ItemComponent",{uses_remaining=80})
    elseif NHCompanions.species[name] then
        e.tags.noita_hideout_companion=true
        e.tags["nh_companion_"..name]=true
        if missingTag~="nh_companion_clock" then put(id,"VariableStorageComponent",{value_int=0,value_string=name},"nh_companion_clock") end
        spawned[#spawned+1]=id
    elseif name:match("^effect_") then put(id,"GameEffectComponent",{frames=-1})
    elseif name=="bee_guard" then e.tags.nh_bee_guard=true
    elseif name=="pebble_player_physics" then
        put(id,"AnimalAIComponent",{});put(id,"PhysicsBodyComponent",{});put(id,"CollisionTriggerComponent",{})
    elseif name=="curse" then put(id,"VariableStorageComponent",{name="effect_curse_damage"})
    elseif path:find("/projectiles/",1,true) or name=="matter_field" then
        put(id,"ProjectileComponent",{mEntityThatShot=0});put(id,"VelocityComponent",{})
        if name=="chain_bolt" then put(id,"LuaComponent",{script_source_file="data/scripts/projectiles/chain_bolt.lua"}) end
        if name=="disc_bullet_bigger" then
            put(id,"AreaDamageComponent",{})
            put(id,"LuaComponent",{script_source_file="data/scripts/projectiles/disc_bullet_bigger_trajectory.lua"})
        end
        if name:find("^swarm_") or name=="pollen" then put(id,"HomingComponent",{target_who_shot=true}) end
    else gifts[#gifts+1]=name end
    return id
end
local targets={}
local function target(x,herd,charm)
    local id=create(x,0)
    entities[id].herd,entities[id].charm=herd,charm
    put(id,"GenomeDataComponent",{})
    targets[#targets+1]=id
    return id
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
function GameShootProjectile(who,_,_,tx,_,id,notify)
    assert(who==player and notify==false and tx)
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
missingTag="nh_companion_clock"
assert(not NHCompanions.use(player,held,"en") and not EntityGetIsAlive(spawned[#spawned]))
missingTag=nil
rejectParent=true
assert(not NHCompanions.use(player,held,"en") and not EntityGetIsAlive(spawned[#spawned]))
rejectParent=false
assert(adapter.capture(held).remaining==80 and EntityGetIsAlive(pet))
local ok,err=NHCompanions.summon(player,"minotaur","en",function() return false,"Write failed." end)
assert(not ok and err=="Write failed." and not EntityGetIsAlive(spawned[#spawned]))
assert(EntityGetIsAlive(pet) and adapter.capture(held).remaining==80)
assert(entities[pet].scaleX==0.5 and entities[pet].scaleY==0.5)
assert(#EntityGetAllChildren(player,"noita_hideout_companion")==1)

function dofile_once(path) return dofile(path) end
dofile("mods/noita_hideout/files/companions/behavior.lua")
NHCompanions.update(pet)
assert(#shots==1)
local shot=entities[shots[1]].components.ProjectileComponent
assert(shot.mWhoShot==player and shot.mShooterHerdId==3 and shot.never_hit_player)
assert(entities[shots[1]].file=="cloud_acid" and entities[shots[1]].x==68)
targets={}
for _=1,119 do NHCompanions.update(pet) end
assert(hp.hp>1 and not EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_companion_gift"))
entities[player].x=1010
NHCompanions.update(pet)
assert(math.abs(entities[pet].x-1010)<20)
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
for _,species in ipairs(NHCompanions.order) do
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
    if effect then assert(#EntityGetAllChildren(player,"nh_companion_"..effect)==1) end
    last,oldAura=current,auras[1]
end
-- Recasting a card for the same species also spends one charge and starts a fresh visit.
local legacyAura=create(0,0,{nh_companion_effect_protection_radioactivity=true})
EntityAddChild(player,legacyAura)
local tierAura=create(0,0,{noita_hideout_companion_aura=true})
EntityAddChild(player,tierAura)
assert(NHCompanions.use(player,held,"en") and adapter.capture(held).remaining==1)
assert(not EntityGetIsAlive(last) and (not oldAura or not EntityGetIsAlive(oldAura)))
assert(not EntityGetIsAlive(legacyAura) and not EntityGetIsAlive(tierAura))
local replacement=spawned[#spawned]
assert(#EntityGetAllChildren(player,"noita_hideout_companion")==1 and EntityGetParent(replacement)==player)
assert(entities[replacement].components.VariableStorageComponentnh_companion_clock.value_int==0)
assert(EntityGetIsAlive(vanilla) and EntityGetIsAlive(food))
assert(NHCompanions.use(player,held,"en") and not EntityGetIsAlive(held))
assert(not EntityGetIsAlive(replacement) and #EntityGetAllChildren(player,"noita_hideout_companion")==1)
-- Verify native spell selection and owner-centred reactions, including allied,
-- charmed and occluded targets inside the close-range threshold.
entities[player].x=0
local function summon(id)
    assert(NHCompanions.summon(player,id,"zh",function() return true end))
    return spawned[#spawned]
end
local function countSince(first,file)
    local n=0
    for i=first+1,#shots do if entities[shots[i]].file==file then n=n+1 end end
    return n
end
local combatRoot="mods/noita_hideout/files/companions/"
local updated
function GetUpdatedEntityID() return updated end
for _,kit in ipairs({
    {"bee","swarm_wasp",5},{"dragon","flamethrower",3},{"slime","swarm_firebug",3,"freezing_gaze_beam",12},
    {"dog","chain_bolt",1,"magic_shield_part",4},{"minotaur","lance_holy",1,"big_magic_shield_part",8},
    {"cat","darkflame",1},{"griffin","griffin_ball_lightning",3,"light_bullet_air",3},
    {"flower_fairy","cloud_acid",1,"pollen",5},{"dryad",nil,0,"disc_bullet_bigger",1},
}) do
    targets={}
    local ally=target(15,100,0)
    local reinforcement=target(8,0,0)
    EntityAddTag(reinforcement,"nh_reinforcement")
    target(11,0,1);target(35,10,0)
    local species=kit[1]
    local far=target(species=="griffin" and 285 or 95,10,0)
    local companion=summon(species)
    local first=#shots
    NHCompanions.update(companion)
    assert(#shots==first+kit[3] and countSince(first,kit[2])==kit[3],species)
    if species=="dryad" then
        local found=false
        for _,e in pairs(entities) do
            if e.file=="pebble_player_physics" then
                assert(e.components.AnimalAIComponent.mGreatestThreat==far and e.components.LifetimeComponent.lifetime==288)
                assert(not e.components.CollisionTriggerComponent)
                found=true
            end
        end
        assert(found)
    end
    for i=first+1,#shots do
        local parts=entities[shots[i]].components
        assert(parts.ProjectileComponent.mWhoShot==player and parts.ProjectileComponent.never_hit_player)
        if parts.HomingComponent then assert(parts.HomingComponent.predefined_target==far and not parts.HomingComponent.target_who_shot) end
    end
    if species=="bee" then
        assert(#EntityGetAllChildren(companion,"nh_bee_guard")==3)
        updated=EntityGetAllChildren(companion,"nh_bee_guard")[1]
        dofile(combatRoot.."bee_orbit.lua")
        assert(math.abs(entities[updated].x)<=21)
        updated=shots[first+1]
        entities[far].charm=1
        dofile(combatRoot.."swarm_target.lua")
        assert(entities[updated].components.HomingComponent.predefined_target==0)
        entities[far].charm=0
        dofile(combatRoot.."swarm_target.lua")
        assert(entities[updated].components.HomingComponent.predefined_target==far)
    elseif species=="dragon" then
        updated=player
        local own=EntityLoad("data/entities/projectiles/deck/chain_bolt.xml",0,0)
        put(player,"ControlsComponent",{mAimingVectorNormalized=1})
        local read=ComponentGetValue2
        function ComponentGetValue2(c,k) if k=="mAimingVectorNormalized" then return 1,0 end; return read(c,k) end
        dofile(combatRoot.."dragon_shot.lua")
        local onShot=_G.shot
        onShot(shots[#shots])
        onShot(own);onShot(own)
        assert(countSince(first,"matter_field")==1)
        frame=frame+24
        entities[own].components.ProjectileComponent.mEntityThatShot=own
        onShot(own)
        assert(countSince(first,"matter_field")==1)
        put(player,"KickComponent",{can_kick=true})
        entities[player].components.ControlsComponent.mButtonFrameKick=frame
        NHCompanions.update(companion)
        assert(countSince(first,"matter_field")==2)
        ComponentGetValue2=read
    end
    local close=target(19,0,0)
    local before=#shots
    NHCompanions.update(companion)
    if kit[4] then assert(countSince(before,kit[4])==kit[5],species) end
    if species=="dog" or species=="minotaur" then
        for i=before+1,#shots do
            assert(EntityGetParent(shots[i])==companion and entities[shots[i]].components.VariableStorageComponent.value_int==player)
        end
    end
    if species=="cat" then assert(EntityHasTag(close,"effect_CURSE") and not EntityHasTag(ally,"effect_CURSE"))
    elseif species=="griffin" then
        -- Both attacks are ready with a distant enemy still in view. At the
        -- guard boundary, gusts take priority even during their own cooldown.
        entities[close].x=64
        entities[companion].components.VariableStorageComponentnh_companion_clock.value_int=84
        before=#shots
        NHCompanions.update(companion)
        assert(#shots==before+3 and countSince(before,"light_bullet_air")==3)
        NHCompanions.update(companion)
        assert(#shots==before+3)
        local outside=target(400,10,0)
        targets={outside}
        NHCompanions.update(companion)
        assert(#shots==before+3)
        -- With the player's sightline blocked, a shoulder-height caster can
        -- still see the close enemy. That must not arm a point-blank volley.
        local ray=RaytracePlatforms
        RaytracePlatforms=function(_,y) return y==0 end
        targets={close}
        NHCompanions.update(companion)
        RaytracePlatforms=ray
        assert(#shots==before+3)
        targets={far}
        NHCompanions.update(companion)
        assert(countSince(before,"griffin_ball_lightning")==3)
    elseif species=="dog" then
        updated=shots[first+1]
        assert(entities[updated].components.LuaComponent.script_source_file==combatRoot.."chain_jump.lua")
        dofile(combatRoot.."chain_jump.lua")
        assert(entities[updated].x==19)
    elseif species=="dryad" then
        local parts=entities[shots[#shots]].components
        assert(not parts.AreaDamageComponent and parts.LuaComponent.script_source_file==combatRoot.."disc_edge.lua")
    elseif species=="flower_fairy" then
        local clock=entities[companion].components.VariableStorageComponentnh_companion_clock
        clock.value_int=204
        NHCompanions.update(companion)
        assert(countSince(first,"pollen")==10 and countSince(first,"cloud_acid")==1)
        targets={far}
        NHCompanions.update(companion)
        assert(countSince(first,"cloud_acid")==2)
    end
    before=#shots
    NHCompanions.update(companion)
    if species=="dragon" then assert(countSince(before,"flamethrower")==3 and countSince(before,"matter_field")==0)
    else assert(#shots==before,species.." cooldown") end
end
targets={}
-- Check the actual Noita entity/card links and shipped PNG dimensions. The
-- source sheets remain archived with the project and must match the animation.
local function bytes(path)
    local file=assert(io.open(path,"rb"))
    local contents=file:read("*a")
    file:close()
    return contents
end
do
    local orb=bytes("mods/noita_hideout/files/projectiles/griffin_ball_lightning.xml")
    local motion=assert(orb:match("<VelocityComponent([^>]+)>"))
    local shot=assert(orb:match("<ProjectileComponent([^>]+)>"))
    local trail=assert(orb:match("<LightningComponent>(.-)</LightningComponent>"))
    assert(motion:find('air_friction="0"',1,true) and shot:find('lifetime_randomness="0"',1,true))
    assert(tonumber(shot:match('speed_min="(%d+)"'))*tonumber(shot:match('lifetime="(%d+)"'))/60>=300)
    assert(trail:find('damage_mortals="0"',1,true) and shot:find('explosion_dont_damage_shooter="1"',1,true))
end
local function png(path,width,height)
    local data=bytes(path)
    assert(data:sub(2,4)=="PNG" and data:sub(13,16)=="IHDR",path)
    local function dimension(offset)
        local a,b,c,d=data:byte(offset,offset+3)
        return ((a*256+b)*256+c)*256+d
    end
    assert(dimension(17)==width and dimension(21)==height,path)
    return data
end
local portraits={}
for _,id in ipairs({"bee","dragon","slime"}) do
    local base="mods/noita_hideout/files/"
    local sprite=base.."companions/"..id.."_idle"
    local source="resources/"..id.."/sprite-fusion-animation-idle-bounce-smooth-loop/spritesheet.png"
    local frameSize=id=="slime" and 65 or 64
    assert(png(sprite..".png",8*frameSize,frameSize)==bytes(source))
    local animation=bytes(sprite..".xml")
    assert(animation:find(sprite..".png",1,true) and animation:find('frame_count="8"',1,true))
    assert(animation:find('frame_width="'..frameSize..'"',1,true) and animation:find('frame_height="'..frameSize..'"',1,true))
    assert(animation:find('frame_wait="0.125"',1,true) and animation:find('loop="1"',1,true))
    assert(bytes(base.."companions/"..id..".xml"):find(sprite..".xml",1,true))
    local card=bytes(base.."items/card_"..id..".xml")
    assert(card:find('ui_sprite="'..NHCompanions.cardIcon(id)..'"',1,true))
    assert(card:find('uses_remaining="80"',1,true) and card:find("card_"..id.."_world.png",1,true))
    portraits[id]=png(NHCompanions.cardIcon(id),16,17)
    png(base.."items/card_"..id.."_world.png",10,13)
end
assert(portraits.bee~=portraits.dragon and portraits.slime~=portraits.dragon and portraits.slime~=portraits.bee)
print("Summon rewards, card durability, replacement rollback, source-scoped auras, role auras and expiration passed.")

local quick=create(0,0)
entities[quick].parent=player
function EntityGetName(id) return id==quick and "inventory_quick" or "" end
local unequipped=assert(adapter.restore({kind="summon_card",species="dryad",remaining=80},0,0))
open=true
assert(not NHCompanions.use(player,unequipped,"en",true))
entities[unequipped].parent=quick
assert(NHCompanions.use(player,unequipped,"en",true) and adapter.capture(unequipped).remaining==79 and held~=unequipped)
