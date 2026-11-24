local root="mods/noita_hideout/files/bow/"
local shoot={}
-- Stage the whole volley before launching it. A missing entity cannot produce
-- a partial paid volley, or arm an impact callback during cleanup.
function shoot.volley(player,file,x,y,dx,dy,speed,count,spread,configure,notify)
    local path=file:match("%.xml$") and file or root..file..".xml"
    local arrows={}
    for i=1,count do
        local id=EntityLoad(path,x,y)
        local p=id and id~=0 and EntityGetFirstComponentIncludingDisabled(id,"ProjectileComponent")
        local v=p and EntityGetFirstComponentIncludingDisabled(id,"VelocityComponent")
        if not v then
            if id and id~=0 then EntityKill(id) end
            for _,a in ipairs(arrows) do EntityKill(a.id) end
            return false
        end
        arrows[i]={id=id,p=p,v=v}
    end
    local genome=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
    local angle=math.atan2(dy,dx)
    for i,a in ipairs(arrows) do
        local heading=angle+(i-(count+1)/2)*spread
        local nx,ny=math.cos(heading),math.sin(heading)
        ComponentSetValue2(a.p,"mWhoShot",player)
        if genome then ComponentSetValue2(a.p,"mShooterHerdId",ComponentGetValue2(genome,"herd_id")) end
        if configure then configure(a.id,a.p) end
        GameShootProjectile(player,x,y,x+nx*100,y+ny*100,a.id,notify and i==1 or false)
        ComponentSetValue2(a.v,"mVelocity",nx*speed,ny*speed)
    end
    return true
end
return shoot
