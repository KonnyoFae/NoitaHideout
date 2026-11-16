-- Keys are stored in the hideout profile. Each action has a single primary essence.
NHEssences = {order = {}, types = {}, byAction = {}, values = dofile("mods/noita_hideout/files/spell_values.lua")}

-- Displayed HP, one unmodified target. Percentage healing is priced at 100 maximum HP.
-- Round the full card once so fractional healing per hit is retained.
local reference_hp = 100
NHEssences.healingProfiles = {
    HEAL_BULLET = {
        amount = 20 * 8.75,
        zh = "每次治疗 8.75 HP × 20 次。",
        en = "8.75 HP per hit × 20 casts.",
    },
    ANTIHEAL = {
        amount = math.floor(20 * (170 / 60) * 0.10 * reference_hp + 0.5),
        zh = "以 100 最大 HP 计，20 次完整再生。\n每次先伤 30 HP，再恢复约 28.3 HP。\n精华按恢复部分结算。",
        en = "20 full regeneration effects at 100 max HP.\nEach hit deals 30, then heals about 28.3 HP.\nExtraction values the healing component.",
    },
    REGENERATION_FIELD = {
        amount = math.floor(2 * (reference_hp * 2 / 3 + 21) + 0.5),
        zh = "以 100 最大 HP 计，在环心停留全程。\n每次约恢复最大 HP 的 2/3 加 21 HP，共 2 次。",
        en = "Stay at the centre for both casts at 100 max HP.\nEach restores about 2/3 of max HP plus 21 HP.",
    },
}
for id, profile in pairs(NHEssences.healingProfiles) do
    NHEssences.values[id] = profile.amount
end

local function define(key, zh, en, actions)
    table.insert(NHEssences.order, key)
    NHEssences.types[key] = {zh = zh, en = en}
    for _, action in ipairs(actions) do
        NHEssences.byAction[action] = key
    end
end

define("essence_healing", "治疗精华", "Healing essence", {
    "HEAL_BULLET", "ANTIHEAL", "REGENERATION_FIELD",
})

define("essence_acid", "酸液精华", "Acid essence", {
    "ACIDSHOT", "CLOUD_ACID",
})

define("essence_high_energy", "高能精华", "High-energy essence", {
    "BOMB", "DYNAMITE", "ROCKET", "ROCKET_TIER_2", "ROCKET_TIER_3", "MISSILE", "GRENADE",
    "GRENADE_TRIGGER", "GRENADE_TIER_2", "GRENADE_TIER_3", "GRENADE_ANTI", "GRENADE_LARGE",
    "MINE", "MINE_DEATH_TRIGGER", "PIPE_BOMB", "PIPE_BOMB_DEATH_TRIGGER", "EXPLODING_DEER",
    "EXPLODING_DUCKS", "GLITTER_BOMB", "FIREWORK", "PROPANE_TANK", "BOMB_CART", "TNTBOX",
    "TNTBOX_BIG", "GLOWING_BOLT", "DEATH_CROSS", "DEATH_CROSS_BIG", "BOMB_HOLY",
    "BOMB_HOLY_GIGA", "NUKE", "NUKE_GIGA", "EXPLOSION", "EXPLOSION_LIGHT",
    "PURPLE_EXPLOSION_FIELD", "METEOR_RAIN",
})

define("essence_fire", "火焰精华", "Fire essence", {
    "FLAMETHROWER", "FIREBOMB", "DARKFLAME", "FIREBALL", "METEOR", "FIRE_BLAST",
})

define("essence_lightning", "雷电精华", "Lightning essence", {
    "LIGHTNING", "BALL_LIGHTNING", "THUNDERBALL", "THUNDER_BLAST", "ELECTROCUTION_FIELD",
    "PROJECTILE_THUNDER_FIELD", "CLOUD_THUNDER",
})

define("essence_frost", "冰冻精华", "Frost essence", {
    "ICEBALL", "FREEZING_GAZE", "FREEZE_FIELD",
})

define("essence_toxin", "毒素精华", "Toxin essence", {
    "SLIMEBALL", "MIST_RADIOACTIVE", "POISON_BLAST",
})

define("essence_bolt", "魔弹精华", "Magic bolt essence", {
    "LIGHT_BULLET", "LIGHT_BULLET_TRIGGER", "LIGHT_BULLET_TRIGGER_2", "LIGHT_BULLET_TIMER",
    "BULLET", "BULLET_TRIGGER", "BULLET_TIMER", "HEAVY_BULLET", "HEAVY_BULLET_TRIGGER",
    "HEAVY_BULLET_TIMER", "SLOW_BULLET", "SLOW_BULLET_TRIGGER", "SLOW_BULLET_TIMER", "SPITTER",
    "SPITTER_TIMER", "SPITTER_TIER_2", "SPITTER_TIER_2_TIMER", "SPITTER_TIER_3",
    "SPITTER_TIER_3_TIMER", "BUBBLESHOT", "BUBBLESHOT_TRIGGER", "BOUNCY_ORB",
    "BOUNCY_ORB_TIMER", "RUBBER_BALL", "POLLEN", "SPIRAL_SHOT", "CHAIN_BOLT", "BUCKSHOT",
    "EXPANDING_ORB", "INFESTATION",
})

define("essence_cutting", "切削精华", "Cutting essence", {
    "DISC_BULLET", "DISC_BULLET_BIG", "DISC_BULLET_BIGGER", "ARROW", "LANCE", "CHAINSAW",
    "DIGGER", "POWERDIGGER", "LUMINOUS_DRILL", "LASER_LUMINOUS_DRILL", "LASER_EMITTER_CUTTER",
    "CRUMBLING_EARTH",
})

define("essence_beam", "光束精华", "Beam essence", {
    "LASER", "MEGALASER", "LASER_EMITTER", "LASER_EMITTER_FOUR",
})

define("essence_force", "力场精华", "Force field essence", {
    "AIR_BULLET", "HOOK", "MAGIC_SHIELD", "BIG_MAGIC_SHIELD", "WALL_HORIZONTAL",
    "WALL_VERTICAL", "WALL_SQUARE", "SHIELD_FIELD",
})

define("essence_displacement", "位移精华", "Displacement essence", {
    "TELEPORT_PROJECTILE", "TELEPORT_PROJECTILE_SHORT", "TELEPORT_PROJECTILE_STATIC",
    "SWAPPER_PROJECTILE", "TELEPORT_PROJECTILE_CLOSER", "TELEPORTATION_FIELD",
})

define("essence_gravity", "引力精华", "Gravity essence", {
    "BLACK_HOLE", "BLACK_HOLE_DEATH_TRIGGER", "WHITE_HOLE", "BLACK_HOLE_BIG", "WHITE_HOLE_BIG",
    "BLACK_HOLE_GIGA", "WHITE_HOLE_GIGA", "PROJECTILE_GRAVITY_FIELD", "VACUUM_ENTITIES",
    "VACUUM_POWDER", "VACUUM_LIQUID",
})

define("essence_summoning", "召唤精华", "Summoning essence", {
    "FISH", "WORM_SHOT", "PEBBLE", "TENTACLE", "TENTACLE_TIMER", "TENTACLE_PORTAL",
    "SUMMON_EGG", "SPORE_POD", "SWARM_FLY", "SWARM_FIREBUG", "SWARM_WASP", "FRIEND_FLY",
    "WORM_RAIN",
})

define("essence_creation", "造物精华", "Creation essence", {
    "SUMMON_ROCK", "GLUE_SHOT", "MIST_ALCOHOL", "MIST_SLIME", "MIST_BLOOD", "ALCOHOL_BLAST",
    "CLOUD_WATER", "CLOUD_OIL", "CLOUD_BLOOD",
})

define("essence_polymorph", "变形精华", "Polymorph essence", {
    "POLYMORPH_FIELD", "CHAOS_POLYMORPH_FIELD", "MASS_POLYMORPH",
    "PROJECTILE_TRANSMUTATION_FIELD",
})

define("essence_enhancement", "强化精华", "Enhancement essence", {
    "BERSERK_FIELD", "LEVITATION_FIELD",
})
