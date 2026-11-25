function damage_received(damage)
    dofile_once("mods/noita_hideout/files/dart_status.lua").damaged(GetUpdatedEntityID(),damage)
end
