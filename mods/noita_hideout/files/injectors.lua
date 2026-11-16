-- Profiles predating typed injectors stored fire doses without a subtype.
local M={types={},order={"fire","lightning","frost","healing"}}

local function define(id,zh,en,essence,cost,zhEffect,enEffect)
    local filename=id=="fire" and "dose" or "dose_"..id
    local effect=id=="fire" and "stimulant" or "stimulant_"..id
    M.types[id]={id=id,zh=zh,en=en,essence=essence,cost=cost,filename=filename,
        icon="mods/noita_hideout/files/items/"..filename..".png",effect=effect,
        tag="noita_hideout_"..effect,zhEffect=zhEffect,enEffect=enEffect}
end

define("fire","耐火激活剂","Fire injector","essence_fire",180,"60 秒火焰免疫","60 seconds of fire immunity")
define("lightning","耐电激活剂","Lightning injector","essence_lightning",180,"60 秒雷电免疫","60 seconds of electricity immunity")
define("frost","耐冰激活剂","Frost injector","essence_frost",180,"60 秒冰冻免疫","60 seconds of freeze immunity")
define("healing","持续治疗激活剂","Regeneration injector","essence_healing",90,
    "60 秒内每 2 秒恢复 1 点生命","1 HP every 2 seconds for 60 seconds")

function M.get(id)
    return M.types[id or "fire"]
end

function M.recipe(id)
    local d=M.types[id]
    return {id=id=="fire" and "injector" or "injector_"..id,category="medical",facility="injector",
        zh=d.zh,en=d.en,inputs={},resources={active_herb=2,[d.essence]=d.cost},
        item={kind="dose",subtype=id,remaining=3,count=1},
        noteZh="每支 3 针，每针效果："..d.zhEffect.."。",noteEn="Three uses. Each grants "..d.enEffect.."."}
end
return M
