-- Profiles predating typed injectors stored fire doses without a subtype.
local M={types={},order={}}
local root="mods/noita_hideout/files/"

local function define(id,zh,en,essence,cost,workSeconds,seconds,zhEffect,enEffect)
    local filename=id=="fire" and "dose" or "dose_"..id
    local effect=id=="fire" and "stimulant" or "stimulant_"..id
    M.types[id]={id=id,zh=zh,en=en,essence="essence_"..essence,cost=cost,workSeconds=workSeconds,
        seconds=seconds,filename=filename,icon=root.."items/"..filename..".png",effect=effect,
        tag="noita_hideout_"..effect,zhEffect=zhEffect,enEffect=enEffect}
    M.order[#M.order+1]=id
end

define("fire","耐火激活剂","Fire injector","fire",6,120,60,"60 秒火焰免疫","60 seconds of fire immunity")
define("lightning","耐电激活剂","Lightning injector","lightning",6,120,60,"60 秒雷电免疫","60 seconds of electricity immunity")
define("frost","耐冰激活剂","Frost injector","frost",6,120,60,"60 秒冰冻免疫","60 seconds of freeze immunity")
define("healing","持续治疗激活剂","Regeneration injector","healing",4,120,60,
    "60 秒内每 2 秒恢复 1 点生命","1 HP every 2 seconds for 60 seconds")
define("quick_heal","快速治疗针","Quick-heal injector","healing",4,60,0,
    "立即恢复最多 25 点生命","up to 25 HP immediately")
define("healing_2","强化持续治疗激活剂","Advanced regeneration injector","healing",8,150,60,
    "60 秒内每秒恢复 1 点生命","1 HP per second for 60 seconds")
define("regen_mana","回春回魔激活剂","Health and mana injector","healing",6,150,60,
    "60 秒内每 2 秒恢复 1 点生命，同时加快法力回复","faster mana recharge and 1 HP every 2 seconds for 60 seconds")
define("shield","飞弹护盾激活剂","Projectile shield injector","force",6,120,30,
    "30 秒可充能的飞弹护盾","a rechargeable projectile shield for 30 seconds")
define("haste","加速激活剂","Haste injector","displacement",4,60,60,
    "60 秒行动加速","60 seconds of faster movement")
define("invisible","隐身激活剂","Invisibility injector","polymorph",5,90,30,
    "30 秒原版隐身效果","30 seconds of invisibility")
define("rage","狂暴激活剂","Berserk injector","enhancement",6,90,30,
    "30 秒原版狂暴效果","30 seconds of berserk")
define("physical","物理防护激活剂","Physical protection injector","force",6,120,60,
    "60 秒近战伤害免疫","60 seconds of melee immunity")
define("poison","抗毒激活剂","Antitoxin injector","toxin",6,120,60,
    "60 秒毒泥免疫并持续解除中毒","60 seconds of toxic sludge immunity and poison removal")
define("resist_all","全面防护激活剂","All-protection injector","force",9,180,10,
    "10 秒原版灵丹妙药保护","10 seconds of ambrosia protection")

function M.get(id)
    return M.types[id or "fire"]
end

function M.recipe(id)
    local d=M.types[id]
    return {id=id=="fire" and "injector" or "injector_"..id,category="medical",facility="injector",
        zh=d.zh,en=d.en,durationFrames=d.workSeconds*60,inputs={},resources={active_herb=2,[d.essence]=d.cost},
        item={kind="dose",subtype=id,remaining=3,count=1},
        noteZh="每支 3 针，每针效果："..d.zhEffect.."。",noteEn="Three uses. Each grants "..d.enEffect.."."}
end

-- New effects stay detached until the durability transaction succeeds. Refresh
-- only this injector's child so native perks and food keep their own timers.
function M.use(player,subtype,pay)
    local d=M.get(subtype)
    if not d then return nil,"Unknown hideout item." end
    if d.id=="quick_heal" then
        local damage=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
        if not damage then return nil,"Could not create the stimulant effect." end
        local hp,maximum=ComponentGetValue2(damage,"hp"),ComponentGetValue2(damage,"max_hp")
        if hp<=0 then return nil end
        if hp>=maximum then return nil,"Health is full." end
        local ok,remaining=pay()
        if not ok then return nil,remaining end
        ComponentSetValue2(damage,"hp",math.min(maximum,hp+1)) -- One internal health unit equals 25 displayed HP.
        return true,remaining
    end

    local entity
    for _,child in ipairs(EntityGetAllChildren(player,d.tag) or {}) do
        if EntityHasTag(child,d.tag) then entity=child; break end
    end
    local fresh=not entity
    if fresh then
        local x,y=EntityGetTransform(player)
        entity=EntityLoad(root..d.effect..".xml",x,y)
        if not entity or entity==0 then return nil,"Could not create the stimulant effect." end
    end
    local regeneration=d.id=="healing" or d.id=="healing_2" or d.id=="regen_mana"
    local timer=EntityGetFirstComponentIncludingDisabled(entity,regeneration and "VariableStorageComponent" or "GameEffectComponent")
    if not timer or timer==0 then
        if fresh then EntityKill(entity) end
        return nil,"Could not create the stimulant effect."
    end
    local consumed,remaining=pay()
    if not consumed then
        if fresh then EntityKill(entity) end
        return nil,remaining
    end
    ComponentSetValue2(timer,regeneration and "value_int" or "frames",regeneration and d.seconds or d.seconds*60)
    if fresh then EntityAddChild(player,entity) end
    return true,remaining
end

return M
