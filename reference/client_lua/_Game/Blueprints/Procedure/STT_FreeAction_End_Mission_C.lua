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

---@type STT_FreeAction_End_Mission_C
local M = UnLua.Class()

function M:ReceiveEnterState(Transition)
    if QuestSystem:GetInstance().QuestInfo[self.MissionId] then
        local config = Database.Query('d_task_story', self.MissionId)
        if config.taskContent == 40001 then --40001到达目标位置触发
            print('------------>STT_FreeAction_End_Mission:' .. tostring(self.MissionId))
            QuestSystem:GetInstance().QuestInfo[self.MissionId] = nil
            QuestSystem:GetInstance():SetMainTrackQuestId(0)
            
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
            self.Overridden.ReceiveEnterState(self, Transition)
        end
    end
    return UE.EStateTreeRunStatus.Running
end

return M
