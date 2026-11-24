NHBank={}
local ew=NHEW or dofile("mods/noita_hideout/files/ew.lua")
local sharedWallet="Wallet transfers are unavailable with shared gold."

-- money is int64 in Noita, while a Lua number can only represent integers
-- exactly up to maxGold. An infinite wallet replenishes itself after debits.
function NHBank.wallet(player)
    local wallet=EntityGetFirstComponentIncludingDisabled(player,"WalletComponent")
    if not wallet or wallet==0 then return end
    if ComponentGetValue2(wallet,"mHasReachedInf") then return nil,true end
    local money=ComponentGetValue2(wallet,"money")
    if type(money)=="number" and money>=0 and money<=NHStore.maxGold and money==math.floor(money) then
        return money,false,wallet
    end
end

-- Commit both the savings and the corresponding change owed to this run's
-- wallet in one profile revision. Ordinary shop debits only affect savings.
function NHBank.prepare(draft,player,request)
    if not ew.walletAllowed() then return nil,sharedWallet end
    local deposit=request.direction=="deposit"
    if not deposit and request.direction~="withdraw" then return nil,"Invalid gold transfer." end
    local money=NHBank.wallet(player)
    if not money then return nil,"Wallet unavailable." end
    local amount=request.amount
    if amount=="all" then amount=deposit and money or draft.bankGold end
    if type(amount)~="number" or amount<1 or amount>NHStore.maxGold or amount~=math.floor(amount) then
        return nil,"Invalid gold amount."
    end
    if deposit and amount>money then return nil,"Not enough carried gold." end
    if not deposit and amount>NHStore.maxGold-money then return nil,"Wallet is full." end
    local net=draft.bankWalletNet
    if (deposit and net < -NHStore.maxGold+amount) or (not deposit and net > NHStore.maxGold-amount) then
        return nil,"Gold transfer exceeds the exact integer range."
    end
    local change=deposit and NHStore.creditGold or NHStore.spendGold
    local ok,reason=change(draft,amount)
    if not ok then return nil,reason end
    draft.bankWalletNet=net+(deposit and -amount or amount)
    return amount
end

local function writeReceipt(key,value)
    pcall(GlobalsSetValue,key,value)
    return GlobalsGetValue(key,"0")==value
end

-- The world saves the applied net alongside the native wallet. Replaying an
-- earlier world applies just the missing difference, retaining pickups and
-- purchases. A new run starts a new ledger and keeps the profile savings.
function NHBank.reconcile(state,player)
    -- The receipt belongs to the private wallet, including after a reload.
    -- Leave both sides of a prepared transfer intact until that wallet returns.
    if not ew.walletAllowed() then return false,sharedWallet end
    local key="noita_hideout.bank_wallet."..state.profile.."/"..state.runSerial
    local receipt=GlobalsGetValue(key,"0")
    local old,planned,before=receipt:match("^(-?%d+)/(-?%d+)/(%d+)$")
    local applied=tonumber(old or receipt)
    if not applied or not (math.abs(applied)<=NHStore.maxGold and applied==math.floor(applied)) then
        return false,"Invalid wallet receipt."
    end
    local target=state.bankWalletNet
    if not planned and applied==target then return true end
    local money,_,wallet=NHBank.wallet(player)
    if not wallet then return false,"Wallet unavailable." end
    if planned then
        planned,before=tonumber(planned),tonumber(before)
        if math.abs(planned)>NHStore.maxGold or before>NHStore.maxGold then return false,"Invalid wallet receipt." end
    else
        local delta=math.max(-money,math.min(NHStore.maxGold-money,target-applied))
        if delta==0 then return false,"Waiting for wallet settlement." end
        planned,before=applied+delta,money
        -- A prepared receipt also survives a failed rollback of either write.
        local pending=string.format("%.0f/%.0f/%.0f",applied,planned,before)
        if not writeReceipt(key,pending) then return false,"Could not record the wallet transfer." end
    end
    local after=before+(planned-applied)
    if after<0 or after>NHStore.maxGold then return false,"Invalid wallet receipt." end
    if money==before then
        pcall(ComponentSetValue2,wallet,"money",after)
        money=ComponentGetValue2(wallet,"money")
    end
    if money~=after then
        if money==before then writeReceipt(key,string.format("%.0f",applied)) end
        return false,"Could not update the wallet."
    end
    if not writeReceipt(key,string.format("%.0f",planned)) then
        -- Restore the pre-transfer pair while still inside this callback. If
        -- either setter stays blocked, the prepared receipt can finish on reload.
        pcall(ComponentSetValue2,wallet,"money",before)
        if ComponentGetValue2(wallet,"money")==before then writeReceipt(key,string.format("%.0f",applied)) end
        return false,"Could not record the wallet transfer."
    end
    if planned~=target then return false,"Waiting for wallet settlement." end
    return true
end
