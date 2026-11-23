local id=GetUpdatedEntityID()
local x,y,_,facing=EntityGetTransform(id)
local anchor=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_decoy_anchor")
local flight=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_decoy_flight")
local homeX,homeY=ComponentGetValue2(anchor,"value_int"),ComponentGetValue2(anchor,"value_float")
local frame=GameGetFrameNum()
local phase=frame/50+homeX*0.1
local tx,ty=homeX+20*math.sin(phase),homeY-15+5*math.cos(phase)
local target=ComponentGetValue2(flight,"value_int")
local pursuing=false
if target~=0 and EntityGetIsAlive(target) and EntityGetFirstComponent(target,"GenomeDataComponent")
    and EntityGetHerdRelation(target,id)<40 and GameGetGameEffectCount(target,"CHARM")==0 then
    local ex,ey=EntityGetFirstHitboxCenter(target)
    if ex and (ex-homeX)^2+(ey+6-homeY)^2<=72^2 and not RaytracePlatforms(x,y-6,ex,ey) then
        tx,ty,pursuing=ex,ey+6,true
    end
end

local dx,dy=tx-x,ty-y
local distance=math.sqrt(dx*dx+dy*dy)
local nextKick=ComponentGetValue2(flight,"value_float")
if nextKick>frame+45 then nextKick=0 end
if pursuing and distance<=11 and frame>=nextKick then
    local sign=dx<0 and -1 or 1
    EntityInflictDamage(target,0.16,"DAMAGE_MELEE","$nh_decoy_kick","NORMAL",sign*65,-20,id,tx,ty-6,60)
    ComponentSetValue2(flight,"value_float",frame+45)
    EntitySetTransform(id,x,y,0,sign,1)
    GamePlayAnimation(id,"attack",2,"fly_idle",0)
    return
end
-- Back out of contact during recovery instead of hovering inside an enemy's melee hitbox.
local recovering=pursuing and nextKick>frame
if recovering then
    local side=dx<0 and -1 or (dx>0 and 1 or facing)
    dx,dy=dx-side*21,dy-6
    distance=math.sqrt(dx*dx+dy*dy)
end
if distance<1 then return end
local step=math.min(pursuing and 2.8 or 1.3,distance)
dx,dy=dx*step/distance,dy*step/distance
local function clear(sx,sy)
    local edgeX=sx>=0 and 4 or -4
    local edgeY=sy>=0 and 2 or -12
    return not RaytracePlatforms(x+edgeX,y-12,x+edgeX+sx,y-12+sy)
        and not RaytracePlatforms(x+edgeX,y+2,x+edgeX+sx,y+2+sy)
        and not RaytracePlatforms(x-edgeX,y+edgeY,x-edgeX+sx,y+edgeY+sy)
end
if not clear(dx,dy) then
    if dy~=0 and clear(0,dy) then dx=0
    elseif dx~=0 and clear(dx,0) then dy=0
    else return end
end
local before=(x-homeX)^2+(y-homeY)^2
local after=(x+dx-homeX)^2+(y+dy-homeY)^2
if after>72^2 and after>=before then return end
if not recovering and math.abs(dx)>0.1 then facing=dx<0 and -1 or 1 end
EntitySetTransform(id,x+dx,y+dy,0,facing,1)
if recovering and nextKick-frame>25 then return end
local sprite=EntityGetFirstComponent(id,"SpriteComponent","character")
local animation=pursuing and "fly_move" or "fly_idle"
if sprite and ComponentGetValue2(sprite,"rect_animation")~=animation then
    GamePlayAnimation(id,animation,1)
end
