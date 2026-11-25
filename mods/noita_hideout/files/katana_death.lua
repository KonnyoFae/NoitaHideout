function death(damage_type,message,responsible,drop_items)
    -- A hostile summon is still an enemy. Ordinary loot eligibility is not a
    -- prerequisite for the guaranteed three-part Zandatsu reward.
    dofile_once("mods/noita_hideout/files/katana_rewards.lua").death(GetUpdatedEntityID(),message,responsible)
end
