local root="mods/noita_hideout/files/"
local function vm(path,alive)
    local calls={}
    local env
    local freeze={
        checkTarget=function(entity)
            assert(type(env.item_pickup)=="function","pickup must already be defined before the first update")
            calls[#calls+1]={"check",entity}
        end,
        release=function(entity,pickingUp) calls[#calls+1]={"release",entity,pickingUp} end,
    }
    env=setmetatable({
        GetUpdatedEntityID=function() return 34 end,
        EntityGetIsAlive=function() return alive~=false end,
        dofile_once=function(file) assert(file==root.."stasis.lua");return freeze end,
    },{__index=_G})
    env._G=env
    assert(setfenv(assert(loadfile(root..path)),env))()
    return env,calls
end

-- Model shared-VM loading: only the source entry has been loaded when the
-- engine dispatches item_pickup. Loading both old files first hides this bug.
local env,calls=vm("hourglass_resume.lua")
assert(type(rawget(env,"item_pickup"))=="function" and calls[1][1]=="check")
env.item_pickup(91)
assert(calls[2][1]=="release" and calls[2][2]==91 and calls[2][3]==true)
-- Pickup may be the first message, or the item may already have disappeared.
env,calls=vm("hourglass_resume.lua",false)
assert(#calls==0 and type(rawget(env,"item_pickup"))=="function")
env.item_pickup(92)
assert(calls[1][1]=="release" and calls[1][2]==92 and calls[1][3]==true)
-- Persisted components may still point at the previous pickup-only entry.
env,calls=vm("hourglass_pickup.lua")
assert(#calls==0 and type(rawget(env,"item_pickup"))=="function")
env.item_pickup(93)
assert(calls[1][1]=="release" and calls[1][2]==93 and calls[1][3]==true)
print("Stasis callbacks: source-first and pickup-first shared VM initialization and legacy pickup entry passed.")
