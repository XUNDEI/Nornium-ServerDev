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

---@type STT_NextNode_C
local M = UnLua.Class()

function M:AfterUnload()
    MessageManager:GetInstance():AddListener("Play_Plot", self)
    --找到下一个可执行的statetree
    local plot_info = PlotSystem:GetInstance().PlotInfo
    local transNodeId = PlotSystem:GetInstance():GetTransNode()
    --刷新完成任务信息
    PlotSystem:GetInstance():RefreshCompletedMissionInfo()
    if transNodeId ~= 0 then
        --找到新解锁的子节点
        local msg = {}
        msg.plot_tree_id = plot_info.plot_tree_id
        msg.plot_node_id = transNodeId
        Client.send("req_play_plot_node", msg)
        self.Complete = true
        return UE.EStateTreeRunStatus.Running
    else
        --nextnode为空时，该节点从头开始
        local msg = {}
        msg.plot_tree_id = plot_info.plot_tree_id
        msg.plot_node_id = plot_info.plot_node_id
        Client.send("req_play_plot_node", msg)
        self.Complete = true
        return UE.EStateTreeRunStatus.Running
    end
end

function M:ReceiveExitState(Transition)
    self.Overridden.ReceiveExitState(self, Transition)
end

function M:Play_Plot()
    MessageManager:GetInstance():RemoveListener("Play_Plot", self)
    local levelName = UE.UGameplayStatics.GetCurrentLevelName(self, true)
    if levelName == "CityMap" then
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        if playerController.BP_StateTree:IsRunning() then
            playerController.BP_StateTree:StopLogic("Finish")
        end
        playerController.BP_StateTree:StartLogic()
        local oldCharacter = playerController:K2_GetPawn()
        if oldCharacter then
            oldCharacter:K2_DestroyActor()
        end
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:LoadLevel("CityMap")
    end
end

return M
