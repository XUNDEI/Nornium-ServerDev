--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local PlotSystem = require "Module.Plot.PlotSystem"

---@type STT_Tutorial_C
local M = UnLua.Class()

function M:ExecTask()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
    local num = saveGameSpeak.TutorialId:Length()
    for i = 1, num do
        local id = saveGameSpeak.TutorialId:Get(i)
        if id == self.TutorialId then
            self.Complete = true
            return
        end
    end
    if self.ShowOnPosses then
        saveGameSpeak.TutorialId:Add(self.TutorialId)
        gameInstance:SaveSaveGameSpeak()
        PlotSystem:GetInstance():SaveTurorialId(self.TutorialId)
    else
        
        MessageManager:GetInstance():AddListener("Finished_Tutorial", self)
        gameInstance:ShowTutorial(self.TutorialId, self.PauseGame)
        saveGameSpeak.TutorialId:Add(self.TutorialId)
        gameInstance:SaveSaveGameSpeak()
        -- UE.UGameplayStatics.SetGlobalTimeDilation(self, 0)
        -- LOG_DEBUG_TRACKBACK("UE.UGameplayStatics.SetGlobalTimeDilation(self, 0)")
    end
    gameInstance:RemoveUMG("UI_Loading2")
end

function M:Finished_Tutorial()
    MessageManager:GetInstance():RemoveListener("Finished_Tutorial", self)
    self.Complete = true
    -- UE.UGameplayStatics.SetGlobalTimeDilation(self, 1)
    -- LOG_DEBUG_TRACKBACK("UE.UGameplayStatics.SetGlobalTimeDilation(self, 1)")
end

return M