local foods={byId={}}
local function dish(id,zh,en,resources,seconds,facility)
    local food={id=id,zh=zh,en=en,resources=resources,workSeconds=seconds,facility=facility or "farmland",
        effects={},notesZh={},notesEn={}}
    local units=0
    for _,amount in pairs(resources) do units=units+amount end
    food.uses=math.max(2,units)
    local function effect(key,n,duration)
        food.effects[#food.effects+1]={key=key,strength=n,seconds=duration}
    end
    local function note(zhText,enText)
        table.insert(food.notesZh,zhText)
        table.insert(food.notesEn,enText)
    end
    local n=resources.grain
    if n then
        effect("grain",n,60*n)
        note(("每4秒恢复最大生命的%d%%，持续%d秒"):format(n,60*n),("%d%% of max HP every 4s for %ds"):format(n,60*n))
    end
    n=resources.sugar
    if n then
        effect("sugar",n,4*n)
        effect("speed",n,60*n)
        note(("每秒恢复最大生命的%d%%，持续%d秒；加速%d秒"):format(n,4*n,60*n),
            ("%d%% of max HP per second for %ds plus haste for %ds"):format(n,4*n,60*n))
    end
    for _,key in ipairs({"egg","meat"}) do
        n=resources[key]
        if n then
            local seconds=(key=="egg" and 120 or 25)*n
            local percent=(key=="egg" and 5 or 20)*n
            effect(key,percent,seconds)
            note(("减伤%d%%，持续%d秒"):format(percent,seconds),("%d%% damage reduction for %ds"):format(percent,seconds))
        end
    end
    if resources.milk then
        food.healPercent=4*resources.milk
        note("立即恢复最大生命的"..food.healPercent.."%","Restore "..food.healPercent.."% of max HP immediately")
    end
    n=resources.spice
    if n then
        effect("spice",n,60*n)
        note(("飞行加速，每秒补充%d%%飞行能量，持续%d秒"):format(5*n,60*n),
            ("Faster flight and +%d%% fuel/s for %ds"):format(5*n,60*n))
        note(("手持法杖每秒额外恢复%d魔力，持续%d秒"):format(10*n,60*n),
            ("+%d held wand mana/s for %ds"):format(10*n,60*n))
    end
    food.noteZh="每份"..food.uses.."口。"..table.concat(food.notesZh,"；").."。"
    food.noteEn=food.uses.." bites. "..table.concat(food.notesEn,". ").."."
    foods[#foods+1]=food
    foods.byId[id]=food
end
dish("hard_bread","硬面包","Hard bread",{grain=1},3)
dish("bread","白面包","White bread",{grain=2},5)
dish("sandwich","三明治","Sandwich",{grain=2,meat=1,egg=1,milk=1},18)
dish("cake","蛋糕","Cake",{grain=1,egg=1,milk=1,sugar=1},15)
dish("scrambled_egg","炒蛋","Scrambled egg",{egg=1},4)
dish("omelet","煎蛋卷","Omelet",{egg=2,milk=1},10)
dish("cheese","奶酪","Cheese",{milk=1},5)
dish("milkshake","奶昔","Milkshake",{milk=1,sugar=1},6)
dish("pudding","布丁","Pudding",{milk=2,egg=1,sugar=1},12)
dish("roast_meat","烤肉","Roast meat",{meat=1},6)
dish("steak","煎肉排","Spiced steak",{meat=1,spice=1},9)
dish("burger","汉堡","Burger",{meat=1,grain=1,milk=1,spice=1},15)
dish("sugar_cube","糖块","Sugar cube",{sugar=1},3)
dish("herb_flatbread","香料草药饼","Spiced herb flatbread",{spice=1,herb=1,grain=2},15,"agri_equipment")
dish("spice_cake","香甜米糕","Sweet spice cake",{spice=1,sugar=2,grain=2},20,"agri_equipment")
dish("milk_omelet","奶香蛋饼","Spiced milk omelet",{spice=1,grain=1,egg=1,milk=1},30,"agri_equipment")
dish("spiced_stew","香料炖肉","Spiced meat stew",{spice=2,herb=1,milk=1,meat=2},45,"agri_equipment")

-- Native items carry total bites in uses_remaining. Stored stacks expose the
-- number of portions and the bites left in the open portion.
function foods.bites(item)
    local food=foods.byId[item.kind]
    if not food then return end
    local count,remaining=item.count,item.remaining
    if count==nil then count=1 end
    if remaining==nil then remaining=food.uses end
    if type(count)~="number" or count<1 or count~=math.floor(count)
        or type(remaining)~="number" or remaining<1 or remaining>food.uses or remaining~=math.floor(remaining) then return end
    local total=(count-1)*food.uses+remaining
    if total<=2147483647 then return total end
end
function foods.setBites(item,total)
    local uses=foods.byId[item.kind].uses
    item.count=math.ceil(total/uses)
    item.remaining=(total-1)%uses+1
end
return foods
