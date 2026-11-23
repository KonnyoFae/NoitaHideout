-- In both vanilla altar scenes the terminal sits on the flat brick ledge
-- between the entrance pool and the shop. Its coordinates follow the room,
-- including when the altar is generated in a parallel world.
local storage={}
local terminal=dofile("mods/noita_hideout/files/terminals/station.lua")
local station
local tag="noita_hideout_mountain_storage"

function storage.reset()
    station=nil
end

function storage.update(player,ax,ay)
    local x,y
    if ax then
        x,y=ax-18,ay+84
    else
        local px,py=EntityGetTransform(player)
        -- Streamed or continued saves can retain the locker after losing both anchors.
        local existing=(EntityGetInRadiusWithTag(px,py,48,tag) or {})[1]
        if existing then station=existing; terminal.upgrade(station); return end
        -- The secret altar uses the same layout but has no workshop_aabb.
        -- Its permanent co-op respawn marker sits between the two pickups.
        for _,anchor in ipairs(EntityGetInRadiusWithTag(px,py,224,"coop_respawn") or {}) do
            local hx,hy=EntityGetTransform(anchor)
            if BiomeMapGetName(hx,hy)=="$biome_holymountain" then
                x,y=hx+104,hy+34
                break
            end
        end
        if not x then return end
    end
    if station and EntityGetIsAlive(station) then
        local sx,sy=EntityGetTransform(station)
        if sx==x and sy==y then terminal.upgrade(station); return end
    end
    if not DoesWorldExistAt(x-9,y-6,x+9,y+7) then return end
    station=(EntityGetInRadiusWithTag(x,y,1,tag) or {})[1]
    if not station then
        local id=EntityLoad("mods/noita_hideout/files/mountain_storage.xml",x,y)
        if id and id~=0 then station=id end
    end
    if station then terminal.upgrade(station) end
end

function storage.inRange(player,x,y)
    if not station or not EntityGetIsAlive(station) then return false end
    if not x then x,y=EntityGetTransform(player) end
    local sx,sy=EntityGetTransform(station)
    return (x-sx)^2+(y-sy)^2<=48^2
end

return storage
