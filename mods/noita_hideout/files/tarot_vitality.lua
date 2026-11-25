local misc="data/entities/misc/"
local stacks=5
local kickTag="nh_tarot_devil_kick"
local ice="mods/noita_hideout/files/tarot_vitality_kick.xml"
local rates={sun_use=0.5,sun_tick=0.02,devil_tick=-0.01,devil_kill=0.05}
local M={paths={
    tarot_sun={misc.."effect_protection_fire.xml",misc.."effect_saving_grace.xml",misc.."effect_remove_fog_of_war.xml"},
    tarot_devil={},
}}
for i=1,stacks do M.paths.tarot_devil[i]=misc.."effect_critical_hit_boost.xml" end

local function changeHealth(player,kind,steps)
    local fraction=rates[kind]*(steps or 1)
    if EntityHasTag(player,"ew_client") or EntityHasTag(player,"ew_notplayer") or EntityHasTag(player,"nh_ew_waiting") then return end
    if fraction>0 and GameGetGameEffectCount(player,"NO_HEAL")>0 then return end
    local model=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not model then return end
    local hp=ComponentGetValue2(model,"hp")
    local maximum=ComponentGetValue2(model,"max_hp")
    if hp<=0 or maximum<=0 then return end
    if (fraction<0 and hp<=maximum/2) or (fraction>0 and hp>=maximum) then return end
    if ModIsEnabled and ModIsEnabled("quant.ew") and
        dofile_once("mods/noita_hideout/files/tarot_shared_health.lua").change(player,kind,steps) then return end
    if fraction>0 then
        ComponentSetValue2(model,"hp",math.min(maximum,hp+fraction*maximum))
    else
        ComponentSetValue2(model,"hp",math.max(maximum/2,hp+fraction*maximum))
    end
end

-- Match vanilla STRONG_KICK. Its four LensValue fields use the native perk's
-- metadata accessors. Reversing the arithmetic preserves later permanent stacks.
local function kickStats(kick,sign)
    for _,field in ipairs({"max_force","player_kickforce"}) do
        local value=tonumber(ComponentGetMetaCustom(kick,field))
        ComponentSetMetaCustom(kick,field,value*1.7^(sign*stacks))
    end
    for field,amount in pairs({kick_damage=2.4,kick_knockback=250}) do
        local value=tonumber(ComponentGetMetaCustom(kick,field))
        ComponentSetMetaCustom(kick,field,value+sign*stacks*amount)
    end
    local speed=ComponentGetValue2(kick,"telekinesis_throw_speed")
    ComponentSetValue2(kick,"telekinesis_throw_speed",speed+sign*stacks*25)
end

local function grantKicks(player)
    for _,kick in ipairs(EntityGetComponent(player,"KickComponent") or {}) do
        kickStats(kick,1)
        local list=ComponentGetValue2(kick,"kick_entities")
        ComponentSetValue2(kick,"kick_entities",list..string.rep(","..ice,stacks))
        ComponentAddTag(kick,kickTag)
    end
    for _,tele in ipairs(EntityGetComponent(player,"TelekinesisComponent") or {}) do
        ComponentSetValue2(tele,"throw_speed",ComponentGetValue2(tele,"throw_speed")+stacks*25)
        ComponentAddTag(tele,kickTag)
    end
end

function M.commit(player,id,timer,existing)
    if id=="tarot_sun" then changeHealth(player,"sun_use")
    elseif id=="tarot_devil" and not existing then grantKicks(player) end
end

function M.pulse(player,id,timer,seconds)
    if id=="tarot_sun" then changeHealth(player,"sun_tick",seconds)
    elseif id=="tarot_devil" then changeHealth(player,"devil_tick",seconds) end
end

function M.expire(player,id)
    if id~="tarot_devil" then return end
    local inheritedSpeed
    for _,kick in ipairs(EntityGetComponentIncludingDisabled(player,"KickComponent",kickTag) or {}) do
        local original,list=ComponentGetValue2(kick,"kick_entities"),{}
        for token in (original..","):gmatch("([^,]*),") do
            if token~=ice then list[#list+1]=token end
        end
        local kept=table.concat(list,",")
        -- The vanilla perk nullifier resets the kick fields and clears its list.
        if original~=kept then
            inheritedSpeed=math.max(inheritedSpeed or 0,ComponentGetValue2(kick,"telekinesis_throw_speed"))
            kickStats(kick,-1)
            ComponentSetValue2(kick,"kick_entities",kept)
        end
        ComponentRemoveTag(kick,kickTag)
    end
    for _,tele in ipairs(EntityGetComponentIncludingDisabled(player,"TelekinesisComponent") or {}) do
        local speed=ComponentGetValue2(tele,"throw_speed")
        -- Telekinesis acquired during the card copies its starting speed from KickComponent.
        if speed>=stacks*25 and (ComponentHasTag(tele,kickTag) or speed==inheritedSpeed) then
            ComponentSetValue2(tele,"throw_speed",speed-stacks*25)
        end
        ComponentRemoveTag(tele,kickTag)
    end
end

function M.healKill(player)
    if not player or player==0 or not EntityGetIsAlive(player) then return end
    local timer=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_tarot_devil")
    if timer and ComponentGetValue2(timer,"value_int")>0 then changeHealth(player,"devil_kill") end
end

local function playerRoot(entity)
    local root=EntityGetRootEntity(entity)
    if root and root~=0 and (EntityHasTag(root,"player_unit") or EntityHasTag(root,"ew_client")) then return root end
end

function M.killOwner(responsible)
    if not responsible or responsible==0 or not EntityGetIsAlive(responsible) then return end
    local player=playerRoot(responsible)
    if not player then
        local shot=EntityGetFirstComponentIncludingDisabled(responsible,"ProjectileComponent")
        local shooter=shot and ComponentGetValue2(shot,"mWhoShot")
        if shooter and shooter~=0 and EntityGetIsAlive(shooter) then player=playerRoot(shooter) end
    end
    return player
end

-- The enemy simulator dispatches the reward once, after resolving ownership.
function M.rewardKill(player)
    if not player then return end
    if EntityHasTag(player,"ew_client") then
        if CrossCall and GlobalsGetValue("nh_ew.status","")~="" then CrossCall("ew_hideout_devil_kill",player) end
    else
        M.healKill(player)
    end
end
return M
