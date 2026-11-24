local root="mods/noita_hideout/files/"
local H=dofile(root.."ew_deposit_history.lua")
local world,owner="World-0","guest"
local key="t/ew/host/r/1/2/3/4/5/6"
local token=world.."|"..owner.."|221"
local other=world.."|other|221"
local old={[token]="g/99,"..key,["g/99"]=token,[key]=token,
    [world.."|"..owner.."|222"]="cancelled",[other]="g/6",["g/6"]=other}
local compact=H.compact(old,world)
assert(compact~=old and compact[world.."|"..owner.."|221"]==nil)
for _,h in ipairs({old,compact}) do
    assert(H.outcome(h,world,owner,"221")=="g/99,"..key and H.outcome(h,world,owner,"222")=="cancelled")
    assert(H.lookup(h,world,owner,key)=="221" and H.lookup(h,world,"other","g/6")=="221")
    assert(not H.lookup(h,"other-world",owner,key) and not H.lookup(h,world,"other",key))
    assert(not H.lookup(h,world,owner,"g/6") and not H.outcome(h,world,owner,"223"))
end
local updated=H.add(compact,world,owner,"223",{"g/7"})
assert(not H.lookup(compact,world,owner,"g/7") and H.lookup(updated,world,owner,"g/7")=="223")
assert(H.add(updated,world,owner,"223",{"g/7"})==updated)
local partial={[token]="g/99,"..key,["g/99"]=token}
assert(H.compact(partial,world)==partial and not H.lookup(partial,world,owner,key))

local settings,flags={},{}
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
dofile(root.."store.lua")
local s=assert(NHStore.load())
s.ewActive,s.ewDepositHistory=world,old
s.ewExpeditions={previous={bags={},ewDepositHistory={["previous|guest|12"]="cancelled"}}}
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(H.lookup(s.ewDepositHistory,world,owner,key)=="221")
assert(s.ewExpeditions.previous.ewDepositHistory.owners.guest["12"]==false)
assert(NHStore.commit(s))
assert(H.outcome(assert(NHStore.load()).ewDepositHistory,world,owner,"222")=="cancelled")
-- Compare real encoded snapshots for identical long-running expeditions.
local sampleWorld="0000000000001234-1234567890"
local sampleOwner="76561198000001234"
local sample={}
for i=1,1000 do
    local token=sampleWorld.."|"..sampleOwner.."|"..i
    local gid="g/184467440737095"..string.format("%05d",i)
    local ticket="t/ew/76561198000004321/r/1/3/"..i.."/"..i.."/345678/777"
    sample[token],sample[gid],sample[ticket]=gid..","..ticket,token,token
end
s=assert(NHStore.load())
s.ewActive,s.ewDepositHistory,s.ewExpeditions=sampleWorld,sample,nil
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(H.lookup(s.ewDepositHistory,sampleWorld,sampleOwner,"g/18446744073709501000")=="1000")
assert(NHStore.commit(s))
local small,large=math.huge,0
for _,v in pairs(settings) do
    if type(v)=="string" and v:match("^NH1:") then small=math.min(small,#v);large=math.max(large,#v) end
end
assert(small<large/2)
print(string.format("1000 synthetic two-key deposits, same encoded profile: %d bytes before, %d after.",large,small))
print("Deposit history: compact and legacy receipts preserve world, holder, cancelled orders and parked expeditions.")
