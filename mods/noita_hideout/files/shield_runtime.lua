local S=NHShields or dofile("mods/noita_hideout/files/shields.lua")
local R={}
local poly=dofile("mods/noita_hideout/files/polymorph_protection.lua")
R.canMimic,R.allowMimic=poly.canMimic,poly.allowMimic
local function component(player,tag)
    return EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent",tag)
end
local function meter(player) return component(player,"nh_equipped_shield") end
local function clock(player) return component(player,"nh_shield_clock") end
local function key(s,row) return table.concat({s.profile,s.runSerial,row.id,row.epoch or 0},"/") end
local checkpoint="noita_hideout.equipped_shield"
local function remember(identity,charge,repair,ready)
    GlobalsSetValue(checkpoint,table.concat({identity,charge,repair,ready},":"))
end
local function clearEffect(player,tag)
    local child=(EntityGetAllChildren(player,tag) or {})[1]
    if not child then return end
    local prior=component(child,"nh_shield_resists")
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if prior and dm then
        for _,pair in ipairs({{"ice","value_float"},{"poison","value_string"}}) do
            if ComponentObjectGetValue2(dm,"damage_multipliers",pair[1])==0 then
                ComponentObjectSetValue2(dm,"damage_multipliers",pair[1],tonumber(ComponentGetValue2(prior,pair[2])))
            end
        end
    end
    EntityRemoveFromParent(child)
    EntityKill(child)
end

local function effects(player,tag,d)
    local child=(EntityGetAllChildren(player,tag) or {})[1]
    if child and d and EntityGetName(child)==d.kind then return end
    if child then clearEffect(player,tag) end
    if not d or #d.effects==0 then return end
    child=EntityCreateNew(d.kind)
    EntityAddTag(child,tag)
    EntityAddComponent2(child,"InheritTransformComponent",{})
    EntityAddChild(player,child)
    for _,effect in ipairs(d.effects) do
        EntityAddComponent2(child,"GameEffectComponent",{effect=effect,frames=-1,exclusivity_group=0})
    end
    if d.kind=="shield_frost" then
        local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
        if dm then
            EntityAddComponent2(child,"VariableStorageComponent",{_tags="nh_shield_resists",
                value_float=ComponentObjectGetValue2(dm,"damage_multipliers","ice"),
                value_string=tostring(ComponentObjectGetValue2(dm,"damage_multipliers","poison"))})
            ComponentObjectSetValue2(dm,"damage_multipliers","ice",0)
            ComponentObjectSetValue2(dm,"damage_multipliers","poison",0)
        end
        EntityAddComponent2(child,"LuaComponent",{script_source_file="mods/noita_hideout/files/injector_antitoxin.lua",execute_every_n_frame=1})
    end
end

-- The player's serialized components carry live combat state between saves.
-- Profile transactions copy it back to the same equipped item before moving it.
function R.snapshot(s,player)
    local row=s.gearShield
    if not row then return end
    local identity=key(s,row)
    local m=player and EntityGetIsAlive(player) and meter(player)
    local ready
    if m and ComponentGetValue2(m,"value_string")==identity then
        row.item.charge=ComponentGetValue2(m,"value_int")
        row.item.repair=ComponentGetValue2(m,"value_float")
        ready=ComponentGetValue2(clock(player),"value_int")
    else
        local token,charge,repair,deadline=GlobalsGetValue(checkpoint,""):match("^([^:]+):(%d+):(%d+):(%d+)$")
        if token~=identity then return end
        row.item.charge,row.item.repair,ready=tonumber(charge),tonumber(repair),tonumber(deadline)
    end
    row.item.delay=math.max(0,math.min(180,ready-GameGetFrameNum()))
end

function R.ensureDamageHook(player)
    local hook=EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_shield_damage")
    if not hook then
        hook=EntityAddComponent2(player,"LuaComponent",{_tags="nh_shield_damage",execute_every_n_frame=-1,
            script_damage_received="mods/noita_hideout/files/shield_damage.lua"})
    end
    local before="mods/noita_hideout/files/shield_damage.lua"
    if hook and hook~=0 and ComponentGetValue2(hook,"script_damage_about_to_be_received")~=before then
        ComponentSetValue2(hook,"script_damage_about_to_be_received",before)
    end
    return hook and hook~=0
end

function R.sync(s,player)
    R.ensureDamageHook(player)
    local row=s.gearShield
    local m=meter(player)
    -- Re-arm both sources after a failed staff cast or a return from mimicry.
    NHCompanions.immunities.apply(player,NHCompanions.active(player))
    poly.set(player,"nh_poly_shield",row and S.types[row.item.kind].poly)
    if not row then
        if m then
            clearEffect(player,"nh_shield_elements")
            EntityRemoveComponent(player,m)
            EntityRemoveComponent(player,clock(player))
        end
        return
    end
    local timer=clock(player)
    if not m then m=EntityAddComponent2(player,"VariableStorageComponent",{_tags="nh_equipped_shield"}) end
    if not timer then timer=EntityAddComponent2(player,"VariableStorageComponent",{_tags="nh_shield_clock"}) end
    if not m or not timer then return end
    local identity=key(s,row)
    if ComponentGetValue2(m,"value_string")~=identity then
        R.snapshot(s,nil)
        ComponentSetValue2(m,"name",row.item.kind)
        ComponentSetValue2(m,"value_string",identity)
        ComponentSetValue2(m,"value_int",row.item.charge)
        ComponentSetValue2(m,"value_float",row.item.repair or 0)
        ComponentSetValue2(timer,"value_int",GameGetFrameNum()+(row.item.delay or 0))
        ComponentSetValue2(timer,"value_string",tostring(GameGetFrameNum()))
        remember(identity,row.item.charge,row.item.repair or 0,ComponentGetValue2(timer,"value_int"))
    end
    local d=S.types[row.item.kind]
    local frame=GameGetFrameNum()
    local charge,repair=ComponentGetValue2(m,"value_int"),ComponentGetValue2(m,"value_float")
    if charge<d.cells*S.cell and frame>ComponentGetValue2(timer,"value_int") and tonumber(ComponentGetValue2(timer,"value_string"))~=frame then
        local mana=GameGetGameEffectCount(player,"MANA_REGENERATION")>0 or #(EntityGetAllChildren(player,"noita_hideout_meal_spice") or {})>0
        local nextCharge,nextRepair=S.recharge(charge,repair,d.cells,mana)
        if charge~=nextCharge or repair~=nextRepair then
            charge,repair=nextCharge,nextRepair
            ComponentSetValue2(m,"value_int",charge)
            ComponentSetValue2(m,"value_float",repair)
            remember(identity,charge,repair,ComponentGetValue2(timer,"value_int"))
        end
        ComponentSetValue2(timer,"value_string",tostring(frame))
    end
    effects(player,"nh_shield_elements",charge>0 and d)
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    return {kind=d.kind,charge=charge,repair=repair,cells=d.cells,maxHp=dm and ComponentGetValue2(dm,"max_hp")}
end

function R.hit(player,damage)
    local m=meter(player)
    if not m or damage<=0 then return damage,0,0 end
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not dm then return damage,0,0 end
    local d=S.types[ComponentGetValue2(m,"name")]
    local before=ComponentGetValue2(m,"value_int")
    local after,spill=S.absorb(before,ComponentGetValue2(dm,"max_hp"),d.resist,damage)
    ComponentSetValue2(m,"value_int",after)
    ComponentSetValue2(m,"value_float",0)
    ComponentSetValue2(clock(player),"value_int",GameGetFrameNum()+180)
    remember(ComponentGetValue2(m,"value_string"),after,0,GameGetFrameNum()+180)
    if before>0 and after==0 then clearEffect(player,"nh_shield_elements") end
    return spill,before,after
end
return R
