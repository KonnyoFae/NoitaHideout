local root="mods/noita_hideout/files/"
local frame,online,ready,canLand,commitOK=20,false,true,true,true
local peer="Alice"
local state={profile=1,runSerial=7}
local globals,fx,sounds={},{},{}
local gear={captured=0,restored=0,cancelled=0}
local function entity(path,x,y) return {path=path,x=x or 0,y=y or 0,tags={},children={},components={}} end
local function add(e,kind,c)
    c.kind,c.tags=kind,{}
    if c._tags then for t in c._tags:gmatch("[^,]+") do c.tags[t]=true end end
    e.components[#e.components+1]=c
    return c
end
local function all(e,kind,tag)
    local found={}
    for _,c in ipairs(e.components) do if c.kind==kind and (not tag or c.tags[tag]) then found[#found+1]=c end end
    return found
end
local function child(e,c) e.children[#e.children+1]=c;return c end
local function children(e,t)
    local matches={}
    for _,c in ipairs(e.children) do if not t or c.tags[t] then matches[#matches+1]=c end end
    return matches
end
local function del(e,c) for i,v in ipairs(e.components) do if v==c then table.remove(e.components,i);return end end end
local env=setmetatable({
    NHCompanions={active=function() return nil end},
    NHEW={enabled=function() return online end,ready=function() return ready end,issuer=function() return peer end,
        localBody=function(e) return e and not e.tags.ew_client end,
        walletAllowed=function() return not online end,rescueAllowed=function() return not online end},
    GlobalsSetValue=function(k,v) globals[k]=v end,GlobalsGetValue=function(k,v) return globals[k] or v end,
    GameGetFrameNum=function() return frame end,GamePlaySound=function(_,event) sounds[#sounds+1]=event end,
    EntityGetTransform=function(e) return e.x,e.y end,EntitySetTransform=function(e,x,y) e.x,e.y=x,y end,
    EntityAddTag=function(e,t) e.tags[t]=true end,EntityRemoveTag=function(e,t) e.tags[t]=nil end,
    EntityHasTag=function(e,t) return e.tags[t] end,EntityGetAllChildren=children,
    EntityAddChild=child,EntityAddComponent2=add,EntityRemoveComponent=del,
    EntityGetComponentIncludingDisabled=all,EntityGetFirstComponentIncludingDisabled=function(e,k,t) return all(e,k,t)[1] end,
    ComponentHasTag=function(c,t) return c.tags[t] end,ComponentAddTag=function(c,t) c.tags[t]=true end,
    ComponentRemoveTag=function(c,t) c.tags[t]=nil end,ComponentGetIsEnabled=function(c) return not c.disabled end,
    EntitySetComponentIsEnabled=function(_,c,on) c.disabled=not on end,
    ComponentGetValue2=function(c,k) return c[k] end,ComponentSetValue2=function(c,k,v) c[k]=v end,
    EntityLoad=function(file,x,y)
        fx[#fx+1]=file
        local e=entity(file,x,y)
        if file==root.."travel/transit_protection.xml" then
            add(e,"GameEffectComponent",{effect="PROTECTION_ALL",frames=30})
            add(e,"LifetimeComponent",{lifetime=32})
        end
        return e
    end,
    DoesWorldExistAt=function() return canLand end,RaytracePlatforms=function() return false end,
    GameGetGameEffect=function(e,k) return k=="POLYMORPH" and e.transform or 0 end,
},{__index=_G})
local p=entity("player",24,70)
local hp=add(p,"DamageModelComponent",{hp=3,max_hp=6})
local wallet=add(p,"WalletComponent",{money=810})
local native=add(child(p,entity("life")),"GameEffectComponent",{effect="RESPAWN",frames=-1,mIsSpent=false})
local shieldHits=0
env.GetUpdatedEntityID=function() return p end
env.dofile=function(file)
    if file==root.."rewind_loadout.lua" then
        return {
            capture=function(_,owner,token) gear.captured=gear.captured+1;gear.last,gear.owner=token,owner;return true end,
            restore=function(_,owner,token)
                assert(owner==gear.owner and token==gear.last)
                if not commitOK then return false end
                gear.restored=gear.restored+1
                return true
            end,
            cancel=function() gear.cancelled=gear.cancelled+1 end,
        }
    end
    if file==root.."shield_runtime.lua" then return {hit=function(_,damage) shieldHits=shieldHits+1;return damage end} end
    return setfenv(assert(loadfile(file)),env)()
end
local modules={}
env.dofile_once=function(file)
    if file==root.."companions.lua" or file==root.."affinity.lua" then return end
    if not modules[file] then modules[file]=env.dofile(file) end
    return modules[file]
end
local function runtime() return env.dofile(root.."rewind_watch.lua") end
local function hit(damage)
    local actual,crit=env.damage_about_to_be_received(damage,0,0,1,13)
    hp.hp=hp.hp-actual
    env.damage_received(actual)
    return actual,crit
end
env.dofile(root.."shield_damage.lua")
local W=runtime()
local function snap() return all(p,"VariableStorageComponent","nh_rewind_snapshot")[1] end

-- A gunshot which would kill the player, and every pellet on the same frame,
-- never reach HP, the equipped shield, extra lives, or the insurance wallet.
assert(W.start(state,p) and W.remaining(p)==3600 and not W.start(state,p))
assert(not native.disabled and not hp.wait_for_kill_flag_on_death and not snap().value_float)
-- A katana dash blocks ordinary damage before consuming the armed watch.
add(p,"VariableStorageComponent",{_tags="nh_katana_dash_guard",value_int=frame+6})
local dashHp=hp.hp
local dashHit,dashCrit=hit(2000)
assert(dashHit==0 and dashCrit==0 and hp.hp==dashHp and W.remaining(p)==3600 and shieldHits==0)
p.x,p.y=240,700
frame=3619
local v,crit=hit(0);assert(v==0 and crit==13 and W.remaining(p)==1)
v,crit=hit(-1);assert(v==-1 and crit==13 and hp.hp==4 and W.remaining(p)==1)
v,crit=hit(2000);assert(v==0 and crit==0 and W.remaining(p)==300)
assert(hit(2000)==0 and #sounds==1 and hp.hp==4 and shieldHits==0 and wallet.money==810)
assert(not native.disabled and not hp.wait_for_kill_flag_on_death and p.x==240)
frame=frame+240
W=runtime()
assert(hit(2)==0 and W.remaining(p)==60)
hp.hp=5 -- health gained or spent directly is independent of the watch
W.update(state,p);assert(p.x==240 and gear.restored==0)
frame=frame+60
commitOK=false
W.update(state,p)
assert(p.x==24 and p.y==70 and hp.hp==5 and gear.restored==0 and #sounds==2)
local count=#fx
p.x=33
W=runtime();W.update(state,p)
assert(not W.start(state,p) and #fx==count and p.x==33 and hp.hp==5)
commitOK=true
W.update(state,p);W.update(state,p)
assert(gear.restored==1 and not snap() and hit(1)==1 and shieldHits==1 and hp.hp==4)

-- Expiry cannot intercept another hit even if damage runs before world update.
frame=4050
assert(W.start(state,p))
p.x,p.y=900,-400
frame=frame+3600
assert(hit(1)==1)
W.update(state,p)
assert(p.x==900 and p.y==-400 and hp.hp==3 and gear.cancelled==1 and gear.restored==1 and #fx==count)

-- A destination streamed out between recording and return is rechecked; an
-- obstructed anchor resolves to nearby open space without replaying the flash.
frame=frame+1;assert(W.start(state,p));assert(hit(1)==0)
p.x,p.y=1000,90
canLand=false
frame=frame+300
W.update(state,p)
assert(p.x==900 and p.y==-400 and gear.restored==1)
canLand=true
env.RaytracePlatforms=function(x,y) return x==897 and y>=-402 and y<=-398 end
W=runtime();W.update(state,p)
assert(p.x==900 and p.y==-408 and gear.restored==2 and not snap())
env.RaytracePlatforms=function() return false end
frame=frame+1;assert(W.start(state,p));assert(hit(1)==0)
canLand=false;p.x,p.y=403,100
frame=frame+300;W.update(state,p)
frame=frame+120;W.update(state,p)
assert(p.x==403 and p.y==100 and gear.restored==3)
canLand=true

-- A transformation by itself cannot activate the watch. During the latched
-- guard the temporary body receives only the remaining time, then yields
-- back to its original body. No writes to HP or death ownership.
local sheep=entity("sheep");sheep.transform={frames=800}
local animalHp=add(sheep,"DamageModelComponent",{hp=1,max_hp=2})
frame=frame+1;assert(W.start(state,p));assert(not W.polymorph(sheep,state))
assert(hit(1)==0)
frame=frame+290
assert(W.polymorph(sheep,state) and W.polymorph(sheep,state))
assert(#sheep.children==1 and sheep.children[1].components[1].frames==10 and sheep.transform.frames==800)
frame=frame+10
assert(W.polymorph(sheep,state) and sheep.transform.frames==1)
assert(animalHp.hp==1 and not animalHp.wait_for_kill_flag_on_death)
W=runtime();W.update(state,p)
assert(gear.restored==4 and not snap())

local cancelled,last=gear.cancelled,globals["nh_rewind.last"]
assert(not W.start(state,p,function() return false end))
assert(not snap() and gear.cancelled==cancelled+1 and W.remaining(p)==0 and globals["nh_rewind.last"]==last)
online=true
globals["nh_ew.rewind_health"]="shared_health"
local captured=gear.captured
local ok,reason=W.start(state,p,function() error("charged a shared-health player") end)
assert(not ok and reason=="Shared health cannot be rewound." and gear.captured==captured)
globals["nh_ew.rewind_health"]="local_health";ready=false
assert(not W.start(state,p))
ready=true;p.tags.ew_client=true
assert(not W.start(state,p))
p.tags.ew_client=nil;frame=frame+1
peer=nil;assert(not W.start(state,p))
peer="Alice";assert(W.start(state,p));peer="Bob"
assert(not W.blockHit(p,25));W.update(state,p);assert(not snap())
frame=frame+1;peer="Alice"
assert(W.start(state,p))
assert(hit(25)==0 and not native.disabled)
globals["nh_ew.rewind_health"]="shared_health"
assert(not W.blockHit(p,25))
local restored=gear.restored
W.update(state,p);assert(not snap() and gear.restored==restored)

-- Loading an untriggered old watch cancels its old death ownership and
-- metadata, including a suspended extra life and the old EW damage hook.
online=false
local prior=add(p,"VariableStorageComponent",{_tags="nh_rewind_snapshot",name="1/7/8",value_int=200,value_float=1,
    value_string="12:13|100:300",value_bool=false})
p.tags.nh_rewind_armed=true
add(p,"VariableStorageComponent",{_tags="nh_rescue",value_string="",value_int=0,value_bool=true})
add(p,"LuaComponent",{_tags="nh_rewind_ew_priority"})
native.tags.nh_rewind_native_life,native.tags.nh_rescue_paused_life,native.disabled=true,true,true
hp.hp,hp.wait_for_kill_flag_on_death=2,true
globals["nh_rewind.clock"]=prior.name
assert(W.polymorph(sheep,state) and sheep.transform.frames==1)
W=runtime();W.update(state,p)
assert(not snap() and not p.tags.nh_rewind_armed and not hp.wait_for_kill_flag_on_death and hp.hp==2)
assert(not native.disabled and not native.tags.nh_rewind_native_life and not all(p,"LuaComponent","nh_rewind_ew_priority")[1])
assert(globals["nh_rewind.clock"]=="")
local old=add(p,"VariableStorageComponent",{_tags="nh_rewind_snapshot",name="1/7/9",value_int=200,value_float=1,
    value_string="12:13",value_bool=true})
gear.last=old.name
W=runtime();W.update(state,p)
assert(not snap() and gear.restored==restored+1 and hp.hp==2)

W=runtime();W.update(state,p)
local query=env.EntityGetFirstComponentIncludingDisabled
env.EntityGetFirstComponentIncludingDisabled=function() error("idle player queried components") end
for i=1,90 do frame=frame+1;W.update(state,p) end
env.EntityGetFirstComponentIncludingDisabled=query
print("Watch: first-hit veto, 60s expiry, 5s guard, safe return, reload/retry, legacy migration and EW passed.")
