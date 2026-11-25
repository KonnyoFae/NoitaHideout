local root="mods/noita_hideout/files/"
local G={
    derringer={zh="巡飞弹发射器",en="Patrol drone launcher",capacity=4,speed=1,patrolRange=160,powder=10,gold=10,seconds=8,
        projectile=root.."projectiles/patrol_drone.xml",
        noteZh="左键向准星位置派出一架无人机，自主盘旋警戒，发现敌人后冲向目标自爆。预装4发。",
        noteEn="Click to send a drone to the reticle. It circles the area and dives into a nearby enemy to detonate. Four launches."},
    flare_gun={zh="智能费洛蒙手枪",en="Smart pheromone pistol",capacity=20,speed=300,powder=20,resources={spice=10},gold=200,seconds=5,
        projectile=root.."projectiles/smart_pheromone.xml",
        noteZh="20 发智能费洛蒙弹。附着 15 秒，脱落后再魅惑 60 秒。受伤时魅惑仍然有效。",
        noteEn="Twenty homing pheromone darts. Each sticks for 15 seconds, then charms for another 60 seconds. The charm persists through damage."},
    sedative_launcher={zh="智能麻醉枪",en="Smart tranquilizer gun",capacity=20,speed=300,powder=20,resources={herb=10},gold=50,seconds=5,
        projectile=root.."projectiles/sedative_dart.xml",
        noteZh="20 发无伤追踪麻醉弹。附着期间持续麻醉 15 秒，脱落后最多再睡 300 秒，此时受伤会醒。",
        noteEn="Twenty harmless homing darts. Each sedates for 15 seconds while attached, then for up to 300 more seconds. Damage wakes the target after the dart falls off."},
}
local function tube(zh,en,effectZh,effectEn)
    return {zh=zh,en=en,isTube=true,capacity=6,speed=280,seconds=10,
        noteZh="预装6发。手持时每次左键发射一发，"..effectZh.."。",noteEn="Six charges. Left-click while held. "..effectEn}
end
G.magic_tube=tube("封堵发射器","Cement launcher","命中时爆散出水泥和水，混合后迅速凝固并封堵缺口","Bursts into cement mixed with water. The mixture quickly sets into a solid plug.")
G.fire_tube=tube("等离子切割发射器","Plasma cutter launcher","命中时沿弹道向前切出约10格宽、50格长的通道","On impact, a forward plasma beam cuts a passage about 10 pixels wide and 50 long.")
G.frost_tube=tube("急冻发射器","Cryo launcher","命中时短暂展开大范围冰冻之环，冻结敌人和可冻结的材料","On impact, a brief Circle of Stillness freezes nearby enemies and materials.")
G.shock_tube=tube("干扰发射器","Disruption launcher","命中时形成持续放电的大片云雾，靠近云雾也有触电危险","On contact, a bank of charged mist repeatedly shocks exposed creatures and conductors. Keep clear.")
local function supportGun(zh,en,capacity,speed,interval,charge,file,flash,noteZh,noteEn)
    return {zh=zh,en=en,capacity=capacity,speed=speed,interval=interval,charge=charge,projectile=file,
        muzzle=root.."muzzle_flashes/"..flash..".xml",noteZh=noteZh.."。用尽后消耗。",noteEn=noteEn.." Disposable."}
end
G.heavy_mg=supportGun("重机枪","Heavy machine gun",320,1080,5,nil,root.."projectiles/support_mg.xml","mg",
    "按住左键发射高速曳光弹，预装320发","Hold for sustained tracer fire. 320 rounds.")
G.heavy_mg.heldSprite=root.."items/heavy_mg_sprite.xml"
G.auto_grenade=supportGun("连发榴弹发射器","Automatic grenade launcher",36,660,15,nil,root.."projectiles/support_grenade.xml","grenade",
    "按住左键连射低弧线碰炸榴弹，预装36发","Hold to fire low-arc impact grenades. 36 rounds.")
G.missile_launcher=supportGun("导弹发射器","Missile launcher",12,290,nil,nil,root.."projectiles/support_missile.xml","missile",
    "追踪弹命中后沿来向继续等离子切割，预装12发","Homing missiles cut forward with plasma on impact. 12 rounds.")
G.railgun=supportGun("轨道炮","Railgun",20,1800,nil,36,root.."projectiles/support_rail.xml","rail",
    "按住左键蓄力，发射可贯穿敌人和薄层地形的重弹，预装20发","Hold to charge a shot that punches through enemies and thin terrain. 20 rounds.")
G.heavy_plasma=supportGun("重等离子炮","Heavy plasma cannon",24,430,14,nil,root.."projectiles/support_plasma.xml","plasma",
    "按住左键连射等离子弹，命中点向八个方向射出短等离子切割束，预装24发","Hold to fire plasma bolts. Each impact sends eight short plasma cutters outwards. 24 rounds.")
G.bfg=supportGun("BFG","BFG",4,145,nil,nil,root.."projectiles/support_bfg.xml","bfg",
    "光球吞噬地形，吸附敌人并持续电击，向周围释放五属性绿电。冲击波扩张后收回球心，引发核爆。预装4发","The terrain-eating orb latches on and electrocutes its target. Green arcs and both shockwave passes deal five damage types. The returning wave triggers a nuclear blast. Four shots.")
-- The native quick slot has its own 16px icon. Draw the original texels
-- directly in the world and in custom inventory slots.
for _,kind in ipairs({"heavy_mg","auto_grenade","missile_launcher","heavy_plasma"}) do
    G[kind].displaySprite=root.."items/"..kind.."_art.png"
end
for _,kind in ipairs({"flare_gun","sedative_launcher"}) do
    G[kind].displaySprite=root.."items/"..kind.."_art.png"
    G[kind].heldSprite=root.."items/"..kind.."_sprite.xml"
    G[kind].groundPivot=16
    G[kind].fireFrames=6
end
for kind,gun in pairs(G) do gun.projectile=gun.projectile or root.."projectiles/"..kind..".xml" end
local M={types=G}
-- The original one-shot signal guns were exchanged for four rounds each.
-- Later ammo capacity changes preserve that exchange and the physical charge count.
function M.convertFlares(count)
    if not NHStore.validBandageCount(count) then return end
    -- An engine item has one signed 32-bit charge counter, even for very large legacy stacks.
    return count<=math.floor(2147483647/4) and count*4 or count
end
function M.physicalRounds(kind,entity,item)
    local n=item and ComponentGetValue2(item,"uses_remaining")
    if kind=="flare_gun" and n and not EntityHasTag(entity,"nh_pheromone_launcher") then
        n=M.convertFlares(n)
        if n then
            ComponentSetValue2(item,"uses_remaining",n)
            EntityAddTag(entity,"nh_pheromone_launcher")
        end
    end
    return n
end

local rewind
function M.consumeRound(player,entity,item,rounds)
    if rounds==1 then
        GameKillInventoryItem(player,entity)
        return
    end
    if EntityHasTag(entity,"nh_rewind_equipment") then
        rewind=rewind or dofile(root.."rewind_loadout.lua")
        rewind.spentRound(player,entity)
    end
    ComponentSetValue2(item,"uses_remaining",rounds-1)
end
-- A hold belongs to the item that received the initial press. UI capture or
-- switching items cancels the charge and cannot start an automatic burst.
local triggerItem,nextShot
local firingOwner,firingItem,fireEnds
local function setAnimation(item,sprite,name)
    if ComponentGetValue2(sprite,"rect_animation")==name then return end
    ComponentSetValue2(sprite,"rect_animation",name)
    ComponentSetValue2(sprite,"next_rect_animation",name)
    EntityRefreshSprite(item,sprite)
end
local function finishBurst()
    if EntityGetIsAlive(firingItem) then
        local sprite=EntityGetFirstComponentIncludingDisabled(firingItem,"SpriteComponent","enabled_in_hand")
        if sprite then setAnimation(firingItem,sprite,"default") end
    end
    firingOwner,firingItem,fireEnds=nil,nil,nil
end
function M.animateShot(player,item,sprite,frames)
    if firingItem and firingItem~=item then finishBurst() end
    setAnimation(item,sprite,"fire")
    -- Each confirmed round renews the animation. The heavy MG loops three frames at 10 fps.
    firingOwner,firingItem,fireEnds=player,item,GameGetFrameNum()+(frames or 18)
end
-- Brief sparks converge around the held weapon. No effect entity survives a cancelled charge.
local function chargeSparks(item,remaining)
    if remaining%4~=0 then return end
    local x,y=EntityGetTransform(item)
    local radius=2+remaining*0.22
    local angle=remaining*0.3
    for i=1,3 do
        local dx,dy=math.cos(angle)*radius,math.sin(angle)*radius
        GameCreateCosmeticParticle("spark_blue",x+dx,y+dy,1,-dx*10,-dy*10,0,0.09,0.12,true,true,false,false,0,0)
        angle=angle+2*math.pi/3
    end
end
function M.trigger(item,edge,frame)
    if firingItem and (frame>=fireEnds or not EntityGetIsAlive(firingOwner)
        or (item or NHNative.held(firingOwner))~=firingItem) then finishBurst() end
    if edge then triggerItem,nextShot=item,frame
    elseif not item or item~=triggerItem then triggerItem=nil end
    if not item or item~=triggerItem then return end
    if EntityHasTag(item,"nh_support_weapon") then
        for kind,gun in pairs(G) do
            if EntityHasTag(item,"noita_hideout_"..kind) then
                if edge and gun.charge then nextShot=frame+gun.charge end
                if frame<nextShot then
                    if gun.charge then chargeSparks(item,nextShot-frame) end
                    return
                end
                if gun.interval then nextShot=frame+gun.interval else triggerItem=nil end
                return item
            end
        end
    end
    if edge then return item end
end
function M.canCombine(gun,a,b)
    local fullA,fullB=a==gun.capacity,b==gun.capacity
    return (fullA and fullB) or (gun.isTube and (fullA or fullB))
end
function M.recipe(kind,id,inputs,resources,count,zh,en)
    local g=G[kind]
    return {id=id or kind,zh=zh or g.zh,en=en or g.en,category="weapons",facility="grenade",durationFrames=g.seconds*60,
        count=count or 1,goldCost=g.gold,inputs=inputs or {{name="gunpowder",amount=g.powder}},resources=resources or g.resources,
        item={kind=kind,name="$nh_hideout_"..kind,icon=root.."items/"..kind..".png",remaining=g.capacity,count=count or 1},
        noteZh=g.noteZh,noteEn=g.noteEn}
end
-- One open gun at the front of the stack. All later guns are fully loaded.
function M.rounds(item)
    local capacity=G[item.kind].capacity
    local remaining,count=item.remaining,item.count or 1
    if not NHStore.validBandageCount(count) or not NHStore.validBandageCount(remaining) or remaining>capacity then return end
    local rounds=(count-1)*capacity+remaining
    if rounds<=2147483647 then return rounds end
end
function M.unpack(item,rounds)
    local capacity=G[item.kind].capacity
    if rounds==0 then
        -- A watch may keep the physical item for the rest of its window.
        -- The inventory tooltip should show this single empty shell.
        item.count,item.remaining=1,0
        return
    end
    item.count=math.ceil(rounds/capacity)
    item.remaining=(rounds-1)%capacity+1
end
return M
