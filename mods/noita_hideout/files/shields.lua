local S={types={},legacyIcons={},order={},chargerOrder={},chargers={},cell=60000,charger="shield_charger"}
local function define(kind,zh,en,cells,resist,scrap,legacySprite,effects,poly)
    local d={kind=kind,zh=zh,en=en,cells=cells,resist=resist,scrap=scrap,effects=effects or {},poly=poly,
        icon="mods/noita_hideout/files/items/"..kind..".png"}
    S.legacyIcons[kind]="data/ui_gfx/perk_icons/"..legacySprite..".png"
    S.order[#S.order+1]=kind
    S.types[kind]=d
end
define("shield_basic","一级护盾","I · Arcane shield",2,25,3,"shield")
define("shield_fire","二级抗火盾","II · Fire shield",3,50,6,"protection_fire",{"PROTECTION_FIRE"})
define("shield_electric","二级抗电盾","II · Electric shield",3,50,6,"protection_electricity",{"PROTECTION_ELECTRICITY"})
define("shield_storm","三级火电盾","III · Fire and lightning shield",4,75,12,"electricity",{"PROTECTION_FIRE","PROTECTION_ELECTRICITY"},true)
define("shield_frost","三级冰毒盾","III · Frost and poison shield",4,75,12,"freeze_field",{"PROTECTION_FREEZE","PROTECTION_RADIOACTIVITY","PROTECTION_FOOD_POISONING"},true)
local function charger(kind,zh,en,scrap,gold,seconds,restore,legacySprite)
    local d={kind=kind,zh=zh,en=en,scrap=scrap,gold=gold,uses=8,castFrames=seconds*60,restore=restore,
        icon="mods/noita_hideout/files/items/"..kind..".png"}
    S.legacyIcons[kind]="data/ui_gfx/perk_icons/"..legacySprite..".png"
    d.noteZh=("右键使用 %d 秒，最多修复 %d 格碎盾。每支可用 8 次。"):format(seconds,restore)
    d.noteEn=("Right-click for %d s to restore up to %d broken cells. Eight uses per charger."):format(seconds,restore)
    S.chargerOrder[#S.chargerOrder+1]=kind
    S.chargers[kind]=d
end
charger(S.charger,"低级充能器","Basic charger",1,10,5,1,"extra_mana")
charger("improved_shield_charger","进阶充能器","Improved charger",2,20,3,2,"mana_from_kills")
charger("advanced_shield_charger","高级充能器","Advanced charger",3,20,2,4,"electricity")

function S.recipe(d)
    local item={kind=d.kind,icon=d.icon,name="$nh_hideout_"..d.kind}
    local zh,en
    if d.cells then
        item.charge=d.cells*S.cell
        zh=d.cells.." 格 · 盾上减伤 "..d.resist.."%"..(d.poly and " · 防变形" or "")
        en=d.cells.." cells · "..d.resist.."% resistance"..(d.poly and " · Polymorph immunity" or "")
    else
        item.count,item.remaining=4,d.uses
        zh,en=d.noteZh,d.noteEn
    end
    return {id=d.kind,category="equipment",zh=d.zh,en=d.en,inputs={},resources={arcane_scrap=d.scrap},
        count=item.count,goldCost=d.gold,durationFrames=60*d.scrap,item=item,noteZh=zh,noteEn=en}
end

-- Charge is measured in fractions of a cell. A max-HP change preserves the
-- filled fraction and the broken cells. Exact integer boundaries stay broken.
function S.chargePoints(charge,maxHP)
    local hpScale=tonumber(MagicNumbersGetValue("GUI_HP_MULTIPLIER")) or 25
    return charge/S.cell*(maxHP/2)*hpScale
end

function S.absorb(charge,maxHP,resist,damage)
    if damage<=0 or maxHP<=0 or charge<=0 then return charge,damage end
    local unitsPerDamage=(1-resist/100)*S.cell/(maxHP/2)
    if damage*unitsPerDamage>=charge then return 0,math.max(0,damage-charge/unitsPerDamage) end
    return charge-math.max(1,math.floor(damage*unitsPerDamage+0.5)),0
end

function S.recharge(charge,repair,cells,mana)
    local partial=charge%S.cell
    if partial>0 then
        return charge+math.min(S.cell-partial,mana and 1000 or 500),0
    elseif mana and charge<cells*S.cell then
        repair=repair+1
        if repair>=360 then return charge+S.cell,0 end
        return charge,repair
    end
    return charge,0
end

S.fields={"gearShield","gearCharger","gearRig","gearAmmo","gearLink"}
function S.slot(kind)
    if NHEquipment.links[kind] then return 5 end
    if S.types[kind] then return 1 end
    if S.chargers[kind] then return 2 end
    if NHFirearms.rigs[kind] then return 3 end
    if NHFirearms.packs[kind] then return 4 end
end
function S.field(kind) return S.fields[S.slot(kind)] end
function S.supply(kind)
    return S.chargers[kind] or NHFirearms.packs[kind]
end

function S.valid(item)
    if NHEquipment.links[item.kind] then
        return NHEquipment.linkUses(item.kind,item.remaining)~=nil and (item.count==nil or item.count==1)
    end
    if NHFirearms.rigs[item.kind] or NHFirearms.packs[item.kind] then return NHFirearms.valid(item) end
    local d=S.types[item.kind]
    if d then
        local function integer(v,limit) return type(v)=="number" and v>=0 and v<=limit and v==math.floor(v) end
        return integer(item.charge,d.cells*S.cell) and integer(item.repair or 0,359) and integer(item.delay or 0,180)
    end
    return S.chargers[item.kind] and NHMedkits.charges(item)~=nil
end

-- Gear is owned by the profile just like the secure case. All moves run on a
-- detached snapshot, including the exchange of an already-equipped shield.
function S.move(s,r)
    local loading=r.destination=="gear"
    local store=loading and r.source or r.destination
    if store~="safe" and store~="warehouse" then return false,"Inventory slot changed." end
    local field=S.field(r.kind)
    local supply=S.supply(r.kind)
    if not field then return false,"Inventory slot changed." end
    local index=NHStore.slotIndex(s,store,loading and r.from or r.safeSlot,r.kind)
    local row=index and s[store][index]
    local gear=s[field]
    if loading then
        if not row or row.id~=r.entity or row.item.kind~=r.kind or not S.valid(row.item) then return false,"Inventory slot changed." end
        if supply and gear then return false,"Equipment slot occupied." end
        if supply and row.item.count>1 then
            if s.nextItemId>=NHStore.maxResourceAmount then return false,"Item ID limit reached." end
            local unit={}
            for k,v in pairs(row.item) do unit[k]=v end
            unit.count=1
            row.item.count,row.item.remaining=row.item.count-1,supply.uses
            s[field]={id=s.nextItemId,item=unit}
            s.nextItemId=s.nextItemId+1
        else
            table.remove(s[store],index)
            if gear then gear.slot=row.slot; table.insert(s[store],gear) end
            row.slot=nil
            s[field]=row
        end
    else
        if r.source~="gear" or not gear or gear.id~=r.entity or gear.item.kind~=r.kind then return false,"Inventory slot changed." end
        if row and supply and NHStore.stackSlot(s,store,gear.item,r.safeSlot) then
            NHStore.mergeStack(row.item,gear.item)
        else
            if not NHStore.freeSlot(s,store,r.safeSlot,r.kind) then return false,"Inventory slot changed." end
            gear.slot=r.safeSlot
            table.insert(s[store],gear)
        end
        s[field]=nil
    end
    if (field=="gearShield" or field=="gearRig") and s[field] then s[field].epoch=s.revision+1 end
    if field=="gearShield" and s[field] then s[field].equippedAt=s[field].epoch end
    return true
end

function S.broken(row)
    if not row then return 0 end
    return S.types[row.item.kind].cells-math.ceil(row.item.charge/S.cell)
end

function S.repair(s,kind)
    local shield=s.gearShield
    local cells=math.min(S.broken(shield),S.chargers[kind].restore)
    if cells<=0 then return false,"No broken shield cell." end
    shield.item.charge,shield.item.repair=shield.item.charge+cells*S.cell,0
    shield.epoch=s.revision+1
    return true
end
return S
