local A={order={},byId={},byAction={}}
local function add(id,slot,zh,en,sprite,zhEffect,enEffect)
    local d={id=id,slot=slot,zh=zh,en=en,icon="data/ui_gfx/gun_actions/"..sprite..".png",
        action="NH_AMMO_"..id:upper(),name="$nh_ammo_"..id,zhEffect=zhEffect,enEffect=enEffect}
    A.byId[id],A.byAction[d.action]=d,d
    table.insert(A.order,d)
end
add("blast",1,"高爆弹芯","Blast core","explosive_projectile","各弹丸在命中处爆炸。","Each pellet explodes on impact.")
add("fire",1,"燃烧弹芯","Incendiary core","fireball","点燃命中目标，并在落点溅出火星。","Ignites the target and scatters fire at the impact point.")
add("frost",1,"冰冻弹芯","Frost core","freeze","冻结命中目标及落点附近的水。","Freezes the target and nearby water.")
add("shock",1,"电击弹芯","Shock core","electric_charge","电击命中目标，并在落点短暂放电。","Shocks the target and discharges at the impact point.")
add("toxin",1,"毒素弹芯","Toxic core","poison_blast","使目标中毒，并在落点溅出少量毒液。","Poisons the target and splashes poison at the impact point.")
add("plasma",1,"等离子切割弹芯","Plasma cutter core","laser_emitter_cutter","命中后沿弹道产生短促的切割束。","Projects a short cutting beam on impact.")
add("speed",2,"高速弹道","High velocity","speed","弹速提高 50%。","Increases projectile speed by 50%.")
add("pierce",2,"高穿透弹道","Entity piercing","piercing_shot","可穿过多个目标，遇地形停止。","Pierces multiple targets and stops at terrain.")
add("cursor",2,"光标制导","Cursor guidance","homing_cursor","弹丸随瞄准方向转弯。","Steers the projectile with your aim.")
add("homing",2,"自动索敌","Homing guidance","homing","弹丸自动转向附近的敌人。","Steers the projectile toward nearby enemies.")

function A.card(d)
    return {kind="spell",name=d.name,icon=d.icon,card={id=d.action,x=0,y=0,item={uses_remaining=-1},useDefaultPickups=true}}
end
function A.description(d)
    local slot=d.slot==1 and "命中配件" or "弹道配件"
    return ("%s。%s基础伤害 -1，弹耗不变。"):format(slot,d.zhEffect),
        ("%s attachment. %s Base damage -1; ammo cost unchanged."):format(d.slot==1 and "Impact" or "Trajectory",d.enEffect)
end
-- Empty string denotes normal ammunition. A special load always has at least one attachment.
function A.profile(impact,flight)
    if not impact and not flight then return "" end
    return (impact or "").."/"..(flight or "")
end
function A.parse(profile)
    if not profile or profile=="" then return nil,nil end
    local a,b=profile:match("^(%w*)/(%w*)$")
    return A.byId[a],A.byId[b]
end
function A.valid(profile)
    if not profile or profile=="" then return true end
    if type(profile)~="string" then return false end
    local a,b=A.parse(profile)
    return (not a or a.slot==1) and (not b or b.slot==2) and A.profile(a and a.id,b and b.id)==profile
end
return A
