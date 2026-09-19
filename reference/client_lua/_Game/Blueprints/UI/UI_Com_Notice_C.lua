require "UnLua"
require "Common.TableUtil"
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Com_Notice_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:IA_Back()
    self.CloseButton_Fight.OnClicked:Broadcast()
end

function M:IA_Confirm()
    self.OKButton_Fight.OnClicked:Broadcast()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.IA_Back)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.IA_Confirm)

---@class NoticeArgs
---@field title string
---@field notice string
---@field confirm fun(self:UI_Com_Notice_C)
---@field cancel fun(self:UI_Com_Notice_C)
---@field showCancel bool

---@param args NoticeArgs
function M:ShowArgs(args)
    if args.title then
        self.TextTitle:SetText(args.title)
    end
    if args.notice then
        self.TRTB_Content:SetText(args.notice)
    end

    self.OKButton_Fight.OnClicked:Add(self, function(self)
        UIManager:GetInstance():RemoveUI(self, true)
        if args.confirm then
            args.confirm(self)
        end
    end)
    
    self.CloseButton_Fight.OnClicked:Add(self, function(self)
        UIManager:GetInstance():RemoveUI(self, true)
        if args.cancel then
            args.cancel(self)
        end
    end)

    self.CloseButton_Fight:SetVisibility(args.showCancel and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
end

return M
