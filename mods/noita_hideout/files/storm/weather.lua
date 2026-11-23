local fps = 60
local calm_frames = 300 * fps
local light_frames = 300 * fps
local heavy_frames = 300 * fps
local storm_frames = 180 * fps
local clearing_frames = 120 * fps
local cycle_frames = calm_frames + light_frames + heavy_frames + storm_frames + clearing_frames
local phases = {
    { frames = calm_frames, zh = "平静", en = "Calm" },
    { frames = light_frames, zh = "小雨", en = "Drizzle" },
    { frames = heavy_frames, zh = "大雨", en = "Rain" },
    { frames = storm_frames, zh = "风暴", en = "Storm" },
    { frames = clearing_frames, zh = "退场", en = "Easing" },
}
local key = "cycle_storm.schedule.v3"
local cycle_start, seed
local previous_frame, previous_sky_level, previous_darkness, previous_flash, previous_rain
local sound_player, next_audio_sample, exposure
local drizzle_tag = "cycle_storm_rain_loop"
local downpour_tag = "cycle_storm_downpour_loop"

local function ensure_rain_loop(player, tag, name)
    local bank = "mods/noita_hideout/files/storm/audio/cycle_storm_" .. name .. ".bank"
    local event = "cycle_storm/" .. name
    local loop = EntityGetFirstComponentIncludingDisabled(player, "AudioLoopComponent", tag)
    if loop then
        if ComponentGetValue2(loop, "event_name") == event and ComponentGetValue2(loop, "file") == bank then return end
        -- The drizzle tag also identifies the old water loop in existing saves.
        EntityRemoveComponent(player, loop)
    end
    EntityAddComponent2(player, "AudioLoopComponent", {
        _tags = tag,
        file = bank,
        event_name = event,
        calculate_material_lowpass = false,
        volume_autofade_speed = 0.1,
    })
end

local function advance_seed(value)
    return (value * 48271) % 2147483647
end

local function save_schedule()
    GlobalsSetValue(key, string.format("%d,%d", cycle_start, seed))
end

local function read_schedule(name, frame)
    local start, state = GlobalsGetValue(name, ""):match("^(-?%d+),(%d+)$")
    start, state = tonumber(start), tonumber(state)
    if start and start <= frame and state >= 1 and state < 2147483647 then
        return start, state
    end
end

local function load_schedule(frame)
    cycle_start, seed = read_schedule(key, frame)
    if cycle_start then return end

    cycle_start, seed = read_schedule("cycle_storm.schedule.v2", frame)
    local old_calm, old_rain = 300 * fps, 450 * fps
    if not cycle_start then
        cycle_start, seed = read_schedule("cycle_storm.schedule.v1", frame)
        if seed then
            old_calm, old_rain = (300 + seed % 301) * fps, 300 * fps
        end
    end
    if cycle_start then
        -- Keep the current phase and its relative progress when updating an old run.
        local old_lengths = { old_calm, old_rain, old_rain, storm_frames, clearing_frames }
        local new_lengths = { calm_frames, light_frames, heavy_frames, storm_frames, clearing_frames }
        local age = frame - cycle_start
        for i, old_length in ipairs(old_lengths) do
            if age < old_length then
                cycle_start = cycle_start + age - math.floor(age * new_lengths[i] / old_length)
                break
            end
            cycle_start = cycle_start + old_length - new_lengths[i]
            age = age - old_length
        end
    else
        local year, month, day, hour, minute, second = GameGetDateAndTimeUTC()
        local stamp = ((((year * 12 + month) * 31 + day) * 24 + hour) * 60 + minute) * 60 + second
        seed = advance_seed(1 + (stamp + math.floor(GameGetRealWorldTimeSinceStarted() * 1000)) % 2147483646)
        cycle_start = frame
    end
    save_schedule()
end

local function update_sky(strength)
    local level = math.floor(strength * 64 + 0.5)
    if level == previous_sky_level then return end
    local state = EntityGetFirstComponentIncludingDisabled(GameGetWorldStateEntity(), "WorldStateComponent")
    if not state then return end
    ComponentSetValue2(state, "fog_target_extra", level / 64 * 0.72)
    ComponentSetValue2(state, "rain_target_extra", level / 64 * 0.95)
    previous_sky_level = level
end

local function storm_flash(elapsed)
    -- One distant flash per ten-second window. Its offset is stable across saves.
    local window = 10 * fps
    local slot = math.floor(elapsed / window)
    local offset = fps + advance_seed(seed + slot * 137) % (6 * fps)
    local age = elapsed % window - offset
    if age == 28 then
        local x, y = GameGetCameraPos()
        GamePlaySound("data/audio/Desktop/projectiles.bank", "player_projectiles/bullet_lightning/create", x, y)
    end
    if age < 0 or age >= 18 then return 0 end
    return math.min(1, (age + 1) / 3) * (1 - age / 18)
end

local function update_rain_sound(frame, rain)
    if rain <= 0 then
        next_audio_sample = nil
        return
    end
    if not next_audio_sample or frame >= next_audio_sample then
        local x, y = GameGetCameraPos()
        exposure = math.max(0, math.min(1, GameGetSkyVisibility(x, y)))
        local players = EntityGetWithTag("player_unit")
        sound_player = players and players[1]
        if sound_player then
            ensure_rain_loop(sound_player, drizzle_tag, "drizzle")
            ensure_rain_loop(sound_player, downpour_tag, "downpour")
        end
        next_audio_sample = frame + 12
    end
    if sound_player and EntityGetIsAlive(sound_player) then
        local gain = 0.90 + 0.10 * exposure
        local blend = math.max(0, (rain - 0.375) / 0.625)
        local drizzle = math.sqrt(math.min(1, rain / 0.375)) * (1 - blend)
        if drizzle > 0 then
            GameEntityPlaySoundLoop(sound_player, drizzle_tag, 0.48 * drizzle * gain, 0)
        end
        if blend > 0 then
            GameEntityPlaySoundLoop(sound_player, downpour_tag, blend * gain, 0)
        end
    end
end

local function update()
    if GameIsIntroPlaying() then return end
    local frame = GameGetFrameNum()
    if frame == previous_frame then return end
    if not cycle_start or (previous_frame and frame < previous_frame) then
        load_schedule(frame)
        previous_sky_level, previous_darkness, previous_flash, previous_rain = nil, nil, nil, nil
        next_audio_sample = nil
    end
    previous_frame = frame

    while frame >= cycle_start + cycle_frames do
        cycle_start = cycle_start + cycle_frames
        seed = advance_seed(seed)
        save_schedule()
    end

    local age = frame - cycle_start
    local phase, elapsed = 1, age
    while elapsed >= phases[phase].frames do
        elapsed = elapsed - phases[phase].frames
        phase = phase + 1
    end
    local rain, darkness, flash = 0, 0, 0
    if phase == 2 then
        rain = 0.03 + 0.345 * elapsed / light_frames
    elseif phase == 3 then
        rain = 0.375 + 0.625 * elapsed / heavy_frames
    elseif phase == 4 then
        rain = 1
        darkness = math.min(1, elapsed / (3 * fps))
        flash = storm_flash(elapsed)
    elseif phase == 5 then
        local transition = math.max(0, 1 - elapsed / (5 * fps))
        rain = 0.25 * (1 - elapsed / clearing_frames) + 0.75 * transition
        darkness = transition
    end

    update_sky(rain)
    update_rain_sound(frame, rain)
    local visual_rain = math.floor(rain * 256 + 0.5) / 256
    if darkness ~= previous_darkness or flash ~= previous_flash or visual_rain ~= previous_rain then
        GameSetPostFxParameter("cycle_storm_light", darkness, flash, visual_rain, 0)
        previous_darkness, previous_flash, previous_rain = darkness, flash, visual_rain
    end
    return phase, elapsed, age
end

return { update = update, phases = phases, frames = cycle_frames, fps = fps }
