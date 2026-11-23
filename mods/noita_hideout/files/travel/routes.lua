local R={}
local regions={
    ["$biome_coalmine"]={"矿场","Mines"},
    ["$biome_coalmine_alt"]={"坍塌矿场","Collapsed Mines"},
    ["$biome_excavationsite"]={"煤矿矿坑","Coal Pits"},
    ["$biome_snowcave"]={"积雪深渊","Snowy Depths"},
    ["$biome_snowcastle"]={"席西基地","Hiisi Base"},
    ["$biome_rainforest"]={"地下丛林","Underground Jungle"},
    ["$biome_vault"]={"避难所","The Vault"},
    ["$biome_crypt"]={"艺之神殿","Temple of the Art"},
    ["$biome_boss_arena"]={"实验室","The Laboratory"},
}

function R.collect(stations,hx,hy,landmarks)
    local home={kind="home",x=hx,y=hy,index=1}
    local groups={{world=0,routes={home}}}
    local byWorld={[0]=groups[1]}
    local rows={home}
    local function add(row)
        local group=byWorld[row.world]
        if not group then
            group={world=row.world,routes={}}
            byWorld[row.world]=group
            groups[#groups+1]=group
        end
        row.index=#rows+1
        rows[row.index]=row
        group.routes[#group.routes+1]=row
    end
    for _,row in ipairs(landmarks or {}) do add(row) end
    for sx,sy in stations:gmatch("(-?%d+),(-?%d+);") do
        local x,y=tonumber(sx),tonumber(sy)
        -- A biome-map cell covers 512 world pixels. Query the actual neighbors
        -- so a moved or skipped layer (including NG+) names the right exit.
        local below=BiomeMapGetName(x,y+512)
        local above=BiomeMapGetName(x,y-512)
        if BiomeMapGetName(x,y)=="$biome_boss_arena" then below="$biome_boss_arena" end
        add({kind="mountain",x=x,y=y,world=GetParallelWorldPosition(x,y),above=regions[above],below=regions[below]})
    end
    table.sort(groups,function(a,b)
        if math.abs(a.world)==math.abs(b.world) then return a.world>b.world end
        return math.abs(a.world)<math.abs(b.world)
    end)
    for _,group in ipairs(groups) do
        table.sort(group.routes,function(a,b)
            if a.kind~=b.kind then return a.kind=="home" or (a.kind=="landmark" and b.kind=="mountain") end
            if a.kind=="landmark" then return a.x<b.x end
            if a.y~=b.y then return a.y<b.y end
            return a.x<b.x
        end)
    end
    return {rows=rows,groups=groups}
end

function R.label(row,tr)
    if row.kind=="home" then return tr("矿井入口 · 藏身处","Mines entrance · Hideout"),"" end
    if row.kind=="landmark" then return tr(unpack(row.name)),tr("地表藏身处终端","Surface hideout terminal") end
    local below=row.below and tr(unpack(row.below))
    local above=row.above and tr(unpack(row.above))
    if below then
        local detail=above and above~=below and tr("来自","From ")..above or ""
        return tr("%s入口圣山","%s entrance"):format(below),detail
    end
    if above then return tr("%s下方圣山","Below %s"):format(above),"" end
    if row.y<0 then return tr("高空圣山","Sky sanctuary"),"" end
    if row.y<4096 then return tr("浅层圣山","Upper sanctuary"),"" end
    if row.y<8192 then return tr("中层圣山","Mid-depth sanctuary"),"" end
    return tr("深层圣山","Deep sanctuary"),""
end
return R
