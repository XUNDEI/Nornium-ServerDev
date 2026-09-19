--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local d_equip_rune = require("ClientDatas.d_equip_rune")

local StrMainProperty = 
{
    Database.L10n(82702002), --攻击 = 1
    Database.L10n(82702004), --生命 = 2
    Database.L10n(82702005), --暴击 = 3
    Database.L10n(82702003), --防御 = 4
    Database.L10n(82702006), --物理 = 5
    Database.L10n(82702007), --魔法 = 6
}

local FilterType = {
    '装备类型',
    '主属性',
    '星芒',
    '自定义',
    '武器类型',
    '命质类型',
    '类型筛选',
    '稀有度',
}

local StrElementType = {
    Database.L10n(249), -- 粒子:1
    Database.L10n(250), -- 动能:2
    Database.L10n(251), -- 力场:3
    Database.L10n(252), -- 灾厄:4
    Database.L10n(253), -- 侵蚀:5
    Database.L10n(254), -- 虚无:6
}

local strSynthesisType = {
    Database.L10n(419), -- 家具
    Database.L10n(420), -- 武器
    Database.L10n(421), -- 养成材料
}

local strRarity = {
    Database.L10n(421), -- 7星
    Database.L10n(421), -- 6星
    Database.L10n(421), -- 5星
    Database.L10n(421), -- 4星
    Database.L10n(421), -- 3星及以下
}

local ImgEquip = {
    '/Game/_Game/TP_New/Character_Detail/Frames/core_png.core_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/core_png.core_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/kidney_png.kidney_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/liver_png.liver_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/stomach_png.stomach_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/brain_png.brain_png'
}

---@type UI_Com_FilterMenu_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.FilterMenuList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized(item, widget)
    end)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:RefreshUI(data, selectedData)
    self.FilterData = selectedData or {}
    self.ListItemDataSource = {}
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    for index, value in ipairs(data) do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = index  --mainFilterIndex
        ItemData.ItemId = value --mainFilterId
        table.insert(self.ListItemDataSource, ItemData)
    end
    self.FilterMenuList:BP_SetListItems(self.ListItemDataSource)
end

function M:BP_OnEntryInitialized(item, widget)
    widget.TagList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnTagEntryInitialized(item, widget)
    end)
    widget.TagList.BP_OnItemClicked:Add(self, function(wbp, item, widget)
        self:BP_OnItemClicked(item, widget)
    end)
    widget.ButtonAll.OnClicked:Add(self, function()
        self:OnClickedMainTagAll(item)
    end)
    widget.DefaultPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    widget.SelectedPanel:SetVisibility(UE.ESlateVisibility.Hidden)

    local count = 0
    local itemDataSource = {}
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    if item.ItemId == UIUtils.EFilterType.EquipType then
        count = 6
        for i = 1, count do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i            --subFilterId
            ItemData.ItemId = item.Index --mainFilterIndex
            table.insert(itemDataSource, ItemData)
        end
    elseif item.ItemId == UIUtils.EFilterType.MainProperty then
        count = 6
        for i = 1, count do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i            --subFilterId
            ItemData.ItemId = item.Index --mainFilterIndex
            table.insert(itemDataSource, ItemData)
        end
    elseif item.ItemId == UIUtils.EFilterType.Rune then
        self.RuneFilterData = {}
        for rune_id, config in pairs(d_equip_rune) do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = rune_id     --subFilterId
            ItemData.ItemId = item.Index --mainFilterIndex
            table.insert(itemDataSource, ItemData)
        end
    elseif item.ItemId == UIUtils.EFilterType.WeaponType then
        count = 7
        for i = 1, count do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i            --subFilterId
            ItemData.ItemId = item.Index --mainFilterIndex
            table.insert(itemDataSource, ItemData)
        end
    elseif item.ItemId == UIUtils.EFilterType.ElementType then
        count = 6
        for i = 1, count do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i            --subFilterId
            ItemData.ItemId = item.Index --mainFilterIndex
            table.insert(itemDataSource, ItemData)
        end
    elseif item.ItemId == UIUtils.EFilterType.SynthesisType then
        count = 3
        for i = 1, count do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i            --subFilterId
            ItemData.ItemId = item.Index --mainFilterIndex
            table.insert(itemDataSource, ItemData)
        end
    elseif item.ItemId == UIUtils.EFilterType.Rarity then
        count = 5
        for i = 1, count do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i            --subFilterId
            ItemData.ItemId = item.Index --mainFilterIndex
            table.insert(itemDataSource, ItemData)
        end
    end
    widget.TagList:BP_SetListItems(itemDataSource)
    widget.FiterType:SetText(FilterType[item.ItemId])
end

function M:OnClickedMainTagAll(item)
    local listWidget = self.FilterMenuList:GetDisplayedEntryWidgets():Get(item.ItemId)
    listWidget.DefaultPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    listWidget.SelectedPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
end

function M:BP_OnTagEntryInitialized(item, widget)
    widget.ItemId = item.ItemId
    widget.Index = item.Index
    local mainFilterId = self.ListItemDataSource[item.ItemId].ItemId
    if mainFilterId == UIUtils.EFilterType.EquipType then
        widget.DefaultText:SetText(Database.L10n(UIUtils.WordEquipType[item.Index]))
        widget.SeletedText:SetText(Database.L10n(UIUtils.WordEquipType[item.Index]))
        local itemRarityPic = LoadObject(ImgEquip[item.Index])
        if itemRarityPic then
            widget.icon_waitResouces:SetBrushFromAtlasInterface(itemRarityPic)
            widget.icon_waitResouces_1:SetBrushFromAtlasInterface(itemRarityPic)
        end
    elseif mainFilterId == UIUtils.EFilterType.MainProperty then
        widget.DefaultText:SetText(StrMainProperty[item.Index])
        widget.SeletedText:SetText(StrMainProperty[item.Index])
        local itemRarityPic = LoadObject(string.format('/Game/_Game/TP_New/Element_res/Frames/attribute_%d_png.attribute_%d_png', item.Index, item.Index))
        if itemRarityPic then
            widget.icon_waitResouces:SetBrushFromAtlasInterface(itemRarityPic)
            widget.icon_waitResouces_1:SetBrushFromAtlasInterface(itemRarityPic)
        end
    elseif mainFilterId == UIUtils.EFilterType.Rune then
        widget.DefaultText:SetText(Database.L10n(d_equip_rune[item.Index].runeName))
        widget.SeletedText:SetText(Database.L10n(d_equip_rune[item.Index].runeName))
        local itemRarityPic = LoadObject(string.format('/Game/_Game/TP_New/Rune_res/Frames/Icon_rune_%d_png.Icon_rune_%d_png', item.Index, item.Index))
        if itemRarityPic then
            widget.icon_waitResouces:SetBrushFromAtlasInterface(itemRarityPic)
            widget.icon_waitResouces_1:SetBrushFromAtlasInterface(itemRarityPic)
        end
    elseif mainFilterId == UIUtils.EFilterType.WeaponType then
        widget.DefaultText:SetText(Database.L10n(UIUtils.WordWeaponType[item.Index]))
        widget.SeletedText:SetText(Database.L10n(UIUtils.WordWeaponType[item.Index]))
        local itemRarityPic = LoadObject(string.format('/Game/_Game/TP_New/Element_res/Frames/weapons_%d_png.weapons_%d_png', item.Index, item.Index))
        if itemRarityPic then
            widget.icon_waitResouces:SetBrushFromAtlasInterface(itemRarityPic)
            widget.icon_waitResouces_1:SetBrushFromAtlasInterface(itemRarityPic)
        end
    elseif mainFilterId == UIUtils.EFilterType.ElementType then
        widget.DefaultText:SetText(StrElementType[item.Index])
        widget.SeletedText:SetText(StrElementType[item.Index])
        local itemRarityPic = LoadObject(string.format('/Game/_Game/TP_New/Element_res/Frames/element_%d_s_png.element_%d_s_png', item.Index, item.Index))
        if itemRarityPic then
            widget.icon_waitResouces:SetBrushFromAtlasInterface(itemRarityPic)
            widget.icon_waitResouces_1:SetBrushFromAtlasInterface(itemRarityPic)
        end
    elseif mainFilterId == UIUtils.EFilterType.SynthesisType then
        widget.DefaultText:SetText(strSynthesisType[item.Index])
        widget.SeletedText:SetText(strSynthesisType[item.Index])
        local itemRarityPic = LoadObject(string.format('/Game/_Game/TP_New/Element_res/Frames/element_%d_s_png.element_%d_s_png', item.Index, item.Index))
        if itemRarityPic then
            widget.icon_waitResouces:SetBrushFromAtlasInterface(itemRarityPic)
            widget.icon_waitResouces_1:SetBrushFromAtlasInterface(itemRarityPic)
        end
    elseif mainFilterId == UIUtils.EFilterType.Rarity then
        widget.DefaultText:SetText(strRarity[item.Index])
        widget.SeletedText:SetText(strRarity[item.Index])
        local itemRarityPic = LoadObject(string.format('/Game/_Game/TP_New/Element_res/Frames/element_%d_s_png.element_%d_s_png', item.Index, item.Index))
        if itemRarityPic then
            widget.icon_waitResouces:SetBrushFromAtlasInterface(itemRarityPic)
            widget.icon_waitResouces_1:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end
    
    if self.FilterData[mainFilterId] and self.FilterData[mainFilterId][item.Index] then
        widget.DefaultPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.SelectedPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    else
        widget.DefaultPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        widget.SelectedPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:BP_OnItemClicked(tagItem)
    local listWidget = self.FilterMenuList:GetDisplayedEntryWidgets():Get(tagItem.ItemId)
    local tagWidgets = listWidget.TagList:GetDisplayedEntryWidgets()
    for i = 1, tagWidgets:Length() do
        local widget = tagWidgets:Get(i)
        if widget.Index == tagItem.Index then
            local mainFilterId = self.ListItemDataSource[tagItem.ItemId].ItemId
            if self.FilterData[mainFilterId] and self.FilterData[mainFilterId][tagItem.Index] then
                widget.DefaultPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                widget.SelectedPanel:SetVisibility(UE.ESlateVisibility.Hidden)
                self.FilterData[mainFilterId][tagItem.Index] = nil
            else
                if not self.FilterData[mainFilterId] then self.FilterData[mainFilterId] = {} end
                self.FilterData[mainFilterId][tagItem.Index] = true
                widget.DefaultPanel:SetVisibility(UE.ESlateVisibility.Hidden)
                widget.SelectedPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            end
        end
    end
end

return M
