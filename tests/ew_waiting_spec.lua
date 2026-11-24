local dir="mods/noita_hideout/files/"
local globals,flags,stored,trace={},{},{},{}
local carryingNotice="$nh_hideout_ew_wait_carrying_peer"
local notices={}
local ctx={my_player={status={}},proxy_opt={game_mode="local_health"},cap={health={}}}
local function entity(name)
    return {name=name,children={},tags={},components={},alive=true,x=120,y=-38}
end
local function attach(p,e) p.children[#p.children+1]=e;e.parent=p end
local function detach(e)
    if not e.parent then return end
    for i,c in ipairs(e.parent.children) do if c==e then table.remove(e.parent.children,i);break end end
    e.parent=nil
end
local function kill(e)
    detach(e);e.alive=false
    while #e.children>0 do kill(e.children[1]) end
end
local function copy(e)
    local o=entity(e.name);o.x,o.y=e.x,e.y
    for k,v in pairs(e.tags) do o.tags[k]=v end
    for k,c in pairs(e.components) do
        o.components[k]={}
        for f,v in pairs(c) do o.components[k][f]=v end
    end
    for _,child in ipairs(e.children) do attach(o,copy(child)) end
    return o
end
local function player(gear)
    local p=entity("DEBUG_NAME:player")
    p.components={WalletComponent={money=53},DamageModelComponent={hp=0.4,max_hp=12},Inventory2Component={}}
    local quick,full=entity("inventory_quick"),entity("inventory_full");attach(p,quick);attach(p,full)
    if gear then attach(quick,entity("wand:mana=12"));attach(quick,entity("potion:water=309")) end
    attach(full,entity("spell"));return p
end
local function gear(p)
    local names={}
    for _,pocket in ipairs(p.children) do for _,i in ipairs(pocket.children) do names[#names+1]=i.name end end
    return table.concat(names,",")
end
local failLoad,failSave,failSerialize
local poly={switch_entity=function(e) assert(ctx.my_player.entity==e);trace[#trace+1]=e.name end}
local cos={player_color=function() trace[#trace+1]="color" end,player_cosmetics=function() trace[#trace+1]="vanity" end}
local env=setmetatable({ctx=ctx,
    dofile_once=function(path)
        if path:find("base64",1,true) then return {encode=function(s) return s end,decode=function(s) return s end} end
        if path:find("player_cosmetics",1,true) then return cos end
        if path:find("system/damage/damage.lua",1,true) then return {on_local_player_spawn=function(p)
            assert(not p.entity.components.ew_player_damage);p.entity.components.ew_player_damage={shared=true}
        end} end
        return poly
    end,
    util={serialize_entity=function(e)
        if failSerialize then error("bad serialization") end
        stored[#stored+1]=copy(e);return tostring(#stored)
    end,deserialize_entity=function(text) return copy(assert(stored[tonumber(text)])) end},
    np={SetPlayerEntity=function() end,SetActiveHeldEntity=function() end},
    EntityGetAllChildren=function(e) local t={};for i,c in ipairs(e.children) do t[i]=c end;return t end,
    EntityGetName=function(e) return e.name end,EntityGetFilename=function(e) return e.filename or "" end,
    EntityGetIsAlive=function(e) return type(e)=="table" and e.alive end,
    EntityRemoveFromParent=detach,EntityAddChild=attach,EntityKill=kill,
    EntityGetParent=function(e) return e.parent end,EntityHasTag=function(e,t) return e.tags[t] end,
    EntityRemoveComponent=function(e,c) for k,v in pairs(e.components) do if v==c then e.components[k]=nil;return end end end,
    EntityGetTransform=function(e) return e.x,e.y end,
    EntityGetFirstComponentIncludingDisabled=function(e,t,...)
        local tag=...
        assert(select("#",...)==0 or type(tag)=="string","Noita rejects an explicit nil third argument")
        return e.components[tag or t]
    end,
    EntityAddComponent2=function(e,t,c) e.components[c._tags or t]=c;return c end,
    ComponentSetValue2=function(c,k,v) c[k]=v end,ComponentGetValue2=function(c,k) return c[k] end,
    GlobalsGetValue=function(k,d) return globals[k] or d end,
    GlobalsSetValue=function(k,v) if not failSave then globals[k]=v end end,
    EntityRemoveTag=function(e,t) e.tags[t]=nil end,EntityAddTag=function(e,t) e.tags[t]=true end,
    EntitySetComponentIsEnabled=function(_,c,v) c.active=v end,
    GameHasFlagRun=function(k) return flags[k] end,GameAddFlagRun=function(k) flags[k]=true end,
    GameRemoveFlagRun=function(k) flags[k]=nil end,inventory_helper={setup_inventory=function() end},
    GamePrint=function(s) notices[#notices+1]=s end,GameTextGet=function(k) return k end,
    EntityLoad=function(file,x,y)
        assert(file==dir.."entities/ew_waiting.xml")
        if failLoad then return 0 end
        local e=entity("observer");e.x,e.y=x,y;e.tags={nh_ew_waiting=true,ew_notplayer=true}
        e.components={WalletComponent={money=0},ControlsComponent={}};return e
    end},{__index=_G})
local W=setfenv(assert(loadfile(dir.."ew_waiting.lua")),env)()
local p=player(true);ctx.my_player.entity=p
local before=gear(p)
local foreign=entity("carried mimic teammate");foreign.tags={ew_client=true,polymorphed_player=true}
attach(p.children[1],foreign)
local entered,reason=W.enter(p)
assert(not entered and reason==carryingNotice and ctx.my_player.entity==p and p.alive and foreign.alive and foreign.parent==p.children[1] and #stored==0)
detach(foreign)
for _,failure in ipairs({"load","write","serialize"}) do
    failLoad,failSave,failSerialize=(failure=="load"),(failure=="write"),(failure=="serialize")
    entered,reason=W.enter(p)
    assert(not entered and reason==nil and p.alive and gear(p)==before and ctx.my_player.entity==p)
end
failLoad,failSave,failSerialize=false,false,false
assert(W.enter(p));local a=ctx.my_player.entity
assert(not p.alive and W.isAnchor(a) and gear(a)=="" and a.components.WalletComponent.money==53)
local function checkSpawn(e)
    ctx.my_player.entity=e;flags.ew_flag_notplayer_active=true
    W.onSpawn({entity=e})
    if flags.ew_flag_notplayer_active then trace[#trace+1]="dont rejoin"
    else cos.player_cosmetics(e);cos.player_color(e) end
    e.tags.homing_target=true;local c=e.components.ControlsComponent
    if c then c.enabled=true end
    env.inventory_helper.setup_inventory()
end
env.OnPlayerSpawned=checkSpawn;W.installSpawnGuard()
trace={};env.OnPlayerSpawned(a)
assert(#trace==0 and flags.ew_flag_notplayer_active and not a.tags.homing_target and a.components.ControlsComponent.enabled==false)
checkSpawn(a) -- works even when the engine cached the unwrapped callback
assert(#trace==0 and flags.ew_flag_notplayer_active)
a.components.WalletComponent.money=75
assert(W.restore(a,true));local back=ctx.my_player.entity
assert(not a.alive and gear(back)==before and back.components.DamageModelComponent.hp==12)
assert(back.components.WalletComponent.money==75 and globals.ew_local_player_dead=="" and not W.restore(a,true))
-- v0.42.24 serialized the real body's full slots and kept the quick slots
-- on its substitute. Reloaded entities may have an empty runtime filename.
local original=player(false)
globals.ew_local_player_dead=env.util.serialize_entity(original)
local old=player(true);old.tags.ew_notplayer=true;old.components.WalletComponent.money=97
old.components.nh_ew_reinforce_episode={value_string="room|peer|7",value_bool=true}
ctx.my_player.entity=old
env.OnPlayerSpawned(old);assert(W.pendingLegacy(old) and old.tags.nh_ew_wait_upgrade)
failSerialize=true;assert(not W.upgrade(old) and gear(old)==before and old.alive)
failSerialize=false;assert(W.upgrade(old));local upgraded=ctx.my_player.entity
assert(not old.alive and gear(upgraded)=="" and upgraded.components.nh_ew_reinforce_episode.value_string=="room|peer|7")
assert(W.restore(upgraded,true) and gear(ctx.my_player.entity)==before and ctx.my_player.entity.components.WalletComponent.money==97)
-- A real teammate carried by an old substitute also keeps its live identity.
local legacyCarrier=player(true);legacyCarrier.tags.ew_notplayer=true
legacyCarrier.components.nh_ew_reinforce_episode={value_string="room|peer|8"}
globals.ew_local_player_dead=env.util.serialize_entity(player(false));ctx.my_player.entity=legacyCarrier
attach(legacyCarrier.children[1],foreign)
local saved=#stored
local recovered,why=W.upgrade(legacyCarrier)
assert(recovered and why==carryingNotice and #notices==1 and notices[1]==carryingNotice)
assert(#stored==saved and not W.isAnchor(ctx.my_player.entity))
assert(not legacyCarrier.alive and foreign.alive and foreign.parent==ctx.my_player.entity.children[1])
-- An unrelated EW downed form continues into the native rejoin path.
local outside=entity("statue");outside.tags.ew_notplayer=true
trace={};env.OnPlayerSpawned(outside);assert(trace[1]=="dont rejoin")
local localPlayer=player(true)
localPlayer.components.ew_player_damage={script_damage_received="mods/quant.ew/files/system/local_health/grab_damage_message.lua"}
ctx.my_player.entity=localPlayer;assert(W.enter(localPlayer))
ctx.proxy_opt.game_mode="shared_health";ctx.cap.health.health=function() return 2.5 end
assert(W.restore(ctx.my_player.entity,false))
assert(gear(ctx.my_player.entity)==before and ctx.my_player.entity.components.DamageModelComponent.hp==2.5)
assert(ctx.my_player.entity.components.ew_player_damage.shared)
print("EW waiting: intact escrow, empty observer, scoped resume, shared wallet, legacy migration and one-time restore passed.")
