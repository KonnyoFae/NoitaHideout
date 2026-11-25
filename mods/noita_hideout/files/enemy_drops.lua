local D = {redPool = dofile("mods/noita_hideout/files/red_collectibles.lua")}

local function bagKind(hp, score, draw)
    if score < 1 then
        if draw < hp / 20 then return "travel_satchel" end
    elseif score < 1.5 then
        local pack = score - 1
        if draw < pack then return "travel_pack" end
        if draw < pack + 0.5 then return "travel_satchel" end
    else
        local case = math.min(0.5, score - 1.5)
        if draw < case then return "loot_case" end
        if draw < case + 0.5 then return "travel_pack" end
        return "travel_satchel"
    end
end

local bagRank={travel_satchel=1,travel_pack=2,loot_case=3}

function D.roll(maxHp, allowBonus, sample, rerolls)
    -- Standalone enemy templates without a damage model historically gave one satchel.
    if maxHp == nil then return "travel_satchel" end
    if type(maxHp) ~= "number" or not (maxHp > 0 and maxHp < math.huge) then return end
    local hp = 25 * maxHp
    local score = math.log10(hp)
    local bag = bagKind(hp, score, sample(1))
    if not allowBonus then return bag end
    local x = math.max(0.5, score)
    local tarotRate,redRate=math.min(1,0.008*x^2),math.min(1,0.00030*x^3)
    local tarot,red=sample(2)<tarotRate,sample(3)<redRate
    -- Lanes 1–5 retain their original meaning. Each category has its own
    -- independent chance to retry, and still yields at most one object.
    if rerolls then
        if bag~="loot_case" and rerolls.bag and sample(6)<rerolls.bag then
            local second=bagKind(hp,score,sample(7))
            if (bagRank[second] or 0)>(bagRank[bag] or 0) then bag=second end
        end
        if not tarot and rerolls.tarot and sample(8)<rerolls.tarot then tarot=sample(9)<tarotRate end
        if not red and rerolls.red and sample(10)<rerolls.red then red=sample(11)<redRate end
    end
    return bag, tarot, red
end

return D
