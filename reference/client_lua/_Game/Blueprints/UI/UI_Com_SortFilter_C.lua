--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"

---@type UI_Com_SortFilter_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.OrderUp = true
    self.DefaultSort = UIUtils.ESortType.Star
    self.SortButton.OnGHSClicked:Add(self, self.OnClick_Sort_Button)
    self.SortOrderButton.OnGHSClicked:Add(self, self.OnClick_Sort_Order)
    self.FilterButton.OnGHSClicked:Add(self, self.OnClick_Sort_Filter)
    self.SortList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized(item, widget)
    end)
    self.SortList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)
end

function M:Destruct()
    if self.FilterPanel then
        self.FilterPanel:RemoveFromParent()
    end
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:RefreshData(data)
    self.sortData = {}
    self.FilterData = {}
    self.SelectedSortIndex = 0
    if data then
        self.sortData = data
        local itemDataSource = {}
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        for key, value in pairs(self.sortData.sortTypes) do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = key        -- type index
            ItemData.ItemId = value     -- sort type
            table.insert(itemDataSource, ItemData)
        end
        self.SortList:ClearListItems()
        self.SortList:BP_SetListItems(itemDataSource)
        self.SortText:SetText(Database.L10n(287))
        self.SortList:SetVisibility(UE.ESlateVisibility.Hidden)

        self.OrderUp = true
        self.ordericon_up:SetVisibility(UE.ESlateVisibility.Visible)
        self.ordericon_down:SetVisibility(UE.ESlateVisibility.Hidden)

        self.FilterButton:SetVisibility(data.canFilter and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end
end

function M:GetSortData()
    local sortData = {}
    sortData.selectedSortType = self.sortData.sortTypes[self.SelectedSortIndex] or UIUtils.ESortType.Star
    sortData.sortOrderUp = self.OrderUp
    return sortData
end

function M:BP_OnEntryInitialized(item, widget)
    widget.SelectedBg:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.SelectedText:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.DefaultBg:SetVisibility(UE.ESlateVisibility.Visible)
    widget.DefaultText:SetVisibility(UE.ESlateVisibility.Visible)
    if item.ItemId == UIUtils.ESortType.Type then
        widget.DefaultText:SetText(Database.L10n(288))
        widget.SelectedText:SetText(Database.L10n(288))
    elseif item.ItemId == UIUtils.ESortType.Level then
        widget.DefaultText:SetText(Database.L10n(289))
        widget.SelectedText:SetText(Database.L10n(289))
    elseif item.ItemId == UIUtils.ESortType.Star then
        self.SelectedSortIndex = item.Index
        widget.DefaultText:SetText(Database.L10n(287))
        widget.SelectedText:SetText(Database.L10n(287))
        widget.SelectedBg:SetVisibility(UE.ESlateVisibility.Visible)
        widget.SelectedText:SetVisibility(UE.ESlateVisibility.Visible)
        widget.DefaultBg:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.DefaultText:SetVisibility(UE.ESlateVisibility.Hidden)
    elseif item.ItemId == UIUtils.ESortType.Talent then
        widget.DefaultText:SetText(Database.L10n(290))
        widget.SelectedText:SetText(Database.L10n(290))
    elseif item.ItemId == UIUtils.ESortType.DEF then
        widget.DefaultText:SetText(Database.L10n(291))
        widget.SelectedText:SetText(Database.L10n(291))
    elseif item.ItemId == UIUtils.ESortType.Attack then
        widget.DefaultText:SetText(Database.L10n(292))
        widget.SelectedText:SetText(Database.L10n(292))
    end
end

function M:BP_OnItemClicked(item)
    if self.SelectedSortIndex == item.Index then
        self.SortList:SetVisibility(UE.ESlateVisibility.Hidden)
        return 
    end
    local lastIndex = self.SelectedSortIndex
    self.SelectedSortIndex = item.Index
    local widgets = self.SortList:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if i == lastIndex then
            widget.SelectedBg:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.SelectedText:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.DefaultBg:SetVisibility(UE.ESlateVisibility.Visible)
            widget.DefaultText:SetVisibility(UE.ESlateVisibility.Visible)
        elseif i == self.SelectedSortIndex then
            widget.SelectedBg:SetVisibility(UE.ESlateVisibility.Visible)
            widget.SelectedText:SetVisibility(UE.ESlateVisibility.Visible)
            widget.DefaultBg:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.DefaultText:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
    self.SortList:SetVisibility(UE.ESlateVisibility.Hidden)
    if item.ItemId == UIUtils.ESortType.Type then
        self.SortText:SetText(Database.L10n(288))
    elseif item.ItemId == UIUtils.ESortType.Level then
        self.SortText:SetText(Database.L10n(289))
    elseif item.ItemId == UIUtils.ESortType.Star then
        self.SortText:SetText(Database.L10n(287))
    elseif item.ItemId == UIUtils.ESortType.Talent then
        self.SortText:SetText(Database.L10n(290))
    elseif item.ItemId == UIUtils.ESortType.DEF then
        self.SortText:SetText(Database.L10n(291))
    elseif item.ItemId == UIUtils.ESortType.Attack then
        self.SortText:SetText(Database.L10n(292))
    end
    self.OnFinishedSort:Broadcast(self)
end

function M:OnClick_Sort_Button()
    --UIUtils.ShowNotify(self, Database.L10n(50500))
    if self.SortList:IsVisible() then
        self.SortList:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.SortList:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    end
end

function M:OnClick_Sort_Order()
    self.OrderUp = not self.OrderUp
    self.ordericon_up:SetVisibility(self.OrderUp and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.ordericon_down:SetVisibility(self.OrderUp and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.OnFinishedSort:Broadcast(self)
end

function M:OnClick_Sort_Filter()
    if not self.FilterPanel then
        local widget_class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Com_FilterMenu.UI_Com_FilterMenu_C")
        self.FilterPanel = UE4.UWidgetBlueprintLibrary.Create(self, widget_class)
        self.FilterPanel.CancelButton.OnGHSClicked:Add(self, self.OnClick_Cancel)
        self.FilterPanel.OKButton.OnGHSClicked:Add(self, self.OnClick_OK)
        self.FilterPanel:RefreshUI(self.sortData.filterTypes, self.FilterData)
        self.FilterPanel:AddToViewport(100)
    end
end

function M:OnClick_Cancel()
    self.FilterPanel:RemoveFromParent()
    self.FilterPanel = nil
end

function M:OnClick_OK()
    self.FilterData = self.FilterPanel.FilterData
    self.OnFinishedFilter:Broadcast(self)
    self.FilterPanel:RemoveFromParent()
    self.FilterPanel = nil
end

return M
