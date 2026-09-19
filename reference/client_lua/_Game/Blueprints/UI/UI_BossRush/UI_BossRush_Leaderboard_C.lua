local PlayerSystem = require "Module.Player.PlayerSystem"
local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"
local BossRushController = require("Module.BossRush.BossRushController")
local Database = require("_Game.Utils.Database")

local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local d_bossrush_ranking = require "ClientDatas.d_bossrush_ranking"

---@type UI_BossRush_Leaderboard_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    if not M.LeaderboardEntryData then
        M.UI_BossRush_LeaderboardEntry_SingleBoss = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_LeaderboardEntry_SingleBoss.UI_BossRush_LeaderboardEntry_SingleBoss_C')
        M.UI_BossRush_LeaderboardEntry_SingleBossRef = UnLua.Ref(M.UI_BossRush_LeaderboardEntry_SingleBoss)
        M.UI_BossRush_LeaderboardEntry_Full = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_LeaderboardEntry_Full.UI_BossRush_LeaderboardEntry_Full_C')
        M.UI_BossRush_LeaderboardEntry_FullRef = UnLua.Ref(M.UI_BossRush_LeaderboardEntry_Full)
        M.UI_BossRush_Reward = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_Reward.UI_BossRush_Reward_C')
        M.UI_BossRush_RewardRef = UnLua.Ref(M.UI_BossRush_Reward)
        M.LeaderboardEntryData = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/LeaderboardEntryData.LeaderboardEntryData_C')
        M.LeaderboardEntryDataRef = UnLua.Ref(M.LeaderboardEntryData)
    end
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Back)

local RANK_ICON_PATH = '/Game/_Game/TP_New/TotalWar_res/Frames/Icon_Reward_%d_png.Icon_Reward_%d_png'

function M:UpdateMainLeaderboard()
    local score = BossRushController:GetInstance():GetPlayerTotalScore()
    self.PlayerScore:SetText(BossRushUtils.FormatRichText(score))

    local rank = BossRushController:GetInstance():GetRank()
    local rewardRank = #d_bossrush_ranking
    for i, info in ipairs(d_bossrush_ranking) do
        if rank <= info.endRank then
            rewardRank = i
            break
        end
    end
    
    if score > 0 then
        local rankIcon = LoadObject(string.format(RANK_ICON_PATH, rewardRank, rewardRank))
    
        self.Icon:SetBrush(UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(rankIcon, 0, 0))
        self.Rank:SetText(string.format(Database.L10n(450), rank))
    else
        self.Rank:SetText(Database.L10n(449))
    end

    if BossRushController:GetInstance():RecordDirty() then
        self.Rank:SetText(Database.L10n(453))
    end

    local leaderboard = BossRushController:GetInstance():GetLeaderboard()

    self.Leaderboard.EntryWidgetClass = M.UI_BossRush_LeaderboardEntry_Full
    self.Leaderboard:ClearListItems()
    for rank, info in ipairs(leaderboard) do
        if rank > BossRushUtils.RANK_MAX then
            break
        end
        ---@type LeaderboardEntryData_C
        local entryData = NewObject(M.LeaderboardEntryData)
        entryData.Rank = rank
        self.Leaderboard:AddItem(entryData)
    end

    self.Rewards:ClearChildren()
    for _, rankInfo in ipairs(d_bossrush_ranking) do
        ---@type UI_BossRush_Reward_C
        local entry = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_Reward)

        self.Rewards:AddChild(entry)
        entry:Setup(rankInfo)
    end

    self.RankTitle1:SetText(Database.L10n(462))
    self.RankTitle2:SetText(Database.L10n(462))
    self.RewardTitle1:SetText(Database.L10n(463))
    self.RewardTitle2:SetText(Database.L10n(463))
    self.SwitchInfo.OnCheckStateChanged:Add(self, function(self, isOn)
        self.LeaderboardPage:SetVisibility(isOn and UE.ESlateVisibility.Collapsed or UE.ESlateVisibility.SelfHitTestInvisible)
        self.RewardPage:SetVisibility(isOn and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
    end)
end

local BOSS_ICON_L_PATH = '/Game/_Game/TP_New/TotalWar_res/Frames/TotalWar_Level%d_L_png.TotalWar_Level%d_L_png'

function M:UpdateBossLeaderboard()
    local score = BossRushController:GetInstance():GetBossScore(self.bossId) or 0
    self.PlayerScore:SetText(BossRushUtils.FormatRichText(score))

    local rank = BossRushController:GetInstance():GetBossRank(self.bossId)
    local difficulty = BossRushUtils.GetScoreDifficulty(score)

    if score > 0 then
        local iconPath = string.format(BOSS_ICON_L_PATH, difficulty, difficulty)
        local icon = LoadObject(iconPath)
        self.Icon:SetBrushFromAtlasInterface(icon)
        self.Rank:SetText(string.format(Database.L10n(450), rank))
    else
        self.Icon:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Rank:SetText(Database.L10n(449))
    end

    if BossRushController:GetInstance():RecordDirty(self.bossId) then
        self.Rank:SetText(Database.L10n(453))
    end

    local leaderboard = BossRushController:GetInstance():GetBossLeaderboard(self.bossId)

    self.Leaderboard.EntryWidgetClass = M.UI_BossRush_LeaderboardEntry_SingleBoss
    self.Leaderboard:ClearListItems()
    for rank, recordId in ipairs(leaderboard) do
        if rank > BossRushUtils.RANK_MAX then
            break
        end
        ---@type LeaderboardEntryData_C
        local entryData = NewObject(M.LeaderboardEntryData)
        entryData.Rank = rank
        entryData.BossId = self.bossId
        self.Leaderboard:AddItem(entryData)
    end
end

function M:Setup(bossId)
    self.bossId = bossId
    -- 头像没有 全是眠眠
    self.Name:SetText(PlayerSystem:GetInstance():GetPlayerName())
    self.UID:SetText(PlayerSystem:GetInstance():GetUID())

    self.CloseBtn.OnClicked:Add(self, self.Close)

    self.SwitchInfo:SetVisibility(bossId and UE.ESlateVisibility.Collapsed or UE.ESlateVisibility.Visible)

    if not bossId then
        self:UpdateMainLeaderboard()
    else
        self:UpdateBossLeaderboard()
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

return M
