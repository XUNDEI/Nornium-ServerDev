--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local Database = require "_Game.Utils.Database"
local PlotSystem = require "Module.Plot.PlotSystem"
local MessageManager = require "Framework.Updater.MessageManager"

---@type SO_Plot_Dialog_C
local M = UnLua.Class()

-- function M:Initialize(Initializer)
-- end

-- function M:UserConstructionScript()
-- end

function M:ReceiveBeginPlay()
    MessageManager:GetInstance():AddListener("Dialog_clicked_option", self)
    MessageManager:GetInstance():AddListener("OnChangedStreamingLevel", self)
end

function M:ReceiveEndPlay()
    MessageManager:GetInstance():RemoveListener("Dialog_clicked_option", self)
    MessageManager:GetInstance():RemoveListener("OnChangedStreamingLevel", self)
end

function M:SO_Plot_Dialog_Finished()
    LOG_WARN('SO_Plot_Dialog_Finished' .. self.DialogId)
    local plot_info = PlotSystem:GetInstance().PlotInfo
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    for _, mission_info in ipairs(plot_info.plot_mission_infos) do
        local task_info = Database.Query("d_task_story", mission_info.mission_id)
        if task_info then
            if self.DialogId == '0' and task_info.taskNumber[1] and task_info.taskNumber[1] == tonumber(self.DialogId) then
                --触发trigger就完成任务
                local msg = { mission_id = mission_info.mission_id }
                PlotSystem:GetInstance():ReqCompletePlotMission(msg)
                gameInstance.req_data.req_complete_plot_mission = msg
            elseif #task_info.taskNumber >= 2 and task_info.taskNumber[1] == tonumber(self.DialogId) and task_info.taskNumber[2] == 0 then
                --播放完dialog就完成任务
                local msg = { mission_id = mission_info.mission_id }
                PlotSystem:GetInstance():ReqCompletePlotMission(msg)
                gameInstance.req_data.req_complete_plot_mission = msg
            end
        else
            LOG_ERROR('Mission Id ' .. mission_info.mission_id .. ' not find in task_story')
        end
    end 

    if not self.HasMission then
        if self.AddPlotIndex then
            gameInstance:AddPlotIndex()
        end
        self.Complete = true
    end
    LOG_WARN('SO_Plot_Dialog_Finished Complete')
    self.Overridden.SO_Plot_Dialog_Finished(self)
end

function M:Dialog_clicked_option(dialog_id, option_index)
    --遍历plot mission 发送事件
    local plot_info = PlotSystem:GetInstance().PlotInfo
    local hasMission = false
    for _, mission_info in ipairs(plot_info.plot_mission_infos) do
        local task_info = Database.Query("d_task_story", mission_info.mission_id)
        if task_info then
            if #task_info.taskNumber >= 2 and task_info.taskNumber[1] == dialog_id and task_info.taskNumber[2] == tonumber(option_index) then
                --选择配置的选项才完成任务
                hasMission = true
                local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                local msg = { mission_id = mission_info.mission_id }
                PlotSystem:GetInstance():ReqCompletePlotMission(msg)
                gameInstance.req_data.req_complete_plot_mission = msg
            end
        else
            LOG_ERROR('Mission Id ' .. mission_info.mission_id .. ' not find in task_story')
        end
    end 
end

function M:OnChangedStreamingLevel()
end

-- function M:ReceiveTick(DeltaSeconds)
-- end

-- function M:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
-- end

-- function M:ReceiveActorBeginOverlap(OtherActor)
-- end

-- function M:ReceiveActorEndOverlap(OtherActor)
-- end

return M
