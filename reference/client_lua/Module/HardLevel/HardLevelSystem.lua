
local NetCmdController = require "Framework.Common.NetCmdController"
local HardLevelSystem = BaseClass("HardLevelSystem", NetCmdController)
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local UIUtils = require '_Game.Utils.UIUtils'
local Database = require '_Game.Utils.Database'


HardLevelSystem.HardLevelInfos = {}

--请求活动列表数据
function HardLevelSystem:OnNetCmd_Res_Hard_Level(result, msgId, parsed_msg)
    -- print("====OnNetCmd_Req_Activity_List:" .. tostring(result))
    -- print('===msg:' .. tostring(table.dump(parsed_msg, nil, 10)))
    HardLevelSystem.HardLevelInfos = parsed_msg.res_hard_level.hard_level_info
end

--请求活动战斗
function HardLevelSystem:ReqHardLevelFight(msg)
    self.CachedHardLevelFightId = msg.fight_level_id
    Client.send("req_hard_level_fight", msg)
end

function HardLevelSystem:OnNetCmd_res_hard_level_fight(result, msgId, parsed_msg)
    if result == 0 then
        --临时记录下挑战副本的战斗uuid
        HardLevelSystem.HardLevelInfos.fight_uuid = parsed_msg.res_hard_level_fight.fight_uuid
    else
        LOG_WARN("Res Activity Hard Level Fight Error Code:", result)
    end
end

function HardLevelSystem:ReqCompleteHardLevelFight(msg)
    self.CachedCompleteHardLevelFight = msg
    Client.send('req_complete_hard_level_fight', msg)
end

function HardLevelSystem:OnNetCmd_res_complete_hard_level_fight(result, msgId, param_msg)
    if result == 0 then
        if HardLevelSystem.HardLevelInfos and self.CachedCompleteHardLevelFight.result then
            if self.CachedHardLevelFightId <= 8 then
                local lastId = HardLevelSystem.HardLevelInfos.passed_level_id
                HardLevelSystem.HardLevelInfos.passed_level_id = lastId >= self.CachedHardLevelFightId and lastId or self.CachedHardLevelFightId
            end
          
            for i = 1, #self.CachedCompleteHardLevelFight.stars do 
                local pos = (self.CachedHardLevelFightId - 1) * 3 + i
                local isPass = HardLevelSystem.HardLevelInfos.stars[pos] or false
                HardLevelSystem.HardLevelInfos.stars[pos] = isPass or self.CachedCompleteHardLevelFight.stars[i]
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
---挑战副本

function HardLevelSystem:GetFightUid()
    if HardLevelSystem.HardLevelInfos.fight_info.fight_uuid > 0 then
        return HardLevelSystem.HardLevelInfos.fight_info.fight_uuid
    end
    return 0
end

function HardLevelSystem:GetFightLevelId()
    if HardLevelSystem.HardLevelInfos.fight_info.fight_level_id > 0 then
        return HardLevelSystem.HardLevelInfos.fight_info.fight_level_id
    end
    return 0
end

function HardLevelSystem:GetNextLevel()
    local nextId = 0
    if self.CachedHardLevelFightId > 0 then
        nextId = self.CachedHardLevelFightId + 1
        local config = Database.Query('d_levels_challenge', nextId)
        return config and nextId or 0
    end
    return nextId
end

return HardLevelSystem