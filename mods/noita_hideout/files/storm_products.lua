local M = {types = {}, stackLimit = 8}
local items = "mods/noita_hideout/files/items/"
local mercuryIcon=items.."storm_mercury.png"
local manaIcon=items.."storm_mana.png"

M.recipes={
    {id="refine_red_mercury",category="storm_products",icon=mercuryIcon,zh="分馏红水银",en="Distill red mercury",
        inputs={},resources={nh_red_mercury=1},materials={midas=20},resourceYield={nh_elixir_of_immortality=20},count=40,durationFrames=60},
    {id="refine_mana_arcane",category="storm_products",icon=manaIcon,zh="晶化法力制奥术碎片",en="Crystallized mana to arcane scrap",
        inputs={},resources={nh_crystallized_mana=1},resourceYield={arcane_scrap=20},count=20,durationFrames=60},
    {id="refine_mana_container",category="storm_products",icon=manaIcon,zh="晶化法力制容器碎片",en="Crystallized mana to container scrap",
        inputs={},resources={nh_crystallized_mana=1},resourceYield={container_scrap=20},count=20,durationFrames=60},
}

M.offers={
    {id="sell_red_mercury",category="storm_products",icon=mercuryIcon,resource="nh_red_mercury",
        zh="出售红水银",en="Sell red mercury",quantity=1,yield={gold=500}},
    {id="sell_crystallized_mana",category="storm_products",icon=manaIcon,resource="nh_crystallized_mana",
        zh="出售晶化法力",en="Sell crystallized mana",quantity=1,yield={gold=500}},
}

local function define(kind, zh, en, units, oil)
    M.types[kind] = {zh=zh, en=en, icon=items..kind..".png",units=units,
        resource=oil and "nh_red_mercury" or "nh_crystallized_mana"}
end

define("storm_mercury","罐装红水银","Canned red mercury",1,true)
define("storm_mercury_pressure","高压红水银","Pressurized red mercury",50,true)
define("storm_mana","法力晶块","Mana shard",1,false)
define("storm_mana_pure","高纯晶块","Pure mana shard",50,false)

-- Pre-stack warehouse records omit count. Old physical items use Noita's -1.
function M.count(n)
    if n==nil then return 1 end
    if type(n)=="number" and n>=1 and n<=M.stackLimit and n==math.floor(n) then return n end
end

function M.worldCount(item)
    if not item then return end
    local n=ComponentGetValue2(item,"uses_remaining")
    if n==-1 then return 1 end
    return M.count(n)
end

function M.refreshLegacyItems(player)
    for kind,product in pairs(M.types) do
        for _,e in ipairs(EntityGetWithTag(kind) or {}) do
            local item=EntityGetFirstComponentIncludingDisabled(e,"ItemComponent")
            local icon=item and ComponentGetValue2(item,"ui_sprite")
            if icon=="data/items_gfx/canister.png" or icon=="data/items_gfx/waterstone.png" or icon=="data/items_gfx/thunderstone.png" then
                local sprite=EntityGetFirstComponentIncludingDisabled(e,"SpriteComponent","enabled_in_hand")
                if sprite then
                    ComponentSetValue2(sprite,"offset_x",8)
                    ComponentSetValue2(sprite,"offset_y",8)
                end
                NHNative.refreshArt(e,item,product.icon)
                local uses=ComponentGetValue2(item,"uses_remaining")
                if uses==nil or uses==-1 then ComponentSetValue2(item,"uses_remaining",1) end
                EntityAddComponent2(e,"LuaComponent",{script_item_picked_up="mods/noita_hideout/files/bag_pickup.lua",execute_every_n_frame=-1})
                if EntityGetRootEntity(e)==player then
                    EntityAddTag(e,"nh_merge_pickup")
                    EntityAddTag(player,"nh_has_merge_pickup")
                end
            end
        end
    end
end

function M.register()
    for kind, def in pairs(M.types) do
        local id, product = kind, def
        NHTransfers.registerItem(id,function(e) return EntityHasTag(e,id) end,{
            warehouseCategory="supplies",
            capture=function(e)
                if EntityGetFirstComponentIncludingDisabled(e,"ItemCostComponent") then return nil,"Item unavailable." end
                local count=M.worldCount(EntityGetFirstComponentIncludingDisabled(e,"ItemComponent"))
                if not count then return nil,"Invalid storm product stack." end
                return {kind=id, count=count, name=product.zh, icon=product.icon}
            end,
            restore=function(record,x,y)
                local count=M.count(record.count)
                if not count then return nil,"Invalid storm product stack." end
                local e=EntityLoad(items..id..".xml",x,y)
                if not e or e==0 then return end
                local item=EntityGetFirstComponentIncludingDisabled(e,"ItemComponent")
                if not item then EntityKill(e); return end
                ComponentSetValue2(item,"uses_remaining",count)
                return e
            end,
        })
    end
end

return M
