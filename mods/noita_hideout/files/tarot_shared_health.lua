local M = {}

-- EW already reconciles ordinary healing from the local DamageModel. Only
-- the Devil's half-health floor needs to be evaluated against the shared pool.
function M.change(player, kind, steps)
    if kind ~= "devil_tick" or not ModIsEnabled or not ModIsEnabled("quant.ew")
        or GlobalsGetValue("nh_ew.tarot_shared_health", "") ~= "1" then return false end
    if CrossCall then CrossCall("ew_hideout_tarot_drain", player, steps or 1) end
    return true
end

return M
