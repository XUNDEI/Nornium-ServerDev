--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local PlotSystem = require "Module.Plot.PlotSystem"

---@type STT_EnterStation_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState()
    self:ExecTask()
    PlotSystem:GetInstance().STTEnteringLevel = true
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController:LoadStationScene(false)
end

function M:ReceiveLatentExitState()
    PlotSystem:GetInstance().STTEnteringLevel = false
end

function M:ReceiveLatentTick()
    if self.Complete then return end
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.bIsInStationScene then
        self.Complete = true
    end
    if self.Complete then
        PlotSystem:GetInstance().STTEnteringLevel = false
        -- self:FinishTask(true)
    end
end

return M