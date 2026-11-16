local tag="noita_hideout_home_wand_edit"
local path="mods/noita_hideout/files/home_wand_edit.xml"
local file=assert(io.open(path,"rb"))
local xml=file:read("*a")
file:close()
local duration=assert(tonumber(xml:match('<GameEffectComponent%s+effect="EDIT_WANDS_EVERYWHERE"%s+frames="(%d+)"')))
assert(xml:find('tags="'..tag..'"',1,true) and duration>1 and duration<10)

local entities,next_id={},0
local function entity(tags,parent,frames)
    next_id=next_id+1
    entities[next_id]={tags=tags or {},parent=parent or 0,effect=frames and {frames=frames} or nil}
    return next_id
end
function EntityGetIsAlive(id) return entities[id]~=nil end
local scans=0
function EntityGetAllChildren(parent,filter)
    scans=scans+1
    local children={}
    for id,e in pairs(entities) do
        if e.parent==parent and (not filter or e.tags[filter]) then children[#children+1]=id end
    end
    return children
end
function EntityHasTag(id,key) return entities[id].tags[key]==true end
function EntityGetFirstComponentIncludingDisabled(id,kind)
    assert(kind=="GameEffectComponent")
    return entities[id].effect
end
function ComponentSetValue2(c,key,value) c[key]=value end
function EntityGetTransform() return 227,-85 end
local block_load=false
function EntityLoad(filename)
    assert(filename==path)
    if block_load then return 0 end
    return entity({[tag]=true},0,duration)
end
function EntityAddChild(parent,id) entities[id].parent=parent end
function EntityRemoveFromParent(id) entities[id].parent=0 end
function EntityKill(id)
    assert(entities[id].tags[tag] and entities[id].parent==0)
    entities[id]=nil
end

dofile("mods/noita_hideout/files/home_wand_edit.lua")
local player=entity()
local native=entity({perk_entity=true},player,-1)
local cube=entity({meditation_cube_effect=true},player,36000)
local mountain=entity({workshop_aabb=true})
local function owned(owner) return EntityGetAllChildren(owner,tag) end
NHHomeWandEdit.update(player,false)
local outsideScans=scans
for i=1,120 do NHHomeWandEdit.update(player,false) end
assert(scans==outsideScans)
assert(#owned(player)==0)
block_load=true
NHHomeWandEdit.update(player,true)
assert(#owned(player)==0)
block_load=false
NHHomeWandEdit.update(player,true)
local lease=assert(owned(player)[1])
for i=1,12 do
    entities[lease].effect.frames=1
    NHHomeWandEdit.update(player,true)
    assert(#owned(player)==1 and entities[lease].effect.frames==duration)
end

-- Rebuild the callback state as on save/continue. A duplicated saved effect
-- is cleaned up; an existing original is renewed even while the inventory is closed.
NHHomeWandEdit.reset()
entity({[tag]=true},player,duration)
NHHomeWandEdit.update(player,true)
assert(#owned(player)==1)
NHHomeWandEdit.reset()
NHHomeWandEdit.update(player,false)
assert(#owned(player)==0)
assert(entities[native].effect.frames==-1 and entities[cube].effect.frames==36000 and entities[mountain])

-- On polymorph or death the ordinary player may be missing, or its entity ID
-- may already have been replaced. Remove our permission from the old owner.
NHHomeWandEdit.update(player,true)
NHHomeWandEdit.update(nil,false)
assert(#owned(player)==0)
NHHomeWandEdit.update(player,true)
local nextPlayer=entity()
NHHomeWandEdit.update(nextPlayer,true)
assert(#owned(player)==0 and #owned(nextPlayer)==1 and entities[native].parent==player)
NHHomeWandEdit.update(nil,false)
entities[nextPlayer]=nil
NHHomeWandEdit.update(nil,false)
assert(#owned(nextPlayer)==0 and entities[cube].parent==player)
print("Home wand editing: vanilla effect, zone entry/exit, original permissions, save/continue, replacement and death passed.")
