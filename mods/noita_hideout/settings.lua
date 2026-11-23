dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "noita_hideout"
mod_settings_version = 1
mod_settings = {
    {
        id = "return_key",
        ui_name = "终端返航（长按） · Recall (hold)",
        value_default = "10",
        values = {{"10","G"},{"11","H"},{"13","J"}},
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
    {
        id = "ammo_key",
        ui_name = "开火模式（点按/长按） / Fire modes (tap/hold)",
        value_default = "5",
        values = {{"5","B"},{"25","V"},{"27","X"}},
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
    {
        id = "test_tools",
        ui_name = "测试物资 / Test supplies",
        ui_description = "在出生点或圣山存取点领取召唤卡、空卡片夹、测试针剂包或魔杖与混合瓶。",
        value_default = true,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
}

function ModSettingsUpdate(init_scope)
    mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
    return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
    mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
