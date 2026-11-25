-- The engine gives each dart its own VM. The on-added tick records the muzzle
-- position before GameShootProjectile gives the spawned entity a velocity.
dart_flight = dart_flight or {}
dofile_once("mods/noita_hideout/files/projectiles/smart_dart.lua").update(GetUpdatedEntityID(), dart_flight)
