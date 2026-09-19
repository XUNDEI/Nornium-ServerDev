---@type STT_ShowMaskedHighlight_C
local M = UnLua.Class()

local QuestSystem = require "Module.Quest.QuestSystem"

function M:ReceiveLatentEnterState(Transition)
    if self.MissionId and self.MissionId > 0 and QuestSystem.TrackQuestId ~= self.MissionId then
        self.Complete = true
        self:FinishTask(true)
        return
    end

    self.step = 1

    self:ShowStep()
end

function M:ShowStep()
    if self.step <= self.Config:Num() then
        ---@type FMaskedHighlightConfig
        local config = self.Config:Get(self.step)

        UIManager:GetInstance():RequestShowMaskedHighlight(self, config)
    end
end

function M:NextStep()
    self.step = self.step + 1

    if self.step > self.Config:Num() then
        if self.ExitAfterClicked then
            self:FinishTask(true)
        end
    else
        self:ShowStep()
    end
end

return M
