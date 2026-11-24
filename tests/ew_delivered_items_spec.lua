-- Exercise the actual profile encoding, two-slot commit and later load.
local settings,flags,receipts={},{},{}
local world,issuer,blockWrite="worldA","Host",false
NHEW={world=function() return world end,issuer=function() return issuer end}
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) if not blockWrite then settings[k]=v end end
function GlobalsGetValue(k,d) return receipts[k] or d end
dofile("mods/noita_hideout/files/store.lua")
local s=assert(NHStore.load())
NHStore.newRun(s)
s.ewActive=world
s.transit={run=s.runSerial,issued={},retired={}}
local function release(id,item,owner)
    local ticket="ew/"..(owner or issuer).."/r/1/1/"..id.."/"..id.."/70/11"
    s.transit.issued[ticket]={row={id=id,slot=1,item=item},container="warehouse"}
    return ticket
end
local wand=release(1,{kind="wand",name=string.rep("wand parts ",1000)})
local flask=release(2,{kind="potion"})
local chain=release(3,NHRelics.empty())
local wallet=release(4,NHCardWallets.empty(1))
local split=release(5,{kind="wand"})
s.transit.issued[split].splitDeposit=world.."|"..issuer.."|17"
local unknown=release(6,{kind="wand"})
local foreign=release(7,{kind="wand"},"Guest")
local previousRun="ew/Host/r/1/12/8/8/70/11"
s.transit.issued[previousRun]={row={id=8,slot=1,item={kind="wand"}},container="warehouse"}
for _,ticket in ipairs({wand,flask,chain,wallet,split,foreign,previousRun}) do receipts["noita_hideout.delivered."..ticket]="1" end
assert(NHStore.commit(s))
assert(s.transit.issued[wand] and not s.transit.delivered)
world="worldB"
assert(NHStore.commit(s) and s.transit.issued[wand])
world="worldA"
blockWrite=true
assert(not NHStore.commit(s) and s.transit.issued[wand] and not s.transit.delivered)
assert(assert(NHStore.load()).transit.issued[wand])
blockWrite=false
assert(NHStore.commit(s))
local min,max=math.huge,0
for _,v in pairs(settings) do
    if type(v)=="string" and v:match("^NH1:") then min=math.min(min,#v);max=math.max(max,#v) end
end
assert(max-min>10000)
receipts={}
s=assert(NHStore.load())
assert(s.transit.delivered[wand]=="wand" and s.transit.delivered[flask]=="potion")
assert(not s.transit.issued[wand] and not s.transit.issued[flask])
for _,ticket in ipairs({chain,wallet,split,unknown,foreign,previousRun}) do
    assert(s.transit.issued[ticket] and not s.transit.delivered[ticket])
end
assert(NHStore.commit(s) and assert(NHStore.load()).transit.delivered[wand]=="wand")
local expeditions=dofile("mods/noita_hideout/files/ew_expeditions.lua")
assert(expeditions.select(s,nil))
world=nil
local solo="r/1/"..s.runSerial.."/8/8/70/11"
s.transit={run=s.runSerial,issued={[solo]={row={id=8,slot=1,item={kind="wand"}},container="warehouse"}},retired={}}
receipts["noita_hideout.delivered."..solo]="1"
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(NHStore.commit(s) and s.transit.issued[solo] and not s.transit.delivered)
world="worldA"
assert(expeditions.select(s,world) and s.transit.delivered[wand]=="wand" and not s.transit.issued[solo])
print("Confirmed EW delivery releases the full wand payload. Failed writes, private contents, remainders and missing proof retain it.")
