local weatherPath = "mods/noita_hideout/files/storm/weather.lua"
local frame, exposure = 0, 0
local light, heavy = "cycle_storm_rain_loop", "cycle_storm_downpour_loop"
local components = {[light] = {event_name = "materials/liquid_flow"}}
local gain = {}
local replacements, creates = 0, 0
local schedule = "0,77"
function GameIsIntroPlaying() return false end
function GameGetFrameNum() return frame end
function GlobalsGetValue() return schedule end
function GlobalsSetValue(_, value) schedule = value end
function GameGetCameraPos() return 0, 4200 end
function GameGetSkyVisibility() return exposure end
function GameGetWorldStateEntity() return 1 end
function EntityGetWithTag() return {2} end
function EntityGetIsAlive(id) return id == 2 end
function EntityGetFirstComponentIncludingDisabled(_, kind, tag)
    if kind == "WorldStateComponent" then return 1 end
    return components[tag]
end
function ComponentSetValue2() end
function ComponentGetValue2(c, k) return c[k] end
function EntityRemoveComponent(_, c)
    assert(c == components[light] and c.event_name == "materials/liquid_flow")
    replacements, components[light] = replacements + 1, nil
end
function EntityAddComponent2(_, _, data)
    local name = data._tags == light and "drizzle" or "downpour"
    assert(not components[data._tags] and data.event_name == "cycle_storm/" .. name)
    assert(data.file == "mods/noita_hideout/files/storm/audio/cycle_storm_" .. name .. ".bank")
    local bank = assert(io.open(data.file, "rb"))
    assert(bank:read(4) == "RIFF")
    bank:close()
    assert(data.calculate_material_lowpass == false)
    creates, components[data._tags] = creates + 1, data
end
function GameEntityPlaySoundLoop(_, tag, intensity)
    assert(components[tag] and intensity > 0 and intensity <= 1)
    gain[tag] = intensity
end
function GamePlaySound(_, event)
    assert(event == "player_projectiles/bullet_lightning/create")
end
local visual
function GameSetPostFxParameter(_, _, _, rain) visual = rain end
function GameEmitRainParticles() error("Physical rain emitted") end

local weather = dofile(weatherPath)
for i=0,72000 do
    frame = i
    if i == 54012 then exposure = 1 end
    if i == 63000 then weather = dofile(weatherPath) end
    gain = {}
    local phase = weather.update()
    if phase == 1 then assert(visual == 0 and not next(gain))
    else assert(next(gain)) end
    if phase == 2 then assert(gain[light] and not gain[heavy]) end
    if i == 45000 then assert(gain[light] and gain[heavy]) end
    if i == 54000 then assert(visual == 1 and not gain[light] and math.abs(gain[heavy] - 0.9) < 0.001) end
    if i == 54012 then assert(visual == 1 and gain[heavy] == 1) end
    if i == 64860 then assert(gain[heavy] and gain[light]) end
    if i == 71999 then assert(not gain[heavy] and gain[light] < 0.01) end
end
assert(creates == 2 and replacements == 1)
-- The real weather clock supplies the mothership with the same round ID throughout a core.
local runtimeFile=assert(loadfile("mods/noita_hideout/files/storm/runtime.lua"))
local shipsRetiring,stationsExpiring,events
local environment=setmetatable({dofile=function(path)
    if path==weatherPath then return dofile(path) end
    if path:match("/airship.lua$") then return {
        service=function() events[#events+1]="retire"; return shipsRetiring end,
        arrive=function() events[#events+1]="airship" end,
    } end
    if path:match("/stations.lua$") then return {update=function(_,__,blocked)
        assert(blocked==shipsRetiring)
        events[#events+1]="stations"
        return stationsExpiring
    end} end
    return {update=function() end}
end},{__index=_G})
local storm=setfenv(runtimeFile,environment)()
for _,sample in ipairs({{125999,false},{126000,72000},{126060,72000},
    {136800,false},{198000,144000}}) do
    frame=sample[1]
    events={}; shipsRetiring=frame==126000; stationsExpiring=frame==126060
    assert((storm.update() or false)==sample[2])
    assert(table.concat(events,",")==(frame==198000 and "retire,stations,airship" or "retire,stations"))
end
print("Global rain: dry phase, underground drizzle, storm audio, surface transition, old loop migration and reload passed.")
