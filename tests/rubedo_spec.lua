local settings,flags={},{}
local fail=false
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k,v) if not fail then settings[k]=v end end
function HasFlagPersistent(k) return flags[k] end
function AddFlagPersistent(k) flags[k]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")
local s=assert(NHStore.load())
NHStore.newRun(s)
s.bankGold=5000
s.materials={midas=1,water=200}
s.resources={arcane_scrap=1,container_scrap=1}
assert(NHStore.commit(s))
for _,missing in ipairs({"gold","midas","arcane_scrap","container_scrap"}) do
    local draft=assert(NHStore.load())
    if missing=="gold" then draft.bankGold=4999
    elseif missing=="midas" then draft.materials.midas=nil
    else draft.resources[missing]=nil end
    assert(not NHStore.craft(draft,"philosopher_stone") and not draft.resources.nh_philosopher_stone and draft.finished==0)
end
local draft=assert(NHStore.load())
assert(NHStore.craft(draft,"philosopher_stone"))
assert(not draft.order and draft.bankGold==0 and not draft.materials.midas and not draft.resources.arcane_scrap and not draft.resources.container_scrap)
assert(draft.resources.nh_philosopher_stone==10)
fail=true; assert(not NHStore.commit(draft)); fail=false
s=assert(NHStore.load())
assert(s.bankGold==5000 and s.materials.midas==1 and not s.resources.nh_philosopher_stone)
assert(NHStore.craft(s,"philosopher_stone") and NHStore.commit(s))
s=assert(NHStore.load())
assert(NHStore.craft(s,"rubedo_midas") and s.materials.midas==100 and s.materials.water==100 and s.resources.nh_philosopher_stone==9)
assert(NHStore.craft(s,"rubedo_immortality") and s.resources.nh_elixir_of_immortality==100 and not s.materials.water and s.resources.nh_philosopher_stone==8)
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(s.resources.nh_elixir_of_immortality==100 and s.resources.nh_philosopher_stone==8)
assert(not NHStore.craft(s,"rubedo_immortality") and s.resources.nh_philosopher_stone==8)
-- Resource balances survive reloads and cannot be bottled.
assert(NHPotion.materialName("nh_philosopher_stone","zh")=="贤者之石")
assert(NHPotion.materialName("nh_elixir_of_immortality","zh")=="不死药")
assert(not NHPotion.materialSlot("nh_philosopher_stone") and not NHPotion.materialSlot("nh_elixir_of_immortality"))
s.docks={{id=s.nextItemId,slot=1,item={kind="potion",capacity=1000,materials={}}}}
assert(not NHPotion.transferMaterial(s,{storedId=s.nextItemId,slot=1,material="nh_elixir_of_immortality",amount=1}))
assert(s.resources.nh_elixir_of_immortality==100)
s.docks={}
s.materials={water=200}
for n=1,15 do s.materials["stock_"..n]=1 end
assert(NHStore.craft(s,"rubedo_immortality") and s.materials.water==100 and s.resources.nh_elixir_of_immortality==200)
s.resources.nh_elixir_of_immortality=NHStore.maxResourceAmount-99
assert(not NHStore.craft(s,"rubedo_immortality") and s.materials.water==100 and s.resources.nh_philosopher_stone==7)

-- Load the stocks and the paid output in the former save format, then reload the migration.
s.materials={nh_elixir_of_immortality=40,nh_philosopher_stone=5}
s.resources={nh_elixir_of_immortality=10}
s.order={id=s.finished+1,recipe="rubedo_immortality",progress=1,required=60,output={materials={nh_elixir_of_immortality=100}}}
assert(NHStore.commit(s))
s=assert(NHStore.load())
assert(not next(s.materials) and s.resources.nh_elixir_of_immortality==50 and s.resources.nh_philosopher_stone==5)
assert(not s.order.output.materials and s.order.output.resources.nh_elixir_of_immortality==100)
local req={run=s.runSerial,orderId=s.order.id,progress=60}
assert(NHStore.advanceProduction(s,req) and NHStore.commit(s))
s=assert(NHStore.load())
assert(s.resources.nh_elixir_of_immortality==150 and not NHStore.advanceProduction(s,req))

local batches={
    supply_logistics={{midas=10},{nh_elixir_of_immortality=10,grain=100,sugar=100,herb=100},0},
    strike_logistics={{midas=20,sand=100,slime=100},{fiber=200},0},
    reinforcement_logistics={{},{nh_elixir_of_immortality=20,fiber=100,spice=100},100},
    intel_logistics={{midas=10},{arcane_scrap=1,spice=100},200},
}
for id,batch in pairs(batches) do
    s.materials,s.resources,s.bankGold=batch[1],batch[2],batch[3]
    for _,stock in ipairs({s.materials,s.resources}) do
        for key,amount in pairs(stock) do
            stock[key]=amount-1
            assert(not NHStore.craft(s,id) and s.bankGold==batch[3] and not s.resources[id])
            stock[key]=amount
        end
    end
    if batch[3]>0 then
        s.bankGold=batch[3]-1
        assert(not NHStore.craft(s,id) and not s.resources[id])
        s.bankGold=batch[3]
    end
    assert(NHStore.craft(s,id) and s.bankGold==0 and not next(s.materials) and s.resources[id]==50)
    for key in pairs(s.resources) do assert(key==id) end
    assert(NHStore.commit(s))
    s=assert(NHStore.load())
    assert(s.resources[id]==50 and not s.order)
end
print("Rubedo and logistics: resource migration, paid order recovery, capacity and four exact recipe payments passed.")
