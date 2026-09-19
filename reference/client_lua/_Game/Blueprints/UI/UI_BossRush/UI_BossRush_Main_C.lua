local Database = require("_Game.Utils.Database")
local BossRushController = require("Module.BossRush.BossRushController")
local UIUtils = require "_Game.Utils.UIUtils"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"
local datetime = require "_Game.Utils.datetime"
local PlayerSystem = require("Module.Player.PlayerSystem")
local Client = require "Network.Client"
local Protos = require "Helper.Protos"

---@type UI_BossRush_Main_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    if not M.UI_BossRush_BossTitle then
        M.UI_BossRush_BossTitle = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_BossTitle.UI_BossRush_BossTitle_C')
        M.UI_BossRush_BossTitleRef = UnLua.Ref(M.UI_BossRush_BossTitle)
        M.UI_BossRush_LeaderboardEntry_Short = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_LeaderboardEntry_Short.UI_BossRush_LeaderboardEntry_Short_C')
        M.UI_BossRush_LeaderboardEntry_ShortRef = UnLua.Ref(M.UI_BossRush_LeaderboardEntry_Short)
        M.UI_BossRush_Leaderboard = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_Leaderboard.UI_BossRush_Leaderboard_C')
        M.UI_BossRush_LeaderboardRef = UnLua.Ref(M.UI_BossRush_Leaderboard)
        M.UI_BossRush_BuffInfo = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_BuffInfo.UI_BossRush_BuffInfo_C')
        M.UI_BossRush_BuffInfoRef = UnLua.Ref(M.UI_BossRush_BuffInfo)
        M.UI_GetItem_BossRush = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_GetItem_BossRush.UI_GetItem_BossRush_C')
        M.UI_GetItem_BossRushRef = UnLua.Ref(M.UI_GetItem_BossRush)
    end
    MessageManager:GetInstance():AddListener(BossRushController.LeaderBoardUpdated, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.NTF_ITEM_INFO, self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener(BossRushController.LeaderBoardUpdated, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.NTF_ITEM_INFO, self)
end

local FormatString = {
    [86400] = Database.L10n(293),
    [3600] = "%d时%d分",
    [0] = "%d分",
}

function M:Tick()
    local time = PlayerSystem:GetInstance():GetServerTime()
    local timeDiff = time - datetime.str_to_time(BossRushController:GetInstance():GetEndTime())

    if timeDiff < 0 then
        local timeText = datetime.format_time(-timeDiff)
        self.TimeLeft:SetText(Database.L10n(446) .. timeText)
        self.BossPageTimeLeft:SetText(Database.L10n(446) .. timeText)
    else
        self.TimeLeft:SetText(Database.L10n(447))
        self.BossPageTimeLeft:SetText(Database.L10n(447))
    end
end

function M:OnAnimationFinished(animation)
    if animation == self.vfxquit then
        self:Close()
    elseif animation == self.vfxquit_detail then
        self:HideBossInfo()
    end
end

function M:UpdateLeaderboard()
    self.Leaderboard:ClearChildren()
    local leaderboard = BossRushController:GetInstance():GetLeaderboard()
    LOG_INFO(table.dump(leaderboard, false, 10))
    for i = 1, 3 do
        local info = leaderboard[i]
        if info then
            ---@type UI_BossRush_LeaderboardEntry_Short_C
            local entry = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_LeaderboardEntry_Short)
            self.Leaderboard:AddChild(entry)

            entry:SetupMainLeaderboardEntry(i)
        end
    end
end

function M:UpdateBossLeaderboard()
    self.BossLeaderboard:ClearChildren()
    local leaderboard = BossRushController:GetInstance():GetBossLeaderboard(self.selectedBoss)
    if not leaderboard then
        return
    end
    for i = 1, 3 do
        local info = leaderboard[i]
        if info then
            ---@type UI_BossRush_LeaderboardEntry_Short_C
            local entry = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_LeaderboardEntry_Short)
            self.BossLeaderboard:AddChild(entry)

            entry:SetupBossLeaderboardEntry(i, info)
        end
    end
end

M[BossRushController.LeaderBoardUpdated] = function(self)
    self:UpdateLeaderboard()
    self:UpdateBossLeaderboard()
end

---@param parsed_msg NtfItemInfoMessage
M[Protos.NTF_ITEM_INFO] = function(self, result, msgId, parsed_msg)
    if self.showRewards then
        ---@type UI_GetItem_BossRush_C
        local ui = UE.UWidgetBlueprintLibrary.Create(self, M.UI_GetItem_BossRush)
        UIManager:GetInstance():AddUI(ui)

        ui:Setup(parsed_msg.ntf_item_info.changed_item_infos)
        self.showRewards = false
    end
end

local BOSS_ICON_L_PATH = '/Game/_Game/TP_New/TotalWar_res/Frames/TotalWar_Level%d_L_png.TotalWar_Level%d_L_png'

function M:SwitchTo(bossId, difficulty)
    self.selectedBoss = bossId
    self.selectedDifficulty = difficulty

    self:UpdateBossLeaderboard()

    local bossConfig = BossRushController:GetInstance():GetBossConfig(bossId, difficulty)

    self.BossImg:SetBrushFromTexture(LoadObject(bossConfig.BossPic), false)

    local name = Database.L10n(bossConfig.name)
    self.Name:SetText(name)
    self.BossPageName:SetText(name)

    local iconPath = string.format(BOSS_ICON_L_PATH, difficulty, difficulty)
    local icon = LoadObject(iconPath)
    self.BossIcon:SetBrushFromAtlasInterface(icon)
    self.BossPageIcon:SetBrushFromAtlasInterface(icon)

    local record = BossRushController:GetInstance():GetPlayerRecord(bossId)

    local score = record and record.score or 0
    local scoreText = BossRushUtils.FormatRichText(score)
    self.BossScore:SetText(scoreText)
    self.BossPageScore:SetText(scoreText)

    local buffs = bossConfig.buffID

    self.BuffInfo:ClearChildren()
    for _, buff in ipairs(buffs) do
        local info = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_BuffInfo)

        self.BuffInfo:AddChild(info)
        info:Setup(buff)
    end

    self.BossReward:ClearChildren()
    self.BossPageReward:ClearChildren()
    for i = 1, #bossConfig.Reward, 3 do
        local id = bossConfig.Reward[i]
        local count = bossConfig.Reward[i + 2]

        ---@type UI_Get_Item_C
        local item = UIUtils.CreateItem(self, id, count, false)
        local bossPageItem = UIUtils.CreateItem(self, id, count, false)

        self.BossReward:AddChild(item)
        self.BossPageReward:AddChild(bossPageItem)
    end

    self.BossInfo.OnClicked:Add(self, self.ShowBossInfo)
    self.Fight.OnClicked:Add(self, self.StartFight)

    self.BossInfo:SetIsEnabled(BossRushController:GetInstance():IsEventPhase())
    self.Fight:SetIsEnabled(BossRushController:GetInstance():IsEventPhase())
    if not BossRushController:GetInstance():IsEventPhase() then
        self.BossInfoText:SetText(Database.L10n(447))
        self.FightText:SetText(Database.L10n(447))
    end

    self:vfx_Switch()
end

function M:ShowBossInfo()
    self.MainPage:SetVisibility(UE.ESlateVisibility.Hidden)
    self.BossPage:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self:vfx_MainToDetail()
end

function M:HideBossInfo()
    self.MainPage:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.BossPage:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:StartFight()
    local bossConfig = BossRushController:GetInstance():GetBossConfig(self.selectedBoss, self.selectedDifficulty)

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:HideAllUI()

    local level_path = bossConfig.Level
    --local fightLevelClass = LoadObject(string.sub(level_path, 1, -2) .. "_C'")
    gameInstance.LevelClass = nil -- fightLevelClass
    gameInstance.LevelClassPath = string.sub(level_path, 1, -2) .. "_C'"
    gameInstance.fightMsg = { boss_id = self.selectedBoss }
    gameInstance.fightType = gameInstance.FIGHT_STATE.BOSSRUSH
    gameInstance.fightCanBack = true

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.CachedSubLevel = 'City1BusinessCenter'
    gameInstance:CachePlayInCity()

    gameInstance.UIName = "UI_BossRush_Main"
    gameInstance.UIArgs = " "
    gameInstance.IsSpecialTeamInfo = true
    gameInstance.TeamContext = {
        type = 1,
        bossId = self.selectedBoss
    }
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    controller:LoadFightBeforeInCity()
end

local BOSS_ICON_S_PATH = '/Game/_Game/TP_New/TotalWar_res/Frames/TotalWar_Level%d_S_png.TotalWar_Level%d_S_png'

function M:SetupBoss()
    local bossIds = BossRushController:GetInstance():GetBoss()
    self.BossTitle = {}
    self.BossTitleGroup:ResetToggleState()
    for _, bossId in ipairs(bossIds) do
        if bossId ~= 0 then
            ---@type UI_BossRush_BossTitle_C
            local bossTitle = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_BossTitle)

            local recordedDifficulty = BossRushController:GetInstance():GetPlayerDifficulty(bossId)

            self.BossTab:AddChild(bossTitle)

            local iconPath = string.format(BOSS_ICON_S_PATH, recordedDifficulty, recordedDifficulty)
            bossTitle.Icon:SetBrushFromAtlasInterface(LoadObject(iconPath), false)

            local bossConfig = BossRushController:GetInstance():GetBossConfig(bossId, recordedDifficulty)
            bossTitle.Name:SetText(Database.L10n(bossConfig.name))

            bossTitle.BossCheckBox.CheckBoxGroup = self.BossTitleGroup
            bossTitle.BossCheckBox.OnCheckStateChanged:Add(self, function(self, isOn)
                if isOn then
                    self:SwitchTo(bossId, recordedDifficulty)
                end
            end)
            self.BossTitle[bossId] = bossTitle
        end
    end
end

function M:ShowLeaderboard(bossId)
    ---@type UI_BossRush_Leaderboard_C
    local leaderboard = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_Leaderboard)

    UIManager:GetInstance():AddUI(leaderboard)

    leaderboard:Setup(bossId)
end

function M:OpenMainLeaderboard()
    self:ShowLeaderboard()
end

function M:OpenSubLeaderboard()
    self:ShowLeaderboard(self.selectedBoss)
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

function M:ShowHelp()
    UIUtils.ShowSystemDes(1005)
end

function M:Back()
    if self.MainPage:GetVisibility() ~= UE.ESlateVisibility.Hidden then
        self:vfx_Out()
    else
        self:vfx_DetailToMain()
    end
end

function M:Setup()
    local bossIds = BossRushController:GetInstance():GetBoss()
    local firstBossId = bossIds[1]

    self:SetupBoss()

    self.PlayerScore:SetText(BossRushUtils.FormatRichText(BossRushController:GetInstance():GetPlayerTotalScore()))

    self.BossTitle[firstBossId].BossCheckBox:SetIsCheckedAndFireEvent(true)

    self.SetBack.OnClicked:Add(self, self.Back)

    self.Help.OnClicked:Add(self, self.ShowHelp)

    self.OpenLeaderboard.OnClicked:Add(self, self.OpenMainLeaderboard)

    self.OpenBossLeaderboard.OnClicked:Add(self, self.OpenSubLeaderboard)

    BossRushController:GetInstance():RequestLeaderboard()

    self:UpdateBossLeaderboard()
    self:UpdateLeaderboard()

    if BossRushController:GetInstance():RewardsAvailable() then
        self.showRewards = true
        Client.send(Protos.REQ_RECEIVE_TOTAL_WAR_REWARD)
    end

    self:vfx_In()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Back)

return M
