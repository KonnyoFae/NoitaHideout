local root="mods/noita_hideout/files/"
local entities,components,moved,globals={},{},{},{}
local frame,mp,ready=900,false,true
local sound,scans=0,0
local function entity(id,tag,x)
    entities[id]={tags={[tag]=true},x=x or 0,y=0,root=id,components={}}
    return id
end
local function add(id,kind,t)
    t=t or {}
    t.kind=kind
    components[#components+1]=t
    local n=#components
    local list=entities[id].components
    list[#list+1]=n
    return n
end
function EntityGetComponentIncludingDisabled(id,kind,tag)
    local list={}
    for _,i in ipairs(entities[id].components) do
        local c=components[i]
        if c.kind==kind and (not tag or c._tags==tag) then list[#list+1]=i end
    end
    return list
end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag) return EntityGetComponentIncludingDisabled(id,kind,tag)[1] end
EntityGetFirstComponent=EntityGetFirstComponentIncludingDisabled
EntityAddComponent2=add
function EntityRemoveComponent(id,c) components[c].kind="" end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityHasTag(id,tag) return entities[id].tags[tag] or false end
function ComponentGetTags(id) return components[id]._tags or "" end
function ComponentGetValue2(id,key) return components[id][key] end
function ComponentSetValue2(id,key,value) components[id][key]=value end
function EntityGetRootEntity(id) return entities[id].root end
function EntityGetTransform(id) return entities[id].x,entities[id].y,0,1,1 end
function EntityApplyTransform(id,x,y) moved[id]=true; entities[id].x,entities[id].y=x,y end
function GameGetFrameNum() return frame end
function GamePlaySound() sound=sound+1 end
function EntityGetInRadiusWithTag(x,y,radius,tag)
    scans=scans+1
    assert(radius==256 and tag=="nh_loot_bag")
    local list={}
    for id,e in pairs(entities) do
        if e.tags[tag] and (x-e.x)^2+(y-e.y)^2<=radius^2 then list[#list+1]=id end
    end
    return list
end
function GlobalsSetValue(key,v) globals[key]=v end
function GlobalsGetValue(key,default) return globals[key] or default end
local function bag(id,name,x,count)
    entity(id,"nh_loot_bag",x)
    entities[id].tags["noita_hideout_"..name]=true
    return add(id,"ItemComponent",{uses_remaining=count,is_pickable=true})
end
local cache={}
function dofile_once(path)
    if path==root.."ew.lua" then
        return {enabled=function() return mp end,localBody=function(id) return not EntityHasTag(id,"ew_client") end,
            world=function() if ready then return "world" end end}
    end
    if not cache[path] then cache[path]=dofile(path) or true end
    return cache[path]
end

local bell=dofile(root.."salvage_bell.lua")
entity(1,"player_unit",0)
entity(2,"ew_client",5)
local s=bag(10,"travel_satchel",256,13)
local p=bag(11,"travel_pack",70,7)
local c=bag(12,"loot_case",-90,23)
bag(13,"travel_pack",256.1,4)
bag(14,"gift_box_1",70,1)
bag(15,"travel_pack",20,4)
entities[15].root=2
bag(16,"loot_case",20,2)
add(16,"ItemCostComponent",{})
local busy=bag(17,"travel_satchel",20,1)
components[busy].is_pickable=false
bag(18,"travel_pack",20,1)
add(18,"VariableStorageComponent",{_tags="nh_ew_deposit_lock"})
assert(not bell.activate(2) and not bell.activate(0))
assert(not bell.activate(1,function() return false end))
assert(bell.remaining(1)==0 and sound==0 and scans==0 and not globals["nh_ew.loot_bonuses_dirty"])
assert(bell.activate(1) and scans==1 and sound==1)
assert(moved[10] and moved[11] and moved[12] and components[s].uses_remaining==13 and components[p].uses_remaining==7 and components[c].uses_remaining==23)
for id=13,18 do assert(not moved[id],"unexpected bag movement "..id) end
assert(bell.remaining(1)==54000)
frame=frame+3600
local reloaded=dofile(root.."salvage_bell.lua")
assert(reloaded.remaining(1)==50400 and scans==1)
assert(not reloaded.activate(1,function() return false end))
assert(reloaded.remaining(1)==50400 and scans==1 and sound==1)
assert(reloaded.activate(1) and reloaded.remaining(1)==54000)
frame=frame+53999
assert(reloaded.remaining(1)==1)
frame=frame+1
assert(reloaded.remaining(1)==0)

mp=true
ready=false
assert(not reloaded.activate(1))
ready=true
globals[bell.bridgeField]="wrong|boot|"..frame
assert(not reloaded.activate(1) and reloaded.remaining(1)==0 and sound==2)
globals[bell.bridgeField]="world|boot|"..(frame-46)
assert(not reloaded.activate(1) and reloaded.remaining(1)==0)
globals[bell.bridgeField]="world|boot|"..frame
for id=20,24 do bag(id,"travel_pack",75,3); entities[id].tags.ew_des=true end
for id=20,22 do
    add(id,"VariableStorageComponent",{name="ew_gid_lid",value_string=tostring(id),value_bool=id==20})
end
add(22,"VariableStorageComponent",{name="ew_gid_lid",value_string="77",value_bool=true})
add(24,"VariableStorageComponent",{name="ew_gid_lid",value_string="invalid",value_bool=true})
assert(reloaded.activate(1) and moved[20] and not moved[21] and not moved[22] and not moved[23] and not moved[24])
local before=reloaded.remaining(1)
local queued=globals[bell.requestField]
assert(queued=="world|boot|"..frame.."|0|0")
frame=frame+35
local ok,reason=reloaded.activate(1)
assert(not ok and reason=="Bell sync unavailable." and reloaded.remaining(1)==before-35 and globals[bell.requestField]==queued)
local bonuses=dofile_once(root.."loot_bonuses.lua")
assert(bonuses.applyRemote(2,{salvage_bell=54000}))
assert(reloaded.remaining(2)==180)
frame=frame+100
assert(bonuses.applyRemote(2,{salvage_bell=10}))
for _,tag in ipairs({"ew_notplayer","nh_ew_waiting"}) do
    entities[2].tags[tag]=true
    assert(reloaded.remaining(2)==0)
    entities[2].tags[tag]=nil
end
assert(reloaded.remaining(2)==10)
frame=frame+10
assert(reloaded.remaining(2)==0)
print("Salvage bell sweep preserved original bags and stacks, filtered blocked pickups and EW owners, refreshed its single saved game timer and expired remote leases.")
