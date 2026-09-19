local Database = require("_Game.Utils.Database")

---@class BossRushModel
---@field configId number @总力战配置id
---@field mainLeaderboardInfo TotalWarRankTotalScoreItemInfo[] @总榜，每一项包含复数boss战记录
---@field mainRank number
---@field bossLeaderboardInfo table<uint32, TotalWarRankBossScoreItemInfo[]> @分榜，每个bossid有一个纪录列表
---@field bossRank table<uint32, number>
---@field records TotalWarRankRecordInfo[]
---@field playerRewards TotalWarRewardInfo[]
local BossRushModel = BaseClass("BossRushModel")

function BossRushModel:__init()
    self.mainLeaderboardInfo = {}
    self.bossLeaderboardInfo = {}
    self.records = {}
end

---@param resTotalWar ResTotalWar
function BossRushModel:InitInfo(resTotalWar)
    self.configId = resTotalWar.total_war_info.schedule_id

    self.config = Database.Query("d_bossrush_schedule", self.configId)

    --分数记录 character_ids还存了上次进战斗时的阵容
    self.playerRecords = resTotalWar.total_war_info.boss_infos

    --锁船信息
    self.usedCharacters = resTotalWar.total_war_info.character_infos

    --正在打的boss
    self.selectedBoss = resTotalWar.total_war_info.fight_boss_id

    --缓存的战斗信息
    self.lastFight = resTotalWar.total_war_info.fight_info

    self.playerRewards = resTotalWar.total_war_info.reward_infos
end

---@param resTotalWarRank ResTotalWarRank
function BossRushModel:UpdateRank(resTotalWarRank)
    self.mainLeaderboardInfo = resTotalWarRank.total_war_rank_info.total_war_rank_total_score_info.total_war_rank_total_score_item_infos
    self.mainRank = resTotalWarRank.total_war_rank_info.total_war_rank_total_score_info.self_rank

    self.bossLeaderboardInfo = {}
    self.bossRank = {}
    for _, info in ipairs(resTotalWarRank.total_war_rank_info.total_war_rank_boss_score_infos) do
        self.bossLeaderboardInfo[info.boss_id] = info.total_war_rank_boss_score_item_infos
        self.bossRank[info.boss_id] = info.self_rank
    end

    self.records = resTotalWarRank.total_war_rank_info.total_war_rank_record_infos
    local total_war_rank_record_info_boss_ranks = resTotalWarRank.total_war_rank_info.total_war_rank_record_info_boss_ranks
    local pb = require "pb"
    for i = 1, #self.records do
        local record = self.records[i]
        record = pb.decode("ghs.TotalWarRankRecordInfo", record)
        record.boss_rank = total_war_rank_record_info_boss_ranks[i]
        self.records[i] = record
    end
end

function BossRushModel:HasPendingFight()
    return self.selectedBoss ~= 0
end

return BossRushModel
