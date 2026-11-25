local freeze=dofile_once("mods/noita_hideout/files/stasis.lua")

-- A shared LuaComponent VM can initialize through either update or pickup.
-- Define its message handler in the update entry point too: old saves still
-- name hourglass_pickup.lua in script_item_picked_up, while new components use
-- this same file for both callbacks.
function item_pickup(item)
    item=item or GetUpdatedEntityID()
    if item and item~=0 then freeze.release(item,true) end
end

local entity=GetUpdatedEntityID()
if entity and entity~=0 and EntityGetIsAlive(entity) then freeze.checkTarget(entity) end
