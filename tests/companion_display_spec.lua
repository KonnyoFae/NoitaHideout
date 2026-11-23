local dir="mods/noita_hideout/files/companions/"
local display=assert(loadfile(dir.."display.lua"))
local frame,x,y=0,0,0
local portrait,light,clock={alpha=0},{},{value_string="dryad"}
local child,creates,wx,wy=nil,0,0,0
function GameGetFrameNum() return frame end
function GetUpdatedEntityID() return 2 end
function EntityGetParent(id) assert(id==2); return 1 end
function EntityGetIsAlive() return true end
function EntityGetTransform(id)
    if id==1 then return x,y end
    return x+6,y-13
end
function EntitySetTransform(id,px,py) assert(id==child); wx,wy=px,py end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    if kind=="SpriteComponent" then return id==2 and portrait or light end
    assert(id==2 and tag=="nh_companion_clock")
    return clock
end
function EntityGetAllChildren(id,tag) assert(id==2 and tag=="nh_companion_wisp"); return {child} end
function EntityLoad(path) assert(path==dir.."wisp.xml"); creates=creates+1; return 3 end
function EntityAddChild(id,dot) assert(id==2 and dot==3); child=dot end
function ComponentGetValue2(c,k) return c[k] end
function ComponentSetValue2(c,k,v) c[k]=v end
function EntityRefreshSprite() end
local function step(dx,dy)
    frame,x,y=frame+1,x+(dx or 0),y+(dy or 0)
    display()
    assert(light.alpha+portrait.alpha==1 and light.visible==(light.alpha>0) and portrait.visible==(portrait.alpha>0))
end
step()
for i=1,59 do step(); assert(portrait.alpha==0) end
for i=1,16 do step(); assert(portrait.alpha==i/16) end
-- Idle jitter and loading an already visible companion should keep its portrait.
for i=1,80 do step(i%2==0 and -0.02 or 0.02) end
companionDisplay=nil
step()
assert(portrait.alpha==1 and creates==1)
for i=1,8 do step(12,0); assert(portrait.alpha==1-i/8) end
for i=1,15 do step(40,-20); assert(math.abs(wx-x)<16 and math.abs(wy-y)<20) end
step(-2400,1600)
assert(portrait.alpha==0 and math.abs(wx-x)<16 and math.abs(wy-y)<20)
for i=1,59 do step(); assert(portrait.alpha==0) end
for i=1,5 do step() end
assert(portrait.alpha==5/16)
step(0,2)
assert(portrait.alpha==3/16)
for i=1,59 do step(); if i>=2 then assert(portrait.alpha==0) end end
step()
assert(portrait.alpha==1/16)
for i=1,80 do step(0.03,0) end
assert(portrait.alpha==0 and creates==1)

local file=assert(io.open(dir.."wisp_sprite.xml","rb"))
local atlas=file:read("*a")
file:close()
dofile("mods/noita_hideout/files/companions.lua")
for _,species in ipairs(NHCompanions.order) do
    clock.value_string,companionDisplay=species,nil
    step()
    assert(light.rect_animation==species and light.next_rect_animation==species)
    assert(atlas:find('name="'..species..'"',1,true))
end

-- A pet loaded from the previous XML installs one display script, even when
-- the gameplay callback runs more than once before the display initializes.
local installed,updates=0,0
function dofile_once() end
function EntityGetFirstComponentIncludingDisabled(id,kind,tag)
    assert(id==2 and kind=="LuaComponent" and tag=="nh_companion_display")
    return installed>0 and 5 or nil
end
function EntityAddComponent2(_,kind,c)
    assert(kind=="LuaComponent" and c.execute_every_n_frame==1 and c.script_source_file==dir.."display.lua")
    installed=installed+1
end
NHCompanions.update=function(pet) assert(pet==2); updates=updates+1 end
local tick=assert(loadfile(dir.."tick.lua"))
tick()
tick()
assert(installed==1 and updates==2)
print("Companion display: movement, teleport, idle delay, interrupted fades, save reload and nine wisp colors passed.")
