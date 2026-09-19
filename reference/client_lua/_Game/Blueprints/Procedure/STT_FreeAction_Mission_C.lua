--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require "_Game.Utils.Database"
local QuestSystem = require "Module.Quest.QuestSystem"

---@type STT_FreeAction_Mission_C
local M = UnLua.Class()

function M:ReceiveEnterState(Transition)
    if self.MissionId ~= 0 then
        local config = Database.Query('d_task_story', self.MissionId)
        if config.taskContent == 40001 then  --40001到达目标位置触发
            local quest = {
                mission_id = self.MissionId,
                completed = false,
                mission_record_args = {}
            }
            QuestSystem:GetInstance().QuestInfo[self.MissionId] = quest
            QuestSystem:GetInstance():SetMainTrackQuestId(self.MissionId)
            self.Overridden.ReceiveEnterState(self, Transition)
        end
    end
    return UE.EStateTreeRunStatus.Running
end

return M
