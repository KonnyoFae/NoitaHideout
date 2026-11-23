function death()
    local id=GetUpdatedEntityID()
    local role=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_reinforcement_role")
    if not role then return end
    local x,y=EntityGetTransform(id)
    local marker=EntityLoad("mods/noita_hideout/files/escort_necrobot_revive.xml",x,y)
    if not marker or marker==0 then return end
    local data=EntityGetFirstComponentIncludingDisabled(marker,"VariableStorageComponent","necrobot_entity_file")
    if not data then EntityKill(marker); return end
    ComponentSetValue2(data,"value_string",ComponentGetValue2(role,"value_string"))
    local ammo=EntityGetFirstComponentIncludingDisabled(id,"VariableStorageComponent","nh_turret_ammo")
    if ammo then
        ComponentSetValue2(data,"value_bool",true)
        ComponentSetValue2(data,"value_int",ComponentGetValue2(ammo,"value_int"))
    end
end
