local patterns=dofile("mods/noita_hideout/files/strike_patterns.lua")
local frame,world=0,nil
function GameGetFrameNum() return frame end
local function scene(cells)
    frame=frame+1
    world=cells
end
function RaytraceSurfaces(x,y,tx,ty)
    local steps=math.max(1,math.ceil(math.max(math.abs(tx-x),math.abs(ty-y))*8))
    for i=0,steps do
        local hx,hy=x+(tx-x)*i/steps,y+(ty-y)*i/steps
        if world(math.floor(hx),math.floor(hy)) then return true,hx,hy end
    end
    return false
end
local function route(spec)
    return patterns.sweep(spec,{x=0,y=0,nx=0,ny=-1},-20,0)
end
for _,spec in ipairs({patterns.strafe,patterns.missile_strafe,patterns.plasma_strafe}) do
    scene(function(_,y) return y>=0 end)
    local flat=route(spec)
    assert(#flat==spec.shots and flat[#flat].x==(spec.shots-1)*spec.spacing)

    -- A 3x3 floater on the designation ray; more debris directly over a shot.
    scene(function(x,y)
        return y>=0 or x>=-1 and x<=1 and y>=-12 and y<=-10
            or x>=spec.spacing-1 and x<=spec.spacing+1 and y>=-5 and y<=-3
    end)
    local hit,_,hy=patterns.sweepTrace(0,-30,0,4)
    assert(hit and math.abs(hy)<0.2)
    local clear=route(spec)
    assert(#clear==#flat)
    for i,p in ipairs(clear) do assert(math.abs(p.x-flat[i].x)<0.2 and math.abs(p.y)<0.2) end

    -- An eight-pixel step up, a step down and a short crack under a landing.
    scene(function(x,y) return (x<31 or x>34) and y>=(x>=12 and x<=25 and -8 or 0) end)
    local rough=route(spec)
    assert(#rough==spec.shots and rough[#rough].x>65)
    for _,p in ipairs(rough) do assert(world(math.floor(p.x),math.floor(p.y))) end

    scene(function(x,y) return y>=math.floor(x/3) end)
    local slope=route(spec)
    assert(#slope==spec.shots and slope[#slope].y>19)

    scene(function(x,y) return x<=22 and y>=0 or x>=37 and y>=0 or y>=24 end)
    local edge=route(spec)
    assert(#edge==2 and edge[2].x<=22 and patterns.point(edge,3,true)==edge[1])
end

scene(function(x,y) return y==-4 and x>=-15 and x<=15 or y>=0 end)
local hit,_,y=patterns.sweepTrace(0,-20,0,5)
assert(hit and math.floor(y)==-4,"a continuous one-pixel platform is solid")
scene(function(x,y) return x==y and x>=-8 and x<=8 end)
assert(patterns.sweepTrace(-8,0,8,0),"a long diagonal seam is solid")
scene(function(x,y) return x==y and x>=-2 and x<=2 end)
assert(not patterns.sweepTrace(-8,0,8,0),"the next frame must see the newly broken debris")
scene(function(x,y) return x==4 and y>=-10 and y<=10 or x==0 and y==0 end)
local wall,hx=patterns.sweepTrace(-10,0,10,0)
assert(wall and math.floor(hx)==4)
for _,face in ipairs({{x=0,y=0,nx=1,ny=0},{x=0,y=0,nx=0,ny=1}}) do
    scene(function(x,y) return x*face.nx+y*face.ny<=0 end)
    assert(#patterns.sweep(patterns.strafe,face,0,-20)==patterns.strafe.shots)
end
