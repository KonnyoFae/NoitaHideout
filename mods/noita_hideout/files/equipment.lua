-- Untiered equipment in existing profiles uses the original four-slot model.
local M={pouch={},card_wallet={}}
local function define(kind,tier,capacity,zh,en,seconds,material,amount)
    local filename=tier==1 and kind or kind.."_"..tier
    M[kind][tier]={tier=tier,capacity=capacity,zh=zh,en=en,filename=filename,
        name="$nh_hideout_"..filename,icon="mods/noita_hideout/files/items/"..filename..".png",
        workSeconds=seconds,ingredient=material,amount=amount,emptyContainers=tier}
end

define("pouch",1,4,"针剂包","Injector pouch",10,"slime",25)
define("pouch",2,8,"二级注射器盒","Tier II injector case",30,"slime",50)
define("pouch",3,12,"三级注射器盒","Tier III injector case",60,"slime",100)
define("card_wallet",1,4,"卡片夹","Card wallet",8,"fiber",4)
define("card_wallet",2,8,"二级卡片夹","Tier II card wallet",30,"fiber",8)
define("card_wallet",3,12,"三级卡片夹","Tier III card wallet",60,"fiber",12)

M.remoteTerminal={kind="remote_terminal",zh="远程藏身处终端",en="Remote hideout terminal",uses=20,
    name="$nh_hideout_remote_terminal",icon="mods/noita_hideout/files/items/remote_terminal.png",
    noteZh="野外右键连接，打开物品栏存取。满耐久 20 点，每次连接消耗 1 点，关闭物品栏时断开。",
    noteEn="Right-click in the field to connect. Open inventory to transfer items. Each connection uses one of 20 charges and ends when inventory closes."}

function M.validRemoteUses(n)
    return type(n)=="number" and n>=1 and n<=M.remoteTerminal.uses and n==math.floor(n)
end

function M.remoteItem()
    local d=M.remoteTerminal
    return {kind=d.kind,remaining=d.uses,name=d.name,icon=d.icon}
end

function M.get(kind,tier)
    if kind=="remote_terminal" and tier==nil then return M.remoteTerminal end
    if tier==nil then tier=1 end
    local tiers=M[kind]
    return tiers and tiers[tier]
end

return M
