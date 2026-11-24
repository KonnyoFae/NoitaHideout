local id=GetUpdatedEntityID()
local shot=EntityGetFirstComponentIncludingDisabled(id,"ProjectileComponent")
local owner=shot and ComponentGetValue2(shot,"mWhoShot")
if not owner or owner==0 or not EntityGetIsAlive(owner) then return end
local x,y,angle=EntityGetTransform(id)
if not x or not DoesWorldExistAt(math.floor(x)-1,math.floor(y)-1,math.ceil(x)+1,math.ceil(y)+1) then return end
local shoot=dofile_once("mods/noita_hideout/files/bow/shoot.lua")
shoot.volley(owner,"fragment",x,y,math.cos(angle),math.sin(angle),205,6,math.pi/3,nil,false)
