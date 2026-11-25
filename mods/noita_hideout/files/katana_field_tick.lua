local fresh=not nh_katana_field_started
nh_katana_field_started=true
dofile_once("mods/noita_hideout/files/katana_field.lua").tick(GetUpdatedEntityID(),fresh)
