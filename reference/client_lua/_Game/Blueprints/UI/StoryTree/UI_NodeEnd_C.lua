local Database = require "_Game.Utils.Database"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_NodeEnd_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Skip()
    self.OnButtonDown:Broadcast()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Skip)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.Skip)

function M:InitUI(nameId, index, show_zheZhi)
    self.TextNumber:SetText(index)
    if show_zheZhi then
        self.TextName2:SetVisibility(UE.ESlateVisibility.Visible)
        self.TextName:SetText(Database.L10n(nameId))
        self.TextBlock_181:SetVisibility(UE.ESlateVisibility.Hidden)
        self.TextNumber:SetVisibility(UE.ESlateVisibility.Hidden)
        self.TextBlock_1:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.TextName:SetText(Database.L10n(nameId))
        self.TextName2:SetVisibility(UE.ESlateVisibility.Hidden)
        self.TextBlock_181:SetVisibility(UE.ESlateVisibility.Visible)
        self.TextNumber:SetVisibility(UE.ESlateVisibility.Visible)
        self.TextBlock_1:SetVisibility(UE.ESlateVisibility.Visible)
    end
    self:PlayAnimationForward(self.In, 1, false)
end

return M
