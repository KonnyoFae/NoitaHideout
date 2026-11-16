local kits={
    order={"field_surgery_kit","tactical_surgery_kit","advanced_surgery_kit"},
    types={
        field_surgery_kit={zh="野战手术包",en="Field surgery kit",uses=1,healPercent=20,castFrames=180,
            ingredient="medkit",herbs=3,essence=20,workSeconds=30},
        tactical_surgery_kit={zh="战术手术包",en="Tactical surgery kit",uses=1,healPercent=35,castFrames=240,
            ingredient="tactical_medkit",herbs=5,essence=35,workSeconds=90},
        advanced_surgery_kit={zh="高端手术包",en="Advanced surgery kit",uses=1,healPercent=50,castFrames=300,
            ingredient="advanced_medkit",herbs=8,essence=50,workSeconds=180},
    },
}

for _,kit in pairs(kits.types) do
    kit.noteZh=string.format("手术用时 %d 秒。完成后清除负面状态并恢复最大生命值的 %d%%，消耗此包。受伤会中断手术。",kit.castFrames/60,kit.healPercent)
    kit.noteEn=string.format("Operate for %d seconds to remove negative effects and restore %d%% of maximum HP. Damage interrupts surgery. The kit is consumed on completion.",kit.castFrames/60,kit.healPercent)
end

function kits.recipe(kind)
    local kit=kits.types[kind]
    return {id=kind,category="medical",facility="medical",zh=kit.zh,en=kit.en,durationFrames=kit.workSeconds*60,
        inputs={},storedIngredient=kit.ingredient,resources={herb=kit.herbs,essence_healing=kit.essence},
        item={kind=kind,remaining=kit.uses,name="$nh_hideout_"..kind,icon="mods/noita_hideout/files/items/"..kind..".png"},
        noteZh=kit.noteZh,noteEn=kit.noteEn}
end

return kits
