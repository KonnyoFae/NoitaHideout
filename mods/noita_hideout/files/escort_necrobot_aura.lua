local robot=GetUpdatedEntityID()
local x,y=EntityGetTransform(robot)
for _,ally in ipairs(EntityGetInRadiusWithTag(x,y,144,"nh_reinforcement") or {}) do
    if ally~=robot and not EntityHasTag(ally,"nh_revive_protected") and EntityGetHerdRelation(robot,ally)>=60 then
        local role=EntityGetFirstComponentIncludingDisabled(ally,"VariableStorageComponent","nh_reinforcement_role")
        if role and ComponentGetValue2(role,"value_string")~="necrobot" then
            local hook=EntityAddComponent2(ally,"LuaComponent",{execute_every_n_frame=-1,
                script_death="mods/noita_hideout/files/escort_necrobot_death.lua"})
            if hook and hook~=0 then
                -- A native mark would also respawn this escort as a hostile original.
                for _,c in ipairs(EntityGetComponentIncludingDisabled(ally,"LuaComponent") or {}) do
                    local death=ComponentGetValue2(c,"script_death")
                    if death=="data/scripts/status_effects/necrobot.lua" or death=="data/scripts/status_effects/necrobot_super.lua" then
                        EntityRemoveComponent(ally,c)
                    end
                end
                EntityAddTag(ally,"necrobot_NOT")
                EntityAddTag(ally,"nh_revive_protected")
                local ax,ay=EntityGetTransform(ally)
                local fx=EntityLoad("data/entities/particles/tinyspark_green_sparse.xml",ax,ay)
                if fx and fx~=0 then EntityAddChild(ally,fx) end
            end
        end
    end
end
