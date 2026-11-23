local M={
    order={"bandage","medkit","tactical_medkit","advanced_medkit"},
    types={
        bandage={zh="绷带",en="Bandage",uses=8,healPercent=5,castFrames=30},
        medkit={zh="小医疗包",en="Medkit",uses=8,healPercent=15,castFrames=60},
        tactical_medkit={zh="战术医疗包",en="Tactical medkit",uses=6,healPercent=25,castFrames=90},
        advanced_medkit={zh="高端医疗包",en="Advanced medkit",uses=6,healPercent=40,castFrames=120},
    },
}

for _,kit in pairs(M.types) do
    kit.noteZh=string.format("可用 %d 次，每次用时 %g 秒，恢复最大生命值的 %d%%。",kit.uses,kit.castFrames/60,kit.healPercent)
    kit.noteEn=string.format("%d uses. Restores %d%% of maximum HP after %g s.",kit.uses,kit.healPercent,kit.castFrames/60)
end

function M.capacity(kind)
    local kit=M.types[kind] or (NHSurgeryKits and NHSurgeryKits.types[kind]) or (NHShields and NHShields.supply(kind))
    return kit and kit.uses
end

function M.validUses(kind,n)
    local cap=M.capacity(kind)
    return cap and type(n)=="number" and n==math.floor(n) and n>=1 and n<=cap
end

function M.remaining(item)
    if item.remaining==nil and (item.kind=="bandage" or item.kind=="medkit") then return M.capacity(item.kind) end
    return item.remaining
end

function M.charges(item)
    local n=item.count
    if n==nil then n=1 end
    local left=M.remaining(item)
    if M.validUses(item.kind,left) and type(n)=="number" and n==math.floor(n) and n>=1 and n<=4 then
        return (n-1)*M.capacity(item.kind)+left
    end
end

function M.unpack(item,total)
    local cap=M.capacity(item.kind)
    if type(total)~="number" or total<1 or total>4*cap or total~=math.floor(total) then return false end
    item.count,item.remaining=math.ceil(total/cap),(total-1)%cap+1
    return true
end

function M.canCombine(kind,a,b)
    local cap=M.capacity(kind)
    return a and b and a+b<=4*cap and (a%cap==0 or b%cap==0)
end

function M.item(kind,count)
    return {kind=kind,remaining=M.capacity(kind),count=count,name="$nh_hideout_"..kind,
        icon="mods/noita_hideout/files/items/"..kind..".png"}
end

function M.upgradeRecipe(kind,ingredient,herbs,essence,seconds)
    local kit=M.types[kind]
    return {id=kind,category="medical",facility="medical",zh=kit.zh,en=kit.en,durationFrames=seconds*60,
        inputs={},storedIngredient=ingredient,resources={herb=herbs,essence_healing=essence},item=M.item(kind,4),count=4,
        noteZh=kit.noteZh,noteEn=kit.noteEn}
end

return M
