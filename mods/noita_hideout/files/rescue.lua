-- A player component holds an in-flight rescue until the world and profile
-- both settle. The damage hook and the controller execute in separate Lua VMs.
local R={}
local root="mods/noita_hideout/files/"
local ew=NHEW or dofile(root.."ew.lua")
local releasedPlayer
local watch
local function rewind()
    if not watch then watch=NHRewind or dofile(root.."rewind_watch.lua") end
    return watch
end
local function meter(player)
    return EntityGetFirstComponentIncludingDisabled(player,"VariableStorageComponent","nh_rescue")
end
local function captureGold(player,record,source,x,y)
    if not ew.walletAllowed() then return false end
    local wallet=EntityGetFirstComponentIncludingDisabled(player,"WalletComponent")
    if not wallet then return false end
    local money=ComponentGetValue2(wallet,"money")
    local inf=ComponentGetValue2(wallet,"mHasReachedInf")
    local keep=source=="policy" and 0 or math.min(money,NHAffinity.livePoints(source))
    ComponentSetValue2(record,"value_string",("%s:%.9g:%.9g:%.0f:%.0f:%d"):format(source,x,y,keep,money-keep,inf and 1 or 0))
    if inf then ComponentSetValue2(wallet,"mHasReachedInf",false) end
    ComponentSetValue2(wallet,"money",keep)
    return true
end

function R.view(state,player)
    local species=NHCompanions.active(player)
    local limit=species and NHAffinity.livePoints(species) or 0
    local wallet=EntityGetFirstComponentIncludingDisabled(player,"WalletComponent")
    local money=wallet and ComponentGetValue2(wallet,"money")
    local kept=type(money)=="number" and math.min(math.max(0,money),limit) or nil
    return {insured=state.insuranceActive==true,species=species,limit=limit,kept=kept}
end

-- Temporarily suspend unspent vanilla lives while a rescue is available.
-- Tags persist with components, so save/continue restores only our suspension.
function R.lifePriority(player,available)
    if not player then return end
    if available~=false and not ew.rescueAllowed() then return end
    if available==nil then
        local record=meter(player)
        available=record and (ComponentGetValue2(record,"value_string")~="" or ComponentGetValue2(record,"value_int")>0)
            or NHCompanions.active(player)~=nil
    end
    local owners={player}
    for _,child in ipairs(EntityGetAllChildren(player) or {}) do owners[#owners+1]=child end
    for _,owner in ipairs(owners) do
        for _,effect in ipairs(EntityGetComponentIncludingDisabled(owner,"GameEffectComponent") or {}) do
            local tag="nh_rescue_paused_life"
            local ours=ComponentHasTag(effect,tag)
            local eligible=ComponentGetValue2(effect,"effect")=="RESPAWN" and not ComponentGetValue2(effect,"mIsSpent")
            if ours and (not available or not eligible) then
                EntitySetComponentIsEnabled(owner,effect,true)
                ComponentRemoveTag(effect,tag)
            elseif available and eligible and not ours and ComponentGetIsEnabled(effect) then
                ComponentAddTag(effect,tag)
                EntitySetComponentIsEnabled(owner,effect,false)
            end
        end
    end
end

function R.intercept(player,dm)
    if ComponentGetValue2(dm,"hp")>0 then return end
    if not ew.rescueAllowed() or not ew.walletAllowed() then return end
    local record=meter(player)
    if not record then return end
    if ComponentGetValue2(record,"value_string")=="" then
        local species,pet=NHCompanions.active(player)
        if not species and ComponentGetValue2(record,"value_int")==0 then return end
        local x,y=EntityGetTransform(player)
        if not captureGold(player,record,species or "policy",x,y) then return end
        if pet then
            NHCompanions.clearSupport(player)
            EntityRemoveFromParent(pet)
            EntityKill(pet)
        end
    end
    ComponentSetValue2(dm,"hp",ComponentGetValue2(dm,"max_hp")*0.5)
end

local function worldKey(state)
    return "nh_rescue."..state.profile.."."..state.runSerial
end

-- Polymorph serializes the original body with its inventory and companion.
-- Latch the fatal position on the temporary body, then bill the real wallet
-- after the native transformation effect restores it.
function R.polymorph(state,body)
    if body and GlobalsGetValue("nh_rewind.clock","")~="" and rewind().polymorph(body,state) then return end
    local dm=body and EntityGetFirstComponentIncludingDisabled(body,"DamageModelComponent")
    if not dm then return end
    local tag="nh_rescue_poly_wait"
    if not ew.rescueAllowed() then
        -- EW takes over this body's death flags, even if we set them first.
        if ComponentHasTag(dm,tag) then ComponentRemoveTag(dm,tag) end
        return
    end
    local key=worldKey(state)
    local species=GlobalsGetValue(key..".companion","")
    if species=="" and not state.insuranceActive then
        if ComponentHasTag(dm,tag) then
            ComponentRemoveTag(dm,tag)
            ComponentSetValue2(dm,"wait_for_kill_flag_on_death",false)
            if ComponentGetValue2(dm,"hp")<=0 then ComponentSetValue2(dm,"kill_now",true) end
        end
        return
    end
    local effect
    for _,kind in ipairs({"POLYMORPH","POLYMORPH_RANDOM","POLYMORPH_UNSTABLE","POLYMORPH_CESSATION"}) do
        local c=GameGetGameEffect(body,kind)
        if c and c~=0 then effect=c; break end
    end
    if not effect then return end
    if not ComponentGetValue2(dm,"wait_for_kill_flag_on_death") then
        ComponentSetValue2(dm,"wait_for_kill_flag_on_death",true)
        ComponentAddTag(dm,tag)
    end
    if ComponentGetValue2(dm,"hp")<=0 then
        if GlobalsGetValue(key..".return","")=="" then
            local x,y=EntityGetTransform(body)
            GlobalsSetValue(key..".return",("%s:%.9g:%.9g"):format(species~="" and species or "policy",x,y))
        end
        ComponentSetValue2(dm,"hp",ComponentGetValue2(dm,"max_hp")*0.5)
    end
    if GlobalsGetValue(key..".return","")~="" then ComponentSetValue2(effect,"frames",1) end
end

function R.arm(state,player)
    if not ew.rescueAllowed() then
        if releasedPlayer~=player then
            -- Pre-compatibility saves can have native extra lives suspended and
            -- an escrowed loss on the body. Keep the escrow for solo settlement.
            R.lifePriority(player,false)
            local record=meter(player)
            if record then
                if ComponentGetValue2(record,"value_string")=="" then
                    EntityRemoveComponent(player,record)
                else
                    ComponentSetValue2(record,"value_bool",false)
                end
            end
            releasedPlayer=player
        end
        return
    end
    releasedPlayer=nil
    local dm=EntityGetFirstComponentIncludingDisabled(player,"DamageModelComponent")
    if not dm then return end
    local key=worldKey(state)
    local species,pet=NHCompanions.active(player)
    if GlobalsGetValue(key..".companion","")~=(species or "") then GlobalsSetValue(key..".companion",species or "") end
    local returning=GlobalsGetValue(key..".return","")
    local record=meter(player)
    if record and ComponentGetValue2(record,"value_string")~="" then R.lifePriority(player,true); return end
    local policy=state.insuranceActive and state.insuranceSerial or 0
    if returning=="" and policy==0 and not species then
        R.lifePriority(player,false)
        if record then
            if ComponentGetValue2(record,"value_bool") then
                ComponentSetValue2(dm,"wait_for_kill_flag_on_death",false)
                if ComponentGetValue2(dm,"hp")<=0 then ComponentSetValue2(dm,"kill_now",true) end
            end
            EntityRemoveComponent(player,record)
        end
        return
    end
    if not record then
        record=EntityAddComponent2(player,"VariableStorageComponent",{_tags="nh_rescue",value_string="",
            value_bool=not ComponentGetValue2(dm,"wait_for_kill_flag_on_death")})
        if not record then return end
        ComponentSetValue2(dm,"wait_for_kill_flag_on_death",true)
    end
    ComponentSetValue2(record,"value_int",policy)
    R.lifePriority(player,true)
    if returning~="" then
        local source,x,y=returning:match("^([^:]+):([^:]+):([^:]+)$")
        if not captureGold(player,record,source,tonumber(x),tonumber(y)) then return end
        if pet and source==species then
            NHCompanions.clearSupport(player)
            EntityRemoveFromParent(pet)
            EntityKill(pet)
        end
        ComponentSetValue2(dm,"hp",ComponentGetValue2(dm,"max_hp")*0.5)
        GlobalsSetValue(key..".return","")
    end
    R.intercept(player,dm)
end

function R.settle(state,player,homeX,homeY,commit,dispatch)
    if not ew.rescueAllowed() or not ew.walletAllowed() then return end
    local record=meter(player)
    if not record then return end
    local pending=ComponentGetValue2(record,"value_string")
    if pending=="" then return end
    local source,x,y,keep,lost,inf=pending:match("^([^:]+):([^:]+):([^:]+):(%d+):(%d+):([01])$")
    x,y=tonumber(x),tonumber(y)
    if not x or not y or not homeX or not homeY then return end
    keep,lost,inf=tonumber(keep),tonumber(lost),inf=="1"
    local crate
    if lost>0 or inf then
        crate=EntityLoad(root.."items/lost_gold_case.xml",x,y)
        local value=crate and crate~=0 and EntityGetFirstComponentIncludingDisabled(crate,"VariableStorageComponent","nh_lost_gold")
        if not value then
            if crate and crate~=0 then EntityKill(crate) end
            return
        end
        ComponentSetValue2(value,"value_string",("%.0f"):format(lost))
        ComponentSetValue2(value,"value_bool",inf)
    end
    if source=="policy" and state.insuranceActive then
        local serial=ComponentGetValue2(record,"value_int")
        if not commit(function(draft)
            if draft.insuranceSerial~=serial then return false,"Insurance policy changed." end
            draft.insuranceActive=false
            return true
        end) then
            if crate then EntityKill(crate) end
            return
        end
    end
    if dispatch then dispatch(player,homeX,homeY) else EntitySetTransform(player,homeX,homeY) end
    local px,py=EntityGetTransform(player)
    local grace=EntityLoad("data/entities/misc/effect_protection_all_short.xml",px,py)
    if grace and grace~=0 then EntityAddChild(player,grace) end
    local motion=EntityGetFirstComponentIncludingDisabled(player,"CharacterDataComponent")
    if motion then ComponentSetValue2(motion,"mVelocity",0,0) end
    ComponentSetValue2(record,"value_string","")
    ComponentSetValue2(record,"value_int",0)
    return source,keep,lost
end
return R
