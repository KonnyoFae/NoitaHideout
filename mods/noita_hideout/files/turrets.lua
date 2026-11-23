local root="mods/noita_hideout/files/"
local T={order={"turret_pack","rocket_turret_pack","shield_turret_pack"},types={}}
-- Keep the released item and recipe IDs so existing stacks and orders become decoys.
local defs={
    {"turret_pack","诱饵气球","Decoy balloon",nil,"固定在部署位置，吸引附近敌人的火力。","Stays at the deployment point and draws nearby enemies' fire."},
    {"rocket_turret_pack","智能诱饵","Smart decoy","essence_high_energy","在部署点附近巡飞，主动吸引敌人并近身踢击。","Patrols near the deployment point, draws fire and kicks enemies at close range."},
    {"shield_turret_pack","护盾诱饵","Shielded decoy","essence_force","与智能诱饵一样巡飞、嘲讽和踢击，随身护盾可拦截来弹。","Patrols, taunts and kicks like the smart decoy. A shield intercepts incoming projectiles."},
}
for _,row in ipairs(defs) do
    local kind,zh,en,essence,noteZh,noteEn=unpack(row,1,6)
    T.types[kind]={zh=zh,en=en,essence=essence,icon=root.."items/"..kind..".png",
        noteZh=noteZh.." 手持左键在附近地面部署一个。",noteEn=noteEn.." Left-click to deploy one on nearby ground."}
end
function T.validCount(n) return type(n)=="number" and n>=1 and n<=4 and n==math.floor(n) end
function T.recipe(kind)
    local d=T.types[kind]
    local resources={arcane_scrap=1}
    if d.essence then resources[d.essence]=1 end
    return {id=kind,zh=d.zh,en=d.en,category="weapons",facility="grenade",
        durationFrames=600,inputs={},resources=resources,goldCost=200,count=4,
        item={kind=kind,name="$nh_hideout_"..kind,icon=d.icon,count=4},
        noteZh=d.noteZh,noteEn=d.noteEn}
end
return T
