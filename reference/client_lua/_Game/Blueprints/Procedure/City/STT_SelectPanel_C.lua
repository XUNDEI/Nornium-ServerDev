--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type STT_SelectPanel_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState()
    self.selectTreePanel = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_SelectTree')
    self.selectTreePanel.IsBadEnd = true
    self.selectTreePanel.ExitPanel:SetVisibility(UE.ESlateVisibility.Hidden)
end

return M
