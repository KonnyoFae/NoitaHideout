local files = "mods/noita_hideout/files/"

local function remoteCopy(mob)
    local tracked = EntityHasTag(mob, "ew_des")
    if not tracked and not (ModIsEnabled and ModIsEnabled("quant.ew")) then return false end
    dofile_once(files .. "ew_items.lua")
    local gid, invalid, owned = NHEWItems.gid(mob)
    -- DES tags both replicas and the simulation owner (which may be a guest).
    if gid then return owned ~= true end
    return invalid or tracked
end

function death(damage_type, message, responsible, drop_items)
    local mob = GetUpdatedEntityID()
    if drop_items == false or EntityHasTag(mob, "nh_loot_paid") or EntityHasTag(mob, "player_unit")
        or EntityHasTag(mob, "polymorphed_player") or EntityHasTag(mob, "ew_peer")
        or EntityHasTag(mob, "ew_client") or EntityHasTag(mob, "ew_notplayer")
        or EntityHasTag(mob, "nh_reinforcement") or remoteCopy(mob) then return end
    EntityAddTag(mob, "nh_loot_paid")
    local x, y = EntityGetTransform(mob)
    local seedX, seedY = x + mob, y + GameGetFrameNum()
    -- Each decision has its own deterministic draw; an empty pool or a missed
    -- bag cannot shift the tarot or collectible roll. Leave Noita's RNG alone.
    local function draw(lane, limit)
        return ProceduralRandomi(seedX, seedY + lane * 7919, 1, limit)
    end
    local function sample(lane) return (draw(lane, 10000000) - 1) / 10000000 end
    local model = EntityGetFirstComponentIncludingDisabled(mob, "DamageModelComponent")
    local drops = dofile_once(files .. "enemy_drops.lua")
    local bonus = not EntityHasTag(mob, "nh_decoy") and not EntityHasTag(mob, "summon_player")
        and not EntityHasTag(mob, "nh_no_rare_drop")
        and not EntityGetFirstComponentIncludingDisabled(mob, "VariableStorageComponent", "no_gold_drop")
    local rerolls
    if bonus and responsible and responsible~=0 then
        local vitality=dofile_once(files.."tarot_vitality.lua")
        local killer=vitality.killOwner(responsible)
        if killer then
            rerolls=dofile_once(files.."loot_bonuses.lua").rerolls(killer,"enemy_kill")
            vitality.rewardKill(killer)
        end
    end
    local bag, tarot, red = drops.roll(model and ComponentGetValue2(model, "max_hp"), bonus, sample, rerolls)
    if bag then EntityLoad(files .. "items/" .. bag .. ".xml", x, y - 3) end
    if tarot then
        local cards = dofile_once(files .. "tarot.lua")
        EntityLoad(cards.dropFile(function(n) return draw(4, n) end), x - 6, y - 3)
    end
    if red and #drops.redPool > 0 then
        EntityLoad(drops.redPool[draw(5, #drops.redPool)].file, x + 6, y - 3)
    end
end
