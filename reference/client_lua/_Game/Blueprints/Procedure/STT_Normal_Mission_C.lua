--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local QuestSystem = require "Module.Quest.QuestSystem"

---@type STT_Normal_Mission_C
local M = UnLua.Class()

function M:ReceiveEnterState(Transition)
    self.HaveAddItem = false
    if self.MissionId ~= 0 then
        local config = Database.Query('d_task_story', self.MissionId)
        if config.taskContent ~= 4001 then  --4001到达目标位置触发
            if not QuestSystem:GetInstance().QuestInfo[self.MissionId] then
                local quest = {
                    mission_id = self.MissionId,
                    completed = false,
                    mission_record_args = {}
                }
                QuestSystem:GetInstance().QuestInfo[self.MissionId] = quest
                QuestSystem:GetInstance():SetMainTrackQuestId(self.MissionId)
                QuestSystem:GetInstance():CheckMissionFinished(quest, config.taskContent, config)
            end
            self.Overridden.ReceiveEnterState(self, Transition)
        end
    end
    return UE.EStateTreeRunStatus.Running
end

function M:ReceiveTick(DeltaTime)
    --self.Overridden.ReceiveTick(self, DeltaTime)
    if QuestSystem:GetInstance().QuestInfo[self.MissionId].finished then
        if not self.HaveAddItem then -- 没领奖励
            self.HaveAddItem = true
            local config = Database.Query('d_task_story', self.MissionId)
            local msg = 'add_item'
            local reward_item_count = #config.reward / 3
            if reward_item_count > 0 then
                for i = 1, reward_item_count do
                    local item_id = config.reward[i * 3]
                    local item_config = UIUtils.GetItemConfigById(item_id)
                    msg = msg .. ' ' .. item_id .. ' ' .. item_config.itemType .. ' ' .. config.reward[i * 3 + 2]
                end
                Client.send("req_gm_cmd", { cmd = msg })
                local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                gameInstance.req_data.req_gm_cmd = msg
                gameInstance.req_data.isMission = true
            end
            return UE.EStateTreeRunStatus.Running
        else 
            local config = Database.Query('d_task_story', self.MissionId)
            if config.taskContent ~= 30002 or
                config.taskContent ~= 30003 or 
                config.taskContent ~= 30005 then --会加载角色场景
                local level = UE.UGameplayStatics.GetStreamingLevel(self, "CharecterScene")
                if level:IsLevelLoaded() then
                    return UE.EStateTreeRunStatus.Running
                end
            end
            print('------------>sttNormalMission:' .. tostring(self.MissionId))
            QuestSystem:GetInstance().QuestInfo[self.MissionId] = nil
            QuestSystem:GetInstance():SetMainTrackQuestId(0)
            return UE.EStateTreeRunStatus.Succeeded
        end
    else
        return UE.EStateTreeRunStatus.Running
    end
end

return M
