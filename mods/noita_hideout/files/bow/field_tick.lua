local root="mods/noita_hideout/files/bow/"
local modes=dofile_once(root.."modes.lua")
local targets=dofile_once("mods/noita_hideout/files/companions/targets.lua")
local field=GetUpdatedEntityID()
local data=EntityGetFirstComponentIncludingDisabled(field,"VariableStorageComponent","nh_bow_field")
if not data then return end
local owner=ComponentGetValue2(data,"value_int")
if owner==0 or not EntityGetIsAlive(owner) then EntityKill(field); return end
local tier=ComponentGetValue2(data,"value_float")
local scan=ComponentGetValue2(data,"name")=="scout"
local mode=scan and modes[2] or modes[3]
local radius=mode.radius[tier]
if not radius then return end
local x,y=EntityGetTransform(field)

-- Only refresh effects applied by this bow. The native curse restores the
-- target's resistances when its single marked child expires.
local function refresh(target,tag,path,frames,useLifetime)
    local effect=(EntityGetAllChildren(target,tag) or {})[1]
    local fresh=not effect
    if fresh then
        local tx,ty=EntityGetTransform(target)
        effect=EntityLoad(path,tx,ty)
        if not effect or effect==0 then return end
        EntityAddTag(effect,tag)
        EntityAddChild(target,effect)
    end
    if useLifetime then
        local life=EntityGetFirstComponentIncludingDisabled(effect,"LifetimeComponent")
        local deadline=GameGetFrameNum()+frames
        if fresh or ComponentGetValue2(life,"kill_frame")<deadline then
            ComponentSetValue2(life,"lifetime",frames)
            ComponentSetValue2(life,"kill_frame",deadline)
        end
    else
        local buff=EntityGetFirstComponentIncludingDisabled(effect,"GameEffectComponent")
        ComponentSetValue2(buff,"frames",frames)
    end
end

if scan then
    for _,id in ipairs(EntityGetInRadiusWithTag(x,y,radius,"mortal") or {}) do
        if targets.hostile(owner,id) then
            refresh(id,"nh_bow_mark",root.."mark.xml",mode.mark[tier],true)
            if tier==4 then refresh(id,"nh_bow_frost","data/entities/misc/effect_frozen_short.xml",48,false) end
        end
    end
else
    local function aid(id)
        local dm=EntityGetFirstComponentIncludingDisabled(id,"DamageModelComponent")
        if not dm then return end
        local hp,max=ComponentGetValue2(dm,"hp"),ComponentGetValue2(dm,"max_hp")
        if hp<=0 then return end
        if hp<max then ComponentSetValue2(dm,"hp",math.min(max,hp+mode.healPerSecond[tier]/125)) end
        refresh(id,"nh_bow_rage","data/entities/misc/effect_berserk.xml",24,false)
        if tier==4 then refresh(id,"nh_bow_ward",root.."ward.xml",24,true) end
    end
    local px,py=EntityGetTransform(owner)
    if (px-x)^2+(py-y)^2<=radius^2 then aid(owner) end
    for _,id in ipairs(EntityGetInRadiusWithTag(x,y,radius,"mortal") or {}) do
        if id~=owner and (EntityHasTag(id,"nh_reinforcement") or EntityHasTag(id,"summon_player")
            or EntityHasTag(id,"noita_hideout_companion") or GameGetGameEffectCount(id,"CHARM")>0
            or (EntityGetFirstComponentIncludingDisabled(id,"GenomeDataComponent") and EntityGetHerdRelationSafe(owner,id)>=60)) then
            aid(id)
        end
    end
end
