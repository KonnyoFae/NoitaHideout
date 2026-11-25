local source = "data/scripts/animals/spawn_worms.lua"
local types = 'local types = { "worm", "worm_big", "worm_tiny" }'
local selection = "local entity = types[rnd]"
local spawn = '\t\tentity_id = EntityLoad( "data/entities/animals/" .. entity .. ".xml", pos_x + Random( -360, 360 ), pos_y - 300 )'

-- The altar crystal summons the ordinary worm templates. Mark the returned
-- entity at this call site so their natural counterparts keep their rewards.
return function()
    local script = ModTextFileGetContent(source)
    if type(script) ~= "string" then return end
    local newline = script:find("\r\n", 1, true) and "\r\n" or "\n"
    local branch = "\tif ( entity ~= nil ) then" .. newline .. spawn .. newline .. "\tend"
    local _, listEnd = script:find(types, 1, true)
    local _, selectionEnd = script:find(selection, (listEnd or 0) + 1, true)
    local first, last = script:find(branch, 1, true)
    if not listEnd or not selectionEnd or not first or selectionEnd >= first
        or script:find(branch, last + 1, true) then return end

    local insertion = last - #"\tend"
    local marker = table.concat({
        '\t\tif entity_id and entity_id ~= 0 and (entity == "worm" or entity == "worm_big" or entity == "worm_tiny") then',
        '\t\t\tEntityAddTag(entity_id, "nh_no_rare_drop")',
        "\t\tend",
    }, newline)
    ModTextFileSetContent(source, script:sub(1, insertion) .. marker .. newline .. script:sub(insertion + 1))
end
