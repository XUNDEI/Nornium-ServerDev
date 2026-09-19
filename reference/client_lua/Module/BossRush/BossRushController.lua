local Protos = require("Helper.Protos")
local datetime = require("_Game.Utils.datetime")
local NetworkMessageListener = require("Module.NetworkMessageListener")
local Client = require "Network.Client"
local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"
local PlayerSystem = require("Module.Player.PlayerSystem")

local BossRushModel = require("Module.BossRush.BossRushModel")

local d_bossrush_level = require("ClientDatas.d_bossrush_level")
local activitysystem = require("Module.Activity.ActivitySystem")

---@class BossRushController : NetworkMessageListener
---@field model BossRushModel
---@field GetInstance fun():BossRushController
local BossRushController = BaseClass("BossRushController", NetworkMessageListener)
local MessageManager = require("Framework.Updater.MessageManager"):GetInstance()

BossRushController.LeaderBoardUpdated = "BossRushController.LeaderBoardUpdated"

---{{{protos
BossRushController.__listened_network_messages = {
    Protos.RES_TOTAL_WAR,
    Protos.RES_TOTAL_WAR_RANK,
    Protos.RES_TOTAL_WAR_FIGHT,
    Protos.RES_RECEIVE_TOTAL_WAR_REWARD,
}

---@param self BossRushController
---@param parsed_msg ResTotalWarMessage
BossRushController[Protos.RES_TOTAL_WAR] = function(self, result, msgId, parsed_msg)
    self.model:InitInfo(parsed_msg.res_total_war)
end

---@param self BossRushController
---@param parsed_msg ResTotalWarRankMessage
BossRushController[Protos.RES_TOTAL_WAR_RANK] = function(self, result, msgId, parsed_msg)
    self.model:UpdateRank(parsed_msg.res_total_war_rank)

    self.timestamp = parsed_msg.res_total_war_rank.last_total_war_ranking_data_seconds

    self:FlushPlayerRecords()

    MessageManager:Broadcast(BossRushController.LeaderBoardUpdated)
end

---@param self BossRushController
---@param parsed_msg ResTotalWarFightMessage
BossRushController[Protos.RES_TOTAL_WAR_FIGHT] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        self.model.selectedBoss = parsed_msg.req_data.boss_id
        self.model.lastFight.fight_uuid = parsed_msg.res_total_war_fight.fight_uuid

        self:UpdateCharacters(self.model.selectedBoss, parsed_msg.req_data.character_ids)
    end
end

---@param self BossRushController
---@param parsed_msg ResCompleteTotalWarFightMessage
BossRushController[Protos.RES_COMPLETE_TOTAL_WAR_FIGHT] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg.res_complete_total_war_fight then
            self:UpdateScore(self.model.selectedBoss, parsed_msg.res_complete_total_war_fight.new_score)
        end
        if parsed_msg.req_data.result == true then
            self:IncreaseDifficulty(self.model.selectedBoss)
        end
        
        local characterIds
        for _, record in ipairs(self.model.playerRecords) do
            if record.boss_id == self.model.selectedBoss then
                characterIds = record.character_ids
            end
        end
        self:UpdateUsedCharacters(self.model.selectedBoss, characterIds)

        self.model.selectedBoss = 0
        self.model.lastFight.fight_level_id = 0
        self.model.lastFight.fight_state = 0
        self.model.lastFight.fight_uuid = 0
        
        MessageManager:Broadcast('OnMsg_Complete_Total_War_Fight')
    end
end

function BossRushController:OnCompleteTotalWarFight(result, msgId, parsed_msg)
    self[Protos.RES_COMPLETE_TOTAL_WAR_FIGHT](self, result, msgId, parsed_msg)
end

---@param self BossRushController
BossRushController[Protos.RES_RECEIVE_TOTAL_WAR_REWARD] = function(self, result, msgId, parsed_msg)
    self.model.playerRewards = {}
end
---}}}

function BossRushController:__init()
    self.model = BossRushModel.New()
end

function BossRushController:GetBossConfig(bossId, difficulty)
    for _, level in ipairs(d_bossrush_level) do
        if level.bossID == bossId and level.difficult == difficulty then
            return level
        end
    end
end

function BossRushController:GetBoss()
    return { self.model.config.boss1, self.model.config.boss2, self.model.config.boss3 }
end

function BossRushController:GetBossScore(bossId)
    for _, record in ipairs(self.model.playerRecords) do
        if bossId == record.boss_id then
            return record.score
        end
    end

    return 0
end

function BossRushController:GetPlayerTotalScore()
    local score = 0

    for _, record in ipairs(self.model.playerRecords) do
        score = score + record.score
    end

    return score
end

function BossRushController:RecordDirty(bossId)
    for _, record in ipairs(self.model.playerRecords) do
        LOG_INFO(table.dump(record))
        if (not bossId or bossId == record.boss_id) and record.dirty then
            return true
        end
    end
end

function BossRushController:FlushPlayerRecords()
    for _, record in ipairs(self.model.playerRecords) do
        if record.dirty and record.timestamp < self.timestamp then
            record.dirty = false
        end
    end
end

function BossRushController:UpdateCharacters(bossId, characterIds)
    for _, record in ipairs(self.model.playerRecords) do
        if record.boss_id == bossId then
            record.character_ids = characterIds
            return
        end
    end

    table.insert(self.model.playerRecords, {
        boss_id = bossId,
        score = 0,
        difficulty_value = 1,
        dirty = false,
        timestamp = PlayerSystem:GetInstance():GetServerTime(),
        character_ids = characterIds,
    })
end

function BossRushController:UpdateScore(bossId, score)
    for _, record in ipairs(self.model.playerRecords) do
        if record.boss_id == bossId then
            if score > record.score then
                record.score = score
                record.dirty = true
                record.timestamp = PlayerSystem:GetInstance():GetServerTime()
            end
            return
        end
    end

    table.insert(self.model.playerRecords, {
        boss_id = bossId,
        score = score,
        difficulty_value = 1,
        dirty = true,
        timestamp = PlayerSystem:GetInstance():GetServerTime(),
        character_ids = {},
    })
end

function BossRushController:UpdateUsedCharacters(bossId, characterIds)
    for _, characterId in ipairs(characterIds) do
        ---@param record TotalWarCharacterInfo
        local conflict = table.any(self.model.usedCharacters, function(record)
            return record.boss_id ~= bossId and record.character_id == characterId
        end)
        ---@param record TotalWarCharacterInfo
        local exist = table.any(self.model.usedCharacters, function(record)
            return record.boss_id == bossId and record.character_id == characterId
        end)
        if conflict then
            LOG_WARN("Used characters conflict!", characterId)
        elseif not exist then
            table.insert(self.model.usedCharacters, {
                boss_id = bossId,
                character_id = characterId,
            })
        end
    end
end

function BossRushController:GetBossUsedCharacters(bossId)
    local res = {}
    for _, v in ipairs(self.model.usedCharacters) do
        if v.boss_id == bossId then
            table.insert(res, v.character_id)
        end
    end

    return res
end

function BossRushController:GetOtherBossUsedCharacters(bossId)
    local res = {}
    for _, v in ipairs(self.model.usedCharacters) do
        if v.boss_id ~= bossId then
            table.insert(res, v.character_id)
        end
    end

    return res
end

---@param leaderboard TotalWarRankTotalScoreItemInfo[] | TotalWarRankBossScoreItemInfo[]
function BossRushController:GetEstimateRank(score, leaderboard)
    local rank = 0
    local found = false
    local rankChanged = true
    for index, info in ipairs(leaderboard) do
        if index <= BossRushUtils.RANK_MAX and info.score == score then
            ---@type TotalWarRankRecordInfo
            local record
            if info.record_id then
                record = self:GetRecord(info.record_id)
            else
                record = self:GetRecord(info.record_ids[1])
            end

            if record.player_id == PlayerSystem:GetInstance():GetUID() then
                rank = index
                rankChanged = false
            end
        end
        if info.score < score then
            rank = index
            found = true
            break
        end
    end

    if not rankChanged then
        return rank
    end

    if found then
        local lowerRank = BossRushUtils.GetRealRank(rank - 1)
        local higherRank = BossRushUtils.GetRealRank(rank)

        if higherRank - lowerRank == 1 then
            return higherRank
        else
            local lowerScore = leaderboard[lowerRank].score
            local higherScore = leaderboard[higherRank].score

            return math.floor((score - lowerScore) / (higherScore - lowerScore) * (higherRank - lowerRank) + lowerRank)
        end
    else
        return BossRushUtils.GetRealRank(#leaderboard + 1)
    end
end

function BossRushController:GetRank()
    return self:GetRealRank()
end

function BossRushController:GetBossRank(bossId)
    return self:GetRealBossRank(bossId)
end

function BossRushController:GetRealRank()
    return self.model.mainRank
end

function BossRushController:GetRealBossRank(bossId)
    return self.model.bossRank[bossId]
end

function BossRushController:GetBossMaxDifficulty(bossId)
    local difficulty = 0
    for _, level in ipairs(d_bossrush_level) do
        if level.bossID == bossId and level.difficult > difficulty then
            difficulty = level.difficult
        end
    end
    return difficulty
end

-- 玩家应该进行的难度
function BossRushController:GetPlayerDifficulty(bossId)
    local record = self:GetPlayerRecord(bossId)

    return record and record.difficulty_value or 1
end

function BossRushController:GetPlayerCharacters(bossId)
    local record = self:GetPlayerRecord(bossId)

    return record and record.character_ids or {}
end

function BossRushController:IncreaseDifficulty(bossId)
    local difficulty = self:GetPlayerDifficulty(bossId)
    local maxDifficulty = self:GetBossMaxDifficulty(bossId)

    local nextDifficulty = math.min(maxDifficulty, difficulty + 1)

    for _, record in ipairs(self.model.playerRecords) do
        if record.boss_id == bossId then
            record.difficulty_value = nextDifficulty
        end
    end
end

function BossRushController:GetCurrentFightRecord()
    return self:GetPlayerRecord(self.model.selectedBoss)
end

function BossRushController:GetPlayerRecord(bossId)
    for _, record in ipairs(self.model.playerRecords) do
        if record.boss_id == bossId then
            return record
        end
    end

    return nil
end

function BossRushController:HasPendingFight()
    return self.model.lastFight and (self.model.lastFight.fight_level_id ~= 0 or self.model.lastFight.fight_uuid ~= 0)
end

function BossRushController:GetPendingBossFight()
    return self.model.selectedBoss
end

function BossRushController:GetEndTime()
    return self.model.config.endTime
end

function BossRushController:GetRewardRank()
    if #self.model.playerRewards > 0 then
        return self.model.playerRewards[1].rank
    end
end

function BossRushController:GetRewardScore()
    if #self.model.playerRewards > 0 then
        return self.model.playerRewards[1].total_score
    end
end

function BossRushController:RewardsAvailable()
    return #self.model.playerRewards > 0
end

function BossRushController:IsEventPhase()
    local startTime = datetime.str_to_time(self.model.config.startTime)
    local endTime = datetime.str_to_time(self.model.config.endTime)

    local serverTime = PlayerSystem:GetInstance():GetServerTime()

    return startTime <= serverTime and serverTime <= endTime
end

function BossRushController:RequestLeaderboard()
    if not self.timestamp or (PlayerSystem:GetInstance():GetServerTime() - self.timestamp > 60) then
        Client.send(Protos.REQ_TOTAL_WAR_RANK)
    end
end

function BossRushController:GetRecord(recordId)
    for _, info in ipairs(self.model.records) do
        if recordId == info.record_id then
            return info
        end
    end
end

function BossRushController:GetLeaderboardEntry(rank)
    return self.model.mainLeaderboardInfo[rank]
end

function BossRushController:GetLeaderboard()
    return self.model.mainLeaderboardInfo
end

function BossRushController:GetBossLeaderboard(bossId)
    return self.model.bossLeaderboardInfo[bossId]
end

return BossRushController
