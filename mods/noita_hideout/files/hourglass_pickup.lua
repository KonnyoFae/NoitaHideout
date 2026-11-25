function item_pickup(item)
    item=item or GetUpdatedEntityID()
    if item and item~=0 then dofile_once("mods/noita_hideout/files/stasis.lua").release(item,true) end
end
