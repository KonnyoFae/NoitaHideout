-- Each dish is a carried item. Shared effects use one timer on the player.
local foods={
    {id="bread",zh="面包",en="Bread",facility="farmland",resources={grain=2},
        effect="bread",seconds=120,
        noteZh="每 4 秒恢复 1 点生命，持续 120 秒。",noteEn="Restores 1 HP every 4 seconds for 120 seconds."},
    {id="sugar_cube",zh="糖块",en="Sugar cube",facility="farmland",resources={sugar=2},
        effect="sugar_cube",seconds=120,
        noteZh="提高行动速度，持续 120 秒。",noteEn="Increases movement speed for 120 seconds."},
    {id="herb_flatbread",zh="香料草药饼",en="Spiced herb flatbread",facility="agri_equipment",resources={spice=1,herb=1,grain=3},
        effect="bread",seconds=180,
        noteZh="每 4 秒恢复 1 点生命，持续 180 秒。",noteEn="Restores 1 HP every 4 seconds for 180 seconds."},
    {id="spice_cake",zh="香甜米糕",en="Sweet spice cake",facility="agri_equipment",resources={spice=1,sugar=2,grain=2},
        effect="food_levitation",seconds=120,
        noteZh="上升速度提高 75%，持续 120 秒。",noteEn="Increases levitation speed by 75% for 120 seconds."},
    {id="milk_omelet",zh="奶香蛋饼",en="Spiced milk omelet",facility="agri_equipment",resources={spice=1,grain=2,egg=2,milk=1},
        effect="food_mana",seconds=120,
        noteZh="加快法力恢复，持续 120 秒。",noteEn="Increases mana regeneration for 120 seconds."},
    {id="spiced_stew",zh="香料炖肉",en="Spiced meat stew",facility="agri_equipment",resources={spice=2,herb=1,milk=1,meat=2},
        effect="bread",seconds=180,healHP=20,
        noteZh="立即恢复最多 20 点生命，随后每 4 秒恢复 1 点，持续 180 秒。",
        noteEn="Restores up to 20 HP immediately and 1 HP every 4 seconds for 180 seconds."},
}
return foods
