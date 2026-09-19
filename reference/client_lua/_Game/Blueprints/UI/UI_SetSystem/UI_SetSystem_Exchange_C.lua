local InputAssets = require "_Game.Utils.Input.InputAssets"
local Client = require("Network.Client")
local InputUtils = require "_Game.Utils.Input.InputUtils"
local Protos = require("Helper.Protos")
local UIUtils = require("_Game.Utils.UIUtils")

---@type UI_SetSystem_Exchange_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self.Btn_Close.OnClicked:Add(self, self.Close)
    self.Btn_Confirm.OnClicked:Add(self, self.Confirm)

    self.GiftCode.OnTextCommitted:Add(self, function(self, text, commitMethod)
        if commitMethod == UE.ETextCommit.OnEnter then
            self:Confirm()
        end
    end)

    NetworkMessageManager:GetInstance():AddListener(Protos.NTF_ITEM_INFO, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_USE_GIFT_CODE, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.NTF_ITEM_INFO, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_USE_GIFT_CODE, self)
end

---@param parsed_msg NtfItemInfoMessage
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

---@param parsed_msg ResUseGiftCodeMessage
M[Protos.RES_USE_GIFT_CODE] = function(self, result, msgId, parsed_msg)
end

function M:Confirm()
    Client.send(Protos.REQ_USE_GIFT_CODE, {
        gift_code = self.GiftCode:GetText()
    })
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

return M
