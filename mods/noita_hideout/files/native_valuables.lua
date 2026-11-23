local valuables={}
local pickup="data/entities/items/pickup/"
local icons="data/ui_gfx/items/"
local catalog={
    safe_haven={name="$item_safe_haven",icon=icons.."safe_haven.png"},
    beamstone={name="$item_mega_beam_stone",icon=icons.."beamstone.png"},
    physics_gold_orb={name="$item_gold_orb",icon=icons.."orb_gold.png"},
}

local function identify(id)
    if not EntityHasTag(id,"item_physics") then return end
    local path=(EntityGetFilename(id) or ""):gsub("\\","/"):lower()
    local variant=path:match("data/entities/items/pickup/([^/]+)%.xml$")
    if variant then return catalog[variant] and variant end
    -- Streamed inventory items can report the enclosing player as their filename.
    local item=EntityGetFirstComponentIncludingDisabled(id,"ItemComponent")
    if item then
        local name=ComponentGetValue2(item,"item_name")
        for key,def in pairs(catalog) do
            if name==def.name and ComponentGetValue2(item,"ui_sprite")==def.icon then return key end
        end
    end
end

function valuables.valid(item)
    if item.kind~="native_valuable" or not catalog[item.variant] or (item.count or 1)~=1 then return false end
    if item.variant~="physics_gold_orb" then return item.kicks==nil end
    local n=item.kicks
    return type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n)
end

function valuables.register()
    NHTransfers.registerItem("native_valuable",identify,{
        warehouseCategory="equipment",
        capture=function(id)
            local variant=identify(id)
            local def=catalog[variant]
            if not def or EntityGetFirstComponentIncludingDisabled(id,"ItemCostComponent") then return nil,"Item unavailable." end
            local record={kind="native_valuable",variant=variant,name=def.name,icon=def.icon}
            if variant=="physics_gold_orb" then
                local count=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","kick_count")
                record.kicks=count and ComponentGetValue2(count,"value_int")
                if not valuables.valid(record) then return nil,"Item unavailable." end
            elseif variant=="safe_haven" then
                for _,var in ipairs(EntityGetComponentIncludingDisabled(id,"VariableStorageComponent") or {}) do
                    if ComponentGetValue2(var,"name")=="throw_time" and ComponentGetValue2(var,"value_int")>=0 then
                        return nil,"This Kammi has already been activated."
                    end
                end
            end
            return record
        end,
        restore=function(record,x,y)
            if not valuables.valid(record) then return nil,"Item unavailable." end
            local id=EntityLoad(pickup..record.variant..".xml",x,y)
            if not id or id==0 then return nil,"Item unavailable." end
            if record.variant=="physics_gold_orb" then
                local count=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","kick_count")
                if not count then EntityKill(id);return nil,"Item unavailable." end
                ComponentSetValue2(count,"value_int",record.kicks)
            end
            return id
        end,
    })
end
return valuables
