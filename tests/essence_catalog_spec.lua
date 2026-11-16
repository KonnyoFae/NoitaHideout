dofile("mods/noita_hideout/files/essences.lua")

local counts = {}
local total = 0
for id, key in pairs(NHEssences.byAction) do
    assert(NHEssences.types[key], id)
    counts[key] = (counts[key] or 0) + 1
    total = total + 1
end
assert(total == 158 and #NHEssences.order == 17)
local visited = {}
for _, key in ipairs(NHEssences.order) do
    local label = NHEssences.types[key]
    assert(counts[key] and not visited[key] and type(label.zh) == "string" and label.zh ~= "", key)
    assert(type(label.en) == "string" and label.en ~= "", key)
    visited[key] = true
end
for key in pairs(NHEssences.types) do assert(visited[key], key) end

-- Identical translations, similar names and trigger payloads can have different effects.
local examples = {
    LASER = "beam", GLOWING_BOLT = "high_energy", LASER_EMITTER_CUTTER = "cutting",
    ANTIHEAL = "healing", MIST_BLOOD = "creation", SLIMEBALL = "toxin", MIST_SLIME = "creation",
    ACIDSHOT = "acid", CLOUD_ACID = "acid", CLOUD_THUNDER = "lightning",
    LIGHT_BULLET_TRIGGER_2 = "bolt", BLACK_HOLE_DEATH_TRIGGER = "gravity",
}
for id, family in pairs(examples) do assert(NHEssences.byAction[id] == "essence_" .. family, id) end
for _, id in ipairs({
    "LANCE_HOLY", "CURSED_ORB", "SUMMON_HOLLOW_EGG", "RANDOM_PROJECTILE",
    "RANDOM_STATIC_PROJECTILE", "BOMB_DETONATOR", "DELAYED_SPELL", "DESTRUCTION", "FUNKY_SPELL",
    "ACID_TRAIL", "SEA_ACID", "MODDED_UNKNOWN_SPELL",
}) do
    assert(not NHEssences.byAction[id], id)
end
print("Spell essences: 158 mapped spells, 17 named resources, special and unsupported cards excluded.")
