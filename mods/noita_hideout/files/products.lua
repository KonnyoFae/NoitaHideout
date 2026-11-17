-- Physical workshop products use the same capture/restore journal as ordinary equipment.
NHProducts={icons={}}
local items="mods/noita_hideout/files/items/"
local healing_items={
    bandage={field="count",default=1,legacySingle=true,valid=NHStore.validBandageCount,healHP=5,error="Invalid bandage count."},
}
for kind,kit in pairs(NHMedkits.types) do
    local id=kind
    healing_items[kind]={field="remaining",default=id=="medkit" and kit.uses or nil,healHP=kit.healHP,healPercent=kit.healPercent,
        valid=function(n) return NHMedkits.validUses(id,n) end,error="Invalid medkit."}
end
local function item_uses(entity,product)
    local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
    local uses=item and ComponentGetValue2(item,"uses_remaining")
    -- Old single grenades and bandages used the engine's unset charge count.
    if item and product.legacySingle and (uses==-1 or uses==nil) then uses=1 end
    return item,uses
end

local foods=dofile("mods/noita_hideout/files/cooking.lua")
local products={}
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
    local icon=items..id..".png"
    NHProducts.icons[id]=icon
    local product=healing_items[id] or throwable_counts[id]
    local surgery=NHSurgeryKits.types[id]
    if surgery then
        product={field="remaining",valid=function(n) return n==surgery.uses end,error="Invalid surgery kit."}
    end
    NHTransfers.registerItem(id,function(entity) return EntityHasTag(entity,"noita_hideout_"..id) end,{
        capture=function(entity)
            local record={kind=id,name="$nh_hideout_"..id,icon=icon}
            if product then
                local _,uses=item_uses(entity,product)
                if not product.valid(uses) then return nil,product.error end
                record[product.field]=uses
            end
            return record
        end,
        restore=function(record,x,y)
            local uses
            if product then
                uses=record[product.field]
                if uses==nil then uses=product.default end
                if not product.valid(uses) then return nil,product.error end
            end
            local entity=EntityLoad(items..id..".xml",x,y)
            if not entity or entity==0 then return nil,"Item could not be created." end
            if product then
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                if not item then EntityKill(entity); return nil,product.error end
                ComponentSetValue2(item,"uses_remaining",uses)
            end
            return entity
        end,
    })
end

local function heal(player,fixedHP,percent,pay)
    local damage=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not damage then return false end
    local hp,max_hp=ComponentGetValue2(damage,"hp"),ComponentGetValue2(damage,"max_hp")
    if hp<=0 or hp>=max_hp then return false end
    local amount=percent and max_hp*percent/100 or fixedHP/25
    if pay and not pay() then return false end
    ComponentSetValue2(damage,"hp",math.min(max_hp,hp+amount))
    return true
end

local function eat(player,food,pay)
    local regen=food.effect=="bread"
    local component=regen and "VariableStorageComponent" or "GameEffectComponent"
    local field=regen and "value_int" or "frames"
    local duration=regen and food.seconds or food.seconds*60
    local tag="noita_hideout_effect_"..food.effect
    local effect
    for _,child in ipairs(EntityGetAllChildren(player,tag) or {}) do
        if EntityHasTag(child,tag) then effect=child; break end
    end
    local fresh=not effect
    if fresh then
        local x,y=EntityGetTransform(player)
        effect=EntityLoad("mods/noita_hideout/files/effect_"..food.effect..".xml",x,y)
        if not effect or effect==0 then return end
    end
    local timer=EntityGetFirstComponentIncludingDisabled(effect,component)
    if not timer or not pay() then
        if fresh then EntityKill(effect) end
        return
    end
    ComponentSetValue2(timer,field,math.max(duration,ComponentGetValue2(timer,field) or 0))
    if fresh then EntityAddChild(player,effect) end
    if food.healHP then heal(player,food.healHP) end
    return true
end

function NHProducts.aim(player)
    local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
    if not controls then return end
    local x,y=EntityGetTransform(player)
    local dx,dy=ComponentGetValue2(controls,"mAimingVectorNormalized")
    -- A mouse click aims at the world cursor, even when a gamepad is connected.
    if InputIsMouseButtonDown(2) or not GameGetIsGamepadConnected() then
        local mx,my=DEBUG_GetMouseWorld()
        if type(mx)=="number" and type(my)=="number" then dx,dy=mx-x,my-y end
    end
    if type(dx)~="number" or type(dy)~="number" then return end
    local length=math.sqrt(dx*dx+dy*dy)
    if length<0.001 then return end
    return dx/length,dy/length
end

local function throw(player,definition,pay,aim)
    local dx,dy
    if aim then dx,dy=aim.x,aim.y else dx,dy=NHProducts.aim(player) end
    if not dx then return end
    local x,y=EntityGetTransform(player)
    x,y=x+dx*8,y+dy*8
    local projectile=EntityLoad(definition.projectile,x,y)
    if not projectile or projectile==0 then return end
    local shot=EntityGetFirstComponentIncludingDisabled(projectile,"ProjectileComponent")
    local velocity=EntityGetFirstComponentIncludingDisabled(projectile,"VelocityComponent")
    if not shot or not velocity or not pay() then
        if shot then EntityRemoveComponent(projectile,shot) end
        EntityKill(projectile)
        return
    end
    -- GameShootProjectile has no return value. Set ownership and velocity as in
    -- the vanilla shoot_projectile helper after the engine registers the shot.
    local vx,vy=dx*definition.speed,dy*definition.speed
    GameShootProjectile(player,x,y,x+vx,y+vy,projectile)
    ComponentSetValue2(shot,"mWhoShot",player)
    local genome=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
    if genome then ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(genome,"herd_id")) end
    ComponentSetValue2(velocity,"mVelocity",vx,vy)
    return true
end

function NHProducts.apply(player,kind,pay,aim)
    local product=healing_items[kind]
    if product then return heal(player,product.healHP,product.healPercent,pay) end
    if throwable_counts[kind] then return throw(player,NHThrowables.types[kind],pay,aim) end
    for _,food in ipairs(foods) do
        if kind==food.id then return eat(player,food,pay) end
    end
end

function NHProducts.use(player,entity,fromInventory,aim)
    if not entity then return end
    if fromInventory then
        if EntityGetRootEntity(entity)~=player then return end
    elseif GameIsInventoryOpen() or NHNative.held(player)~=entity then return end
    for _,kind in ipairs(products) do
        if EntityHasTag(entity,"noita_hideout_"..kind) then
            local product=healing_items[kind] or throwable_counts[kind]
            local item,uses
            if product then
                item,uses=item_uses(entity,product)
                if not product.valid(uses) then return end
            end
            return NHProducts.apply(player,kind,function()
                if not uses or uses==1 then GameKillInventoryItem(player,entity)
                else ComponentSetValue2(item,"uses_remaining",uses-1) end
                return true
            end,aim)
        end
    end
end
