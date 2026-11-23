local root="mods/noita_hideout/files/"
local tick=assert(loadfile(root.."turrets/mount.lua"))
local clock,cannon,missile,blocked,tx,ty=0,false,false,false,100,17
local tower,player,enemy,head,round=1,2,3,4,5
local parts,children,shots
local function reset(capacity)
    children,shots={},{}
    parts={[tower]={VariableStorageComponent={value_int=capacity},GenomeDataComponent={herd_id=7}},
        [enemy]={GenomeDataComponent={herd_id=8}},[head]={}}
end
function GetUpdatedEntityID() return tower end
function GameGetFrameNum() return clock end
function EntityGetWithTag() return {player} end
function EntityGetInRadiusWithTag() return {enemy} end
function GameGetGameEffectCount() return 0 end
function EntityGetHerdRelation() return 0 end
function EntityHasTag(id,t) return id==tower and ((cannon and t=="nh_chaingun_turret") or (missile and t=="nh_missile_turret")) end
function EntityGetTransform(id) assert(id==tower); return 10,20 end
function EntityGetFirstHitboxCenter(id) assert(id==enemy); return tx,ty end
function RaytracePlatforms() return blocked end
function EntityGetAllChildren(id,t) assert(id==tower and t=="nh_mount_head"); return children end
function EntityCreateNew() return head end
function EntityAddTag() end
function EntityAddComponent2(id,t,data) parts[id][t]=data; return data end
function EntityAddChild(id,h) assert(id==tower and h==head and not children[1]); children[1]=h end
function EntitySetTransform(id,x,y,angle,_,flip)
    assert(id==head and x==10 and y==17)
    parts[head].angle,parts[head].flip=angle,flip
end
function EntityGetFirstComponent(id,t) return parts[id][t] end
EntityGetFirstComponentIncludingDisabled=EntityGetFirstComponent
function ComponentGetValue2(c,k) return c[k] or 0 end
function ComponentSetValue2(c,k,v,w) c[k]=w and {v,w} or v end
function EntityLoad(path,x,y)
    assert(path==root.."turrets/"..(missile and "missile_round.xml" or (cannon and "chaingun_shell.xml" or "mg_round.xml")))
    parts[round]={ProjectileComponent={speed_min=500},VelocityComponent={}}
    if missile then parts[round].HomingComponent={} end
    return round
end
function GameShootProjectile(id,x,y,ex,ey,r,notify)
    assert(id==tower and r==round and notify==false)
    local angle=parts[head].angle
    assert(math.abs(math.cos(angle)-(ex-x)/100)<0.0001 and math.abs(math.sin(angle)-(ey-y)/100)<0.0001)
    shots[#shots+1]={frame=clock,x=x,y=y}
end
function GamePlayAnimation(id,name,priority,follow)
    assert(id==head and (name=="attack_ranged" or (missile and name=="attack_lower")) and follow=="stand")
    shots[#shots].animation=name
end
function GameEntityPlaySound() end
dofile_once=dofile

reset(6)
for f=0,100,4 do
    clock=f
    if f==4 then tx=-65 end
    tick()
    if f==4 then assert(parts[head].flip==-1 and shots[2].x<10) end
end
assert(#shots==6 and parts[tower].VariableStorageComponent.value_int==0)
for i,f in ipairs({0,4,8,12,16,60}) do assert(shots[i].frame==f) end
assert(parts[round].ProjectileComponent.mWhoShot==player)

-- A wall appearing mid-burst cancels its remaining rounds until the next volley.
reset(8)
clock=0;tick()
blocked=true;clock=4;tick()
blocked=false;clock=8;tick()
assert(#shots==1)
clock=60;tick()
assert(#shots==2)

cannon=true
reset(3)
clock=0;tx=110;ty=-30;tick()
clock=4;tx=-60;tick()
assert(#shots==1 and parts[head].flip==-1 and math.cos(parts[head].angle)<0)
clock=80;tick()
assert(#shots==2 and shots[2].x<10)
clock=160;tx=16;ty=17;tick()
assert(#shots==3 and shots[3].x<tx and parts[tower].VariableStorageComponent.value_int==0)

cannon,missile=false,true
for _,side in ipairs({-1,1}) do
    reset(3)
    tx,ty=10+side*200,17
    for frame=0,160,4 do clock=frame; tick() end
    assert(#shots==3 and shots[1].frame==0 and shots[2].frame==20 and shots[3].frame==120)
    assert(shots[1].animation=="attack_ranged" and shots[2].animation=="attack_lower")
    for i,s in ipairs(shots) do
        assert(math.abs(s.x-(10+side*10))<0.001 and math.abs(s.y-(i==2 and 17 or 4))<0.001)
    end
    assert(parts[round].HomingComponent.predefined_target==enemy and parts[tower].VariableStorageComponent.value_int==0)
end
print("Fixed mount facing, muzzle direction, close targets, burst timing, cover and ammunition passed")
