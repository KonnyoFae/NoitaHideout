local remote=dofile("mods/noita_hideout/files/terminals/remote.lua")
local id=GetUpdatedEntityID()
if not remote.expire(id) then
    dofile("mods/noita_hideout/files/terminals/field.lua").update(id,remote.radius)
end
