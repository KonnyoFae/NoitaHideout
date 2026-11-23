local tablets={}
local books="data/entities/items/books/"
local byVariant,byDescription={},{}

local function define(variant,file,title,description,laboratory,forged)
    local def={variant=variant,file=books..file..".xml",title="$booktitle"..title,description="$bookdesc"..description,
        icon="data/ui_gfx/items/"..(laboratory and "laboratory_tablet" or "emerald_tablet")..".png",forged=forged or false}
    byVariant[variant],byDescription[def.description]=def,def
end
for index=0,10 do
    local number=("%02d"):format(index)
    define(number,"book_"..number,number,number)
    if index==2 or index>=4 then define("forged_"..number,"base_forged",number,number.."_forged",true,true) end
end
define("tree","book_tree","_tree","_tree")
define("corpse","book_corpse","_corpse","_corpse")
define("all_spells","book_all_spells","_allspells","_allspells",true)

local function identify(entity)
    if not EntityHasTag(entity,"tablet") then return end
    local component=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    local def=component and byDescription[ComponentGetValue2(component,"ui_description")]
    if def and ComponentGetValue2(component,"item_name")==def.title and ComponentGetValue2(component,"ui_sprite")==def.icon
        and EntityHasTag(entity,def.forged and "forged_tablet" or "normal_tablet") then return def end
end

function tablets.valid(item)
    return item.kind=="tablet" and byVariant[item.variant]~=nil and (item.count==nil or item.count==1)
end

function tablets.register()
    NHTransfers.registerItem("tablet",identify,{
        warehouseCategory="equipment",
        capture=function(entity)
            local def=identify(entity)
            if not def or EntityGetFirstComponentIncludingDisabled(entity,"ItemCostComponent") then return nil,"Tablet unavailable." end
            return {kind="tablet",variant=def.variant,name=def.title,icon=def.icon}
        end,
        restore=function(item,x,y)
            if not tablets.valid(item) then return nil,"Tablet unavailable." end
            local def=byVariant[item.variant]
            local entity=EntityLoad(def.file,x,y)
            if not entity or entity==0 then return nil,"Tablet unavailable." end
            if def.forged then
                local component=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                if not component then EntityKill(entity); return nil,"Tablet unavailable." end
                ComponentSetValue2(component,"item_name",def.title)
                ComponentSetValue2(component,"ui_description",def.description)
                for kind,key in pairs({UIInfoComponent="name",AbilityComponent="ui_name"}) do
                    local display=EntityGetFirstComponentIncludingDisabled(entity,kind)
                    if display then ComponentSetValue2(display,key,def.title) end
                end
            end
            return entity
        end,
    })
end
return tablets
