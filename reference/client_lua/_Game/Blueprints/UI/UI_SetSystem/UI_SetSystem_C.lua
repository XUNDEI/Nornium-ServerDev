local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SetSystem_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

InputUtils.BindClose(M)

local EResolutionType =
{
    FullScreen = 1, --无边框窗口化
    Type1920 = 2,   --1920x1080
    Type1600 = 3,   --1600x900
    Type1280 = 4,   --1280x800
    Type800 = 5,    --800x600
}

function M:Construct()
    if not M.UI_KeySelectorRef then
        M.UI_KeySelector = LoadClass('/Game/_Game/Blueprints/UI/UI_SetSystem/UI_KeySelector.UI_KeySelector_C')
        M.UI_KeySelectorRef = UnLua.Ref(M.UI_KeySelector)
        M.UI_KeySettingTitle = LoadClass('/Game/_Game/Blueprints/UI/UI_SetSystem/UI_KeySettingTitle.UI_KeySettingTitle_C')
        M.UI_KeySettingTitleRef = UnLua.Ref(M.UI_KeySettingTitle)
        M.UI_SetSystem_Handle = LoadClass('/Game/_Game/Blueprints/UI/UI_SetSystem/UI_SetSystem_Handle.UI_SetSystem_Handle_C')
        M.UI_SetSystem_HandleRef = UnLua.Ref(M.UI_SetSystem_Handle)
        M.UI_SetSystem_Exchange = LoadClass('/Game/_Game/Blueprints/UI/UI_SetSystem/UI_SetSystem_Exchange.UI_SetSystem_Exchange_C')
        M.UI_SetSystem_ExchangeRef = UnLua.Ref(M.UI_SetSystem_Exchange)
    end

    self.Overridden.Construct(self)

    self.SettingToggle.OnCheckStateChanged:Add(self, self.ShowKeySetting)

    self.SettingToggle:SetIsCheckedAndFireEvent(false)

    self.Reset.OnClicked:Add(self, function()
        UIManager:GetInstance():ShowConfirm({
            notice = Database.L10n(342),
            confirm = function()
                if not UE.UKismetSystemLibrary.IsValid(self) then return end
                self:ResetKeySetting()
            end,
            showCancel = true,
        })
    end)
    self.Preview.OnClicked:Add(self, self.PreviewGamepad)

    self.ResolutionList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized(item, widget)
    end)
    self.ResolutionList.BP_OnItemClicked:Add(self, function(wbp, item, widget)
        self:BP_OnItemClicked(item, widget)
    end)

    self.exchange.OnClicked:Add(self, self.ShowGiftCode)

    local itemDataSource = {}
    self.ListItemDataSource = {}
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    for i = 1, 5 do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = i
        table.insert(self.ListItemDataSource, ItemData)
    end
    self.ResolutionList:BP_SetListItems(self.ListItemDataSource)

    -- ---@type UE.UGHSButton
    -- self.Restore_Default_1.OnGHSClicked:Add(self, function()
    --     UIManager:GetInstance():ShowConfirm({
    --         notice = "[[DefaultContent]]将恢复为[[End]][[HighlightContent]]默认设置[[End]][[DefaultContent]]是否继续？[[End]]",
    --         confirm = function()
    --             if not UE.UKismetSystemLibrary.IsValid(self) then return end
    --             self:ResetSoundSettings()
    --         end,
    --         showCancel = true,
    --     })
    -- end)

    -- self.Restore_Default.OnGHSClicked:Add(self, function()
    --     UIManager:GetInstance():ShowConfirm({
    --         notice = "[[DefaultContent]]将恢复为[[End]][[HighlightContent]]默认设置[[End]][[DefaultContent]]是否继续？[[End]]",
    --         confirm = function()
    --             if not UE.UKismetSystemLibrary.IsValid(self) then return end
    --             self:ResetGameSettings()
    --         end,
    --         showCancel = true,
    --     })
    -- end)
end

local Titles = {
    334,
    333,
    335,
}

---@param GamepadSetting boolean
function M:ShowKeySetting(GamepadSetting)
    self.KeySettings:ClearChildren()
    for _, title in ipairs(Titles) do
        ---@type UI_KeySettingTitle_C
        local titleWidget = UE.UWidgetBlueprintLibrary.Create(self, M.UI_KeySettingTitle)

        self.KeySettings:AddChild(titleWidget)

        titleWidget.Title:SetText(Database.L10n(title))

        for _, entry in pairs(InputAssets) do
            if UE.UGameplayStatics.ObjectIsA(entry, UE.UInputMappingContext) then
                if InputUtils.MappingContextType[entry] == title then
                    self:GenerateEntries(entry, GamepadSetting)
                end
            end
        end
    end
end

---@param InputMappingContext UInputMappingContext
---@param GamepadSetting boolean
function M:GenerateEntries(InputMappingContext, GamepadSetting)
    local Mappings = InputMappingContext.Mappings
    
    ---@param Mapping FEnhancedActionKeyMapping
    for _, Mapping in pairs(Mappings) do
        if Mapping.SettingBehavior == UE.EPlayerMappableKeySettingBehaviors.OverrideSettings then
            local defaultKey = Mapping.Key

            if UE.UKismetInputLibrary.Key_IsGamepadKey(defaultKey) == GamepadSetting then
                local name = Mapping.PlayerMappableKeySettings.Name

                ---@type UI_KeySelector_C
                local entry = UE.UWidgetBlueprintLibrary.Create(self, M.UI_KeySelector)

                self.KeySettings:AddChild(entry)

                entry:Init(name, GamepadSetting and InputUtils.Platform.Xbox or InputUtils.Platform.PC)

                local category = Mapping.PlayerMappableKeySettings.DisplayCategory

                entry:SetIsEnabled(category ~= "ReadOnly")
            end
        end
    end
end

function M:PreviewGamepad()
    local ui = UE.UWidgetBlueprintLibrary.Create(self, M.UI_SetSystem_Handle)

    UIManager:GetInstance():AddUI(ui)

    ui:Setup()
end

function M:ResetKeySetting()
    local GamepadSetting = self.SettingToggle:IsChecked()
    ---@param entry UInputMappingContext
    for _, entry in pairs(InputAssets) do
        if UE.UGameplayStatics.ObjectIsA(entry, UE.UInputMappingContext) then
            local Mappings = entry.Mappings
            
            ---@param Mapping FEnhancedActionKeyMapping
            for _, Mapping in pairs(Mappings) do
                if Mapping.SettingBehavior ~= UE.EPlayerMappableKeySettingBehaviors.OverrideSettings then
                    break
                end

                local name = Mapping.PlayerMappableKeySettings.Name
                
                local defaultKey = Mapping.Key

                if UE.UKismetInputLibrary.Key_IsGamepadKey(defaultKey) == GamepadSetting then
                    InputUtils.ResetMapping(self, name)
                end
            end
        end
    end

    self:ShowKeySetting(GamepadSetting)
end

function M:ShowGiftCode()
    local ui = UE.UWidgetBlueprintLibrary.Create(self, M.UI_SetSystem_Exchange)

    UIManager:GetInstance():AddUI(ui)
end

function M:BP_OnEntryInitialized(item, widget)
    if item.Index == EResolutionType.FullScreen then
        widget.DefaultText:SetText("无边框窗口化")
        widget.SelectedText:SetText("无边框窗口化")
    elseif item.Index == EResolutionType.Type1920 then
        widget.DefaultText:SetText("1920x1080")
        widget.SelectedText:SetText("1920x1080")
    elseif item.Index == EResolutionType.Type1600 then
        widget.DefaultText:SetText("1600x900")
        widget.SelectedText:SetText("1600x900")
    elseif item.Index == EResolutionType.Type1280 then
        widget.DefaultText:SetText("1280x800")
        widget.SelectedText:SetText("1280x800")
    elseif item.Index == EResolutionType.Type800 then
        widget.DefaultText:SetText("800x600")
        widget.SelectedText:SetText("800x600")
    end
    if self.SelectedIndex == item.Index then
        widget.SelectedBg:SetVisibility(UE.ESlateVisibility.Visible)
        widget.SelectedText:SetVisibility(UE.ESlateVisibility.Visible)
        widget.DefaultText:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:BP_OnItemClicked(item, widget)
    if self.SelectedIndex == item.Index then
        self.ResolutionList:SetVisibility(UE.ESlateVisibility.Collapsed)
        return 
    end
    local lastIndex = self.SelectedIndex
    local widgets = self.ResolutionList:GetDisplayedEntryWidgets()
    self.SelectedIndex = item.Index
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if i == lastIndex then
            widget.SelectedBg:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.SelectedText:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.DefaultText:SetVisibility(UE.ESlateVisibility.Visible)
        elseif i == self.SelectedIndex then
            widget.SelectedBg:SetVisibility(UE.ESlateVisibility.Visible)
            widget.SelectedText:SetVisibility(UE.ESlateVisibility.Visible)
            widget.DefaultText:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
    if item.Index == EResolutionType.FullScreen then
        self.ResolutionText:SetText("无边框窗口化")
    elseif item.Index == EResolutionType.Type1920 then
        self.ResolutionText:SetText("1920x1080")
    elseif item.Index == EResolutionType.Type1600 then
        self.ResolutionText:SetText("1600x900")
    elseif item.Index == EResolutionType.Type1280 then
        self.ResolutionText:SetText("1280x800")
    elseif item.Index == EResolutionType.Type800 then
        self.ResolutionText:SetText("800x600")
    end
    self:ChangeResolution(item.Index)
    self.ResolutionList:SetVisibility(UE.ESlateVisibility.Collapsed)
end

return M
