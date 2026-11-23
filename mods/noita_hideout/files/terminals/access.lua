-- Terminal placement and the controller share proximity results within one update.
if NHTerminalAccess then return NHTerminalAccess end
local A={}
local scope

function A.duringUpdate(update)
    local scratch={}
    return function()
        local outer=scope
        scope=outer and {} or scratch
        scope.player=nil
        local ok,err=pcall(update)
        scope=outer
        if outer then outer.player=nil end
        if not ok then error(err,0) end
    end
end

function A.invalidateAccess()
    if scope then scope.player=nil end
end

function A.access(player,hx,hy,resolve)
    local x,y=EntityGetTransform(player)
    if not scope then return resolve(player,x,y,hx,hy) end
    if player~=scope.player or x~=scope.x or y~=scope.y or hx~=scope.hx or hy~=scope.hy then
        scope.near,scope.station,scope.landmark,scope.remote=resolve(player,x,y,hx,hy)
        scope.player,scope.x,scope.y,scope.hx,scope.hy=player,x,y,hx,hy
    end
    return scope.near,scope.station,scope.landmark,scope.remote
end

NHTerminalAccess=A
return A
