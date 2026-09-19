--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local d_character = require "ClientDatas.d_character"
local d_bag_item = require "ClientDatas.d_bag_item"
local d_com_params = require("ClientDatas.d_com_params")
local d_bag_item_weapon = require "ClientDatas.d_bag_item_weapon"
local d_bag_item_equip = require "ClientDatas.d_bag_item_equip"
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local d_furnace_synthesis = require("ClientDatas.d_furnace_synthesis")
local d_furnace_decompose = require("ClientDatas.d_furnace_decompose")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Demon_Furnace_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

local SyntheticType = {
    Furniture = 1,
    Weapon = 2,
    Material = 3,
}

local SyntheticRarity = {
    SevenStars = 1,
    SixStars = 2,
    FiveStars = 3,
    FourStars = 4,
    UnderThreeStars = 5,
}

InputUtils.RegisterMouseEvent(M)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
    --Tab
    self.SyntheticTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_SyntheticTab)
    self.DecomposeTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_DecomposeTab)
    self.SyntheticTab:SetIsCheckedAndFireEvent(true)
    self.perpetualTab:SetIsCheckedAndFireEvent(true)
    self.req_data = {}
    self:InitSyntheticData()
    self:InitDecomposeData()
    self:InitSyntheticPanel()
    self:InitDecomposePanel()
    
    local path = string.format("'/Game/_Game/Blueprints/NPCs/BP_NPC_Demon_Furnace.BP_NPC_Demon_Furnace_C'") 
    local playerClass = LoadClass(path)
    local trans = UE.UKismetMathLibrary.MakeTransform(
        UE.FVector(400, 350, 100),
        UE.FRotator(0, 0, 0),
        UE.FVector(1, 1, 1))
    self.NPC = self:GetWorld():SpawnActor(playerClass, trans,
        UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)

    NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
    NetworkMessageManager:GetInstance():AddListener("ntf_character_info", self)
    MessageManager:GetInstance():AddListener("OnMsg_Ntf_Item_Info", self)
end

function M:Destruct()
    if self.NPC then
        self.NPC:K2_DestroyActor()
    end
    NetworkMessageManager:GetInstance():RemoveListener("ntf_item_info", self)
    NetworkMessageManager:GetInstance():RemoveListener("ntf_character_info", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Ntf_Item_Info", self)
end

function M:InitSyntheticData()
    --生成器
    self.BPItemList.BP_OnEntryInitialized:Clear()
    self.BPItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.BPItemList.BP_OnItemClicked:Clear()
    self.BPItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    self.GHSSlider.OnGHSValueChanged:Add(self, self.OnSlider_Value_Changed)
    self.BtnMinus.OnGHSClicked:Add(self, self.OnClicked_Minus)
    self.BtnAdd.OnGHSClicked:Add(self, self.OnClicked_Add)
    self.GHSButtonSynthetic.OnGHSClicked:Add(self, self.OnClickedSynthetic)

    self.timeLimitedTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_TimeLimitTab)
    self.perpetualTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_PerpetualTab)

    self.SelectedItemIndex = 1
    self.BPItemInfos = {}
    for _, value in pairs(d_bag_item) do
        if value.itemType == UIUtils.ItemMainType.TempProp and value.subType == UIUtils.ItemTempPropType.BluePrint then
            table.insert(self.BPItemInfos, value)
        end
    end
    self.BagBPItemInfos = BackpackSystem:GetInstance():GetAllItemByType(UIUtils.ItemMainType.TempProp, UIUtils.ItemTempPropType.BluePrint)
    self.ActivedBPItemIds = BackpackSystem:GetInstance().PlayerInfo.blueprint_ids

    self.AllSyntheticItem = {}
    for index, synthesis_info in pairs(d_furnace_synthesis) do
        local SynItemInfo = {}
        local param_num = #synthesis_info.item / 2
        local cosume_num = 0
        local max_synthetic_num = -1
        if param_num > 0 then
            for i = 1, param_num do
                local cosume_id = synthesis_info.item[i * 2 - 1]
                if d_bag_item[cosume_id].itemType == UIUtils.ItemMainType.Currency then
                    local has_gold = UIUtils.GetGold()
                    local price = synthesis_info.item[i * 2]
                    max_synthetic_num = math.floor(has_gold / price)
                else
                    cosume_num = cosume_num + 1
                    local has_num = BackpackSystem:GetInstance():GetItemCount(cosume_id)
                    --融合数量的最大值
                    if has_num >= synthesis_info.item[i * 2] then
                        if max_synthetic_num == -1 then
                            max_synthetic_num = math.floor(has_num / synthesis_info.item[i * 2])
                        else
                            if math.floor(has_num / synthesis_info.item[i * 2]) < max_synthetic_num then
                                max_synthetic_num = math.floor(has_num / synthesis_info.item[i * 2])
                            end
                        end
                    else
                        max_synthetic_num = 0
                    end
                end
            end
        end
        if max_synthetic_num > 0 then
            SynItemInfo.can_synthetic = 1
            synthesis_info.can_synthetic = 1
        else
            SynItemInfo.can_synthetic = 0
            synthesis_info.can_synthetic = 0
        end

        if synthesis_info.targetType == SyntheticType.Weapon then --weapon
            local config = d_bag_item_weapon[synthesis_info.targetID]
            SynItemInfo.config = synthesis_info
            SynItemInfo.type = SyntheticType.Weapon
            SynItemInfo.index = index
            SynItemInfo.item_config = config
            if config.rarity == 7 then
                SynItemInfo.rarity = SyntheticRarity.SevenStars
            elseif config.rarity == 6 then
                SynItemInfo.rarity = SyntheticRarity.SixStars
            elseif config.rarity == 5 then
                SynItemInfo.rarity = SyntheticRarity.FiveStars
            elseif config.rarity == 4 then
                SynItemInfo.rarity = SyntheticRarity.FourStars
            elseif config.rarity < 4 then
                SynItemInfo.rarity = SyntheticRarity.UnderThreeStars
            end
            table.insert(self.AllSyntheticItem, SynItemInfo)
        else
            local config = d_bag_item[synthesis_info.targetID]
            SynItemInfo.config = synthesis_info
            SynItemInfo.index = index
            SynItemInfo.item_config = config
            if config.rarity == 7 then
                SynItemInfo.rarity = SyntheticRarity.SevenStars
            elseif config.rarity == 6 then
                SynItemInfo.rarity = SyntheticRarity.SixStars
            elseif config.rarity == 5 then
                SynItemInfo.rarity = SyntheticRarity.FiveStars
            elseif config.rarity == 4 then
                SynItemInfo.rarity = SyntheticRarity.FourStars
            elseif config.rarity < 4 then
                SynItemInfo.rarity = SyntheticRarity.UnderThreeStars
            end
            if config.itemType == UIUtils.ItemMainType.Build then
                SynItemInfo.type = SyntheticType.Furniture
            else
                SynItemInfo.type = SyntheticType.Material
            end
            table.insert(self.AllSyntheticItem, SynItemInfo)
        end
    end

    local sortData = {}
    local SortTypes = { UIUtils.ESortType.Star }
    local filterTypes = { UIUtils.EFilterType.SynthesisType, UIUtils.EFilterType.Rarity }
    sortData.sortTypes = SortTypes
    sortData.filterTypes = filterTypes
    sortData.canFilter = true
    self.UI_Com_SortFilter:RefreshData(sortData)

    self.UI_Com_SortFilter.OnFinishedSort:Add(self, function()
        self:RefreshSortedSyntheticPanel()
    end)
    
    self.UI_Com_SortFilter.OnFinishedFilter:Add(self, function()
        self:RefreshFilteredSyntheticPanel()
    end)
end

function M:RefreshSortedSyntheticPanel()
    local sortData = self.UI_Com_SortFilter:GetSortData()
    --sort
    --sort
    if sortData.selectedSortType == UIUtils.ESortType.Star then
        table.sort(self.CurItemDataList, function(a, b)
            if a.can_synthetic ~= b.can_synthetic then
                return a.can_synthetic > b.can_synthetic
            else
                if a.item_config.rarity ~= b.item_config.rarity then
                    if sortData.sortOrderUp then
                        return a.item_config.rarity > b.item_config.rarity
                    else
                        return a.item_config.rarity < b.item_config.rarity
                    end
                else
                    return a.config.id < b.config.id
                end
            end
        end)
    end

    self.ItemDataSource = {}
    for index, item_info in pairs(self.CurItemDataList) do
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        local ItemData = NewObject(ItemClass)
        ItemData.Index = #self.ItemDataSource + 1
        ItemData.ItemId = item_info.config.id
        table.insert(self.ItemDataSource, ItemData)
    end
    self.BPItemList:ClearListItems()
    self.BPItemList:BP_SetListItems(self.ItemDataSource)
    self:RefreshSidebar()
end

function M:RefreshFilteredSyntheticPanel()
    self.CurItemDataList = {}
    local sortData = self.UI_Com_SortFilter:GetSortData()

    --filter
    local filterItemData = {}
    local filterData = self.UI_Com_SortFilter.FilterData
    for filterType, tags in pairs(filterData) do
        if filterType == UIUtils.EFilterType.SynthesisType then
            local tag_count = 0
            for i, v in pairs(tags) do
                tag_count = tag_count + 1
            end
            if tag_count > 0 then
                for index, itemData in ipairs(self.AllSyntheticItem) do
                    if tags[itemData.type] then
                        table.insert(filterItemData, itemData)
                    end
                end
                self.CurItemDataList = filterItemData
                filterItemData = {}
            end
        end
        if filterType == UIUtils.EFilterType.Rarity then
            local tag_count = 0
            for i, v in pairs(tags) do
                tag_count = tag_count + 1
            end
            if tag_count > 0 then
                for index, itemData in ipairs(self.AllSyntheticItem) do
                    if tags[itemData.rarity] then
                        table.insert(filterItemData, itemData)
                    end
                end
                self.CurItemDataList = filterItemData
                filterItemData = {}
            end
        end
    end

    --sort
    if sortData.selectedSortType == UIUtils.ESortType.Star then
        table.sort(self.CurItemDataList, function(a, b)
            if a.can_synthetic ~= b.can_synthetic then
                return a.can_synthetic > b.can_synthetic
            else
                if a.item_config.rarity ~= b.item_config.rarity then
                    if sortData.sortOrderUp then
                        return a.item_config.rarity > b.item_config.rarity
                    else
                        return a.item_config.rarity < b.item_config.rarity
                    end
                else
                    return a.config.id < b.config.id
                end
            end
        end)
    end

    self.ItemDataSource = {}
    for index, item_info in pairs(self.CurItemDataList) do
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        local ItemData = NewObject(ItemClass)
        ItemData.Index = #self.ItemDataSource + 1
        ItemData.ItemId = item_info.config.id
        table.insert(self.ItemDataSource, ItemData)
    end
    self.BPItemList:ClearListItems()
    self.BPItemList:BP_SetListItems(self.ItemDataSource)
    self:RefreshSidebar()
end

function M:InitDecomposeData()
    --生成器
    self.DecomposeItemList.BP_OnEntryInitialized:Clear()
    self.DecomposeItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnDecomposeEntryInitialized(item, widget)
    end)
    --点击事件
    self.DecomposeItemList.BP_OnItemClicked:Clear()
    self.DecomposeItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnDecomposeItemClicked(item)
    end)

    --check box
    self.weapon.OnCheckStateChanged:Add(self, self.OnFilterTypeChanged)
    self.equip.OnCheckStateChanged:Add(self, self.OnFilterTypeChanged)
    self.sixStars.OnCheckStateChanged:Add(self, self.OnFilterStateChanged)
    self.fiveStars.OnCheckStateChanged:Add(self, self.OnFilterStateChanged)
    self.fourStars.OnCheckStateChanged:Add(self, self.OnFilterStateChanged)
    self.underThreeStars.OnCheckStateChanged:Add(self, self.OnFilterStateChanged)

    --button
    self.GHSButtonDecompose.OnGHSClicked:Add(self, self.OnClickedDecompose)
end

function M:RefershDecomposeItems()
    self.DecomposeItemInfos = {}
    self.EquipItemInfos = {}
    self.WeaponItemInfos = {}
    for itemId, v in pairs(BackpackSystem:GetInstance().BagInfo) do
        local config = d_bag_item[itemId]
        if not config then
            config = d_bag_item_weapon[itemId]
        end
        if not config then
            config = d_bag_item_equip[itemId]
        end
        if config and config.itemType == UIUtils.ItemMainType.Equip then
            for _, itemInfo in pairs(v) do
                if itemInfo.arm_info.locked == false then
                    local lv, _ = UIUtils.GetEquipLevel(itemInfo.item_id, itemInfo.arm_info.break_times, itemInfo.arm_info.exp)
                    itemInfo.lv = lv
                    itemInfo.config = config
                    table.insert(self.EquipItemInfos, itemInfo)
                end
            end
        elseif config and config.itemType == UIUtils.ItemMainType.Weapon then
            for _, itemInfo in pairs(v) do
                if itemInfo.weapon_info.locked == false then
                    local lv, _ = UIUtils.GetWeaponLevel(itemInfo.item_id, itemInfo.weapon_info.break_times, itemInfo.weapon_info.exp)
                    itemInfo.lv = lv
                    itemInfo.config = config
                    table.insert(self.WeaponItemInfos, itemInfo)
                end
            end
        end
    end

    if #self.EquipItemInfos > 1 then
        table.sort(self.EquipItemInfos, function(a, b)
            if a.config.rarity ~= b.config.rarity then
                return a.config.rarity > b.config.rarity
            else
                if a.arm_info.exp ~= b.arm_info.exp then
                    return a.arm_info.exp > b.arm_info.exp
                else
                    if a.item_id ~= b.item_id then
                        return a.item_id > b.item_id
                    else
                        return a.item_uuid > b.item_uuid
                    end
                end
            end
        end)
    end

    if #self.WeaponItemInfos > 1 then
        table.sort(self.WeaponItemInfos, function(a, b)
            if a.config.rarity ~= b.config.rarity then
                return a.config.rarity > b.config.rarity
            else
                if a.weapon_info.exp ~= b.weapon_info.exp then
                    return a.weapon_info.exp > b.weapon_info.exp
                else
                    if a.item_id ~= b.item_id then
                        return a.item_id > b.item_id
                    else
                        return a.item_uuid > b.item_uuid
                    end
                end
            end
        end)
    end

    for _, value in ipairs(self.EquipItemInfos) do
        table.insert(self.DecomposeItemInfos, value)
    end

    for _, value in ipairs(self.WeaponItemInfos) do
        table.insert(self.DecomposeItemInfos, value)
    end
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitSyntheticPanel()
    local sortData = self.UI_Com_SortFilter:GetSortData()
    self.CurItemDataList = self.AllSyntheticItem
    if sortData.selectedSortType == UIUtils.ESortType.Star then
        table.sort(self.CurItemDataList, function(a, b)
            if a.can_synthetic ~= b.can_synthetic then
                return a.can_synthetic > b.can_synthetic
            else
                if a.item_config.rarity ~= b.item_config.rarity then
                    if sortData.sortOrderUp then
                        return a.item_config.rarity > b.item_config.rarity
                    else
                        return a.item_config.rarity < b.item_config.rarity
                    end
                else
                    return a.config.id < b.config.id
                end
            end
        end)
    end

    self.ItemDataSource = {}
    for index, item_info in pairs(self.CurItemDataList) do
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        local ItemData = NewObject(ItemClass)
        ItemData.Index = #self.ItemDataSource + 1
        ItemData.ItemId = item_info.config.id
        table.insert(self.ItemDataSource, ItemData)
    end
    self.BPItemList:ClearListItems()
    self.BPItemList:BP_SetListItems(self.ItemDataSource)

    self:RefreshSidebar()
end

function M:InitDecomposePanel()
    self.CheckedItems = {}
    self:RefershDecomposeItems()
    self.weapon:SetIsCheckedAndFireEvent(true)
    self.equip:SetIsCheckedAndFireEvent(true)
    self.sixStars:SetIsCheckedAndFireEvent(true)
    self.fiveStars:SetIsCheckedAndFireEvent(true)
    self.fourStars:SetIsCheckedAndFireEvent(true)
    self.underThreeStars:SetIsCheckedAndFireEvent(true)
end

function M:RefreshSidebar()
    self.consume_item_infos = {}
    self.synthesis_count = 0
    self.max_num = 0
    self.price = 0
    if #self.ItemDataSource > 0 then
        local itemId = self.ItemDataSource[self.SelectedItemIndex].ItemId
        local synthesis_info = d_furnace_synthesis[itemId]
        local config = {}

        local curItemId = 0
        if synthesis_info.targetType == 1 then
            for _, v in pairs(d_bag_item) do
                if v.subParam[1] and v.subParam[1] == synthesis_info.targetID then
                    curItemId = v.id
                    break
                end
            end
        else
            curItemId = synthesis_info.targetID
        end
        self.UI_Item_BP.Img_bg.OnMouseButtonDownEvent:Unbind()
        self.UI_Item_BP.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
            UIUtils.ShowItemInfo(curItemId)
            return UE.UWidgetBlueprintLibrary.Handled()
        end)

        if synthesis_info.targetType == 1 then
            local character_config = d_character[synthesis_info.targetID]
            self.TextBPName:SetText(Database.L10n(character_config.name))

            for index, value in pairs(d_bag_item) do
                if value.itemType == UIUtils.ItemMainType.TempProp
                    and value.subType == UIUtils.ItemTempPropType.CharCard
                    and value.subParam[1] == synthesis_info.targetID then
                    config = value
                end
            end
        elseif synthesis_info.targetType == 2 then
            config = d_bag_item_weapon[synthesis_info.targetID]
            self.TextBPName:SetText(Database.L10n(config.itemName))
        elseif synthesis_info.targetType == 3 then
            config = d_bag_item[synthesis_info.targetID]
            self.TextBPName:SetText(Database.L10n(config.itemName))
        end

        if config.itemType == UIUtils.ItemMainType.Weapon or config.itemType == UIUtils.ItemMainType.Equip then
            self.UI_Item_BP.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_Item_BP.itemboxIcon:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self.UI_Item_BP.Text_Count:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self.UI_Item_BP.Text_Count:SetText('Lv.1')
        else
            self.UI_Item_BP.itemboxIcon:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_Item_BP.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
        end

        --稀有度背景图片
        if config.rarityPath and config.rarityPath ~= '' then
            local strArr = string.split(config.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                self.UI_Item_BP.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        --icon
        if config.iconPath and config.iconPath ~= '' then
            local strArr = string.split(config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            local sprite_object = UE.UObject.Load(iconResPath)
            local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
            if iconRes then
                self.UI_Item_BP.wp_icon_res:SetBrush(icon_sprite)
            end
        end

        if config.rarity <= 6 then
            self.UI_Item_BP.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.UI_Item_BP.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        end

        local param_num = #synthesis_info.item / 2
        local cosume_num = 0
        local max_synthetic_num = -1
        for i = 1, 3 do
            self["UI_Item_" .. i]:SetVisibility(UE.ESlateVisibility.Collapsed)
        end

        --消耗物item
        if param_num > 0 then
            for i = 1, param_num do
                local cosume_id = synthesis_info.item[i * 2 - 1]
                if d_bag_item[cosume_id].itemType == UIUtils.ItemMainType.Currency then
                    self.price = synthesis_info.item[i * 2]
                else
                    cosume_num = cosume_num + 1
                    self["UI_Item_" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
                    --稀有度背景图片
                    if d_bag_item[cosume_id].rarityPath and d_bag_item[cosume_id].rarityPath ~= '' then
                        local strArr = string.split(d_bag_item[cosume_id].rarityPath, '/')
                        local littePath = strArr[#strArr]
                        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                        local itemRarityPic = LoadObject(rarityPath)
                        if itemRarityPic then
                            self["UI_Item_" .. i].wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                        end
                    end

                    --icon
                    if d_bag_item[cosume_id].iconPath and d_bag_item[cosume_id].iconPath ~= '' then
                        local strArr = string.split(d_bag_item[cosume_id].iconPath, '/')
                        local littePath = strArr[#strArr]
                        local iconResPath = string.format('/Game/_Game/%s.%s', d_bag_item[cosume_id].iconPath, littePath)
                        local iconRes = LoadObject(iconResPath)
                        local sprite_object = UE.UObject.Load(iconResPath)
                        local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
                        if iconRes then
                            self["UI_Item_" .. i].wp_icon_res:SetBrush(icon_sprite)
                        end
                    end

                    if config.rarity <= 6 then
                        self["UI_Item_" .. i].wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
                    else
                        self["UI_Item_" .. i].wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility
                        .SelfHitTestInvisible)
                    end

                    self["UI_Item_" .. i].Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
                    self["UI_Item_" .. i].Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
                    self["UI_Item_" .. i].TemaranRichText_Count:SetVisibility(UE.ESlateVisibility.Visible)
                    local has_num = BackpackSystem:GetInstance():GetItemCount(cosume_id)
                    if has_num < synthesis_info.item[i * 2] then
                        self["UI_Item_" .. i].TemaranRichText_Count:SetText(string.format(
                            '<span color="#de5d24">%d</><span color="#2E374CFF">/%d</>', has_num,
                            synthesis_info.item[i * 2]))
                    else
                        self["UI_Item_" .. i].TemaranRichText_Count:SetText(string.format(
                            '<span color="#2E374CFF">%d/%d</>', has_num, synthesis_info.item[i * 2]))
                    end

                    --融合数量的最大值
                    if has_num >= synthesis_info.item[i * 2] then
                        if max_synthetic_num == -1 then
                            max_synthetic_num = math.floor(has_num / synthesis_info.item[i * 2])
                        else
                            if math.floor(has_num / synthesis_info.item[i * 2]) < max_synthetic_num then
                                max_synthetic_num = math.floor(has_num / synthesis_info.item[i * 2])
                            end
                        end
                    else
                        max_synthetic_num = 0
                    end
                    if max_synthetic_num > d_com_params[5].value2 then
                        max_synthetic_num = d_com_params[5].value2
                    end

                    table.insert(self.consume_item_infos, {
                        item_uuid = cosume_id,
                        count = synthesis_info.item[i * 2]
                    })

                    self["UI_Item_" .. i].Img_bg.OnMouseButtonDownEvent:Unbind()
                    self["UI_Item_" .. i].Img_bg.OnMouseButtonDownEvent:Bind(self, function()
                        UIUtils.ShowItemInfo(cosume_id, synthesis_info.item[i * 2])
                        return UE.UWidgetBlueprintLibrary.Handled()
                    end)
                end
            end
        end

        local actived = false
        for _, ActivedId in ipairs(self.ActivedBPItemIds) do
            if ActivedId.blueprintId == itemId then
                actived = true
                break
            end
        end

        if actived and max_synthetic_num >= 1 then
            self.max_num = max_synthetic_num
            self.synthesis_count = 1
            self:RefreshSlider()
            self.SliderPanel:SetVisibility(UE.ESlateVisibility.Visible)
            self.GHSButtonSynthetic:SetVisibility(UE.ESlateVisibility.Visible)
            local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
            self.GHSButtonSynthetic:SetColorAndOpacity(opacity)
        else
            self:RefreshSlider()
            self.SliderPanel:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            self.GHSButtonSynthetic:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
            self.GHSButtonSynthetic:SetColorAndOpacity(opacity)
        end
        local num = self.synthesis_count > 0 and self.synthesis_count or 1
        self.Text_Num:SetText(num)

        if self.price > 0 then
            self.cost_break:SetVisibility(UE.ESlateVisibility.Visible)
            local has_gold = UIUtils.GetGold()
            if has_gold < self.price then
                self.TemaranRichText_NeedGold:SetText(string.format(
                    '<span color="#de5d24">%d</><span color="##FFFFFFFF">/%d</>', has_gold, self.price))
            else
                self.TemaranRichText_NeedGold:SetText(string.format(
                    '<span color="#FFFFFFFF">%d/%d</>', has_gold, self.price))
            end
        else
            self.cost_break:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        self.SideBarPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    else
        self.SideBarPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:BP_OnEntryInitialized(item, widget)
    widget.Index = item.Index
    widget.ItemId = item.ItemId
    local synthesis_info = d_furnace_synthesis[item.ItemId]
    local config = {}
    if synthesis_info.targetType == 1 then
        local character_config = d_character[synthesis_info.targetID]
        widget.TextName:SetText(Database.L10n(character_config.name))

        for index, value in pairs(d_bag_item) do
            if value.itemType == UIUtils.ItemMainType.TempProp
                and value.subType == UIUtils.ItemTempPropType.CharCard
                and value.subParam[1] == synthesis_info.targetID then
                    
                config = value
            end
        end
    elseif synthesis_info.targetType == 2 then
        config = d_bag_item_weapon[synthesis_info.targetID]
        widget.TextName:SetText(Database.L10n(config.itemName))
    elseif synthesis_info.targetType == 3 then
        config = d_bag_item[synthesis_info.targetID]
        widget.TextName:SetText(Database.L10n(config.itemName))
    end

    --稀有度背景图片
    if config.rarityPath and config.rarityPath ~= '' then
        local strArr = string.split(config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            widget.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if config.iconPath and config.iconPath ~= '' then
        local strArr = string.split(config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        local sprite_object = UE.UObject.Load(iconResPath)
        local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
        if iconRes then
            widget.icon_res:SetBrush(icon_sprite)
        end
    end

    local canActive = false
    local actived = false
    for _, BPItemInfo in ipairs(self.BagBPItemInfos) do
        if BPItemInfo.config.subParam[1] == item.ItemId then
            canActive = true
            break
        end
    end

    for index, ActivedId in ipairs(self.ActivedBPItemIds) do
        if ActivedId.blueprintId == item.ItemId then
            if self.ActivedBPItemIds[index].isNew then
                widget.ImageNew:SetVisibility(UE.ESlateVisibility.Visible)
            else
                widget.ImageNew:SetVisibility(UE.ESlateVisibility.Hidden)
            end
            actived = true
            break
        end
    end

    if actived then
        if synthesis_info.can_synthetic == 1 then
            widget.ImageMask:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageCanActivate:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.NeverOwnsPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            widget.ImageNew:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageMask:SetVisibility(UE.ESlateVisibility.Visible)
            widget.ImageCanActivate:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.NeverOwnsPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    else
        widget.ImageNew:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.ImageMask:SetVisibility(UE.ESlateVisibility.Visible)
        widget.ImageCanActivate:SetVisibility(canActive and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.NeverOwnsPanel:SetVisibility(canActive and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    end
    widget.TextPrice_1:SetText(1)

    --选中
    if self.SelectedItemIndex == item.Index then 
        widget.ImageBG:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.ImageBGSelected:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self:RefreshSidebar()
    else
        widget.ImageBG:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        widget.ImageBGSelected:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:BP_OnItemClicked(item)
    if self.SelectedItemIndex == item.Index then return end
    local lastIndex = self.SelectedItemIndex
    self.SelectedItemIndex = item.Index
    local widgets = self.BPItemList:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.Index == lastIndex or widget.Index == item.Index then
            widget.ImageBG:SetVisibility(self.SelectedItemIndex == widget.Index and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInvisible)
            widget.ImageBGSelected:SetVisibility(self.SelectedItemIndex == widget.Index and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        end
    end
    self:RefreshSidebar()
end

function M:BP_OnDecomposeEntryInitialized(item, widget)
    widget.Index = item.Index
    widget.ItemId = item.ItemId
    local item_info = self.DecomposeItemInfos[widget.Index]
    local config  = item_info.config
    --稀有度背景图片
    if config.rarityPath and config.rarityPath ~= '' then
        local strArr = string.split(config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            widget.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if config.iconPath and config.iconPath ~= '' then
        local strArr = string.split(config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        local sprite_object = UE.UObject.Load(iconResPath)
        local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
        if iconRes then
            widget.wp_icon_res:SetBrush(icon_sprite)
        end
    end

    if config.rarity <= 6 then
        widget.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        widget.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end

    if config.itemType == UIUtils.ItemMainType.Weapon then
        widget.Text_Count:SetText("Lv." .. (item_info.lv or 1))
        widget.Text_Count:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        if item_info.weapon_info.refine_level > 0 then
            widget.weapon_refined:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            widget.refined_num:SetText('+'..item_info.weapon_info.refine_level)
        else
            widget.weapon_refined:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    else
        widget.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    widget.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.wp_Selected:SetVisibility(UE.ESlateVisibility.Hidden)
    for index, _ in pairs(self.CheckedItems) do
        if index == widget.Index then
            widget.wp_Selected:SetVisibility(UE.ESlateVisibility.Visible)
        end
    end
end

function M:BP_OnDecomposeItemClicked(item)
    local count = 0
    for key, value in pairs(self.CheckedItems) do
        count = count + 1
    end

    if not self.CheckedItems[item.Index] then
        if count >= d_com_params[6].value2 then
            UIManager:GetInstance():Notify(Database.L10n(317))
            return
        end
        self.CheckedItems[item.Index] = item
    else
        self.CheckedItems[item.Index] = nil
    end
    local widgets = self.DecomposeItemList:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.Index == item.Index then
            widget.wp_Selected:SetVisibility(self.CheckedItems[item.Index] and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
            break
        end
    end
    self:RefreshDecomposeSubPanel()
end

function M:RefreshDecomposeSubPanel()
    self.DecomposeGrid:ClearChildren()
    self.MaterialGrid:ClearChildren()
    
    --判断选中材料个数
    local selectedCount = table.count(self.CheckedItems)
    self.ScrollBox_Decompose:SetVisibility(selectedCount > 0 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

    if selectedCount > 0 then
        self.GHSButtonDecompose:SetVisibility(UE.ESlateVisibility.Visible)
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
        self.GHSButtonDecompose:SetColorAndOpacity(opacity)
    else
        self.GHSButtonDecompose:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
        self.GHSButtonDecompose:SetColorAndOpacity(opacity)
    end

    local decompose_item_infos = {}
    local expMat = {}
    local weaponMat = {}
    for _, check_item in pairs(self.CheckedItems) do
        local item_info = self.DecomposeItemInfos[check_item.Index]
        local itemType = item_info.config.itemType
        for __, decompose_info in ipairs(d_furnace_decompose) do
            if itemType == decompose_info.itemType
                and decompose_info.itemType == UIUtils.ItemMainType.Weapon
                and decompose_info.itemRarity == item_info.config.rarity then

                local obtain_num = #decompose_info.obtain / 3
                --武器分解必返还金币
                decompose_item_infos[9001] = 1
                for i = 1, obtain_num do
                    decompose_item_infos[decompose_info.obtain[i * 3 - 2]] = 1
                end
            elseif itemType == decompose_info.itemType
                and decompose_info.itemType == UIUtils.ItemMainType.Equip
                and decompose_info.itemRarity == item_info.config.rarity then

                local obtain_num = #decompose_info.obtain / 3
                for i = 1, obtain_num do
                    decompose_item_infos[decompose_info.obtain[i * 3 - 2]] = 1
                end
            end
        end
        if item_info[item_info.item_extra].exp > 0 then
            local exp = item_info[item_info.item_extra].exp * d_com_params[4].value2 / 100
            local auto_LevelUp_MatList = self:GetAutoLevelUpMat(exp, itemType)
            for _, value in ipairs(auto_LevelUp_MatList) do
                table.insert(expMat, value)
            end
        end
        if item_info[item_info.item_extra].refine_level and item_info[item_info.item_extra].refine_level > 0 then
            local find = false
            for _, weapon_id in ipairs(weaponMat) do
                if weapon_id == item_info.item_id then
                    find = true
                end
            end
            if not find then
                table.insert(weaponMat, item_info.item_id)
            end
        end
    end

    --分解可能获得
    local index = 0
    for item_id, value in pairs(decompose_item_infos) do
        local ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Backpack/UI_Item.UI_Item_C"))
        local row = math.floor(index / 3)
        local column = index - row * 3 
        index = index + 1
        ui.itemboxicon:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
        local item_info = d_bag_item[item_id]
        if item_info and item_info.rarityPath and item_info.rarityPath ~= '' then
            local strArr = string.split(item_info.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                ui.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        --icon
        if item_info and item_info.iconPath and item_info.iconPath ~= '' then
            local strArr = string.split(item_info.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', item_info.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            local sprite_object = UE.UObject.Load(iconResPath)
            local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
            if iconRes then
                ui.wp_icon_res:SetBrush(icon_sprite)
            end
        end

        if item_info.rarity <= 6 then
            ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        end

        ui.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
            UIUtils.ShowItemInfo(item_id, BackpackSystem:GetInstance():GetItemCount(item_id))
            return UE.UWidgetBlueprintLibrary.Handled()
        end)

        self.DecomposeGrid:AddChild(ui)
        UE.UWidgetLayoutLibrary.SlotAsUniformGridSlot(ui):SetRow(row)
        UE.UWidgetLayoutLibrary.SlotAsUniformGridSlot(ui):SetColumn(column)
       
    end
    local y = math.floor(index / 3)
    if index % 3 > 0 then
        y = y + 1
    end
    self.Spacer:SetSize(UE.FVector2D(0, y * -30))

    --养成返还
    for index, value in pairs(expMat) do
        local item_id = value.item_id
        local ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Backpack/UI_Item.UI_Item_C"))
        index = index - 1
        local row = math.floor(index / 3)
        local column = index - row * 3 
        ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Text_Count:SetText(value.selectCount)
        local item_info = d_bag_item[item_id]
        if item_info and item_info.rarityPath and item_info.rarityPath ~= '' then
            local strArr = string.split(item_info.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                ui.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        --icon
        if item_info and item_info.iconPath and item_info.iconPath ~= '' then
            local strArr = string.split(item_info.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', item_info.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            local sprite_object = UE.UObject.Load(iconResPath)
            local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
            if iconRes then
                ui.wp_icon_res:SetBrush(icon_sprite)
            end
        end

        if item_info.rarity <= 6 then
            ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        end

        ui.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
            UIUtils.ShowItemInfo(value.item_id, value.selectCount)
            return UE.UWidgetBlueprintLibrary.Handled()
        end)
        self.MaterialGrid:AddChild(ui)
        UE.UWidgetLayoutLibrary.SlotAsUniformGridSlot(ui):SetRow(row)
        UE.UWidgetLayoutLibrary.SlotAsUniformGridSlot(ui):SetColumn(column)
    end

    --光淬返还
    -- for index, value in pairs(weaponMat) do
    --     local item_id = value
    --     local ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Backpack/UI_Item.UI_Item_C"))
    --     index = index - 1
    --     local row = math.floor(index / 3)
    --     local column = index - row * 3 
    --     ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
    --     ui.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
    --     local item_info = d_bag_item_weapon[item_id]
    --     if item_info and item_info.rarityPath and item_info.rarityPath ~= '' then
    --         local strArr = string.split(item_info.rarityPath, '/')
    --         local littePath = strArr[#strArr]
    --         local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
    --         local itemRarityPic = LoadObject(rarityPath)
    --         if itemRarityPic then
    --             ui.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
    --         end
    --     end

    --     --icon
    --     if item_info and item_info.iconPath and item_info.iconPath ~= '' then
    --         local strArr = string.split(item_info.iconPath, '/')
    --         local littePath = strArr[#strArr]
    --         local iconResPath = string.format('/Game/_Game/%s.%s', item_info.iconPath, littePath)
    --         local iconRes = LoadObject(iconResPath)
    --         local sprite_object = UE.UObject.Load(iconResPath)
    --         local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
    --         if iconRes then
    --             ui.wp_icon_res:SetBrush(icon_sprite)
    --         end
    --     end

    --     if item_info.rarity <= 6 then
    --         ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
    --     else
    --         ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    --     end

    --     ui.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
    --         UIUtils.ShowItemInfo(value.item_id, value.selectCount)
    --         return UE.UWidgetBlueprintLibrary.Handled()
    --     end)
    --     self.MaterialGrid:AddChild(ui)
    --     UE.UWidgetLayoutLibrary.SlotAsUniformGridSlot(ui):SetRow(row)
    --     UE.UWidgetLayoutLibrary.SlotAsUniformGridSlot(ui):SetColumn(column)
    -- end
end

function M:GetLevelUpMaterialList()
    local result = {}
    local itemNum = 0
    local materailConfigList = UIUtils.GetAllItemConfigByType(UIUtils.ItemMainType.TempProp, self:GetItemSubType())
    for k, v in pairs(materailConfigList) do
        local item = {
            item_id = k,
            count = BackpackSystem:GetInstance():GetItemCount(k),
            selectCount = 0,
            config = v
        }
        table.insert(result, item)
        itemNum = itemNum + 1
    end
    
    if itemNum > 1 then
        table.sort(result, function(a, b)
            return a.item_id < b.item_id
        end)
    end
    return result
end

function M:GetAutoLevelUpMat(exp, itemType)
    local result = {}
    if itemType == UIUtils.ItemMainType.Equip then
        local itemNum = 0
        local needExp = exp
        local levelUpItemList = {}
        local materailConfigList = UIUtils.GetAllItemConfigByType(UIUtils.ItemMainType.TempProp, UIUtils.ItemTempPropType.EquipExp)
        for k, v in pairs(materailConfigList) do
            local item = {
                item_id = k,
                count = BackpackSystem:GetInstance():GetItemCount(k),
                selectCount = 0,
                config = v
            }
            table.insert(levelUpItemList, item)
            itemNum = itemNum + 1
        end
        if levelUpItemList then
            for i = #levelUpItemList, 1, -1 do 
                local item = levelUpItemList[i]
                if needExp >= item.config.subParam[1] then
                    local count, temp2 = math.modf(needExp / item.config.subParam[1])
                    if count > 0 then
                        if item.count >= count then
                            item.selectCount = count
                            needExp = needExp - item.config.subParam[1] * count
                        else
                            item.selectCount = item.count
                            needExp = needExp - item.config.subParam[1] * item.count
                        end
                    end
                end
            end
            if needExp > 0 then
                for i = #levelUpItemList, 1, -1 do 
                    local item = levelUpItemList[i]
                    local count, temp2 = math.floor(needExp / item.config.subParam[1])
                    if count > 0 then
                        if item.count - item.selectCount >= count then
                            needExp = needExp - item.config.subParam[1] * count
                        else
                            needExp = needExp - item.config.subParam[1] * item.count
                        end
                        item.selectCount = item.selectCount + count
                    end
                end
            end
        end
        for _, value in ipairs(levelUpItemList) do
            if value.selectCount > 0 then
                table.insert(result, value)
            end
        end
    elseif itemType == UIUtils.ItemMainType.Weapon then
        local itemNum = 0
        local needExp = exp
        local levelUpItemList = {}
        local materailConfigList = UIUtils.GetAllItemConfigByType(UIUtils.ItemMainType.TempProp, UIUtils.ItemTempPropType.WeaponExp)
        for k, v in pairs(materailConfigList) do
            local item = {
                item_id = k,
                count = BackpackSystem:GetInstance():GetItemCount(k),
                selectCount = 0,
                config = v
            }
            table.insert(levelUpItemList, item)
            itemNum = itemNum + 1
        end
        if levelUpItemList then
            for i = #levelUpItemList, 1, -1 do 
                local item = levelUpItemList[i]
                if needExp >= item.config.subParam[1] then
                    local count, temp2 = math.modf(needExp / item.config.subParam[1])
                    if count > 0 then
                        if item.count >= count then
                            item.selectCount = count
                            needExp = needExp - item.config.subParam[1] * count
                        else
                            item.selectCount = item.count
                            needExp = needExp - item.config.subParam[1] * item.count
                        end
                    end
                end
            end
            if needExp > 0 then
                for i = #levelUpItemList, 1, -1 do 
                    local item = levelUpItemList[i]
                    local count, temp2 = math.floor(needExp / item.config.subParam[1])
                    if count > 0 then
                        if item.count - item.selectCount >= count then
                            needExp = needExp - item.config.subParam[1] * count
                        else
                            needExp = needExp - item.config.subParam[1] * item.count
                        end
                        item.selectCount = item.selectCount + count
                    end
                end
            end
        end
        for _, value in ipairs(levelUpItemList) do
            if value.selectCount > 0 then
                table.insert(result, value)
            end
        end
    end
    return result
end

function M:OnFilterTypeChanged(isOn)
    -- if not isOn then return end
    self.DecomposeItemInfos = {}
    self.CheckedItems = {}
    self:RefreshDecomposeSubPanel()
    if self.equip:IsChecked() then
        for _, value in ipairs(self.EquipItemInfos) do
            table.insert(self.DecomposeItemInfos, value)
        end
    end

    if self.weapon:IsChecked() then
        for _, value in ipairs(self.WeaponItemInfos) do
            table.insert(self.DecomposeItemInfos, value)
        end
    end
    self.DecomposeItemDataSource = {}
    for index, decompose_item_info in pairs(self.DecomposeItemInfos) do
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        local ItemData = NewObject(ItemClass)
        ItemData.Index = index
        ItemData.ItemId = decompose_item_info.item_id
        table.insert(self.DecomposeItemDataSource, ItemData)
    end
    self.DecomposeItemList:ClearListItems()
    if #self.DecomposeItemDataSource > 0 then
        self.DecomposeItemList:BP_SetListItems(self.DecomposeItemDataSource)
        self.nothing:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.nothing:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function M:OnFilterStateChanged(isOn)
    -- if not isOn then return end
    local filter = {}
    if self.sixStars:IsChecked() then
        filter[7] = 1
        filter[6] = 1
    end
    if self.fiveStars:IsChecked() then
        filter[5] = 1
    end
    if self.fourStars:IsChecked() then
        filter[4] = 1
    end
    if self.underThreeStars:IsChecked() then
        filter[3] = 1
        filter[2] = 1
        filter[1] = 1
    end
    
    self.DecomposeItemInfos = {}
    self.CheckedItems = {}
    self:RefreshDecomposeSubPanel()
    if self.equip:IsChecked() then
        for _, value in ipairs(self.EquipItemInfos) do
            if filter[value.config.rarity] then
                table.insert(self.DecomposeItemInfos, value)
            end
        end
    end

    if self.weapon:IsChecked() then
        for _, value in ipairs(self.WeaponItemInfos) do
            if filter[value.config.rarity] then
                table.insert(self.DecomposeItemInfos, value)
            end
        end
    end
    self.DecomposeItemDataSource = {}
    for index, decompose_item_info in pairs(self.DecomposeItemInfos) do
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        local ItemData = NewObject(ItemClass)
        ItemData.Index = index
        ItemData.ItemId = decompose_item_info.item_id
        table.insert(self.DecomposeItemDataSource, ItemData)
    end
    self.DecomposeItemList:ClearListItems()
    if #self.DecomposeItemDataSource > 0 then
        self.DecomposeItemList:BP_SetListItems(self.DecomposeItemDataSource)
        self.nothing:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.nothing:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function M:OnClicked_Exit()
    self:BindToAnimationFinished(self.quit, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationReverse(self.quit, 1, false)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:InitUIEx(type)
    if type == 2 then
        self:BindToAnimationFinished(self.switch, function()
            self:UnbindAllFromAnimationFinished(self.switch)
            self.SyntheticTab:SetIsCheckedAndFireEvent(false)
            self.DecomposeTab:SetIsCheckedAndFireEvent(true)
        end)
        self.WidgetSwitcher:SetActiveWidgetIndex(type - 1)
        self:PlayAnimationForward(self.switch)
        --self:OnTabCheckStateChanged(type - 1)
    end
end

function M:OnCheckStateChanged_SyntheticTab(isOn)
    if not isOn then return end
    self:OnTabCheckStateChanged(0)
end

function M:OnCheckStateChanged_DecomposeTab(isOn)
    if not isOn then return end
    self:OnTabCheckStateChanged(1)
    self:RefershDecomposeItems()
    self:OnFilterStateChanged()
end

function M:OnTabCheckStateChanged(index)
    self.WidgetSwitcher:SetActiveWidgetIndex(index)
    self:StopAnimation(self.switch)
    self:PlayAnimationForward(self.switch)
end

function M:RefreshCostInfo(percent)
    self.ProgressBar:SetPercent(percent)
    local num = math.floor(percent * (self.max_num)) + 1
    if math.floor(percent * (self.max_num)) + 1 > self.max_num then
        num = self.max_num
    end
    self.Text_Num:SetText(math.floor(num))
    self.synthesis_count = num
    
    if self.price > 0 then
        self.cost_break:SetVisibility(UE.ESlateVisibility.Visible)
        local has_gold = UIUtils.GetGold()
        if has_gold < self.price then
            self.TemaranRichText_NeedGold:SetText(string.format(
                '<span color="#de5d24">%d</><span color="##FFFFFFFF">/%d</>', has_gold, self.price))
        else
            self.TemaranRichText_NeedGold:SetText(string.format(
                '<span color="#FFFFFFFF">%d/%d</>', has_gold, self.price))
        end
    else
        self.cost_break:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:OnSlider_Value_Changed(target, value)
    if value then
        self:RefreshCostInfo(value / self.GHSSlider.MaxValue)
    end
end

function M:RefreshSlider()
    if self.max_num >= 1 then
        self.GHSSlider:SetValue(self.GHSSlider.MaxValue * self.synthesis_count / self.max_num)
        local percent = self.synthesis_count / self.max_num
        self.ProgressBar:SetPercent(percent)
    else
        self.GHSSlider:SetValue(self.GHSSlider.MaxValue)
        self.ProgressBar:SetPercent(1)
    end
    self.Text_Num:SetText(self.synthesis_count)

    if self.price > 0 then
        self.cost_break:SetVisibility(UE.ESlateVisibility.Visible)
        local has_gold = UIUtils.GetGold()
        if has_gold < self.price then
            self.TemaranRichText_NeedGold:SetText(string.format(
                '<span color="#de5d24">%d</><span color="##FFFFFFFF">/%d</>', has_gold, self.price))
        else
            self.TemaranRichText_NeedGold:SetText(string.format(
                '<span color="#FFFFFFFF">%d/%d</>', has_gold, self.price))
        end
    else
        self.cost_break:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:OnClicked_Minus()
    if self.synthesis_count > 1 then
        self.synthesis_count = self.synthesis_count - 1
        self:RefreshSlider()
    end
end

function M:OnClicked_Add()
    if self.synthesis_count < self.max_num then
        self.synthesis_count = self.synthesis_count + 1
        self:RefreshSlider()
    end
end

function M:OnClickedSynthetic()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    self:PlayAnimationForward(self.anniu, 1, false)
    local msg = {}
    msg.blueprint_id = self.ItemDataSource[self.SelectedItemIndex].ItemId
    msg.count = self.synthesis_count
    msg.item_infos = self.consume_item_infos
    self.req_data.req_item_synthetic = msg
    Client.send("req_item_synthetic", msg)
    BackpackSystem:CacheChangeItem(msg)
end

function M:OnClickedDecompose()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    local msg = {}
    local uuids = {}
    for key, check_item in pairs(self.CheckedItems) do
        local item_info = self.DecomposeItemInfos[check_item.Index]
        table.insert(uuids, item_info.item_uuid)
    end
    msg.item_uuids = uuids
    self.req_data.req_item_decompose = msg
    Client.send("req_item_decompose", msg)
    BackpackSystem:CacheChangeItem(msg)
end

function M:OnCheckStateChanged_TimeLimitTab(isOn)
    if not isOn then return end
    UIUtils.ShowNotify(self, Database.L10n(50500))
end

function M:OnCheckStateChanged_PerpetualTab(isOn)
    if not isOn then return end
end

function M:ShowGetItemUI()
    if self.req_data.req_item_synthetic or self.req_data.req_item_decompose then
        local item_infos = {}
        local bSynthesis = self.WidgetSwitcher:GetActiveWidgetIndex() == 0 and true or false
        local synthesis_info = {}
        if bSynthesis then
            --融合获得物品
            local item_id = self.req_data.req_item_synthetic.blueprint_id
            synthesis_info = d_furnace_synthesis[item_id]
            if self.req_data.ntf_item_info then
                for _, changed_item_info in ipairs(self.req_data.ntf_item_info.changed_item_infos) do
                    if changed_item_info.item_id == synthesis_info.targetID then
                        local config = {}
                        if synthesis_info.targetType == 1 then
                            local curItemId
                            for _, v in pairs(d_bag_item) do
                                if v.subParam[1] and v.subParam[1] == synthesis_info.targetID then
                                    curItemId = v.id
                                    break
                                end
                            end
                            local character_config = d_character[synthesis_info.targetID]
                            local bag_configh = d_bag_item[curItemId]
                            config.itemName = character_config.name
                            config.rarityPath = bag_configh.rarityPath
                            config.iconPath = bag_configh.iconPath
                        elseif synthesis_info.targetType == 2 then
                            config = d_bag_item_weapon[synthesis_info.targetID]
                        elseif synthesis_info.targetType == 3 then
                            config = d_bag_item[synthesis_info.targetID]
                        end
                        table.insert(item_infos,
                            { item_id = changed_item_info.item_id, count = changed_item_info.count, weapon_info =
                            changed_item_info.weapon_info, config = config })
                    end
                end
            elseif self.req_data.ntf_character_info then
                for index, changed_character_info in ipairs(self.req_data.ntf_character_info.changed_character_infos) do
                    if changed_character_info.character_id == synthesis_info.targetID then
                        local config = {}
                        if synthesis_info.targetType == 1 then
                            local curItemId
                            for _, v in pairs(d_bag_item) do
                                if v.subParam[1] and v.subParam[1] == synthesis_info.targetID then
                                    curItemId = v.id
                                    break
                                end
                            end
                            local character_config = d_character[synthesis_info.targetID]
                            local bag_configh = d_bag_item[curItemId]
                            config.itemName = character_config.name
                            config.rarityPath = bag_configh.rarityPath
                            config.iconPath = bag_configh.iconPath
                        elseif synthesis_info.targetType == 2 then
                            config = d_bag_item_weapon[synthesis_info.targetID]
                        elseif synthesis_info.targetType == 3 then
                            config = d_bag_item[synthesis_info.targetID]
                        end
                        table.insert(item_infos, { item_id = changed_character_info.item_id, count = self.req_data.req_item_synthetic.count, config = config })
                    end
                end
            end
        else
            --分解获得物品
            if self.req_data.ntf_item_info then
                local changed_items = {}
                for _, changed_item_info in ipairs(self.req_data.ntf_item_info.changed_item_infos) do
                    if changed_item_info.count > 0 then
                        local config = d_bag_item[changed_item_info.item_id]
                        if not config then
                            config = d_bag_item_equip[changed_item_info.item_id]
                        end
                        if not config then
                            config = d_bag_item_weapon[changed_item_info.item_id]
                        end
                        if not changed_items[changed_item_info.item_id] then
                            changed_items[changed_item_info.item_id] = { item_id = changed_item_info.item_id, count = changed_item_info.count, config = config }
                        else
                            changed_items[changed_item_info.item_id].count = changed_items[changed_item_info.item_id].count + changed_item_info.count
                        end
                    end
                end

                for _, value in pairs(changed_items) do
                    table.insert(item_infos, value)
                end
            end
            if #item_infos > 0 then
                for key, check_item in pairs(self.CheckedItems) do
                    local item_info = self.DecomposeItemInfos[check_item.Index]
                    for index, value in ipairs(self.EquipItemInfos) do
                        if item_info.item_uuid == value.item_uuid then
                            table.remove(self.EquipItemInfos, index)
                            break
                        end
                    end

                    for index, value in ipairs(self.WeaponItemInfos) do
                        if item_info.item_uuid == value.item_uuid then
                            table.remove(self.WeaponItemInfos, index)
                            break
                        end
                    end
                end
                self.CheckedItems = {}
                self:OnFilterStateChanged()
            end
        end
        
        if bSynthesis and synthesis_info.targetType == 2 then
            self.UI_GetWeapon = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetWeapon')
            self.UI_GetWeapon:RefreshUI(item_infos)
        else
            if #item_infos > 0 then
                self.UI_GetItem_Notice = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetItem_Notice')
                self.UI_GetItem_Notice:RefreshUI(item_infos)
            end
        end
        self.req_data.ntf_item_info = nil
        self.req_data.ntf_character_info = nil
        self.req_data.req_item_synthetic = nil
        self.req_data.req_item_decompose = nil
    end
end

function M:ntf_item_info(result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg and parsed_msg.ntf_item_info and parsed_msg.ntf_item_info.changed_item_infos then
            self.req_data.ntf_item_info = parsed_msg.ntf_item_info
            self:ShowGetItemUI()
        end
    end
end

function M:ntf_character_info(result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg and parsed_msg.ntf_character_info and parsed_msg.ntf_character_info.changed_character_infos then
            if self.WidgetSwitcher:GetActiveWidgetIndex() == 0 then
                local item_id = self.req_data.req_item_synthetic.blueprint_id
                local synthesis_info = d_furnace_synthesis[item_id]
                for index, changed_character_info in ipairs(parsed_msg.ntf_character_info.changed_character_infos) do
                    if changed_character_info.character_id == synthesis_info.targetID then
                        self.req_data.ntf_character_info = parsed_msg.ntf_character_info
                        self.req_data.ntf_item_info = nil
                        self:ShowGetItemUI()
                    end
                end
            elseif self.WidgetSwitcher:GetActiveWidgetIndex() == 1 then
            end
        end
    end
end

function M:OnMsg_Ntf_Item_Info()
    self:InitSyntheticData()
    self:InitSyntheticPanel()
end

return M
