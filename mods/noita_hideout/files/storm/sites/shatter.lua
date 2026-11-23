local stations=dofile_once("mods/noita_hideout/files/storm/sites/stations.lua")
function damage_received(damage)
    if damage>0 then stations.shatter(GetUpdatedEntityID()) end
end
