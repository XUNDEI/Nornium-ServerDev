--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"
local utf8 = require "Common.Tools.utf8"

-- local solotName = "SG_SaveGame_Backpack"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local MessageManager = require "Framework.Updater.MessageManager"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Backpack_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

--构造函数
function M:Construct()
    self:InitData()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Bag_Use_Item_Success", self)
end

function M:Destruct()
    self:SaveSaveGameBackpack()
    MessageManager:GetInstance():RemoveListener("OnMsg_Bag_Use_Item_Success", self)
end

function M:OnMsg_Bag_Use_Item_Success(itemInfo)

    if itemInfo then
        --当前选中的icon刷新
        -- local widgets = self.ItemList:GetDisplayedEntryWidgets()
        -- for i = 1, widgets:Length() do
        --     local widget = widgets:Get(i)
        --     if widget.Index == self.SelectedItemIndex then
        --         UIUtils.RefreshUIItem(widget, itemInfo, true)
        --         self:RefreshItem(widget, itemInfo, true)
        --     end
        -- end
        if itemInfo.config.itemType == UIUtils.ItemMainType.TempProp then
            if itemInfo.config.subType == UIUtils.ItemTempPropType.BluePrint or 
                itemInfo.config.subType == UIUtils.ItemTempPropType.ForgeBP then
                local str = '<span color="#' .. UIUtils.EItemRarityColor[itemInfo.config.rarity] .. 'FF">' .. Database.L10n(itemInfo.config.itemName) .. '</>'
                print(str)
                UIUtils.ShowNotify(self, string.format(Database.L10n(511401001) or "%s", str))
            end
        end
       
    end
    self:InitBagInfo()
    self:RefreshTab(false)
end

function M:OnMsg_Req_Strengthen_Weapon_Success()
    local curItem = self.CurItemDataList[self.SelectedItemIndex]
    if curItem and self.CurTabIndex == UIUtils.ItemMainType.Weapon then
        local widgets = self.ItemList:GetDisplayedEntryWidgets()
        for i = 1, widgets:Length() do
            local widget = widgets:Get(i)
            if widget.Index == self.SelectedItemIndex then
                UIUtils.RefreshUIItem(widget, curItem, true)
                self:RefreshItem(widget, curItem, true)
                break
            end
        end
    end
    self:InitBagInfo()
    self:RefreshTab(false)
end

function M:InitBagInfo()
    self.AllData = {}
    for _, v in pairs(CharacterSystem:GetInstance().CharacterInfo) do 
        -- print("===char:" .. tostring(v or {}, nil, 10))
        if v.weapon_info then
            local itemConfig = UIUtils.GetItemConfigById(v.weapon_info.item_id)
            local mainType = itemConfig.itemType
            if not self.AllData[mainType] then self.AllData[mainType] = {} end
            v.weapon_info.config = itemConfig
            v.weapon_info.characterId = v.character_id
            table.insert(self.AllData[mainType], v.weapon_info)
        end
        if v.arm_infos then
            for _, armInfo in pairs(v.arm_infos) do 
                local itemConfig = UIUtils.GetItemConfigById(armInfo.item_id)
                local mainType = itemConfig.itemType
                if not self.AllData[mainType] then self.AllData[mainType] = {} end
                armInfo.config = itemConfig
                armInfo.characterId = v.character_id
                table.insert(self.AllData[mainType], armInfo)
            end
        end
    end

    for item_id, bagData in pairs(BackpackSystem:GetInstance().BagInfo) do
        local itemConfig = UIUtils.GetItemConfigById(item_id)
        if itemConfig then
            if itemConfig.show == 1 then
                local mainType = itemConfig.itemType
                if not self.AllData[mainType] then self.AllData[mainType] = {} end

                if not itemConfig.cost or itemConfig.cost == 0 then
                    for _, v in ipairs(bagData) do 
                        v.config = itemConfig
                        v.characterId = nil
                        table.insert(self.AllData[mainType], v)
                    end
                end

                if not self.AllData[UIUtils.ItemMainType.Consumables] then self.AllData[UIUtils.ItemMainType.Consumables] = {} end
                if itemConfig.cost and itemConfig.cost == 1 then
                    for _, v in ipairs(bagData) do 
                        v.config = itemConfig
                        v.characterId = nil
                        table.insert(self.AllData[UIUtils.ItemMainType.Consumables], v)
                    end
                end
            end
        end
    end
    for type, v in pairs(self.AllData) do
        if type == UIUtils.ItemMainType.Consumables
            or type == UIUtils.ItemMainType.TempProp then
            table.sort(v, function(a, b)
                if a.config.bagSort ~= b.config.bagSort then
                    if a.config.bagSort == 0 or b.config.bagSort == 0 then
                        return a.config.bagSort > b.config.bagSort
                    else
                        return a.config.bagSort < b.config.bagSort
                    end
                else
                    if a.config.rarity ~= b.config.rarity then
                        return a.config.rarity > b.config.rarity
                    else
                        return a.item_uuid < b.item_uuid
                    end
                end
            end)
        end
    end
end

function M:InitData()
    self.SaveGame_Backpack = self:GetSaveGameBackpack()

    self:InitBagInfo()

    --每个页签对应最大格子数量
    self.TabMaxCount = 0
    local tab = require("ClientDatas.d_player")
    for k, v in pairs(tab) do
        if v.id == 1 then
            self.TabMaxCount = v.param[1]
            break
        end
    end

    self.item_data = {}
    self.CurTabIndex = 0
end

function M:GetSaveGameBackpack()
    if not self.SaveGame_Backpack then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if UE.UGameplayStatics.DoesSaveGameExist('SG_SaveGame_Backpack_' .. gameInstance.account_id, 0) then
            self.SaveGame_Backpack = UE.UGameplayStatics.LoadGameFromSlot('SG_SaveGame_Backpack_' .. gameInstance.account_id, 0) 
        else
            local sg_backpackPath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/SG_Backpack.SG_Backpack_C'
            local sg_backpackClass = UE.UClass.Load(sg_backpackPath)
            self.SaveGame_Backpack = UE.UGameplayStatics.CreateSaveGameObject(sg_backpackClass)
        end
    end
    return self.SaveGame_Backpack
end

function M:SaveSaveGameBackpack()
    if UE.UKismetSystemLibrary.IsValid(self.SaveGame_Backpack) then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        self.SaveGame_Backpack.RecordBackpack.TabIndex = self.CurTabIndex
        UE.UGameplayStatics.SaveGameToSlot(self.SaveGame_Backpack, 'SG_SaveGame_Backpack_' .. gameInstance.account_id, 0)
    end
end

function M:InitUI()
    -- print("================InitUI")
    --self.UI_Com_UseWindow:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Exit.OnClicked:Clear()
    self.Exit.OnClicked:Add(self, self.OnClicked_Exit)

    self.TabList = {}
    self.TabList[UIUtils.ItemMainType.Weapon] = self.UI_tab_weapon
    self.TabList[UIUtils.ItemMainType.Equip] = self.UI_tab_equip
    self.TabList[UIUtils.ItemMainType.TempProp] = self.UI_tab_city_generated
    self.TabList[UIUtils.ItemMainType.Consumables] = self.UI_tab_srpg_generated

    self.UI_tab_weapon.GraphicsSet_1.OnGHSClicked:Add(self, self.OnClick_UI_Tab_Weapon)
    self.UI_tab_equip.GraphicsSet_1.OnGHSClicked:Add(self, self.OnClick_UI_Tab_Equip)
    self.UI_tab_city_generated.GraphicsSet_1.OnGHSClicked:Add(self, self.OnClick_UI_Tab_City_Generated)
    self.UI_tab_srpg_generated.GraphicsSet_1.OnGHSClicked:Add(self, self.OnClick_UI_Tab_Srpg_Generated)

    self.UI_ItemInfo.UI_Com_BagDetail.Btn_Refine.OnClicked:Add(self, self.OnClicked_Refine)
    self.UI_ItemInfo.UI_Com_BagDetail.Btn_Refine_short.OnClicked:Add(self, self.OnClicked_Refine)
    self.UI_ItemInfo.UI_Com_BagDetail.Btn_Level.OnClicked:Add(self, self.OnClicked_LevelUp)
    self.UI_ItemInfo.UI_Com_BagDetail.Btn_Level_short.OnClicked:Add(self, self.OnClicked_LevelUp)

    --生成器
    self.ItemList.BP_OnEntryInitialized:Clear()
    self.ItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.ItemList.BP_OnItemClicked:Clear()
    self.ItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    self.ItemList.BP_OnItemIsHoveredChanged:Add(self, function(wbp, item, bIsHovered)
        self:BP_OnItemIsHoveredChanged(item, bIsHovered)
    end)

    self.ItemList.BP_OnListViewScrolled:Add(self, function(wbp, offset, distanceRemaining)
        -- print('-------offset:' .. tostring(offset) .. ",DistanceRemaining:" .. tostring(distanceRemaining))
        self:BP_OnListViewScrolled(offset, distanceRemaining)
    end)

    self.UI_Com_SortFilter.OnFinishedSort:Add(self, function()
        self:RefreshTab(true)
        self:EnterAnimation()
    end)
    self.UI_Com_SortFilter.OnFinishedFilter:Add(self, function()
        self:RefreshTab(true)
        self:EnterAnimation()
    end)

    self.ItemList:SetScrollbarVisibility(UE.ESlateVisibility.Hidden)

    for index, btn in pairs(self.TabList) do
        btn.Normal_1:SetRenderOpacity(1)
        btn.SelectedPanel_1:SetRenderOpacity(0)
    end

    self:TabSelected(self.SaveGame_Backpack.RecordBackpack.TabIndex, true)

    self:PlayAnimation(self.In)
end

function M:TabSelected(idx, isFirst)
    if idx <= UIUtils.ItemMainType.Weapon or idx == UIUtils.ItemMainType.Weapon then
        local sortData = {}
        local sortTypes = { UIUtils.ESortType.Type, UIUtils.ESortType.Level, UIUtils.ESortType.Star }
        sortData.sortTypes = sortTypes
        sortData.canFilter = false
        self.UI_Com_SortFilter:RefreshData(sortData)
        self.UI_Com_SortFilter:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    elseif idx == UIUtils.ItemMainType.Equip then
        local sortData = {}
        local SortTypes = { UIUtils.ESortType.Type, UIUtils.ESortType.Star }
        local filterTypes = { UIUtils.EFilterType.EquipType, UIUtils.EFilterType.MainProperty, UIUtils.EFilterType.Rune }
        sortData.sortTypes = SortTypes
        sortData.filterTypes = filterTypes
        sortData.canFilter = false
        self.UI_Com_SortFilter:RefreshData(sortData)
        self.UI_Com_SortFilter:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    else
        self.UI_Com_SortFilter:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    if idx <= UIUtils.ItemMainType.Weapon then idx = UIUtils.ItemMainType.Weapon end
    if self.CurTabIndex == idx then return end
    --self.UI_Money:SetVisibility(self.CurTabIndex == UIUtils.ItemMainType.Consumables and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    for index, btn in pairs(self.TabList) do
        if index == self.CurTabIndex then
            --btn:PlayAnimationReverse(btn.In, 1, false)
            btn:StopAllAnimations()
            btn.Normal_1:SetRenderOpacity(1)
            btn.SelectedPanel_1:SetRenderOpacity(0)
        elseif index == idx then
            btn:PlayAnimationForward(btn.In, 1, false)
        else
            -- btn.Normal_1:SetRenderOpacity(1)
            -- btn.SelectedPanel_1:SetRenderOpacity(0)
        end
    end

    self.CurTabIndex = idx

    self.InitHideItemUI = true
    self:RefreshTab(true)

    --延时0.5s 列表的item可能还没初始化完
    -- UE.UKismetSystemLibrary.K2_SetTimerDelegate(
    --     { self, self.EnterAnimation }, 
    --     0.25, 
    --     false
    -- )
    self:EnterAnimation()
end

function M:EnterAnimation()
    self.Time1 = 0.05 --每行时间间隔
    self.Time2 = 0.15 --一行的所有item的间隔 /列数

    self.MaxItemNumInDisplay = 30
    self.minValue = math.min(self.MaxItemNumInDisplay, #self.CurItemDataList)

    self.InitAnimationIndex = 0
    self.DoAnimationIndexList = {}
    self.PastTime = 0
    self.StartPlayAnim = self.minValue > 0 
end

function M:Tick(MyGeometry, InDeltaTime)
    if self.StartPlayAnim then
        local uiNum = self.ItemList:GetDisplayedEntryWidgets():Length()
        local itemNum = self.minValue
        if uiNum >= itemNum then
            self.PastTime = self.PastTime + InDeltaTime
            for i = 1, self.minValue do 
                local curTime = self.Time1 + math.ceil((i - 1) / 6) * self.Time1 + (i - 1) % 6 * (self.Time2 / 6.0)
               
                local find = false
                for _, index in ipairs(self.DoAnimationIndexList) do 
                    if index == i then 
                        find = true
                        break
                    end
                end
                if not find then
                    if self.PastTime >= curTime then
                        --优化节点
                        if self.InitHideItemUI then
                            self.InitHideItemUI = false
                        end
                        self:InitPlayAnimation(i)
                    end
                end
            end
        end
    end
end 

function M:InitPlayAnimation(index)
    local widgets = self.ItemList:GetDisplayedEntryWidgets()
    -- print('----index:' .. tostring(index) .. ',array:' .. tostring(#self.DoAnimationIndexList) .. ', count:' .. tostring(widgets:Length()))
    if index <= widgets:Length() then
        local widget = widgets:Get(index)
        if widget then 
            --widget:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            widget:StopAllAnimations()
            widget:PlayAnimationForward(widget.danru, 1, false)
        else
            LOG_ERROR('----not find ui:' .. tostring(index))
        end
    else
        print('--------error index:' .. tostring(index))
    end
    table.insert(self.DoAnimationIndexList, index)
    if #self.DoAnimationIndexList >= self.minValue then
        self.StartPlayAnim = false
        self.InitHideItemUI = false

        --强制设置所有ui显示
        -- for i = 1, widgets:Length() do 
        --     local ui = widgets:Get(i)
        --     ui.Panel_Bg:SetRenderOpacity(1)
        -- end
    end
end

function M:GetItemDataByTabIndex()
    self.CurItemDataList = {}
    local tabData = self.AllData[self.CurTabIndex] or {}
    for i = 1, #tabData do
        table.insert(self.CurItemDataList, tabData[i])
    end
    --非局类道具 
    if self.CurTabIndex == UIUtils.ItemMainType.TempProp then
        --获取皮肤卡
        local skins = self.AllData[UIUtils.ItemMainType.Skin] or {}
        for i = 1, #skins do
            table.insert(self.CurItemDataList, skins[i])
        end
    elseif self.CurTabIndex == UIUtils.ItemMainType.Weapon then
        local sortData = self.UI_Com_SortFilter:GetSortData()
        if sortData.selectedSortType == UIUtils.ESortType.Level then
            table.sort(self.CurItemDataList, function(a, b)
                if a.weapon_info.exp ~= b.weapon_info.exp then
                    if sortData.sortOrderUp then
                        return a.weapon_info.exp > b.weapon_info.exp
                    else
                        return a.weapon_info.exp < b.weapon_info.exp
                    end
                else
                    if a.config.id ~= b.config.id then
                        return a.config.id < b.config.id
                    else
                        return a.item_uuid < b.item_uuid
                    end
                end
            end)
        elseif sortData.selectedSortType == UIUtils.ESortType.Type then
            table.sort(self.CurItemDataList, function(a, b)
                if a.config.subType ~= b.config.subType then
                    if sortData.sortOrderUp then
                        return a.config.subType > b.config.subType
                    else
                        return a.config.subType < b.config.subType
                    end
                else
                    if a.config.id ~= b.config.id then
                        return a.config.id < b.config.id
                    else
                        return a.item_uuid < b.item_uuid
                    end
                end
            end)
        elseif sortData.selectedSortType == UIUtils.ESortType.Star then
            table.sort(self.CurItemDataList, function(a, b)
                if a.config.rarity ~= b.config.rarity then
                    if sortData.sortOrderUp then
                        return a.config.rarity > b.config.rarity
                    else
                        return a.config.rarity < b.config.rarity
                    end
                else
                    if a.config.id ~= b.config.id then
                        return a.config.id < b.config.id
                    else
                        return a.item_uuid < b.item_uuid
                    end
                end
            end)
        end
    elseif self.CurTabIndex == UIUtils.ItemMainType.Equip then
        local sortData = self.UI_Com_SortFilter:GetSortData()
        --filter
        local filterItemData = {}
        local filterData = self.UI_Com_SortFilter.FilterData
        for filterType, tags in pairs(filterData) do
            if filterType == UIUtils.EFilterType.EquipType and #tags > 0 then
                for index, itemData in ipairs(self.CurItemDataList) do
                    if tags[itemData.config.subType] then
                        table.insert(filterItemData, itemData)
                    end
                end
                self.CurItemDataList = filterItemData
                filterItemData = {}
            end
            if filterType == UIUtils.EFilterType.MainProperty then
                local tag_count = 0
                for i, v in pairs(tags) do
                    tag_count = tag_count + 1
                end
                if tag_count > 0 then
                    for index, itemData in ipairs(self.CurItemDataList) do
                        for _, arm_random_attribute_info in ipairs(itemData.arm_info.arm_random_attribute_infos) do
                            local equipConfig = require("ClientDatas.d_equip")[itemData.item_id]
                            local weight_index = arm_random_attribute_info.weight_index
                            local attr_id = equipConfig.randomAtt[weight_index]
                            local attrConfig = require("ClientDatas.d_attributes")[attr_id]
                            if tags[attrConfig.showTag] then
                                table.insert(filterItemData, itemData)
                            end
                        end
                    end
                    self.CurItemDataList = filterItemData
                    filterItemData = {}
                end
            end
            if filterType == UIUtils.EFilterType.Rune then
                local tag_count = 0
                for i, v in pairs(tags) do
                    tag_count = tag_count + 1
                end
                if tag_count > 0 then
                    for index, itemData in ipairs(self.CurItemDataList) do
                        for _, arm_rune_info in ipairs(itemData.arm_info.arm_rune_infos) do
                            if tags[arm_rune_info.rune_id] then
                                table.insert(filterItemData, itemData)
                            end
                        end
                    end
                    self.CurItemDataList = filterItemData
                    filterItemData = {}
                end
            end
        end
        --sort
        if sortData.selectedSortType == UIUtils.ESortType.Type then
            table.sort(self.CurItemDataList, function(a, b)
                if a.config.subType ~= b.config.subType then
                    if sortData.sortOrderUp then
                        return a.config.subType > b.config.subType
                    else
                        return a.config.subType < b.config.subType
                    end
                else
                    return a.item_uuid < b.item_uuid
                end
            end)
        elseif sortData.selectedSortType == UIUtils.ESortType.Star then
            table.sort(self.CurItemDataList, function(a, b)
                if a.config.rarity ~= b.config.rarity then
                    if sortData.sortOrderUp then
                        return a.config.rarity > b.config.rarity
                    else
                        return a.config.rarity < b.config.rarity
                    end
                else
                    return a.item_uuid < b.item_uuid
                end
            end)
        end
    end
end

function M:RefreshTab(bForceFirst)
    self:GetItemDataByTabIndex()
    --当前选中标签获取对应数据
    if #self.CurItemDataList == 0 then --判断是否有数据或者数据个数0
        self.UI_ItemInfo:SetVisibility(UE.ESlateVisibility.Hidden)
        self.nothing:SetVisibility(UE.ESlateVisibility.Visible)
        if self.CurTabIndex == UIUtils.ItemMainType.Weapon then
            self.Panel_Nothing:SetVisibility(UE.ESlateVisibility.Hidden)
            local arrList = string.split('9003,9005', ',')
            for i, str in ipairs(arrList) do
                local linkId = tonumber(str)
                if linkId and linkId > 0 then
                    local d_bag_item_link = require('ClientDatas.d_bag_item_link')
                    local config = d_bag_item_link[linkId]
                    if config then
                        local itemUI = self['UI_SourceItem' .. tostring(i)]
                        itemUI.Text_Des:SetText(Database.L10n(config.desc))
                        itemUI.Btn_Normal.OnClicked:Add(self, function()
                            -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                            -- gameInstance:OpenLink(linkId, '')
                        end)
                    end
                end
            end
        elseif self.CurTabIndex == UIUtils.ItemMainType.Equip then
            self.Panel_Nothing:SetVisibility(UE.ESlateVisibility.Hidden)
            local arrList = string.split('9006', ',')
            for i, str in ipairs(arrList) do
                local linkId = tonumber(str)
                if linkId and linkId > 0 then
                    local d_bag_item_link = require('ClientDatas.d_bag_item_link')
                    local config = d_bag_item_link[linkId]
                    if config then
                        local itemUI = self['UI_SourceItem' .. tostring(i)]
                        itemUI:SetVisibility(UE.ESlateVisibility.Visible)

                        itemUI.Text_Des:SetText(Database.L10n(config.desc))
                        itemUI.Btn_Normal.OnClicked:Add(self, function()
                            -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                            -- gameInstance:OpenLink(linkId, '')
                        end)
                    end
                end
            end
            local itemUI = self['UI_SourceItem' .. tostring(2)]
            itemUI:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.Panel_Nothing:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    else
        self.UI_ItemInfo:SetVisibility(UE.ESlateVisibility.Visible)
        self.nothing:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Panel_Nothing:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    --容量
    local allCount = #self.CurItemDataList
    -- for _, v in pairs(self.CurItemDataList) do 
    --     print("=====curitemdata:" .. tostring(table.dump(v)))
    --     allCount = allCount + v.ItemNum
    -- end
    self.Text_Content:SetText(tostring(allCount) .. '/' .. tostring(self.TabMaxCount))
    
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    --队列中排序(简单)
    self.ItemDataSource = {}

    for i = 1, #self.CurItemDataList do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = i
        ItemData.ItemId = self.CurItemDataList[i].item_id
        table.insert(self.ItemDataSource, ItemData)
    end

    --默认选中第一个
    if bForceFirst then
        self.SelectedItemIndex = 1
    else
        if self.SelectedItemIndex > allCount then
            self.SelectedItemIndex = allCount
        end
        if self.SelectedItemIndex <= 0 then
            self.SelectedItemIndex = 1
        end
    end
    local curScrollOffset = self.ItemList:GetScrollOffset()
    self.ItemList:ClearListItems()
    self.ItemList:BP_SetListItems(self.ItemDataSource)
    if bForceFirst then
        self.ItemList:ScrollToTop()
    else
        self.ItemList:SetScrollOffset(curScrollOffset)
        --self.ItemList:ScrollToBottom()
    end

end

function M:BP_OnEntryInitialized(item, widget)
    print('----BP_OnEntryInitialized' .. item.Index)
    widget.Index = item.Index
    widget.ItemId = item.ItemId
    local data = self.CurItemDataList[item.Index]
    local bIsSelected = self.SelectedItemIndex == item.Index
    UIUtils.RefreshUIItem(widget, data, bIsSelected)
    if bIsSelected then
        self:RefreshItem(widget, data, bIsSelected)
    end
   
    if widget:IsPlayingAnimation(widget.danru) then
        widget:StopAnimation(widget.danru)
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.DelayUntilNextTick(self)
            widget:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            widget.Panel_Bg:SetRenderOpacity(1)
            if self.StartPlayAnim and self.InitHideItemUI then
                if item.index > self.MaxItemNumInDisplay then
                    widget:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    widget.Panel_Bg:SetRenderOpacity(1)
                else
                    widget.Panel_Bg:SetRenderOpacity(0)
                end
            else
                widget:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                widget.Panel_Bg:SetRenderOpacity(1)
            end
        end))
    else
        widget:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        widget.Panel_Bg:SetRenderOpacity(1)
        --print('----index:' .. tostring(item.Index) .. ',InitHideItemUI:' .. tostring(self.InitHideItemUI) .. ",StartPlayAnim:" .. tostring(self.StartPlayAnim))
        if self.StartPlayAnim and self.InitHideItemUI then
            if item.index > self.MaxItemNumInDisplay then
                widget:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                widget.Panel_Bg:SetRenderOpacity(1)
            else
                widget.Panel_Bg:SetRenderOpacity(0)
            end
        else
            widget:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            widget.Panel_Bg:SetRenderOpacity(1)
            -- if self.ItemList:IsRefreshPending() then
            --     widget.Panel_Bg:SetRenderOpacity(1)
            -- else
            --     widget.Panel_Bg:SetRenderOpacity(1)
            -- end
        end
    end
end

function M:BP_OnItemClicked(item)
    print("====itemClicked:" .. tostring(self.SelectedItemIndex) .. ",index:" .. tostring(item.Index) .. ",id:" .. tostring(item.ItemId))
    if self.SelectedItemIndex == item.Index then return end
    local lastIndex = self.SelectedItemIndex
    self.SelectedItemIndex = item.Index
    local widgets = self.ItemList:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.Index == lastIndex or widget.Index == item.Index then
            local data = self.CurItemDataList[widget.Index]
            self:RefreshItem(widget, data, widget.Index == item.Index)
        end
    end
end

function M:RefreshItem(ui, data, bIsSelected)
    ui.selected:SetVisibility(bIsSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    if bIsSelected then
        self.item_data = data
        self.UI_ItemInfo:RefreshUI(data, true, self)
    end
end

function M:BP_OnItemIsHoveredChanged(item, bIsHovered)
    -- print("====itemClicked:" .. tostring(self.SelectedItemIndex) .. ",index:" .. tostring(item.Index) .. ",id:" .. tostring(item.ItemId) .. ',bIsHovered:' .. tostring(bIsHovered))

end

function M:BP_OnListViewScrolled(offset, distanceRemaining)
    --print("---StartPlayAnim:" .. tostring(self.StartPlayAnim))
    if self.StartPlayAnim then
        self.StartPlayAnim = false
        self.InitHideItemUI = false
        
    end
    local widgets = self.ItemList:GetDisplayedEntryWidgets()
    --print('---ui count:' .. tostring(widgets:Length()))
    --强制设置所有ui显示
    for i = 1, widgets:Length() do 
        local ui = widgets:Get(i)
        if ui.Panel_Bg:GetRenderOpacity() < 1 then
            ui.Panel_Bg:SetRenderOpacity(1)
        end
    end
end

----------------------------------------------------------------------
--- 
function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:OnClick_UI_Tab_Weapon()
    self:TabSelected(UIUtils.ItemMainType.Weapon)
end

function M:OnClick_UI_Tab_Equip()
    self:TabSelected(UIUtils.ItemMainType.Equip)
end

function M:OnClick_UI_Tab_City_Generated()
    self:TabSelected(UIUtils.ItemMainType.TempProp)
end

function M:OnClick_UI_Tab_Srpg_Generated()
    self:TabSelected(UIUtils.ItemMainType.Consumables)
end

function M:OnClicked_Refine()
    -- UIUtils.ShowNotify(self, Database.L10n(266))
    local item_data = self.item_data
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_weapon_refined')
    ui:SetBackUI(self, item_data, true)
end

function M:OnClicked_LevelUp()
    -- UIUtils.ShowNotify(self, Database.L10n(266))
    local item_data = self.item_data
    if self.item_data.config.itemType == UIUtils.ItemMainType.Equip then
        local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Levelup_Equip')
        ui:SetBackUI(self, item_data, true)
    elseif self.item_data.config.itemType == UIUtils.ItemMainType.Weapon then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance:OpenLink(9017, "") then
            local ui = gameInstance:GetUMG('UI_Levelup_weapon')
            ui:SetBackUI(self, item_data, true)
        end
    end
end

return M
