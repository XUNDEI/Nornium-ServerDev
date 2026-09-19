--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"

---@type UI_Sweep_Settlement_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

-- function M:Construct()
-- end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitUI()
    self.ItemList:ClearListItems()
    self.Btn_Sure.OnGHSClicked:Add(self, self.OnClick_Sure)

    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    self.ItemDataSource = {}
    for i = 1, #self.changed_item_infos do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = i
        ItemData.ItemId = self.changed_item_infos[i].item_id
        table.insert(self.ItemDataSource, ItemData)
    end
    self.ItemList:BP_SetListItems(self.ItemDataSource)

    self.ItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized(item, widget)
    end)
    self.ItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)
    self:PlayAnimationForward(self.vfxIn)
end

function M:BP_OnEntryInitialized(item, widget)
    local itemConfig = UIUtils.GetItemConfigById(item.ItemId)
    local data = {}
    data.config = itemConfig
    widget.index = item.index
    widget.item_data = itemConfig
    if itemConfig then
        --稀有度背景图片
        if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
            local strArr = string.split(itemConfig.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/%s.%s', itemConfig.rarityPath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                widget.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end
        
        --类型
        --icon
        if itemConfig.iconPath and itemConfig.iconPath ~= '' then
            widget.wp_icon_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            local strArr = string.split(itemConfig.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                widget.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        else
            widget.wp_icon_res:SetVisibility(UE.ESlateVisibility.Collapsed)
        end
        widget.Text_Count:SetText(self.changed_item_infos[item.Index].count)
    end
end

function M:BP_OnItemClicked(item)
    UIUtils.ShowItemInfo(item.ItemId, self.changed_item_infos[item.Index].count)
end

function M:OnClick_Sure()
    self:BindToAnimationFinished(self.vfxExit, function()
        self.backUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationForward(self.vfxExit)
end

function M:SetBackUI(backUI, changed_item_infos)
    self.backUI = backUI
    if self.backUI then
        self.backUI:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    self.changed_item_infos = changed_item_infos
    self:InitUI()
end

return M
