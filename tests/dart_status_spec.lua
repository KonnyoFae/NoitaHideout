local files="mods/noita_hideout/files/"
local now=100
local function entity(tag)
    return {tags={[tag]=true},children={},components={}}
end
function EntityAddComponent2(e,kind,c)
    c.kind=kind; e.components[#e.components+1]=c
    return c
end
function EntityGetFirstComponentIncludingDisabled(e,kind,...)
    local tag=...
    assert(select("#",...)==0 or type(tag)=="string","Noita rejects explicit nil tags")
    for _,c in ipairs(e.components) do
        if c.kind==kind and (not tag or c._tags==tag) then return c end
    end
end
function EntityRemoveComponent(e,c)
    for i,other in ipairs(e.components) do if other==c then table.remove(e.components,i);return end end
end
function EntityGetAllChildren(e,tag)
    local matches={}
    for _,child in ipairs(e.children) do
        if not child.dead and (not tag or child.tags[tag]) then matches[#matches+1]=child end
    end
    return matches
end
function EntityRemoveTag(e,tag) e.tags[tag]=nil end
function EntityAddChild(e,child) e.children[#e.children+1]=child end
function EntityKill(e) e.dead=true end
function EntityGetIsAlive(e) return not e.dead end
function EntityGetTransform() return 10,20 end
function EntitySetTransform(e,x,y,rotation) e.x,e.y,e.rotation=x,y,rotation end
function EntityRefreshSprite(e,c) assert(c.kind=="SpriteComponent") end
function ComponentGetValue2(c,key) return c[key] end
function ComponentSetValue2(c,key,v,...)
    if key=="Transform" then c[key]={v,...} else c[key]=v end
end
function GameGetFrameNum() return now end
function EntityLoad(path)
    local kind=assert(path:match("/dart_(%a+)"))
    local e=entity("nh_dart_"..kind)
    EntityAddComponent2(e,"LifetimeComponent",{})
    if kind=="needle" then
        EntityAddComponent2(e,"SpriteComponent",{})
        EntityAddComponent2(e,"InheritTransformComponent",{})
    else
        EntityAddComponent2(e,"GameEffectComponent",{})
        EntityAddComponent2(e,"VariableStorageComponent",{_tags="nh_dart_clock"})
    end
    return e
end
local function child(e,kind) return EntityGetAllChildren(e,"nh_dart_"..kind)[1] end
local function life(e) return EntityGetFirstComponentIncludingDisabled(e,"LifetimeComponent").kill_frame end
local function hook(e) return EntityGetFirstComponentIncludingDisabled(e,"LuaComponent","nh_dart_wake") end
local D=dofile(files.."dart_status.lua")
local mob=entity("enemy")
local dm=EntityAddComponent2(mob,"DamageModelComponent",{hp=1})
local nativeCharm=entity("external_charm")
EntityAddChild(mob,nativeCharm)
assert(D.attach(mob,"sedative",14,22,0.25) and D.attach(mob,"pheromone"))
local sed,charm=child(mob,"sedative"),child(mob,"pheromone")
local needle=child(sed,"needle")
local mount=EntityGetFirstComponentIncludingDisabled(needle,"InheritTransformComponent").Transform
assert(needle.x==14 and needle.y==22 and needle.rotation==0.25)
assert(mount[1]==4 and mount[2]==2 and mount[3]==1 and mount[4]==1 and mount[5]==0.25)
for _,kind in ipairs({"sedative","pheromone"}) do
    local attached=child(child(mob,kind),"needle")
    assert(EntityGetFirstComponentIncludingDisabled(attached,"SpriteComponent").image_file==files.."projectiles/"..kind.."_needle.png")
end
assert(life(needle)==1000 and life(sed)==19000 and life(charm)==4600 and hook(mob))
now=999
D.damaged(mob,1)
assert(D.has(mob,"sedative") and D.has(mob,"pheromone"))
now=1000
D.damaged(mob,0);D.damaged(mob,-1)
assert(D.has(mob,"sedative"))
D=dofile(files.."dart_status.lua") -- VM reload; all timing comes from the host and its children.
D.damaged(mob,0.01)
assert(not D.has(mob,"sedative") and not hook(mob) and D.has(mob,"pheromone") and not nativeCharm.dead)
assert(dm.hp==1)
now=4599; assert(D.has(mob,"pheromone"))
now=4600; assert(not D.has(mob,"pheromone") and D.attach(mob,"pheromone"))
assert(charm.dead and child(mob,"pheromone")~=charm and not nativeCharm.dead)
assert(D.attach(mob,"sedative"))
sed=child(mob,"sedative")
needle=child(sed,"needle")
now=4800;assert(D.attach(mob,"sedative"))
assert(child(mob,"sedative")==sed and child(sed,"needle")==needle and life(needle)==5700)
now=5700;assert(D.attach(mob,"sedative"))
assert(needle.dead and child(sed,"needle")~=needle and life(sed)==24600)
assert(#EntityGetAllChildren(mob,"nh_dart_sedative")==1)
now=24599;assert(D.has(mob,"sedative"))
now=24600;assert(not D.has(mob,"sedative"))
D.cleanup(mob);assert(not hook(mob))
dm.hp=0;assert(not D.attach(mob,"sedative"))
local ally=entity("enemy")
EntityAddComponent2(ally,"DamageModelComponent",{hp=1})
assert(D.attach(ally,"pheromone") and not hook(ally))
now=now+D.attachedFrames
D.damaged(ally,1);assert(D.has(ally,"pheromone"))

local function text(path)
    local f=assert(io.open(path,"rb")); local s=f:read("*all"); f:close(); return s
end
local sedXml=text(files.."projectiles/dart_sedative_effect.xml")
assert(sedXml:find('effect="CUSTOM"',1,true) and sedXml:find('disable_movement="1"',1,true))
local charmXml=text(files.."projectiles/dart_pheromone_effect.xml")
assert(charmXml:find('effect="CHARM"',1,true))
for _,xml in ipairs({sedXml,charmXml,text(files.."projectiles/dart_needle.xml")}) do
    assert(xml:find('serialize_duration="1"',1,true))
end
print("Smart darts: 15 s attachment, 300 s interruptible sedation, 60 s uninterruptible charm, refresh and external charm isolation passed.")
