local root="mods/noita_hideout/files/"
local shields=dofile(root.."shield_runtime.lua")
local M={}

-- Like other carried relics, durability belongs to the physical item and is
-- captured by its storage codec. A pending transfer must never pay a skill.
function M.spendDurability(state,player,weapon)
    if not player or not weapon or not EntityGetIsAlive(weapon) or NHNative.held(player)~=weapon
        or EntityGetRootEntity(weapon)~=player then return false end
    local K=NHKatanas or dofile_once(root.."katanas.lua")
    local def=K.types[K.kind(weapon)]
    if not def or not def.durability then return false end
    if NHEWItems and NHEWItems.lockInfo(weapon) then return false end
    if EntityGetFirstComponentIncludingDisabled(weapon,"ItemCostComponent") then return false end
    local ok=NHTransfers.available(state,player,weapon)
    if not ok then return false end
    local item=EntityGetFirstComponentIncludingDisabled(weapon,"ItemComponent")
    local remaining=item and ComponentGetValue2(item,"uses_remaining")
    local cost=def.plunderDurabilityCost or 1
    if type(remaining)~="number" or remaining~=math.floor(remaining) or remaining<cost or remaining>def.durability then return false end
    ComponentSetValue2(item,"uses_remaining",remaining-cost)
    return true
end

-- Spending shield energy is not damage: no health spill, rescue or reactor hit.
function M.spend(player,weapon,commit,shieldCells,ammo)
    local paid,shieldPoints
    local ok=commit(function(draft)
        if NHNative.held(player)~=weapon then return false,"Item unavailable." end
        shields.snapshot(draft,player)
        local shield,rig=draft.gearShield,draft.gearRig
        local cost=0
        if shieldCells and shieldCells>0 then
            if not shield or not NHShields.types[shield.item.kind] then return false,"A charged shield is required." end
            cost=math.ceil(NHShields.cell*shieldCells)
            if shield.item.charge<cost then return false,"Not enough shield charge." end
            local health=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
            local maxHP=health and ComponentGetValue2(health,"max_hp")
            if not maxHP or maxHP<=0 then return false,"Item unavailable." end
            shieldPoints=NHShields.chargePoints(cost,maxHP)
            if not (shieldPoints>0) then return false,"Item unavailable." end
        end
        if ammo and ammo>0 and (not rig or rig.item.reserve<ammo) then return false,"Not enough reserve ammo." end
        if cost>0 then
            shield.item.charge=shield.item.charge-cost
            shield.item.repair,shield.item.delay=0,180
            shield.epoch=draft.revision+1
        end
        if ammo and ammo>0 then rig.item.reserve=rig.item.reserve-ammo end
        paid=draft
        return true
    end)
    if ok and paid then shields.sync(paid,player) end
    return ok==true,ok and shieldPoints or nil
end

function M.reward(player,commit,token,total,amount)
    local paid,delta
    local ok=commit(function(draft)
        local prior=draft.katanaRewardToken==token and draft.katanaRewardSeen or 0
        delta=math.max(0,total-(prior or 0))
        if delta==0 then return false,"Reward already collected." end
        shields.snapshot(draft,player)
        local shield,rig=draft.gearShield,draft.gearRig
        if shield and NHShields.types[shield.item.kind] then
            local capacity=NHShields.types[shield.item.kind].cells*NHShields.cell
            shield.item.charge=math.min(capacity,shield.item.charge+math.ceil(capacity*amount.shieldRewardFraction)*delta)
            shield.item.repair=0
            shield.epoch=draft.revision+1
        end
        if rig and NHFirearms.rigs[rig.item.kind] then
            rig.item.reserve=math.min(NHFirearms.rigs[rig.item.kind].capacity,rig.item.reserve+amount.ammoReward*delta)
        end
        draft.katanaRewardToken,draft.katanaRewardSeen=token,total
        paid=draft
        return true
    end)
    if ok and paid then shields.sync(paid,player) end
    return ok==true,delta
end
return M
