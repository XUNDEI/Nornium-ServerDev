local BossRushController = require("Module.BossRush.BossRushController")
local Database = require("_Game.Utils.Database")
local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"

---@type UI_BossRush_LeaderboardEntry_Short_C
local M = UnLua.Class()

-- local ICON_PATH = '/Game/_Game/TP_New/IdolProfile_res/Frames/%s_png.%s_png'
function M:SetupMainLeaderboardEntry(rank)
    local entry = BossRushController:GetInstance():GetLeaderboardEntry(rank)
    local records = entry.record_ids

    local avatarId, playerName

    for _, recordId in ipairs(records) do
        if recordId ~= 0 then
            local record = BossRushController:GetInstance():GetRecord(recordId)

            avatarId = record.avatar_id
            playerName = record.player_name
        end
    end

    -- local avatarName = Database.Query("d_character", avatarId).idolProfile
    -- local icon = LoadObject(string.format(ICON_PATH, avatarName, avatarName))
    -- self.Icon:SetBrushFromAtlasInterface(icon)
    self.Name:SetText(playerName)
    self.Score:SetText(BossRushUtils.FormatRichText(entry.score))
    self.rank:SetText(rank)
end

---@param entry TotalWarRankBossScoreItemInfo
function M:SetupBossLeaderboardEntry(rank, entry)
    local record = BossRushController:GetInstance():GetRecord(entry.record_id)

    local avatarId = record.avatar_id
    local playerName = record.player_name

    -- local avatarName = Database.Query("d_character", avatarId).idolProfile
    -- local icon = LoadObject(string.format(ICON_PATH, avatarName, avatarName))
    -- self.Icon:SetBrushFromAtlasInterface(icon)
    self.Name:SetText(playerName)
    self.Score:SetText(BossRushUtils.FormatRichText(record.score))
    self.rank:SetText(rank)
end

return M
