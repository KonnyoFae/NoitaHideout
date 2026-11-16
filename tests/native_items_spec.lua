local frame, down, pressed_at = 10, false, -20
local tags = {[123] = {noita_hideout_pouch = true}, [124] = {noita_hideout_dose = true}}
local active, root = 123, 15
local content = ",en,ru,pt-br,es-es,de,fr-fr,it,pl,zh-cn,jp,ko\nbase,Test"
function GameGetFrameNum() return frame end
function EntityGetIsAlive(e) return tags[e] ~= nil end
function EntityGetRootEntity() return root end
function EntityHasTag(e, tag) return tags[e] and tags[e][tag] or false end
function EntityGetFirstComponentIncludingDisabled(_, kind)
    return ({ControlsComponent = 100, Inventory2Component = 101, ItemComponent = 102})[kind]
end
function ComponentGetValue2(_, key)
    if key == "mButtonDownFire" then return down end
    if key == "mButtonFrameFire" then return pressed_at end
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
local cols = {}
for cell in content:match("nh_hideout_pouch,([^\n]+)"):gmatch("[^,]+") do cols[#cols + 1] = cell end
assert(#cols == 11 and cols[1] == "Injector pouch" and cols[9] == "针剂包")
for _,kit in ipairs({{"tactical_medkit","战术医疗包","15%"},{"advanced_medkit","高端医疗包","25%"}}) do
    local name=assert(content:match("\nnh_hideout_"..kit[1]..",([^\n]+)"))
    local desc=assert(content:match("\nnh_hideout_"..kit[1].."_desc,([^\n]+)"))
    assert(name:find(kit[2],1,true) and desc:find(kit[3],1,true) and desc:find("最大生命值",1,true))
    assert(select(2,desc:gsub(",",""))==10)
end
assert(NHNative.kind(NHNative.spawn("pouch",0,0)) == "pouch")
assert(NHNative.kind(NHNative.spawn("dose",0,0)) == "dose")
assert(not NHNative.spawn("other",0,0))
assert(NHNative.held(15) == 123)
root = 77
assert(not NHNative.held(15))

local function poll(is_down, blocked, begins_press)
    frame = frame + 1
    down = is_down
    if begins_press then pressed_at = frame end
    return NHNative.pressed(15, blocked)
end
NHNative.resetInput()
assert(not poll(false, false))
assert(poll(true, false, true))
assert(not poll(true, false))
assert(not poll(true, true))
assert(not poll(false, true)) -- panel temporarily overrides button state
assert(not poll(true, false)) -- still holding the same button after closing
assert(not poll(false, false))
assert(poll(true, false, true))
assert(not poll(true, false))
NHNative.resetInput()
assert(not poll(true, false)) -- don't inject on reload mid-press
assert(not poll(false, false))
assert(poll(true, false, true))
print("Native items: held ownership, single click, held input, UI close, world reset and translations passed.")
