-- Only sweep planning uses this filter. Native projectiles still collide normally.
local M={}
local frame,solid,small
local function isSolid(x,y,key)
    local cached=solid[key]
    if cached~=nil then return cached end
    local hit,hx=RaytraceSurfaces(x+0.25,y+0.5,x+1.25,y+0.5)
    cached=hit and hx<x+1 or false
    solid[key]=cached
    return cached
end

-- Keep thin connected platforms, including diagonal ones. Stop the search
-- as soon as ten connected pixels prove this is more than a piece of debris.
local function isDebris(x,y)
    local key=x..","..y
    if small[key]~=nil then return small[key] end
    if not isSolid(x,y,key) then return nil end
    local queue={{x,y,key}}
    local seen={[key]=true}
    local tiny=true
    for _,cell in ipairs(queue) do
        for yy=cell[2]-1,cell[2]+1 do
            for xx=cell[1]-1,cell[1]+1 do
                local nextKey=xx..","..yy
                if not seen[nextKey] then
                    seen[nextKey]=true
                    if isSolid(xx,yy,nextKey) then
                        queue[#queue+1]={xx,yy,nextKey}
                        if #queue>9 or small[nextKey]==false then tiny=false; break end
                    end
                end
            end
            if not tiny then break end
        end
        if not tiny then break end
    end
    for _,cell in ipairs(queue) do small[cell[3]]=tiny end
    return tiny
end

function M.trace(x,y,tx,ty)
    local current=GameGetFrameNum()
    if frame~=current then frame,solid,small=current,{},{} end
    local vx,vy=tx-x,ty-y
    local length=math.sqrt(vx*vx+vy*vy)
    if length<0.001 then return RaytraceSurfaces(x,y,tx,ty) end
    local dx,dy=vx/length,vy/length
    local progress=0
    while progress<=length do
        local hit,hx,hy=RaytraceSurfaces(x+dx*progress,y+dy*progress,tx,ty)
        if not hit then return false end
        local debris=isDebris(math.floor(hx),math.floor(hy))
        if debris==nil then
            -- A boundary hit can be rounded onto the air side of the cell.
            debris=isDebris(math.floor(hx+dx*0.75),math.floor(hy+dy*0.75))
        end
        if not debris then return true,hx,hy end
        progress=math.max(progress,(hx-x)*dx+(hy-y)*dy)+1
    end
    return false
end

return M
