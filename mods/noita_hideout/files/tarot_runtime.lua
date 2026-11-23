local root="mods/noita_hideout/files/"
local T=NHTarot or dofile(root.."tarot.lua")
local R={}
local paths={
    tarot_hermit={"data/entities/misc/effect_invisibility.xml","data/entities/misc/effect_stains_drop_faster.xml"},
    tarot_chariot={"data/entities/misc/perks/shield.xml","data/entities/misc/perks/contact_damage.xml"},
}
local function clock(player,id) return EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_"..id) end
local function remove(id)
    -- Unpaid physical rewards must not leave a physics body behind.
    for _,body in ipairs(EntityGetComponentIncludingDisabled(id,"PhysicsBodyComponent") or {}) do
        ComponentSetValue2(body,"on_death_leave_physics_body",false)
    end
    EntityRemoveFromParent(id)
    EntityKill(id)
end
local function resistance(player,factor)
    for _,dm in ipairs(EntityGetComponentIncludingDisabled(player,"DamageModelComponent") or {}) do
        for _,kind in ipairs({"projectile","explosion"}) do
            local current=ComponentObjectGetValue2(dm,"damage_multipliers",kind)
            ComponentObjectSetValue2(dm,"damage_multipliers",kind,current*factor)
        end
    end
end
function R.expire(player,id)
    for _,entity in ipairs(EntityGetAllChildren(player,"nh_"..id) or {}) do remove(entity) end
    local c=clock(player,id)
    if id=="tarot_hermit" and GameGetGameEffectCount(player,"INVISIBILITY")==0 then
        -- Vanilla INVISIBILITY removal restores sprites. Do not reveal a
        -- player who still has the perk or an unrelated invisibility effect.
        for _,sprite in ipairs(EntityGetComponentIncludingDisabled(player,"SpriteComponent") or {}) do
            ComponentSetValue2(sprite,"alpha",1)
        end
    end
    if id=="tarot_chariot" then
        for _,hook in ipairs(EntityGetComponentIncludingDisabled(player,"LuaComponent","nh_tarot_revenge") or {}) do
            EntityRemoveComponent(player,hook)
        end
        if c and ComponentGetValue2(c,"value_bool") then resistance(player,1/0.8) end
    end
    if c then EntityRemoveComponent(player,c) end
end
-- Older garden effects were GameEffect children without a perk icon.
-- Restore only their presentation, including the engine's consumed-life state.
function R.refreshLifeIcons(player)
    for _,entity in ipairs(EntityGetAllChildren(player) or {}) do
        local path=(EntityGetFilename and EntityGetFilename(entity) or ""):gsub(string.char(92),"/")
        if EntityHasTag(entity,"nh_tarot_life") or path:sub(-#(root.."tarot_life.xml"))==root.."tarot_life.xml" then
            local effect=EntityGetFirstComponentIncludingDisabled(entity,"GameEffectComponent")
            if effect and ComponentGetValue2(effect,"effect")=="RESPAWN" then
                local icon=EntityGetFirstComponentIncludingDisabled(entity,"UIIconComponent")
                local sprite="data/ui_gfx/perk_icons/"..(ComponentGetValue2(effect,"mIsSpent") and "respawn_spent" or "respawn")..".png"
                if not icon then
                    icon=EntityAddComponent2(entity,"UIIconComponent",{name="$perk_respawn",description="$perkdesc_respawn",
                        icon_sprite_file=sprite,is_perk=true,display_in_hud=true})
                elseif ComponentGetValue2(icon,"icon_sprite_file")~=sprite then
                    ComponentSetValue2(icon,"icon_sprite_file",sprite)
                end
            end
        end
    end
end
function R.tick(player)
    for _,id in ipairs({"tarot_hermit","tarot_chariot"}) do
        local c=clock(player,id)
        if c then
            local now=GameGetFrameNum()
            local previous=ComponentGetValue2(c,"value_float")
            if now~=previous then
                local left=ComponentGetValue2(c,"value_int")-math.max(1,now-previous)
                if left<=0 then R.expire(player,id)
                else ComponentSetValue2(c,"value_int",left); ComponentSetValue2(c,"value_float",now) end
            end
        end
    end
end
function R.apply(player,id,pay)
    if not T.types[id] then return end
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not dm or ComponentGetValue2(dm,"hp")<=0 then return end
    local x,y=EntityGetTransform(player)
    local entities,components={},{}
    local function rollback()
        for _,entity in ipairs(entities) do remove(entity) end
        for _,c in ipairs(components) do EntityRemoveComponent(player,c) end
    end
    local function spawn(path,tag,attach)
        local entity=EntityLoad(path,x,y-10)
        if not entity or entity==0 then return end
        entities[#entities+1]=entity
        if tag then EntityAddTag(entity,tag) end
        local effect=EntityGetFirstComponentIncludingDisabled(entity,"GameEffectComponent")
        if (path==root.."tarot_life.xml" or path:find("/effect_",1,true)) and not effect then return end
        if effect then ComponentSetValue2(effect,"frames",-1) end
        if attach then
            EntityAddChild(player,entity)
            if EntityGetParent(entity)~=player then return end
        end
        return entity
    end
    local function add(kind,values)
        local c=EntityAddComponent2(player,kind,values)
        if c and c~=0 then components[#components+1]=c; return c end
    end
    local existing=paths[id] and clock(player,id)
    local timer=existing
    if id=="tarot_garden" then
        if not spawn(root.."tarot_life.xml","nh_tarot_life",true) then rollback(); return end
    elseif id=="tarot_tower" then
        if not spawn("data/entities/items/pickup/beamstone.xml",nil,false) then rollback(); return end
    elseif not existing then
        for _,path in ipairs(paths[id]) do
            if not spawn(path,"nh_"..id,true) then rollback(); return end
        end
        timer=add("VariableStorageComponent",{_tags="nh_"..id,value_int=T.duration,value_float=GameGetFrameNum()})
        if not timer then rollback(); return end
        if id=="tarot_chariot" and not add("LuaComponent",{_tags="nh_tarot_revenge",
            script_damage_received="data/scripts/perks/revenge_bullet.lua",execute_every_n_frame=-1}) then rollback(); return end
    end
    if paths[id] and not EntityGetFirstComponentIncludingDisabled(player,"LuaComponent","nh_tarot_tick") then
        if not add("LuaComponent",{_tags="nh_tarot_tick",script_source_file=root.."tarot_tick.lua",execute_every_n_frame=1}) then rollback(); return end
    end
    local paid,reason=pay()
    if not paid then rollback(); return nil,reason end
    if timer then
        ComponentSetValue2(timer,"value_int",T.duration)
        ComponentSetValue2(timer,"value_float",GameGetFrameNum())
        if id=="tarot_chariot" and not existing then
            resistance(player,0.8)
            ComponentSetValue2(timer,"value_bool",true)
        end
    elseif id=="tarot_garden" then
        -- Match vanilla EXTRA_HP, including the HP cap and health gained.
        for _,model in ipairs(EntityGetComponentIncludingDisabled(player,"DamageModelComponent") or {}) do
            local old=ComponentGetValue2(model,"max_hp")
            local cap=ComponentGetValue2(model,"max_hp_cap") or 0
            local maximum=cap>0 and math.min(old*1.5,cap) or old*1.5
            local hp=ComponentGetValue2(model,"hp")
            ComponentSetValue2(model,"max_hp",maximum)
            ComponentSetValue2(model,"hp",math.min(maximum,hp+math.abs(maximum-old)))
        end
    end
    if id=="tarot_garden" then R.refreshLifeIcons(player) end
    return true
end
return R
