local orb = GetUpdatedEntityID()
local component = EntityGetFirstComponentIncludingDisabled
local get, set = ComponentGetValue2, ComponentSetValue2
local state = component(orb, "VariableStorageComponent", "nh_bfg_state")
-- A projectile already in flight in a 0.42.11 save still has its old native lifetime and explosion.
if not state then return end

local host = component(orb, "VariableStorageComponent", "nh_bfg_host")
local shot = component(orb, "ProjectileComponent")
local shooter = get(shot, "mWhoShot")
local phase = get(state, "name")
local age = get(state, "value_int") + 1
local x, y = EntityGetTransform(orb)
local waveRadius, waveFrames = 200, 24
local types = {"DAMAGE_PROJECTILE", "DAMAGE_FIRE", "DAMAGE_SLICE", "DAMAGE_RADIOACTIVE", "DAMAGE_EXPLOSION"}

local function changePhase(nextPhase)
    set(state, "name", nextPhase)
    set(state, "value_int", 0)
    set(state, "value_string", ",")
end

local function alive(target)
    if not target or target == 0 or not EntityGetIsAlive(target) then return false end
    local model = EntityGetFirstComponent(target, "DamageModelComponent")
    return model and get(model, "hp") > 0
end

local function hostile(target)
    return target ~= shooter and alive(target) and component(target, "GenomeDataComponent")
        and EntityGetHerdRelation(shooter, target) < 40 and GameGetGameEffectCount(target, "CHARM") == 0
end

-- Distances to the near and far edges of the hitbox keep large targets and the centre of the wave hittable.
local function bounds(target)
    local tx, ty = EntityGetFirstHitboxCenter(target)
    local box = EntityGetFirstComponent(target, "HitboxComponent")
    local halfW, halfH = 0, 0
    if box then
        halfW = (get(box, "aabb_max_x") - get(box, "aabb_min_x")) * 0.5
        halfH = (get(box, "aabb_max_y") - get(box, "aabb_min_y")) * 0.5
    end
    local dx, dy = math.abs(tx - x), math.abs(ty - y)
    local nx, ny = math.max(0, dx - halfW), math.max(0, dy - halfH)
    return nx*nx + ny*ny, (dx + halfW)^2 + (dy + halfH)^2, tx, ty
end

local function fiveHits(target, amount, tx, ty)
    for _, kind in ipairs(types) do
        EntityInflictDamage(target, amount, kind, "BFG", "NONE", 0, 0, shooter, tx, ty)
    end
end

local function drawArc(tx, ty, seed)
    local dx, dy = tx - x, ty - y
    local length = math.max(1, math.sqrt(dx*dx + dy*dy))
    local steps = math.ceil(length / 2)
    for i = 0, steps do
        local t = i / steps
        local bend = math.sin(math.pi*t) * (3*math.sin(seed + 15*t) + 1.8*math.sin(37*t - seed))
        GameCreateCosmeticParticle("spark_green", x+t*dx-bend*dy/length, y+t*dy+bend*dx/length,
            1, 0, 0, 0, 0.07, 0.12, true, true, false, false, 0, 0)
    end
end

local function targets(range)
    if shooter == 0 or not EntityGetIsAlive(shooter) then return {} end
    return EntityGetInRadiusWithTag(x, y, range, "mortal") or {}
end

local function discharge(excluded)
    local visible = {}
    for _, target in ipairs(targets(140)) do
        if target ~= excluded and hostile(target) then
            local tx, ty = EntityGetFirstHitboxCenter(target)
            local distance = (tx-x)^2 + (ty-y)^2
            if distance <= 100^2 and not RaytraceSurfaces(x, y, tx, ty) then
                visible[#visible+1] = {id=target, distance=distance, x=tx, y=ty}
            end
        end
    end
    table.sort(visible, function(a,b) return a.distance < b.distance end)
    for i = 1, math.min(3, #visible) do
        local t = visible[i]
        drawArc(t.x, t.y, GameGetFrameNum() + t.id)
        fiveHits(t.id, 0.4, t.x, t.y)
    end
end

local function stopFlight()
    local velocity = component(orb, "VelocityComponent")
    set(velocity, "mVelocity", 0, 0)
    EntitySetComponentIsEnabled(orb, velocity, false)
    EntitySetComponentsWithTagEnabled(orb, "nh_bfg_flight", false)
end

local function startWave()
    changePhase("out")
    EntitySetComponentsWithTagEnabled(orb, "nh_bfg_ring", true)
end

local function wave(from, to)
    local minSq, maxSq = math.min(from,to)^2, math.max(from,to)^2
    local hit = get(state, "value_string")
    for _, target in ipairs(targets(math.max(from,to) + 64)) do
        local key = "," .. target .. ","
        if not hit:find(key, 1, true) and hostile(target) then
            local near, far, tx, ty = bounds(target)
            if near <= maxSq and far >= minSq then
                hit = hit .. target .. ","
                fiveHits(target, 4, tx, ty)
            end
        end
    end
    set(state, "value_string", hit)

    local ring = component(orb, "SpriteComponent", "nh_bfg_ring")
    local scale = math.max(to / waveRadius, 0.005)
    set(ring, "special_scale_x", scale)
    set(ring, "special_scale_y", scale)
    set(ring, "alpha", phase == "in" and 1 or 0.78)
    EntityRefreshSprite(orb, ring)
    if age % 3 == 0 then
        local speed = phase == "in" and -65 or 45
        for i = 1, 12 do
            local theta = i * math.pi / 6 + age * 0.43
            local dx, dy = math.cos(theta), math.sin(theta)
            GameCreateCosmeticParticle("spark_green", x+dx*to, y+dy*to, 1, dx*speed, dy*speed, 0,
                0.12, 0.23, true, true, false, false, 0, 0)
        end
    end
end

set(state, "value_int", age)
if phase == "flight" then
    if age > 1 then
        local px, py = get(state, "value_float"), get(host, "value_float")
        -- The previous frame's eater has cleared this short segment unless the material resisted it.
        if RaytraceSurfaces(px, py, x, y) then
            stopFlight()
            EntitySetTransform(orb, px, py)
            startWave()
            return
        end
    end
    set(state, "value_float", x)
    set(host, "value_float", y)
    local nearest, distance = nil, 12^2
    for _, target in ipairs(targets(76)) do
        if hostile(target) then
            local near = bounds(target)
            if near <= distance then nearest, distance = target, near end
        end
    end
    if nearest then
        local tx, ty = EntityGetTransform(nearest)
        stopFlight()
        set(host, "value_int", nearest)
        set(state, "value_float", x-tx)
        set(host, "value_float", y-ty)
        changePhase("attached")
    elseif age >= 150 then
        stopFlight()
        startWave()
    elseif age % 12 == 0 then
        discharge(nil)
    end
elseif phase == "attached" then
    local target = get(host, "value_int")
    if not alive(target) then startWave() return end
    local tx, ty = EntityGetTransform(target)
    x, y = tx + get(state, "value_float"), ty + get(host, "value_float")
    EntitySetTransform(orb, x, y)
    if age % 12 == 0 then
        EntityInflictDamage(target, 2, "DAMAGE_ELECTRICITY", "BFG", "NONE", 0, 0, shooter, x, y)
        discharge(target)
    end
    if age >= 72 or not alive(target) then startWave() end
elseif phase == "out" or phase == "in" then
    local step = waveRadius / waveFrames
    local from = phase == "out" and (age-1)*step or waveRadius-(age-1)*step
    local to = phase == "out" and age*step or waveRadius-age*step
    wave(from, to)
    if age == waveFrames then
        if phase == "out" then
            changePhase("in")
        else
            changePhase("spent")
            set(shot, "on_lifetime_out_explode", true)
            set(shot, "on_death_explode", true)
            set(shot, "lifetime", 1)
        end
    end
end
