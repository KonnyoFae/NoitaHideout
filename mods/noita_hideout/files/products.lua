-- Physical workshop products use the same capture/restore journal as ordinary equipment.
NHProducts={}
local items="mods/noita_hideout/files/items/"
local function valid_uses(n)
    return type(n)=="number" and n>=1 and n<=3 and n==math.floor(n)
end

local foods=dofile("mods/noita_hideout/files/cooking.lua")
local products={"medkit","grenade","bandage"}
for _,food in ipairs(foods) do products[#products+1]=food.id end
for _,kind in ipairs(products) do
    local id=kind
    NHTransfers.registerItem(id,function(entity) return EntityHasTag(entity,"noita_hideout_"..id) end,{
        capture=function(entity)
            local record={kind=id,name="$nh_hideout_"..id,icon=items..id..".png"}
            if id=="medkit" then
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                record.remaining=item and ComponentGetValue2(item,"uses_remaining")
                if not valid_uses(record.remaining) then return nil,"Invalid medkit." end
            end
            return record
        end,
        restore=function(record,x,y)
            if id=="medkit" and record.remaining~=nil and not valid_uses(record.remaining) then return nil,"Invalid medkit." end
            local entity=EntityLoad(items..id..".xml",x,y)
            if not entity or entity==0 then return nil,"Item could not be created." end
            if id=="medkit" then
                local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
                if not item then EntityKill(entity); return nil,"Invalid medkit." end
                ComponentSetValue2(item,"uses_remaining",record.remaining or 3)
            end
            return entity
        end,
    })
end

local function heal(player,amount)
    local damage=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not damage then return false end
    local hp,max_hp=ComponentGetValue2(damage,"hp"),ComponentGetValue2(damage,"max_hp")
    if hp<=0 or hp>=max_hp then return false end
    ComponentSetValue2(damage,"hp",math.min(max_hp,hp+amount))
    return true
end

local function eat(player,entity,food)
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
    if not timer then
        if fresh then EntityKill(effect) end
        return
    end
    ComponentSetValue2(timer,field,math.max(duration,ComponentGetValue2(timer,field) or 0))
    if fresh then EntityAddChild(player,effect) end
    if food.healHP then heal(player,food.healHP/25) end
    GameKillInventoryItem(player,entity)
    return true
end

function NHProducts.use(player,entity)
    if not entity or GameIsInventoryOpen() or NHNative.held(player)~=entity then return end
    if EntityHasTag(entity,"noita_hideout_medkit") then
        local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
        local uses=item and ComponentGetValue2(item,"uses_remaining")
        if not valid_uses(uses) or not heal(player,0.4) then return end
        if uses==1 then GameKillInventoryItem(player,entity)
        else ComponentSetValue2(item,"uses_remaining",uses-1) end
        return true
    elseif EntityHasTag(entity,"noita_hideout_bandage") then
        if not heal(player,0.2) then return end
        GameKillInventoryItem(player,entity)
        return true
    elseif EntityHasTag(entity,"noita_hideout_grenade") then
        local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
        if not controls then return end
        local x,y=EntityGetTransform(player)
        local dx,dy=ComponentGetValue2(controls,"mAimingVectorNormalized")
        -- Aim at the world cursor on a mouse click, including when a gamepad is plugged in.
        if ComponentGetValue2(controls,"mButtonDownLeftClick") or not GameGetIsGamepadConnected() then
            local mx,my=DEBUG_GetMouseWorld()
            if type(mx)=="number" and type(my)=="number" then dx,dy=mx-x,my-y end
        end
        if type(dx)~="number" or type(dy)~="number" then return end
        local length=math.sqrt(dx*dx+dy*dy)
        if length<0.001 then return end
        dx,dy=dx/length,dy/length
        x,y=x+dx*8,y+dy*8
        local projectile=EntityLoad("data/entities/projectiles/deck/grenade_small.xml",x,y)
        if not projectile or projectile==0 then return end
        local shot=EntityGetFirstComponentIncludingDisabled(projectile,"ProjectileComponent")
        local velocity=EntityGetFirstComponentIncludingDisabled(projectile,"VelocityComponent")
        if not shot or not velocity then
            if shot then EntityRemoveComponent(projectile,shot) end
            EntityKill(projectile)
            return
        end
        -- GameShootProjectile has no return value. Follow the native shoot_projectile
        -- helper by assigning the shooter, herd and throw velocity to the loaded entity.
        GameShootProjectile(player,x,y,x+dx*180,y+dy*180,projectile)
        ComponentSetValue2(shot,"mWhoShot",player)
        local genome=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
        if genome then ComponentSetValue2(shot,"mShooterHerdId",ComponentGetValue2(genome,"herd_id")) end
        ComponentSetValue2(velocity,"mVelocity",dx*180,dy*180)
        GameKillInventoryItem(player,entity)
        return true
    end
    for _,food in ipairs(foods) do
        if EntityHasTag(entity,"noita_hideout_"..food.id) then return eat(player,entity,food) end
    end
end
