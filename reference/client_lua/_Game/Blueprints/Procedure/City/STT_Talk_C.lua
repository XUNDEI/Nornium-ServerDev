--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type STT_Talk_C
local M = UnLua.Class()

function M:ReceiveEnterState(Transition)
    MessageManager:GetInstance():AddListener("Finished_Talk", self)
    self.Overridden.ReceiveEnterState(self, Transition)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:ShowTalkUI(self.TalkId)
    local ui = gameInstance:GetUMG('UI_Dialog_Talk')
    gameInstance:GetUMG('UI_Dialog_Talk').EventOnPlayEnd:Add(self, self.Finished_Talk)
    return UE.EStateTreeRunStatus.Running
end

function M:ReceiveExitState(Transition)
    MessageManager:GetInstance():RemoveListener("Finished_Talk", self)
    self.Overridden.ReceiveExitState(self, Transition)
end

function M:Finished_Talk()
    self.Complete = true
end

return M