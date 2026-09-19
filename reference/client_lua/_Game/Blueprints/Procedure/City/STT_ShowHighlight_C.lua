--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type STT_ShowHighlight_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState(Transition)
    UIManager:GetInstance():RequestShowHighlight(self.Position, self.Size, self.Anchors, UE.UKismetSystemLibrary.Conv_SoftClassReferenceToClass(self.UI))
end

function M:ReceiveStateCompleted(CompletionStatus, CompletedActiveStates)
    UIManager:GetInstance():RemoveHighlight(UE.UKismetSystemLibrary.Conv_SoftClassReferenceToClass(self.UI))
end

return M
