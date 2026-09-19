--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local QuestSystem = require "Module.Quest.QuestSystem"
local UIUtils = require '_Game.Utils.UIUtils'
local PlotSystem = require "Module.Plot.PlotSystem"
local PlayerSystem = require('Module.Player.PlayerSystem')
local Database = require "_Game.Utils.Database"

---@type STT_WaitMission_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState()
    if self.MissionId and self.MissionId > 0 then
        local plot_info = PlotSystem:GetInstance().PlotInfo
        local bFinished = false
        local task_info = Database.Query("d_task_story", self.MissionId)
    
        if task_info.taskType == UIUtils.ETaskType.Main then --主线
            for _, completed_mission_id in ipairs(plot_info.node_completed_mission_ids) do
                --当前节点已完成任务
                if completed_mission_id == self.MissionId then
                    bFinished = true
                    self.Complete = true
                    self:FinishTask(true)
                    return 
                end
            end
        elseif task_info.taskType == UIUtils.ETaskType.Tutorial then --教学
            for _, completed_mission_id in ipairs(plot_info.node_completed_mission_ids) do
                --当前节点已完成任务
                if completed_mission_id == self.MissionId then
                    bFinished = true
                    self.Complete = true
                    self:FinishTask(true)
                    return 
                end
            end
            for _, completed_mission_id in ipairs(plot_info.completed_mission_ids) do
                --已完成任务
                if completed_mission_id == self.MissionId then
                    bFinished = true
                    self.Complete = true
                    self:FinishTask(true)
                    return 
                end
            end
        end
    end
end

function M:ReceiveLatentTick(DeltaTime)
    if QuestSystem.TrackQuestId == self.MissionId then
        self:FinishTask(true)
    end
end

return M