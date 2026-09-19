--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local PlotSystem = require "Module.Plot.PlotSystem"

---@type UI_TreeReward_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.Btn_Close.OnClicked:Add(self, function()
        UIManager:GetInstance():RemoveUI(self)
    end)

    self.ListView_Reward.BP_OnEntryInitialized:Clear()
    self.ListView_Reward.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized(item, widget)
    end)
end

function M:RefreshUI(tree_id, item_data)
    self.Tree_Id = tree_id
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local itemDataSource = {}

    --local award_id = 0
    local completed_count = 0
    local plot_info = PlotSystem:GetInstance().PlotInfo
    local tree_data = Database.Query("d_story_tree", tree_id)
    -- for _, plot_tree_info in ipairs(plot_info.plot_tree_infos) do
    --     if plot_tree_info.plot_tree_id == tree_data.id then
    --         award_id = plot_tree_info.received_award_ids[#plot_tree_info.received_award_ids]
    --     end
    -- end

    for _, story_node_info in pairs(plot_info.story_node_infos[tree_id]) do
        if story_node_info.completed then
            completed_count = completed_count + 1
        end
    end

    local button_number = #tree_data.number
    for i = 1, button_number do
        local widget_class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_StoryTree/UI_TreeReward_Button.UI_TreeReward_Button_C")
        local widget = UE4.UWidgetBlueprintLibrary.Create(self, widget_class)
        self.Panel_Content:AddChild(widget)
        local slot = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget)
        slot:SetPosition(UE.FVector2D(60 + 350 * i / button_number - 67, 188))
        widget.LevelText:SetText(i)
        if i < completed_count then
            widget.ImageCurrent:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageBgUndone:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageUndone:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageBgDone:SetVisibility(UE.ESlateVisibility.Visible)
            widget.ImageDone:SetVisibility(UE.ESlateVisibility.Visible)
        elseif i == completed_count then
            widget.ImageCurrent:SetVisibility(UE.ESlateVisibility.Visible)
            widget.ImageBgUndone:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageUndone:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageBgDone:SetVisibility(UE.ESlateVisibility.Visible)
            widget.ImageDone:SetVisibility(UE.ESlateVisibility.Visible)
        else
            widget.ImageCurrent:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageBgUndone:SetVisibility(UE.ESlateVisibility.Visible)
            widget.ImageUndone:SetVisibility(UE.ESlateVisibility.Visible)
            widget.ImageBgDone:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageDone:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
    self.TextProgress:SetText(completed_count .. '/' .. button_number)
    self.ProgressBar:SetPercent(completed_count / button_number)
    
    local item_count = #item_data / 2
    for index = 1, item_count do
        local itemData = NewObject(ItemClass)
        itemData.ItemId = item_data[index]
        itemData.Index = item_data[index + 1]
        table.insert(itemDataSource, itemData)
    end
    self.ListView_Reward:BP_SetListItems(itemDataSource)
end

function M:BP_OnEntryInitialized(item, widget)
    local config = UIUtils.GetItemConfigById(item.ItemId)
    --稀有度背景图片
    if config.rarityPath and config.rarityPath ~= '' then
        local strArr = string.split(config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', config.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            widget.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if config.iconPath and config.iconPath ~= '' then
        widget.wp_icon_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local strArr = string.split(config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            widget.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    else
        widget.wp_icon_res:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    widget.Text_Count:SetText(item.Index)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

return M
