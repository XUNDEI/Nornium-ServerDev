
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SetSystem_Handle_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:Setup()
    self.Back.OnClicked:Add(self, self.Close)

    self.Fight.OnCheckStateChanged:Add(self, function(self, isOn)
        if isOn then
            self:Show(335)
        end
    end)

    self.Scene.OnCheckStateChanged:Add(self, function(self, isOn)
        if isOn then
            self:Show(334)
        end
    end)

    self.Common.OnCheckStateChanged:Add(self, function(self, isOn)
        if isOn then
            self:Show(333)
        end
    end)

    self.Common:SetIsCheckedAndFireEvent(true)
end

function M:Show(title)
    local keys = self.Keys:GetAllChildren()

    ---@param widget UI_SetSystem_Handle_Entry_C
    for _, widget in pairs(keys) do
        widget:Update(title)
    end
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)


return M
