--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local d_story_tree = require("ClientDatas.d_story_tree")
local d_story_node = require("ClientDatas.d_story_node")
local PlotSystem = require "Module.Plot.PlotSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SelectTree_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self:InitUI()
    self.IsBadEnd = false
end

function M:Destruct()
end

function M:InitUI()
    self.Exit.OnClicked:Add(self, self.OnClicked_Exit)
    self.ExplainBtn.OnGHSClicked:Add(self, self.OnClicked_ExplainBtn)
    
    self.ListView_Scroll.BP_OnEntryInitialized:Clear()
    self.ListView_Scroll.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized(item, widget)
    end)

    self.ListView_Scroll.BP_OnFinishedScrolling:Add(self, function(wbp)
        self:BP_OnFinishedScrolling()
    end)

    self.ListView_Scroll:SetScrollbarVisibility(UE.ESlateVisibility.Hidden)

    self.ListView_Scroll.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    self.Now.OnClicked:Add(self, self.OnClicked_NowButton)

    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local itemDataSource = {}
    
    for key, value in pairs(d_story_tree) do
        local itemData = NewObject(ItemClass)
        itemData.Index = key
        table.insert(itemDataSource, itemData)
    end
    self.ListView_Scroll:ClearListItems()
    self.ListView_Scroll:BP_SetListItems(itemDataSource)
    self.ListView_Scroll:SetScrollOffset(0)
end

function M:BP_OnEntryInitialized(item, widget)
    widget.Index = item.Index
    widget.DetailPanel:SetVisibility(UE.ESlateVisibility.Collapsed)
    local size = UE.FVector2D(530 * 0.85, 900 * 0.85)
    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.UI_Tree):SetSize(size)
    local tree_data = d_story_tree[widget.Index]
    local node_data = d_story_node[widget.Index]
    widget.UI_Tree.TextNameLock:SetText(Database.L10n(tree_data.name))
    widget.UI_Tree.TextNameUnLock:SetText(Database.L10n(tree_data.name))
    widget.UI_Tree.TextNameComplete:SetText(Database.L10n(tree_data.name))
    
    widget.UI_Tree.Complete:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.OKButton.OnClicked:Clear()
    widget.OKButton.OnClicked:Add(self, self.OnClicked_OKButton)

    --剧情树状态
    if #node_data.key > 0 then
        widget.UI_Tree.Lock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        widget.UI_Tree.UnLock:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        widget.UI_Tree.Lock:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.UI_Tree.UnLock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    end

    --奖励
    local award_id = 0
    local plot_info = PlotSystem:GetInstance().PlotInfo
    for _, plot_tree_info in ipairs(plot_info.plot_tree_infos) do
        if plot_tree_info.plot_tree_id == tree_data.id then
            award_id = plot_tree_info.received_award_ids[#plot_tree_info.received_award_ids]
        end
    end
    widget.TextProgress:SetText(award_id .. '/' .. #tree_data.number)

    if widget.Index == self.SelectedIndex then
        widget.DetailPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        local size = UE.FVector2D(530, 900)
        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.UI_Tree):SetSize(size)
        widget.UI_UnLock:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.UI_Desc.TextDesc:SetText(Database.L10n(tree_data.desc))
    else
        widget.DetailPanel:SetVisibility(UE.ESlateVisibility.Collapsed)
        local size = UE.FVector2D(530 * 0.85, 900 * 0.85)
        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.UI_Tree):SetSize(size)
    end
    widget:PlayAnimation(widget.In)
end

function M:BP_OnItemClicked(item)
    local screenPos = UE.UWidgetLayoutLibrary.GetMousePositionOnViewport(self)
    local widgets = self.ListView_Scroll:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.Index == item.Index then
            widget:PlayAnimation(widget.selected)
            local data = d_story_tree[widget.Index]
            widget.DetailPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            -- local size = UE.FVector2D(530, 900)
            -- UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.UI_Tree):SetSize(size)
            widget.UI_UnLock:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.UI_Desc.TextDesc:SetText(Database.L10n(data.desc))
            self.SelectedIndex = widget.Index
        else
            widget.DetailPanel:SetVisibility(UE.ESlateVisibility.Collapsed)
            local size = UE.FVector2D(530 * 0.85, 900 * 0.85)
            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.UI_Tree):SetSize(size)
        end
    end
end

function M:OnClicked_OKButton()
    self.selectNodePanel = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_SelectNode')
    self.selectNodePanel:RefreshUI(self.SelectedIndex)
end

function M:OnClicked_NowButton()
    local plot_info = PlotSystem:GetInstance().PlotInfo
    self.selectNodePanel = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_SelectNode')
    self.selectNodePanel:RefreshUI(plot_info.plot_tree_id)
end

function M:BP_OnFinishedScrolling()
    print('OnFinishedScrolling')
    local curScrollOffset = self.ListView_Scroll:GetScrollOffset()
    local _, modNUm = math.modf(curScrollOffset)
    local newOffset = modNUm < 0.45 and math.floor(curScrollOffset) or math.ceil(curScrollOffset)
    --newOffset = UE.UKismetMathLibrary.Clamp(newOffset, 0, self.MaxIndex)
    self.ListView_Scroll:SetScrollOffset(newOffset)
end

function M:OnClicked_Exit()
    if not self.IsBadEnd then
        UIManager:GetInstance():RemoveUI(self)
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:OnClicked_ExplainBtn()
    UIUtils.ShowSystemDes(1003)
end

return M
