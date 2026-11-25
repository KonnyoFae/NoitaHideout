-- Each released collectible has a stable id, its physical entity file, and
-- the complete warehouse item record accepted by that entity's storage codec.
-- Those two representations describe the same reward in combat and at home.
local path="mods/noita_hideout/files/items/"
local function collectible(id,zh,en,noteZh,noteEn,tarot,companion)
    return {id=id,file=path..id..".xml",zh=zh,en=en,
        noteZh="物品栏右键或手持按射击键启动。"..noteZh,
        noteEn="Right-click in inventory or fire while held. "..noteEn,tarot=tarot,companion=companion,
        item={kind=id,remaining=90,name="$nh_hideout_"..id,icon=path..id..".png"}}
end
local collectibles={
    collectible("salvage_bell","打捞钟","Salvage Bell",
        "将附近战利品袋召到身边。接下来 15 分钟提高击杀掉落。",
        "Draw nearby loot bags to you and improve kill drops for 15 minutes.","tarot_moon","cat"),
    collectible("rewind_watch","倒流表","Rewind Watch",
        "设置 60 秒锚点。首次受击会挡下伤害并获得 5 秒无敌，随后闪回并恢复原装备的弹药和护盾。未受击则自然结束。",
        "Set a 60-second anchor. The first hit is blocked and grants 5 seconds of invulnerability. Then blink back and rewind your original ammo and shield. The anchor expires if unused.","tarot_hermit","dryad"),
    collectible("stasis_hourglass","静滞沙漏","Stasis Hourglass",
        "在原地展开持续 30 秒的静滞领域。敌人、投射物及独立物理块停下，玩家可自由行动。水、沙和火仍照常流动。",
        "Suspend enemies, projectiles and loose physics bodies around this spot for 30 seconds. Players move freely. Water, sand and fire continue to flow.","tarot_tower","slime"),
    collectible("dustless_duster","无尘掸帚","Dustless Duster",
        "展开持续 60 秒的随身领域，将松散材料、敌人、投射物和地面物品向外推开。岩层和地板保持原状。",
        "Repel loose materials, enemies, projectiles and dropped items around you for 60 seconds. Solid terrain stays in place.","tarot_chariot","griffin"),
    collectible("mana_reactor","魔力堆芯","Mana Reactor",
        "开启 90 秒堆芯直通。手持法杖每秒额外恢复最大法力的 15%。多功能左轮与步枪无限供弹。藏身处护盾耗尽时鸣警，无盾再受伤将在原地引发超级核爆。",
        "Gain 90 seconds of direct power. Your held wand gains 15% of max mana per second. The multi-purpose revolver and rifle fire without spending ammo. At zero hideout shield, the siren warns that your next damaging hit will detonate a Giga Nuke.","tarot_sun","dragon"),
}
-- Weapon relics share the red drop and dismantling catalogue, but their own
-- katana codec and input controller own storage and skill activation.
local katanas=dofile("mods/noita_hideout/files/katanas.lua")
local dragon=katanas.types.dragon_king
collectibles[#collectibles+1]={id="dragon_king",file=dragon.file,zh=dragon.zh,en=dragon.en,
    noteZh=dragon.noteZh,noteEn=dragon.noteEn,katana=true,tarot="tarot_devil",companion="dragon",item=katanas.item("dragon_king")}
return collectibles
