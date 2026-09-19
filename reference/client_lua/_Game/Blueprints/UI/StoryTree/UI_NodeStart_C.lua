local Database = require "_Game.Utils.Database"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_NodeStart_C
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

function M:InitUI(nameId, index)
    self.TextName:SetText(Database.L10n(nameId))
    self.TextNumber:SetText(index)
    self:PlayAnimationForward(self.In, 1, false)
end

return M
