-- This component keeps its own VM between ticks. Loading the saved entity
-- starts a fresh VM, so recapture any enemies rebuilt from native templates.
local first=not nh_hourglass_started
nh_hourglass_started=true
dofile_once("mods/noita_hideout/files/hourglass_field.lua").tick(GetUpdatedEntityID(),first)
