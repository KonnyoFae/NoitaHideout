local root="mods/noita_hideout/files/"
local settings,flags={},{}
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) settings[k]=v end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile(root.."store.lua")
local finds=dofile(root.."pet_finds.lua")
local state=assert(NHStore.load())
NHStore.newRun(state)
local function claim(module,key,count)
    local paid,draft=module.payment(state,key,count)
    if draft then state.warehouse,state.nextItemId=draft.warehouse,draft.nextItemId end
    return paid
end
assert(finds.hasRed())
local collectibles={"salvage_bell","rewind_watch","stasis_hourglass","dustless_duster","mana_reactor","dragon_king"}
for i,id in ipairs(collectibles) do
    local key=finds.redKey(function(n) assert(n==#collectibles); return i end)
    assert(key=="red:"..id and finds.known(key) and NHStore.category(id)=="collection")
    assert(claim(finds,key,1)==1 and state.warehouse[1].item.remaining==90)
    state.warehouse={}
end
assert(not finds.known("gold") and not finds.known("red:missing") and not finds.canPay(state,"red:missing"))
local last={}
for level=1,3 do
    local pool=finds.toolPool(level)
    assert(#pool==level*3+1)
    local sedatives=0
    for i,key in ipairs(pool) do
        assert(not last[i] or last[i]==key)
        assert(finds.known(key) and finds.canPay(state,key))
        state.warehouse={}
        assert(claim(finds,key,1)==1 and #state.warehouse==1)
        local item=state.warehouse[1].item
        assert(item.kind==key and item.count==1 and item.name and item.icon)
        if key=="sedative_launcher" then
            sedatives=sedatives+1
            assert(item.remaining==20)
        end
        if NHGuns.types[key] then assert(NHGuns.rounds(item)==NHGuns.types[key].capacity)
        else assert(NHTurrets.types[key] and NHTurrets.validCount(item.count)) end
    end
    assert(sedatives==1)
    last=pool
end
for _,key in ipairs({"travel_satchel","travel_pack","loot_case"}) do
    state.warehouse={}
    assert(finds.known(key) and claim(finds,key,13)==13)
    assert(#state.warehouse==1 and state.warehouse[1].item.count==13)
end

-- Full tubes can join a partly used tube, but sidearms must not consume a
-- partly used sidearm's slot. Capturing an incoming batch leaves rows untouched.
state.warehouse={}
assert(claim(finds,"magic_tube",1)==1)
local beforeId=state.nextItemId
local old=state.warehouse[1]
old.item.remaining=2
local paid,draft=finds.payment(state,"magic_tube",4)
assert(paid==4 and draft.nextItemId==beforeId and #draft.warehouse==1)
assert(old.item.count==1 and old.item.remaining==2)
assert(draft.warehouse[1].item.count==5 and draft.warehouse[1].item.remaining==2)
state.warehouse={}
assert(claim(finds,"derringer",1)==1)
state.warehouse[1].item.remaining=1
assert(claim(finds,"derringer",3)==3 and #state.warehouse==2)
assert(state.warehouse[2].item.count==3 and state.warehouse[2].item.remaining==4)

-- Old full four-decoy stacks accept new finds after reload. A seventeenth
-- decoy goes into its own slot, regardless of the variant.
for _,kind in ipairs(NHTurrets.order) do
    state.warehouse={}
    assert(claim(finds,kind,4)==4)
    local oldId=state.warehouse[1].id
    assert(NHStore.commit(state))
    state=assert(NHStore.load())
    assert(finds.canPay(state,kind) and claim(finds,kind,13)==13)
    assert(#state.warehouse==2 and state.warehouse[1].id==oldId)
    assert(state.warehouse[1].item.count==16 and state.warehouse[2].item.count==1)
end

state.warehouse={}
assert(claim(finds,"turret_pack",42)==42)
assert(#state.warehouse==3 and state.warehouse[1].item.count==16 and state.warehouse[2].item.count==16)
assert(state.warehouse[3].item.count==10)
-- Reserve a four-decoy workshop batch in the third stack of a full grid.
-- Only two extra finds fit until the reservation is released.
local capacity=NHStore.warehouseCapacity(state,"supplies")
for i=#state.warehouse+1,capacity do
    state.warehouse[i]={id=state.nextItemId,slot=i,item={kind="bandage",count=1}}
    state.nextItemId=state.nextItemId+1
end
state.order={output={item={kind="turret_pack",count=4},slot=3}}
assert(finds.canPay(state,"turret_pack") and claim(finds,"turret_pack",7)==2)
assert(state.warehouse[3].item.count==12)
assert(not finds.canPay(state,"turret_pack") and not finds.canPay(state,"magic_tube"))
assert(finds.payment(state,"turret_pack",7)==0)
state.order=false
assert(claim(finds,"turret_pack",7)==4 and state.warehouse[3].item.count==16)
-- Freeing one row permits exactly sixteen more decoys.
table.remove(state.warehouse)
assert(claim(finds,"turret_pack",17)==16)
assert(not finds.canPay(state,"turret_pack"))

-- Register a real storage codec as a stand-in for a future collectible.
-- Both the combat path and the pet's stable key refer to the same definition.
local red={id="stone",file="data/entities/items/pickup/beamstone.xml",
    item={kind="native_valuable",variant="beamstone",name="$item_mega_beam_stone",icon="data/ui_gfx/items/beamstone.png"}}
local env=setmetatable({dofile=function(path)
    if path==root.."red_collectibles.lua" then return {red} end
    return dofile(path)
end},{__index=_G})
local future=setfenv(assert(loadfile(root.."pet_finds.lua")),env)()
local enemy=setfenv(assert(loadfile(root.."enemy_drops.lua")),env)()
assert(enemy.redPool[1].file==red.file)
local key=future.redKey(function(n) assert(n==1); return 1 end)
assert(key=="red:stone" and future.known(key) and future.hasRed())
-- The supplies grid remains full. Red valuables use the equipment grid.
assert(future.canPay(state,key) and claim(future,key,2)==2)
local first,second=state.warehouse[capacity+1],state.warehouse[capacity+2]
assert(first.slot==1 and second.slot==2 and first.item~=second.item and first.item~=red.item)
assert(first.item.variant=="beamstone" and NHNativeValuables.valid(first.item))
assert(NHStore.commit(state))
state=assert(NHStore.load())
assert(state.warehouse[capacity+1].item.variant=="beamstone")
print("Pet finds: tier pools, full and partial stacks, order reservations, full warehouse and shared collectible records passed.")
