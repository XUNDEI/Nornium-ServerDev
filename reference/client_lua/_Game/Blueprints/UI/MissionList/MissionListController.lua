local MissionList = require "_Game.Blueprints.UI.MissionList.MissionList"
local Database = require("_Game.Utils.Database")
local MissionEntry = require("_Game.Blueprints.UI.MissionList.MissionEntry")

local MissionListController = BaseClass("MissionListController")

---@param ParentCanvas UCanvasPanel
function MissionListController:__init(ParentCanvas)
    self.parentCanvas = ParentCanvas

    self.missionList = MissionList.New()

    self.parentCanvas:AddChildToCanvas(self.missionList.widget)

    -- CanvasPanvel没有自动布局，只能手动设下位置
    local anchors = UE.FAnchors()
    local offsets = UE.FMargin()

    -- 目前FAnchors的构造函数没有导出
    anchors.Minimum = UE.FVector2D(0, 0)
    anchors.Maximum = UE.FVector2D(1, 1)

    self.missionList.widget.Slot:SetAnchors(anchors)
    self.missionList.widget.Slot:SetOffsets(offsets)

    self.missionEntries = {}
end

function MissionListController:SetUp()
    -- 固定文本
    self.missionList.widget.MissionSourceTitle:SetText(DataBase.L10n(118000010))
    self.missionList.widget.AcquiredDateTitle:SetText(DataBase.L10n(118000011))
    self.missionList.widget.RewardTitle:SetText(DataBase.L10n(118000012))
    self.missionList.widget.CurrentMissionTitle:SetText(DataBase.L10n(118000013))
    self.missionList.widget.CompletedMissionTitle:SetText(DataBase.L10n(118000014))

    self.missionList.widget.MissionInfo:SetVisibility(UE.ESlateVisibility.Hidden)

    self.close = function()
        self.missionList.widget:SetVisibility(UE.ESlateVisibility.Hidden)
        self.parentCanvas:RemoveChild(self.missionList.widget)
    end

    self.missionList.widget.Close.OnClicked:Add(self.missionList.widget.Close, self.close)

    self.missionList.widget.CurrentMission.OnCheckStateChanged:Add(self.missionList.widget, function()
        self:RefreshMissionList(0)
    end)

    self.missionList.widget.CompletedMission.OnCheckStateChanged:Add(self.missionList.widget, function()
        self:RefreshMissionList(1)
    end)

    self.missionList.widget.CurrentMission:SetIsCheckedAndFireEvent(true)
    self.missionList.widget.CurrentMission.OnCheckStateChanged:Broadcast(true)
end

function MissionListController:RefreshMissionList(FilterResult)
    self.missionList.widget.MissionInfo:SetVisibility(UE.ESlateVisibility.Hidden)
    self:ClearMissionList()
    self:UpdateMissionList(FilterResult)
end

function MissionListController:ClearMissionList()
    for _, missionEntry in pairs(self.missionEntries) do
        self.missionList.widget.Content:RemoveChild(missionEntry.widget)
    end

    self.missionEntries = {}
end

function MissionListController:UpdateMissionInfo(MissionEntry)
    local missionInfo = MissionEntry.missionInfo
    local missionConfig = Database.Query("d_srpg_mission", missionInfo.mission_id)

    self.missionList.widget.MissionSourceText:SetText(Database.L10n(missionConfig.sourceId))
    self.missionList.widget.Description:SetText(Database.L10n(missionConfig.descrId))
    self.missionList.widget.RewardText:SetText(Database.L10n(missionConfig.rewardId))

    self.missionList.widget.AcquiredDateText:SetText(string.format("%d %d", missionInfo.mission_begin_turn,
        missionInfo.mission_begin_step))

    self.missionList.widget.MissionInfo:SetVisibility(UE.ESlateVisibility.Visible)
end

function MissionListController:UpdateMissionList(FilterResult)
    FilterResult = FilterResult or 0
    
    local missionInfos = UE.UGameplayStatics.GetGameInstance(self.parentCanvas).resUniverse.res_universe.universe_info.mission_infos

    self.updateMissionInfo = function(MissionEntryWidget, IsChecked)
        if IsChecked then
            for _, missionEntry in pairs(self.missionEntries) do
                if missionEntry.widget == MissionEntryWidget then
                    self:UpdateMissionInfo(missionEntry)
                    break
                end
            end
        end
    end

    self.missionList.widget.MissionListGroup:ResetToggleState()
    for _, missionInfo in pairs(missionInfos) do
        if missionInfo.mission_result == FilterResult then
            local missionEntry = MissionEntry.New(missionInfo)

            self.missionList.widget.Content:AddChild(missionEntry.widget)

            missionEntry:SetUp()

            missionEntry.widget.CheckBox.CheckBoxGroup = self.missionList.widget.MissionListGroup

            missionEntry.widget.CheckBox.OnCheckStateChanged:Add(missionEntry.widget, self.updateMissionInfo)

            table.insert(self.missionEntries, missionEntry)
        end
    end
end

return MissionListController
