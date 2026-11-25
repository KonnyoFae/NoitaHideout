-- New Enemies can leave several generations of its temporary hitbox on an
-- inventory item. Verify the original geometry before relying on Noita's
-- normal card/wand factory to recreate it. Capture never edits the live item.
local H={backup="new_enemies_unseen_effect_old_values_values",cardTemplate="data/entities/misc/custom_cards/action.xml"}
local restoreFile="data/scripts/misc/unseen_restore_script.lua"
local invalid="Could not verify the original hitbox after Unseen."
local helperTags={enabled_in_world=true,enabled_in_hand=true,enabled_in_inventory=true,disabled_visual=true}

function H.restoreScript(c)
    if ComponentGetValue2(c,"script_source_file")~=restoreFile then return false end
    local seen={}
    for tag in (ComponentGetTags(c) or ""):gmatch("[^,]+") do
        assert(helperTags[tag],invalid)
        seen[tag]=true
    end
    for tag in pairs(helperTags) do assert(seen[tag],invalid) end
    local get=ComponentGetValue2
    assert(get(c,"execute_every_n_frame")==300 and not get(c,"execute_on_added") and not get(c,"execute_on_removed")
        and not get(c,"remove_after_executed") and not get(c,"call_init_function") and not get(c,"enable_coroutines")
        and not get(c,"limit_all_callbacks") and get(c,"limit_how_many_times_per_frame")==-1
        and get(c,"limit_to_every_n_frame")==-1 and get(c,"execute_times")==0,invalid)
    for key in pairs(ComponentGetMembers(c) or {}) do
        if key:match("^script_") and key~="script_source_file" then
            local file=ComponentGetValue2(c,key)
            assert(file==nil or file=="",invalid)
        end
    end
    return true
end

local function shape(x1,x2,y1,y2,damage,height)
    if x1==-4 and x2==4 and y1==-height and y2==height and damage==1 then return "original" end
    if x1==0 and x2==0 and y1==-450 and y2==-450 and damage==0 then return "hidden" end
end

local function liveShape(c,height)
    local get=ComponentGetValue2
    return shape(get(c,"aabb_min_x"),get(c,"aabb_max_x"),get(c,"aabb_min_y"),get(c,"aabb_max_y"),get(c,"damage_multiplier"),height)
end

function H.factoryCard(entity)
    local path=EntityGetFilename(entity) or ""
    if path~=H.cardTemplate then
        if not path:match("^data/entities/misc/custom_cards/[%w_]+%.xml$") then return end
        local xml=(ModTextFileGetContent(path) or ""):gsub("<!%-%-.-%-%->","")
        if xml:match('<Base%s+[^>]-file%s*=%s*"([^"]+)"')~="data/entities/base_custom_card.xml" then return end
    end
    local boxes=EntityGetComponentIncludingDisabled(entity,"HitboxComponent") or {}
    if #boxes~=1 then return false end
    local c,get=boxes[1],ComponentGetValue2
    local x,y=get(c,"offset")
    if liveShape(c,3)=="original" and x==0 and y==0 and (ComponentGetTags(c) or "")=="enabled_in_world"
        and get(c,"is_player")==false and get(c,"is_item")==false and get(c,"is_enemy")==true then return path end
end

local function backupShape(c,height)
    local value=ComponentGetValue2(c,"value_string")
    assert(type(value)=="string" and #value<=256 and (ComponentGetTags(c) or "")==""
        and not ComponentGetValue2(c,"value_bool") and (ComponentGetValue2(c,"value_int") or 0)==0
        and (ComponentGetValue2(c,"value_float") or 0)==0,invalid)
    local values,count={},0
    for part in (value..","):gmatch("(.-),") do
        local key,raw=part:match("^([%a_]+):number=([%d.%-]+)$")
        local n=tonumber(raw)
        assert(n and not values[key],invalid)
        values[key],count=n,count+1
    end
    assert(count==5,invalid)
    return assert(shape(values.aabb_min_x,values.aabb_max_x,values.aabb_min_y,values.aabb_max_y,values.damage_multiplier,height),invalid)
end

local function checkInactive(entity)
    -- The effect recurses down from its parent. For a card in a wand the
    -- effect entity can be a child of the wand, the inventory or the player.
    while entity and entity~=0 do
        for _,child in ipairs(EntityGetAllChildren(entity) or {}) do
            for _,c in ipairs(EntityGetComponentIncludingDisabled(child,"GameEffectComponent") or {}) do
                local id=ComponentGetValue2(c,"custom_effect_id")
                assert(not ComponentGetIsEnabled(c) or (id~="NEW_ENEMIES_UNSEEN" and id~="NEW_ENEMIES_SWALLOWED"),
                    "Wait for Unseen or Swallowed to wear off before storing this item.")
            end
        end
        entity=EntityGetParent(entity)
    end
end

function H.check(entity,wand,backups,hasHelper)
    if not backups and not hasHelper
        and not EntityGetFirstComponentIncludingDisabled(entity,"HitboxComponent","temp_hitbox")
        and not EntityGetFirstComponentIncludingDisabled(entity,"HitboxComponent","disabled_visual") then return end
    checkInactive(entity)
    local height=wand and 4 or 3
    local originalBackup,originalCopy,base
    for _,c in ipairs(backups or {}) do
        if backupShape(c,height)=="original" then originalBackup=true end
    end
    for _,c in ipairs(EntityGetComponentIncludingDisabled(entity,"HitboxComponent") or {}) do
        local world,copy
        for tag in (ComponentGetTags(c) or ""):gmatch("[^,]+") do
            if tag=="enabled_in_world" then world=true
            elseif tag=="temp_hitbox" then copy=true
            else assert(tag=="disabled_visual",invalid) end
        end
        local get=ComponentGetValue2
        local x,y=get(c,"offset")
        local geometry=liveShape(c,height)
        assert(world and geometry and x==0 and (y==0 or (not copy and y==450))
            and get(c,"is_player")==false and get(c,"is_item")==false and get(c,"is_enemy")==(not wand),invalid)
        if copy then
            if geometry=="original" then originalCopy=true end
        else
            assert(not base,invalid)
            base=geometry
        end
    end
    assert(base=="original" or (base=="hidden" and originalBackup and originalCopy),invalid)
    return true
end
return H
