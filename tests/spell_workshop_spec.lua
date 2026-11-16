local settings,flags={},{}
function ModSettingGet(key) return settings[key] end
function ModSettingSet(key,value) settings[key]=value end
function HasFlagPersistent(key) return flags[key]==true end
function AddFlagPersistent(key) flags[key]=true end
dofile("mods/noita_hideout/files/store.lua")
dofile("mods/noita_hideout/files/potion.lua")

local state=assert(NHStore.load())
local run=NHStore.newRun(state)
local seen,counts={}, {projectile=0,static_projectile=0}
local durationExamples={LIGHT_BULLET=5,BOMB=10,HEAL_BULLET=30,REGENERATION_FIELD=60,NUKE=120,NUKE_GIGA=180}
local durationBands={[5]=true,[10]=true,[30]=true,[60]=true,[120]=true,[180]=true}
local cheapestSpell={}
local originalUnlocks=0
for _,recipe in ipairs(NHStore.recipes) do
    if recipe.category=="spell" then
        local card=recipe.item.card
        assert(not seen[card.id] and recipe.id=="spell_"..card.id)
        seen[card.id]=true
        counts[recipe.spellType]=counts[recipe.spellType]+1
        local key=NHEssences.byAction[card.id]
        local amount=recipe.resources[key]
        cheapestSpell[key]=math.min(cheapestSpell[key] or amount,amount)
        local seconds=recipe.durationFrames/60
        assert(durationBands[seconds] and NHStore.productionFrames(recipe)==recipe.durationFrames,card.id)
        assert(not durationExamples[card.id] or durationExamples[card.id]==seconds,card.id)
        local refund,resource=NHStore.salvageYield(recipe.item,"essence")
        assert(recipe.facility=="salvage" and refund==amount and key==resource and amount>0)
        assert(next(recipe.resources)==key and next(recipe.resources,key)==nil and not card.stack and recipe.item.kind=="spell")
        assert(recipe.item.name:match("^%$action_") and recipe.item.icon:match("^data/ui_gfx/gun_actions/"))
        local full=card.item.uses_remaining
        assert(full==-1 or full>=1)
        state.resources[key]=amount
        state.levels.salvage=0
        local ok,reason=NHStore.startOrder(state,recipe.id)
        assert(not ok and reason=="Facility is locked." and state.resources[key]==amount)
        state.levels.salvage=1
        if recipe.unlockFlag then
            flags[recipe.unlockFlag]=false
            ok,reason=NHStore.startOrder(state,recipe.id)
            assert(not ok and reason=="Spell not unlocked in this save." and state.resources[key]==amount)
            AddFlagPersistent(recipe.unlockFlag)
            originalUnlocks=originalUnlocks+1
        end
        state.resources[key]=amount-1
        ok,reason=NHStore.startOrder(state,recipe.id)
        assert(not ok and reason=="Not enough workshop resources." and state.resources[key]==amount-1 and not state.order)
        state.resources[key]=amount
        assert(NHStore.startOrder(state,recipe.id))
        local order=state.order
        assert(order.required==recipe.durationFrames)
        assert(not state.resources[key] and order.output.slot==1 and not NHStore.freeSlot(state,"warehouse",1,"spell"))
        assert(NHStore.freeSlot(state,"warehouse",1,"wand")==1 and not NHStore.startOrder(state,recipe.id))
        assert(NHStore.commit(state))
        state=assert(NHStore.load())
        local halfway={run=run,orderId=order.id,progress=math.max(math.floor(order.required/2),order.required-NHStore.checkpointFrames)}
        assert(NHStore.advanceProduction(state,halfway) and state.order and #state.warehouse==0)
        halfway.checkpoint="temple/"..order.id
        local changed,finished=NHStore.advanceProduction(state,halfway)
        assert(changed and finished and not state.order and #state.warehouse==1)
        assert(not NHStore.advanceProduction(state,halfway))
        local row=state.warehouse[1]
        assert(row.slot==1 and row.item.card.id==card.id and row.item.card.item.uses_remaining==full)
        assert(row.item.card.useDefaultPickups)
        row.item.card.item.uses_remaining=0
        assert(card.item.uses_remaining==full)
        assert(NHStore.salvage(state,{id=row.id,kind="spell",slot=row.slot,mode="essence"}))
        assert(#state.warehouse==0 and state.resources[key]==amount and NHStore.commit(state))
    end
end
for id in pairs(NHEssences.byAction) do assert(seen[id],id) end
for _,recipe in ipairs(NHStore.recipes) do
    if recipe.category=="medical" or recipe.category=="weapons" then
        for key,amount in pairs(recipe.resources or {}) do
            if cheapestSpell[key] then assert(amount*10<=cheapestSpell[key],recipe.id..": "..key) end
        end
    end
end
assert(counts.projectile==117 and counts.static_projectile==41 and originalUnlocks==20)
assert(not NHStore.startOrder(state,"spell_SPEED") and not NHStore.startOrder(state,"spell_RANDOM_PROJECTILE"))

for slot=1,NHStore.warehouseCapacity(state,"spell") do
    state.warehouse[slot]={slot=slot,id=state.nextItemId,item={kind="spell",card={id="LIGHT_BULLET"}}}
    state.nextItemId=state.nextItemId+1
end
state.resources.essence_high_energy=375
local ok,why=NHStore.startOrder(state,"spell_BOMB")
assert(not ok and why=="Product storage is full." and not state.order and state.resources.essence_high_energy==375)
table.remove(state.warehouse,4)
assert(NHStore.startOrder(state,"spell_BOMB") and state.order.output.slot==4)
local template
for _,recipe in ipairs(NHStore.recipes) do if recipe.id=="spell_BOMB" then template=recipe.item end end
state.order.output.item.card.item.uses_remaining=1
assert(template.card.item.uses_remaining==3,"each order must own its native item fields")
print("Spell workshop: all 158 essence round trips, original unlocks, warehouse reservations, timed delivery and save reloads passed.")
