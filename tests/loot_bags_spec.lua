local root="mods/noita_hideout/files/"
local settings,flags={},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile(root.."store.lua")
dofile(root.."potion.lua")
local state=assert(NHStore.load())
NHStore.newRun(state)
assert(NHFoods.byId.hard_bread.uses==2 and NHFoods.byId.scrambled_egg.uses==2)
assert(NHFoods.byId.sandwich.uses==5 and NHFoods.byId.cake.uses==4 and NHFoods.byId.burger.uses==4)
state.foodPortions=nil
state.warehouse={{id=state.nextItemId,slot=1,item={kind="cake",count=3,remaining=1}}}
state.nextItemId=state.nextItemId+1
assert(NHStore.commit(state))
state=assert(NHStore.load())
assert(NHFoods.bites(state.warehouse[1].item)==5 and state.foodPortions)
assert(NHStore.commit(state) and NHFoods.bites(NHStore.load().warehouse[1].item)==5)
state.materials={sand=300,water=200}
state.resources.fiber=16
state.bankGold=340
for _,pair in ipairs({{"dog_kennel","dog"},{"cat_house","cat"}}) do
    assert(not NHStore.buyGood(state,{id=pair[2]},0))
    assert(NHStore.buyUpgrade(state,{id=pair[1],level=0},0))
    assert(NHStore.buyGood(state,{id=pair[2]},0))
end
local function quantity(kind)
    local n=0
    for _,row in ipairs(state.warehouse) do if row.item.kind==kind then n=n+(row.item.count or 1) end end
    return n
end
NHFarm.sync(state,119*60)
assert(quantity("travel_satchel")==0)
NHFarm.sync(state,120*60)
assert(quantity("travel_satchel")==0 and quantity("travel_pack")==0 and quantity("loot_case")==0)
NHFarm.sync(state,300*60)
assert(math.abs(NHFarm.income.petFraction(state,"travel_pack")-4/30)<1e-9)
-- Simulate an old release with four earned pairs and one case awaiting delivery.
state.farm.minuteIncome={remainder={},open={},owed={dog=4,cat=1},
    openRare={counts={},private={}},rare={counts={},private={}}}
assert(NHFarm.sync(state,300*60))
assert(quantity("travel_satchel")==4 and quantity("travel_pack")==4 and quantity("loot_case")==1)
assert(NHStore.commit(state))
state=assert(NHStore.load())
-- A full supplies grid with room for only one of the kennel yields retains the entire cycle.
for _,row in ipairs(state.warehouse) do if row.item.kind=="travel_pack" then row.item={kind="bandage"} end end
while true do
    local slot=NHStore.freeSlot(state,"warehouse",nil,"bandage")
    if not slot then break end
    table.insert(state.warehouse,{slot=slot,id=state.nextItemId,item={kind="bandage"}})
    state.nextItemId=state.nextItemId+1
end
state.farm.minuteIncome.owed.dog=1
NHFarm.sync(state,360*60)
assert(quantity("travel_satchel")==4 and not NHFarm.due(state,360*60))
table.remove(state.warehouse)
NHFarm.sync(state,360*60)
assert(quantity("travel_satchel")==5 and quantity("travel_pack")==1 and not NHFarm.sync(state,360*60))
local use=dofile(root.."inventory_use.lua")
local slot,index=NHStore.stackSlot(state,"warehouse",{kind="travel_satchel"})
local row=state.warehouse[index]
local ref={container="warehouse",slot=slot,storedId=row.id,kind=row.item.kind,count=row.item.count}
local created,alive,roll={}, {},100
function EntityGetTransform() return 10,20 end
function SetRandomSeed() end
function GameGetFrameNum() return 2345 end
function ProceduralRandomi(x,y,a,b) return b==100 and roll or b end
function EntityLoad(file)
    local id=#created+1
    created[id],alive[id]=file,true
    return id
end
function CreateItemActionEntity(id) return EntityLoad("spell/"..id) end
function EntityKill(id) alive[id]=nil end
local chooseLast=ProceduralRandomi
local native,doses=NHNative,NHDoses
local confirmed
NHNative={spawn=function(kind,_,_,subtype)
    assert(kind=="dose")
    return EntityLoad(root.."items/"..assert(NHInjectors.types[subtype]).filename..".xml")
end}
NHDoses={confirmLoot=function(entity) confirmed=entity end}

local function openWith(kind, sequence, pay)
    local index=0
    function ProceduralRandomi(_,_,lo,hi)
        index=index+1
        local n=sequence[index]
        assert(n and n>=lo and n<=hi,"unexpected loot roll "..index.." for "..kind)
        return n
    end
    created,alive,confirmed={},{},nil
    local ok=NHLootBags.open(1,kind,pay or function() return true end)
    assert(index==#sequence)
    ProceduralRandomi=chooseLast
    return ok
end

local covered={}
local expected={{55,25,20,0,2,0},{0,40,35,25,5,2},{0,30,35,35,15,8}}
for level,kind in ipairs(NHLootBags.order) do
    local tier=NHLootBags.types[kind]
    local sedativeIndex
    local p=expected[level]
    assert(tier.gold==level and tier.tarot==p[5] and tier.card==p[6])
    local low=0
    for col,group in ipairs({"food","medical","tool","dose"}) do
        assert(tier.chances[group]==p[col])
        if p[col]>0 then
            local pool=({food=NHFoods,medical=tier.medical,tool=tier.tools,dose=tier.doses})[group]
            for i,entry in ipairs(pool) do
                local id=group=="food" and entry.id or entry
                local file=group=="dose" and assert(NHInjectors.types[id]).filename or id
                local f=assert(io.open(root.."items/"..file..".xml","r")); f:close()
                if file=="sedative_launcher" then
                    assert(group=="tool" and not sedativeIndex,"duplicate or misplaced sedative launcher in "..kind)
                    sedativeIndex=i
                else
                    assert(not covered[file],"supply in multiple grade pools: "..file)
                end
                covered[file]=true
                for _,at in ipairs({low+1,low+p[col]}) do
                    local seq={at,i,100}
                    if tier.card>0 then seq[#seq+1]=100 end
                    assert(openWith(kind,seq,function(entity,subtype)
                        if group=="dose" then assert(entity==level+1 and subtype==id)
                        else assert(not entity and not subtype) end
                        return true
                    end))
                    for j=1,level do assert(created[j]=="data/entities/items/pickup/goldnugget.xml") end
                    assert(#created==level+1 and created[level+1]==root.."items/"..file..".xml")
                    assert((confirmed~=nil)==(group=="dose"))
                end
            end
        end
        low=low+p[col]
    end
    assert(low==100)
    assert(sedativeIndex,"sedative launcher missing from "..kind)
    for _,container in ipairs({kind,NHLootBags.packKinds[level]}) do
        local rolls={tier.chances.food+tier.chances.medical+1,sedativeIndex,100}
        if tier.card>0 then rolls[#rolls+1]=100 end
        local stack={kind=container,count=2}
        local draft={runSerial=1,closedThrough=0,warehouse={{id=1,slot=1,item=stack}}}
        local clicked={container="warehouse",slot=1,storedId=1,kind=container,count=2}
        assert(openWith(container,rolls,function() return use.spend(draft,1,clicked) end))
        assert(stack.count==1 and #created==level+1+(container==kind and 0 or 2))
        assert(created[#created]==root.."items/sedative_launcher.xml" and alive[#created])
    end
    for i=1,100 do
        local seq={1,1,i}
        local tarot=i<=tier.tarot
        local companion=101-i<=tier.card
        if tarot then seq[#seq+1]=#NHTarot.order end
        if tier.card>0 then seq[#seq+1]=101-i end
        if companion then seq[#seq+1]=#NHCompanions.order end
        assert(openWith(kind,seq))
        local count=level+1
        if tarot then count=count+1; assert(created[count]==root.."items/card_tarot_devil.xml") end
        if companion then count=count+1; assert(created[count]==root.."items/card_cat.xml") end
        assert(#created==count)
    end
end
local gunFile=assert(io.open(root.."items/sedative_launcher.xml","r"))
local gunXml=gunFile:read("*a")
gunFile:close()
assert(gunXml:match('<ItemComponent%s+[^>]-uses_remaining="(%d+)"')=="20")
for _,id in ipairs(NHInjectors.order) do assert(covered[NHInjectors.types[id].filename]) end
for _,set in ipairs({NHMedkits.order,NHSurgeryKits.order,NHTurrets.order,NHShields.chargerOrder,
        {"ammo_pack","improved_ammo_pack","advanced_ammo_pack","flare_gun","derringer","magic_tube","fire_tube","frost_tube","shock_tube"}}) do
    for _,id in ipairs(set) do assert(covered[id],id.." missing from loot") end
end
assert(openWith("loot_case",{100,1,1,1,1,1}) and #created==6 and confirmed==4)
assert(not openWith("loot_case",{100,1,1,1,1,1},function() return false end) and not confirmed and not next(alive))
local giftOdds={{60,30,10},{50,35,15},{40,40,20}}
for level,odds in ipairs(giftOdds) do
    local kind="gift_box_"..level
    assert(use.supports(kind))
    for i=1,100 do
        created,alive,roll={},{},i
        local paid=0
        assert(NHLootBags.open(1,kind,function() paid=paid+1; return true end))
        assert(paid==1 and #created==2 and created[1]==root.."items/"..NHLootBags.packKinds[level]..".xml")
        if i<=odds[1] then assert(created[2]==root.."items/"..NHFoods[#NHFoods].id..".xml")
        elseif i<=100-odds[3] then assert(created[2]=="data/entities/items/pickup/sun/sunstone.xml")
        else assert(created[2]==root.."items/card_tarot_devil.xml") end
    end
end
-- Every released card must be selectable through each physical container.
-- Pick a main supply and suppress the separate companion roll so the last
-- entity is always the tarot reward.
for level,bag in ipairs(NHLootBags.order) do
    for index,species in ipairs(NHTarot.order) do
        local path=root.."items/card_"..species..".xml"
        local rolls={1,1,1,index}
        if NHLootBags.types[bag].card>0 then rolls[#rolls+1]=100 end
        for _,kind in ipairs({bag,NHLootBags.packKinds[level]}) do
            assert(openWith(kind,rolls) and created[#created]==path,kind.." missing "..species)
        end
        local gift="gift_box_"..level
        assert(openWith(gift,{100,index}) and created[2]==path,gift.." missing "..species)
    end
end
created,alive,roll={},{},61
assert(not NHLootBags.open(1,"gift_box_1",function() return false end) and not next(alive))
local loadReward=EntityLoad
for failed=1,2 do
    created,alive={},{}
    EntityLoad=function(file)
        if #created+1==failed then return 0 end
        return loadReward(file)
    end
    assert(not NHLootBags.open(1,"gift_box_1",function() error("partial gift was charged") end))
    assert(not next(alive))
end
EntityLoad=loadReward
created,alive,roll={},{},1
assert(not NHLootBags.open(1,"loot_case",function() return false end) and not next(alive))
for level,kind in ipairs(NHLootBags.packKinds) do
    local bag=NHLootBags.types[kind]
    for _,chance in ipairs({1,50,100}) do
        created,alive,roll={},{},chance
        assert(NHLootBags.open(1,NHLootBags.order[level],function() return true end))
        local expected=created
        created,alive={},{}
        assert(NHLootBags.open(1,kind,function() return true end))
        assert(created[1]==root.."items/"..bag.charger..".xml" and created[2]==root.."items/"..bag.ammo..".xml")
        assert(#created==#expected+2)
        for i,path in ipairs(expected) do assert(created[i+2]==path) end
        created,alive={},{}
        assert(not NHLootBags.open(1,kind,function() return false end) and not next(alive))
    end
end
created,alive,roll={},{},1
assert(NHLootBags.open(1,"travel_satchel",function() return use.spend(state,1,ref) end))
assert(quantity("travel_satchel")==4 and not use.peek(state,1,ref))
NHNative,NHDoses=native,doses
print("Graded supplies, independent card rolls and payout rollback passed.")

-- Old storage records and prepaid orders used different charge encodings.
settings,flags={},{}
local old=assert(NHStore.load())
NHStore.newRun(old)
old.medicalStacks,old.fiveDoseUses=nil,nil
old.warehouse={{id=old.nextItemId,slot=1,item={kind="bandage",count=4}},
    {id=old.nextItemId+1,slot=2,item={kind="dose",subtype="haste",remaining=3,count=1}}}
old.nextItemId=old.nextItemId+2
old.pouches[old.starterPouchId].cells={{remaining=3,count=1},{remaining=2,count=1}}
old.issuedDoses={sample={remaining=3,subtype="frost",x=1,y=2}}
old.order={id=1,recipe="medical",required=300,progress=2,output={slot=3,item={kind="medkit",remaining=3}}}
assert(NHStore.commit(old))
old=assert(NHStore.load())
assert(old.warehouse[1].item.remaining==4 and old.warehouse[1].item.count==1 and old.warehouse[2].item.remaining==5)
assert(old.pouches[old.starterPouchId].cells[1].remaining==5 and old.pouches[old.starterPouchId].cells[2].remaining==2)
assert(old.issuedDoses.sample.remaining==5 and old.order.output.item.remaining==3)
assert(NHStore.commit(old) and NHStore.load().warehouse[1].item.remaining==4)

for _,kind in ipairs({"bandage","medkit","tactical_medkit","advanced_medkit","field_surgery_kit","tactical_surgery_kit","advanced_surgery_kit"}) do
    local cap=NHMedkits.capacity(kind)
    local stack={kind=kind,remaining=1,count=3}
    local full={kind=kind,remaining=cap,count=1}
    local s={safe={{slot=1,id=1,item=stack}}}
    assert(not NHStore.stackSlot(s,"safe",{kind=kind,remaining=1,count=1}))
    assert(NHStore.stackSlot(s,"safe",full)==1)
    NHStore.mergeStack(stack,full)
    assert(stack.count==4 and stack.remaining==1 and not NHStore.stackSlot(s,"safe",full))
end

-- The controller settles a due gift with the same case capacity, stack and
-- persistent profile as an inventory transfer. Only a full case drops loot.
dofile(root.."transfers.lua")
local deliver=dofile(root.."companions/gifts.lua")
local pending,message
local function queue(level,frame) pending={value_string="bee",value_float=level,value_int=frame} end
function EntityGetFirstComponentIncludingDisabled(_,kind,tag)
    assert(kind=="VariableStorageComponent" and tag=="nh_companion_gift")
    return pending
end
function EntityRemoveComponent(_,c) assert(c==pending); pending=nil end
function ComponentGetValue2(c,key) return c[key] end
function GamePrint(text) message=text end
local function tick(save) deliver(1,"zh",NHStore.load,save or NHStore.commit) end
local base=assert(NHStore.load())
assert(#base.safe==0 and NHStore.freeSafeSlot(base)==1)
assert(NHStore.commit(base))
created={}
queue(1,200)
tick(function() return false end)
assert(pending and #NHStore.load().safe==0 and #created==0 and not message)
tick()
assert(not pending and message:find("蜂娘赠送了一件礼物盒",1,true) and #created==0 and NHStore.load().safe[1].item.count==1)
queue(1,200); tick()
assert(not pending and NHStore.load().safe[1].item.count==1)
queue(1,400); tick()
assert(not pending and NHStore.load().safe[1].item.count==2 and #created==0)
queue(3,600)
local loadItem=EntityLoad
EntityLoad=function() return 0 end
tick(); assert(pending)
EntityLoad=loadItem
tick(); tick()
assert(not pending and #created==1 and created[1]==root.."items/gift_box_3.xml")
assert(NHStore.load().safe[1].item.count==2)
print("Gift boxes grant a matching supply pack and one weighted bonus. Rollback, delivery retries, replay and full-case fallback passed.")
