local T={
    batchSize=8,
    order={"grenade","fire_grenade","frost_grenade","shock_grenade","sand_knife","metal_knife"},
    types={
        grenade={zh="魔法手雷",en="Magic grenade",speed=180,workSeconds=10,
            projectile="data/entities/projectiles/deck/grenade_small.xml",
            noteZh="投出后爆炸，伤及周围目标。",noteEn="Explodes and damages nearby targets."},
        fire_grenade={zh="火焰手雷",en="Fire grenade",speed=180,workSeconds=10,radius=30,
            noteZh="爆炸半径 %d，造成火焰伤害并点燃目标。",noteEn="A radius-%d blast deals fire damage and ignites targets."},
        frost_grenade={zh="冰冻手雷",en="Frost grenade",speed=180,workSeconds=10,radius=28,
            noteZh="爆炸半径 %d，造成冰冻伤害并短暂冻结目标。",noteEn="A radius-%d blast deals ice damage and briefly freezes targets."},
        shock_grenade={zh="雷电手雷",en="Shock grenade",speed=180,workSeconds=10,radius=32,
            noteZh="爆炸半径 %d，造成雷电伤害并短暂电击目标。",noteEn="A radius-%d blast deals electric damage and briefly shocks targets."},
        sand_knife={zh="砂晶飞刀",en="Sand crystal knife",speed=270,workSeconds=5,radius=18,
            noteZh="命中时扬起半径 %d 的砂尘，造成伤害并短暂致盲。",noteEn="Impact scatters sand in a radius of %d to damage and briefly blind targets."},
        metal_knife={zh="金属飞刀",en="Metal knife",speed=270,workSeconds=8,radius=22,
            noteZh="命中时迸出碎片，对半径 %d 内的目标造成切割伤害。",noteEn="Impact scatters fragments for slicing damage in a radius of %d."},
    },
}

for kind,def in pairs(T.types) do
    if def.radius then
        def.noteZh=string.format(def.noteZh,def.radius)
        def.noteEn=string.format(def.noteEn,def.radius)
    end
    def.projectile=def.projectile or "mods/noita_hideout/files/projectiles/"..kind..".xml"
    def.bundle={kind=kind,count=T.batchSize,name="$nh_hideout_"..kind,icon="mods/noita_hideout/files/items/"..kind..".png"}
end

function T.validCount(n)
    return type(n)=="number" and n>=1 and n<=T.batchSize and n==math.floor(n)
end

function T.count(item)
    -- Single magic grenades already in storage or in a paid order had no count.
    if item.kind=="grenade" and item.count==nil then return 1 end
    return item.count
end

function T.recipe(kind,inputs,resources,id,zh,en)
    local d=T.types[kind]
    return {id=id or kind,category="weapons",facility="grenade",zh=zh or d.zh,en=en or d.en,
        durationFrames=d.workSeconds*60,inputs=inputs or {},resources=resources,count=T.batchSize,item=d.bundle,
        noteZh=d.noteZh,noteEn=d.noteEn}
end

return T
