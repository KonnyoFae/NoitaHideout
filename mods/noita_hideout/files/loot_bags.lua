local M={order={"travel_satchel","travel_pack","loot_case"},types={
    travel_satchel={zh="行囊",en="Satchel",gold=1,tarot=2,card=0,
        chances={food=55,medical=25,tool=20,dose=0},
        medical={"bandage","medkit","field_surgery_kit"},
        tools={"magic_tube","flare_gun","turret_pack","shield_charger","ammo_pack"}},
    travel_pack={zh="背包",en="Backpack",gold=2,tarot=5,card=2,
        chances={food=0,medical=40,tool=35,dose=25},
        medical={"tactical_medkit","tactical_surgery_kit"},
        tools={"fire_tube","frost_tube","rocket_turret_pack","improved_shield_charger","improved_ammo_pack"},
        doses={"fire","lightning","frost","healing","quick_heal","haste","poison"}},
    loot_case={zh="保险盒",en="Lockbox",gold=3,tarot=15,card=8,
        chances={food=0,medical=30,tool=35,dose=35},
        medical={"advanced_medkit","advanced_surgery_kit"},
        tools={"shock_tube","derringer","shield_turret_pack","advanced_shield_charger","advanced_ammo_pack"},
        doses={"healing_2","regen_mana","shield","invisible","rage","physical","resist_all"}},
}}
local root="mods/noita_hideout/files/items/"
M.packKinds={"supply_pack","improved_supply_pack","advanced_supply_pack"}
local function definePack(level,zh,en,charger,ammo)
    local kind=M.packKinds[level]
    local loot=M.order[level]
    M.types[kind]={zh=zh,en=en,loot=loot,icon=root..kind..".png",legacyIcon=root..loot..".png",charger=charger,ammo=ammo}
end
definePack(1,"基础补给箱","Basic supply box","shield_charger","ammo_pack")
definePack(2,"进阶补给箱","Improved supply box","improved_shield_charger","improved_ammo_pack")
definePack(3,"高级补给箱","Advanced supply box","advanced_shield_charger","advanced_ammo_pack")
local function defineGift(level,zh,food,relic)
    M.types["gift_box_"..level]={zh=zh,en="Gift box "..level,guaranteedPack=M.packKinds[level],
        food=food,relic=relic,tarot=100-food-relic}
end
defineGift(1,"一级礼物盒",60,30)
defineGift(2,"二级礼物盒",50,35)
defineGift(3,"三级礼物盒",40,40)
function M.item(kind,count)
    return {kind=kind,count=count or 1,name="$nh_hideout_"..kind,icon=M.types[kind].icon or root..kind..".png"}
end

local function tarotFile(roll)
    local tarot=NHTarot or dofile("mods/noita_hideout/files/tarot.lua")
    return root.."card_"..tarot.order[roll(#tarot.order)]..".xml"
end

local function giftBonusFile(bag,roll)
    local chance=roll(100)
    if chance<=bag.food then return root..NHFoods[roll(#NHFoods)].id..".xml" end
    if chance<=bag.food+bag.relic then
        local relics=NHRelics.dropFiles
        return relics[roll(#relics)]
    end
    return tarotFile(roll)
end

-- Stage the entire payout before charging the clicked item. Stored and
-- carried containers both open at the player's feet.
function M.open(player,kind,pay)
    local bag=M.types[kind]
    local tier=M.types[bag.loot] or bag
    local x,y=EntityGetTransform(player)
    local frame=GameGetFrameNum()
    local rollIndex=0
    local function roll(maximum)
        rollIndex=rollIndex+1
        return ProceduralRandomi(x+frame,y+player+rollIndex*7919,1,maximum)
    end
    local entities={}
    local dose,subtype
    local function spawn(entity)
        if entity and entity~=0 then entities[#entities+1]=entity; return true end
        return false
    end
    local function payout()
        if bag.guaranteedPack then
            if not spawn(EntityLoad(root..bag.guaranteedPack..".xml",x-5,y-4)) then return end
            if not spawn(EntityLoad(giftBonusFile(bag,roll),x+5,y-4)) then return end
            return pay()
        end
        if bag.loot then
            if not spawn(EntityLoad(root..bag.charger..".xml",x-6,y-6)) then return end
            if not spawn(EntityLoad(root..bag.ammo..".xml",x+6,y-6)) then return end
        end
        for i=1,tier.gold do
            if not spawn(EntityLoad("data/entities/items/pickup/goldnugget.xml",x+i-2,y-3)) then return end
        end
        local chance=tier.chances
        local draw=roll(100)
        local kind
        if draw<=chance.food then
            kind=NHFoods[roll(#NHFoods)].id
        elseif draw<=chance.food+chance.medical then
            kind=tier.medical[roll(#tier.medical)]
        elseif draw<=chance.food+chance.medical+chance.tool then
            kind=tier.tools[roll(#tier.tools)]
        else
            subtype=tier.doses[roll(#tier.doses)]
            dose=NHNative.spawn("dose",x-5,y-4,subtype)
            if not spawn(dose) then return end
        end
        if kind and not spawn(EntityLoad(root..kind..".xml",x-5,y-4)) then return end
        if roll(100)<=tier.tarot then
            if not spawn(EntityLoad(tarotFile(roll),x+5,y-4)) then return end
        end
        if tier.card>0 and roll(100)<=tier.card then
            local id=NHCompanions.order[roll(#NHCompanions.order)]
            if not spawn(EntityLoad(root.."card_"..id..".xml",x-9,y-5)) then return end
        end
        if not pay(dose,subtype) then return end
        if dose then NHDoses.confirmLoot(dose) end
        return true
    end
    if payout() then return true end
    for _,entity in ipairs(entities) do EntityKill(entity) end
end
return M
