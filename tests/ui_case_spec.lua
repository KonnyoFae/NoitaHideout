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

local function mouse(model, x, y, event, widget)
    local s = math.min(1, (width - 10) / 314, (height - 10) / 196)
    pointer = {
        x = math.floor((width - 314*s) / 2) + x*s,
        y = math.floor((height - 196*s) / 2) + y*s,
        down = event == "press" or event == "hold",
        pressed = event == "press", released = event == "release",
    }
    return render(model, widget)
end

for i, lang in ipairs({"en", "zh"}) do
    pointer = {x = 0, y = 0}
    width, height = i == 1 and 427 or 321, i == 1 and 240 or 180
    local m = {open = true, mode = "home", lang = lang, near = true, loot = {},
        case_count = 2, pouch_location = "safe", secure_loot = {}, carried = {
            {kind = "dose", entity = 11, name = "Stimulant"},
            {kind = "wand", entity = 12, name = "Wand"},
            {kind = "potion", entity = 13, name = "Flask"},
            {kind = "potion", entity = 14, name = "Flask"},
            {kind = "dose", entity = 15, name = "Stimulant"},
        }}
    assert(render(m, 47) == "recall_case")
    assert(not render(m, 101), "stash does not expose portable contents")
    m.mode = "case"
    assert(not render(m, 47), "portable case must not access home actions")
    assert(render(m, 101) == "take_dose")
    assert(render(m, 102) == "take_dose")
    assert(render(m, 31) == "move")
    local act, ent = render(m, 125)
    assert(act == "place" and ent == 11)
    act, ent = render(m, 130)
    assert(act == "place" and ent == 12)
    render(m, 146)
    act, ent = render(m, 126)
    assert(act == "place" and ent == 15, "page uses current entity ID")
    render(m, 145)
    m.secure_loot[1], m.secure_kind = "Broom", "wand"
    act, ent = render(m, 112)
    assert(act == "secure_withdraw" and ent == 1)
    assert(not render(m, 130), "occupied valuable slot cannot accept another wand")
    assert(render(m, 126) == "place", "occupied valuable slot does not block pouch")
    m.pouch_location, m.case_count = "lost", 0
    assert(not render(m, 102))
    assert(not render(m, 126))
    assert(not render(m, 31))
    m.pouch_location, m.case_count = "safe", 1
    m.secure_loot, m.secure_kind = {}, nil
    -- Item widgets can click on mouse-down in Noita. Waiting for release
    -- lets the same button support click-transfer and drop-at-destination.
    assert(not mouse(m, 175, 52, "press", 125))
    assert(not mouse(m, 83, 52, "hold"))
    act, ent = mouse(m, 22, 52, "release", 101)
    assert(act == "place" and ent == 11)
    assert(not mouse(m, 22, 52, "idle", 101), "ignore delayed native click")
    assert(not mouse(m, 175, 74, "press", 129))
    assert(not mouse(m, 22, 52, "release", 101), "wand cannot drop in the pouch")
    assert(not mouse(m, 175, 74, "press", 129))
    act, ent = mouse(m, 22, 118, "release", 112)
    assert(act == "place" and ent == 12)
    assert(not mouse(m, 22, 52, "press", 101))
    assert(mouse(m, 175, 108, "release") == "take_dose")
    m.secure_loot[1], m.secure_kind = "Broom", "wand"
    assert(not mouse(m, 22, 118, "press", 111))
    act, ent = mouse(m, 170, 105, "release")
    assert(act == "secure_withdraw" and ent == 1)
    assert(not mouse(m, 22, 118, "press", 111))
    assert(not mouse(m, 22, 170, "release"), "outside drop cancels")
    assert(not mouse(m, 22, 52, "press", 101))
    assert(mouse(m, 23, 53, "release", 101) == "take_dose", "single click issues one dose")
    assert(not mouse(m, 22, 52, "press", 101))
    m.open = false
    mouse(m, 22, 52, "hold")
    m.open = true
    assert(not mouse(m, 175, 52, "release"), "closing the panel cancels the drag")
    m.open, m.near, m.ground_case = false, false, true
    render(m)
    assert(drawn[i == 1 and "[G] Open nearby case" or "[G] 打开地上的安全箱"])
end
print("Case HUD: clicks, two-way drag, cancellation, protected slots, paging and field access passed.")
