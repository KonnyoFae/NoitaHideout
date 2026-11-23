local root="mods/noita_hideout/files/"
dofile(root.."store.lua")
dofile(root.."potion.lua")
local support=dofile(root.."fire_support.lua")
local state={levels={resupply=2},gearLink={id=7,item={kind="data_link_3",remaining=2}},resources={supply_logistics=5,essence_displacement=100}}
local frame,ctrl,fresh,ground=100,false,false,true
local controls,entities={},{}
local nextId,commits,kicks=100,0,0
local packAttempts,rejectPack,rejectCommit=0,nil,false
local errorText
function GameGetFrameNum() return frame end
local playerX,playerY=40,10
function EntityGetTransform(id) if id==1 then return playerX,playerY end end
function EntityGetFirstComponentIncludingDisabled() return controls end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function InputIsKeyDown(k) return k==224 and ctrl end
function InputIsKeyJustDown(k) return k==224 and fresh end
function InputIsMouseButtonDown() return false end
function DoesWorldExistAt() return true end
function RaytracePlatforms(x,y,tx,ty)
    if x==tx and ground then
        if y<=20 and ty>=20 then return true,x,20 end
        if y>=-16 and ty<=-16 then return true,x,-16 end
    end
    return false
end
function EntityLoad(path,x,y)
    if path:find("_pack.xml",1,true) then
        packAttempts=packAttempts+1
        if packAttempts==rejectPack then return 0 end
    end
    nextId=nextId+1
    entities[nextId]={path=path,x=x,y=y}
    return nextId
end
function EntitySetTransform(id,x,y) entities[id].x,entities[id].y=x,y end
function EntityKill(id) entities[id]=nil end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityHasTag(id,tag) return entities[id] and tag=="nh_supply_pod" and entities[id].path==root.."supply_pod.xml" end
function EntityGetRootEntity(id) return id end
function PhysicsBodyIDGetFromEntity(id) return {id} end
function PhysicsApplyForce(id,x,y)
    assert(entities[id] and x~=0 and y<0 and not entities[id].ejected)
    entities[id].ejected=true
    kicks=kicks+1
end
local function tick(key)
    frame=frame+1
    for _,k in ipairs({"Up","Down","Left","Right"}) do controls["mButtonDown"..k]=k==key end
    support.input(state,1,false)
    support.finishInput()
    fresh=false
    support.update(state,1,function(edit)
        if rejectCommit then return false end
        assert(edit(state))
        commits=commits+1
        return true
    end,function(msg) errorText=msg end)
    return support.view(state,1)
end
local function selectPack()
    ctrl,fresh=true,true
    assert(tick().menu.category==2)
    assert(tick("Left").menu.category==1)
    assert(tick("Down").menu.level==2)
    return tick("Right").menu
end
local function launch()
    assert(selectPack().level==3)
    local v=tick("Right")
    assert(v.menu.level==3 and v.menu.project==1 and v.payment.resource=="supply_logistics")
    assert(v.payment.cost==5 and v.payment.stock==(state.resources.supply_logistics or 0))
    tick()
    local call=tick("Right").call
    assert(call.project=="resupply" and not call.targeted and call.phase=="connecting" and call.connectedAt==frame+60)
    ctrl=false
    frame=call.connectedAt-2
    assert(tick().call.phase=="connecting" and not next(entities))
    return tick()
end
local function land()
    for i=1,100 do if not tick() then return end end
    error("pod never landed")
end
do
    local cabin=dofile(root.."travel/cabin.lua")
    local pod=launch().call.pod
    assert(entities[pod])
    playerX,playerY=cabin.point(cabin.infirmary)
    assert(not tick() and not entities[pod] and commits==0 and state.resources.supply_logistics==5)
    playerX,playerY=40,10
end
-- A locked weapon remains browsable, and unlocks at its advertised station tier.
for _,weapon in ipairs({{"heavy_plasma",2,12},{"bfg",3,30}}) do
    for tier=weapon[2]-1,weapon[2] do
        state.resources.supply_logistics=weapon[3]
        state.levels.resupply=tier
        selectPack()
        local view=tick()
        while view.projects[view.menu.project]~=weapon[1] do
            assert(view.menu.project<#view.projects)
            view=tick("Down")
            tick()
        end
        assert(view.payment.cost==weapon[3])
        if tier<weapon[2] then
            assert(view.projectStatus=="need_station_"..weapon[2] and tick("Right").menu.level==2)
        else
            assert(not view.projectStatus and tick("Right").menu.level==3)
        end
        ctrl=false
        assert(not tick())
    end
end
state.levels.resupply=2
state.resources.supply_logistics=4
assert(selectPack().level==2 and tick().projectStatus=="insufficient_packs" and commits==0 and not next(entities))
assert(state.resources.essence_displacement==100 and state.resources.supply_logistics==4)
state.resources.supply_logistics=5
state.levels.resupply=0
assert(selectPack().level==2)
ctrl=false; assert(not tick())
state.levels.resupply=2
assert(selectPack().level==3 and tick("Up").menu.level==3 and tick("Left").menu.level==2)
ctrl=false; assert(not tick())
assert(launch().call.phase=="descending")
state.resources.supply_logistics=4
assert(not tick() and errorText=="Not enough supply logistics packs." and not next(entities) and commits==0)
state.resources.supply_logistics=5
ground=false; assert(not launch() and errorText:find("landing") and commits==0)
ground=true
for _,failure in ipairs({"third pack","commit","success"}) do
    packAttempts=0
    rejectPack=failure=="third pack" and 3 or nil
    rejectCommit=failure=="commit"
    local call=launch().call
    assert(call.phase=="descending" and entities[call.pod].x==40 and entities[call.pod].y<10)
    assert(not call.beam and packAttempts==0 and commits==0)
    land()
    if failure~="success" then assert(not next(entities) and state.resources.supply_logistics==5 and commits==0) end
end
tick(); tick()
assert(commits==1 and kicks==4 and not state.resources.supply_logistics and state.resources.essence_displacement==100 and state.gearLink.item.remaining==2)
local packs,flashes=0,0
for _,e in pairs(entities) do
    if e.path==root.."pod_open_fx.xml" then assert(e.x==40 and e.y==12); flashes=flashes+1
    else assert(e.ejected and e.path==root.."items/improved_supply_pack.xml"); packs=packs+1 end
end
assert(packs==4 and flashes==1)
do
    local supply=dofile(root.."resupply.lua")
    for _,kind in ipairs({"heavy_mg","auto_grenade","heavy_plasma","missile_launcher","railgun","bfg"}) do
        local order={x=40,y=10,weapon=kind}
        assert(not supply.deliver(order,function() return false end) and not entities[nextId])
        assert(supply.deliver(order,function() return true end) and entities[nextId].path==root.."items/"..kind..".xml")
        if kind=="railgun" then
            local file=assert(io.open(entities[nextId].path))
            local rounds=file:read("*a"):match('<ItemComponent[^>]-uses_remaining="(%d+)"')
            file:close()
            assert(tonumber(rounds)==20)
        end
    end
end
for station,essence in pairs({resupply="essence_healing",support="essence_high_energy",reinforcement="essence_creation",intel="essence_force"}) do
    local build={levels={},resources={},materials={},warehouse={}}
    for level=0,2 do
        local cost={nh_philosopher_stone=level+1,arcane_scrap=({1,5,15})[level+1],container_scrap=5,[essence]=(level+1)*100}
        for key,n in pairs(cost) do build.resources[key]=n end
        build.resources.container_scrap=4
        assert(not NHStore.buyUpgrade(build,{id=station,level=level}) and build.resources[essence]==cost[essence])
        build.resources.container_scrap=5
        assert(NHStore.buyUpgrade(build,{id=station,level=level}) and build.levels[station]==level+1 and not next(build.resources))
    end
end
print("Resupply menu, cave descent, four packs, failed delivery rollback and single landing payment passed.")

do
    support.reset()
    state.levels={intel=1}
    local scanCount,px,py=0,40,10
    function EntityGetTransform() return px,py end
    function EntityGetFirstComponentIncludingDisabled(id,kind)
        if id==1 and kind=="ControlsComponent" then return controls end
        if entities[id] and kind=="MagicXRayComponent" then return 999 end
    end
    local failScan=false
    function EntityLoad(path,x,y)
        assert(path==root.."recon_scan.xml" and x==px and y==py)
        if failScan then return 0 end
        nextId=nextId+1
        scanCount=scanCount+1
        entities[nextId]={path=path}
        return nextId
    end
    local function selectRecon()
        ctrl,fresh=true,true
        tick(); tick("Right"); tick(); tick("Right")
        local v=tick("Down")
        assert(v.menu.category==4 and v.projects[v.menu.project]=="recon" and v.payment.cost==1 and v.payment.resource=="intel_logistics")
        return tick("Right")
    end
    assert(selectRecon().projectStatus=="insufficient_packs")
    for _,outcome in ipairs({"spawn failure","payment failure","success"}) do
        state.resources.intel_logistics=1
        assert(selectRecon().menu.level==3)
        tick(); local active=tick("Right").call
        assert(active.project=="recon" and not active.targeted and state.resources.intel_logistics==1)
        ctrl=false
        frame=active.connectedAt-2
        assert(tick().call.phase=="connecting")
        px,py=px+19,py-31
        failScan,rejectCommit=outcome=="spawn failure",outcome=="payment failure"
        assert(not tick() and not tick())
        if outcome=="spawn failure" then assert(errorText=="Recon scan failed." and scanCount==0)
        elseif outcome=="payment failure" then assert(scanCount==1 and not entities[nextId])
        else assert(scanCount==2 and entities[nextId]) end
        assert((state.resources.intel_logistics or 0)==(outcome=="success" and 0 or 1))
        assert(state.gearLink.item.remaining==2)
    end
end
print("Recon: data-link-only access, live player position, vanilla scan and single successful payment passed.")

do
    state.levels.intel=3
    local attached,permanent
    function EntityGetComponent(_,_,tag) return tag=="perk_component" and permanent and {permanent} or {} end
    function EntityGetAllChildren(_,tag) return tag=="nh_enemy_radar" and attached and {attached} or {} end
    function EntityLoad(path,x,y)
        assert(path==root.."enemy_radar.xml")
        nextId=nextId+1
        entities[nextId]={path=path}
        return nextId
    end
    function EntityAddChild(player,id) assert(player==1); attached=id end
    local function selectRadar()
        ctrl,fresh=true,true
        tick(); tick("Right"); tick(); tick("Right"); tick("Down"); tick(); tick("Down"); tick()
        return tick("Down")
    end
    state.resources.intel_logistics=12
    permanent={script_source_file="data/scripts/perks/radar.lua"}
    assert(selectRadar().projectStatus=="radar_active" and tick("Right").menu.level==2)
    ctrl=false; tick(); permanent=nil
    assert(not selectRadar().projectStatus and tick("Right").menu.level==3)
    tick(); local call=tick("Right").call
    ctrl=false; frame=call.connectedAt; tick()
    assert(attached and state.resources.intel_logistics==6)
    assert(selectRadar().projectStatus=="radar_active" and tick("Right").menu.level==2)
    ctrl=false; tick(); EntityKill(attached); attached=nil
    assert(not selectRadar().projectStatus)
    -- Switch from the enemy radar to its separate site-locator menu entry.
    local globals={}
    function GlobalsGetValue(k,d) return globals[k] or d end
    function GlobalsSetValue(k,v) globals[k]=v end
    local notice
    function GameTextGetTranslatedOrNot(k) return k end
    function GamePrint(s) notice=s end
    permanent={script_source_file="data/scripts/perks/radar_item.lua"}
    state.resources.intel_logistics=30
    local function siteMenu()
        local view
        for i=1,3 do tick(); view=tick("Down") end
        assert(view.projects[view.menu.project]=="site_radar" and view.payment.cost==15)
        return view
    end
    for attempt=1,2 do
        if attempt==2 then selectRadar(); globals["cycle_storm.sites.ship_locations"]="40,10,2" end
        assert(not siteMenu().projectStatus)
        tick("Right"); tick()
        local order=tick("Right").call
        ctrl=false; frame=order.connectedAt; tick()
        if attempt==1 then assert(notice=="$nh_storm_scan_empty" and state.resources.intel_logistics==30) end
    end
    assert(state.resources.intel_logistics==15 and globals["cycle_storm.sites.scan_until"])
    selectRadar(); assert(siteMenu().projectStatus=="radar_active")
end
