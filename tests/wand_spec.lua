-- Isolated Noita API mock for the two code paths that used to lose a
-- passive wand attachment or regenerate a deck on top of its restored cards.
local ents, comps, next_id, last_load = {}, {}, 0, 0
local frame, missing_action = 500, nil
local function id() next_id = next_id + 1; return next_id end
local function entity(file)
    local e = id()
    ents[e] = {file = file, name = "", components = {}, children = {}}
    return e
end
function EntityAddComponent2(e, t, v)
    local c = id()
    comps[c] = {type = t, data = v or {}}
    table.insert(ents[e].components, c)
    return c
end
function EntityGetAllComponents(e) return ents[e].components end
function EntityGetComponentIncludingDisabled(e, t, tag)
    local result = {}
    for _, c in ipairs(ents[e].components) do
        -- Noita treats an explicit empty tag as a tag filter.
        if comps[c].type == t and (not tag or comps[c].data._tags == tag) then
            result[#result + 1] = c
        end
    end
    return result
end
function EntityGetFirstComponentIncludingDisabled(e, t, tag)
    return EntityGetComponentIncludingDisabled(e, t, tag)[1]
end
function ComponentGetMembers(c) return comps[c].data end
function ComponentGetTypeName(c) return comps[c].type end
function ComponentGetIsEnabled(c) return true end
function ComponentGetValue2(c, field)
    local v = comps[c].data[field]
    if type(v) == "table" then return unpack(v) end
    if v == nil then return 0 end -- scalar defaults in this mock
    return v
end
function ComponentSetValue2(c, k, v, second)
    if second ~= nil then v = {v, second} end
    comps[c].data[k] = v
end
function ComponentObjectGetMembers(c, k) return comps[c].data[k] end
function ComponentObjectGetValue2(c, k, f) return comps[c].data[k][f] end
function ComponentObjectSetValue2(c, k, f, v) comps[c].data[k][f] = v end
local function remove(list, value)
    for i, v in ipairs(list) do if v == value then table.remove(list, i); return end end
end
function EntityRemoveComponent(e, c) remove(ents[e].components, c) end
function EntityGetAllChildren(e) return ents[e].children end
function EntityAddChild(e, child) ents[child].parent = e; table.insert(ents[e].children, child) end
function EntityRemoveFromParent(e) remove(ents[ents[e].parent].children, e); ents[e].parent = nil end
function EntityKill(e) ents[e].dead = true; for _, child in ipairs(ents[e].children) do EntityKill(child) end end
function EntityGetFilename(e) return ents[e].file end
function EntityGetTags(e) return ents[e].tags or "item,wand" end
function EntityAddTag(e, tag) ents[e].tags = EntityGetTags(e) .. "," .. tag end
function EntityRemoveTag() error("Unexpected tag removal") end
function EntityGetName(e) return ents[e].name end
function EntitySetName(e, name) ents[e].name = name end
function EntityRefreshSprite(e, c)
    local sprite = comps[c].data
    if sprite.image_file:lower():match("%.png$") then
        sprite.rect_animation, sprite.next_rect_animation = "", ""
    elseif sprite.rect_animation == "missing_clip" then
        sprite.rect_animation = ""
    end
end
function EntitySetComponentsWithTagEnabled() end
function GameGetFrameNum() return frame end
function CreateItemActionEntity(action)
    if action == missing_action then return 0 end
    local e = entity("")
    EntityAddComponent2(e, "ItemActionComponent", {action_id = action})
    EntityAddComponent2(e, "ItemComponent", {uses_remaining = -1, permanently_attached = false})
    return e
end
function EntityLoad(file)
    local e = entity(file)
    local item = {item_name = "Wand", always_use_item_name_in_ui = false}
    EntityAddComponent2(e, "ItemComponent", item)
    EntityAddComponent2(e, "AbilityComponent", {use_gun_script = true, mNextFrameUsable = 0,
        mReloadNextFrameUsable = 0, gun_config = {deck_capacity = 1},
        gunaction_config = {fire_rate_wait = 17, spread_degrees = -3.5}})
    EntityAddComponent2(e, "SpriteComponent", {_tags = "item",
        image_file = file:match("wand_varpuluuta") and "data/items_gfx/wands/custom/plant_02.png"
            or "data/items_gfx/handgun.xml",
        rect_animation = "JobAbilityMachinegun", next_rect_animation = "default"})
    EntityAddComponent2(e, "HotspotComponent", {_tags = "shoot_pos", offset = {22, 0}})
    EntityAddComponent2(e, "LuaComponent", {execute_on_added = true, remove_after_executed = true,
        script_source_file = "data/scripts/gun/procedural/wand_level_05_better.lua"})
    if file:match("wand_varpuluuta") then
        local cleaner = entity("")
        EntityAddComponent2(cleaner, "CellEaterComponent", {only_stain = true, radius = 20, eat_probability = 10})
        EntityAddComponent2(cleaner, "InheritTransformComponent")
        EntityAddChild(e, cleaner)
        item.item_name = "$item_wand_varpuluuta"
        item.always_use_item_name_in_ui = true
        EntityAddComponent2(e, "LuaComponent", {execute_on_added = true, remove_after_executed = false,
            script_source_file = "data/scripts/gun/procedural/wand_varpuluuta.lua"})
    end
    EntityAddChild(e, CreateItemActionEntity("TEST_GENERATED_CARD"))
    last_load = e
    return e
end

dofile("mods/noita_hideout/files/wand.lua")
local sample = assert(NHWand.sample(25, 10))
EntityAddTag(sample, "test_wand_tag")
local a = EntityGetFirstComponentIncludingDisabled(sample, "AbilityComponent")
ComponentSetValue2(a, "stat_times_player_has_edited", 3)
ComponentSetValue2(a, "stat_times_player_has_shot", 34)
ComponentSetValue2(a, "mNextFrameUsable", frame + 12)
local saved = assert(NHWand.capture(sample))
assert(saved.cleaner.radius == 20 and #saved.cards == 3)
assert(saved.cards[1].id == "SPEED" and saved.cards[1].item.permanently_attached)
assert(saved.cards[3].id == "BOMB" and saved.cards[3].x == 2 and saved.cards[3].item.uses_remaining == 2)
frame = 50 -- restore into a world with a different frame clock
local rebuilt = assert(NHWand.restore(saved, 26, 10))
local rebuilt_ability = EntityGetFirstComponentIncludingDisabled(rebuilt, "AbilityComponent")
assert(ComponentGetValue2(rebuilt_ability, "mNextFrameUsable") == 62)
local rebuilt_data = assert(NHWand.capture(rebuilt))
assert(rebuilt_data.ability.stat_times_player_has_shot == 34 and rebuilt_data.ability.stat_times_player_has_edited == 3)
assert(rebuilt_data.cleaner.radius == 20 and #rebuilt_data.cards == 3)
assert(rebuilt_data.cards[3].item.uses_remaining == 2 and rebuilt_data.gun_config.deck_capacity == 4)
assert(rebuilt_data.gunaction_config.spread_degrees == -3.5)
-- Old records contain clip names inherited from the broom's former XML
-- sprite. A plain PNG has no clips; a failed or successful withdrawal must
-- never rewrite the source record behind the journal's back.
assert(saved.sprite.rect_animation == "" and saved.sprite.next_rect_animation == "")
saved.sprite.rect_animation, saved.sprite.next_rect_animation = "JobAbilityMachinegun", "default"
assert(NHWand.restore(saved, 26, 10))
assert(saved.sprite.rect_animation == "JobAbilityMachinegun" and saved.sprite.next_rect_animation == "default")
-- For an XML sprite, animation mismatches still reject the clone.
saved.sprite.image_file = "data/items_gfx/handgun.xml"
saved.sprite.rect_animation = "missing_clip"
local bad, error_text = NHWand.restore(saved, 26, 10)
assert(not bad and error_text:match("wand%.sprite%.rect_animation") and ents[last_load].dead)
saved.sprite.image_file = "data/items_gfx/wands/custom/plant_02.png"
-- Refuse before deleting an unsupported attachment, and remove an incomplete restore.
local extra = entity("mods/other/attachment.xml")
EntityAddChild(sample, extra)
assert(not NHWand.capture(sample) and not ents[sample].dead and not ents[extra].dead)
missing_action = "BOMB"
assert(not NHWand.restore(saved, 0, 0) and ents[last_load].dead)
for _, child in ipairs(EntityGetAllChildren(last_load)) do assert(ents[child].dead) end
-- Starter wands can report the player's filename because they are inline children.
local starter = EntityLoad("data/entities/player.xml")
local comp = EntityGetFirstComponentIncludingDisabled(starter, "ItemComponent")
ComponentSetValue2(comp, "item_name", "default_gun")
ComponentSetValue2(comp, "collect_nondefault_actions", true)
ComponentSetValue2(comp, "remove_on_death", true)
ComponentSetValue2(EntityGetFirstComponentIncludingDisabled(starter, "AbilityComponent"), "sprite_file", "data/items_gfx/handgun.xml")
EntityRemoveComponent(starter, EntityGetFirstComponentIncludingDisabled(starter, "LuaComponent"))
assert(assert(NHWand.capture(starter)).template == "data/entities/items/starting_wand_rng.xml")

ents[starter].file = "??sav/player.xml"
function ComponentGetTags(c) return comps[c].data._tags end
function EntitySetComponentIsEnabled(_, c, value) comps[c].enabled = value end
function ComponentGetIsEnabled(c) return comps[c].enabled ~= false end
local history = EntityAddComponent2(starter, "VariableStorageComponent", {
    name="$spell_lab_shugged_operation_read_from_wand", _tags="spell_lab_shugged_edit_panel_history",
    value_bool=false, value_int=1, value_float=0, value_string="BOUNCY_ORB:,BOUNCY_ORB:,"
})
EntitySetComponentIsEnabled(starter, history, false)
local record = assert(NHWand.capture(starter))
assert(record.editor[1].values.value_string=="BOUNCY_ORB:,BOUNCY_ORB:," and not record.editor[1].enabled)
assert(NHWand.restore(record, 0, 0))
