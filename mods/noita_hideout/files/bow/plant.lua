local arrow=GetUpdatedEntityID()
local shot=EntityGetFirstComponentIncludingDisabled(arrow,"ProjectileComponent")
local data=EntityGetFirstComponentIncludingDisabled(arrow,"VariableStorageComponent","nh_bow_field")
if not shot or not data or ComponentGetValue2(shot,"lifetime")<=0 then return end
local owner=ComponentGetValue2(data,"value_int")
if owner==0 or not EntityGetIsAlive(owner) then return end
local x,y,angle=EntityGetTransform(arrow)
if not x or not DoesWorldExistAt(math.floor(x)-1,math.floor(y)-1,math.ceil(x)+1,math.ceil(y)+1) then return end
local tier=ComponentGetValue2(data,"value_float")
local plant=dofile_once("mods/noita_hideout/files/bow/support_field.lua")
plant(owner,x,y,tier,angle)
