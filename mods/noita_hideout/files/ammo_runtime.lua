local R={}
local staff=dofile("mods/noita_hideout/files/battle_staff.lua")
R.registerStaff=staff.register
R.guardMimic=staff.guardMimic
local targetKey="nh_ammo_gold_target"
local activeGun,activeRig,heldSince,due

local function goldKey(s)
    local row=s and s.gearRig
    if row then return ("nh_ammo_gold.%d.%d.%d"):format(s.profile,s.runSerial,row.id) end
end

function R.bind(s)
    local key=s and s.gearRig and s.gearRig.item.reserve<NHFirearms.rigs[s.gearRig.item.kind].capacity and goldKey(s) or ""
    if GlobalsGetValue(targetKey,"")~=key then GlobalsSetValue(targetKey,key) end
end

function R.reset()
    staff.reset()
    activeGun,activeRig,heldSince,due=nil,nil,nil,nil
    R.bind(nil)
end

-- Pickup scripts and the controller have separate Lua states. The cumulative
-- world counter is acknowledged in the same profile write as the reserve.
function R.gold(s,commit)
    local key=goldKey(s)
    if not key then return true end
    local total=math.floor((tonumber(GlobalsGetValue(key,"0")) or 0)/10)
    local item=s.gearRig.item
    local seen=item.goldKey==key and item.goldSeen or 0
    if total<=seen then return true end
    return commit(function(draft)
        if goldKey(draft)~=key then return false,"Inventory slot changed." end
        local rig=draft.gearRig.item
        local prior=rig.goldKey==key and rig.goldSeen or 0
        rig.reserve=math.min(NHFirearms.rigs[rig.kind].capacity,rig.reserve+10*math.max(0,total-prior))
        rig.goldKey,rig.goldSeen=key,math.max(total,prior)
        return true
    end)
end

local function aimedMode(player)
    local dx,dy
    if GameGetIsGamepadConnected() then
        local controls=EntityGetFirstComponentIncludingDisabled(player,"ControlsComponent")
        if not controls then return end
        dx,dy=ComponentGetValue2(controls,"mAimingVectorNormalized")
        if dx*dx+dy*dy<0.1 then return end
    else
        local mx,my=DEBUG_GetMouseWorld()
        local cx,cy,width,height=GameGetCameraBounds()
        dx,dy=mx-cx-width/2,my-cy-height/2
        if dx*dx+dy*dy<(height*0.04)^2 then return end
    end
    if math.abs(dx)>math.abs(dy) then return dx>0 and 2 or 4 end
    return dy>0 and 3 or 1
end

function R.update(s,player,commit,input)
    local gun=NHNative.held(player)
    if not gun or not EntityHasTag(gun,"nh_firearm") then
        staff.reset()
        activeGun,activeRig,heldSince,due=nil,nil,nil,nil
        return
    end
    local mag=EntityGetFirstComponentIncludingDisabled(gun,"VariableStorageComponent","nh_magazine")
    local ability=EntityGetFirstComponentIncludingDisabled(gun,"AbilityComponent")
    if not mag or not ability then return end
    local kind=ComponentGetValue2(mag,"name")
    local def=NHFirearms.items[kind]
    local modes=NHFirearms.modeList(kind)
    local index=NHFirearms.prepareMagazine(gun,mag)
    local points=ComponentGetValue2(mag,"value_int")
    local row=s.gearRig
    local id=row and row.id
    local reserve=row and row.item.reserve or 0
    if activeGun~=gun or activeRig~=id then
        staff.reset()
        activeGun,activeRig,heldSince,due=gun,id,nil,nil
    end
    local frame=GameGetFrameNum()
    local menu,hover
    if not input.enabled then heldSince,due=nil,nil
    else
        if input.pressed then heldSince=frame end
        if heldSince then
            menu=frame-heldSince>=15
            if menu then hover=aimedMode(player) end
            if not input.down then
                local selected=menu and hover or (not menu and index%#modes+1)
                if selected and selected~=index then
                    index=selected
                    ComponentSetValue2(mag,"value_float",index)
                    if points>=modes[index].cost then due=nil end
                end
                menu,heldSince=false,nil
            end
        end
        if points<def.magazine and reserve>0 and not due and not heldSince and (input.reload or points<modes[index].cost) then
            due=frame+def.loadFrames
            local playerX,playerY=EntityGetTransform(player)
            GamePlaySound("data/audio/Desktop/animals.bank","animals/shotgun_cock",playerX,playerY)
        end
    end
    if points>=def.magazine or reserve<=0 then due=nil end
    if due and frame>=due then
        due=nil
        local added=0
        local ok=commit(function(draft)
            local rig=draft.gearRig
            if not rig or rig.id~=id or NHNative.held(player)~=gun then return false,"Inventory slot changed." end
            added=math.min(def.magazine-points,rig.item.reserve)
            if added<=0 then return false,"No reserve." end
            rig.item.reserve=rig.item.reserve-added
            return true
        end)
        if ok then
            points,reserve=points+added,reserve-added
            ComponentSetValue2(mag,"value_int",points)
        end
    end
    local blocked=due~=nil or heldSince~=nil or not input.enabled
    if ComponentGetValue2(mag,"value_bool")~=blocked then ComponentSetValue2(mag,"value_bool",blocked) end
    local charge,cast,mimicTarget
    if kind=="battle_staff" then
        local aiming=input.enabled and not heldSince and not input.pressed
        points,charge,cast,mimicTarget=staff.update(player,gun,mag,index,points,frame,blocked or input.pressed or input.reload,
            aiming and due~=nil,input.canMimic)
    end
    if ComponentGetValue2(ability,"mana")~=points then ComponentSetValue2(ability,"mana",points) end
    return {rounds=points,max=def.magazine,reserve=reserve,modes=modes,index=index,menu=menu,hover=hover,
        loading=due and due-frame,keyName=input.keyName,charge=charge,mimicTarget=mimicTarget},cast
end
return R
