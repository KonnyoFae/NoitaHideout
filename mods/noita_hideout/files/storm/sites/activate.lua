local stations=dofile_once("mods/noita_hideout/files/storm/sites/stations.lua")
function interacting(player,rig)
    stations.activate(player,rig)
end
