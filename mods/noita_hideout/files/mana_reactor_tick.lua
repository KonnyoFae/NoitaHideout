local frame=GameGetFrameNum()
-- On load the instance VM starts fresh. Thereafter do equipment work every
-- six frames, with one earlier wakeup if the absolute deadline falls between.
if not nh_reactor_next or frame>=nh_reactor_next then
    local child=GetUpdatedEntityID()
    if not nh_reactor_next then
        -- An effect already active in an older save still points at the hotbar art.
        local icon=EntityGetFirstComponentIncludingDisabled(child,"UIIconComponent")
        local items="mods/noita_hideout/files/items/"
        if icon and ComponentGetValue2(icon,"icon_sprite_file")==items.."mana_reactor_icon.png" then
            ComponentSetValue2(icon,"icon_sprite_file",items.."mana_reactor_status.png")
        end
    end
    nh_reactor_next=dofile_once("mods/noita_hideout/files/mana_reactor.lua").update(child,frame)
end
