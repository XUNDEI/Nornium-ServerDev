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

---@type STT_Dialog_Option_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState(Transition)
    if self.Entered then return end
    self.Entered = true
    LOG_DEBUG('STT_Dialog_Option_C:ReceiveLatentEnterState')
    MessageManager:GetInstance():AddListener("Dialog_clicked_option", self)
    MessageManager:GetInstance():AddListener("Set_Disable_LoadingAnim", self)
    MessageManager:GetInstance():AddListener("OnChangedStreamingLevel", self)
    local plot_info = PlotSystem:GetInstance().PlotInfo
    self.HasMission = false
    for _, mission_info in ipairs(plot_info.plot_mission_infos) do
        local task_info = Database.Query("d_task_story", mission_info.mission_id)
        if task_info then
            if #task_info.taskNumber >= 2 and task_info.taskNumber[1] == tonumber(self.DialogId) then
                self.HasMission = true
                LOG_WARN('此对话 ' .. self.DialogId)
                LOG_WARN('有任务 ' .. mission_info.mission_id .. ' ' .. task_info.taskNumber[2])
                MessageManager:GetInstance():AddListener("complete_plot_mission", self)
            end
        end
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2")
    self.Overridden.ReceiveLatentEnterState(self, Transition)
end

function M:ReceiveEnterState(Transition)
    if self.Entered then return UE.EStateTreeRunStatus.Running end
    self.Entered = true
    LOG_DEBUG('STT_Dialog_Option_C:ReceiveEnterState')
    MessageManager:GetInstance():AddListener("Dialog_clicked_option", self)
    MessageManager:GetInstance():AddListener("Set_Disable_LoadingAnim", self)
    MessageManager:GetInstance():AddListener("OnChangedStreamingLevel", self)
    local plot_info = PlotSystem:GetInstance().PlotInfo
    self.HasMission = false
    for _, mission_info in ipairs(plot_info.plot_mission_infos) do
        local task_info = Database.Query("d_task_story", mission_info.mission_id)
        if task_info then
            if #task_info.taskNumber >= 2 and task_info.taskNumber[1] == tonumber(self.DialogId) then
                self.HasMission = true
                LOG_WARN('此对话 ' .. self.DialogId)
                LOG_WARN('有任务 ' .. mission_info.mission_id .. ' ' .. task_info.taskNumber[2])
                MessageManager:GetInstance():AddListener("complete_plot_mission", self)
            end
        end
    end
    -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- gameInstance:RemoveUMG("UI_Loading2")
    self.Overridden.ReceiveEnterState(self, Transition)
    return UE.EStateTreeRunStatus.Running
end

function M:ReceiveExitState(Transition)
    LOG_DEBUG('STT_Dialog_Option_C:ReceiveExitState')
    MessageManager:GetInstance():RemoveListener("Dialog_clicked_option", self)
    MessageManager:GetInstance():RemoveListener("Set_Disable_LoadingAnim", self)
    MessageManager:GetInstance():RemoveListener("OnChangedStreamingLevel", self)
    UIManager:GetInstance():ClearTracker()
    self.Overridden.ReceiveExitState(self, Transition)
end

function M:Dialog_clicked_option(dialog_id, option_index)
    --遍历plot mission 发送事件
    local plot_info = PlotSystem:GetInstance().PlotInfo
    for _, mission_info in ipairs(plot_info.plot_mission_infos) do
        local task_info = Database.Query("d_task_story", mission_info.mission_id)
        if task_info then
            if #task_info.taskNumber >= 2 and task_info.taskNumber[1] == dialog_id and task_info.taskNumber[2] == tonumber(option_index) then
                self.msg = { mission_id = mission_info.mission_id }
            end
        else
            LOG_ERROR('Mission Id ' .. mission_info.mission_id .. ' not find in task_story')
        end
    end 
    return UE.EStateTreeRunStatus.Running
end

function M:Set_Disable_LoadingAnim()
    --如果对话之后进入战斗 只播放一次FadeIn 禁用BP_ScreenFade的动画播放 不然会播放FadeIn FadeOut 和进入战斗前的FadeIn
    if self.BlockUILoadingAnim then
        --退出战斗场景时DisableLoadingAnim会重置
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController.BP_ScreenFade.DisableLoadingAnim = true
    end
end

function M:STT_Speak_Finished()
    LOG_WARN('STT_Speak_Finished' .. self.DialogId)
    local plot_info = PlotSystem:GetInstance().PlotInfo
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    if self.msg then
        PlotSystem:GetInstance():ReqCompletePlotMission(self.msg)
        gameInstance.req_data.req_complete_plot_mission = self.msg
    else
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
    end

    if not self.HasMission then
        self.Complete = true
    end
    LOG_WARN('STT_Speak_Finished Complete')
    self.Overridden.STT_Speak_Finished(self)
end

function M:complete_plot_mission()
    MessageManager:GetInstance():RemoveListener("complete_plot_mission", self)
    self.Complete = true
end

function M:OnChangedStreamingLevel()
    if UE.UGameplayStatics.IsValid(self) and self.LoadTrigger then
        UIManager:GetInstance():ClearTracker()
        print('-------------loadtrigger')
        self:LoadTrigger()
    end
end

return M