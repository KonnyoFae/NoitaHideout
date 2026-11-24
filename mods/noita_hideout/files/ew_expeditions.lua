-- Only transient expedition data changes on switching worlds. Warehouse
-- rows, money, buildings and the item ID sequence stay on the local profile.
local M={}
local fields={"runSerial","closedThrough","bankWalletNet","checkpoints","transit","issuedDoses","giftRun","giftFrame",
    "ewReinforcePending","ewReinforceSponsors","ewDepositPending","ewDepositReceipt","ewDepositHistory"}
function M.select(s,scope)
    if s.ewActive==scope then return false end
    local slots=s.ewExpeditions or {}
    local parked={bags={}}
    for _,key in ipairs(fields) do parked[key]=s[key] end
    for id,pouch in pairs(s.pouches) do
        if pouch.location=="bag" then parked.bags[id]=pouch; s.pouches[id]=nil end
    end
    slots[s.ewActive or "single"]=parked
    local key=scope or "single"
    local nextRun=slots[key]
    if not nextRun then
        local serial=math.max(s.ewSerial or 0,s.runSerial)+1
        s.ewSerial=serial
        nextRun={runSerial=serial,closedThrough=serial-1,bankWalletNet=0,checkpoints={}}
    end
    for _,field in ipairs(fields) do s[field]=nextRun[field] end
    for id,pouch in pairs(nextRun.bags or {}) do
        assert(not s.pouches[id],"Carried pouch ID already in use")
        s.pouches[id]=pouch
    end
    slots[key]=nil
    s.ewActive,s.ewExpeditions=scope,slots
    return true
end
return M
