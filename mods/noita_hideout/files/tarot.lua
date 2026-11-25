local T={durability=40,duration=30*60*60,order={},timedOrder={},types={}}
local rows={
    {"tarot_garden","花园","Garden","respawn","额外生命 +1；最大生命值增加 50%，永久保留。","One extra life; maximum HP increases by 50%, permanently.",permanent=true},
    {"tarot_hermit","隐者","Hermit","invisibility","隐身与驱散斗篷，持续 30 分钟。","Invisibility and Repelling Cape for 30 minutes."},
    {"tarot_chariot","战车","Chariot","shield","永久护盾、复仇子弹与伤害力场，持续 30 分钟。","Permanent Shield, Revenge Bullets and Contact Damage for 30 minutes."},
    {"tarot_tower","高塔","Tower","mega_beam_stone","在身旁生成一块萨德祈唯（光石），永久保留。","Creates a permanent Sadekivi (beamstone) nearby.",permanent=true},
    {"tarot_sun","太阳","Sun","protection_fire","立即回复最大生命的 50%。接下来 30 分钟内每秒回复最大生命的 2%，并获得火焰免疫、一线生机、全知视野和视野保护（抵御致盲、黑幕与迷幻扭曲）。","Restore 50% of maximum HP immediately. For 30 minutes, regenerate 2% of maximum HP per second and gain Fire Immunity, Saving Grace, All-Seeing Eye and protection against blindness, dark veils and hallucinatory distortion."},
    {"tarot_moon","月亮","Moon","low_gravity","获得凝聚法力、冰冻免疫、低重力、浮空增强和视野保护（抵御致盲、黑幕与迷幻扭曲），持续 30 分钟。","Gain Mana Regeneration, Freezing Immunity, Low Gravity, Levitation Boost and protection against blindness, dark veils and hallucinatory distortion for 30 minutes."},
    {"tarot_magician","魔术师","Magician","edit_wands_everywhere","在身边放置七种战术发射器和三种诱饵，每种一组。获得 30 分钟的法杖随时编辑。","Place one set of each of the seven tactical launchers and three decoys around you. Tinker with wands everywhere for 30 minutes."},
    {"tarot_devil","魔鬼","Devil","critical_hit","30 分钟内，每秒扣除最大生命的 1%，降至半血即停。获得五层暴击率增加、五层坚持练腿，亲自击杀敌人回复最大生命的 5%。","For 30 minutes, lose 1% of maximum HP per second while above half health. Gain five stacks each of Critical Hit + and Never Skip Leg Day. Your kills restore 5% of maximum HP."},
}
for _,r in ipairs(rows) do
    T.order[#T.order+1]=r[1]
    if not r.permanent then T.timedOrder[#T.timedOrder+1]=r[1] end
    T.types[r[1]]={zh=r[2],en=r[3],perkIcon=r[4],
        noteZh=r[5].."每次消耗 1 耐久，并补满已装备护盾、弹挂与随身枪械弹匣。限时效果再次使用刷新时长。",
        noteEn=r[6].." Uses one charge. Refills equipped shield, ammo rig and carried gun magazines. Timed effects refresh on reuse."}
end
function T.dropFile(roll)
    return "mods/noita_hideout/files/items/card_"..T.order[roll(#T.order)]..".xml"
end
function T.refillDraft(s)
    if s.gearShield then
        local item=s.gearShield.item
        item.charge,item.repair,item.delay=NHShields.types[item.kind].cells*NHShields.cell,0,0
        s.gearShield.epoch=s.revision+1
    end
    if s.gearRig then
        local item=s.gearRig.item
        item.reserve=NHFirearms.rigs[item.kind].capacity
    end
    return true
end
function T.refillGuns(player)
    for _,id in ipairs(GameGetAllInventoryItems(player) or {}) do
        local mag=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_magazine")
        local def=mag and NHFirearms.items[ComponentGetValue2(mag,"name")]
        if def and def.magazine then
            NHFirearms.prepareMagazine(id,mag)
            ComponentSetValue2(mag,"value_int",def.magazine)
            local ability=EntityGetFirstComponentIncludingDisabled(id,"AbilityComponent")
            if ability then ComponentSetValue2(ability,"mana",def.magazine) end
        end
    end
end
return T
