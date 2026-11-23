dofile_once("mods/noita_hideout/files/companions/behavior.lua")
local pet=GetUpdatedEntityID()
-- Companions already serialized in an older world retain the original six-frame script.
if not EntityGetFirstComponentIncludingDisabled(pet,"LuaComponent","nh_companion_display") then
    EntityAddComponent2(pet,"LuaComponent",{_tags="nh_companion_display",execute_every_n_frame=1,
        script_source_file="mods/noita_hideout/files/companions/display.lua",vm_type="ONE_PER_COMPONENT_INSTANCE"})
end
NHCompanions.update(pet)
