local install = dofile("mods/noita_hideout/files/loot_spawn_sources.lua")
local target = "data/scripts/animals/spawn_worms.lua"
local source, writes
function ModTextFileGetContent(path)
    assert(path == target)
    return source
end
function ModTextFileSetContent(path, text)
    assert(path == target)
    source, writes = text, writes + 1
end

-- Preserve the vanilla selection and spawn branch. A separate spawn in the
-- same script represents an unrelated mod extending the altar effect.
local fixture = [=[local entity_id = GetUpdatedEntityID()
local pos_x, pos_y = EntityGetTransform(entity_id)
local count = Random(1,3)
local types = { "worm", "worm_big", "worm_tiny" }

for i=1,count do
	local rnd = Random( 1, #types )
	local entity = types[rnd]

	if ( entity ~= nil ) then
		entity_id = EntityLoad( "data/entities/animals/" .. entity .. ".xml", pos_x + Random( -360, 360 ), pos_y - 300 )
	end
end
GameScreenshake(30)
]=]
local extra = 'EntityLoad("data/entities/animals/worm_big.xml", 0, 0)\n'
local function run(text, failSecond, extraSpawn)
    local nextChoice, calls, tags, shakes = -1, {}, {}, 0
    local function spawn(path, x, y)
        calls[#calls+1] = {path=path, x=x, y=y}
        return #calls==2 and failSecond and 0 or 100+#calls
    end
    local env = {
        dofile_once = function() end,
        GetUpdatedEntityID = function() return 17 end,
        EntityGetTransform = function() return 45, 800 end,
        SetRandomSeed = function() end,
        GameGetFrameNum = function() return 80 end,
        Random = function(a, b)
            if a == -360 and b == 360 then return 7 end
            assert(a == 1 and b == 3)
            nextChoice = nextChoice + 1
            return nextChoice == 0 and 3 or nextChoice
        end,
        EntityLoad = spawn,
        EntityAddTag = function(id, tag)
            assert(tag == "nh_no_rare_drop" and id > 0 and not tags[id])
            tags[id] = true
        end,
        GameScreenshake = function(force)
            assert(force == 30)
            shakes = shakes + 1
        end,
    }
    local chunk = assert(loadstring(text))
    setfenv(chunk, env)()
    assert(env.EntityLoad == spawn and shakes == 1)
    assert(#calls == (extraSpawn and 4 or 3))
    for i, kind in ipairs({"worm", "worm_big", "worm_tiny"}) do
        assert(calls[i].path == "data/entities/animals/"..kind..".xml")
        assert(calls[i].x == 52 and calls[i].y == 500)
        assert((tags[100+i] == true) == (i ~= 2 or not failSecond))
    end
    assert(not tags[104])
end

local function check(input, extraSpawn)
    source, writes = input, 0
    install()
    assert(writes == 1)
    local patched = source
    install()
    assert(writes == 1 and source == patched)
    run(patched, false, extraSpawn)
    run(patched, true, extraSpawn)
end
check(fixture..extra, true)
check(fixture:gsub("\n", "\r\n"), false)
assert(not source:gsub("\r\n", ""):find("\n",1,true))

for _, input in ipairs({
    "", "EntityLoad('data/entities/animals/worm.xml',0,0)",
    fixture:gsub('local types = { "worm", "worm_big", "worm_tiny" }', 'local types = {"worm", "other", "worm_tiny"}'),
    fixture:gsub('local entity = types%[rnd%]', 'local entity = other[rnd]'),
    fixture:gsub('pos_y %- 300', 'pos_y - 400'), fixture..fixture,
}) do
    source, writes = input, 0
    install()
    assert(source == input and writes == 0)
end
source, writes = nil, 0
install()
assert(source == nil and writes == 0)

local path = os.getenv("NH_TEST_ALTAR_WORMS")
if path and path ~= "" then
    local f = assert(io.open(path, "rb"))
    local original = f:read("*a")
    f:close()
    check(original, false)
end
print("Altar worm source: isolated spawn marker, preserved behavior, repeat install and unknown sources passed.")
