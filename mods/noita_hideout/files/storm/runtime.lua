local root = "mods/noita_hideout/files/storm/"
local weather = dofile(root .. "weather.lua")
local draw_cycle = dofile(root .. "hud.lua")
local stations = dofile(root .. "sites/stations.lua")
local airship = dofile(root .. "sites/airship.lua")
local locations = dofile(root .. "sites/locations.lua")
local phase, elapsed, age

local function update()
    phase, elapsed, age = weather.update()
    if phase then
        local retiringShips = airship.service(phase, age)
        local expiringStations = stations.update(phase, age, retiringShips)
        if phase == 4 and not retiringShips and not expiringStations then airship.arrive() end
        if phase == 4 and (elapsed == 0 or GameGetFrameNum() % 60 == 0) then
            return GameGetFrameNum() - age
        end
    end
end

local function draw()
    if phase then draw_cycle(weather, phase, elapsed, age, stations, locations) end
end

return {update = update, draw = draw}
