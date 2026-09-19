--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local PlotSystem = require "Module.Plot.PlotSystem"

---@type STT_EnterBuild_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState()
    PlotSystem:GetInstance().STTEnteringLevel = true
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController:EnterBuildLevel('City1Hotel', self.PlayerStartTag, false)
end

function M:ReceiveLatentExitState()
    PlotSystem:GetInstance().STTEnteringLevel = false
end

function M:ReceiveLatentTick()
    if self.Complete then return end
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.IsInBuildLevel then
        self.Complete = true
    end
    if self.Complete then
        PlotSystem:GetInstance().STTEnteringLevel = false
        -- self:FinishTask(true)
    end
end

return M