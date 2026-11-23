ModLuaFileAppend("data/scripts/init.lua", "mods/noita_hideout/files/storm/disable_vanilla_weather.lua")
ModRegisterAudioEventMappings("mods/noita_hideout/files/storm/audio/events.txt")
local shader_path = "data/shaders/post_final.frag"
local shader = ModTextFileGetContent(shader_path)
local uniform_anchor = "uniform float night_amount;"
local lighting_anchor = "// apply the lighting to the foreground"
local rain_anchor = "// damage flash effect"
if shader and shader:find("vec2 cycleStormStreak(", 1, true) then return end
if shader and shader:find(uniform_anchor, 1, true) and shader:find(lighting_anchor, 1, true)
    and shader:find(rain_anchor, 1, true) then
    -- Return translucent body coverage and a shorter reflection at the leading end.
    local declarations = [[
uniform vec4 cycle_storm_light;
vec2 cycleStormStreak(vec2 position, vec2 spacing, float halfLength, float width, float coverage) {
    vec2 grid = position / spacing;
    vec2 cell = mod(floor(grid), 1024.0);
    vec3 h = fract(cell.xyx * vec3(0.1031, 0.1030, 0.0973));
    h += dot(h, h.yzx + 33.33);
    vec3 jitter = fract((h.xxy + h.yzz) * h.zyx);
    vec2 drop = (fract(grid) - mix(vec2(0.26), vec2(0.74), jitter.xy)) * spacing;
    float along = drop.y / (halfLength * mix(0.72, 1.0, jitter.x));
    float taper = 1.0 - smoothstep(0.48, 1.0, abs(along));
    float edge = 1.0 - smoothstep(0.0, width, abs(drop.x));
    float body = edge * taper * step(jitter.z, coverage);
    float glint = body * edge * (1.0 - smoothstep(0.0, 0.42, abs(along - 0.42)));
    return vec2(body, glint);
}
]]
    shader = shader:gsub(uniform_anchor, uniform_anchor .. "\n" .. declarations, 1)
    local lighting = [[
    if (cycle_storm_light.x > 0.0) {
        float darkness = cycle_storm_light.x;
        float flash = cycle_storm_light.y;
        vec2 offset = (tex_coord - vec2(0.5)) * world_viewport_size;
        float distant = smoothstep(32.0, 120.0, length(offset));
        float shade = darkness * mix(0.25, 0.92, distant);
        lights *= 1.0 - shade;
        color *= mix(vec3(1.0 - shade), vec3(1.1, 1.2, 1.4), flash);
        lights += fog_of_war * vec3(0.70, 0.80, 1.0) * flash;
    }

]]
    shader = shader:gsub(lighting_anchor, lighting .. lighting_anchor, 1)
    local foreground = [[
    if (cycle_storm_light.z > 0.0) {
        float wet = sqrt(cycle_storm_light.z);
        vec2 farPos = vec2(world_pos.x - world_pos.y * 0.10, world_pos.y - time * 155.0);
        vec2 nearPos = vec2(world_pos.x - world_pos.y * 0.16 + 57.0, world_pos.y - time * 245.0);
        vec2 farRain = cycleStormStreak(farPos, vec2(11.0, 62.0), 11.0, 0.62, wet);
        vec2 nearRain = cycleStormStreak(nearPos, vec2(19.0, 96.0), 21.0, 0.86, wet * 0.82);
        float sceneLight = clamp(dot(color, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
        float stormTransmission = 1.0 - 0.35 * cycle_storm_light.x;
        vec3 glass = color * 0.78 + vec3(0.12, 0.16, 0.20);
        float opacity = (farRain.x * 0.20 + nearRain.x * 0.34) * stormTransmission;
        color = mix(color, glass, opacity);
        float reflection = (0.15 + sceneLight * 0.34) * stormTransmission + cycle_storm_light.y * 0.26;
        float gleam = (farRain.y * 0.20 + nearRain.y * 0.40) * reflection;
        color = mix(color, vec3(0.72, 0.77, 0.82), gleam);
    }
]]
    shader = shader:gsub(rain_anchor, foreground .. rain_anchor, 1)
    ModTextFileSetContent(shader_path, shader)
else
    print("[Cycle Storm] Shader hooks missing; weather audio and timing remain active.")
end
