-- Physical workshop products use the same capture/restore journal as ordinary equipment.
NHProducts={}
local items="mods/noita_hideout/files/items/"
local function valid_uses(n)
    return type(n)=="number" and n>=1 and n<=3 and n==math.floor(n)
end

for _,kind in ipairs({"medkit","grenade"}) do
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

function NHProducts.use(player,entity)
    if not entity or GameIsInventoryOpen() or NHNative.held(player)~=entity then return end
    if EntityHasTag(entity,"noita_hideout_medkit") then
        local damage=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
        local item=EntityGetFirstComponentIncludingDisabled(entity,"ItemComponent")
        if not damage or not item then return end
        local hp,max_hp=ComponentGetValue2(damage,"hp"),ComponentGetValue2(damage,"max_hp")
        local uses=ComponentGetValue2(item,"uses_remaining")
        if hp<=0 or hp>=max_hp or not valid_uses(uses) then return end
        ComponentSetValue2(damage,"hp",math.min(max_hp,hp+0.4))
        if uses==1 then GameKillInventoryItem(player,entity)
        else ComponentSetValue2(item,"uses_remaining",uses-1) end
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
end
