local NetCmdController = require "Framework.Common.NetCmdController"
local ShopSystem = BaseClass("ShopSystem", NetCmdController)
local MessageManager = require "Framework.Updater.MessageManager"
local Client = require "Network.Client"
local d_shop = require("ClientDatas.d_shop")
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local d_bag_item = require("ClientDatas.d_bag_item")
local BackpackSystem = require "Module.Backpack.BackpackSystem"

local ErrorCode = 
{
    ResShopList = 
    {
        OK = 0,
        SHOP_LIST_LOADED = 1,
    },
    ResultType = 
    {
        OK               = 0,
        NO_SHOP          = 1,
        REFRESH_LIMIT    = 2,
        RES_NOT_ENOUGH   = 3,
    }
}
---------------------------------------------------------
---数据处理
ShopSystem.ShopInfo = {}

-- --缓存购买的物品
function ShopSystem:CachedPurchaseItems(shop_id, shop_item_id, shop_item_count)
    self.CachedShopId = shop_id
    self.CachedShopItemId = shop_item_id
    self.CachedShopItemCount = shop_item_count
end

---------------------------------------------------------
---协议处理
function ShopSystem:OnNetCmd_Res_Shop_List(result, msgId, parsed_msg)
    -- LOG_INFO("==服务器下发商店数据:" .. tostring(result))
    if result == 0 and
        parsed_msg and
        parsed_msg.res_shop_list and
        parsed_msg.res_shop_list.shop_list_info and
        parsed_msg.res_shop_list.shop_list_info.shop_infos then
            
        --优化数据存储结构
        self.ShopInfo = {}
        for _, shop_info in pairs(parsed_msg.res_shop_list.shop_list_info.shop_infos) do
            if not self.ShopInfo[shop_info.shop_id] then
                self.ShopInfo[shop_info.shop_id] = shop_info
                for _, shop_item_info in ipairs(shop_info.shop_item_infos) do
                    shop_item_info.purchase_times = 0
                    local item_info = d_shop[shop_item_info.shop_item_id]
                    if not item_info then
                        LOG_FORMAT_ERROR("item_info is nil, shop_item_id=%s, shop_id=%d",
                        tostring(shop_item_info.shop_item_id), shop_info.shop_id)
                    end
                    local bag_item_info
                    if item_info.itemType == UIUtils.ItemMainType.Weapon then
                        bag_item_info = Database.Query("d_bag_item_weapon", item_info.goodsId)
                    elseif item_info.itemType == UIUtils.ItemMainType.Equip then
                        bag_item_info = Database.Query("d_bag_item_equip", item_info.goodsId)
                    else
                        bag_item_info = Database.Query("d_bag_item", item_info.goodsId)
                    end
                    if not bag_item_info then
                        LOG_ERROR('====未找到d_bag_item配置:' .. tostring(item_info.goodsId))
                    else
                        shop_item_info.count = BackpackSystem:GetInstance():GetItemCount(bag_item_info.id)
                        shop_item_info.config = bag_item_info
                        shop_item_info.shop_config = item_info
                        for _, purchase_limit_info in ipairs(shop_info.purchase_limit_infos) do
                            if purchase_limit_info.shop_item_id == shop_item_info.shop_item_id then
                                shop_item_info.purchase_times = purchase_limit_info.purchase_times
                            end
                        end
                    end
                end

                table.sort(self.ShopInfo[shop_info.shop_id].shop_item_infos, function(itemA, itemB)
                    return itemA.shop_config.sortWeight > itemB.shop_config.sortWeight
                end)
            end
        end
        -- print("====背包数据:" .. tostring(table.dump(self.ShopInfo, false, 10)))
    end
end

function ShopSystem:OnNetCmd_Res_Shop_Refresh(result, msgId, parsed_msg)
    if result == ErrorCode.ResultType.OK then
    end
end

function ShopSystem:OnNetCmd_Res_Shop_Buy(result, msgId, parsed_msg)
    if result == ErrorCode.ResultType.OK then
        local msg = {
            shop_id = self.CachedShopId,
            shop_item_id = self.CachedShopItemId,
            shop_item_count = self.CachedShopItemCount,
        }
        MessageManager:GetInstance():Broadcast("OnMsg_Shop_Buy", msg)
    else
        LOG_INFO("===OnNetCmd_Res_Shop_Buy:" .. tostring(result))
    end
end

function ShopSystem:OnNetCmd_Ntf_Shop_Info(result, msgId, parsed_msg)
    -- LOG_INFO("===OnNetCmd_Ntf_Shop_Info:" .. tostring(result))
    if result == ErrorCode.ResultType.OK then
        for _, shop_info in pairs(parsed_msg.ntf_shop_info.shop_infos) do
            self.ShopInfo[shop_info.shop_id] = shop_info
            for _, shop_item_info in ipairs(shop_info.shop_item_infos) do
                shop_item_info.purchase_times = 0
                local item_info = d_shop[shop_item_info.shop_item_id]
                local bag_item_info
                if item_info.itemType == UIUtils.ItemMainType.Weapon then
                    bag_item_info = Database.Query("d_bag_item_weapon", item_info.goodsId)
                elseif item_info.itemType == UIUtils.ItemMainType.Equip then
                    bag_item_info = Database.Query("d_bag_item_equip", item_info.goodsId)
                else
                    bag_item_info = Database.Query("d_bag_item", item_info.goodsId)
                end
                if not bag_item_info then
                    LOG_ERROR('====未找到d_bag_item配置:' .. tostring(item_info.goodsId))
                else
                    shop_item_info.count = BackpackSystem:GetInstance():GetItemCount(bag_item_info.id)
                    shop_item_info.config = bag_item_info
                    shop_item_info.shop_config = item_info
                    for _, purchase_limit_info in ipairs(shop_info.purchase_limit_infos) do
                        if purchase_limit_info.shop_item_id == shop_item_info.shop_item_id then
                            shop_item_info.purchase_times = purchase_limit_info.purchase_times
                        end
                    end
                end
            end

            table.sort(self.ShopInfo[shop_info.shop_id].shop_item_infos, function(itemA, itemB)
                return itemA.shop_config.sortWeight > itemB.shop_config.sortWeight
            end)
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Shop_Refresh")
    end
end

return ShopSystem
