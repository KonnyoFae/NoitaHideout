-- Each reloadable weapon reserves its single native wand slot for its built-in action.
local F={order={"scatter_revolver","marksman_rifle","battle_staff","hunting_bow"},rigs={},packs={}}
F.items={
    hunting_bow={zh="猎杀弓",en="Hunting bow",magazine=60,loadFrames=60,scrap=12,fixed=true,
        icon="mods/noita_hideout/files/items/hunting_bow_icon.png",noteZh="按住拉弓，每半秒升一档，松开发射。B 切换火力、侦查、辅助和机动，R 换弹。",
        noteEn="Hold to draw, gaining a tier every half second. Release to shoot. B changes mode and R reloads."},
    battle_staff={zh="武装杖",en="Battle staff",magazine=120,loadFrames=72,scrap=12,fixed=true,
        icon="mods/noita_hideout/files/items/staff_icon.png",noteZh="按住蓄力，松手释放。每半秒升一档。B 切换施法、召唤、变形和恢复，R 装填。召唤与变形可点按免费杖击。",noteEn="Hold to charge one tier per half second and release to cast. B switches spells, summons, transformation and recovery. Tap in summon or transformation mode to strike for free."},
    scatter_revolver={zh="多功能左轮",en="Multimode revolver",magazine=36,loadFrames=54,scrap=6,
        icon="mods/noita_hideout/files/items/scatter_revolver.png",noteZh="36 点共用弹匣：速射、马格南、霰弹、喷枪。R 整匣装填。",noteEn="36-point magazine: auto, magnum, scatter or spray. R reloads."},
    marksman_rifle={zh="多功能步枪",en="Multimode rifle",magazine=60,loadFrames=72,scrap=10,
        icon="mods/noita_hideout/files/items/marksman_rifle.png",noteZh="60 点共用弹匣：自动、狙击、微型导弹、光束。R 整匣装填。",noteEn="60-point magazine: auto, sniper, micro missile or beam. R reloads."},
}

F.mods=dofile("mods/noita_hideout/files/ammo_mods.lua")
F.modes=dofile("mods/noita_hideout/files/firearm_modes.lua")
F.staffModes={
    {id="cast",zh="施法",en="Spellcasting",costs={1,3,6,10},
        spells={{"魔法飞弹","Magic missile"},{"法力冲击","Mana pulse"},{"店长光球","Guardian orb"},{"小轨道炮","Mini railgun"}}},
    {id="summon",zh="召唤",en="Summoning",costs={0,2,4,8},
        spells={{"杖击","Strike"},{"岩石精灵","Rock spirit"},{"追踪鸭群","Homing ducks"},{"追踪陨石","Homing meteors"}}},
    {id="transform",zh="变形",en="Transformation",costs={0,5,10},
        spells={{"杖击","Strike"},{"变羊弹","Sheep bolt"},{"自身拟态","Mimic"}}},
    {id="restore",zh="恢复",en="Recovery",costs={2,8,16,32},
        spells={{"治疗魔弹","Healing bolt"},{"护盾治疗领域","Healing ward"},{"一级补给包","Supply box I"},{"生命魔晶","Life crystal"}}},
}
F.bowModes=dofile("mods/noita_hideout/files/bow/modes.lua")
for _,modes in ipairs({F.staffModes,F.bowModes}) do
    for _,mode in ipairs(modes) do
        mode.cost=mode.costs[1]
        mode.minCost=math.min(unpack(mode.costs))
    end
end
function F.modeList(kind)
    if kind=="hunting_bow" then return F.bowModes end
    return kind=="battle_staff" and F.staffModes or F.modes.guns[kind]
end
local function ammoTier(rigId,packId,zh,en,capacity,refill,rigScrap,packScrap,gold)
    local art="mods/noita_hideout/files/items/"
    local rig={zh=zh.."弹挂",en=en.." ammo rig",icon=art..rigId..".png",capacity=capacity,scrap=rigScrap,
        noteZh=("携带 %d 点备弹。装备后每拾取累计 10 金补 10 点。"):format(capacity),
        noteEn=("Stores %d ammo points. Every 10 in nugget value adds 10 points."):format(capacity)}
    local pack={zh=zh.."弹药盒",en=en.." ammo box",icon=art..packId..".png",refill=refill,scrap=packScrap,gold=gold,uses=8,castFrames=120,
        noteZh=("右击使用 2 秒，向已装备的弹挂补入最多 %d 点备弹。每盒 8 次。"):format(refill),
        noteEn=("Use for 2 seconds to supply up to %d points to the equipped rig. Eight uses."):format(refill)}
    F.rigs[rigId],F.packs[packId]=rig,pack
    F.items[rigId],F.items[packId]=rig,pack
    table.insert(F.order,rigId)
    table.insert(F.order,packId)
end
ammoTier("ammo_rig","ammo_pack","基础","Basic",240,120,3,1,10)
ammoTier("improved_ammo_rig","improved_ammo_pack","进阶","Improved",480,240,6,2,20)
ammoTier("advanced_ammo_rig","advanced_ammo_pack","高级","Advanced",720,360,9,3,30)

-- Carried entities from earlier saves can retain the original placeholder paths.
F.legacyIcons={ammo_rig="data/items_gfx/material_backbag.png",ammo_pack="data/items_gfx/pouch.png"}

function F.recipe(kind)
    local d=F.items[kind]
    local item={kind=kind,icon=d.icon,name="$nh_hideout_"..kind}
    if d.magazine then item.rounds,item.mode=d.magazine,1
    elseif d.capacity then item.reserve,item.pointsVersion=0,1
    else item.remaining,item.count=d.uses,4 end
    return {id=kind,zh=d.zh,en=d.en,category=d.magazine and "weapons" or "equipment",
        inputs={},resources={arcane_scrap=d.scrap},goldCost=d.gold,
        durationFrames=60*(d.uses and 4 or d.scrap),item=item,count=item.count,noteZh=d.noteZh,noteEn=d.noteEn}
end
function F.migratePoints(node)
    if type(node)~="table" then return end
    if F.rigs[node.kind] and node.pointsVersion==nil and type(node.reserve)=="number" then
        node.reserve,node.pointsVersion=node.reserve*10,1
    else
        for _,v in pairs(node) do if type(v)=="table" then F.migratePoints(v) end end
    end
end

function F.reserve(c)
    local n=ComponentGetValue2(c,"value_int")
    if ComponentGetValue2(c,"name")=="reserve_rounds" then
        n=n*10
        ComponentSetValue2(c,"value_int",n)
        ComponentSetValue2(c,"name","reserve_points")
    end
    return n
end

function F.migrateMagazines(node)
    if type(node)~="table" then return end
    if F.modes.guns[node.kind] and node.mode==nil and type(node.rounds)=="number" then
        node.rounds,node.mode,node.loaded=node.rounds*6,1,nil
    else
        for _,child in pairs(node) do if type(child)=="table" then F.migrateMagazines(child) end end
    end
end

function F.prepareMagazine(entity,mag)
    local mode=ComponentGetValue2(mag,"value_float") or 0
    if mode>=1 then return mode end
    local def=F.items[ComponentGetValue2(mag,"name")]
    local points=math.min(def.magazine,ComponentGetValue2(mag,"value_int")*6)
    ComponentSetValue2(mag,"value_float",1)
    ComponentSetValue2(mag,"value_int",points)
    local ability=EntityGetFirstComponentIncludingDisabled(entity,"AbilityComponent")
    if ability then
        ComponentSetValue2(ability,"mana_max",def.magazine)
        ComponentSetValue2(ability,"mana",points)
    end
    return 1
end

function F.profileComponent(entity)
    return EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent","nh_gun_profile") or
        EntityAddComponent2(entity,"VariableStorageComponent",{_tags="nh_gun_profile",name="",value_string=""})
end

function F.stored(s,ref)
    if not ref or (ref.container~="safe" and ref.container~="warehouse") then return end
    local i=NHStore.slotIndex(s,ref.container,ref.slot,"wand")
    local row=i and s[ref.container][i]
    if row and row.id==ref.id and F.modes.guns[row.item.kind] then return row.item end
end

function F.socket(s,ref,request)
    local gun=F.stored(s,ref)
    local container=request.container
    if not gun or request.gunId~=ref.id or (container~="warehouse" and container~="safe") then return false,"Inventory slot changed." end
    local a,b=F.mods.parse(gun.configured)
    local cells={a,b}
    local cell=request.targetCell or request.sourceCell
    if cell~=1 and cell~=2 then return false,"Inventory slot changed." end
    if request.targetCell then
        local i=NHStore.slotIndex(s,container,request.from,"spell")
        local row=i and s[container][i]
        local d=row and row.item.card and F.mods.byAction[row.item.card.id]
        if not d or row.id~=request.entity or d.slot~=cell or cells[cell] then return false,"Inventory slot changed." end
        local count=row.item.card.stack or 1
        if count==1 then table.remove(s[container],i) else row.item.card.stack=count-1 end
        cells[cell]=d
    else
        local d=cells[cell]
        if not d or d.id~=request.entity or not request.safeSlot or not NHStore.freeSlot(s,container,request.safeSlot,"spell") then return false,"Inventory slot changed." end
        table.insert(s[container],{id=s.nextItemId,slot=request.safeSlot,item=F.mods.card(d)})
        s.nextItemId=s.nextItemId+1
        cells[cell]=nil
    end
    gun.configured=F.mods.profile(cells[1] and cells[1].id,cells[2] and cells[2].id)
    return true
end

function F.valid(item)
    local d=F.items[item.kind]
    if not d then return false end
    if d.magazine and (not F.mods.valid(item.configured) or not F.modeList(item.kind)[item.mode or 1]) then return false end
    if d.uses then return NHMedkits.charges(item)~=nil end
    if d.capacity and (item.goldSeen~=nil or item.goldKey~=nil) then
        if type(item.goldKey)~="string" or type(item.goldSeen)~="number"
            or item.goldSeen<0 or item.goldSeen~=math.floor(item.goldSeen) then return false end
    end
    local n=item[d.magazine and "rounds" or "reserve"]
    return type(n)=="number" and n==math.floor(n) and n>=0 and n<=(d.magazine or d.capacity)
        and (item.count==nil or item.count==1)
end
function F.lane(kind)
    if kind=="spell" then return "spell" end
    if kind=="wand" or (F.items[kind] and F.items[kind].magazine) then return "wand" end
    return "tool"
end
function F.nativeLane(kind,entity)
    if kind=="battle_staff" then
        local ability=EntityGetFirstComponentIncludingDisabled(entity,"AbilityComponent")
        if ability and not ComponentGetValue2(ability,"use_gun_script") then return "tool" end
    end
    return F.lane(kind)
end

local mounts={
    battle_staff={art="mods/noita_hideout/files/items/staff_angles.xml",x=0,y=0,tipX=8,tipY=0},
    scatter_revolver={art=F.items.scatter_revolver.icon,x=4,y=8,tipX=6,tipY=-2},
    marksman_rifle={art="mods/noita_hideout/files/items/rifle.png",x=11,y=10,tipX=17,tipY=-3},
}
function F.repairGunSprite(entity,kind)
    local mount=mounts[kind]
    if not mount or EntityGetFirstComponentIncludingDisabled(entity,"LuaComponent","nh_equipment_mirror") then return end
    local script="mods/noita_hideout/files/equipment_sprite_mirror.lua"
    local old=EntityGetFirstComponentIncludingDisabled(entity,"LuaComponent","nh_revolver_mirror")
    if old then
        ComponentSetValue2(old,"script_source_file",script)
        ComponentAddTag(old,"nh_equipment_mirror")
        return
    end
    local sprite=EntityGetFirstComponentIncludingDisabled(entity,"SpriteComponent","enabled_in_hand")
    if not sprite then return end
    local art=mount.art
    local current=ComponentGetValue2(sprite,"image_file")
    if kind~="battle_staff" and current~=art and current~=F.items[kind].icon and not (kind=="scatter_revolver" and current=="mods/noita_hideout/files/items/scatter_revolver_world.png") then return end
    local ability=EntityGetFirstComponentIncludingDisabled(entity,"AbilityComponent")
    if ability then ComponentSetValue2(ability,"sprite_file",art) end
    ComponentSetValue2(sprite,"image_file",art)
    if kind=="battle_staff" then
        -- An older save can contain the original staff hidden by a pose child.
        ComponentSetValue2(sprite,"visible",true)
        ComponentSetValue2(sprite,"rect_animation","default")
        ComponentSetValue2(sprite,"next_rect_animation","default")
    end
    ComponentSetValue2(sprite,"has_special_scale",true)
    ComponentSetValue2(sprite,"special_scale_x",0.5)
    ComponentSetValue2(sprite,"special_scale_y",0.5)
    ComponentSetValue2(sprite,"offset_x",mount.x)
    ComponentSetValue2(sprite,"offset_y",mount.y)
    local muzzle=EntityGetFirstComponentIncludingDisabled(entity,"HotspotComponent","shoot_pos")
    if muzzle then ComponentSetValue2(muzzle,"offset",mount.tipX,mount.tipY) end
    EntityRefreshSprite(entity,sprite)
    EntityAddComponent2(entity,"LuaComponent",{_tags="enabled_in_hand,enabled_in_world,nh_equipment_mirror",
        script_source_file=script,execute_every_n_frame=1})
end

function F.repairStaff(entity,player)
    local ability=EntityGetFirstComponentIncludingDisabled(entity,"AbilityComponent")
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    if not ability or not item then return end
    if not EntityGetFirstComponentIncludingDisabled(entity,"LuaComponent","nh_equipment_mirror") then
        F.repairGunSprite(entity,"battle_staff")
        ComponentSetValue2(item,"ui_sprite",F.items.battle_staff.icon)
    end
    if ComponentGetValue2(ability,"use_gun_script") then return end
    local parent=EntityGetParent(entity)
    if parent and parent~=0 and (EntityGetName(parent)~="inventory_quick" or EntityGetParent(parent)~=player) then return end
    if ComponentGetValue2(item,"is_frozen") then ComponentSetValue2(item,"is_frozen",false) end
    if parent and parent~=0 then
        local occupied={}
        for _,other in ipairs(EntityGetAllChildren(parent) or {}) do
            if other~=entity and F.nativeLane(NHTransfers.item_kind(other),other)=="wand" then
                local otherItem=EntityGetFirstComponentIncludingDisabled(other,"ItemComponent")
                if otherItem then local col=ComponentGetValue2(otherItem,"inventory_slot"); occupied[col]=true end
            end
        end
        local col=ComponentGetValue2(item,"inventory_slot")
        if col<0 or col>3 or occupied[col] then
            col=0
            while occupied[col] do col=col+1 end
            if col>3 then return end
        end
        ComponentSetValue2(item,"inventory_slot",col,0)
    end
    if not EntityGetFirstComponentIncludingDisabled(entity,"HotspotComponent","shoot_pos") then
        local muzzle=EntityAddComponent2(entity,"HotspotComponent",{_tags="shoot_pos"})
        if muzzle then ComponentSetValue2(muzzle,"offset",8,0) end
    end
    ComponentSetValue2(ability,"use_gun_script",true)
    local inventory=parent and parent~=0 and EntityGetFirstComponentIncludingDisabled(player,"Inventory2Component")
    if inventory then ComponentSetValue2(inventory,"mForceRefresh",true) end
end

function F.ensureBuiltInAction(entity,kind)
    local actionId="NH_"..kind:upper()
    local card,item
    for _,child in ipairs(EntityGetAllChildren(entity) or {}) do
        local action=EntityGetFirstComponentIncludingDisabled(child,"ItemActionComponent")
        if action and ComponentGetValue2(action,"action_id")==actionId then
            card=child
            item=EntityGetFirstComponentIncludingDisabled(card,"ItemComponent")
            if not item then return false end
            if ComponentGetValue2(item,"permanently_attached") and ComponentGetValue2(item,"is_frozen") then return true end
            break
        end
    end
    if not card then
        local x,y=EntityGetTransform(entity)
        card=CreateItemActionEntity(actionId,x,y)
        if not card or card==0 then return false end
        item=EntityGetFirstComponentIncludingDisabled(card,"ItemComponent")
        if not item then EntityKill(card);return false end
        EntityAddChild(entity,card)
        EntitySetComponentsWithTagEnabled(card,"enabled_in_world",false)
        EntitySetComponentsWithTagEnabled(card,"enabled_in_hand",false)
    end
    -- The one slot already exists. Converting it to always cast consumes that slot.
    ComponentSetValue2(item,"inventory_slot",0,0)
    ComponentSetValue2(item,"permanently_attached",true)
    ComponentSetValue2(item,"is_frozen",true)
    local owner=EntityGetRootEntity(entity)
    local inventory=EntityGetFirstComponentIncludingDisabled(owner,"Inventory2Component")
    if inventory then ComponentSetValue2(inventory,"mForceRefresh",true) end
    return true
end

function F.registerItems()
    for _,id in ipairs(F.order) do
        if not F.packs[id] then
            local kind=id
            local d=F.items[kind]
            local tag=d.magazine and "nh_magazine" or "nh_reserve"
            NHProducts.icons[kind]=d.icon
            NHTransfers.registerItem(kind,function(entity) return EntityHasTag(entity,"noita_hideout_"..kind) end,{
                warehouseCategory=d.magazine and "wand" or "equipment",
                capture=function(entity)
                    local c=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",tag)
                    if not c then return nil,"Equipment unavailable." end
                    local item={kind=kind,name="$nh_hideout_"..kind,icon=d.icon}
                    item[d.magazine and "rounds" or "reserve"]=ComponentGetValue2(c,"value_int")
                    if d.capacity then item.reserve,item.pointsVersion=F.reserve(c),1
                    else
                        local profile=F.profileComponent(entity)
                        item.configured=ComponentGetValue2(profile,"name")
                        item.mode=F.prepareMagazine(entity,c)
                        item.rounds=ComponentGetValue2(c,"value_int")
                    end
                    if not F.valid(item) then return nil,"Invalid ammunition count." end
                    return item
                end,
                restore=function(item,x,y)
                    if not F.valid(item) then return nil,"Invalid ammunition count." end
                    local entity=EntityLoad("mods/noita_hideout/files/items/"..kind..".xml",x,y)
                    if not entity or entity==0 then return nil,"Equipment unavailable." end
                    local c=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent",tag)
                    if not c then EntityKill(entity); return nil,"Equipment unavailable." end
                    ComponentSetValue2(c,"value_int",item[d.magazine and "rounds" or "reserve"])
                    if d.capacity then ComponentSetValue2(c,"name","reserve_points") end
                    if d.magazine then
                        local profile=F.profileComponent(entity)
                        ComponentSetValue2(profile,"name",item.configured or "")
                        ComponentSetValue2(c,"value_float",item.mode or 1)
                        local ability=EntityGetFirstComponentIncludingDisabled(entity,"AbilityComponent")
                        if not ability or not F.ensureBuiltInAction(entity,kind) then
                            EntityKill(entity)
                            return nil,"Equipment unavailable."
                        end
                        ComponentSetValue2(ability,"mana",item.rounds)
                    end
                    return entity
                end,
            })
        end
    end
end
return F
