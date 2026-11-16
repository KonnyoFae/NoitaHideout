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

function M.get(kind,tier)
    if tier==nil then tier=1 end
    local tiers=M[kind]
    return tiers and tiers[tier]
end

return M
