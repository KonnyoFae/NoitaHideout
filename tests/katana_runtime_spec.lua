local root="mods/noita_hideout/files/"
local originalDofile=dofile
NHKatanas=originalDofile(root.."katanas.lua")
NHShields=originalDofile(root.."shields.lua")
NHFirearms=originalDofile(root.."firearms.lua")
local frame,selected,leftMouse,rightMouse,failCommit,wallDistance,prePostGap
local state,entities,events,fieldCreates,fieldCancels,spent,poses
local liveCharge,liveEpoch,ensureCount,rewardHits,rewarded,movementActive,movementApplies,movementReleases
local nativeDown,nativeStamp,combatTarget,fieldPayments,guiHpMultiplier,fxEvents,fxFollows
local rewards
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local shieldRuntime={
    snapshot=function(draft)
        if draft.gearShield and draft.gearShield.epoch==liveEpoch then draft.gearShield.item.charge=liveCharge end
    end,
    sync=function(draft)
        if draft.gearShield then liveCharge,liveEpoch=draft.gearShield.item.charge,draft.gearShield.epoch end
    end,
}
local combat={
    apply=function(player,event,hit)
        assert(player==1 and type(hit)=="table")
        events[#events+1]=copy(event)
        if combatTarget and event.plunder and not hit[combatTarget] then
            local enemy=combatTarget
            combatTarget=nil
            hit[enemy]=true
            local message="katana/"..event.token
            assert(rewards.mark(enemy,player,message))
            rewards.death(enemy,message,player)
            rewards.death(enemy,message,player)
            entities[enemy].alive=false
        end
        if rewardHits and event.plunder and not rewarded[event.token] then
            rewarded[event.token]=true
            assert(rewards.credit(player))
        end
        return 0
    end,
    safeStep=function(x,y,dx,dy,distance)
        local moved=math.min(distance,math.max(0,(wallDistance or math.huge)-(x*dx+y*dy)))
        return x+dx*moved,y+dy*moved,moved
    end,
}
local fields={}
function fields.activate(player,options,pay)
    for id=101,100+fieldCreates do if fields.active(id) then return nil,"Field already active." end end
    fieldPayments=fieldPayments+1
    local ok,paidDuration=pay()
    if not ok then return end
    local duration=paidDuration or options.duration
    fieldCreates=fieldCreates+1
    local id=100+fieldCreates
    entities[id]={alive=true,x=entities[player].x,y=entities[player].y,untilFrame=frame+duration,comps={},tags={}}
    return id,duration
end
function fields.active(id) return entities[id] and entities[id].alive and frame<entities[id].untilFrame end
function fields.cancel(id) fieldCancels=fieldCancels+1;entities[id].alive=false end
local visual={reset=function() end,pose=function(player,weapon,kind,now,action) poses[#poses+1]={kind=kind,action=action} end}
local fx={spawn=function(x,y,angle,kind,scale,flip)
    local entity=1000+#fxEvents
    fxEvents[#fxEvents+1]={entity=entity,x=x,y=y,angle=angle,kind=kind,scale=scale,flip=flip}
    return entity
end,follow=function(entity,x,y,angle,scale,flip)
    fxFollows[#fxFollows+1]={entity=entity,x=x,y=y,angle=angle,scale=scale,flip=flip}
end}
local movement={
    factor=0.3,
    apply=function(player)
        movementActive,movementApplies=true,movementApplies+1
        return true
    end,
    release=function(player)
        movementActive,movementReleases=false,movementReleases+1
    end,
    reset=function() movementActive=false end,
}
function dofile(path)
    if path==root.."shield_runtime.lua" then return shieldRuntime end
    if path==root.."katana_combat.lua" then return combat end
    if path==root.."katana_field.lua" then return fields end
    if path==root.."katana_visual.lua" then return visual end
    if path==root.."katana_rewards.lua" then return rewards end
    if path==root.."katana_fx.lua" then return fx end
    if path==root.."katana_movement.lua" then return movement end
    return originalDofile(path)
end
function dofile_once(path) return dofile(path) end
rewards=originalDofile(root.."katana_rewards.lua")
function ModIsEnabled() return false end
function GlobalsGetValue(_,default) return default end
function GameGetFrameNum() return frame end
function MagicNumbersGetValue(key) assert(key=="GUI_HP_MULTIPLIER");return tostring(guiHpMultiplier) end
function InputIsMouseButtonDown(button) return button==1 and leftMouse or button==2 and rightMouse or false end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive end
function EntityGetRootEntity(id) return entities[id].parent or id end
function EntityHasTag(id,tag) return entities[id] and entities[id].tags[tag] or false end
function EntityAddTag(id,tag) entities[id].tags[tag]=true end
function GameGetGameEffectCount() return 0 end
function EntityGetFirstComponentIncludingDisabled(id,kind,...)
    local tag=select(1,...)
    assert(select("#",...)==0 or tag~=nil,"Noita rejects an explicitly nil component tag")
    if tag=="" then return nil end -- Explicit empty tag is not an omitted filter.
    return entities[id] and entities[id].comps[kind..(tag or "")]
end
function EntityAddComponent2(id,kind,fields)
    local c={value_int=0,value_float=0,value_string=""}
    for k,v in pairs(fields) do c[k]=v end
    entities[id].comps[kind..(fields._tags or "")]=c
    return c
end
function ComponentGetValue2(c,key)
    local v=c[key]
    if type(v)=="table" then return unpack(v) end
    return v
end
function ComponentSetValue2(c,key,a,b) c[key]=b~=nil and {a,b} or a end
function EntityGetTransform(id)
    local e=entities[id]
    return e.x,e.y,e.rotation or 0,e.sx or 1,e.sy or 1
end
function EntitySetTransform(id,x,y,r,sx,sy)
    local e=entities[id]
    e.x,e.y,e.rotation,e.sx,e.sy=x,y,r or 0,sx or 1,sy or 1
end
function GamePlaySound() end
NHNative={held=function() return selected end}
NHTransfers={available=function(_,player,weapon) return player==1 and weapon==selected end}
NHEWItems=nil
local aimX,aimY=1,0
NHProducts={aim=function() return aimX,aimY end}
NHKatanas.ensureBuiltInAction=function() ensureCount=ensureCount+1;return true end
local runtime
local function commit(edit)
    local draft=copy(state)
    local ok=edit(draft)
    if not ok or failCommit then return false end
    shieldRuntime.snapshot(draft)
    draft.revision=draft.revision+1
    state=draft
    spent=spent+1
    return true
end
local function step(left,right,blocked,enabled,inputAge,mapped)
    -- One game tick: in native execution the pre callback observes the frame
    -- immediately before post. Same-frame execution remains useful in mocks.
    frame=frame+1-prePostGap
    leftMouse,rightMouse=left==true,right==true
    local c=entities[1].comps.ControlsComponent
    -- Fire2 is the flask-spray action and can share the physical left button.
    -- Keep native stamps separately: the runtime suppresses component fields.
    local down={Fire=leftMouse,Throw=rightMouse,Fire2=leftMouse}
    for _,action in ipairs({"Fire","Throw","Fire2"}) do
        local key=action:lower()
        if mapped and mapped[key]~=nil then down[action]=mapped[key] end
        if down[action] and not nativeDown[action] then nativeStamp[action]=frame end
        if mapped and mapped[key.."Age"]~=nil then nativeStamp[action]=frame-mapped[key.."Age"] end
        c["mButtonDown"..action]=down[action]
        c["mButtonFrame"..action]=nativeStamp[action] or -100
        nativeDown[action]=down[action]
    end
    c.mButtonDownLeftClick,c.mButtonDownRightClick=leftMouse,rightMouse
    runtime.capture(1,blocked==true)
    frame=frame+(inputAge~=nil and inputAge or prePostGap)
    local view=runtime.update(state,1,commit,enabled~=false)
    if not blocked and selected and NHKatanas.kind(selected) then
        assert(c.mButtonDownFire==false and c.mButtonDownThrow==false)
    end
    return view
end
local function advance(count,left,right,blocked)
    local view
    for _=1,count do view=step(left,right,blocked) end
    return view
end
local function attacks()
    local list,seen={},{}
    for _,event in ipairs(events) do
        if not seen[event.token] then list[#list+1]=event;seen[event.token]=true end
    end
    return list
end
local function reset(kind)
    if runtime then runtime.reset() end
    frame,selected,leftMouse,rightMouse,failCommit,wallDistance=100,7,false,false,false,nil
    prePostGap=0
    fieldCreates,fieldCancels,spent,ensureCount,fieldPayments=0,0,0,0,0
    nativeDown,nativeStamp,combatTarget={},{},nil
    guiHpMultiplier=25
    rewardHits,rewarded,movementActive,movementApplies,movementReleases=false,{},false,0,0
    events,poses,fxEvents,fxFollows={},{},{},{}
    state={profile=1,runSerial=1,revision=5,gearShield={id=10,epoch=3,item={kind="shield_storm",charge=90001,repair=0,delay=0}},
        gearRig={id=11,item={kind="ammo_rig",reserve=20}}}
    liveCharge,liveEpoch=90001,3
    entities={
        [1]={alive=true,x=0,y=0,rotation=0.1,sx=-1.2,sy=1.1,tags={player_unit=true},
            comps={ControlsComponent={},DamageModelComponent={hp=4,max_hp=10},CharacterDataComponent={mVelocity={100,-100}},
                CharacterPlatformingComponent={run_velocity=154}}},
        [7]={alive=true,x=0,y=0,parent=1,tags={["noita_hideout_"..(kind or "hf_blade")]=true},
            comps={ItemComponent={uses_remaining=NHKatanas.types[kind or "hf_blade"].durability or -1}}},
        [8]={alive=true,x=0,y=0,parent=1,tags={noita_hideout_hf_murasama=true},comps={}},
    }
    aimX,aimY=1,0
    runtime=originalDofile(root.."katana_runtime.lua")
    step(false,false)
end

reset("hf_blade")
step(true,false)
assert(#events==0)
step(false,false)
advance(10,false,false)
assert(#attacks()==1 and attacks()[1].damage==NHKatanas.types.hf_blade.quickDamage and not attacks()[1].plunder and spent==0)
step(true,false)
advance(NHKatanas.types.hf_blade.chargeFrames,true,false)
assert(#attacks()==1)
step(false,false)
advance(8,false,false)
assert(#attacks()==2 and attacks()[2].damage==NHKatanas.types.hf_blade.heavyDamage and spent==0)

reset("hf_murasama")
step(true,false)
advance(NHKatanas.types.hf_murasama.chargeFrames-1,true,false)
assert(#events==0 and state.gearRig.item.reserve==20)
advance(1,true,false)
assert(state.gearRig.item.reserve==15 and #attacks()==1)
advance(80,true,false)
assert(state.gearRig.item.reserve==15 and #attacks()==1 and entities[1].x==120)
assert(entities[1].rotation==0.1 and entities[1].sx==-1.2 and entities[1].sy==1.1,"Dash reset player rotation or skin scale")
step(false,false)
step(true,false)
advance(NHKatanas.types.hf_murasama.chargeFrames+8,true,false)
assert(state.gearRig.item.reserve==10 and #attacks()==2)

for _,reason in ipairs({"ammo","write","wall"}) do
    reset("hf_murasama")
    if reason=="ammo" then state.gearRig.item.reserve=4
    elseif reason=="write" then failCommit=true
    else wallDistance=0 end
    local before=state.gearRig.item.reserve
    step(true,false)
    advance(NHKatanas.types.hf_murasama.chargeFrames+15,true,false)
    assert(state.gearRig.item.reserve==before and #events==0 and entities[1].x==0)
    local guard=entities[1].comps.VariableStorageComponentnh_katana_dash_guard
    assert(not guard or guard.value_int==0)
end

reset("hf_murasama")
wallDistance=7
step(true,false)
advance(NHKatanas.types.hf_murasama.chargeFrames+20,true,false)
assert(entities[1].x==7 and state.gearRig.item.reserve==15 and #attacks()==1)
local guard=entities[1].comps.VariableStorageComponentnh_katana_dash_guard
assert(guard and guard.value_int==0)

reset("hf_blade")
step(false,true)
advance(NHKatanas.zandatsu.chargeFrames-1,false,true)
assert(fieldCreates==0 and liveCharge==90001)
local mode=advance(1,false,true)
assert(fieldCreates==1 and liveCharge==60001 and entities[1].comps.DamageModelComponent.hp==4)
assert(mode.plunder==750,"duration must reflect the shield points actually paid")
step(false,false)
advance(40,true,false)
assert(fieldCreates==1 and #attacks()>=6)
for _,event in ipairs(attacks()) do assert(event.plunder and event.damage==NHKatanas.types.hf_blade.quickDamage) end
assert(movementActive and movementApplies>0)
step(true,true)
assert(fieldCancels==1 and not movementActive)
advance(40,true,true)
assert(fieldCreates==1)

-- Switching, UI capture, or reloading while a button is held cannot release
-- the abandoned charge into a new weapon or activate an unpaid skill.
for _,interrupt in ipairs({"switch","menu","reload","disabled"}) do
    reset("hf_blade")
    step(true,false)
    advance(35,true,false)
    local beforePoses=#poses
    if interrupt=="switch" then selected=8;step(true,false)
    elseif interrupt=="menu" then step(true,false,true)
    elseif interrupt=="disabled" then step(true,false,false,false)
    else runtime=originalDofile(root.."katana_runtime.lua");step(true,false) end
    if interrupt=="menu" or interrupt=="disabled" then
        assert(#poses==beforePoses+1 and not poses[#poses].action,"Held sword must remain at the waist when combat is blocked")
    end
    advance(45,true,false)
    step(false,false)
    advance(6,false,false)
    assert(#events==0 and spent==0)
end
reset("hf_murasama")
step(true,false)
advance(NHKatanas.types.hf_murasama.chargeFrames,true,false)
local x=entities[1].x
selected=nil
step(false,false)
advance(10,false,false)
assert(entities[1].x==x and state.gearRig.item.reserve==15)
assert(entities[1].comps.VariableStorageComponentnh_katana_dash_guard.value_int==0)

reset("hf_blade")
liveCharge,state.gearShield.item.charge=0,0
step(false,true)
advance(80,false,true)
assert(fieldCreates==0 and spent==0)
reset("hf_blade")
step(false,true)
advance(NHKatanas.zandatsu.chargeFrames,false,true)
step(false,false)
advance(entities[101].untilFrame-frame+2,false,false)
assert(fieldCancels==1 and fieldCreates==1 and liveCharge==60001)

-- A queued kill is claimed before the same tick's skill payment. Spending
-- must read the newly committed shield charge rather than update()'s old table.
reset("hf_blade")
step(false,true)
advance(NHKatanas.zandatsu.chargeFrames-1,false,true)
assert(rewards.credit(1))
step(false,true)
assert(fieldCreates==1 and liveCharge==84001 and state.gearShield.item.charge==84001)
assert(entities[101].untilFrame-frame==750,"payment-time rewards must not increase the fixed half-cell payment or its duration")
assert(state.gearRig.item.reserve==25 and entities[1].comps.DamageModelComponent.hp==4.5 and state.katanaRewardSeen==1)

-- The final blow may arrive after the frame's claim. Its credit must still be
-- collected when the next input frame cancels, expires, or leaves the weapon.
for _,ending in ipairs({"switch","menu","disabled","right","expiry"}) do
    reset("hf_blade")
    step(false,true)
    advance(NHKatanas.zandatsu.chargeFrames,false,true)
    step(false,false)
    rewardHits=true
    step(true,false)
    assert(liveCharge==60001 and state.gearRig.item.reserve==20)
    if ending=="switch" then selected=nil;step(false,false)
    elseif ending=="menu" then step(false,false,true)
    elseif ending=="disabled" then step(false,false,false,false)
    elseif ending=="right" then step(false,true)
    else entities[101].untilFrame=frame+1;step(false,false) end
    assert(fieldCancels==1 and not movementActive)
    assert(liveCharge==84001 and state.gearRig.item.reserve==25 and entities[1].comps.DamageModelComponent.hp==4.5)
    rewardHits=false
    advance(20,false,false)
    assert(liveCharge==84001 and state.gearRig.item.reserve==25 and state.katanaRewardSeen==1)
end

-- Cooldown is a serialized player component, so reloading cannot shorten it.
reset("hf_blade")
step(true,false);step(false,false)
local before=#attacks()
runtime=originalDofile(root.."katana_runtime.lua")
step(false,false);step(true,false);step(false,false)
assert(#attacks()==before)

-- A polymorph/save transition can leave the restored body carrying its
-- serialized movement multiplier after runtime lost the old field record.
-- Cleanup must also happen before the early return for an ordinary held item.
for _,holding in ipairs({"none","katana"}) do
    reset("hf_blade")
    runtime=originalDofile(root.."katana_runtime.lua")
    if holding=="none" then selected=nil end
    movementActive=true
    local releases=movementReleases
    runtime.capture(1,false)
    assert(not movementActive and movementReleases>releases,"Restored body retained an abandoned movement multiplier")
end

-- Accept both mock same-frame input and Noita's actual pre=N / post=N+1.
-- Each helper invocation still advances one full game tick in either mode.
for _,gap in ipairs({0,1}) do
    reset("hf_blade")
    prePostGap=gap
    local startFrame=frame
    step(true,false)
    assert(frame==startFrame+1 and #events==0)
    step(false,false)
    assert(frame==startFrame+2 and #attacks()==1 and attacks()[1].damage==NHKatanas.types.hf_blade.quickDamage)
    assert(spent==0)
    reset("hf_blade")
    prePostGap=gap
    step(false,true)
    advance(NHKatanas.zandatsu.chargeFrames-1,false,true)
    assert(fieldCreates==0 and liveCharge==90001)
    local view=step(false,true)
    assert(fieldCreates==1 and view.plunder==750 and liveCharge==60001)
end

-- Future input and an input older than one frame must cancel pending charges
-- before an attack or resource payment, never release the abandoned action.
for _,age in ipairs({-1,2}) do
    for _,action in ipairs({"slash","field"}) do
        reset("hf_blade")
        if action=="slash" then
            step(true,false)
            advance(NHKatanas.types.hf_blade.chargeFrames,true,false)
            assert(step(false,false,false,true,age)==nil)
        else
            step(false,true)
            advance(NHKatanas.zandatsu.chargeFrames-1,false,true)
            assert(step(false,true,false,true,age)==nil)
        end
        step(false,false)
        advance(5,false,false)
        assert(#events==0 and fieldCreates==0 and spent==0 and liveCharge==90001)
    end
end

local function mappedStep(left,right,mapped)
    return step(left,right,false,true,nil,mapped)
end
local function mappedAdvance(count,left,right,mapped)
    local view
    for _=1,count do view=mappedStep(left,right,mapped) end
    return view
end

-- Real mouse actions can also raise Fire2 or Throw. Their native values may
-- remain raised after the physical button is up; neither is a new right click.
for _,overlap in ipairs({"fire2","throw"}) do
    reset("hf_blade")
    local native={[overlap]=true}
    mappedStep(true,false,native)
    mappedAdvance(40,true,false,native)
    assert(#events==0 and fieldCreates==0 and spent==0,"left charge was mistaken for Blade Mode: "..overlap)
    mappedStep(false,false,native)
    mappedAdvance(45,false,false,native)
    assert(#attacks()==1 and attacks()[1].damage==NHKatanas.types.hf_blade.heavyDamage)
    assert(fieldCreates==0 and spent==0,"stale native action restarted a released mouse press: "..overlap)
end
reset("hf_blade")
mappedAdvance(50,false,false,{fire2=true,fire2Age=0})
mappedStep(false,false,{fire2=false})
assert(#events==0 and fieldCreates==0,"Fire2 alone is never the alternate katana action")

-- Keyboard/gamepad mapped actions start only from a fresh stamp, and then
-- remain held even after that stamp ages. A stale raised field is not a press.
for _,age in ipairs({-2,2,40}) do
    reset("hf_blade")
    mappedStep(false,false,{fire=true,fireAge=age})
    mappedAdvance(40,false,false,{fire=true})
    mappedStep(false,false,{fire=false})
    assert(#events==0 and fieldCreates==0,"stale/future mapped Fire started a charge")
    mappedStep(false,false,{throw=true,throwAge=age})
    mappedAdvance(40,false,false,{throw=true})
    mappedStep(false,false,{throw=false})
    assert(fieldCreates==0 and spent==0,"stale/future mapped Throw started a field")
end
for _,age in ipairs({-1,0,1}) do
    reset("hf_blade")
    mappedStep(false,false,{fire=true,fireAge=age})
    mappedAdvance(35,false,false,{fire=true})
    mappedStep(false,false,{fire=false})
    assert(#attacks()==1 and attacks()[1].damage==NHKatanas.types.hf_blade.heavyDamage)
    assert(fieldCreates==0 and spent==0)
    reset("hf_blade")
    mappedStep(false,false,{throw=true,throwAge=age})
    mappedAdvance(80,false,false,{throw=true})
    assert(fieldCreates==1 and fieldPayments==1 and liveCharge==60001)
    mappedStep(false,false,{throw=false})
    mappedStep(false,false,{throw=true,throwAge=0})
    assert(fieldCancels==1,"a newly pressed mapped Throw should leave Blade Mode")
end

-- A genuinely mapped alternate press keeps ownership when the player later
-- adds mouse-primary input. Mixing controls must neither cancel its charge nor
-- invent another alternate edge after the paid field opens.
for _,gap in ipairs({0,1}) do
    reset("hf_blade")
    prePostGap=gap
    local view=mappedStep(false,false,{throw=true,throwAge=0})
    assert(view.preparing and fieldCreates==0)
    mappedAdvance(5,false,false,{throw=true})
    view=mappedStep(true,false,{throw=true})
    assert(view.preparing and fieldCreates==0,"mouse-primary canceled the already-owned mapped Throw charge")
    view=mappedAdvance(NHKatanas.zandatsu.chargeFrames-6,true,false,{throw=true})
    assert(fieldCreates==1 and fieldPayments==1 and liveCharge==60001 and view.plunder,
        "mapped Throw must finish at its original charge deadline while mouse-primary is held")
    view=mappedAdvance(13,true,false,{throw=true})
    assert(#attacks()>=2 and view.plunder and fieldCancels==0 and fieldPayments==1,
        "mixed-input hold must keep one paid field active for repeated slashes")
    for _,event in ipairs(attacks()) do assert(event.plunder) end
end

-- A new alternate press during quick-slash recovery still starts its actual
-- hold timer. It may resolve once recovery permits, without requiring a second
-- release/press or charging again from the end of the attack animation.
for _,kind in ipairs({"hf_blade","hf_murasama"}) do
    reset(kind)
    step(true,false);step(false,false)
    assert(#attacks()==1 and not attacks()[1].plunder)
    step(false,true)
    advance(NHKatanas.zandatsu.chargeFrames-1,false,true)
    assert(fieldCreates==0 and liveCharge==90001,"recovery input opened Blade Mode before a full real hold")
    local view=step(false,true)
    assert(fieldCreates==1 and fieldPayments==1 and liveCharge==60001 and view.plunder,
        "a fresh right hold during quick recovery was discarded or its timer was restarted")
end

-- First press owns an ordinary charge. Pressing both together chooses left;
-- releasing left cannot hand the still-held right button a synthetic edge.
for _,lead in ipairs({0,5}) do
    reset("hf_blade")
    if lead>0 then step(true,false);advance(lead,true,false) end
    step(true,true)
    advance(40,true,true)
    assert(fieldCreates==0 and #events==0,"opposite button stole an existing left charge")
    step(false,true)
    advance(40,false,true)
    assert(fieldCreates==0 and #attacks()==1 and attacks()[1].damage==NHKatanas.types.hf_blade.heavyDamage)
    step(false,false)
    step(false,true)
    advance(NHKatanas.zandatsu.chargeFrames,false,true)
    assert(fieldCreates==1 and liveCharge==60001,"right must work after its own release and new press")
end
reset("hf_blade")
step(false,true);advance(5,false,true)
step(true,true);advance(40,true,true)
assert(fieldCreates==1 and liveCharge==60001 and #attacks()>0)
for _,event in ipairs(attacks()) do assert(event.plunder,"a later left press stole the earlier right charge") end

-- A single paid field permits repeated taps and separately settles two kills.
-- No reward, attack edge, or raised Fire2 may replace the field or its deadline.
for _,kind in ipairs({"hf_blade","hf_murasama"}) do
    reset(kind)
    step(false,true)
    advance(NHKatanas.zandatsu.chargeFrames,false,true)
    local id,deadline=101,entities[101].untilFrame
    local view=step(true,true)
    assert(view.plunder==deadline-frame and fields.active(id) and fieldCancels==0,
        "left attacks must work while the initial right button is still held")
    assert(#attacks()==1 and attacks()[1].plunder)
    step(false,false)
    for _=1,3 do
        advance(7,false,false)
        mappedStep(true,false,{fire2=false})
        view=mappedStep(true,false,{fire2=true})
        assert(view.plunder==deadline-frame and fieldCancels==0,"delayed Fire2 ended Blade Mode after one slash")
        mappedStep(false,false,{fire2=true,throw=true,throwAge=20})
        advance(7,false,false)
    end
    for _,enemy in ipairs({20,21}) do
        entities[enemy]={alive=true,x=20,y=0,tags={enemy=true},comps={DamageModelComponent={hp=0,max_hp=4}}}
        combatTarget=enemy
        step(true,false)
        view=step(false,false)
        advance(7,false,false)
        assert(entities[enemy].tags.nh_katana_reward_paid and fields.active(id))
        assert(fieldCreates==1 and entities[id].untilFrame==deadline and fieldPayments==1,
            "attacks or rewards reset/repurchased the same field")
    end
    assert(state.katanaRewardSeen==2 and liveCharge==108001 and state.gearRig.item.reserve==30)
    assert(entities[1].comps.DamageModelComponent.hp==5 and fieldCancels==0)
    assert(#attacks()>=6 and spent==3,"one field payment and exactly two reward commits")
    step(true,false)
    step(true,true)
    assert(fieldCancels==1,"a genuinely re-pressed right button must still exit during left attacks")
end

-- Murasama fires once on a full hold, even with overlapping native actions.
reset("hf_murasama")
mappedStep(true,false,{throw=true,fire2=true})
mappedAdvance(120,true,false,{throw=true,fire2=true})
assert(#attacks()==1 and entities[1].x==120 and state.gearRig.item.reserve==15 and spent==1)
mappedStep(false,false,{throw=true,fire2=true})
mappedAdvance(45,false,false,{throw=true,fire2=true})
assert(#attacks()==1 and fieldCreates==0 and spent==1)

-- Dragon King's entire left action is free, including at zero durability,
-- with no equipped shield or ammo rig. Holding does not auto-dash or respawn.
for _,held in ipairs({"left","right"}) do
    reset("dragon_king")
    entities[7].comps.ItemComponent.uses_remaining=0
    selected=8
    step(held=="left",held=="right")
    selected=7
    for _=1,5 do
        local view=step(held=="left",held=="right")
        assert(view and view.kind=="dragon_king" and view.remaining==0,
            "held-input equip must retain zero durability in the HUD view")
        assert(not view.charge and not view.plunder and not view.stasis)
    end
    local view=step(false,false)
    assert(view.remaining==0 and #events==0 and fieldCreates==0 and spent==0,
        "releasing an equip-carried press must not fire or hide exhausted durability")
end
reset("dragon_king")
entities[7].comps.ItemComponent.uses_remaining=0
state.gearShield,state.gearRig=nil,nil
step(true,false)
advance(NHKatanas.types.dragon_king.chargeFrames-1,true,false)
assert(fieldCreates==0 and #events==0)
local dragonView=advance(1,true,false)
assert(fieldCreates==1 and dragonView.stasis==120 and not dragonView.plunder)
local shortDeadline=entities[101].untilFrame
dragonView=advance(119,true,false)
assert(dragonView.stasis==1 and #events==0 and not movementActive)
advance(31,true,false)
assert(fieldCreates==1 and fieldCancels==1 and entities[101].untilFrame==shortDeadline)
step(false,false)
assert(math.abs(entities[1].x-160/36)<0.000001,"release starts the first weighted dash step")
advance(7,false,false)
assert(entities[1].x==160 and #attacks()==1 and attacks()[1].damage==8 and #events==8)
assert(entities[7].comps.ItemComponent.uses_remaining==0 and spent==0 and fieldPayments==1)
advance(40,false,false)
step(true,false);step(false,false)
assert(#attacks()==2 and attacks()[2].damage==NHKatanas.types.dragon_king.quickDamage and spent==0)

-- Releasing before short stasis expires cancels it before the dash; opening
-- inventory does the same without releasing an abandoned dash afterward.
for _,ending in ipairs({"release","menu","switch","disabled"}) do
    reset("dragon_king")
    step(true,false);advance(18,true,false)
    assert(fieldCreates==1 and fields.active(101))
    if ending=="release" then
        step(false,false);advance(7,false,false)
        assert(entities[1].x==160 and #attacks()==1)
    else
        if ending=="menu" then step(true,false,true)
        elseif ending=="switch" then selected=8;step(true,false)
        else step(true,false,false,false) end
        advance(30,true,false);step(false,false)
        assert(entities[1].x==0 and #events==0)
    end
    assert(fieldCancels==1 and spent==0 and entities[7].comps.ItemComponent.uses_remaining==90)
end

-- A paid Dragon King field lasts exactly thirty seconds, spends one physical
-- durability once, and never installs the ordinary blades' movement limiter.
reset("dragon_king")
step(false,true);advance(36,false,true)
local longDeadline=entities[101].untilFrame
assert(longDeadline-frame==1800 and entities[7].comps.ItemComponent.uses_remaining==89)
assert(liveCharge==90001 and state.gearRig.item.reserve==20 and spent==0 and not movementActive)
dragonView=advance(40,true,true)
assert(#attacks()>=6 and dragonView.plunder==longDeadline-frame and fieldCancels==0)
entities[1].x=80
dragonView=step(false,false)
assert(dragonView.plunder and not movementActive and movementApplies==0 and fields.active(101))
dragonView=advance(longDeadline-frame-1,false,false)
assert(dragonView.plunder==1 and entities[101].untilFrame==longDeadline)
step(false,false)
assert(fieldCreates==1 and fieldCancels==1 and fieldPayments==1 and entities[7].comps.ItemComponent.uses_remaining==89)
assert(liveCharge==90001 and state.gearRig.item.reserve==20 and spent==0)
reset("dragon_king")
entities[7].comps.ItemComponent.uses_remaining=0
step(false,true);advance(80,false,true)
assert(fieldCreates==0 and entities[7].comps.ItemComponent.uses_remaining==0 and spent==0)
step(false,false);step(true,false);advance(18,true,false)
assert(fieldCreates==1,"zero durability blocks only the paid right skill")
step(false,false);advance(7,false,false)
assert(entities[1].x==160 and entities[7].comps.ItemComponent.uses_remaining==0)

-- Ordinary Blade Mode always spends half one cell. A 50-point cell pays 25
-- for five seconds, regardless of tier capacity or the filled portion.
local durations={
    {charge=30000,maxHP=4,multiplier=25,frames=300},
    {charge=30001,maxHP=4,multiplier=25,frames=300},
    {charge=60000,maxHP=4,multiplier=25,frames=300},
    {charge=120000,maxHP=4,multiplier=25,frames=300,shield="shield_basic"},
    {charge=180000,maxHP=4,multiplier=25,frames=300,shield="shield_fire"},
    {charge=210001,maxHP=4,multiplier=25,frames=300},
    {charge=240000,maxHP=40,multiplier=25,frames=3000},
    {charge=60000,maxHP=4,multiplier=50,frames=600},
}
for _,kind in ipairs({"hf_blade","hf_murasama"}) do
    for _,case in ipairs(durations) do
        reset(kind)
        liveCharge,state.gearShield.item.charge=case.charge,case.charge
        state.gearShield.item.kind=case.shield or "shield_storm"
        entities[1].comps.DamageModelComponent.max_hp=case.maxHP
        guiHpMultiplier=case.multiplier
        step(false,true)
        local view=advance(36,false,true)
        assert(fieldCreates==1 and view.plunder==case.frames and fields.active(101),"wrong shield-derived duration")
        assert(liveCharge==case.charge-NHShields.cell/2 and spent==1 and fieldPayments==1)
        local deadline=entities[101].untilFrame
        if case.frames>1 then
            frame=deadline-2
            view=step(false,true)
            assert(view.plunder==1 and fieldCancels==0)
        end
        step(false,true)
        assert(fieldCancels==1 and fieldCreates==1 and spent==1,"held activation button repaid after dynamic expiry")
    end
end

-- A tiny positive balance cannot buy a shorter field, even when maximum HP
-- and the displayed-health multiplier would make those points look larger.
for _,kind in ipairs({"hf_blade","hf_murasama"}) do
    for _,charge in ipairs({0,1,1200,NHShields.cell/2-1}) do
        reset(kind)
        liveCharge,state.gearShield.item.charge=charge,charge
        entities[1].comps.DamageModelComponent.max_hp=40
        guiHpMultiplier=50
        step(false,true)
        local view=advance(80,false,true)
        assert(fieldCreates==0 and fieldPayments==1 and spent==0 and not view.plunder and not movementActive)
        assert(liveCharge==charge and state.gearShield.item.charge==charge and state.revision==5)
        assert(state.gearShield.epoch==3 and state.gearShield.item.delay==0 and state.gearRig.item.reserve==20)
        assert(entities[1].comps.DamageModelComponent.hp==4,"insufficient shield must never spill into HP")
        step(false,false)
        advance(10,true,false)
        step(false,false)
        assert(#attacks()==1 and not attacks()[1].plunder,"failed activation must leave ordinary attacks usable")
    end
end

-- Full high-tier capacity buys more separate fields. Releasing and making a
-- new deliberate press after each expiry pays exactly the same half cell.
for _,kind in ipairs({"hf_blade","hf_murasama"}) do
    for _,shieldKind in ipairs({"shield_basic","shield_fire","shield_storm"}) do
        reset(kind)
        local casts=NHShields.types[shieldKind].cells*2
        state.gearShield.item.kind=shieldKind
        liveCharge,state.gearShield.item.charge=casts*NHShields.cell/2,casts*NHShields.cell/2
        entities[1].comps.DamageModelComponent.max_hp=4
        for cast=1,casts do
            step(false,true)
            local view=advance(NHKatanas.zandatsu.chargeFrames,false,true)
            assert(fieldCreates==cast and fieldPayments==cast and spent==cast and view.plunder==300)
            assert(liveCharge==(casts-cast)*NHShields.cell/2 and state.gearRig.item.reserve==20)
            local deadline=entities[100+cast].untilFrame
            step(false,false)
            frame=deadline-1
            view=step(false,false)
            assert(fieldCancels==cast and not view.plunder and not movementActive)
        end
        step(false,true);advance(80,false,true)
        assert(fieldCreates==casts and spent==casts and fieldPayments==casts+1 and liveCharge==0)
        assert(entities[1].comps.DamageModelComponent.hp==4)
    end
end

-- Charging, maximum-health changes and kill rewards after activation cannot
-- extend the prepaid deadline. The next cast can take a new snapshot.
reset("hf_blade")
liveCharge,state.gearShield.item.charge=60000,60000
entities[1].comps.DamageModelComponent.max_hp=4
step(false,true);advance(36,false,true)
local paidDeadline=entities[101].untilFrame
assert(paidDeadline-frame==300)
entities[1].comps.DamageModelComponent.max_hp=40
guiHpMultiplier=50
liveCharge,state.gearShield.item.charge=240000,240000
assert(rewards.credit(1))
local snapshotView=step(false,false)
assert(snapshotView.plunder==paidDeadline-frame and entities[101].untilFrame==paidDeadline)
assert(fieldPayments==1 and fieldCreates==1 and state.katanaRewardSeen==1)
frame=paidDeadline-1;step(false,false)
assert(fieldCancels==1)

-- Quick slashes, charged heavy slashes and both special dashes use the same
-- accelerated sweep. The image follows the new hand and has its own length.
for _,variant in ipairs({{"hf_blade","quick"},{"hf_blade","heavy"},{"hf_murasama","quick"},
    {"hf_murasama","dash"},{"dragon_king","quick"},{"dragon_king","dash"}}) do
    local kind,prefix=unpack(variant)
    reset(kind)
    local def=NHKatanas.types[kind]
    step(true,false)
    if prefix~="quick" then advance(def.chargeFrames,true,false) end
    if prefix~="dash" or kind=="dragon_king" then step(false,false) end
    local duration=def[prefix.."Frames"]
    advance(duration-1,false,false)
    local distance=def[prefix.."Lunge"] or def[prefix.."Distance"]
    local moving=def[prefix.."LungeFrames"] or duration
    assert(#events==duration and #attacks()==1)
    local position=0
    for tick,event in ipairs(events) do
        local delta=tick<=moving and distance*2*tick/(moving*(moving+1)) or 0
        assert(math.abs(event.x1-position)<0.000001 and event.y1==-4,"capsule must begin at the previous hand")
        position=position+delta
        assert(math.abs(event.fxX-position)<0.000001 and event.fxY==-4,"image origin must follow the hand after movement")
        assert(math.abs(event.x2-event.fxX-def[prefix.."Reach"])<0.000001 and event.y2==-4)
        assert(event.fxReach==def[prefix.."FxReach"] and event.showFx==(tick==1))
    end
    assert(math.abs(entities[1].x-distance)<0.000001 and entities[1].y==0)
    assert(entities[1].rotation==0.1 and entities[1].sx==-1.2 and entities[1].sy==1.1)
    assert(#fxEvents==1 and #fxFollows==duration-1,"one swing generated repeated slash sprites")
    assert(fxEvents[1].scale==def[prefix.."FxReach"]/64)
    for _,follow in ipairs(fxFollows) do assert(follow.entity==fxEvents[1].entity) end
end

-- At zero aim the attack follows facing, matching the idle blade.
reset("hf_blade")
aimX,aimY=0,0
step(true,false);step(false,false);advance(6,false,false)
assert(math.abs(entities[1].x+NHKatanas.types.hf_blade.quickLunge)<0.000001 and entities[1].y==0)

-- The same collision limiter also stops ordinary heavy/quick attack movement.
for _,heavy in ipairs({false,true}) do
    reset("hf_blade")
    wallDistance=2
    step(true,false)
    if heavy then advance(30,true,false) end
    step(false,false);advance(8,false,false)
    assert(entities[1].x==2 and #attacks()==1,"ordinary attack passed the movement obstruction")
    assert(#fxEvents==1)
end

-- Blade Mode lunges honor the movement multiplier but can never move their
-- own caster outside the fixed circle. Deliberate walking out still cancels.
for _,kind in ipairs({"hf_blade","hf_murasama","dragon_king"}) do
    reset(kind)
    local def=NHKatanas.types[kind]
    step(false,true);advance(36,false,true);step(false,false)
    local deadline=entities[101].untilFrame
    step(true,false);advance(4,true,false)
    local multiplier=kind=="dragon_king" and 1 or 0.3
    assert(math.abs(entities[1].x-def.quickLunge*multiplier)<0.000001,"Blade Mode lunge ignored its movement policy")
    step(false,false);advance(7,false,false)
    entities[1].x,entities[1].y=159.75,0
    local view=advance(120,true,false)
    assert(entities[1].x<160 and entities[1].x>=159.75 and entities[1].y==0)
    assert(view.plunder==deadline-frame and fieldCreates==1 and fieldCancels==0 and fieldPayments==1)
    assert(entities[101].untilFrame==deadline,"edge slashes reset their paid deadline")
    step(false,false)
    entities[1].x,entities[1].y=0,159.75;aimX,aimY=0.8,0.6
    view=advance(45,true,false)
    assert(entities[1].x^2+entities[1].y^2<160^2 and view.plunder and fieldCancels==0,"diagonal edge slashes escaped the circle")
    entities[1].x,entities[1].y=161,0
    step(false,false)
    assert(fieldCancels==1,"manual movement beyond the circle must still end the field")
end

-- Clip the actual floor-projected step, while keeping the blade pointed
-- down at the reticle. Clipping the requested diagonal can push past the rim.
reset("dragon_king")
step(false,true);advance(36,false,true);step(false,false)
entities[1].y=-54
entities[1].x=math.sqrt(160^2-54^2)-0.25
aimX,aimY=math.cos(math.rad(12)),math.sin(math.rad(12))
local oldStep=combat.safeStep
combat.safeStep=function(x,y,dx,dy,distance) return x+dx*distance,y,distance end
local edgeView=advance(16,true,false)
assert(edgeView.plunder and fields.active(101) and entities[1].x^2+entities[1].y^2<160^2)
local swing=events[#events]
assert(math.abs(swing.y2-swing.fxY-aimY*NHKatanas.types.dragon_king.quickReach)<0.00001)
combat.safeStep=oldStep
dofile=originalDofile
print("Katana runtime: native inputs, paid-duration snapshots, accelerated capsule sweeps, single following slash art and Blade Mode boundary lunges passed.")
