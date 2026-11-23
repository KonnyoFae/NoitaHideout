local L={}
local root="mods/noita_hideout/files/terminals/"
local fixed=dofile(root.."station.lua")
-- Vanilla's bridge cell ends at -9728. The pyramid entrance's west face
-- meets the surface near 8704. Probe away from each structure, onto land.
local sites={
    {key="snowcliff",name={"冻结避难所东崖","Frozen Vault · East Cliff"},x=-9700,step=12,
        biome="$biome_vault_frozen",bx=-9970,by=768},
    {key="pyramid",name={"金字塔西麓","Pyramid · West Foot"},x=8660,step=-12,
        biome="$biome_pyramid",bx=9984,by=-640},
}
local function nearbySite(x,y,margin)
    if y < -512-margin or y > 320+margin then return end
    local world=GetParallelWorldPosition(x,0)
    -- One biome-map cell spans 512 pixels. NG+ can change the map width.
    local offset=world==0 and 0 or world*BiomeMapGetSize()*512
    for _,s in ipairs(sites) do
        local dx=(x-offset-s.x)*(s.step>0 and 1 or -1)
        if dx>=-margin and dx<=16*math.abs(s.step)+margin then return s,world,offset end
    end
end

local function worldPrefix(prefix,world)
    -- Keep the main world's 0.42.5 placement and unlock keys.
    if world==0 then return prefix end
    return prefix.."world"..world.."."
end

local function position(prefix,s)
    local x,y=GlobalsGetValue(prefix..s.key.."_position",""):match("^(-?%d+),(-?%d+)$")
    return tonumber(x),tonumber(y)
end

local function probe(x,top,bottom)
    if not DoesWorldExistAt(x-18,top,x+18,bottom) then return end
    local hit,_,floor=RaytraceSurfaces(x,top,x,bottom)
    if not hit or floor<top+32 or floor>bottom-10 or GameGetSkyVisibility(x,floor-20)<0.5 then return end
    for dx=-12,12,6 do
        local sx=x+dx
        if RaytraceSurfacesAndLiquiform(sx,floor-32,sx,floor-5) then return end
        local supported,_,sy=RaytracePlatforms(sx,floor-5,sx,floor+5)
        if not supported or math.abs(sy-floor)>4 then return end
    end
    return math.floor(floor)-7
end

function L.update(px,py,prefix)
    local s,world,offset=nearbySite(px,py,320)
    if not s then return end
    prefix=worldPrefix(prefix,world)
    local x,y=position(prefix,s)
    local tag="nh_landmark_"..s.key
    if x then
        if not DoesWorldExistAt(x-18,y-32,x+18,y+16)
            or (EntityGetInRadiusWithTag(x,y,4,tag) or {})[1] then return end
    else
        if BiomeMapGetName(offset+s.bx,s.by)~=s.biome then return end
        -- Probe a streamed column near the player. Sky and footing checks
        -- reject underground visits, trees, the bridge and the pyramid slope.
        local top=math.max(-512,math.floor(py)-180)
        local bottom=math.min(320,math.floor(py)+200)
        if bottom-top<42 then return end
        for i=0,16 do
            x=offset+s.x+i*s.step
            y=probe(x,top,bottom)
            if y then break end
        end
        if not y then return end
    end
    local id=EntityLoad(root.."station.xml",x,y)
    if not id or id==0 then return end
    EntityRemoveTag(id,"nh_home_terminal")
    EntityAddTag(id,"nh_landmark_terminal")
    EntityAddTag(id,tag)
    fixed.upgrade(id)
    GlobalsSetValue(prefix..s.key.."_position",("%d,%d"):format(x,y))
end

function L.near(x,y)
    local s,world=nearbySite(x,y,48)
    if s then return (EntityGetInRadiusWithTag(x,y,48,"nh_landmark_"..s.key) or {})[1],s,world end
end

function L.unlock(prefix,s,world)
    local key=worldPrefix(prefix,world)..s.key.."_unlocked"
    if GlobalsGetValue(key,"")=="1" then return false end
    if world~=0 then
        local worlds=GlobalsGetValue(prefix.."landmark_worlds","")
        local token=world..";"
        if not (";"..worlds):find(";"..token,1,true) then
            GlobalsSetValue(prefix.."landmark_worlds",worlds..token)
        end
    end
    GlobalsSetValue(key,"1")
    return true
end

function L.unlocked(prefix)
    local stops={}
    local function addWorld(world)
        local base=worldPrefix(prefix,world)
        for _,s in ipairs(sites) do
            if GlobalsGetValue(base..s.key.."_unlocked","")=="1" then
                local x,y=position(base,s)
                if x then stops[#stops+1]={kind="landmark",world=world,x=x,y=y,name=s.name} end
            end
        end
    end
    addWorld(0)
    for world in GlobalsGetValue(prefix.."landmark_worlds",""):gmatch("(-?%d+);") do addWorld(tonumber(world)) end
    return stops
end
return L
