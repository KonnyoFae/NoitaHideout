local root="mods/noita_hideout/files/"
dofile(root.."store.lua")
local mockFrame, queries=0,0
local entities, loaded={},{}

function dofile_once(path)
    if loaded[path]==nil then loaded[path]=dofile(path) or true end
    return loaded[path]
end

local function entity(tags,parent)
    local id=#entities+1
    local e={children={},components={},tags={}}
    entities[id]=e
    for tag in (tags or ""):gmatch("[^,]+") do e.tags[tag]=true end
    if parent then table.insert(entities[parent].children,id) end
    return id
end
local function component(id,kind,tag,fields)
    local c=fields or {}
    c.kind,c.tag=kind,tag
    table.insert(entities[id].components,c)
    return c
end
function GameGetFrameNum() return mockFrame end
function GlobalsGetValue(_,default) return default end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityHasTag(id,tag)
    queries=queries+1
    return entities[id].tags[tag] or false
end
function EntityGetTags(id)
    local tags={}
    for tag in pairs(entities[id].tags) do tags[#tags+1]=tag end
    return table.concat(tags,",")
end
function GameTextGetTranslatedOrNot(name) return name end
function EntityGetAllChildren(id,tag)
    queries=queries+1
    local result={}
    for _,child in ipairs(entities[id].children) do
        if not tag or entities[child].tags[tag] then result[#result+1]=child end
    end
    return #result>0 and result or nil
end
function EntityGetComponentIncludingDisabled(id,kind,tag)
    queries=queries+1
    local result={}
    for _,c in ipairs(entities[id].components) do
        if c.kind==kind and (not tag or tag==c.tag) then result[#result+1]=c end
    end
    return #result>0 and result or nil
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    return (EntityGetComponentIncludingDisabled(id,kind,tag) or {})[1]
end
EntityGetFirstComponent=EntityGetFirstComponentIncludingDisabled
function ComponentGetValue2(c,key) return c[key] end

NHSalvageBell=dofile(root.."salvage_bell.lua")
NHRewind=dofile(root.."rewind_watch.lua")
local collect=dofile(root.."storm/effects.lua")
local radarUntil=0
local locations={remaining=function(frame) return math.max(0,radarUntil-frame) end}
local function sample(id,frame,lang)
    mockFrame=frame
    return collect(id,lang or "en",frame,locations)
end
local function byIcon(rows)
    local result={}
    for _,r in ipairs(rows) do
        assert(type(r.icon)=="string" and #r.icon>0 and type(r.label)=="string" and #r.label>0 and r.frames>0)
        assert(not result[r.icon],"duplicate status icon "..r.icon)
        result[r.icon]=r
    end
    return result
end
local function frames(rows,icon,expected)
    local row=assert(rows[root.."items/"..icon..".png"],"missing "..icon)
    assert(row.frames==expected,icon..": expected "..expected.." frames, got "..tostring(row.frames))
    return row.label
end

local idle=entity("player_unit")
assert(#sample(idle,100)==0)
local first=queries
assert(first>0)
for frame=101,114 do assert(#sample(idle,frame)==0) end
assert(queries==first,"empty HUD scanned the player before 15 frames")
assert(#sample(idle,115)==0 and queries>first)

local player=entity("player_unit")
local timed={"tarot_hermit","tarot_chariot","tarot_sun","tarot_moon","tarot_magician","tarot_devil"}
local clocks={}
for i,id in ipairs(timed) do
    clocks[i]=component(player,"VariableStorageComponent","nh_"..id,{value_int=200+i,value_float=110})
end
-- Neither permanent tarot produces a timer, even if a stale clock is present.
for _,id in ipairs({"tarot_garden","tarot_tower"}) do
    component(player,"VariableStorageComponent","nh_"..id,{value_int=2000,value_float=110})
end
local function tarotAt(frame,offset)
    local rows=sample(player,frame)
    assert(#rows==6)
    rows=byIcon(rows)
    for i,id in ipairs(timed) do
        assert(frames(rows,"card_"..id,200+i-offset):find(NHTarot.types[id].en,1,true))
    end
end
tarotAt(115,5)
tarotAt(116,6)

local dog=entity("noita_hideout_companion",player)
component(dog,"VariableStorageComponent","nh_companion_clock",{value_int=1423,value_string="dog"})
local firstPet=byIcon(sample(player,130,"zh"))
assert(frames(firstPet,"card_dog",15*60*60-1423)==NHCompanions.species.dog.zh)
assert(frames(firstPet,"card_tarot_sun",183)==NHTarot.types.tarot_sun.zh)
entities[player].children={}
local dryad=entity("noita_hideout_companion",player)
component(dryad,"VariableStorageComponent","nh_companion_clock",{value_int=42,value_string="dryad"})
local nextPet=byIcon(sample(player,145,"zh"))
assert(not nextPet[NHCompanions.cardIcon("dog")])
frames(nextPet,"card_dryad",15*60*60-42)

-- Local relics and the radar use absolute simulation-frame deadlines.
local owner=entity("player_unit,nh_rewind_armed,nh_reactor_active")
component(owner,"VariableStorageComponent","nh_salvage_bell",{value_int=904})
component(owner,"VariableStorageComponent","nh_rewind_snapshot",{value_int=905})
component(owner,"VariableStorageComponent","nh_hourglass_cast",{value_int=906})
component(owner,"VariableStorageComponent","nh_reactor_active",{value_int=908})
local duster=entity("nh_duster_field",owner)
component(duster,"VariableStorageComponent","nh_duster_until",{value_int=907})
radarUntil=909
local relicOrder={"salvage_bell","rewind_watch","stasis_hourglass","dustless_duster","mana_reactor"}
local relics=sample(owner,900)
assert(#relics==6)
local indexed=byIcon(relics)
for i,name in ipairs(relicOrder) do frames(indexed,name,i+3) end
frames(indexed,"remote_terminal",9)
assert(#sample(owner,909)==0)
-- All six rows expired since the sample at 900. Rewinding within the same
-- 15-frame window must reconstruct the rows, even with the same owner ID.
local rewound=byIcon(sample(owner,902))
for i,name in ipairs(relicOrder) do frames(rewound,name,i+1) end
radarUntil=0
assert(#sample(nil,903)==0)
assert(#sample(idle,903)==0)

local patient=entity("player_unit")
local rage=entity("noita_hideout_stimulant_rage",patient)
component(rage,"GameEffectComponent",nil,{frames=75})
local quick=entity("noita_hideout_stimulant_quick_heal",patient)
local pulses=component(quick,"VariableStorageComponent",nil,{value_int=4})
local last=component(quick,"LuaComponent",nil,{mLastExecutionFrame=896})
local meal=entity("noita_hideout_meal_spice",patient)
component(meal,"VariableStorageComponent",nil,{value_int=3})
component(meal,"LuaComponent",nil,{mLastExecutionFrame=885})
component(meal,"UIIconComponent",nil,{icon_sprite_file=root.."items/steak.png",name="$nh_hideout_meal_spice"})
local duplicate=entity("foreign_stimulant_rage",patient)
component(duplicate,"GameEffectComponent",nil,{frames=5000})
local radar=entity("nh_enemy_radar",patient)
component(radar,"LifetimeComponent",nil,{kill_frame=915})
local medicine=sample(patient,900)
assert(#medicine==4)
indexed=byIcon(medicine)
frames(indexed,"dose_rage",75)
frames(indexed,"dose_quick_heal",4*12-4)
frames(indexed,"steak",3*60-15)
assert(indexed["data/ui_gfx/perk_icons/radar_enemy.png"].frames==15)
pulses.value_int,last.mLastExecutionFrame=25,913
local refreshed=byIcon(sample(patient,915))
frames(refreshed,"dose_quick_heal",25*12-2)
assert(not refreshed["data/ui_gfx/perk_icons/radar_enemy.png"])

clocks[1].value_int,clocks[1].value_float=108000,927
local restored=byIcon(sample(player,930))
frames(restored,"card_tarot_hermit",107997)
assert(not restored[root.."items/card_tarot_sun.png"] and not restored[root.."items/dose_quick_heal.png"])
print("Storm HUD timers: six timed cards, companions, relics, radar, injectors and meals; expiry, refresh, owner change, rewind and idle sampling passed.")
