--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_NPCBase_C
local M = UnLua.Class()


function M:OnEvent_OverlapStart()
    local wordId = self.OptionItemWordIndex:Get(1)
    UIManager:GetInstance():ClearInteractOption()
    local index = UIManager:GetInstance().layers.Options:GetChildrenCount()
    UIManager:GetInstance():AddInteractOption(self, wordId, function()
        local widget = UIManager:GetInstance().layers.Options:GetChildAt(index)
        self:OnClickItem(widget, index)
    end)
end

function M:OnEvent_OverlapEnd()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
end

function M:OnClickItem(widget, index)
    self.Overridden.OnClickItem(self, widget, index)
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OnMessage('OpenActivityUI', 1)
end

return M