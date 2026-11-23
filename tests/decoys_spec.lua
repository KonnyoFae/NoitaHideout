local root="mods/noita_hideout/files/turrets/"
local entities={
    [1]={x=0,y=0,herd=1,anchor={value_int=0,value_float=0},flight={value_int=0,value_float=0}},
    [2]={x=20,y=0,herd=2}, [3]={x=-30,y=0,herd=2}, [4]={x=2,y=0,herd=1},
    [5]={x=6,y=0,herd=2,charmed=true}, [6]={x=86,y=0,herd=2},
}
for id=2,6 do entities[id].ai={mGreatestPrey=0,mGreatestThreat=0} end
local frame,hits,facing=100,0,1
function GetUpdatedEntityID() return 1 end
function GameGetFrameNum() return frame end
function EntityGetTransform(id) local e=entities[id]; return e.x,e.y,0,facing,1 end
function EntitySetTransform(id,x,y,_,dir) entities[id].x,entities[id].y,facing=x,y,dir end
function EntityGetFirstHitboxCenter(id) return entities[id].x,entities[id].y-6 end
function EntityGetInRadiusWithTag() return {1,2,3,4,5,6} end
function EntityGetFirstComponent(id,kind,tag)
    local e=entities[id]
    if kind=="GenomeDataComponent" then return e end
    if kind=="AnimalAIComponent" then return e.ai end
    if tag=="nh_decoy_anchor" then return e.anchor end
    if tag=="nh_decoy_flight" then return e.flight end
end
EntityGetFirstComponentIncludingDisabled=EntityGetFirstComponent
function ComponentGetValue2(c,key) return c[key] end
function ComponentSetValue2(c,key,v) c[key]=v end
function EntityGetIsAlive(id) return entities[id]~=nil end
function EntityHasTag(id,tag) return id==1 and tag=="nh_decoy" end
function EntityGetHerdRelation(a,b) return entities[a].herd==entities[b].herd and 100 or 0 end
function GameGetGameEffectCount(id) return entities[id].charmed and 1 or 0 end
function RaytracePlatforms(_,_,tx) return tx<=-25 end
function EntityInflictDamage(id,amount,kind,_,_,_,_,who)
    assert(id==2 and who==1 and kind=="DAMAGE_MELEE" and amount==0.16)
    hits=hits+1
end
function GamePlayAnimation() end
local scan=assert(loadfile(root.."decoy_taunt.lua"))
local fly=assert(loadfile(root.."decoy_flight.lua"))
scan()
assert(entities[1].flight.value_int==2 and entities[2].ai.mGreatestPrey==1 and entities[6].ai.mGreatestThreat==1)
for _,id in ipairs({3,4,5}) do assert(entities[id].ai.mGreatestPrey==0) end
for f=100,134,2 do frame=f;fly() end
assert(hits==1 and entities[1].x<15)
entities[2].x=120
scan()
assert(entities[1].flight.value_int==0,"do not pursue enemies outside the anchor radius")
for f=136,250,2 do frame=f;fly();assert(entities[1].x^2+entities[1].y^2<=72^2) end
assert(hits==1 and math.abs(entities[1].x)<=21 and entities[1].y<0)
print("Decoys filter allies, charm and blocked sight, kick once per recovery, and return to their deployment area.")
