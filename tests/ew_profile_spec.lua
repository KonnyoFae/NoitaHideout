local settings,world,flags={},{},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
function GlobalsGetValue(k,d) return world[k] or d end
function GlobalsSetValue(k,v) world[k]=v end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
local scopes=dofile("mods/noita_hideout/files/ew_expeditions.lua")
local s=assert(NHStore.load())
NHStore.newRun(s)
local bag=s.pouches[s.starterPouchId]
bag.location,bag.token="bag","old-solo-bag"
s.checkpoints["solo-station"]=true
s.bankWalletNet,s.bankGold=-35,35
assert(NHStore.commit(s))
local function enter(id)
    s=assert(NHStore.load())
    assert(scopes.select(s,id))
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
    assert(not scopes.select(s,id))
end
enter("host-A")
local runA=s.runSerial
assert(s.bankGold==35 and s.bankWalletNet==0 and not next(s.checkpoints) and not s.pouches[bag.id])
s.bankGold,s.bankWalletNet=40,-5
s.checkpoints.A=true
local id=NHPouches.create(s,"bag",1,1)
s.pouches[id].token="A-bag"
assert(NHStore.commit(s))
enter("host-B")
assert(s.runSerial~=runA and s.bankGold==40 and s.bankWalletNet==0 and not s.pouches[id])
s.checkpoints.B=true
assert(NHStore.commit(s))
enter("host-A")
assert(s.runSerial==runA and s.bankGold==40 and s.bankWalletNet==-5 and s.checkpoints.A and not s.checkpoints.B)
assert(s.pouches[id].token=="A-bag")
enter(nil)
assert(s.runSerial==1 and s.closedThrough==0 and s.bankGold==40 and s.bankWalletNet==-35 and s.checkpoints["solo-station"])
assert(s.pouches[bag.id].token=="old-solo-bag" and not s.pouches[id])
-- A new vanilla run still closes the previous solo run, leaving the
-- suspended cooperative session intact.
assert(NHStore.newRun(s)==2 and NHStore.commit(s))
enter("host-A")
assert(s.runSerial==runA and s.pouches[id].token=="A-bag")

local frame,online=120,true
function GameGetFrameNum() return frame end
function ModIsEnabled(id) return online and id=="quant.ew" end
function GameGetDateAndTimeLocal() return 2026,1,1,0,0,0 end
function GameGetRealWorldTimeSinceStarted() return 1.234567 end
function SessionNumbersGetValue() return "0" end
NHEW=nil
local ew=dofile("mods/noita_hideout/files/ew.lua")
world["nh_ew.local_peer"]="0000000000000001"
local owner=assert(ew.bind(1))
assert(not ew.ready() and not ew.walletAllowed())
world["nh_ew.world_mark"]="host-A"
world["nh_ew.status"]="1|host-A|0|g|0|120"
frame=121
assert(ew.world()=="host-A" and ew.walletAllowed() and not ew.rescueAllowed())
-- The cross-VM reply slot may itself have been restored from the world save.
-- Its contents count only if the current synchronous lookup wrote them.
do
    local field,key="nh_ew.release_winner","t/ew/Guest/r/1/2/3/4/5/6"
    world[field]="Guest|42"
    function CrossCall(name,w,h,k)
        assert(name=="ew_hideout_release_winner" and w=="host-A" and h==owner and k==key)
    end
    assert(not ew.releaseWinner("host-A",owner,key) and world[field]=="")
    function CrossCall() GlobalsSetValue(field,"Guest|45") end
    local winner,tx=ew.releaseWinner("host-A",owner,key)
    assert(winner=="Guest" and tx=="45" and world[field]=="")
    assert(not ew.releaseWinner("host-B",owner,key) and not ew.releaseWinner("host-A","Other",key))
    CrossCall=nil
end
local testTags={[2]="nh_ew_waiting",[3]="ew_client",[4]="ew_notplayer"}
function EntityHasTag(id,name) return testTags[id]==name end
assert(ew.localBody(1) and not ew.localBody(2) and not ew.localBody(3) and not ew.localBody(4))
local itemKeys={"g/18446744073709551615"}
local request="host-A|"..owner.."|12|"..itemKeys[1].."|"
world["nh_ew.item_tx_reply"]=request.."granted" -- stale saved world
assert(ew.itemTransaction(12,"prepare",itemKeys)==nil)
assert(world["nh_ew.item_request"]==request.."prepare" and world["nh_ew.item_tx_reply"]=="")
world["nh_ew.item_tx_reply"]=request.."granted"
assert(ew.itemTransaction("12","prepare",itemKeys)=="granted")
assert(ew.itemTransaction(12,"commit",itemKeys)==nil and world["nh_ew.item_request"]==request.."commit")
world["nh_ew.item_tx_reply"]=request.."done"
assert(ew.itemTransaction(12,"cancel",itemKeys)=="done")
frame=180
assert(not ew.ready() and not ew.walletAllowed() and ew.itemTransaction(12,"commit",itemKeys)==nil)
world["nh_ew.local_peer"]="0000000000000008"
ew.reset()
assert(ew.bind(1)==owner)
online=false
ew.reset()
assert(ew.enabled() and not ew.ready() and not ew.rescueAllowed())
world={}
ew.reset()
assert(not ew.enabled() and ew.walletAllowed() and ew.rescueAllowed())
print("EW profile: local economy, independent expedition journals, reconnect and solo continuity passed.")

-- Switching host worlds must also suspend an unfinished deposit. Its receipt
-- and old-item cleanup records belong to the same world as the pending item.
local roomState=assert(NHStore.load())
local deposit={tx="34",world="host-A"}
local receipt="host-A|Owner|33"
local history={[receipt]="g/123",["g/123"]=receipt}
roomState.ewDepositPending,roomState.ewDepositReceipt,roomState.ewDepositHistory=deposit,receipt,history
assert(scopes.select(roomState,"host-B"))
assert(not roomState.ewDepositPending and not roomState.ewDepositReceipt and not roomState.ewDepositHistory)
assert(scopes.select(roomState,"host-A"))
assert(roomState.ewDepositPending==deposit and roomState.ewDepositReceipt==receipt and roomState.ewDepositHistory==history)
