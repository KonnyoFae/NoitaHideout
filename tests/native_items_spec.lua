local frame=10
local controls={}
local tags = {[123] = {noita_hideout_pouch = true}, [124] = {noita_hideout_dose = true}, [125]={wand=true}}
local active, root = 123, 15
local content = ",en,ru,pt-br,es-es,de,fr-fr,it,pl,zh-cn,jp,ko\nbase,Test"
function GameGetFrameNum() return frame end
function EntityGetIsAlive(e) return tags[e] ~= nil end
function EntityGetRootEntity() return root end
function EntityHasTag(e, tag) return tags[e] and tags[e][tag] or false end
function EntityGetFirstComponentIncludingDisabled(_, kind)
    return ({ControlsComponent = 100, Inventory2Component = 101, ItemComponent = 102})[kind]
end
function ComponentGetValue2(c,key)
    if c==100 then return controls[key] end
    if key == "mActiveItem" then return active end
end
function ModTextFileGetContent() return content end
function ModTextFileSetContent(_, value) content = value end
function EntityLoad(path) return path:match("/pouch%.xml$") and 123 or 124 end
dofile("mods/noita_hideout/files/native_items.lua")

NHNative.registerTranslations()
local first_registration = content
NHNative.registerTranslations()
assert(content == first_registration)
assert(content:find("\nnh_hideout_locale,en,en,en,en,en,en,en,en,zh,en,en,\n",1,true))
for row in content:gmatch("\n(nh_[^\r\n]+)") do
    assert(row:sub(-1)==",", "Missing final CSV delimiter for "..row:match("^[^,]+"))
end
for _,sample in ipairs({
    {"zh","完全汉化","zh"}, {"zh","任意语言名","zh"}, {"en","English","en"},
    {"","完全汉化","zh"}, {"$nh_hideout_locale","简体中文","zh"}, {"","日本語","en"}
}) do
    function GameTextGet(key) return key=="$nh_hideout_locale" and sample[1] or sample[2] end
    assert(NHNative.language()==sample[3])
end
local firearms=dofile("mods/noita_hideout/files/firearms.lua")
for _,kind in ipairs({"scatter_revolver","marksman_rifle"}) do
    local gun=firearms.items[kind]
    local en='"'..gun.noteEn..'"'
    local expected=string.rep(en..",",8)..gun.noteZh..","..en..","..en
    assert(content:find("\nnh_hideout_"..kind.."_desc,"..expected..",\n",1,true))
end
local cols = {}
for cell in content:match("nh_hideout_pouch,([^\n]+)"):gmatch("[^,]+") do cols[#cols + 1] = cell end
assert(#cols == 11 and cols[1] == "Injector pouch" and cols[9] == "针剂包")
for _,kind in ipairs({"pouch","card_wallet","remote_terminal"}) do
    local row=assert(content:match("\nnh_hideout_"..kind.."_desc,([^\n]+)"))
    assert(row:find("Right-click",1,true) and row:find("右键",1,true))
end
for _,kit in ipairs({{"bandage","绷带","5%"},{"medkit","小医疗包","15%"},{"tactical_medkit","战术医疗包","25%"},{"advanced_medkit","高端医疗包","40%"}}) do
    local name=assert(content:match("\nnh_hideout_"..kit[1]..",([^\n]+)"))
    local desc=assert(content:match("\nnh_hideout_"..kit[1].."_desc,([^\n]+)"))
    assert(name:find(kit[2],1,true) and desc:find(kit[3],1,true) and desc:find("最大生命值",1,true))
    assert(select(2,desc:gsub(",",""))==11)
end
local throwables=dofile("mods/noita_hideout/files/throwables.lua")
for _,id in ipairs(throwables.order) do
    local item=throwables.types[id]
    for _,row in ipairs({{id,item.zh,item.en},{id.."_desc",item.noteZh,item.noteEn}}) do
        local translated=assert(content:match("\nnh_hideout_"..row[1]..",([^\n]+)"))
        local columns={}
        for cell in translated:gmatch("[^,]+") do columns[#columns+1]=cell end
        assert(#columns==11 and columns[1]==row[3] and columns[9]==row[2])
    end
end
assert(NHNative.kind(NHNative.spawn("pouch",0,0)) == "pouch")
assert(NHNative.kind(NHNative.spawn("dose",0,0)) == "dose")
assert(not NHNative.spawn("other",0,0))
assert(NHNative.held(15) == 123)
root = 77
assert(not NHNative.held(15))

NHMedkits=dofile("mods/noita_hideout/files/medkits.lua")
NHSurgeryKits=dofile("mods/noita_hideout/files/surgery_kits.lua")
NHThrowables=throwables
NHInventoryUse=dofile("mods/noita_hideout/files/inventory_use.lua")
NHTransfers={item_kind=function(e) return tags[e].wand and "wand" end}
root=15
local mouseLeft,mouseRight,boundThrow=false,false,false
function ComponentSetValue2(c,key,value) assert(c==100);controls[key]=value end
function InputIsMouseButtonDown(button) return button==1 and mouseLeft or button==2 and mouseRight end
local function poll(menu,target,left,right,pad,fireAlsoBoundToRight)
    frame=frame+1
    local throw=right or pad or false
    if throw and not boundThrow then controls.mButtonFrameThrow=frame end
    mouseLeft,mouseRight,boundThrow=left or false,right or false,throw
    controls.mButtonDownFire=mouseLeft or (mouseRight and fireAlsoBoundToRight) or false
    controls.mButtonDownLeftClick=mouseLeft
    controls.mButtonDownThrow,controls.mButtonDownRightClick=throw,mouseRight
    controls.mButtonDownFire2=right or false
    return NHNative.prepareRightUse(15,menu,target)
end
NHNative.resetInput()
active=123
assert(not poll(false))
assert(not poll(false,nil,true) and not controls.mButtonDownFire)
assert(not poll(false,nil,true) and not controls.mButtonDownFire and controls.mButtonDownDelayLineFire==0)
active=125 -- Selecting a wand while still holding left must not fire it.
assert(not poll(false,nil,true) and not controls.mButtonDownFire)
assert(not poll(false) and not poll(false,nil,true) and controls.mButtonDownFire)
assert(not poll(false))
assert(not poll(false,nil,false,true) and controls.mButtonDownThrow and controls.mButtonDownFire2)
assert(not poll(false))
active=124
assert(poll(false,nil,false,true)==124 and not controls.mButtonDownThrow and not controls.mButtonDownRightClick)
active=125 -- Last charge spent, wand selected while right is still held.
assert(not poll(false,nil,false,true,false,true) and not controls.mButtonDownFire and not controls.mButtonDownThrow)
assert(not poll(false))
local slot={kind="dose",entity=124,parent=77}
assert(not poll(true,nil,false,true) and not controls.mButtonDownThrow) -- A fresh inventory has no hitboxes yet.
assert(not poll(true,slot,false,true))
assert(not poll(true))
assert(not poll(true,{kind="wand"},false,true) and controls.mButtonDownThrow)
assert(not poll(true,slot,false,true)) -- Moving over a slot mid-press isn't a click.
assert(not poll(true))
assert(poll(true,slot,false,true)==slot and not controls.mButtonDownFire2)
active=123
assert(not poll(false,nil,false,true) and not controls.mButtonDownThrow) -- Closing with the same click.
assert(not poll(false))
assert(poll(false,nil,false,false,true)==123 and not controls.mButtonDownThrow)
assert(not poll(false,nil,false,false,true)) -- Bound gamepad Throw, held.
assert(not poll(false))
assert(poll(false,nil,false,true)==123)
assert(not poll(false,nil,false,false,true)) -- Native Throw lags behind mouse release.
assert(poll(false,nil,false,true)==123)
assert(not poll(false))
NHNative.resetInput()
assert(not poll(false,nil,false,true) and not controls.mButtonDownThrow) -- Reload mid-press.
assert(not poll(false) and poll(false,nil,false,true)==123)
print("Native items: owned right clicks, protected left holds, UI hit targets, controller input, reload and translations passed.")

local owner,quick,entity=15,33,124
local parent,throwing,occupied=quick,entity,false
function EntityGetParent(id) assert(id==entity);return parent end
function EntityGetName(id) return id==quick and "inventory_quick" or "" end
function EntityGetRootEntity(id) return parent==quick and owner or parent==0 and id or parent end
function ComponentGetValue2(c,key)
    if key=="inventory_slot" then return 2,0 end
    if key=="mThrowItem" then assert(c==101);return throwing end
end
function ComponentSetValue2(c,key,value) assert(c==101 and key=="mThrowItem");throwing=value end
local slot=assert(NHNative.heldUseSlot(owner,entity))
assert(slot.owner==owner and slot.entity==entity and slot.parent==quick and slot.xslot==2 and slot.yslot==0)
local attempts=0
local function place(p,id,original)
    assert(p==owner and id==entity and original==slot);attempts=attempts+1
    if occupied then return false end
    parent=quick
    return true
end
assert(not NHNative.recoverUseSlot(owner,slot,place) and throwing==0 and attempts==0)
throwing,parent=entity,0
assert(NHNative.recoverUseSlot(owner,slot,place) and throwing==0 and parent==quick and attempts==1)
occupied,throwing,parent=true,125,0
assert(not NHNative.recoverUseSlot(owner,slot,place) and throwing==125 and parent==0 and attempts==2)
parent=88
assert(not NHNative.recoverUseSlot(owner,slot,place) and parent==88 and attempts==2)
assert(not NHNative.recoverUseSlot(99,slot,place) and throwing==125 and attempts==2)
print("Native items: only the right-clicked item can be restored to its original empty slot.")
