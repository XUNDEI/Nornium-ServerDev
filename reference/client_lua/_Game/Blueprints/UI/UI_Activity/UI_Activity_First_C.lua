local MallSystem = require("Module.ShopSystem.MallSystem")
local UIUtils = require("_Game.Utils.UIUtils")
local Protos = require("Helper.Protos")

---@type UI_Activity_First_C : UI_Activity_Base
local M = UnLua.Class("_Game.Blueprints.UI.UI_Activity.UI_Activity_Base")

function M:Construct()
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_MALL_BUY, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.NTF_ITEM_INFO, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_MALL_BUY, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.NTF_ITEM_INFO, self)
end

M[Protos.RES_MALL_BUY] = function(self, result, msgId, parsed_msg)
    self.waiting = false

    if result == 0 then
        self:RefreshUI()
    end
end

M[Protos.NTF_ITEM_INFO] = function(self, result, msgId, parsed_msg)
    local rewardList = {}
    for _, item in pairs(parsed_msg.ntf_item_info.changed_item_infos) do
        table.insert(rewardList, {
            itemId = item.item_id,
            count = item.count,
        })
    end
    UIUtils.ShowGetRewardCommonUI(self, rewardList)
end

function M:RefreshUI()
    self.activityId = 4
    self.Super.RefreshUI(self)

    self.Btn_Fight.OnClicked:Clear()
    self.Btn_Fight.OnClicked:Add(self, function()
        if not self.waiting then
            self.waiting = true
            MallSystem:GetInstance():BuyGiftPacks(1010)
        end
    end)

    self.Total.OnClicked:Clear()
    self.Total.OnClicked:Add(self, function()
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        ---@type UI_TopUp_Shop_C
        local ui = gameInstance:AddUMG('UI_TopUp_Shop')
        ui.Btn_AddUp.OnGHSClicked:Broadcast()
    end)

    self.Btn_Fight:SetIsEnabled(MallSystem:GetInstance():CanBuyGiftPacks(1010))
    self.Btn_Fight:SetVisibility(MallSystem:GetInstance():CanBuyGiftPacks(1010) and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
    self.Bought:SetVisibility(not MallSystem:GetInstance():CanBuyGiftPacks(1010) and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
end

return M
