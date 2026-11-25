-- Physical workshop products use the same capture/restore journal as ordinary equipment.
NHProducts={icons={}}
local items="mods/noita_hideout/files/items/"
local supportGround=dofile("mods/noita_hideout/files/support_ground.lua")
NHProducts.repairNearbySupportWeapons=supportGround.near
local healing_items=NHMedkits.types
local function item_uses(entity,product)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    local uses=item and ComponentGetValue2(item,"uses_remaining")
    -- Old single grenades and bandages used the engine's unset charge count.
    if item and product.legacySingle and (uses==-1 or uses==nil) then uses=1 end
    return item,uses
end

local foods=NHFoods
local products={}
for kind in pairs(NHEquipment.links) do products[#products+1]=kind end
for _,kind in ipairs(NHFirearms.order) do
    if NHFirearms.packs[kind] then products[#products+1]=kind end
end
local shields=NHShields or dofile("mods/noita_hideout/files/shields.lua")
for _,kind in ipairs(shields.order) do products[#products+1]=kind end
for _,kind in ipairs(shields.chargerOrder) do products[#products+1]=kind end
for kind in pairs(NHGuns.types) do products[#products+1]=kind end
local deploymentCounts={}
for _,kind in ipairs(NHTurrets.order) do
    products[#products+1]=kind
    deploymentCounts[kind]={field="count",default=1,valid=NHTurrets.validCount,error="Invalid deployment stack."}
end
local bagCounts={}
for kind in pairs(NHLootBags.types) do
    products[#products+1]=kind
    bagCounts[kind]={field="count",default=1,valid=NHStore.validBandageCount,error="Invalid loot stack."}
end
local throwable_counts={}
for _,kind in ipairs(NHThrowables.order) do
    products[#products+1]=kind
    throwable_counts[kind]={field="count",default=kind=="grenade" and 1 or nil,legacySingle=kind=="grenade",
        valid=NHThrowables.validCount,error="Invalid throwable count."}
end
for kind in pairs(healing_items) do products[#products+1]=kind end
for _,kind in ipairs(NHSurgeryKits.order) do products[#products+1]=kind end
for _,food in ipairs(foods) do products[#products+1]=food.id end
for _,kind in ipairs(products) do
    local id=kind
    local shield=shields.types[id]
    local link=NHEquipment.links[id]
    local icon=(shield or shields.supply(id) or link or NHLootBags.types[id] or {}).icon or items..id..".png"
    NHProducts.icons[id]=icon
    local medical=NHMedkits.capacity(id)
    local product=deploymentCounts[id] or bagCounts[id] or throwable_counts[id]
    NHTransfers.registerItem(id,function(entity) return EntityHasTag(entity,"noita_hideout_"..id) end,{
        warehouseCategory=(link or shield or shields.supply(id)) and "equipment" or nil,
        capture=function(entity)
            local record={kind=id,name="$nh_hideout_"..id,icon=icon}
            if shield then
                local c=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent","nh_shield_item")
                record.charge=c and ComponentGetValue2(c,"value_int") or shield.cells*shields.cell
                record.repair=c and ComponentGetValue2(c,"value_float") or 0
                record.delay=c and tonumber(ComponentGetValue2(c,"value_string")) or 0
                if not shields.valid(record) then return nil,"Invalid shield equipment." end
            elseif medical then
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                local n=item and ComponentGetValue2(item,"uses_remaining")
                if id==shields.charger and NHStore.validBandageCount(n) and n>32 then
                    record.chargerOverflow,n=n-32,32
                end
                if not NHMedkits.unpack(record,id=="bandage" and n==-1 and 1 or n) then return nil,"Invalid medkit." end
            elseif NHGuns.types[id] then
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                local n=NHGuns.physicalRounds(id,entity,item)
                if not NHStore.validBandageCount(n) then return nil,"Invalid ammunition count." end
                NHGuns.unpack(record,n)
            elseif foods.byId[id] then
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                local bites=item and ComponentGetValue2(item,"uses_remaining")
                if bites==-1 then bites=foods.byId[id].uses end
                if not NHStore.validBandageCount(bites) then return nil,"Invalid food stack." end
                foods.setBites(record,bites)
            elseif link then
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                record.remaining=item and NHEquipment.linkUses(id,ComponentGetValue2(item,"uses_remaining"))
                if not record.remaining then return nil,"Invalid data link charge." end
            elseif product then
                local _,uses=item_uses(entity,product)
                if not product.valid(uses) then return nil,product.error end
                record[product.field]=uses
            end
            return record
        end,
        restore=function(record,x,y)
            local uses
            if medical then
                uses=NHMedkits.charges(record)
                if not uses then return nil,"Invalid medkit." end
            elseif NHGuns.types[id] then
                uses=NHGuns.rounds(record)
                if not uses then return nil,"Invalid ammunition count." end
            elseif foods.byId[id] then
                uses=foods.bites(record)
                if not uses then return nil,"Invalid food stack." end
            elseif link then
                uses=NHEquipment.linkUses(id,record.remaining)
                if not uses then return nil,"Invalid data link charge." end
            elseif product then
                uses=record[product.field]
                if uses==nil then uses=product.default end
                if not product.valid(uses) then return nil,product.error end
            end
            local entity=EntityLoad(items..id..".xml",x,y)
            if not entity or entity==0 then return nil,"Item could not be created." end
            if shield and (not shields.valid(record) or not EntityAddComponent2(entity,"VariableStorageComponent",{
                _tags="nh_shield_item",value_int=record.charge,value_float=record.repair or 0,value_string=tostring(record.delay or 0)})) then
                EntityKill(entity)
                return nil,"Invalid shield equipment."
            end
            if uses then
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                if not item then EntityKill(entity); return nil,"Missing item component." end
                ComponentSetValue2(item,"uses_remaining",uses)
            end
            return entity
        end,
    })
end

function NHProducts.linkKind(entity)
    for kind in pairs(NHEquipment.links) do
        if EntityHasTag(entity,"noita_hideout_"..kind) then return kind end
    end
end

function NHProducts.spendRemoteCharge(player,entity)
    if not entity or entity==0 or not EntityGetIsAlive(entity) or EntityGetRootEntity(entity)~=player then return false end
    local kind=NHProducts.linkKind(entity)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    local uses=item and NHEquipment.linkUses(kind,ComponentGetValue2(item,"uses_remaining"))
    if not uses then return false end
    if uses==1 then GameKillInventoryItem(player,entity)
    else ComponentSetValue2(item,"uses_remaining",uses-1) end
    return true
end

local function heal(player,percent,pay)
    local damage=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not damage then return false end
    local hp,max_hp=ComponentGetValue2(damage,"hp"),ComponentGetValue2(damage,"max_hp")
    if hp<=0 or hp>=max_hp then return false end
    local amount=max_hp*percent/100
    if pay and not pay() then return false end
    ComponentSetValue2(damage,"hp",math.min(max_hp,hp+amount))
    return true
end

local function eat(player,food,pay)
    if #food.effects==0 then return heal(player,food.healPercent,pay) end
    local pending={}
    local function discard()
        for _,entry in ipairs(pending) do if entry.fresh then EntityKill(entry.id) end end
    end
    for _,buff in ipairs(food.effects) do
        local tag="noita_hideout_meal_"..buff.key
        local entity=(EntityGetAllChildren(player,tag) or {})[1]
        local fresh=not entity
        if fresh then
            local x,y=EntityGetTransform(player)
            entity=EntityLoad("mods/noita_hideout/files/meal_"..buff.key..".xml",x,y)
            if not entity or entity==0 then discard(); return end
        end
        local timer=EntityGetFirstComponentIncludingDisabled(entity,"VariableStorageComponent")
        pending[#pending+1]={id=entity,fresh=fresh,timer=timer,buff=buff}
        if not timer then discard(); return end
    end
    local hook
    if (food.resources.egg or food.resources.meat)
        and not EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","noita_hideout_meal_defence") then
        hook=EntityAddComponent2(player,"LuaComponent",{_tags="noita_hideout_meal_defence",
            script_damage_about_to_be_received="mods/noita_hideout/files/meal_damage.lua",execute_every_n_frame=-1})
        if not hook or hook==0 then discard(); return end
    end
    if not pay() then
        if hook then EntityRemoveComponent(player,hook) end
        discard()
        return
    end
    for _,entry in ipairs(pending) do
        local buff,timer=entry.buff,entry.timer
        local strength=ComponentGetValue2(timer,"value_float")
        -- A weaker meal cannot prolong a stronger bonus.
        if entry.fresh or buff.strength>=strength then
            ComponentSetValue2(timer,"value_float",buff.strength)
            ComponentSetValue2(timer,"value_int",math.max(buff.seconds,ComponentGetValue2(timer,"value_int")))
        end
        if entry.fresh then EntityAddChild(player,entry.id) end
    end
    if food.healPercent then heal(player,food.healPercent) end
    return true
end

function NHProducts.aim(player,x,y,preferMouse)
    local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    if not controls then return end
    if not x then x,y=EntityGetTransform(player) end
    local dx,dy=ComponentGetValue2(controls,"mAimingVectorNormalized")
    -- A mouse click aims at the world cursor, even when a gamepad is connected.
    local cursor=false
    if preferMouse or InputIsMouseButtonDown(1) or InputIsMouseButtonDown(2) or not GameGetIsGamepadConnected() then
        local mx,my=DEBUG_GetMouseWorld()
        if type(mx)=="number" and type(my)=="number" then dx,dy,cursor=mx-x,my-y,true end
    end
    if type(dx)~="number" or type(dy)~="number" then return end
    local length=math.sqrt(dx*dx+dy*dy)
    if length<0.001 then return end
    return dx/length,dy/length,cursor and length or nil
end

-- Old physical items can still carry the previous sprite pivot or no muzzle.
-- Refresh both when taking a gun in hand, including guns loaded from a save.
local tubeMount={6,7,10,-4.5}
local pistolMount={0,0,6.25,-2.5,heldScale=0.25}
local mounts={
    derringer={4,7,12,-2}, flare_gun=pistolMount, sedative_launcher=pistolMount,
    magic_tube=tubeMount, fire_tube=tubeMount, frost_tube=tubeMount, shock_tube=tubeMount,
    -- Animated weapons carry their grip pivot in their sprite XML.
    heavy_mg={0,0,11,1.5}, auto_grenade={2,7,10,-2}, missile_launcher={4,7,7,-3},
    heavy_plasma={3,7,9,-4}, railgun={4,9,11,-3}, bfg={4,10,11,-3},
}
local mounted,currentMount,scaledSprite
local function refreshMount(weapon)
    for kind,mount in pairs(mounts) do
        if EntityHasTag(weapon,"noita_hideout_"..kind) then
            local sprite=EntityGetFirstComponentIncludingDisabled(weapon,"SpriteComponent","enabled_in_hand")
            local gun=NHGuns.types[kind]
            local original=gun.heldSprite or gun.displaySprite
            if sprite then
                local suffix=(kind=="railgun" or kind=="bfg") and ".png" or "_world.png"
                local scale=original and (mount.heldScale or 0.5) or 1
                ComponentSetValue2(sprite,"image_file",original or items..kind..suffix)
                ComponentSetValue2(sprite,"offset_x",mount[1]/scale)
                ComponentSetValue2(sprite,"offset_y",mount[2]/scale)
                if gun.heldSprite then
                    ComponentSetValue2(sprite,"rect_animation","default")
                    ComponentSetValue2(sprite,"next_rect_animation","default")
                end
                if original then
                    supportGround.repair(weapon,kind)
                    ComponentSetValue2(sprite,"has_special_scale",true)
                    ComponentSetValue2(sprite,"special_scale_x",scale)
                    ComponentSetValue2(sprite,"special_scale_y",scale)
                    if not EntityGetFirstComponentIncludingDisabled(weapon,"LuaComponent","nh_equipment_mirror") then
                        EntityAddComponent2(weapon,"LuaComponent",{_tags="enabled_in_hand,nh_equipment_mirror",
                            script_source_file="mods/noita_hideout/files/equipment_sprite_mirror.lua",execute_every_n_frame=1})
                    end
                end
                EntityRefreshSprite(weapon,sprite)
            end
            local hotspot=EntityGetFirstComponentIncludingDisabled(weapon,"HotspotComponent","shoot_pos")
                or EntityAddComponent2(weapon,"HotspotComponent",{_tags="shoot_pos"})
            ComponentSetValue2(hotspot,"offset",mount[3],mount[4])
            return mount,original and sprite
        end
    end
end

function NHProducts.poseSupportGun(player,weapon)
    if not weapon or not (EntityHasTag(weapon,"nh_support_weapon") or EntityHasTag(weapon,"nh_loaded_gun")) then mounted=nil; return end
    if weapon~=mounted then currentMount,scaledSprite=refreshMount(weapon); mounted=weapon end
    if not currentMount then return end
    local arm=(EntityGetAllChildren(player,"player_arm_r") or {})[1]
    local x,y
    if arm then x,y=EntityGetHotspot(arm,"hand",true) end
    if not x then x,y=EntityGetTransform(player) end
    local dx,dy,distance=NHProducts.aim(player,x,y)
    if not dx then return end
    local flip=dx<0 and -1 or 1
    EntityApplyTransform(weapon,x,y,math.atan2(dy,dx),1,flip)
    -- Special scale overrides the entity's flip. Apply the current aim
    -- immediately, including when firing on the same frame as a turn.
    if scaledSprite then
        local scaleY=ComponentGetValue2(scaledSprite,"special_scale_y")
        if scaleY*flip<0 then ComponentSetValue2(scaledSprite,"special_scale_y",-scaleY) end
    end
    -- Use the very pose applied to the sprite this frame for the launch point.
    local forward,side=currentMount[3],currentMount[4]*flip
    return dx,dy,x+dx*forward-dy*side,y+dy*forward+dx*side,distance
end

local function throw(player,definition,pay,aim,weapon)
    local dx,dy,tipX,tipY,cursorDistance
    if weapon then dx,dy,tipX,tipY,cursorDistance=NHProducts.poseSupportGun(player,weapon) end
    if not dx then
        if aim then dx,dy=aim.x,aim.y else dx,dy,cursorDistance=NHProducts.aim(player) end
    end
    if not dx then return end
    local x,y=EntityGetTransform(player)
    local attachFlash=false
    local anchorX,anchorY
    local forward=8
    if definition.patrolRange then
        local ax,ay=x,y
        if tipX then ax,ay=EntityGetTransform(weapon) end
        local reach=math.min(cursorDistance or definition.patrolRange,definition.patrolRange)
        local hit,hx,hy=RaytraceSurfaces(ax,ay,ax+dx*reach,ay+dy*reach)
        if hit then reach=math.max(0,math.sqrt((hx-ax)^2+(hy-ay)^2)-4) end
        anchorX,anchorY=ax+dx*reach,ay+dy*reach
        forward=math.min(forward,reach)
    end
    if tipX then
        local hit,hx,hy=RaytraceSurfaces(x,y,tipX,tipY)
        if hit then
            local backX,backY=x-hx,y-hy
            local distance=math.max(1,math.sqrt(backX*backX+backY*backY))
            x,y=hx+backX/distance,hy+backY/distance
        else
            x,y=tipX,tipY
            attachFlash=true
        end
    else
        x,y=x+dx*forward,y+dy*forward
    end
    local projectile=EntityLoad(definition.projectile,x,y)
    if not projectile or projectile==0 then return end
    local shot=EntityGetFirstComponentIncludingDisabled(projectile,"ProjectileComponent")
    local velocity=EntityGetFirstComponentIncludingDisabled(projectile,"VelocityComponent")
    local patrolReady=not anchorX or EntityAddComponent2(projectile,"VariableStorageComponent",
        {_tags="nh_patrol_anchor",value_int=math.floor(anchorX+0.5),value_float=anchorY})
    if not shot or not velocity or not patrolReady or not pay() then
        if shot then EntityRemoveComponent(projectile,shot) end
        EntityKill(projectile)
        return
    end
    -- GameShootProjectile has no return value. Set ownership and velocity as in
    -- the vanilla shoot_projectile helper after the engine registers the shot.
    local vx,vy=dx*definition.speed,dy*definition.speed
    GameShootProjectile(player,x,y,x+vx,y+vy,projectile)
    if definition.heldSprite and scaledSprite and EntityGetIsAlive(weapon) then
        NHGuns.animateShot(player,weapon,scaledSprite,definition.fireFrames)
    end
    if tipX then
        local px,py,angle,sx,sy=EntityGetTransform(projectile)
        if px~=x or py~=y then EntityApplyTransform(projectile,x,y,angle,sx,sy) end
    end
    ComponentSetValue2(shot,"mWhoShot",player)
    local genome=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
    if genome then ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(genome,"herd_id")) end
    ComponentSetValue2(velocity,"mVelocity",vx,vy)
    if definition.muzzle then
        local flash=EntityLoad(definition.muzzle,x,y)
        if flash and flash~=0 and attachFlash and EntityGetIsAlive(weapon) then
            EntityAddChild(weapon,flash)
            EntityAddComponent2(flash,"InheritTransformComponent",{parent_hotspot_tag="shoot_pos"})
        end
    end
    return true
end

function NHProducts.fireHeld(player)
    local entity=NHNative.held(player)
    if not entity or GameIsInventoryOpen() then return end
    for kind in pairs(NHTurrets.types) do
        if EntityHasTag(entity,"noita_hideout_"..kind) then
            local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
            local count=item and ComponentGetValue2(item,"uses_remaining")
            if not NHTurrets.validCount(count) then return end
            return dofile("mods/noita_hideout/files/turret_runtime.lua").deploy(player,kind,function()
                if count==1 then GameKillInventoryItem(player,entity)
                else ComponentSetValue2(item,"uses_remaining",count-1) end
                return true
            end)
        end
    end
    for kind,gun in pairs(NHGuns.types) do
        if EntityHasTag(entity,"noita_hideout_"..kind) then
            local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
            local rounds=NHGuns.physicalRounds(kind,entity,item)
            if not NHStore.validBandageCount(rounds) then return end
            return throw(player,gun,function()
                NHGuns.consumeRound(player,entity,item,rounds)
                return true
            end,nil,entity)
        end
    end
end

function NHProducts.apply(player,kind,pay,aim,available)
    local product=healing_items[kind]
    if bagCounts[kind] then return NHLootBags.open(player,kind,pay) end
    if product then return NHSurgery.begin(player,kind,available or function() return true end,pay) end
    if throwable_counts[kind] then return throw(player,NHThrowables.types[kind],pay,aim) end
    for _,food in ipairs(foods) do
        if kind==food.id then return eat(player,food,pay) end
    end
end

function NHProducts.use(player,entity,fromInventory,aim,settleLoot)
    if not entity then return end
    if fromInventory then
        if EntityGetRootEntity(entity)~=player then return end
    elseif GameIsInventoryOpen() or NHNative.held(player)~=entity then return end
    for _,kind in ipairs(products) do
        if EntityHasTag(entity,"noita_hideout_"..kind) then
            local product=healing_items[kind] or bagCounts[kind] or throwable_counts[kind]
            local item,uses
            if healing_items[kind] then
                local available,pay=NHSurgery.physicalSource(player,entity,fromInventory,4*NHMedkits.capacity(kind),kind=="bandage")
                return NHProducts.apply(player,kind,pay,aim,available)
            elseif foods.byId[kind] then
                item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                uses=item and ComponentGetValue2(item,"uses_remaining")
                if uses==-1 then uses=foods.byId[kind].uses end
                if not NHStore.validBandageCount(uses) then return end
            elseif product then
                item,uses=item_uses(entity,product)
                if not product.valid(uses) then return end
            end
            return NHProducts.apply(player,kind,function(dose,subtype)
                local bag=NHLootBags.types[kind]
                if (dose or (bag and bag.loot)) and not settleLoot(dose,subtype) then return false end
                if not uses or uses==1 then GameKillInventoryItem(player,entity)
                else ComponentSetValue2(item,"uses_remaining",uses-1) end
                return true
            end,aim)
        end
    end
end
