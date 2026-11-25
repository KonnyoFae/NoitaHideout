local install=dofile("mods/noita_hideout/files/tarot_sight_ne.lua")
local path="data/scripts/animals/moal.lua"
local enabled,exists,text,writes=true,true,nil,0
function ModIsEnabled(id) assert(id=="new_enemies"); return enabled end
function ModDoesFileExist(file) assert(file==path); return exists end
function ModTextFileGetContent(file) assert(file==path); return text end
function ModTextFileSetContent(file,value) assert(file==path); text,writes=value,writes+1 end

-- The extra sprite and sound stand in for an extension by another mod.
local fixture=[=[local entity_id=GetUpdatedEntityID()
local players = {}
players[1]=EntityGetWithName("DEBUG_NAME:player")
local px,py=EntityGetTransform(players[1])
for _,child in ipairs(EntityGetAllChildren(entity_id)) do
    local sprite_components=EntityGetComponentIncludingDisabled(child, 'SpriteComponent')
    for _,sprite_component in ipairs(sprite_components) do
        if px<200 then
            local alpha=math.min(1,(200-px)/100)
            ComponentSetValue2 ( sprite_component, 'alpha', alpha )
        else
            ComponentSetValue2(sprite_component,"alpha",0)
        end
    end
end
ComponentSetValueVector2(400,"mVelocity",7,2)
GamePlaySound("bank","attack",0,0)
]=]

local function patch(source)
    text,writes=source,0
    install()
    assert(writes==1 and text~=source)
    local first=text
    install()
    assert(text==first and writes==1)
    return text
end

local names={"darkness","player_dark","player_dark2","player_dark3","player_dark4","player_dark5","player_eldritch","other"}
local children={1,2,3,4,5,6,7,8}
local function run(script,dist,protected)
    local alphas,events,queries={},{},0
    local function idle() end
    local function transform(id)
        if id==20 then return dist,0 end
        if id==40 then return 10,0 end
        return 0,0
    end
    local env=setmetatable({
        dofile_once=function(file)
            if file=="mods/noita_hideout/files/tarot_sight.lua" then
                return {active=function(id) assert(id==20); queries=queries+1; return protected end}
            end
        end,
        GetUpdatedEntityID=function() return 30 end,
        EntityGetWithName=function() return 20 end,
        EntityGetAllChildren=function() return children end, EntityGetName=function(id) return names[id] end,
        EntityGetComponentIncludingDisabled=function(id,kind) assert(kind=="SpriteComponent"); return {id} end,
        EntityGetTransform=transform, GameGetCameraPos=transform, EntitySetTransform=idle,
        EntitySetComponentIsEnabled=idle, EntitySetComponentsWithTagEnabled=idle,
        ComponentSetValue2=function(c,key,value) assert(key=="alpha"); alphas[c]=value end,
        GameGetFrameNum=function() return 100 end, SetRandomSeed=idle, Random=function() return 0 end,
        get_distance=function(x,y,a,b) return math.sqrt((a-x)^2+(b-y)^2) end,
        get_direction=function() return 0 end, GetValueNumber=function(_,default) return default end, SetValueNumber=idle,
        EntityGetWithTag=function() return {40} end, EntityGetComponent=function() return {400} end,
        edit_component=function(_,kind,fn) assert(kind=="VelocityComponent"); fn(400,{}) end,
        ComponentGetValueVector2=function() return 1,0 end,
        ComponentSetValueVector2=function(c,key,x,y)
            assert(c==400 and key=="mVelocity"); events[#events+1]=x..","..y
        end,
        GamePlaySound=function(_,event) events[#events+1]=event end,
    },{__index=_G})
    setfenv(assert(loadstring(script)),env)()
    return alphas,table.concat(events," "),queries
end

local function check(source)
    local filtered=patch(source)
    for _,dist in ipairs({30,150,250}) do
        local original,combat=run(source,dist,false)
        assert(combat~="")
        for _,protected in ipairs({true,false}) do
            local alpha,actions,queries=run(filtered,dist,protected)
            assert(queries==(dist<200 and 1 or 0) and actions==combat)
            for i=1,7 do
                assert(original[i]==math.min(1,math.max(0,(200-dist)/100)))
                assert(alpha[i]==(protected and 0 or original[i]))
            end
            assert(alpha[8]==original[8])
        end
    end
end
check(fixture)
check((fixture:gsub("\n","\r\n")))
assert(not text:gsub("\r\n",""):find("\n",1,true))
for _,unknown in ipairs({"",fixture..fixture,(fixture:gsub("local players","local targets"))}) do
    text,writes=unknown,0
    install()
    assert(writes==0 and text==unknown)
end
text,writes=fixture,0
enabled=false
install()
enabled,exists=true,false
install()
assert(writes==0 and text==fixture)
exists=true
local original=os.getenv("NH_TEST_NE_MOAL")
if original and original~="" then
    local file=assert(io.open(original,"rb"))
    local script=file:read("*a")
    file:close()
    check(script)
end
print("Moal's seven vision masks, range fade, unrelated sprites, combat and repeated registration passed.")
