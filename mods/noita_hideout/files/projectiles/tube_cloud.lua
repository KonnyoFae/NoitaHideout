local cloud=GetUpdatedEntityID()
local x,y=EntityGetTransform(cloud)
local radius=68
local phase=GameGetFrameNum()/12
-- Distribute wet mist across the visible part of the room. Ground and pools struck
-- by discharges carry electricity according to their own material properties.
for i=1,12 do
    local angle=i*math.pi/6+phase*0.4
    local dx,dy=math.cos(angle),math.sin(angle)
    local length=radius*math.sqrt(((i*7+phase*3)%13+1)/14)
    local ex,ey=x+dx*length,y+dy*length
    local hit,hx,hy=RaytraceSurfacesAndLiquiform(x,y,ex,ey)
    if hit then ex,ey=hx-dx,hy-dy end
    GameCreateParticle("steam",ex,ey,8,dx*12,dy*8,false,false)
    GameCreateCosmeticParticle("spark_electric",ex,ey,1,dx*18,dy*18,0,0.12,0.32,true,true,false,false,0,0)
    if i%3==0 then
        GameCreateParticle("water",ex,ey,3,0,15,false,false)
        EntityLoad("data/entities/misc/electricity_medium.xml",hit and hx+dx*1.5 or ex,hit and hy+dy*1.5 or ey)
    end
end

local owner=EntityGetRootEntity(cloud)
for _,target in ipairs(EntityGetInRadiusWithTag(x,y,radius,"mortal") or {}) do
    local tx,ty=EntityGetFirstHitboxCenter(target)
    local hp=EntityGetFirstComponent(target,"DamageModelComponent")
    if tx and hp and not RaytraceSurfaces(x,y,tx,ty) and GameGetGameEffectCount(target,"PROTECTION_ELECTRICITY")==0
        and GameGetGameEffectCount(target,"PROTECTION_ALL")==0 and ComponentObjectGetValue2(hp,"damage_multipliers","electricity")>0 then
        if GameGetGameEffectCount(target,"ELECTROCUTION")==0 then
            EntityInflictDamage(target,0.12,"DAMAGE_ELECTRICITY","$nh_hideout_shock_tube","NONE",0,0,owner,tx,ty)
            if EntityGetIsAlive(target) and GameGetGameEffectCount(target,"STUN_PROTECTION_ELECTRICITY")==0
                and GameGetGameEffectCount(target,"ELECTROCUTION")==0 then
                LoadGameEffectEntityTo(target,"data/entities/misc/effect_electricity.xml")
            end
        end
    end
end
