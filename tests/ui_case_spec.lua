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
assert(render(model,31)=="take_pouch")
assert(render(model,32)=="take_dose")
assert(render(model,34)=="place")
model.secure_loot={"Starter wand"}
assert(render(model,33)=="secure_withdraw")
model.pouch_location="bag"
assert(not render(model,31))
assert(not render(model,32))
assert(render(model,11)=="close")
print("HUD field access, protected pouch, valuables and held-item controls passed.")
