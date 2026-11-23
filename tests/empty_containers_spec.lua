local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key] end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local s=assert(NHStore.load())
local function flask(materials,variant)
    return {kind="potion",capacity=1000,materials=materials,variant=variant}
end
local function row(container,slot,item)
    local id=s.nextItemId
    s.nextItemId=id+1
    local record={id=id,slot=slot,item=item}
    table.insert(s[container],record)
    return record
end
local function quote()
    for _,p in ipairs(NHStore.progressMenu(s,"en").expansion) do
        if p.id=="warehouse_containers" then return p end
    end
end
local function upgrade(level)
    return NHStore.buyUpgrade(s,{id="warehouse_containers",level=level})
end

local late=row("warehouse",9,flask({},"jar"))
local loaded=row("warehouse",1,flask({water=1}))
local early=row("warehouse",2,flask({},"powder_stash"))
local dock=row("docks",1,flask({}))
local safe=row("safe",1,flask({}))
assert(not NHPotion.isEmptyContainer({kind="potion",materials={}}))
assert(not NHPotion.isEmptyContainer({kind="potion",capacity=1000}))
local attached=flask({})
attached.children={{id=123}}
assert(not NHPotion.isEmptyContainer(attached))
assert(not NHPotion.isEmptyContainer(flask({},"unknown_template")))
assert(not NHPotion.isEmptyContainer(loaded.item))
assert(not NHPotion.isEmptyContainer({kind="pouch",capacity=4,cells={}}))
assert(NHStore.emptyContainerCount(s)==2 and not NHStore.spendEmptyContainers(s,3))
assert(#s.warehouse==3 and loaded.item.materials.water==1)
assert(NHStore.spendEmptyContainers(s,1) and s.warehouse[1]==late and s.warehouse[2]==loaded)
assert(not NHStore.slotIndex(s,"warehouse",early.slot,"potion"))
assert(s.safe[1]==safe and s.docks[1]==dock)

-- Rank one uses bulk stock. Later previews and commits use the same shell
-- count. Filling a quoted shell before confirmation cancels the purchase.
s.materials={sand=3000,water=1700}
assert(upgrade(0))
local preview=quote()
assert(preview.canBuy and preview.costs[3].key=="empty_container" and preview.costs[3].amount==1)
assert(preview.costs[3].available==1)
late.item.materials.slime=1
assert(not quote().canBuy and not upgrade(1))
assert(s.materials.sand==2800 and s.materials.water==1600 and #s.warehouse==2)
late.item.materials.slime=nil
assert(upgrade(1) and #s.warehouse==1 and s.warehouse[1]==loaded)
assert(not upgrade(1))
row("warehouse",3,flask({}))
row("warehouse",4,flask({}))
preview=quote()
assert(not preview.canBuy and preview.costs[3].amount==2 and preview.costs[4].key=="container_scrap")
assert(preview.costs[4].amount==1 and not upgrade(2) and #s.warehouse==3)

-- Dismantling shares the strict empty predicate. Recheck the current item,
-- not the right-click preview. Scrap remains separate from arcane scrap.
s.levels.salvage=1
local victim=row("warehouse",8,flask({},"powder_stash"))
local salvage={kind="potion",slot=8,id=victim.id}
victim.item.materials.sand=1
assert(not NHStore.salvage(s,salvage) and not s.resources.container_scrap)
victim.item.materials.sand=nil
assert(NHStore.salvage(s,salvage) and not NHStore.salvage(s,salvage))
assert(s.resources.container_scrap==1 and not s.resources.arcane_scrap)
assert(quote().canBuy and upgrade(2) and not s.resources.container_scrap)
assert(#s.warehouse==1 and s.warehouse[1].item.materials.water==1)
assert(s.docks[1]==dock and s.safe[1]==safe)
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(s.levels.warehouse_containers==3 and quote().costs[3].amount==3 and quote().costs[4].amount==2)
assert(s.warehouse[1].id==loaded.id and s.warehouse[1].item.materials.water==1)
local store={kind="potion",slot=loaded.slot,id=loaded.id,mode="store_contents"}
s.resources.container_scrap=NHStore.maxResourceAmount
assert(not NHStore.salvage(s,store) and s.warehouse[1].item.materials.water==1)
s.resources.container_scrap=3
s.warehouse[1].item.materials.slime=27
s.materials={water=100}
for i=1,15 do s.materials["filler_"..i]=1 end
assert(not NHStore.salvage(s,store) and not s.materials.slime and s.materials.water==100 and s.resources.container_scrap==3)
s.materials.filler_15=nil
assert(NHStore.salvage(s,store) and NHStore.commit(s))
s=assert(NHStore.load())
assert(not NHStore.salvage(s,store) and s.materials.slime==27 and s.materials.water==101 and s.resources.container_scrap==4)
assert(#s.warehouse==0 and #s.safe==1 and #s.docks==1)
print("Empty container eligibility, deterministic payment, stale quotes, salvage and expansion costs passed.")
