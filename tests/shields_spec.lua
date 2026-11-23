local settings,flags={},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
local S=NHShields
local function craft(s,id)
    assert(NHStore.startOrder(s,id))
    assert(NHStore.advanceProduction(s,{run=s.runSerial,orderId=s.order.id,progress=s.order.required}))
    assert(NHStore.commit(s))
end
for i,id in ipairs(S.order) do
    local d=S.types[id]
    local s=assert(NHStore.load())
    NHStore.newRun(s)
    s.resources.arcane_scrap=d.scrap
    craft(s,id)
    local row=s.warehouse[#s.warehouse]
    assert(row.item.kind==id and NHStore.category(id)=="equipment" and row.item.charge==S.cell*d.cells)
    assert((s.resources.arcane_scrap or 0)==0)
    assert(S.move(s,{kind=id,source="warehouse",destination="gear",from=row.slot,entity=row.id}))
    assert(NHStore.commit(s) and NHStore.load().gearShield.id==row.id)
    local charge,spill=S.absorb(S.cell,100,d.resist,10)
    assert(spill==0 and charge==S.cell-(100-d.resist)*120)
    charge,spill=S.absorb(S.cell,200,d.resist,10)
    assert(spill==0 and charge==S.cell-(100-d.resist)*60)
    charge,spill=S.absorb(S.cell/5,100,50,50)
    assert(charge==0 and spill==30)
    charge,spill=S.absorb(S.cell,100,50,100)
    assert(charge==0 and spill==0)
    local q,r=S.cell/2,0
    for t=1,60 do q,r=S.recharge(q,r,d.cells,false) end
    assert(q==S.cell and S.recharge(q,r,d.cells,false)==q)
    for t=1,359 do q,r=S.recharge(q,r,d.cells,true) end
    assert(q==S.cell and r==359)
    q,r=S.recharge(q,r,d.cells,true)
    assert(q==S.cell*2 and r==0)
    local kind=S.chargerOrder[(i-1)%3+1]
    local d=S.chargers[kind]
    s.resources.arcane_scrap,s.bankGold=d.scrap,d.gold
    craft(s,kind)
    local charger=s.warehouse[#s.warehouse]
    assert(charger.item.count==4 and charger.item.remaining==8 and s.bankGold==0 and (s.resources.arcane_scrap or 0)==0)
    local move={kind=kind,source="warehouse",destination="gear",from=charger.slot,entity=charger.id}
    assert(S.move(s,move) and not S.move(s,move))
    assert(charger.item.count==3 and s.gearCharger.item.count==1 and s.gearCharger.id~=charger.id)
    assert(not S.repair(s,kind))
    s.gearShield.item.charge=S.cell/2
    assert(S.repair(s,kind))
    local restored=math.min(d.restore,S.types[id].cells-1)*S.cell+S.cell/2
    assert(s.gearShield.item.charge==restored)
    local use=dofile("mods/noita_hideout/files/inventory_use.lua")
    local ref={kind=kind,container="gear",storedId=s.gearCharger.id,count=1}
    for n=8,1,-1 do
        ref.remaining=n
        assert(use.spend(s,1,ref))
    end
    assert(not s.gearCharger)
    assert(S.move(s,move))
    local gear=s.gearCharger
    gear.item.remaining=3
    assert(S.move(s,{source="gear",destination="warehouse",safeSlot=charger.slot,entity=gear.id,kind=kind}))
    assert(charger.item.count==3 and charger.item.remaining==3)
    assert(S.move(s,move) and s.gearCharger.item.remaining==3 and charger.item.remaining==8)
    assert(S.move(s,{kind=id,source="gear",destination="warehouse",safeSlot=2,entity=row.id}))
    assert(NHStore.commit(s) and NHStore.load().warehouse[NHStore.slotIndex(s,"warehouse",2,id)].item.charge==restored)
    settings={}
    flags={}
end
print("Shield crafting, five branches, overflow, max HP scaling, partial recharge, broken cells, gear slots and persistence passed.")

-- Rebuild an old snapshot with the real wire codec, as if saved by the
-- previous version while a charger order and a native delivery were in flight.
do
    local function upvalue(fn,name)
        for i=1,60 do
            local key,value=debug.getupvalue(fn,i)
            if key==name then return value end
        end
        error("Missing snapshot codec "..name)
    end
    local s=assert(NHStore.load())
    NHStore.newRun(s)
    s.resources.arcane_scrap,s.bankGold=1,10
    assert(NHStore.startOrder(s,S.charger))
    assert(NHStore.commit(s))
    local output=s.order.output
    local function old(count) return {kind=S.charger,count=count,name="$nh_hideout_shield_charger"} end
    s.durableChargers=nil
    s.gearCharger={id=2,item=old(20)}
    s.warehouse={{id=3,slot=output.slot,item=old(37)}}
    s.safe={{id=4,slot=1,item=old(9)}}
    s.nextItemId=7
    output.item=old(1)
    s.transit={run=s.runSerial,retired={},issued={ticket={container="gear",x=0,y=0,row={id=6,item=old(10)}}}}
    local payload=upvalue(NHStore.commit,"encode")(s)
    local raw="NH1:"..upvalue(NHStore.commit,"checksum")(payload)..":"..payload
    for key,value in pairs(settings) do
        if type(value)=="string" and value:match("^NH1:") then settings[key]=raw end
    end
    local migrated=assert(NHStore.load())
    assert(migrated.gearCharger.item.count==1 and migrated.gearCharger.item.remaining==8)
    assert(NHMedkits.charges(migrated.safe[1].item)==9)
    assert(migrated.transit.issued.ticket.chargerOverflow==2)
    assert(NHMedkits.charges(migrated.order.output.item)==1)
    assert(NHStore.advanceProduction(migrated,{run=s.runSerial,orderId=s.order.id,progress=s.order.required}))
    assert(NHStore.commit(migrated))
    for i=1,2 do
        migrated=assert(NHStore.load())
        local total=NHMedkits.charges(migrated.gearCharger.item)+NHMedkits.charges(migrated.safe[1].item)
        for _,row in ipairs(migrated.warehouse) do total=total+assert(NHMedkits.charges(row.item)) end
        assert(total==20+37+9+1 and (migrated.pendingChargerUses or 0)==0)
        assert(NHStore.commit(migrated))
    end
end
