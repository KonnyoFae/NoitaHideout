-- The supplied four-frame slash is cosmetic. Combat owns its attack token,
-- swept volume and hit list; the fading image never applies extra damage.
local M={}
local file="mods/noita_hideout/files/katana_fx.xml"
local defaultScale={hf_blade=0.5,hf_murasama=0.5,dragon_king=0.75}

local function finite(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end

local function position(entity,x,y,angle,scale,flip)
    -- The four animation frames occupy y=-15..13 relative to the grip.
    -- Check the tip and both outer edges so an oblique wall also shortens
    -- the visible arc, using the same terrain query as blade contact.
    local dx,dy=math.cos(angle),math.sin(angle)
    local ratio=1
    for edge=-1,1 do
        local vx=(64*dx-15*edge*dy)*scale
        local vy=(64*dy+15*edge*dx)*scale
        local blocked,hx,hy=RaytracePlatforms(x,y,x+vx,y+vy)
        if blocked then
            local length=math.sqrt(vx*vx+vy*vy)
            local along=((hx-x)*vx+(hy-y)*vy)/length
            ratio=math.min(ratio,math.max(0,(along-1)/length))
        end
    end
    scale=math.max(0.0001,scale*ratio)
    local scaleY=(flip and flip<0 and -1 or 1)*scale
    EntitySetTransform(entity,x,y,angle,scale,scaleY)
    EntityApplyTransform(entity,x,y,angle,scale,scaleY)
end

function M.follow(entity,x,y,angle,scale,flip)
    if EntityGetIsAlive(entity) and EntityHasTag(entity,"nh_katana_fx") then position(entity,x,y,angle,scale,flip) end
end

function M.spawn(x,y,angle,kind,scale,flip)
    if not finite(x) or not finite(y) or not finite(angle) then return end
    -- Art and contact have separate lengths so the tip has a small allowance.
    scale=scale or defaultScale[kind] or 0.5
    if not finite(scale) or scale<=0 then return end
    scale=math.min(scale,4)
    local entity=EntityLoad(file,x,y)
    if not entity or entity==0 then return end
    position(entity,x,y,angle,scale,flip)
    return entity
end

return M
