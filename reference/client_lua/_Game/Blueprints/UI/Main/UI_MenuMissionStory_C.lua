--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local QuestSystem = require "Module.Quest.QuestSystem"
local MessageManager = require "Framework.Updater.MessageManager"

---@type UI_MenuMissionStory_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.LastCheckTime = 0
    self.LastTrackQuestId = 0
    self.QuestDoneCount = 0
    self.Img_Bg.OnMouseButtonDownEvent:Bind(self, self.OnClicked_MenuMission)
    MessageManager:GetInstance():AddListener('OnMsg_MissionRecord', self)
    self:InitUI()
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener('OnMsg_MissionRecord', self)
end

function M:Tick(MyGeometry, InDeltaTime)
    self.LastCheckTime = self.LastCheckTime + InDeltaTime
    if self.LastCheckTime > 0.01 then
        self.LastCheckTime = 0
        self:CheckQuest()
    end
end

function M:InitUI()
    local TrackQuestId = QuestSystem:GetInstance().TrackQuestId
    if TrackQuestId == 0 then
        self.Btn_OpenList:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:OnClicked_MenuMission()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OpenLink(9008, "")
    return UE.UWidgetBlueprintLibrary.Handled()
end

function M:CheckQuest()
    local TrackQuestId = QuestSystem:GetInstance().TrackQuestId
    if TrackQuestId > 0 then
        if self.LastTrackQuestId ~= TrackQuestId then
            self.LastTrackQuestId = TrackQuestId
            self.Btn_OpenList:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self:RefreshQuestUI()
            self:PlayAnimationForward(self.InitAnimation)

            if self.LastTrackQuestId > 0 then
                local taskConfig = QuestSystem:GetInstance():GetTaskConfigById(self.LastTrackQuestId)
                if not taskConfig then return end
                local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                if taskConfig and taskConfig.maps and taskConfig.maps ~= '' and not gameInstance:LevelIsVisible(taskConfig.maps) then
                    return
                end
                if taskConfig and #taskConfig.coordinate < 3 then
                    return
                end
            end
        else
            return
        end
    else
        if self.LastTrackQuestId > 0 then
            self.LastTrackQuestId = 0
            self.Btn_OpenList:SetVisibility(UE.ESlateVisibility.Hidden)
            return
        end
    end
end

function M:OnMsg_MissionRecord()
    if self.LastTrackQuestId > 0 then
        self:RefreshQuestUI()
    end
end

function M:RefreshQuestUI()
    if self.LastTrackQuestId > 0 then
        local questData = QuestSystem:GetInstance():GetQuestInfo(self.LastTrackQuestId)
        local config = QuestSystem:GetInstance():GetTaskConfigById(self.LastTrackQuestId)
        if config then
            self.type:SetText(UIUtils.GetTaskTypeName(config.taskType))
            self.name:SetText(Database.L10n(config.taskTitle))
            if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
                if config.taskContent == 0
                    or config.taskContent == UIUtils.EOpenNeedType.MainQuestChapter
                    or config.taskContent == UIUtils.EOpenNeedType.Login
                    or config.taskContent == UIUtils.EOpenNeedType.HaveChar
                    or config.taskContent == UIUtils.EOpenNeedType.Dialog
                    or config.taskContent == UIUtils.EOpenNeedType.CompleteFight
                    or config.taskContent == UIUtils.EOpenNeedType.CompleteUniverseTrip
                    or config.taskContent == UIUtils.EOpenNeedType.CompleteSpecialSRPG
                    or config.taskContent == UIUtils.EOpenNeedType.SelectPanel
                    or config.taskContent == UIUtils.EOpenNeedType.STTButton
                    or config.taskContent == UIUtils.EOpenNeedType.BuildActor
                    or config.taskContent == UIUtils.EOpenNeedType.BuildCreate
                    or config.taskContent == UIUtils.EOpenNeedType.OpenUI then
                    self.desc:SetText(Database.L10n(config.taskTarget))
                else
                    self.desc:SetText(Database.L10n(config.taskTarget) .. '(' .. questData.DoneCount .. '/' .. questData.AllCount .. ')')
                end
            else
                self.desc:SetText(string.format(Database.L10n(config.taskTarget), table.unpack(config.taskNumber)) .. '(' .. questData.DoneCount .. '/' .. questData.AllCount .. ')')
            end
        end
    end
end 

return M
