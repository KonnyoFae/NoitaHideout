local M={}
local terrain=dofile("mods/noita_hideout/files/sweep_terrain.lua")
M.sweepTrace=terrain.trace
local dir="mods/noita_hideout/files/projectiles/"
local shell=dir.."strike_shell.xml"
local missile=dir.."strike_missile.xml"
M.tracking_strike={projectile=shell,radius=34,speed=420,direct=60,blast=30}
M.strafe={pattern="sweep",projectile=shell,radius=23,speed=380,shots=6,spacing=16,interval=13}
M.minelayer={surfaceOnly=true,projectile=dir.."strike_minelayer.xml",radius=0,danger=156,speed=320}
M.barrage={pattern="area",projectile=shell,radius=26,speed=380,shots=8,spread=47,interval=10}
M.missile_strafe={pattern="sweep",projectile=missile,radius=25,danger=67,speed=340,shots=6,spacing=18,interval=10}
M.plasma_strafe={pattern="sweep",projectile=dir.."strike_plasma.xml",radius=19,speed=470,shots=6,spacing=18,interval=9}
M.missile_barrage={pattern="area",projectile=missile,radius=28,danger=67,speed=340,shots=8,spread=56,interval=9}
M.rail_snipe={projectile=dir.."strike_rail.xml",radius=34,speed=1800,through=90}

-- Fixed intelligence targets use the cursor or the first blocking surface.
local deck="data/entities/projectiles/deck/"
M.berserk_field={placed=true,range=240,radius=28,delay=90,projectile=deck.."berserk_field.xml"}
M.polymorph_field={placed=true,range=240,radius=28,delay=180,projectile=deck.."polymorph_field.xml"}
M.black_hole_big={placed=true,range=360,radius=150,delay=300,alert={"巨大黑洞","Large black hole"},projectile=deck.."black_hole_big.xml"}
M.white_hole_big={placed=true,range=360,radius=150,delay=300,alert={"巨大白洞","Large white hole"},projectile=deck.."white_hole_big.xml"}
M.nuke={range=560,radius=250,speed=420,delay=480,alert={"核弹","Nuke"},projectile=deck.."nuke.xml"}
M.nuke_giga={range=560,radius=400,speed=420,delay=720,alert={"超级核弹","Giga nuke"},projectile=deck.."nuke_giga.xml"}

-- Search from the open side of the current surface. A ray that starts in a
-- raised step can report its own origin as a hit; retry from slightly farther out.
local function surfaceAhead(x,y,nx,ny)
    for lift=2,10,4 do
        local sx,sy=x+nx*lift,y+ny*lift
        local hit,hx,hy=terrain.trace(sx,sy,x-nx*9,y-ny*9)
        if not hit then return end
        if (sx-hx)*nx+(sy-hy)*ny>0.75 then return hx,hy end
    end
end

function M.sweepNormal(x,y,nx,ny)
    local tx,ty=-ny,nx
    local ax,ay=surfaceAhead(x-4*tx,y-4*ty,nx,ny)
    local bx,by=surfaceAhead(x+4*tx,y+4*ty,nx,ny)
    if not ax or not bx then return nx,ny end
    local ux,uy=by-ay,ax-bx
    local length=math.sqrt(ux*ux+uy*uy)
    if length<1 or ux*nx+uy*ny<0.5*length then return nx,ny end
    return ux/length,uy/length
end

function M.sweep(spec,first,px,py,last)
    local nx,ny=first.nx,first.ny
    local dx,dy=-ny,nx
    local projection=(first.x-px)*dx+(first.y-py)*dy
    if math.abs(projection)<2 and last then projection=dx*last.dx+dy*last.dy end
    if projection<0 then dx,dy=-dx,-dy end
    local route={dx=dx,dy=dy,{x=first.x,y=first.y,ox=nx*3,oy=ny*3}}
    local x,y=first.x,first.y
    local step,missed,maxGap=2,0,6
    local sinceShot=0
    while #route<spec.shots do
        local advance=missed+step
        local hx,hy=surfaceAhead(x+dx*advance,y+dy*advance,nx,ny)
        if hx and (hx-x)*dx+(hy-y)*dy>0.4 then
            local ux,uy=M.sweepNormal(hx,hy,nx,ny)
            if ux*first.nx+uy*first.ny>0.35 then
                -- Blend the normals so a single rough pixel cannot turn the run down a cliff.
                local bx,by=2*nx+ux,2*ny+uy
                local length=math.sqrt(bx*bx+by*by)
                nx,ny=bx/length,by/length
                local tx,ty=-ny,nx
                if tx*dx+ty*dy<0 then tx,ty=-tx,-ty end
                dx,dy=tx,ty
            end
            x,y=hx,hy
            sinceShot=sinceShot+advance
            missed=0
            if sinceShot>=spec.spacing then
                route[#route+1]={x=x,y=y,ox=nx*3,oy=ny*3}
                sinceShot=sinceShot-spec.spacing
            end
        else
            missed=advance
            if missed>maxGap then break end
        end
    end
    return route
end

-- One point per sector, shuffled with a local generator. Keep the same
-- pattern from designation through launch without disturbing Noita's RNG.
function M.area(spec,x,y,seed)
    local function random()
        seed=(seed*48271)%2147483647
        return seed/2147483647
    end
    local points={{x=x,y=y,ox=0,oy=0}}
    local sectors=spec.shots-1
    for i=1,sectors do
        local function sample()
            local angle=(i-1+random())*2*math.pi/sectors
            local r=spec.spread*math.sqrt(0.2+0.8*random())
            return {x=x+math.cos(angle)*r,y=y+math.sin(angle)*r,ox=0,oy=0}
        end
        points[i+1]=sample()
        points[i+1].alternatives={sample(),sample()}
    end
    for i=#points,3,-1 do
        local j=2+math.floor(random()*(i-1))
        points[j],points[i]=points[i],points[j]
    end
    return points
end

function M.point(route,index,sweep)
    if #route==1 then return route[1] end
    if not sweep then return route[(index-1)%#route+1] end
    local offset=(index-1)%(2*(#route-1))
    return route[1+math.min(offset,2*(#route-1)-offset)]
end
return M
