local width, height = 427, 240
local click, action, argument
local drawn = {}
local frame = 0
local pointer = {x = 0, y = 0}
function GameGetFrameNum() return frame end
function InputIsMouseButtonDown() return pointer.down == true end
function InputIsMouseButtonJustDown() return pointer.pressed == true end
function InputIsMouseButtonJustUp() return pointer.released == true end
function GameGetCameraBounds() return 0, 0, width, height end
function DEBUG_GetMouseWorld() return pointer.x, pointer.y end
function GuiCreate() return {} end
function GuiStartFrame() drawn = {} end
function GuiGetScreenDimensions() return width, height end
function GuiZSet() end
function GuiZSetForNextWidget() end
function GuiColorSetForNextWidget() end
function GuiImageNinePiece() end
function GuiImage() end
function GuiTooltip() end
function GuiGetImageDimensions() return 14, 8 end
function GuiGetTextDimensions(_, value, scale)
    local w = 0
    for letter in value:gmatch("[^\128-\191][\128-\191]*") do
        w = w + (#letter > 1 and 8 or 4)
    end
    return w * (scale or 1), 9 * (scale or 1)
end
function GuiText(_, _, _, value) drawn[value] = true end
function GuiButton(_, id, _, _, value)
    drawn[value] = true
    return id == click
end
function GuiImageButton(_, id) return id == click end

dofile("mods/noita_hideout/files/ui.lua")
local function render(model, widget)
    frame = frame + 1
    click, action, argument = widget, nil, nil
    NHUI.draw(model, function(command, item)
        assert(not action, "multiple actions on a single input")
        action, argument = command, item
    end)
    return action, argument
end

local model={lang="en", open=false, near=false, status=""}
assert(render(model,2)=="open_case")
model.open, model.mode, model.pouch_location, model.case_count=true,"case","safe",2
model.revision,model.carried=4,{{kind="wand",entity=42,name="Wand"},{kind="dose",entity=43,name="Dose"}}
local function point(x,y,event)
    pointer={x=width-187-5+x,y=height-116-5+y,down=event=="press" or event=="hold",
        pressed=event=="press",released=event=="release"}
    return render(model)
end
render(model)
assert(not point(12,77,"press"))
assert(not point(12,77,"release"),"clicking a source must not transfer it")
point(12,77,"press")
assert(not point(12,36,"release"),"wand cannot go in pouch")
point(12,77,"press")
local cmd,id=point(123,36,"release")
assert(cmd=="place" and id==42)
point(35,77,"press")
cmd,id=point(12,36,"release")
assert(cmd=="place" and id==43)
point(12,36,"press")
assert(point(164,78,"release")=="take_pouch")
point(65,36,"press")
assert(point(65,78,"release")=="take_dose")
model.secure_loot,model.secure_kind,model.secure_id={"Starter wand"},"wand",15
point(123,36,"press")
assert(not point(12,77,"release"),"occupied target")
point(123,36,"press")
assert(not point(-20,-10,"release"),"outside cancels")
point(123,36,"press")
cmd,id=point(164,78,"release")
assert(cmd=="secure_withdraw" and id==1)
point(123,36,"press")
model.secure_id=16
assert(not point(164,78,"release"),"stored source was replaced")
point(35,77,"press")
model.carried[2]=nil
assert(not point(12,36,"release"),"carried source was removed")
point(12,36,"press")
model.open=false
render(model)
model.open=true
assert(not point(164,78,"release"),"closing cancels")
assert(render(model,11)=="close")
print("Case HUD: drag both ways, correct entity, incompatible targets, stale items and cancellation passed.")
