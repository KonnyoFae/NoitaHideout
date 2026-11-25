-- Moal keeps the darkness sprites on the monster and updates their alpha every
-- frame. Filter just its near-range alpha write, leaving NE in control of the
-- sprites' transforms, lifetime and all of the encounter's other behavior.
local path="data/scripts/animals/moal.lua"
local playersDecl="local%s+players%s*=%s*{%s*}"
local spriteRead=[=[EntityGetComponentIncludingDisabled%s*%(%s*child%s*,%s*["']SpriteComponent["']%s*%)]=]
local alphaWrite=[=[ComponentSetValue2%s*%(%s*sprite_component%s*,%s*["']alpha["']%s*,%s*alpha%s*%)]=]
local filtered=[=[do
    if nhMoalSight==nil then
        nhMoalSight=dofile_once("mods/noita_hideout/files/tarot_sight.lua").active(players[1])==true
    end
    local name=nhMoalSight and EntityGetName(child)
    local hidden=name and (name=="darkness" or name=="player_eldritch" or name=="player_dark" or name:match("^player_dark[2-5]$"))
    ComponentSetValue2(sprite_component,"alpha",hidden and 0 or alpha)
end]=]

return function()
    if not ModIsEnabled("new_enemies") or not ModDoesFileExist(path) then return end
    local text=ModTextFileGetContent(path)
    if type(text)~="string" or text:find("nhMoalSight",1,true) then return end
    local declaration,after=text:find(playersDecl)
    if not declaration or text:find(playersDecl,after+1) then return end
    local _,sprites=text:find(spriteRead,after+1)
    if not sprites then return end
    local start,finish=text:find(alphaWrite)
    if not start or start<=sprites or text:find(alphaWrite,finish+1) then return end
    local newline=text:find("\r\n",1,true) and "\r\n" or "\n"
    local replacement=filtered:gsub("\n",newline)
    ModTextFileSetContent(path,text:sub(1,declaration-1).."local nhMoalSight"..newline
        ..text:sub(declaration,start-1)..replacement..text:sub(finish+1))
end
