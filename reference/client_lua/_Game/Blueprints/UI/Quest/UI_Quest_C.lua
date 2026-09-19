local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local QuestSystem = require "Module.Quest.QuestSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Login_C
local M = UnLua.Class()

M.HideCursor = false
M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitUI()
    self:InitData()
    self.Overridden.Construct(self)
    MessageManager:GetInstance():AddListener("OnMsg_RefreshDailyMission", self)
    MessageManager:GetInstance():AddListener("OnMsg_CompleteDailyMission", self)
    MessageManager:GetInstance():AddListener("OnMsg_Refresh_Plot_Mission", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_RefreshDailyMission", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_CompleteDailyMission", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Refresh_Plot_Mission", self)
end

function M:OnMsg_RefreshDailyMission(questInfo)
    if questInfo then
        self.LastSelectedItemData.ID = questInfo.mission_id
        self.QuestDataList = self:GetQuestDataList(self.SelectedTabIndex)
        local itemUI = self:GetItem(self.LastSelectedItemData)
        if itemUI then
            self:BP_OnEntryInitialized(self.LastSelectedItemData, itemUI)
            self:RefreshQuestPanel()
        end
    else
        self:RefreshTab()
    end
end

function M:OnMsg_Refresh_Plot_Mission()
    self:RefreshTab()
end

function M:OnMsg_CompleteDailyMission(questId)
    self.bReqComplete = false
    if self.LastSelectedItemData.Id == questId then
        local config = QuestSystem:GetInstance():GetTaskConfigById(questId)
        if config then
            local rewardList = {}
            for i = 1, #config.reward, 3 do 
                local itemId = config.reward[i]
                local count = config.reward[i + 2]
                table.insert(rewardList, {
                    itemId = itemId,
                    count = count,
                })
            end
            UIUtils.ShowGetRewardCommonUI(self, rewardList)
        end
        self.QuestDataList = self:GetQuestDataList(self.SelectedTabIndex)
        local itemUI = self:GetItem(self.LastSelectedItemData)
        if itemUI then
            self:BP_OnEntryInitialized(self.LastSelectedItemData, itemUI)
            self:RefreshQuestPanel()
        end
    end
end 

function M:InitData()
    --默认选中角色tab
    self.SelectedTabIndex = UIUtils.ETaskType.None
    self.UI_QuestTab.ProgressTab:SetIsCheckedAndFireEvent(true)
    self.SelectedItemIndex = 0

    self:RefreshTab()
end

function M:InitUI()
    self.Btn_Exit.OnGHSClicked:Add(self, self.OnClicked_Btn_Exit)

    self.UI_QuestTab.ProgressTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_ProgressTab)
    self.UI_QuestTab.MainTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_MainTab)
    self.UI_QuestTab.IFTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_IFTab)
    self.UI_QuestTab.DailyTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_DailyTab)

    self.ExplainBtn.OnGHSClicked:Add(self, self.OnClicked_ExplainBtn)

    self.TreeView.BP_OnEntryInitialized:Add(self, function(wbp, data, ui)
        self:BP_OnEntryInitialized(data, ui)
    end)

    self.TreeView.BP_OnItemExpansionChanged:Add(self, function(wbp, data, expand)
        self:BP_OnItemExpansionChanged(data, expand)
    end)

    self.TreeView.BP_OnItemClicked:Add(self, function(wbp, data)
        self:BP_OnItemClicked(data)
    end)

    self.UI_QuestReward.ListView_Reward.BP_OnEntryInitialized:Add(self, function(wbp, data, ui)
        self:BP_OnEntryInitialized_Reward(data, ui)
    end)
    self.UI_QuestReward.ListView_Reward.BP_OnItemClicked:Add(self, function(wbp, data)
        self:BP_OnItemClicked_Reward(data)
    end)

    self.Btn_Trace.OnGHSClicked:Add(self, self.OnClicked_Btn_Trace)
    self.Btn_Reward.OnGHSClicked:Add(self, self.OnClicked_Btn_Reward)
    self.Btn_Refresh.OnGHSClicked:Add(self, self.OnClicked_Btn_Refresh)

    --播放入场动画
    self:PlayAnimationForward(self.In, 1.0, false)
    self.UI_QuestTab:PlayAnimationForward(self.UI_QuestTab.In, 1.0, false)

    self.InitIsBlock = false
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not pc.BP_PlayerController_City_UniverseBridge.BlockInputAction then
        pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
        self.InitIsBlock = true
    end
end

function M:GetQuestDataList(tabIndex)
    local taskList = {}
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local isOpen, _ = gameInstance:OpenLinkEx(9012, true)
    local questInfo = QuestSystem:GetInstance().QuestInfo
    for id, v in pairs(questInfo) do
        local config = QuestSystem:GetInstance():GetTaskConfigById(id)
        if config then
            v.config = config
            if not config.dominantType or config.dominantType == 1 then
                if config.taskType == UIUtils.ETaskType.Tutorial and (tabIndex == 0 or tabIndex == 2) then --教学
                    if not v.completed and not v.finished then
                        if not taskList[2] then
                            taskList[2] = {}
                        end
                        table.insert(taskList[2], v)
                    end
                elseif tabIndex == 0 or (config.taskType == tabIndex) then
                    if config.taskType == UIUtils.ETaskType.Main then
                        if not v.completed and not v.finished then
                            if not taskList[config.taskType] then
                                taskList[config.taskType] = {}
                            end
                            table.insert(taskList[config.taskType], v)
                        end
                    else
                        if config.taskType == UIUtils.ETaskType.Daily and not isOpen then

                        else
                            if not taskList[config.taskType] then
                                taskList[config.taskType] = {}
                            end
                            table.insert(taskList[config.taskType], v)
                        end
                    end
                end
            end
        end
    end
    for _, v in pairs(taskList) do
        if #v > 1 then
            table.sort(v, function(a, b)
                return a.mission_id < b.mission_id
            end)
        end
    end
   
    return taskList
end

function M:RefreshTab()
    local trackQuestId = QuestSystem:GetInstance().TrackQuestId
    --print("==trackQuestId:" .. tostring(trackQuestId))
    self.QuestDataList = self:GetQuestDataList(self.SelectedTabIndex)
    --print("==self.QuestDataList:" .. tostring(table.dump(self.QuestDataList, nil, 10)))

    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Quest/UI_Data/BP_QuestData.BP_QuestData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)

    self.LastSelectedItemData = nil
    self.ExpanedItemData = nil

    local questList = {}
    if self.SelectedTabIndex == 0 then
        for _, v in pairs(self.QuestDataList) do
            for _, quest in pairs(v) do
                table.insert(questList, quest)
            end
        end
    else
        questList = self.QuestDataList[self.SelectedTabIndex] or {}
    end
    
    if #questList > 1 then
        table.sort(questList, function(a, b)
            if a.config.taskType > b.config.taskType then
                return true
            elseif a.config.taskType == b.config.taskType then
                return a.mission_id < b.mission_id
            end

            return false
        end)
    end

    self.TreeView:ClearListItems()

    if #questList > 0 then
        for idx, quest in ipairs(questList) do
            local childItemData = NewObject(ItemClass)
            childItemData.Index = idx --quest.taskType
            childItemData.ID = quest.mission_id
            childItemData.Layer = 2
            -- itemData.Children:Add(childItemData)
            self.TreeView:AddItem(childItemData)
            if self.SelectedItemIndex > 0 then
                if self.SelectedItemIndex == idx then
                    self.LastSelectedItemData = childItemData
                end
            elseif (trackQuestId > 0 and trackQuestId == quest.mission_id) then
                self.LastSelectedItemData = childItemData
                self.SelectedItemIndex = idx
            elseif idx == 1 then
                if not self.LastSelectedItemData then
                    self.LastSelectedItemData = childItemData
                end
            end
        end
    end

    if self.LastSelectedItemData then
        if not self.ExpanedItemData then 
            self.ExpanedItemData = self.LastSelectedItemData
        end
    end
    if self.ExpanedItemData then
        self.TreeView:SetItemExpansion(self.ExpanedItemData, true)
    end
    self:RefreshQuestPanel()
end

function M:GetQuestData(id)
    if self.QuestDataList then
        for _, questList in pairs(self.QuestDataList) do
            for _, quest in ipairs(questList) do
                if quest.mission_id == id then
                    return quest
                end
            end
        end
    end
    return nil
end

function M:RefreshQuestPanel()
    self.UI_QuestReward.ListView_Reward:ClearListItems()

    if self.LastSelectedItemData then
        self.Panel_Quest:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        print("---------------RefreshQuestPanel:" .. tostring(self.LastSelectedItemData.ID) .. ",index:" .. tostring(self.SelectedItemIndex))
        local questData = self:GetQuestData(self.LastSelectedItemData.ID)

        local config = QuestSystem:GetInstance():GetTaskConfigById(self.LastSelectedItemData.ID)
        -- print("============task config:" .. tostring(table.dump(config, nil, 10)))
        local bRefreshVisible = config.taskType == UIUtils.ETaskType.Daily

        --刷新次数
        local canRefresh = QuestSystem:GetInstance().DailyLastRefreshSeconds == 0
        self.Text_RefreshCount:SetText(canRefresh and '1/1' or '0/1')
        bRefreshVisible = bRefreshVisible and canRefresh
        -- self.Panel_Refresh:SetVisibility(bRefreshVisible and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        self.Panel_Refresh:SetVisibility(UE.ESlateVisibility.Hidden)

        if questData and config then
            self.Img_Bg_1:SetVisibility(config.taskType == UIUtils.ETaskType.Daily and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            self.Img_Bg_2:SetVisibility((config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            self.Img_Bg_3:SetVisibility(config.taskType == UIUtils.ETaskType.Sub and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

            self.Text_Title:SetText(Database.L10n(config.taskTitle))
            self.Text_QuestDes:SetText(Database.L10n(config.taskDetails))
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
                    self.Text_QuestTarget:SetText(Database.L10n(config.taskTarget))
                else
                    self.Text_QuestTarget:SetText(Database.L10n(config.taskTarget) .. '(' .. questData.DoneCount .. '/' .. questData.AllCount .. ')')
                end
            else
                self.Text_QuestTarget:SetText(string.format(Database.L10n(config.taskTarget), table.unpack(config.taskNumber)) .. '(' .. questData.DoneCount .. '/' .. questData.AllCount .. ')')
            end
            --奖励列表
            self.RewardList = {}
            for i = 1, #config.reward, 3 do 
                local itemId = config.reward[i]
                local count = config.reward[i + 2]
                table.insert(self.RewardList, {
                    itemId = itemId,
                    count = count,
                })
            end

            local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Character/UI_Data/BP_ListItemData.BP_ListItemData_C'
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            local itemDataSource = {}
            for idx, reward in ipairs(self.RewardList) do 
                local itemData = NewObject(ItemClass)
                itemData.Index = idx
                itemData.Id = reward.itemId 
                table.insert(itemDataSource, itemData)
            end
            self.UI_QuestReward.ListView_Reward:BP_SetListItems(itemDataSource)

            local isGetReward = questData.completed
            --self.Panel_Getted:SetVisibility(isGetReward and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            self.UI_QuestReward.Img_Got:SetVisibility(isGetReward and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            self.UI_QuestReward.Text_Got:SetVisibility(isGetReward and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

            local isComplete = false
            if not questData.completed then
                isComplete = questData.DoneCount >= questData.AllCount
            end
            -- self.Panel_Refresh:SetVisibility((bRefreshVisible and not isGetReward and not isComplete) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            self.Btn_Reward:SetVisibility(isComplete and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            self.Btn_trace:SetVisibility(UE.ESlateVisibility.Hidden)
            if not isGetReward and not isComplete then
                local questId = QuestSystem:GetInstance().TrackQuestId
                local isTraced = (questId and questId == self.LastSelectedItemData.ID)
                self.Image_1:SetVisibility(isTraced and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
                self.Text_Trace:SetVisibility(isTraced and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
                self.Text_Trace_Cancle:SetVisibility(isTraced and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
                self.Btn_trace:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            end
        end
    else
        self.Text_Title:SetText("")
        self.Text_QuestDes:SetText("")
        self.Text_QuestTarget:SetText("")

        self.Btn_trace:SetVisibility(UE.ESlateVisibility.Hidden)

        self.Panel_Quest:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

----------------------------------------------------------------------------------
---UI Event
--总览页签
function M:OnCheckStateChanged_ProgressTab(isOn)
    if not isOn then return end
    self.UI_QuestTab:PlayAnimationForward(self.UI_QuestTab['vfx1'], 1.0, false)
    self:OnTabCheckStateChanged(0)
end

--主线
function M:OnCheckStateChanged_MainTab(isOn)
    if not isOn then return end
    self.UI_QuestTab:PlayAnimationForward(self.UI_QuestTab['vfx2'], 1.0, false)
    self:OnTabCheckStateChanged(2)
end

--支线
function M:OnCheckStateChanged_IFTab(isOn)
    if not isOn then return end
    self.UI_QuestTab:PlayAnimationForward(self.UI_QuestTab['vfx3'], 1.0, false)
    self:OnTabCheckStateChanged(3)
end

--日常
function M:OnCheckStateChanged_DailyTab(isOn)
    if not isOn then return end
    self.UI_QuestTab:PlayAnimationForward(self.UI_QuestTab['vfx4'], 1.0, false)
    self:OnTabCheckStateChanged(1)
end

function M:OnTabCheckStateChanged(index)
    if self.SelectedTabIndex ~= index then
        self.SelectedTabIndex = index
        self:RefreshTab()
    end
end

function M:OnClicked_Btn_Exit()
    if self.InitIsBlock then
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        self.InitIsBlock = false
    end
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Exit)

function M:BP_OnEntryInitialized(data, ui)
    ui.Index = data.Index
    ui.Layer = data.Layer
    ui.ID = data.ID

    ui.Panel_QuestType:SetVisibility(data.Layer == 0 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    ui.Panel_Chapter:SetVisibility(data.Layer == 1 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    ui.Panel_Quest:SetVisibility(data.Layer == 2 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)

    if data.Layer == 0 then
        ui.Text_QuestType:SetText(UIUtils.GetTaskTypeName(data.Index) .. '任务')
    end

    local config = QuestSystem:GetInstance():GetTaskConfigById(data.ID)
    ui.Text_Quest:SetText(config and Database.L10n(config.taskTitle) or "None")

    self:RefreshItem(ui, data == self.LastSelectedItemData)

    --红点提醒
    local questData = self:GetQuestData(data.ID)
    if questData and not questData.completed and questData.finished then
        ui.Img_RedPoint_Task:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    else
        ui.Img_RedPoint_Task:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

function M:BP_OnItemExpansionChanged(data, expand)
    local layer = data.Layer
    if layer == 1 then
        local ui = self:GetItem(data)
        if ui then

        end
    end
end

function M:BP_OnItemClicked(data)
    if data.Layer ~= 2 or self.LastSelectedItemData == data then return end
    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshItem(ui, false)
        end
    end
    self.LastSelectedItemData = data
    self.SelectedItemIndex = data.Index
    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshItem(ui, true)
        end
    end
    self:RefreshQuestPanel()
end

function M:GetItem(itemData)
    local widgets = self.TreeView:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.Index == itemData.Index and widget.Layer == itemData.Layer and widget.ID == itemData.ID then
            return widget
        end
    end
    return nil
end

function M:RefreshItem(ui, selected)
    ui.Img_Chapter_Selected:SetVisibility(selected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    ui.Img_Quest_Selected:SetVisibility(selected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    ui.Img_Quest_Selected1:SetVisibility(selected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
end

function M:BP_OnEntryInitialized_Reward(data, ui)
    local itemData = self.RewardList[data.Index]
    itemData.config = UIUtils.GetItemConfigById(itemData.itemId)

    --稀有度背景图片
    if itemData.config.rarityPath and itemData.config.rarityPath ~= '' then
        local strArr = string.split(itemData.config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', itemData.config.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            ui.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    local hasMat = itemData.count > 0
    if hasMat then
        ui.lackState:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.wp_icon_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        --icon
        if itemData.config.iconPath and itemData.config.iconPath ~= '' then
            local strArr = string.split(itemData.config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                ui.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        end
    else
        ui.wp_icon_res:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.lackState:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        --icon
        if itemData.config.iconPath and itemData.config.iconPath ~= '' then
            local strArr = string.split(itemData.config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                ui.lackIcon:SetBrushFromAtlasInterface(iconRes)
            end
        end
    end
   
    --个数
    ui.Text_Count:SetText(itemData.count)
end

function M:BP_OnItemClicked_Reward(item)
    local itemData = self.RewardList[item.Index]
    UIUtils.ShowItemInfo(itemData.itemId, itemData.count)
end

function M:OnClicked_Btn_Trace()
    local questId = QuestSystem:GetInstance().TrackQuestId
    if questId and questId ~= self.LastSelectedItemData.ID then
        local config = QuestSystem:GetInstance():GetTaskConfigById(self.LastSelectedItemData.ID)
        if not config then
            config = Database.Query('d_task_story', self.LastSelectedItemData.ID)
        end
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            --强制删除为空的
            -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            -- local ui = gameInstance:GetUMG('UI_City')
            -- if ui then
            --     local worldPos = UE.FVector(config.coordinate[1], config.coordinate[2], config.coordinate[3])
            --     ui:StartTrackPos(self.LastSelectedItemData.ID, true, worldPos)
            -- end
            -- QuestSystem:GetInstance():SetTrackQuestId(self.LastSelectedItemData.ID)
        end
        QuestSystem:GetInstance():SetTrackQuestId(self.LastSelectedItemData.ID)

        self.Image_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.Text_Trace:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Text_Trace_Cancle:SetVisibility(UE.ESlateVisibility.Visible)
    else
        local config = QuestSystem:GetInstance():GetTaskConfigById(self.LastSelectedItemData.ID)
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            --强制删除为空的
            -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            -- local ui = gameInstance:GetUMG('UI_City')
            -- if ui then
            --     ui:StartTrackPos("", false, nil)
            -- end
        end
        QuestSystem:GetInstance():SetTrackQuestId(0)

        self.Image_1:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Text_Trace:SetVisibility(UE.ESlateVisibility.Visible)
        self.Text_Trace_Cancle:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:OnClicked_Btn_Reward()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end

    QuestSystem:GetInstance():ReqCompletePlayerDailyMission(self.LastSelectedItemData.ID)
end

function M:OnClicked_Btn_Refresh()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    local canRefresh = QuestSystem:GetInstance().DailyLastRefreshSeconds == 0
    if canRefresh then
        QuestSystem:GetInstance():ReqRefreshPlayerDailyMission(self.LastSelectedItemData.ID)
    end
end

function M:OnClicked_ExplainBtn()
    UIUtils.ShowSystemDes(1004)
end


return M