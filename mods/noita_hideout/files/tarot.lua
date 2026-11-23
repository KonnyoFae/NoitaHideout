local T={durability=40,duration=30*60*60,order={"tarot_garden","tarot_hermit","tarot_chariot","tarot_tower"},types={}}
local rows={
    {"tarot_garden","花园","Garden","respawn","额外生命 +1；最大生命值增加 50%，永久保留。","One extra life; maximum HP increases by 50%, permanently."},
    {"tarot_hermit","隐者","Hermit","invisibility","隐身与驱散斗篷，持续 30 分钟。","Invisibility and Repelling Cape for 30 minutes."},
    {"tarot_chariot","战车","Chariot","shield","永久护盾、复仇子弹与伤害力场，持续 30 分钟。","Permanent Shield, Revenge Bullets and Contact Damage for 30 minutes."},
    {"tarot_tower","高塔","Tower","mega_beam_stone","在身旁生成一块萨德祈唯（光石），永久保留。","Creates a permanent Sadekivi (beamstone) nearby."},
}
for _,r in ipairs(rows) do
    T.types[r[1]]={zh=r[2],en=r[3],perkIcon=r[4],
        noteZh=r[5].."每次消耗 1 耐久，并补满已装备护盾、弹挂与随身枪械弹匣。限时效果再次使用刷新时长。",
        noteEn=r[6].." Uses one charge. Refills equipped shield, ammo rig and carried gun magazines. Timed effects refresh on reuse."}
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
