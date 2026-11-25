-- Sample once, before the native shooter consumes ControlsComponent. In
-- particular Fire2 can mirror the primary mouse binding (flask spray).
local M={}

local function freshBinding(controls,action,frame)
    local stamp=ComponentGetValue2(controls,"mButtonFrame"..action)
    return type(stamp)=="number" and stamp>=0 and math.abs(stamp-frame)<=1
end

function M.sample(history,controls,frame)
    local mouseLeft=InputIsMouseButtonDown(1)
    local mouseRight=InputIsMouseButtonDown(2)
    local fire=ComponentGetValue2(controls,"mButtonDownFire")==true
    local throw=ComponentGetValue2(controls,"mButtonDownThrow")==true
    local mouse=mouseLeft or mouseRight
    -- Ignore both a binding that coincides with a mouse press and its tail
    -- when native controls are repopulated after suppression.
    if mouse then history.lastMouseFrame=frame end
    local acceptBinding=not mouse and frame>(history.lastMouseFrame or -10)+1
    local function bound(down,previous,owned,action)
        return down and (owned or (acceptBinding and not previous and freshBinding(controls,action,frame)))
    end
    history.boundLeft=bound(fire,history.fire,history.boundLeft,"Fire")
    history.boundRight=bound(throw,history.throw,history.boundRight,"Throw")
    -- If one mapped button reports both actions, primary owns the press.
    if history.boundLeft and history.boundRight and not history.right then history.boundRight=false end
    history.fire,history.throw=fire,throw
    local left=mouseLeft or history.boundLeft
    local right=mouseRight or history.boundRight
    local sample={left=left,right=right,mouseLeft=mouseLeft,leftPress=left and not history.left,rightPress=right and not history.right,
        heldAtEquip=mouse or fire or throw}
    history.left,history.right=left,right
    return sample
end

return M
