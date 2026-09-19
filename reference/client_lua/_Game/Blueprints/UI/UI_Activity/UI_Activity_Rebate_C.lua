local UIUtils = require("_Game.Utils.UIUtils")
---@type UI_Activity_Rebate_C : UI_Activity_Base
local M = UnLua.Class("_Game.Blueprints.UI.UI_Activity.UI_Activity_Base")

function M:RefreshUI()
    self.activityId = 5
    self.Super.RefreshUI(self)

    self.Help.OnClicked:Add(self, function()
        UIUtils.ShowSystemDes(1008)
    end)

    self.Btn_Fight.OnClicked:Clear()
    self.Btn_Fight.OnClicked:Add(self, function()
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        ---@type UI_TopUp_Shop_C
        local ui = gameInstance:AddUMG('UI_TopUp_Shop')
        ui.MonthCard:SetIsCheckedAndFireEvent(true)
    end)

    self.Btn_Fight_1.OnClicked:Clear()
    self.Btn_Fight_1.OnClicked:Add(self, function()
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        ---@type UI_TopUp_Shop_C
        local ui = gameInstance:AddUMG('UI_TopUp_Shop')
        ui.TopUp:SetIsCheckedAndFireEvent(true)
    end)
end

return M
