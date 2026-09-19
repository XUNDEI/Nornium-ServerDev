--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type STT_HideLoading2_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState(Transition)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2") 
    self:FinishTask(true)
end

return M