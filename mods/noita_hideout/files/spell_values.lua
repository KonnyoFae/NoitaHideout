-- One entry is the yield of one whole loose card. Finite use counts come
-- from data/scripts/gun/gun_actions.lua. Unrestricted spells use a common
-- twenty-cast reference window. The inventory card's charges are irrelevant.
local values = {}
local unlimited = 20

local function price(casts, perCast)
    for id, power in pairs(perCast) do
        local total = casts * power
        local payout = math.min(total, 375) + math.max(0, total - 375) / 8
        values[id] = math.floor(payout + 0.5)
    end
end

-- For direct attacks, one displayed HP of primary impact/blast is one
-- reference point (entity XML damage * 25). Multiple missiles count when
-- intrinsic to one cast. Elemental secondary damage is valued in its primary
-- family only. Trigger carriers receive a small fixed handling premium;
-- no attached spell's damage or value is added.
price(unlimited, {
    LIGHT_BULLET = 3, LIGHT_BULLET_TRIGGER = 4, LIGHT_BULLET_TIMER = 4,
    LIGHT_BULLET_TRIGGER_2 = 8.25,
    BULLET = 10, BULLET_TRIGGER = 11, BULLET_TIMER = 11,
    HEAVY_BULLET = 12.75, HEAVY_BULLET_TRIGGER = 13.75, HEAVY_BULLET_TIMER = 13.75,
    SLOW_BULLET = 15.75, SLOW_BULLET_TRIGGER = 16.75, SLOW_BULLET_TIMER = 16.75,
    SPITTER = 7.5, SPITTER_TIMER = 8.5, SPITTER_TIER_2 = 12.5, SPITTER_TIER_2_TIMER = 13.5,
    SPITTER_TIER_3 = 15, SPITTER_TIER_3_TIMER = 16,
    BUBBLESHOT = 5, BUBBLESHOT_TRIGGER = 6, BOUNCY_ORB = 10, BOUNCY_ORB_TIMER = 11,
    RUBBER_BALL = 3, POLLEN = 10, BUCKSHOT = 3 * 4.625,
    -- Allow three jumps on a chain, one grown orb impact, and two hits per spark.
    CHAIN_BOLT = 3 * 25, EXPANDING_ORB = 75, INFESTATION = 6 * 2 * 1.25,
})
price(15, {SPIRAL_SHOT = 4 * 5})

-- Detonations and warheads. A small magic grenade (grenade_small.xml) is
-- a 30-point output: 17.5 impact + 12.5 blast. GRENADE uses grenade.xml.
price(3, {BOMB = 125})
price(16, {DYNAMITE = 62.5, GLITTER_BOMB = 25 + 20})
price(10, {ROCKET = 180, EXPLODING_DEER = 100, PROPANE_TANK = 325})
price(8, {ROCKET_TIER_2 = 217.5, DEATH_CROSS_BIG = 100})
price(6, {ROCKET_TIER_3 = 255, BOMB_CART = 100})
price(25, {GRENADE = 80, GRENADE_TRIGGER = 81, GRENADE_ANTI = 72.5, FIREWORK = 55})
price(20, {
    MISSILE = 75, GRENADE_TIER_2 = 100, GRENADE_TIER_3 = 122.5,
    PIPE_BOMB = 137.5, PIPE_BOMB_DEATH_TRIGGER = 138.5, EXPLODING_DUCKS = 3 * 100,
    -- The field rains small blasts for several seconds; budget six useful hits.
    PURPLE_EXPLOSION_FIELD = 6 * 15,
})
price(35, {GRENADE_LARGE = 147.5})
price(15, {MINE = 100, MINE_DEATH_TRIGGER = 101, TNTBOX = 125, TNTBOX_BIG = 200})
price(unlimited, {GLOWING_BOLT = 15, DEATH_CROSS = 75, EXPLOSION = 68.75, EXPLOSION_LIGHT = 93.75})
-- Large terrain destruction is a separate utility allowance: one point per
-- blast-radius pixel for holy bombs, two for earthquake-producing nukes.
price(2, {BOMB_HOLY = 200 + 180, BOMB_HOLY_GIGA = 500 + 320, METEOR_RAIN = 6 * 120})
price(1, {NUKE = 75 + 250 + 2 * 250, NUKE_GIGA = 250 + 500 + 2 * 400})

-- Fire, lightning and frost include their primary element. Sustained or
-- recurring sources get a bounded exposure allowance so a single target
-- standing in the effect forever cannot multiply the salvage quote.
price(60, {FLAMETHROWER = 23.75, DARKFLAME = 40})
price(unlimited, {FIREBOMB = 10, FIRE_BLAST = 20, LIGHTNING = 125,
    BALL_LIGHTNING = 3 * 18.75, THUNDER_BLAST = 75})
price(15, {FIREBALL = 56.25, ICEBALL = 56.25, FREEZE_FIELD = 40, ELECTROCUTION_FIELD = 45})
price(10, {METEOR = 120})
price(3, {THUNDERBALL = 180})
price(6, {PROJECTILE_THUNDER_FIELD = 120})
price(5, {CLOUD_THUNDER = 150})
price(20, {FREEZING_GAZE = 12 * 10})

-- Acid/toxin contact, persistent mist and sustained rainfall have different
-- coverage. These are explicit exposure estimates, not guaranteed HP hits.
price(20, {ACIDSHOT = 30})
price(8, {CLOUD_ACID = 120})
price(unlimited, {SLIMEBALL = 18, MIST_RADIOACTIVE = 24, POISON_BLAST = 36})

-- Slicing and digging: one direct strike for simple blades, two contacts
-- for the recurring omega saw. Wider excavation adds utility to blast/drill
-- tools. Large-scale earthquake provides a separate terrain benchmark.
price(unlimited, {
    DISC_BULLET = 20, DISC_BULLET_BIG = 62.5, DISC_BULLET_BIGGER = 2 * 37.5,
    ARROW = 5, LANCE = 35, CHAINSAW = 12.75, DIGGER = 12, POWERDIGGER = 24,
    LUMINOUS_DRILL = 30, LASER_LUMINOUS_DRILL = 31, LASER_EMITTER_CUTTER = 60,
    LASER = 15.25, MEGALASER = 120, LASER_EMITTER = 48, LASER_EMITTER_FOUR = 96,
})
price(3, {CRUMBLING_EARTH = 240})

-- Force (short shove < grappling < persistent barrier); displacement
-- distinguishes a short precise hop, long travel, return, and area control.
price(unlimited, {
    AIR_BULLET = 8, HOOK = 15, MAGIC_SHIELD = 4 * 8, BIG_MAGIC_SHIELD = 8 * 8,
    WALL_HORIZONTAL = 32, WALL_VERTICAL = 32,
    TELEPORT_PROJECTILE = 30, TELEPORT_PROJECTILE_SHORT = 20,
    TELEPORT_PROJECTILE_STATIC = 18, SWAPPER_PROJECTILE = 36, TELEPORT_PROJECTILE_CLOSER = 24,
})
price(20, {WALL_SQUARE = 64})
price(10, {SHIELD_FIELD = 70})
price(15, {TELEPORTATION_FIELD = 54})

-- A normal hole consumes terrain in a radius of 12, the omega hole in a
-- radius of 60 for much longer. White and black receive equal allowances at
-- the same size. Vacuum fields gather existing matter or entities.
price(3, {BLACK_HOLE = 100, BLACK_HOLE_DEATH_TRIGGER = 101, WHITE_HOLE = 100})
price(6, {BLACK_HOLE_BIG = 200, WHITE_HOLE_BIG = 200, BLACK_HOLE_GIGA = 500,
    WHITE_HOLE_GIGA = 500, PROJECTILE_GRAVITY_FIELD = 70})
price(20, {VACUUM_ENTITIES = 40, VACUUM_POWDER = 24, VACUUM_LIQUID = 24})

-- Summons use a bounded service or attack budget; the rock spirit acts
-- autonomously, the inert rock cannot. Repeated creature hits and random
-- hatches do not require simulating the world or rolling an outcome.
price(20, {FISH = 8})
price(10, {WORM_SHOT = 50, PEBBLE = 60})
price(5, {TENTACLE_PORTAL = 6 * 20})
price(2, {SUMMON_EGG = 65, WORM_RAIN = 360})
price(unlimited, {
    TENTACLE = 20, TENTACLE_TIMER = 21, SPORE_POD = 30,
    SWARM_FLY = 4 * 3.5, SWARM_FIREBUG = 3 * 7.5, SWARM_WASP = 5 * 7,
    FRIEND_FLY = 4 * 10,
})

-- Creation values distinguish brief dispersal, an enduring solid and a
-- productive rain cloud. Transmutation scales from one local effect to the
-- large-area spell. Buffs distinguish mobility from a strong combat buff.
price(unlimited, {GLUE_SHOT = 14, MIST_ALCOHOL = 15, MIST_SLIME = 15, ALCOHOL_BLAST = 25})
price(3, {SUMMON_ROCK = 60, CLOUD_BLOOD = 90, MASS_POLYMORPH = 320})
price(10, {MIST_BLOOD = 22, CLOUD_WATER = 50, CHAOS_POLYMORPH_FIELD = 75})
price(15, {CLOUD_OIL = 50, BERSERK_FIELD = 65, LEVITATION_FIELD = 35})
price(5, {POLYMORPH_FIELD = 70})
price(6, {PROJECTILE_TRANSMUTATION_FIELD = 90})

return values
