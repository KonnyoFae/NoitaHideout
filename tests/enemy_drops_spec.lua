-- Probabilities are fractions per eligible death; HP in this table is displayed HP.
local expected={
    {1,         .95,.05,0,0,       .002,.0000375},
    {5,         .75,.25,0,0,       .008*math.log10(5)^2,.0003*math.log10(5)^3},
    {10,        .50,.50,0,0,       .008,.0003},
    {10^1.12,   .38,.50,.12,0,     .008*1.12^2,.0003*1.12^3},
    {10^1.25,   .25,.50,.25,0,     .0125,.0005859375},
    {10^1.5,    0,.50,.50,0,       .018,.0010125},
    {10^1.75,   0,.25,.50,.25,     .0245,.0016078125},
    {100,       0,0,.50,.50,       .032,.0024},
    {1000,      0,0,.50,.50,       .072,.0081},
    {10^12,     0,0,.50,.50,       1,.5184},
    {10^16,     0,0,.50,.50,       1,1},
}
local function near(actual,want,message)
    assert(type(actual)=="number" and math.abs(actual-want)<1e-9,
        ("%s: expected %.10f, got %s"):format(message,want,tostring(actual)))
end

local root="mods/noita_hideout/files/"
local modules,loaded={},{}
function dofile_once(path)
    if not loaded[path] then loaded[path]=true; modules[path]=dofile(path) end
    return modules[path]
end
local drops=dofile_once(root.."enemy_drops.lua")
local tarot=dofile_once(root.."tarot.lua")
local released={}
for _,red in ipairs(drops.redPool) do released[red.id]=true end
assert(released.salvage_bell and released.rewind_watch and released.stasis_hourglass and released.dustless_duster and released.mana_reactor and released.dragon_king,
    "all finished collectibles and the Dragon King katana are available for enemy loot")
local pool={"tarot_garden","tarot_hermit","tarot_chariot","tarot_tower","tarot_sun","tarot_moon","tarot_magician","tarot_devil"}
assert(#tarot.order==#pool)
for i,kind in ipairs(pool) do
    assert(tarot.dropFile(function(size) assert(size==#pool); return i end)==root.."items/card_"..kind..".xml")
end

for _,case in ipairs(expected) do
    local maxHp=case[1]/25
    local counts={empty=0,travel_satchel=0,travel_pack=0,loot_case=0}
    for i=1,200 do
        local bag=drops.roll(maxHp,false,function(lane)
            assert(lane==1,"bonus rolls on an ordinary-bag-only death")
            return (i-.5)/200
        end)
        local key=bag or "empty"
        counts[key]=counts[key]+1
    end
    for i,kind in ipairs({"empty","travel_satchel","travel_pack","loot_case"}) do
        near(counts[kind]/200,case[i+1],kind.." at "..case[1].." HP")
    end
    for lane=2,3 do
        local chance=case[lane+4]
        local function hit(sample)
            local _,card,red=drops.roll(maxHp,true,function(n) return n==lane and sample or .99 end)
            if lane==2 then return card end
            return red
        end
        assert(hit(chance-1e-10),"miss below the bonus probability")
        if chance<1 then assert(not hit(chance+1e-10),"hit above the bonus probability") end
    end
end

local mob,frame=37,9876
local killCredits,rewards={},{}
loaded[root.."tarot_vitality.lua"]=true
modules[root.."tarot_vitality.lua"]={killOwner=function(id)
    killCredits[#killCredits+1]=id
    if id==55 or id==56 then return id end
end,rewardKill=function(id) rewards[id]=(rewards[id] or 0)+1 end}
loaded[root.."loot_bonuses.lua"]=true
modules[root.."loot_bonuses.lua"]={rerolls=function(player,event)
    assert(event=="enemy_kill")
    if player==55 then return {bag=0.25,tarot=0.25,red=0.25} end
end}
local hp,tags,spawned,draws,used,vars
local ewEnabled=false
function ModIsEnabled(id) assert(id=="quant.ew"); return ewEnabled end
function GetUpdatedEntityID() return mob end
function GameGetFrameNum() return frame end
function EntityGetTransform(id) assert(id==mob); return 67,123 end
function EntityHasTag(id,tag) assert(id==mob); return tags[tag]==true end
function EntityAddTag(id,tag) assert(id==mob); tags[tag]=true end
function EntityGetComponentIncludingDisabled(id,kind)
    assert(id==mob and kind=="VariableStorageComponent")
    return vars
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    assert(id==mob)
    if kind=="VariableStorageComponent" then
        for _,c in ipairs(vars) do if c.tag==tag then return c end end
        return
    end
    assert(kind=="DamageModelComponent")
    if hp~=nil then return 42 end
end
function ComponentGetValue2(component,key)
    if type(component)=="table" then return component[key] end
    assert(component==42 and key=="max_hp")
    return hp
end
function ComponentGetTags(c) return c.tag or "" end
function EntityLoad(path,x,y)
    spawned[#spawned+1]={path=path,x=x,y=y}
    return 100+#spawned
end
function ProceduralRandomi(x,y,lo,hi)
    assert(x==67+mob and lo==1)
    local lane=(y-123-frame)/7919
    local value=draws[lane]
    assert(value and value>=lo and value<=hi,"unexpected draw on lane "..lane)
    if lane<=3 then assert(hi==10000000) end
    assert(not used[lane],"repeated random seed "..lane)
    used[lane]=true
    return value
end
local function reset(displayHP,initialTags,rolls)
    hp=displayHP and displayHP/25
    tags,spawned=initialTags or {},{}
    draws,used=rolls or {},{}
    vars={}
end
dofile(root.."enemy_loot.lua")
local function expectedItems(paths)
    assert(#spawned==#paths)
    local remaining={}
    for _,p in ipairs(paths) do remaining[p]=true end
    for _,drop in ipairs(spawned) do
        assert(remaining[drop.path],drop.path)
        remaining[drop.path]=nil
    end
    assert(not next(remaining))
end
local satchel=root.."items/travel_satchel.xml"
local pack=root.."items/travel_pack.xml"
local card=root.."items/card_tarot_devil.xml"
local bonus="mods/test_only/items/red.xml"
local function bagDraw(displayHP,wanted)
    for i=1,100 do
        local n=50000+(i-1)*100000
        if drops.roll(displayHP/25,false,function() return (n-1)/10000000 end)==wanted then return n end
    end
    error("impossible test bag")
end
for _,tag in ipairs({"player_unit","polymorphed_player","ew_peer","ew_client","ew_notplayer","nh_reinforcement","nh_loot_paid","ew_des"}) do
    reset(100,{[tag]=true})
    death(0,"",1,true)
    expectedItems({})
end
reset(100)
death(0,"",1,false)
expectedItems({})
for _,h in ipairs({0,-2,math.huge,0/0}) do
    reset(h)
    death(0,"",0,true)
    expectedItems({})
end
reset(nil)
death(0,"",0,true)
expectedItems({satchel})
assert(spawned[1].x==67 and spawned[1].y==120)

-- No ordinary bag is needed for a bonus. While the red pool is empty, a hit cannot load an entity.
local releasePool=drops.redPool
drops.redPool={}
local miss=bagDraw(1,nil)
reset(1,{}, {miss,1,1,#pool})
death(0,"environment",0,true)
expectedItems({card})
drops.redPool[1]={id="fixture",file=bonus,item={kind="native_valuable",variant="beamstone"}}
for _,case in ipairs({
    {1,1,{card,bonus}}, {20001,1,{bonus}}, {1,376,{card}}, {20001,376,{}}
}) do
    reset(1,{}, {miss,case[1],case[2],#pool,1})
    death(0,"environment",0,true)
    expectedItems(case[3])
    assert(used[1] and used[2] and used[3])
    death(0,"same enemy reported twice",1,true)
    expectedItems(case[3])
end
local packDraw=bagDraw(100,"travel_pack")
-- A credited player with the bell can improve each result once. The floor
-- stays at the original result. Each category uses its own 25% gate.
local caseFile=root.."items/loot_case.xml"
local upgrade={packDraw,10000000,10000000,#pool,1,1,1,1,1,1,1}
reset(100,{},upgrade)
death(0,"player with active bell",55,true)
expectedItems({caseFile,card,bonus})
death(0,"duplicate credited kill",55,true)
assert(rewards[55]==1)
for _,other in ipairs({0,56,91}) do
    reset(100,{},upgrade)
    death(0,"environment, expired bell or another player's kill",other,true)
    expectedItems({pack})
    assert(not used[6] and not used[8] and not used[10])
end
for _,c in ipairs({{6,{pack,card,bonus}},{8,{caseFile,bonus}},{10,{caseFile,card}}}) do
    local lanes={unpack(upgrade)}
    lanes[c[1]]=2500001
    reset(100,{},lanes)
    death(0,"one gate misses",55,true)
    expectedItems(c[2])
end
reset(100,{}, {packDraw,1,1,#pool,1,1,10000000})
death(0,"successes are retained",55,true)
expectedItems({pack,card,bonus})
reset(1,{}, {miss,10000000,10000000,1,1,2500000,1,2500001,1,2500001,1})
death(0,"missed bag receives one extra chance",55,true)
expectedItems({satchel})
reset(100,{nh_no_rare_drop=true},{packDraw})
death(0,"bell cannot amplify summoned loot",55,true)
expectedItems({pack})
reset(100,{}, {packDraw,1,1,#pool,1})
death(0,"player shot",1,true)
expectedItems({pack,card,bonus})
for _,tag in ipairs({"nh_decoy","summon_player","nh_no_rare_drop"}) do
    reset(100,{[tag]=true},{packDraw})
    death(0,"deployed or summoned target destroyed",1,true)
    expectedItems({pack})
    assert(not used[2] and not used[3])
end
reset(100,{}, {packDraw})
vars={{tag="no_gold_drop",name=""}}
death(0,"vanilla non-gold drop",0,true)
expectedItems({pack})
assert(not used[2] and not used[3])
reset(100,{}, {packDraw,1,1,#pool,1})
vars={{name="no_gold_drop"}}
death(0,"ordinary enemy killed by another enemy",91,true)
expectedItems({pack,card,bonus})

-- EW's numeric GID is stored as a string on an untagged variable; ownership belongs to the entity's simulator.
ewEnabled=true
local function gid(owned)
    return {name="ew_gid_lid",value_string="18446744073709551615",value_bool=owned}
end
for _,tracked in ipairs({false,true}) do
    reset(100,{ew_des=tracked})
    vars={gid(false)}
    death(0,"remote entity",0,true)
    expectedItems({})
    assert(not tags.nh_loot_paid)
    reset(100,{ew_des=tracked})
    vars={gid(nil)}
    death(0,"unknown owner",0,true)
    expectedItems({})
    reset(100,{ew_des=tracked},{packDraw,1,1,#pool,1})
    vars={gid(true)}
    death(0,"entity simulated by the local client",91,true)
    expectedItems({pack,card,bonus})
    death(0,"replicated duplicate",0,true)
    expectedItems({pack,card,bonus})
end
reset(100,{ew_des=true})
death(0,"tracked without a GID",0,true)
expectedItems({})
reset(100)
vars={gid(true),gid(true)}
death(0,"ambiguous identity",0,true)
expectedItems({})
reset(100,{}, {packDraw,1,1,#pool,1})
local creditsBefore=#killCredits
death(0,"untracked local enemy",91,true)
expectedItems({pack,card,bonus})
death(0,"duplicate callback",91,true)
assert(#killCredits==creditsBefore+1 and killCredits[#killCredits]==91)
drops.redPool=releasePool
print("Bag weights, independent bonus drops, environmental kills, summon restrictions, repeat callbacks and EW entity ownership passed.")
