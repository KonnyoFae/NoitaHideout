-- Add a stable id, duration in simulation frames, and a retry chance (0 < q <= 1)
-- for each affected event and category. Leave unaffected categories out.
-- Call loot_bonuses.activate(player, id) on successful use by the local player.
-- Reusing an id refreshes it. EW mirrors the timer to the enemy's simulator.
-- Other reward producers can query rerolls(player, event) under their own event.
return {
    {id="salvage_bell",duration=15*60*60,tag="nh_salvage_bell",
        events={enemy_kill={bag=0.25,tarot=0.25,red=0.25}}},
}
