-- Called after the companion tick, in the controller's inventory state.
-- The run/frame receipt prevents granting a stored box again if the world
-- resumes from an earlier checkpoint than the persistent secure case.
return function(player,lang,activeDraft,save)
    local pending=EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_companion_gift")
    if not pending then return end
    local draft=activeDraft()
    if not draft then return end
    local frame=ComponentGetValue2(pending,"value_int")
    if draft.giftRun==draft.runSerial and frame<=(draft.giftFrame or -1) then
        EntityRemoveComponent(player,pending)
        return
    end
    local who=NHCompanions.species[ComponentGetValue2(pending,"value_string")]
    local kind="gift_box_"..ComponentGetValue2(pending,"value_float")
    local box=NHLootBags.item(kind)
    local slot,index=NHTransfers.storageSlot(draft,"safe",box)
    if slot then
        if index then NHStore.mergeStack(draft.safe[index].item,box)
        else
            if draft.nextItemId>=NHStore.maxResourceAmount then return end
            table.insert(draft.safe,{id=draft.nextItemId,slot=slot,item=box})
            draft.nextItemId=draft.nextItemId+1
        end
        draft.giftRun,draft.giftFrame=draft.runSerial,frame
        if not save(draft) then return end
    else
        local x,y=EntityGetTransform(player)
        local entity=EntityLoad("mods/noita_hideout/files/items/"..kind..".xml",x,y-4)
        if not entity or entity==0 then return end
    end
    EntityRemoveComponent(player,pending)
    if lang=="zh" then
        GamePrint(who.zh.."赠送了一件礼物盒。"..(slot and "已放入安全箱。" or "安全箱已满，礼物落在脚边。"))
    else
        GamePrint(who.en.." gave you a gift box. "..(slot and "Stored in the secure case." or "Case full. Dropped at your feet."))
    end
end
