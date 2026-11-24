-- The controller owns the caller's personal stock. EW owns the downed bodies.
-- Persist the five packs and the exact request together before contacting the host.
return function(current,draftForRun,save,tr,feedback)
    local M={}
    local cost=5
    local stockKey="supply_logistics"
    local requestKey="nh_ew.reinforce_request"
    local offerKey="nh_ew.reinforce_sponsor_offer"
    local replyKey="nh_ew.reinforce_sponsor_reply"
    local lastRoster,targets,lastChecked
    local lastSponsor,pollEarlier
    local function validPosition(n)
        return type(n)=="number" and math.abs(n)<1073741824
    end

    local function roster()
        local raw=GlobalsGetValue("nh_ew.reinforce_targets","")
        if raw~=lastRoster then
            lastRoster,targets=raw,{}
            for line in raw:gmatch("[^\r\n]+") do
                local owner,episode,x,y,label=line:match("^(%w+)|([1-9]%d*)|(-?%d+)|(-?%d+)|(.*)$")
                x,y=tonumber(x),tonumber(y)
                if validPosition(x) and validPosition(y) and #owner<=40 and #episode<=15 and owner~=NHEW.issuer() then
                    targets[owner]={episode=episode,x=x,y=y,redirect=label:match("^[^|]*|redirect$")~=nil}
                end
            end
        end
        return targets
    end

    function M.visible()
        local world=NHEW.world()
        local state=current()
        return world~=nil and state~=nil and state.ewActive==world
            and GlobalsGetValue("nh_ew.reinforce_mode","")==world
    end

    function M.redirectAvailable()
        if not M.visible() then return false end
        for _,target in pairs(roster()) do
            if target.redirect then return true end
        end
        return false
    end

    function M.available()
        if not M.visible() then return false,tr("联机增援尚未就绪。","Multiplayer reinforcement is unavailable.") end
        if M.redirectAvailable() then return true end
        local state=current()
        if (state.resources[stockKey] or 0)<cost then return false,tr("需要 5 点补给资源。","Requires 5 supply logistics packs.") end
        local pending=state.ewReinforcePending
        for target in pairs(roster()) do
            if not pending or not pending[target] then return true end
        end
        return false,tr("暂无可增援的倒地队友。","No downed teammate is available for reinforcement.")
    end

    function M.select(player,x,y)
        local ok,reason=M.available()
        if not ok then return nil,reason end
        if not NHEW.localBody(player) or not validPosition(x) or not validPosition(y) then
            return nil,tr("无法确认呼叫者的位置。","Could not locate the caller.")
        end
        local best,distance
        local redirect=M.redirectAvailable()
        local pending=current().ewReinforcePending
        for owner,target in pairs(roster()) do
            local d=(x-target.x)^2+(y-target.y)^2
            if target.redirect==redirect and (redirect or not pending or not pending[owner])
                and (not distance or d<distance or (d==distance and owner<best)) then
                best,distance=owner,d
            end
        end
        local target=targets[best]
        return {world=NHEW.world(),owner=NHEW.issuer(),target=best,episode=target.episode,
            x=target.x,y=target.y,redirect=redirect}
    end

    function M.request(player,x,y,ticket)
        local ok,reason=M.available()
        if not ok then return false,reason end
        local owner=NHEW.issuer()
        local target=ticket and roster()[ticket.target]
        if not owner or not NHEW.localBody(player) or not target or target.episode~=ticket.episode
            or ticket.owner~=owner or ticket.world~=NHEW.world() then
            return false,tr("这次倒地已结束，增援取消。","The selected teammate is no longer down. Reinforcement canceled.")
        end
        if not validPosition(x) or not validPosition(y) then return false,tr("无法提交这次空投。","Cannot submit this drop.") end
        if target.redirect then
            if not ticket.redirect then return false,tr("请为这次增援另选落点。","Select a new landing site for this reinforcement.") end
            GlobalsSetValue("nh_ew.reinforce_redirect",table.concat({ticket.world,ticket.target,ticket.episode,math.floor(x),math.floor(y)},"|"))
            return true
        end
        if ticket.redirect then return false,tr("这次增援的落点已更新。","This reinforcement's landing site has changed.") end
        local draft=draftForRun()
        if not draft or draft.ewActive~=ticket.world or (draft.ewReinforcePending and draft.ewReinforcePending[ticket.target]) then
            return false,tr("增援档案已改变。","The reinforcement record has changed.")
        end
        if draft.revision>=999999999999999 then
            return false,tr("无法提交这次空投。","Cannot submit this drop.")
        end
        if (draft.resources[stockKey] or 0)<cost then return false,tr("需要 5 点补给资源。","Requires 5 supply logistics packs.") end
        local request=table.concat({ticket.world,owner,string.format("%.0f",draft.revision+1),ticket.target,
            ticket.episode,math.floor(x),math.floor(y)},"|")
        NHStore.deductStock(draft.resources,{[stockKey]=cost})
        draft.ewReinforcePending=draft.ewReinforcePending or {}
        draft.ewReinforcePending[ticket.target]=request
        if not save(draft) then return false,tr("无法保存这次增援请求。","Could not save the reinforcement request.") end
        GlobalsSetValue(requestKey,request)
        return true
    end

    local function nextEntry(entries,previous)
        local first,after
        for who in pairs(entries) do
            if not first or who<first then first=who end
            if previous and who>previous and (not after or who<after) then after=who end
        end
        return after or first
    end
    local function refund(draft)
        local stock=draft.resources[stockKey] or 0
        if stock>NHStore.maxResourceAmount-cost then return false end
        draft.resources[stockKey]=stock+cost
        return true
    end

    -- Offers come from EW after host authentication. Reserve on this player's
    -- profile before acknowledging, including while this player is spectating.
    function M.updateSponsor()
        local s=current()
        local world=NHEW.world()
        local payer=NHEW.issuer()
        if not world or not payer or not s or s.ewActive~=world then return end
        local held=s.ewReinforceSponsors
        local offer=GlobalsGetValue(offerKey,"")
        local order
        if offer~="" and M.visible() and not (held and pollEarlier) then
            order=offer
            pollEarlier=true
        elseif held then
            lastSponsor=nextEntry(held,lastSponsor)
            order=lastSponsor
            pollEarlier=false
        end
        if not order then return end
        local caller,tx=NHStore.reinforcementOrder(order,world)
        if not caller or caller==payer then return end
        local payment=held and held[order]
        if not payment then
            local draft=draftForRun()
            if not draft or draft.ewActive~=world then return end
            payment=draft.ewReinforceSponsors and draft.ewReinforceSponsors[order]
            if not payment then
                if (draft.resources[stockKey] or 0)<cost then
                    GlobalsSetValue(replyKey,order.."|none")
                    return
                end
                if draft.revision>=999999999999999 then return end
                payment=string.format("%.0f",draft.revision+1)
                NHStore.deductStock(draft.resources,{[stockKey]=cost})
                draft.ewReinforceSponsors=draft.ewReinforceSponsors or {}
                draft.ewReinforceSponsors[order]=payment
                if not save(draft) then return end
            end
        end
        local reply=order.."|"..payment
        local receipt=GlobalsGetValue("nh_ew.reinforce_sponsor_result."..table.concat({world,caller,tx,payer,payment},"."),"")
        if receipt~="ok" and receipt~="rejected" then
            if GlobalsGetValue(replyKey,"")~=reply then GlobalsSetValue(replyKey,reply) end
            return
        end
        local draft=draftForRun()
        if not draft or not draft.ewReinforceSponsors or draft.ewReinforceSponsors[order]~=payment then return end
        if receipt=="rejected" and not refund(draft) then return end
        draft.ewReinforceSponsors[order]=nil
        if not next(draft.ewReinforceSponsors) then draft.ewReinforceSponsors=nil end
        if not save(draft) then return end
        if GlobalsGetValue(replyKey,"")==reply then GlobalsSetValue(replyKey,"") end
        if GlobalsGetValue(offerKey,"")==order then GlobalsSetValue(offerKey,"") end
        if receipt=="ok" then feedback(tr("已接手增援，消耗 5 点补给。","Reinforcement sponsored. Spent 5 supply packs."))
        else feedback(tr("接手预留的 5 点补给已退还。","Refunded 5 supply packs reserved for reinforcement.")) end
    end

    function M.settle()
        local entries=current().ewReinforcePending
        if not entries then return end
        -- Rotate the mailbox through concurrent calls, even when a target disconnects.
        lastChecked=nextEntry(entries,lastChecked)
        local pending=entries[lastChecked]
        local world,owner,id=pending:match("^([%w_-]+)|([%w_-]+)|(%d+)|")
        if not world or world~=NHEW.world() or owner~=NHEW.issuer() then return end
        local receipt=GlobalsGetValue("nh_ew.reinforce_result."..world.."."..owner.."."..id,"")
        if receipt~="ok" and receipt~="rejected" and receipt~="transferred" then
            if GlobalsGetValue(requestKey,"")~=pending then GlobalsSetValue(requestKey,pending) end
            return
        end
        local draft=draftForRun()
        if not draft or not draft.ewReinforcePending or draft.ewReinforcePending[lastChecked]~=pending then return end
        if receipt~="ok" and not refund(draft) then return end
        draft.ewReinforcePending[lastChecked]=nil
        if not next(draft.ewReinforcePending) then draft.ewReinforcePending=nil end
        if not save(draft) then return end
        if GlobalsGetValue(requestKey,"")==pending then GlobalsSetValue(requestKey,"") end
        if receipt=="ok" then feedback(tr("队友已满血归队，消耗 5 点补给。","Teammate revived at full health. Spent 5 supply packs."))
        elseif receipt=="transferred" then feedback(tr("队友已接手增援，5 点补给已退还。","A teammate took over. Refunded 5 supply packs."))
        else feedback(tr("增援取消，5 点补给已退还。","Reinforcement canceled. Refunded 5 supply packs.")) end
    end
    return M
end
