-- A packed perk remains a single physical item. Equipped cards are direct
-- children of this run's player; only the effect on that card is ours to remove.
NHPerks={}
local card_tag="noita_hideout_perk_card"
local type_tag="noita_hideout_perk_type"
local effect_tag="noita_hideout_perk_effect"
local pack_radius=18
local supported={
    PROTECTION_FIRE="fire", PROTECTION_RADIOACTIVITY="radioactivity",
    PROTECTION_ELECTRICITY="electricity", PROTECTION_MELEE="melee", PROTECTION_EXPLOSION="explosion",
}

local function component(id,kind,tag)
    return EntityGetFirstComponentIncludingDisabled(id,kind,tag)
end

local function card_info(id)
    if not id or not EntityGetIsAlive(id) or not EntityHasTag(id,card_tag) then return end
    local var=component(id,"VariableStorageComponent",type_tag)
    if not var then return end
    local perk=ComponentGetValue2(var,"value_string")
    if supported[perk] then return perk,var end
end

local function record(perk)
    local key=perk:lower()
    return {kind="perk",perk=perk,name="$perk_"..key,icon="data/ui_gfx/perk_icons/"..key..".png"}
end

local function restore(item,x,y)
    local suffix=supported[item.perk]
    if not suffix then return nil,"Unknown packed perk." end
    local id=EntityLoad("mods/noita_hideout/files/items/perk_"..suffix..".xml",x,y)
    if id and id~=0 and card_info(id)==item.perk then return id end
    if id and id~=0 then EntityKill(id) end
    return nil,"Could not create packed perk."
end

local function equipped(player)
    local slots={}
    for _,id in ipairs(EntityGetAllChildren(player) or {}) do
        local perk,var=card_info(id)
        if perk then
            local slot=ComponentGetValue2(var,"value_int")
            if slot>0 then slots[slot]=id end
        end
    end
    return slots
end

local function valid_slot(state,slot)
    return type(slot)=="number" and slot==math.floor(slot) and slot>=1 and slot<=NHStore.level(state,"perk_slots")
end

local function equipped_record(state,player,slot,id)
    if not GameIsInventoryOpen() or not valid_slot(state,slot) or not id or equipped(player)[slot]~=id then
        return nil,"Inventory slot changed."
    end
    return record(card_info(id))
end

NHTransfers.registerItem("perk",function(id) return EntityHasTag(id,card_tag) end,{
    capture=function(id)
        local perk=card_info(id)
        if not perk then return nil,"Unknown packed perk." end
        if component(id,"GameEffectComponent",effect_tag) then return nil,"Unequip this perk first." end
        return record(perk)
    end,
    captureEquipped=equipped_record,
    restore=restore,
})

local function in_native_slot(player,slot)
    if type(slot)~="table" or slot.lane~="tool" or slot.yslot~=0 or type(slot.xslot)~="number"
        or slot.xslot~=math.floor(slot.xslot) or slot.xslot<0 or slot.xslot>3 then return false end
    if not slot.parent or EntityGetParent(slot.parent)~=player or EntityGetName(slot.parent)~="inventory_quick" then return false end
    for _,id in ipairs(EntityGetAllChildren(slot.parent) or {}) do
        local item=component(id,"ItemComponent")
        if item and NHTransfers.item_kind(id)~="wand" then
            local x,y=ComponentGetValue2(item,"inventory_slot")
            if x==slot.xslot and y==slot.yslot then return true,id end
        end
    end
    return true
end

local function refresh_inventory(player)
    local inventory=component(player,"Inventory2Component")
    if not inventory then return end
    ComponentSetValue2(inventory,"mForceRefresh",true)
end

local function effect(id,perk)
    local c=component(id,"GameEffectComponent",effect_tag)
    if c then return c end
    return EntityAddComponent2(id,"GameEffectComponent",{_tags=effect_tag,effect=perk,frames=-1})
end

local function can_equip(state,player,slot,perk)
    if not GameIsInventoryOpen() or not valid_slot(state,slot) or not supported[perk] then return nil,"Inventory slot changed." end
    local slots=equipped(player)
    if slots[slot] then return nil,"Inventory slot changed." end
    for _,other in pairs(slots) do if card_info(other)==perk then return nil,"Perk already equipped." end end
    return true
end

local function attach(player,id,slot)
    local perk,var=card_info(id)
    if not effect(id,perk) then return nil,"Could not activate perk." end
    EntitySetComponentsWithTagEnabled(id,"enabled_in_hand",false)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_world",false)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_inventory",false)
    EntityRemoveFromParent(id)
    EntityAddChild(player,id)
    ComponentSetValue2(var,"value_int",slot)
    refresh_inventory(player)
    return true
end

function NHPerks.equip(state,player,id,slot,source)
    local valid,live=in_native_slot(player,source)
    if not valid or live~=id then return nil,"Inventory slot changed." end
    local ok,reason=can_equip(state,player,slot,card_info(id))
    if not ok then return nil,reason end
    return attach(player,id,slot)
end

local function storage_request(request)
    return type(request)=="table" and (request.container=="safe" or request.container=="warehouse")
        and type(request.storageSlot)=="number" and request.storageSlot>=1 and request.storageSlot==math.floor(request.storageSlot)
end

function NHPerks.equipStored(state,player,request)
    if not storage_request(request) then return nil,"Inventory slot changed." end
    local index=NHStore.slotIndex(state,request.container,request.storageSlot,"perk")
    local row=index and state[request.container][index]
    if not row or row.id~=request.entity or row.item.kind~="perk" then return nil,"Inventory slot changed." end
    local ok,reason=can_equip(state,player,request.perkSlot,row.item.perk)
    if not ok then return nil,reason end
    return NHTransfers.withdraw(state,player,index,request.container,function(id)
        return attach(player,id,request.perkSlot)
    end)
end

function NHPerks.storeEquipped(state,player,request)
    if not storage_request(request) then return nil,"Inventory slot changed." end
    return NHTransfers.depositEquippedPerk(state,player,request)
end

function NHPerks.unequip(state,player,slot,id,target)
    local valid,live=in_native_slot(player,target)
    if not GameIsInventoryOpen() or not valid_slot(state,slot) or not valid or live or not id
        or equipped(player)[slot]~=id then return nil,"Inventory slot changed." end
    local _,var=card_info(id)
    local c=component(id,"GameEffectComponent",effect_tag)
    if c then EntityRemoveComponent(id,c) end
    ComponentSetValue2(var,"value_int",0)
    EntityRemoveFromParent(id)
    EntityAddChild(target.parent,id)
    ComponentSetValue2(component(id,"ItemComponent"),"inventory_slot",target.xslot,0)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_inventory",true)
    refresh_inventory(player)
    return true
end

function NHPerks.update(state,player)
    for slot,id in pairs(equipped(player)) do
        if valid_slot(state,slot) then effect(id,card_info(id))
        else
            -- A rolled-back profile may have fewer unlocked slots than the world.
            -- Release the physical card rather than hiding it in an inaccessible slot.
            local _,var=card_info(id)
            local c=component(id,"GameEffectComponent",effect_tag)
            if c then EntityRemoveComponent(id,c) end
            ComponentSetValue2(var,"value_int",0)
            EntityRemoveFromParent(id)
            local x,y=EntityGetTransform(player)
            EntitySetTransform(id,x,y)
            EntitySetComponentsWithTagEnabled(id,"enabled_in_world",true)
        end
    end
end

local function pickup_info(id)
    if not EntityGetIsAlive(id) or EntityGetParent(id)~=0 or not EntityHasTag(id,"item_perk") then return end
    local price=component(id,"ItemCostComponent")
    if price and ComponentGetValue2(price,"cost")>0 then return end
    local perk,keep
    for _,c in ipairs(EntityGetComponentIncludingDisabled(id,"VariableStorageComponent") or {}) do
        local key=ComponentGetValue2(c,"name")
        if key=="perk_id" then perk=ComponentGetValue2(c,"value_string")
        elseif key=="perk_dont_remove_others" then keep=ComponentGetValue2(c,"value_bool") end
    end
    if supported[perk] then return perk,keep end
end

local function nearest(player)
    local x,y=EntityGetTransform(player)
    local best,kind,distance
    for _,id in ipairs(EntityGetInRadiusWithTag(x,y,pack_radius,"item_perk") or {}) do
        local perk=pickup_info(id)
        if perk then
            local ex,ey=EntityGetTransform(id)
            local d=(ex-x)^2+(ey-y)^2
            if not distance or d<distance or (d==distance and id<best) then best,kind,distance=id,perk,d end
        end
    end
    return best,kind
end

-- Match the native perk choice and reroll rules without granting an irreversible
-- run perk. Perks explicitly spawned as independent choices keep their siblings.
local function finish_choice(player,id,keep)
    local x,y=EntityGetTransform(id)
    local px,py=EntityGetTransform(player)
    local choices=EntityGetInRadiusWithTag(px,py,200,"item_perk") or {}
    local disable=#choices<=1
    if not keep then
        SetRandomSeed(x,y)
        if Random(1,100)<=tonumber(GlobalsGetValue("TEMPLE_PERK_DESTROY_CHANCE","100")) then
            disable=true
            for _,other in ipairs(EntityGetWithTag("perk") or {}) do if other~=id then EntityKill(other) end end
        end
    end
    if disable then
        for _,machine in ipairs(EntityGetInRadiusWithTag(px,py,200,"perk_reroll_machine") or {}) do
            local price=component(machine,"ItemCostComponent")
            if price then EntitySetComponentIsEnabled(machine,price,false) end
            for _,sprite in ipairs(EntityGetComponentIncludingDisabled(machine,"SpriteComponent","shop_cost") or {}) do
                EntitySetComponentIsEnabled(machine,sprite,false)
            end
            EntitySetComponentsWithTagEnabled(machine,"perk_reroll_disable",false)
        end
    end
    EntityKill(id)
end

function NHPerks.pack(state,player,id)
    if not GameIsInventoryOpen() or NHStore.level(state,"perk_pack")<1 or not id or nearest(player)~=id then
        return nil,"No packable perk nearby."
    end
    local perk,keep=pickup_info(id)
    if not perk then return nil,"No packable perk nearby." end
    local x,y=EntityGetTransform(id)
    local card,reason=restore(record(perk),x,y)
    if not card then return nil,reason end
    finish_choice(player,id,keep)
    return true
end

function NHPerks.view(state,player,model)
    model.perkCapacity=NHStore.level(state,"perk_slots")
    model.perkCells={}
    if model.perkCapacity>0 then
        for slot,id in pairs(equipped(player)) do
            local v=record(card_info(id))
            v.entity,v.name=id,GameTextGetTranslatedOrNot(v.name)
            model.perkCells[slot]=v
        end
    end
    model.packablePerk=nil
    if NHStore.level(state,"perk_pack")>0 then
        local id,perk=nearest(player)
        if id then model.packablePerk={entity=id,name=GameTextGetTranslatedOrNot(record(perk).name)} end
    end
end

function NHPerks.draw(gui,model,ox,oy,scale,pw,qw,qh,tr,slot,slots,dispatch)
    local capacity=model.perkCapacity or 0
    local nearby=model.packablePerk
    if capacity==0 and not nearby then return end
    local height=16+(capacity>0 and qh+5 or 0)+(nearby and 14 or 0)
    local offset=(model.popup and -66 or 0)-height-5
    local top=oy+offset*scale
    GuiZSetForNextWidget(gui,-79)
    GuiImageNinePiece(gui,4200,ox,top,pw*scale,height*scale,1)
    GuiText(gui,ox+8*scale,top+3*scale,tr("特质栏","Perks"),scale)
    for n=1,capacity do
        local v=model.perkCells[n] or {}
        slot(n-1,offset+16,"perk",v.kind,v.name or tr("特质空格","Empty perk slot"),v.icon,v.entity)
        slots[#slots].perkSlot=n
    end
    if nearby then
        local x,y=ox+8*scale,top+(height-13)*scale
        if GuiButton(gui,4201,x,y,tr("封装附近特质","Pack nearby perk"),scale) then dispatch("pack_perk",{entity=nearby.entity}) end
        GuiTooltip(gui,nearby.name,tr("消耗地上这次特质选择，封装后在脚边拾取。","Uses this perk choice; pick up the card at your feet."))
    end
    return top
end
