-- These pockets are children of the local player but are not native inventory
-- bags. The held item cannot be thrown or dragged from a native inventory slot.
local E={}
local tag="nh_ew_deposit_escrow"
local function component(e,kind) return EntityGetFirstComponentIncludingDisabled(e,kind) end
function E.box(player,id)
    local box=EntityGetParent(id)
    if not box or box==0 or EntityGetParent(box)~=player or EntityGetName(box)~=tag then return end
    local c=EntityGetFirstComponentIncludingDisabled(box,"VariableStorageComponent",tag)
    if c then return box,c end
end
function E.slot(player,id)
    local parent=EntityGetParent(id)
    if parent==player then return {bag="attached"} end
    if not parent or EntityGetParent(parent)~=player then return end
    local bag=EntityGetName(parent)
    if bag~="inventory_quick" and bag~="inventory_full" then return end
    local c=component(id,"ItemComponent")
    if not c then return end
    local x,y=ComponentGetValue2(c,"inventory_slot")
    if type(x)~="number" or type(y)~="number" then return end
    return {bag=bag,x=x,y=y}
end
local function refresh(player)
    local c=component(player,"Inventory2Component")
    if c then ComponentSetValue2(c,"mForceRefresh",true) end
end
local function attach(id,p)
    EntityRemoveFromParent(id);EntityAddChild(p,id)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_world",false)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_hand",false)
    EntitySetComponentsWithTagEnabled(id,"enabled_in_inventory",true)
    return EntityGetParent(id)==p
end
function E.stash(player,id,token,slot)
    if not slot then return false end
    if slot.bag=="attached" then return EntityGetParent(id)==player end
    local current,c=E.box(player,id)
    if current then return ComponentGetValue2(c,"value_string")==token end
    local old=E.slot(player,id)
    if not old or old.bag~=slot.bag then return false end
    local box=EntityCreateNew(tag)
    if not box or box==0 then return false end
    EntityAddTag(box,tag)
    local marker=EntityAddComponent2(box,"VariableStorageComponent",{_tags=tag,name=tag,value_string=token,
        value_bool=slot.bag=="inventory_quick",value_int=slot.x,value_float=slot.y})
    if not marker or marker==0 then EntityKill(box);return false end
    EntityAddChild(player,box)
    if EntityGetParent(box)~=player then EntityKill(box);return false end
    if CrossCall then pcall(CrossCall,"ew_hideout_deposit_unselect",player,id) end
    if not attach(id,box) then
        if #(EntityGetAllChildren(box) or {})==0 then EntityKill(box) end
        return false
    end
    refresh(player)
    return true
end
local function wand(id)
    local ability=component(id,"AbilityComponent")
    return EntityHasTag(id,"wand") or (ability~=nil and ComponentGetValue2(ability,"use_gun_script")==true)
end
local function placement(player,id,bag,x,y,alternatives)
    local parent
    for _,child in ipairs(EntityGetAllChildren(player) or {}) do if EntityGetName(child)==bag then parent=child;break end end
    if not parent then return end
    local inv=component(player,"Inventory2Component")
    if not inv then return end
    local full=bag=="inventory_full"
    local w=full and ComponentGetValue2(inv,"full_inventory_slots_x") or 4
    local h=full and ComponentGetValue2(inv,"full_inventory_slots_y") or 1
    if not w or not h or w<1 or h<1 then return end
    local occupied={}
    local wandLane=not full and wand(id)
    for _,other in ipairs(EntityGetAllChildren(parent) or {}) do
        local c=component(other,"ItemComponent")
        if c and EntityGetIsAlive(other) and (full or wand(other)==wandLane) then
            local ox,oy=ComponentGetValue2(c,"inventory_slot")
            if ox and oy then occupied[oy*w+ox]=true end
        end
    end
    if x>=0 and y>=0 and x<w and y<h and not occupied[y*w+x] then return parent,x,y end
    if alternatives then
        for n=0,w*h-1 do if not occupied[n] then return parent,n%w,math.floor(n/w) end end
    end
end
function E.release(player,id,token,alternatives)
    local box,marker=E.box(player,id)
    if not box then return true end
    if ComponentGetValue2(marker,"value_string")~=token then return false end
    local bag=ComponentGetValue2(marker,"value_bool") and "inventory_quick" or "inventory_full"
    local parent,x,y=placement(player,id,bag,ComponentGetValue2(marker,"value_int"),ComponentGetValue2(marker,"value_float"),alternatives)
    if not parent or not attach(id,parent) then return false end
    ComponentSetValue2(component(id,"ItemComponent"),"inventory_slot",x,y)
    if #(EntityGetAllChildren(box) or {})==0 then EntityKill(box) end
    refresh(player)
    return true
end
function E.each(player,fn)
    for _,box in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityGetName(box)==tag then
            for _,id in ipairs(EntityGetAllChildren(box) or {}) do fn(id) end
        end
    end
end
return E
