local fields,settings,flags={},{},{}
function GlobalsGetValue(k,d) return fields[k] or d end
function GlobalsSetValue(k,v) fields[k]=v end
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
local scopes=dofile("mods/noita_hideout/files/ew_expeditions.lua")
local world,owner="mine","caller"
NHEW={world=function() return world end,issuer=function() return owner end,localBody=function(p) return p==1 end}
local s=assert(NHStore.load())
assert(scopes.select(s,world))
s.resources.supply_logistics=5
assert(NHStore.commit(s))
local broken,notice
local function save(draft)
    if broken then return false end
    assert(NHStore.commit(draft))
    s=draft
    return true
end
local function controller()
    return dofile("mods/noita_hideout/files/ew_reinforce.lua")(function() return s end,NHStore.load,save,
        function(zh,en) return en end,function(msg) notice=msg end)
end
local function stock() return s.resources.supply_logistics or 0 end
local r=controller()
local mode="nh_ew.reinforce_mode"
local roster="nh_ew.reinforce_targets"
local mailbox="nh_ew.reinforce_request"
local function receipt(msg)
    local field,who,id=msg:match("^([^|]+)|([^|]+)|(%d+)|")
    return "nh_ew.reinforce_result."..field.."."..who.."."..id
end
assert(not r.visible())
fields[mode]=world
assert(r.visible() and not r.available())
fields[roster]="caller|1|0|0|self\nb|1|0|0|left\nc|1|99|0|far\na|2|2|0|right\nmalformed"
assert(not r.select(2,0,0))
assert(r.select(1,0,0).target=="b" and r.select(1,99,1).target=="c")
local ticket=assert(r.select(1,1,0))
assert(ticket.target=="a" and ticket.episode=="2" and stock()==5) -- distance tie, stable across peers
fields[roster]="b|1|0|0|still down\na|3|2|0|new episode"
assert(not r.request(1,20,40,ticket) and stock()==5 and not fields[mailbox])
ticket=assert(r.select(1,2,0))
assert(not r.request(1,2^30,0,ticket))
broken=true
assert(not r.request(1,20,40,ticket) and stock()==5 and not fields[mailbox])
broken=false
assert(r.request(1,-22.5,41,ticket))
local first=assert(fields[mailbox])
assert(first:find("|a|3|-23|41",1,true) and stock()==0 and s.ewReinforcePending.a==first)
assert(not r.available() and not r.request(1,0,0,ticket))

-- World globals may be lost on reload. Only the same world and caller can
-- replay the debit. A different expedition never inherits a pending call.
world="other"
assert(scopes.select(s,world) and not s.ewReinforcePending and save(s))
fields[mailbox]=""
r.settle()
assert(fields[mailbox]=="")
world="mine"
assert(scopes.select(s,world) and s.ewReinforcePending.a==first and save(s))
s=assert(NHStore.load())
r=controller()
r.settle()
assert(fields[mailbox]==first and stock()==0)
fields[receipt(first)]="rejected"
broken=true
r.settle()
assert(stock()==0 and s.ewReinforcePending.a==first)
broken=false
r.settle()
r.settle()
assert(stock()==5 and not s.ewReinforcePending and fields[mailbox]=="" and notice:find("Refunded"))
assert(r.request(1,12,34,ticket))
local second=fields[mailbox]
assert(second~=first and stock()==0)
fields[receipt(second)]="ok"
r.settle()
r.settle()
assert(stock()==0 and not s.ewReinforcePending and notice:find("full health"))
assert(not r.available() and not r.select(1,2,0))
-- A disconnected target with an outstanding receipt does not block other
-- teammates. The pending requests survive reload and settle independently.
s.resources.supply_logistics=10
assert(save(s))
assert(r.request(1,3,3,ticket))
local offline=fields[mailbox]
local other=assert(r.select(1,2,0))
assert(other.target=="b" and not r.request(1,3,3,ticket))
assert(r.request(1,3,3,other))
local online=fields[mailbox]
fields[receipt(online)]="ok"
r=controller()
r.settle()
r.settle()
assert(s.ewReinforcePending.a==offline and not s.ewReinforcePending.b and stock()==0)
fields[receipt(offline)]="rejected"
r.settle()
assert(not s.ewReinforcePending and stock()==5)

-- A paid episode can be redirected even with zero packs and a pending order.
s.resources.supply_logistics=5;assert(save(s))
assert(r.request(1,8,9,ticket))
local paid=fields[mailbox]
fields[roster]="b|1|2|0|redirect\na|3|60|30|friend|redirect"
assert(r.redirectAvailable() and r.available() and stock()==0)
local move=assert(r.select(1,2,0))
assert(move.target=="a" and move.redirect and move.x==60 and move.y==30)
assert(r.request(1,12,4,move) and fields["nh_ew.reinforce_redirect"]=="mine|a|3|12|4")
assert(fields[mailbox]==paid and stock()==0)
fields[roster]="b|1|2|0|redirect\na|3|60|30|friend"
assert(not r.redirectAvailable() and not r.request(1,8,9,move))
fields[receipt(paid)]="transferred";r.settle();r.settle()
assert(not s.ewReinforcePending and stock()==5 and notice:find("took over"))

-- The downed player's own profile can fund an existing order. No body or
-- data link is needed for an authenticated takeover of that exact episode.
local offerKey="nh_ew.reinforce_sponsor_offer"
local replyKey="nh_ew.reinforce_sponsor_reply"
local offer="mine|departed|41|caller|9|-8|19"
local otherOffer="mine|departed|42|b|8|13|10"
local function sponsorResult(tx,payment)
    return "nh_ew.reinforce_sponsor_result.mine.departed."..tx..".caller."..payment
end
fields[offerKey]="elsewhere|departed|41|caller|9|-8|19"
r.updateSponsor();assert(stock()==5 and not s.ewReinforceSponsors)
fields[offerKey]=offer;broken=true;r.updateSponsor()
assert(not fields[replyKey] and stock()==5 and not s.ewReinforceSponsors)
broken=false;r.updateSponsor()
local payment=s.ewReinforceSponsors[offer]
assert(payment and fields[replyKey]==offer.."|"..payment and stock()==0)
fields[offerKey]="";fields[replyKey]=""
s=assert(NHStore.load());r=controller();r.updateSponsor()
assert(stock()==0 and fields[replyKey]==offer.."|"..payment)
world="elsewhere";assert(scopes.select(s,world) and save(s));fields[replyKey]=""
r.updateSponsor();assert(not s.ewReinforceSponsors and fields[replyKey]=="")
world="mine";assert(scopes.select(s,world) and save(s));assert(s.ewReinforceSponsors[offer]==payment)
fields[offerKey]=otherOffer
local sawEarlier,sawDecline=false,false
for _=1,4 do
    r.updateSponsor()
    sawEarlier=sawEarlier or fields[replyKey]==offer.."|"..payment
    sawDecline=sawDecline or fields[replyKey]==otherOffer.."|none"
end
assert(sawEarlier and sawDecline and stock()==0)
fields[offerKey]="";fields[sponsorResult("41","9999")]="rejected"
r.updateSponsor();assert(stock()==0 and s.ewReinforceSponsors[offer]==payment)
fields[sponsorResult("41",payment)]="rejected"
broken=true;r.updateSponsor();assert(stock()==0 and s.ewReinforceSponsors[offer]==payment)
broken=false;r.updateSponsor();r.updateSponsor()
assert(stock()==5 and not s.ewReinforceSponsors)
fields[offerKey]=otherOffer;r.updateSponsor()
local winning=s.ewReinforceSponsors[otherOffer]
assert(winning~=payment and stock()==0)
fields[sponsorResult("42",winning)]="ok"
r.updateSponsor();r.updateSponsor()
assert(stock()==0 and not s.ewReinforceSponsors and fields[offerKey]=="")
world=nil
assert(not r.visible())
print("EW reinforcement: nearest teammate, stale episodes, escrow, replay and single charge passed.")
