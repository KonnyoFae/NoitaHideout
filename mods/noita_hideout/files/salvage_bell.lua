local files="mods/noita_hideout/files/"
local bonuses=dofile_once(files.."loot_bonuses.lua")
local M={radius=256}
M.bridgeField="nh_ew.salvage_bell_bridge"
M.requestField="nh_ew.salvage_bell_request"
local function timer(player,tag)
    return EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
end

function M.remaining(player)
    return bonuses.remaining(player,"salvage_bell")
end

local function freeBag(bag,multiplayer)
    if EntityGetRootEntity(bag)~=bag or not (EntityHasTag(bag,"noita_hideout_travel_satchel")
        or EntityHasTag(bag,"noita_hideout_travel_pack") or EntityHasTag(bag,"noita_hideout_loot_case")) then return false end
    local item=EntityGetFirstComponent(bag,"ItemComponent")
    if not item or not ComponentGetValue2(item,"is_pickable") or EntityGetFirstComponentIncludingDisabled(bag,"ItemCostComponent")
        or timer(bag,"nh_ew_deposit_lock") then return false end
    if multiplayer then
        dofile_once(files.."ew_items.lua")
        local gid,invalid,owned=NHEWItems.gid(bag)
        if gid then return owned==true end
        if invalid or EntityHasTag(bag,"ew_des") then return false end
    end
    return true
end

function M.pull(x,y,multiplayer)
    local count=0
    for _,bag in ipairs(EntityGetInRadiusWithTag(x,y,M.radius,"nh_loot_bag") or {}) do
        if freeBag(bag,multiplayer) then
            local ox,oy,angle,sx,sy=EntityGetTransform(bag)
            -- Old saves can still contain the original physical bag.
            local body=EntityGetFirstComponent(bag,"PhysicsBodyComponent")
            if body then
                local bx,by=GamePosToPhysicsPos(x,y)
                PhysicsComponentSetTransform(body,bx,by,angle or 0,0,0,0)
            else
                EntityApplyTransform(bag,x,y,angle,sx,sy)
            end
            count=count+1
            if count<=8 and GameCreateCosmeticParticle then
                for i=1,4 do
                    local t=i/5
                    GameCreateCosmeticParticle("spark_white",ox+(x-ox)*t,oy+(y-oy)*t,1,
                        (x-ox)*0.4,(y-oy)*0.4,0,0.1,0.2,true,true,false,false,0,0)
                end
            end
        end
    end
    return count
end

function M.sound(x,y)
    GamePlaySound("data/audio/Desktop/projectiles.bank","player_projectiles/kantele/a/create",x,y)
end

function M.activate(player,pay)
    local ew=dofile_once(files.."ew.lua")
    if not player or player==0 or not EntityGetIsAlive(player) or not ew.localBody(player)
        or not EntityHasTag(player,"player_unit") then return false end
    local multiplayer=ew.enabled()
    local bridge
    local frame=GameGetFrameNum()
    if multiplayer then
        local world=ew.world()
        local scope,when=GlobalsGetValue(M.bridgeField,""):match("^([^|]+|[^|]+)|(%d+)$")
        when=tonumber(when)
        if not world or not scope or scope:match("^([^|]+)|")~=world or frame<when or frame-when>45
            or GlobalsGetValue(M.requestField,"")~="" then
            return false,"Bell sync unavailable."
        end
        bridge=scope
    end
    if not bonuses.activate(player,"salvage_bell",pay) then return false end
    local x,y=EntityGetTransform(player)
    if multiplayer then
        -- Hideout's init Lua state has no CrossCall. EW consumes this cast on
        -- its next poll. A second use cannot overwrite or pay for a pending cast.
        GlobalsSetValue(M.requestField,table.concat({bridge,frame,x,y},"|"))
    end
    M.pull(x,y,multiplayer)
    M.sound(x,y)
    return true
end

return M
