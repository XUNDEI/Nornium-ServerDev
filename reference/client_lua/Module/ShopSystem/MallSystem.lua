local NetCmdController = require "Framework.Common.NetCmdController"
local MallSystem = BaseClass("MallSystem", NetCmdController)
local MessageManager = require "Framework.Updater.MessageManager"
local Client = require "Network.Client"
local d_shop = require("ClientDatas.d_shop")
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local d_bag_item = require("ClientDatas.d_bag_item")
local PlayerSystem = require("Module.Player.PlayerSystem")
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
    },
    ResultResMallBuy = 
    {
        OK              = 0,
        NO_MALL         = 1,
        NO_MALL_ITEM    = 2,
        MALL_REFRESHED  = 3,
        PURCHASE_LIMIT  = 4,
        RES_NOT_ENOUGH  = 5,
        ITEM_NOT_USEFUL = 6,

        STEAM_GET_USER_INFO_FAILED        = 101,
        STEAM_USER_LOCKED_FROM_PURCHASING = 102,
        STEAM_INIT_TXN_FAILED             = 103,

        STEAM_GET_USER_INFO_FAILED_HTTP_FAILED        = 111,
        STEAM_INIT_TXN_FAILED_HTTP_FAILED             = 113,

        STEAM_GET_USER_INFO_FAILED_JSON_FAILED        = 121,
        STEAM_INIT_TXN_FAILED_JSON_FAILED             = 123,
    }
}

local MallType = 
{
    GiftPacks = 103,
    DressUp = 104,
    Furniture = 105,
    LowClassExchange = 106,
    HighClassExchange = 107,
    TopUp = 201,
    MonthCard = 202,
    Passport = 203,
}

---------------------------------------------------------
---数据处理
MallSystem.MallInfo = {}
MallSystem.PastTime = 0

function MallSystem:SaveChargeInfo(charge_info)
    self.chargeInfo = charge_info
end

function MallSystem:OnNetCmd_Res_Mall_List(result, msgId, parsed_msg)
    MallSystem.MallInfo = parsed_msg.res_mall_list.mall_list_info
    for index, mall_info in ipairs(MallSystem.MallInfo.mall_infos) do
        table.sort(mall_info.mall_item_infos, function(a, b)
            local a_config = Database.Query("d_mall", a.mall_item_id)
            local b_config = Database.Query("d_mall", b.mall_item_id)
            if a_config.orde ~= b_config.order then
                return a_config.order < b_config.order
            else
                return a_config.id < b_config.id
            end
        end)
    end

    --判断是否要领月卡奖励
    if MallSystem.MallInfo.month_card_info.expire_seconds ~= 0 then
        local server_time = PlayerSystem:GetInstance():GetServerTime()
        if server_time > MallSystem.MallInfo.month_card_info.expire_seconds then
            --过期
        else
            if MallSystem.MallInfo.month_card_info.last_tick_seconds == 0 then
                --第一次申请月卡奖励
                Client.send("req_mall_receive_month_card")
            else
                --凌晨四点刷新奖励
                local time = UIUtils.GetDailyRefresh(MallSystem.MallInfo.month_card_info.last_tick_seconds)
                if time > 0 then
                    Client.send("req_mall_receive_month_card")
                end
            end
        end
    end
end

function MallSystem:OnNetCmd_Res_Mall_Buy(result, msgId, parsed_msg)
    print("======OnNetCmd_Res_Mall_Buy:" .. result)
    if result == 0 then
        local item_info = Database.Query("d_mall", parsed_msg.req_data.mall_item_id)
        if item_info then
            if #item_info.goods > 1 then
                local tempItemId = item_info.goods[1]
                local tempItemConfig = UIUtils.GetItemConfigById(tempItemId)
                local CharacterSystem = require('Module.CharacterSystem.CharacterSystem')
                if tempItemConfig.itemType == UIUtils.ItemMainType.Skin then
                    CharacterSystem:GetInstance():UseSkinItem(tempItemId)
                elseif tempItemConfig.itemType == UIUtils.ItemMainType.TempProp and tempItemConfig.subType == UIUtils.ItemTempPropType.CharCard then
                    CharacterSystem:GetInstance():UsePlayerSkin(tempItemId)
                end
            end
            if item_info.charge == 1 then
                self:SaveChargeInfo(parsed_msg)
                MessageManager:GetInstance():Broadcast("OnMsg_Res_Charge_Mall_Buy", parsed_msg)
                return
            end
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Res_Mall_Buy", parsed_msg)
    else
        --有错误码时 关闭等待ui
        local ui = self.GameInstance:GetUMG('UI_TopUp_Shop')
        if ui and UE.UKismetSystemLibrary.IsValid(ui) then
            ui.WaitPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        if result == ErrorCode.ResultResMallBuy.STEAM_GET_USER_INFO_FAILED_HTTP_FAILED 
            or result == ErrorCode.ResultResMallBuy.STEAM_INIT_TXN_FAILED_HTTP_FAILED
            or result == ErrorCode.ResultResMallBuy.STEAM_GET_USER_INFO_FAILED_JSON_FAILED
            or result == ErrorCode.ResultResMallBuy.STEAM_INIT_TXN_FAILED_JSON_FAILED then
            UIUtils.ShowNotify(self.GameInstance, Database.L10n(504))
        elseif result == ErrorCode.ResultResMallBuy.STEAM_GET_USER_INFO_FAILED then
            UIUtils.ShowNotify(self.GameInstance, Database.L10n(505))
        elseif result == ErrorCode.ResultResMallBuy.STEAM_USER_LOCKED_FROM_PURCHASING then
            UIUtils.ShowNotify(self.GameInstance, Database.L10n(506))
        elseif result == ErrorCode.ResultResMallBuy.STEAM_INIT_TXN_FAILED then
            UIUtils.ShowNotify(self.GameInstance, Database.L10n(507))
        end
    end
end

function MallSystem:OnNetCmd_Res_Finish_Order(result, msgId, parsed_msg)
    if result == 0 then
        MessageManager:GetInstance():Broadcast("OnMsg_Res_Finish_Order", parsed_msg)
    else
        --有错误码时 关闭等待ui
        local ui = self.GameInstance:GetUMG('UI_TopUp_Shop')
        if ui and UE.UKismetSystemLibrary.IsValid(ui) then
            ui.WaitPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        if self.UI_Waiting then
            self.GameInstance:RemoveUMG('UI_Waiting')
            self.UI_Waiting = nil
        end
    end
end

function MallSystem:OnNetCmd_Ntf_Finish_Order(result, msgId, parsed_msg)
    if result == 0 then
        local config = Database.Query("d_mall", self.chargeInfo.req_data.mall_item_id)
        if config then
            MallSystem.MallInfo.charge_point_info.charge_point = MallSystem.MallInfo.charge_point_info.charge_point + config.chargePoint
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Res_Mall_Buy", self.chargeInfo)
    end
    if self.UI_Waiting then
        self.GameInstance:RemoveUMG('UI_Waiting')
        self.UI_Waiting = nil
    end
end

function MallSystem:OnNetCmd_Ntf_Mall_Info(result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg.ntf_mall_info and parsed_msg.ntf_mall_info.mall_infos then
            for index, ntf_mall_info in ipairs(parsed_msg.ntf_mall_info.mall_infos) do
                for index, mall_info in ipairs(MallSystem.MallInfo.mall_infos) do
                    if mall_info.mall_id == ntf_mall_info.mall_id then
                        MallSystem.MallInfo.mall_infos[index] = ntf_mall_info
                        table.sort(MallSystem.MallInfo.mall_infos[index].mall_item_infos, function(a, b)
                            local a_config = Database.Query("d_mall", a.mall_item_id)
                            local b_config = Database.Query("d_mall", b.mall_item_id)
                            if a_config.orde ~= b_config.order then
                                return a_config.order < b_config.order
                            else
                                return a_config.id < b_config.id
                            end
                        end)
                    end
                end
            end

            if parsed_msg.ntf_mall_info.month_card_info then
                MallSystem.MallInfo.month_card_info = parsed_msg.ntf_mall_info.month_card_info
            end
            MessageManager:GetInstance():Broadcast("OnMsg_Ntf_Mall_Info")
        end
    end
end

function MallSystem:OnNetCmd_Res_Mall_Receive_Charge_Point_Reward(result, msgId, parsed_msg)
    if result == 0 then
        table.insert(MallSystem.MallInfo.charge_point_info.received_charge_point_ids, parsed_msg.req_data.charge_point_id)
        MessageManager:GetInstance():Broadcast("OnMsg_Res_Receive_Charge_Point_Reward", parsed_msg.req_data.charge_point_id)
        print("======OnNetCmd_Res_Receive_Charge_Point_Reward:" .. parsed_msg.req_data.charge_point_id)
    end
end

function MallSystem:OnNetCmd_Res_Mall_Receive_Month_Card(result, msgId, parsed_msg)
    if result == 0 then
        local monthly_config = Database.Query("d_gacha_monthly_pass", 1007)
        if monthly_config then
            self.GameInstance.MonthCardItems = {}
            local item_count = #monthly_config.dailyReward / 3
            for i = 1, item_count do
                table.insert(self.GameInstance.MonthCardItems, { item_id = monthly_config.dailyReward[i * 3 - 2], count = monthly_config.dailyReward[i * 3] })
            end
        end
        MessageManager:GetInstance():Broadcast("OnMsg_Res_Mall_Receive_Month_Card")
    end
end

function MallSystem:SetGameInstance(gameInstance)
    self.GameInstance = gameInstance
end

function MallSystem:CanBuyMothCard()
    local time = MallSystem.MallInfo.month_card_info.expire_seconds - PlayerSystem:GetInstance():GetServerTime()
    local day = math.floor(time / 24 / 60 / 60)
    local monthly_config = Database.Query("d_gacha_monthly_pass", 1007)
    if monthly_config then
        if day >= (monthly_config.maxLasting - 30) then
            return false
        end
    end
    return true
end

function MallSystem:BuyMothCard()
    local can_buy = self:CanBuyMothCard()
    if can_buy then
        local moth_card_mall_info = {}
        for _, mall_info in ipairs(MallSystem.MallInfo.mall_infos) do
            if mall_info.mall_id == MallType.MonthCard then
                moth_card_mall_info = mall_info
                break
            end
        end

        local msg = {}
        msg.mall_id = moth_card_mall_info.mall_id
        msg.mall_item_id = 1007
        msg.mall_item_count = 1
        msg.last_auto_refresh_seconds = moth_card_mall_info.last_auto_refresh_seconds
        local bSuccess, SteamId, CurrentGameLanguage = self.GameInstance:PreparePayWithSteam(0)
        if bSuccess then
            msg.steam_id = SteamId
            msg.steam_current_game_language = CurrentGameLanguage
        end
        msg.access_token = self.GameInstance.key
        Client.send("req_mall_buy", msg)
    end
end

function MallSystem:CanBuyGiftPacks(mall_item_id)
    local gift_packs_mall_info = {}
    for _, mall_info in ipairs(MallSystem.MallInfo.mall_infos) do
        if mall_info.mall_id == MallType.GiftPacks then
            gift_packs_mall_info = mall_info
            break
        end
    end

    local purchase_times = 0
    for _, mall_purchase_limit_info in ipairs(gift_packs_mall_info.mall_purchase_limit_infos) do
        if mall_purchase_limit_info.mall_item_id == mall_item_id then
            purchase_times = mall_purchase_limit_info.purchase_times
        end
    end

    local config = Database.Query("d_mall", mall_item_id)
    if config then
        if config.limitTimes > 0 then
            if config.limitTimes - purchase_times <= 0 then
                return false
            end
        end
    end

    --是否已拥有
    local hasAllGood = true
    local good_id = config.goods[4]
    local count = UIUtils.GetItemCount(good_id)
    if count == 0 then
        hasAllGood = false
    end

    local item_config
    if config.goods[4] then
        item_config = Database.Query("d_bag_item", config.goods[4])
        if not item_config then
            item_config = Database.Query("d_bag_item_weapon", config.goods[4])
        end
        if not item_config then
            item_config = Database.Query("d_bag_item_equip", config.goods[4])
        end
    end

    if item_config.itemType == UIUtils.ItemMainType.TempProp and item_config.subType == UIUtils.ItemTempPropType.CharCard then
        local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
        local character_id = item_config.subParam[1]
        local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
        if character_info then
            --有角色时判断涂装里的机甲是否已激活
            hasAllGood = true
            local skin_id = item_config.subParam[2]
            local skin_info = Database.Query("d_bag_item", skin_id)
            if skin_info then
                for _, item_skin_id in ipairs(skin_info.subParam) do
                    local item_skin_info = Database.Query("d_char_clothes", item_skin_id)
                    if item_skin_info.dressType == 4 then                     --套房皮肤
                        local _, isSkinUnlock = UIUtils.CharSkinIsUnlock(character_id, item_skin_info.dressType - 1,
                            item_skin_id - 1000000)
                        if not isSkinUnlock then
                            hasAllGood = false
                            break
                        end
                    else
                        local _, isSkinUnlock = UIUtils.CharSkinIsUnlock(character_id, item_skin_info.dressType - 1,
                            item_skin_id)
                        if not isSkinUnlock then
                            hasAllGood = false
                            break
                        end
                    end
                end
            end
        end
    end

    if hasAllGood then
        return false
    end

    return true
end

function MallSystem:BuyGiftPacks(mall_item_id)
    local config = Database.Query("d_mall", mall_item_id)
    local can_buy = self:CanBuyGiftPacks(mall_item_id)
    if config and can_buy then
        local gift_packs_mall_info = {}
        for _, mall_info in ipairs(MallSystem.MallInfo.mall_infos) do
            if mall_info.mall_id == MallType.GiftPacks then
                gift_packs_mall_info = mall_info
                break
            end
        end

        local msg = {}
        msg.mall_id = gift_packs_mall_info.mall_id
        msg.mall_item_id = mall_item_id
        msg.mall_item_count = 1
        msg.last_auto_refresh_seconds = gift_packs_mall_info.last_auto_refresh_seconds
        local bSuccess, SteamId, CurrentGameLanguage = self.GameInstance:PreparePayWithSteam(0)
        if bSuccess then
            msg.steam_id = SteamId
            msg.steam_current_game_language = CurrentGameLanguage
        end
        msg.access_token = self.GameInstance.key
        Client.send("req_mall_buy", msg)
        self.UI_Waiting = self.GameInstance:AddUMG('UI_Waiting')
    end
end

function MallSystem:CheckMonthCard(DeltaTime)
    self.PastTime = self.PastTime + DeltaTime
    if self.PastTime > 1 then
        self.PastTime = 0
        if MallSystem.MallInfo.month_card_info then
            --判断是否要领月卡奖励
            if MallSystem.MallInfo.month_card_info.expire_seconds ~= 0 then
                local server_time = PlayerSystem:GetInstance():GetServerTime()
                if server_time > MallSystem.MallInfo.month_card_info.expire_seconds then
                    --过期
                else
                    if MallSystem.MallInfo.month_card_info.last_tick_seconds == 0 then
                        --第一次申请月卡奖励
                        Client.send("req_mall_receive_month_card")
                    else
                        --凌晨四点刷新奖励
                        local time = UIUtils.GetDailyRefresh(MallSystem.MallInfo.month_card_info.last_tick_seconds)
                        if time > 0 then
                            Client.send("req_mall_receive_month_card")
                        end
                    end
                end
            end
        end
    end
end

return MallSystem
