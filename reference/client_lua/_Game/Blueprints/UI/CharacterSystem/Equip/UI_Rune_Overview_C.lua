--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require "_Game.Utils.Database"
local d_equip_rune = require("ClientDatas.d_equip_rune")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Rune_Overview_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterMouseEvent(M)
InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:Construct()
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
    self.ItemDataSource = {}
    self.selected_rune_id = nil
end

function M:InitUI(rune_id)
    self.selected_rune_id = rune_id
    for id, _ in pairs(d_equip_rune) do
        table.insert(self.ItemDataSource, id)
    end
    table.sort(self.ItemDataSource, function(a, b)
        return a < b
    end)
    local default_selected_index = 0
    self.GHSCheckBoxGroup:ResetToggleState()
    for index, id in pairs(self.ItemDataSource) do
        local equp_rune_info = d_equip_rune[id]
        local ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Equip/UI_Tab_Rune_Item.UI_Tab_Rune_Item_C"))
        local rune_word_name = Database.L10n(equp_rune_info.runeName)
        ui.Title:SetText(rune_word_name)
        ui.selected_title:SetText(rune_word_name)
        ui.Copy.CheckBoxGroup = self.GHSCheckBoxGroup
        ui.Copy.OnCheckStateChanged:Add(self, function(self, isOn)
            if isOn then
                self:RefreshContent(id)
            end
        end)
        self.RuneWordVerticalBox:AddChild(ui)
        if rune_id == id then
            default_selected_index = index - 1
        end
    end
    local firstItem = self.RuneWordVerticalBox:GetChildAt(default_selected_index)
    self.ScrollBox:ScrollWidgetIntoView(firstItem, false, UE.EDescendantScrollDestination.IntoView, 0)
    if firstItem then firstItem.Copy:SetIsCheckedAndFireEvent(true) end

    self.RuneTileView.BP_OnEntryInitialized:Clear()
    self.RuneTileView.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
end

function M:RefreshContent(rune_id)
    local equp_rune_info = d_equip_rune[rune_id]

    --符文列表刷新
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local attrDataSource = {}
    local itemData = NewObject(ItemClass)
    itemData.ItemId = rune_id
    table.insert(attrDataSource, itemData)
    self.RuneTileView:ClearListItems()
    self.RuneTileView:BP_SetListItems(attrDataSource)
    for i = 2, 5 do
        self['TextDesc_' .. i]:SetText(Database.L10n(equp_rune_info[i .. 'runesDesc']))
    end
    self.TextName:SetText(Database.L10n(equp_rune_info.runeName))
end

function M:BP_OnEntryInitialized(item, ui)
    local rune_info = d_equip_rune[item.ItemId]
    if rune_info then
        ui.RenuText:SetText(Database.L10n(rune_info.runeName))
        local strArr = string.split(rune_info.runeIcon, '/')
        local littePath = strArr[#strArr]
        local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
        if itemRarityPic then
            ui.RuneImage:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end
end

return M
