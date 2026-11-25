local root="mods/noita_hideout/files/"
local M={}
local tag="nh_katana_credit"
local function first(id,kind,componentTag)
    if componentTag then return EntityGetFirstComponentIncludingDisabled(id,kind,componentTag) end
    return EntityGetFirstComponentIncludingDisabled(id,kind)
end
local function alive(player)
    if not player or player==0 or not EntityGetIsAlive(player) then return false end
    local dm=first(player,"DamageModelComponent")
    return dm and ComponentGetValue2(dm,"hp")>0 and not EntityHasTag(player,"nh_ew_waiting")
end

function M.ensure(player,state)
    local c=first(player,"VariableStorageComponent",tag)
    local scope=tostring(state.profile).."/"..tostring(state.runSerial)
    if c and ComponentGetValue2(c,"name")==scope then return c end
    if not c then c=EntityAddComponent2(player,"VariableStorageComponent",{_tags=tag}) end
    if not c then return end
    ComponentSetValue2(c,"name",scope)
    ComponentSetValue2(c,"value_string",scope.."/"..player.."/"..GameGetFrameNum())
    ComponentSetValue2(c,"value_int",0)
    ComponentSetValue2(c,"value_float",0)
    return c
end

function M.credit(player)
    if not alive(player) then return false end
    if EntityHasTag(player,"ew_client") then
        if CrossCall then CrossCall("ew_hideout_katana_credit",player) end
        return true
    end
    local c=first(player,"VariableStorageComponent",tag)
    if not c then return false end
    local total=ComponentGetValue2(c,"value_int")
    ComponentSetValue2(c,"value_int",math.min(2147483647,total+1))
    return true
end

function M.mark(enemy,player,message)
    local c=first(enemy,"VariableStorageComponent","nh_katana_last_hit")
    c=c or EntityAddComponent2(enemy,"VariableStorageComponent",{_tags="nh_katana_last_hit"})
    if not c then return false end
    ComponentSetValue2(c,"value_int",player)
    ComponentSetValue2(c,"value_string",message)
    if not first(enemy,"LuaComponent","nh_katana_death") then
        EntityAddComponent2(enemy,"LuaComponent",{_tags="nh_katana_death",execute_every_n_frame=-1,
            script_death=root.."katana_death.lua"})
    end
    return true
end

function M.death(enemy,message,responsible)
    if EntityHasTag(enemy,"nh_katana_reward_paid") then return end
    local c=first(enemy,"VariableStorageComponent","nh_katana_last_hit")
    if not c or message~=ComponentGetValue2(c,"value_string") or responsible~=ComponentGetValue2(c,"value_int") then return end
    if not dofile_once(root.."field_targets.lua").canAffect(enemy,ModIsEnabled("quant.ew")) then return end
    EntityAddTag(enemy,"nh_katana_reward_paid")
    M.credit(responsible)
end

-- The profile receipt makes shield/ammo retries idempotent. Health is an
-- entity mutation: its own serialized cursor prevents replay on a normal save.
function M.claim(state,player,commit)
    if not alive(player) then return end
    local c=M.ensure(player,state)
    if not c then return end
    local total=ComponentGetValue2(c,"value_int")
    local token=ComponentGetValue2(c,"value_string")
    local seen=state.katanaRewardToken==token and state.katanaRewardSeen or 0
    local amount=(NHKatanas or dofile_once(root.."katanas.lua")).zandatsu
    if total>(seen or 0) and not dofile_once(root.."katana_resources.lua").reward(player,commit,token,total,amount) then return end
    local healed=ComponentGetValue2(c,"value_float")
    if total<=healed then return end
    ComponentSetValue2(c,"value_float",total)
    local dm=first(player,"DamageModelComponent")
    if dm and GameGetGameEffectCount(player,"NO_HEAL")==0 then
        local maximum=ComponentGetValue2(dm,"max_hp")
        local hp=ComponentGetValue2(dm,"hp")
        if hp>0 then ComponentSetValue2(dm,"hp",math.min(maximum,hp+maximum*amount.healthRewardFraction*(total-healed))) end
    end
end
return M
