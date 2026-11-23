local root="mods/noita_hideout/files/"
local T=NHTurrets or dofile(root.."turrets.lua")
local R={}
local ammo=dofile(root.."turrets/ammo.lua")
local function discard(id)
    for _,kind in ipairs({"LuaComponent","ExplodeOnDamageComponent"}) do
        for _,c in ipairs(EntityGetComponentIncludingDisabled(id,kind) or {}) do EntityRemoveComponent(id,c) end
    end
    local hp=EntityGetFirstComponentIncludingDisabled(id,"DamageModelComponent")
    if hp then ComponentSetValue2(hp,"create_ragdoll",false) end
    EntityKill(id)
end
function R.preview(player,kind)
    local px,py=EntityGetTransform(player)
    local dx,dy=NHProducts.aim(player)
    if not dx then return end
    local x,y=px+dx*28,py+dy*16
    local hit,_,ground=RaytracePlatforms(x,y-8,x,y+40)
    local valid=hit and ground~=nil and (x-px)^2+(ground-py)^2<=64^2
    y=hit and ground and ground-5 or y
    local view={x=x,y=y,kind=kind,valid=false,width=12,height=18,offsetX=6,offsetY=14}
    if not valid or RaytracePlatforms(px,py,x,y-6) then return view end
    for offset=-6,6,3 do
        if RaytracePlatforms(x+offset,y-14,x+offset,y+3) then return view end
    end
    for offset=-14,4,3 do
        if RaytracePlatforms(x-6,y+offset,x+6,y+offset) then return view end
    end
    if #(EntityGetInRadiusWithTag(x,y,22,"nh_deployed_turret") or {})>0 then return view end
    view.valid=true
    return view
end
function R.heldPreview(player)
    local held=NHNative.held(player)
    if not held then return end
    for _,kind in ipairs(T.order) do
        if EntityHasTag(held,"noita_hideout_"..kind) then return R.preview(player,kind) end
    end
end
local function spawnDecoy(kind,x,y,herd)
    local id=EntityLoad(root.."turrets/"..kind..".xml",x,y)
    if not id or id==0 then return end
    local genome=EntityGetFirstComponentIncludingDisabled(id,"GenomeDataComponent")
    local anchor=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_decoy_anchor")
    if not genome or not anchor or not EntityGetFirstComponentIncludingDisabled(id,"DamageModelComponent") then
        discard(id); return
    end
    ComponentSetValue2(genome,"herd_id",herd)
    ComponentSetValue2(anchor,"value_int",math.floor(x+0.5))
    ComponentSetValue2(anchor,"value_float",y)
    return id
end

function R.deploy(player,kind,pay)
    if not T.types[kind] then return end
    local view=R.preview(player,kind)
    if not view or not view.valid then
        if GamePrint then GamePrint("$nh_turret_no_ground") end
        return
    end
    local owner=EntityGetFirstComponentIncludingDisabled(player,"GenomeDataComponent")
    if not owner then return end
    local id=spawnDecoy(kind,view.x,view.y,ComponentGetValue2(owner,"herd_id"))
    if not id then return end
    if not pay() then discard(id); return end
    return true
end

-- Streamed legacy entities retain their released name even when their filename is unavailable.
function R.upgradeWorkshopDecoys()
    for _,id in ipairs(EntityGetWithTag("nh_deployed_turret") or {}) do
        if not EntityHasTag(id,"nh_decoy") and not EntityHasTag(id,"nh_reinforcement") then
            local kind=EntityGetName(id):match("^%$nh_hideout_(.+)$")
            local genome=EntityGetFirstComponentIncludingDisabled(id,"GenomeDataComponent")
            local old=EntityGetFirstComponentIncludingDisabled(id,"DamageModelComponent")
            if T.types[kind] and genome and old then
                local x,y=EntityGetTransform(id)
                local replacement=spawnDecoy(kind,x,y,ComponentGetValue2(genome,"herd_id"))
                if replacement then
                    local hp=EntityGetFirstComponentIncludingDisabled(replacement,"DamageModelComponent")
                    local fraction=ComponentGetValue2(old,"hp")/math.max(0.001,ComponentGetValue2(old,"max_hp"))
                    ComponentSetValue2(hp,"hp",math.min(1,fraction)*ComponentGetValue2(hp,"max_hp"))
                    discard(id)
                end
            end
        end
    end
end

-- Old saves serialize the mobile robot body and its native firing callbacks.
local motionComponents={"AnimalAIComponent","CharacterPlatformingComponent","CharacterDataComponent","CharacterCollisionComponent",
    "VelocityComponent","PathFindingComponent","PathFindingGridMarkerComponent"}
local function upgradeEmplacement(id,tag)
    if EntityGetFirstComponentIncludingDisabled(id,"LuaComponent","nh_mount_control") then return end
    local model=EntityGetFirstComponentIncludingDisabled(id,"DamageModelComponent")
    if not model then return end
    if tag=="nh_mg_turret" then ammo.upgradeMachineGun(id) end
    ComponentObjectSetValue2(model,"damage_multipliers","melee",0)
    for _,kind in ipairs(motionComponents) do
        for _,c in ipairs(EntityGetComponentIncludingDisabled(id,kind) or {}) do
            EntitySetComponentIsEnabled(id,c,false)
        end
    end
    for _,c in ipairs(EntityGetComponentIncludingDisabled(id,"AIAttackComponent") or {}) do
        EntityRemoveComponent(id,c)
    end
    for _,c in ipairs(EntityGetComponentIncludingDisabled(id,"LuaComponent") or {}) do
        if ComponentGetValue2(c,"script_shot")==root.."turrets_shot.lua" or ComponentHasTag(c,"nh_mg_burst_tick") then
            EntityRemoveComponent(id,c)
        end
    end
    local gun=EntityGetFirstComponentIncludingDisabled(id,"SpriteComponent","gun")
    if gun then EntityRemoveComponent(id,gun) end
    local base=EntityGetFirstComponentIncludingDisabled(id,"SpriteComponent","character")
    if base then
        ComponentSetValue2(base,"z_index",2)
        EntityRefreshSprite(id,base)
    end
    local hit=EntityGetFirstComponentIncludingDisabled(id,"HitboxComponent")
    if hit then ComponentSetValue2(hit,"aabb_min_y",-9) end
    EntityAddTag(id,"nh_terrain_mount")
    local x,y=EntityGetTransform(id)
    EntitySetTransform(id,x,y,0,1,1)
    EntityAddComponent2(id,"LuaComponent",{_tags="nh_mount_control",script_source_file=root.."turrets/mount.lua",execute_every_n_frame=4})
end
function R.upgradeEmplacements()
    for _,tag in ipairs({"nh_mg_turret","nh_chaingun_turret"}) do
        for _,id in ipairs(EntityGetWithTag(tag) or {}) do upgradeEmplacement(id,tag) end
    end
end

function R.status(player)
    local px,py=EntityGetTransform(player)
    local closest,best=nil,52^2
    for _,id in ipairs(EntityGetInRadiusWithTag(px,py,52,"nh_terrain_mount") or {}) do
        local x,y=EntityGetTransform(id)
        local distance=(x-px)^2+(y-py)^2
        if distance<=best then closest,best=id,distance end
    end
    if not closest then return end
    local health=EntityGetFirstComponentIncludingDisabled(closest,"DamageModelComponent")
    local counter=ammo.counter(closest)
    if not health or not counter then return end
    local rounds=ComponentGetValue2(counter,"value_int")
    local hp=math.ceil(ComponentGetValue2(health,"hp")*25)
    local maxHP=math.floor(ComponentGetValue2(health,"max_hp")*25+0.5)
    local x,y=EntityGetTransform(closest)
    local capacity=ComponentGetValue2(counter,"value_float")
    if maxHP<=0 or capacity<=0 then return end
    return {x=x,y=y,hp=hp,maxHP=maxHP,rounds=rounds,capacity=capacity}
end
return R
