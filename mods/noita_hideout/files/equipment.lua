-- Untiered equipment in existing profiles uses the original four-slot model.
local M={pouch={},card_wallet={}}
local function define(kind,tier,capacity,zh,en,seconds,material,amount)
    local filename=tier==1 and kind or kind.."_"..tier
    M[kind][tier]={tier=tier,capacity=capacity,zh=zh,en=en,filename=filename,
        name="$nh_hideout_"..filename,icon="mods/noita_hideout/files/items/"..filename..".png",
        workSeconds=seconds,ingredient=material,amount=amount,containerScrap=tier}
end

define("pouch",1,4,"针剂包","Injector pouch",10,"slime",25)
define("pouch",2,8,"二级注射器盒","Tier II injector case",30,"slime",50)
define("pouch",3,12,"三级注射器盒","Tier III injector case",60,"slime",100)
define("card_wallet",1,4,"卡片夹","Card wallet",8,"fiber",4)
define("card_wallet",2,8,"二级卡片夹","Tier II card wallet",30,"fiber",8)
define("card_wallet",3,12,"三级卡片夹","Tier III card wallet",60,"fiber",12)

M.linkOrder,M.links={},{}
local function defineLink(kind,uses,seconds,zh,en)
    M.linkOrder[#M.linkOrder+1]=kind
    M.links[kind]={kind=kind,uses=uses,seconds=seconds,zh=zh,en=en,name="$nh_hideout_"..kind,
        icon="mods/noita_hideout/files/items/"..kind..".png",
        noteZh=("装备后按住左 Ctrl 呼叫支援，连接需 %d 秒，不耗耐久。野外右键部署 10 分钟的藏身处终端，每次消耗 1 点耐久，共 %d 点。"):format(seconds,uses),
        noteEn=("Equip and hold Left Ctrl for support. The link takes %d s and costs no durability. Right-click to deploy a hideout terminal for 10 minutes using one of %d charges."):format(seconds,uses)}
end
defineLink("remote_terminal",20,5,"一级数据链","Tier I data link")
defineLink("data_link_2",40,3,"二级数据链","Tier II data link")
defineLink("data_link_3",80,1,"三级数据链","Tier III data link")
-- Old profiles and already spawned items can contain either first-generation ID.
M.links.data_link=M.links.remote_terminal

function M.linkUses(kind,n)
    local d=M.links[kind]
    if not d then return end
    if kind=="data_link" and (n==nil or n==-1) then return d.uses end
    if type(n)=="number" and n>=1 and n<=d.uses and n==math.floor(n) then return n end
end

function M.remoteItem(kind)
    local d=M.links[kind or "remote_terminal"]
    return {kind=d.kind,remaining=d.uses,name=d.name,icon=d.icon}
end

function M.get(kind,tier)
    if M.links[kind] and tier==nil then return M.links[kind] end
    if tier==nil then tier=1 end
    local tiers=M[kind]
    return tiers and tiers[tier]
end

return M
