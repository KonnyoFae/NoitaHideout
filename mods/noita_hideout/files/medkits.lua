local M={
    order={"medkit","tactical_medkit","advanced_medkit"},
    types={
        medkit={zh="小医疗包",en="Medkit",uses=3,healHP=10},
        tactical_medkit={zh="战术医疗包",en="Tactical medkit",uses=9,healPercent=15},
        advanced_medkit={zh="高端医疗包",en="Advanced medkit",uses=12,healPercent=25},
    },
}

for _,kit in pairs(M.types) do
    if kit.healPercent then
        kit.noteZh=string.format("可用 %d 次，每次恢复最大生命值的 %d%%。",kit.uses,kit.healPercent)
        kit.noteEn=string.format("%d uses. Each restores %d%% of maximum HP.",kit.uses,kit.healPercent)
    else
        kit.noteZh=string.format("可用 %d 次，每次最多恢复 %d 点生命。",kit.uses,kit.healHP)
        kit.noteEn=string.format("%d uses. Each restores up to %d HP.",kit.uses,kit.healHP)
    end
end

function M.validUses(kind,n)
    local kit=M.types[kind]
    return kit~=nil and type(n)=="number" and n==math.floor(n) and n>=1 and n<=kit.uses
end

function M.remaining(item)
    if item.kind=="medkit" and item.remaining==nil then return M.types.medkit.uses end
    return item.remaining
end

function M.item(kind)
    return {kind=kind,remaining=M.types[kind].uses,name="$nh_hideout_"..kind,
        icon="mods/noita_hideout/files/items/"..kind..".png"}
end

function M.upgradeRecipe(kind,ingredient,herbs,essence,seconds)
    local kit=M.types[kind]
    return {id=kind,category="medical",facility="medical",zh=kit.zh,en=kit.en,durationFrames=seconds*60,
        inputs={},storedIngredient=ingredient,resources={herb=herbs,essence_healing=essence},item=M.item(kind),
        noteZh=kit.noteZh,noteEn=kit.noteEn}
end

return M
