-- Keep the skin's original body, arm image, scale and attachment points.
-- The blade image extends backwards from its grip; the engine still owns the
-- player's arm and inventory. The sword crosses the waist behind the body;
-- its handle faces the aim direction while its long blade extends backwards.
local M={}
local posed={}
local kinds={hf_blade=true,hf_murasama=true,dragon_king=true}
local scale=0.5
local itemFiles="mods/noita_hideout/files/items/"

local function finite(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end

local function alive(entity)
    return entity and entity~=0 and EntityGetIsAlive(entity)
end

local function near(a,b)
    return type(a)=="number" and type(b)=="number" and math.abs(a-b)<0.0001
end

local function restoreArm(record)
    if not record.arm or not alive(record.arm) then return end
    local x,y,r,sx,sy=EntityGetTransform(record.arm)
    local applied=record.applied
    -- Do not overwrite an engine update or another mod's later pose.
    if applied and near(x,applied[1]) and near(y,applied[2]) and near(r,applied[3])
        and near(sx,applied[4]) and near(sy,applied[5]) then
        local original=record.original
        EntitySetTransform(record.arm,original[1],original[2],original[3],original[4],original[5])
    end
    record.arm,record.original,record.applied=nil,nil,nil
end

local function release(player)
    local record=posed[player]
    if not record then return end
    restoreArm(record)
    if alive(record.mount) then
        -- EntityKill is deferred until the engine finishes its current frame.
        if record.mountSprite then ComponentSetValue2(record.mountSprite,"visible",false) end
        EntityKill(record.mount)
    end
    if alive(record.weapon) then
        local sprite=EntityGetFirstComponentIncludingDisabled(record.weapon,"SpriteComponent","enabled_in_hand")
        if sprite then
            ComponentSetValue2(sprite,"visible",true)
            ComponentSetValue2(sprite,"z_index",-1.5)
        end
    end
    posed[player]=nil
end

function M.reset(player)
    if player then release(player); return end
    for owner in pairs(posed) do release(owner) end
end

function M.pose(player,weapon,kind,frame,action)
    if not alive(player) or not alive(weapon) or not kinds[kind] then M.reset(player);return end
    local prior=posed[player]
    if prior and prior.weapon~=weapon then release(player);prior=nil end
    if prior then restoreArm(prior) end
    local sprite=EntityGetFirstComponentIncludingDisabled(weapon,"SpriteComponent","enabled_in_hand")
    if not sprite then return end
    local record=prior or {weapon=weapon}
    posed[player]=record
    if not alive(record.mount) then
        -- The engine owns the held item's render matrix. Give only this sword
        -- a display child; the skin's native body and arm remain untouched.
        for _,child in ipairs(EntityGetAllChildren(weapon,"nh_katana_mount") or {}) do EntityKill(child) end
        record.mount=EntityCreateNew("Katana hand mount")
        EntityAddTag(record.mount,"nh_katana_mount")
        record.mountSprite=EntityAddComponent2(record.mount,"SpriteComponent",{
            image_file=itemFiles..kind.."_sprite.xml",rect_animation="default",
            has_special_scale=true,special_scale_x=scale,special_scale_y=scale,z_index=0.625,
        })
        EntityAddChild(weapon,record.mount)
    end
    ComponentSetValue2(sprite,"visible",false)
    local arm=(EntityGetAllChildren(player,"player_arm_r") or {})[1]
    action=type(action)=="table" and action or {}
    local kick=action.handKick
    if alive(arm) and finite(kick) and kick~=0 then
        kick=math.max(-0.12,math.min(0.12,kick))
        local x,y,r,sx,sy=EntityGetTransform(arm)
        if finite(x) and finite(y) and finite(r) then
            sx,sy=sx or 1,sy or 1
            record.arm,record.original=arm,{x,y,r,sx,sy}
            record.applied={x,y,r+kick,sx,sy}
            EntitySetTransform(arm,x,y,r+kick,sx,sy)
        end
    end
    local x,y=EntityGetTransform(player)
    if not finite(x) or not finite(y) then return end
    y=y-3
    local angle=action.angle
    if not finite(angle) then
        local dx,dy
        if NHProducts and NHProducts.aim then dx,dy=NHProducts.aim(player,x,y) end
        if not finite(dx) or not finite(dy) or dx*dx+dy*dy<0.00001 then
            local _,_,_,facing=EntityGetTransform(player)
            dx,dy=facing and facing<0 and -1 or 1,0
        end
        angle=math.atan2(dy,dx)
    end
    -- A torso-relative belt mount keeps the blade behind the character even
    -- when vanilla extends the empty native hand towards the cursor.
    x,y=x+math.cos(angle)*4,y+math.sin(angle)*4
    -- Rotation aims the grip's +X axis forwards; only local Y flips for the
    -- opposite facing. A second X mirror would turn the blade towards enemies.
    local flip=math.cos(angle)<0 and -1 or 1
    -- ApplyTransform refreshes the native item's Ability/attachment components,
    -- which immediately replace this angle with their cached cursor rotation.
    EntitySetTransform(weapon,x,y,angle,1,flip)
    ComponentSetValue2(sprite,"has_special_scale",true)
    ComponentSetValue2(sprite,"special_scale_x",scale)
    ComponentSetValue2(sprite,"special_scale_y",scale*flip)
    local body=EntityGetFirstComponent(player,"SpriteComponent","character")
    local depth=body and ComponentGetValue2(body,"z_index")
    ComponentSetValue2(sprite,"z_index",(finite(depth) and depth or 0.6)+0.025)
    ComponentSetValue2(record.mountSprite,"special_scale_y",scale*flip)
    ComponentSetValue2(record.mountSprite,"z_index",(finite(depth) and depth or 0.6)+0.025)
    -- The SpriteComponent owns local Y reflection; keeping the entity scale
    -- positive avoids native matrix decomposition changing a left-facing angle.
    EntitySetTransform(record.mount,x,y,angle,1,1)
    EntityApplyTransform(record.mount,x,y,angle,1,1)
    return x,y,angle
end

return M
