local airship=dofile_once("mods/noita_hideout/files/storm/sites/airship.lua")
function interacting(player,safe)
    airship.open(player,safe)
end
