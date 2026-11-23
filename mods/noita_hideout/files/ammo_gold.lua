-- Read the denomination before vanilla applies EXTRA_MONEY and destroys the nugget.
local original_gold_pickup=item_pickup
function item_pickup(entity,owner,name)
    local key=GlobalsGetValue("nh_ammo_gold_target","")
    local amount=0
    if key~="" and EntityHasTag(owner,"player_unit") and EntityHasTag(entity,"gold_nugget") then
        local value=10
        for _,c in ipairs(EntityGetComponentIncludingDisabled(entity,"VariableStorageComponent") or {}) do
            if ComponentGetValue2(c,"name")=="gold_value" then value=ComponentGetValue2(c,"value_int"); break end
        end
        amount=math.max(0,math.floor(value))
    end
    original_gold_pickup(entity,owner,name)
    if amount>0 then
        GlobalsSetValue(key,tostring((tonumber(GlobalsGetValue(key,"0")) or 0)+amount))
    end
end
