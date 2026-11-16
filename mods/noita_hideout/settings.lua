dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "noita_hideout"
mod_settings_version = 1
mod_settings = {
    {
        id = "test_tools",
        ui_name = "测试物资与模拟通关 / Playtest tools",
        ui_description = "在出生点生成样品、重发针剂包或模拟本局唯一一次通关奖励。",
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
