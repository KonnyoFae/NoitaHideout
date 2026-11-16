function damage_received(damage)
    -- The controller checks this listener after the simulation step. A later
    -- heal in the same frame cannot hide a hit, and healing alone never cancels.
    if damage>0 then EntitySetComponentIsEnabled(GetUpdatedEntityID(),GetUpdatedComponentID(),false) end
end
