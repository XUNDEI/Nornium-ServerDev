--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require '_Game.Utils.UIUtils'
local Database = require "_Game.Utils.Database"
local PlotSystem = require "Module.Plot.PlotSystem"

---@type STT_Block_C
local M = UnLua.Class()

function M:ReceiveEnterState(Transition)
    MessageManager:GetInstance():AddListener("complete_plot_mission", self)
    return self.Overridden.ReceiveEnterState(self, Transition)
end

function M:ReceiveExitState(Transition)
    MessageManager:GetInstance():RemoveListener("complete_plot_mission", self)
    self.Overridden.ReceiveExitState(self, Transition)
end

function M:ExecTask()
    local plot_info = PlotSystem:GetInstance().PlotInfo
    local bFinished = false
    local task_info = Database.Query("d_task_story", self.MissionId)

    if task_info.taskType == UIUtils.ETaskType.Main then --主线
        for _, completed_mission_id in ipairs(plot_info.node_completed_mission_ids) do
            --当前节点已完成任务
            if completed_mission_id == self.MissionId then
                bFinished = true
                self.Complete = true
                return UE.EStateTreeRunStatus.Succeeded
            end
        end
    elseif task_info.taskType == UIUtils.ETaskType.Tutorial then --教学
        for _, completed_mission_id in ipairs(plot_info.node_completed_mission_ids) do
            --当前节点已完成任务
            if completed_mission_id == self.MissionId then
                bFinished = true
                self.Complete = true
                return UE.EStateTreeRunStatus.Succeeded
            end
        end
        for _, completed_mission_id in ipairs(plot_info.completed_mission_ids) do
            --已完成任务
            if completed_mission_id == self.MissionId then
                bFinished = true
                self.Complete = true
                return UE.EStateTreeRunStatus.Succeeded
            end
        end
    end
end

function M:complete_plot_mission(mission_id)
    if mission_id == self.MissionId then
        self.Complete = true
    end
end

return M