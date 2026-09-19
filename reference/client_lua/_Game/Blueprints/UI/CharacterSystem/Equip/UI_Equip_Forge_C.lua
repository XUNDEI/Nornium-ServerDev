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
local d_equip = require("ClientDatas.d_equip") 
local d_bag_item = require "ClientDatas.d_bag_item"
local d_equip_forge = require("ClientDatas.d_equip_forge")
local d_equip_forge_feed = require("ClientDatas.d_equip_forge_feed")
local d_bag_item_equip = require("ClientDatas.d_bag_item_equip")
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local FeedType = 
{
    Suit = 1,
    HightRarity = 2,
    HighAttr = 3,
    DoubleMaterial_HightRarity = 4,
    DoubleMaterial_HightAttr = 5,
    ReturnMaterial = 6
}

---@type UI_Equip_forge_C
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
    --生成器
    self.List.BP_OnEntryInitialized:Clear()
    self.List.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.List.BP_OnItemClicked:Clear()
    self.List.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    --投料生成器
    self.FeedList.BP_OnEntryInitialized:Clear()
    self.FeedList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnFeedEntryInitialized(item, widget)
    end)
    --投料点击事件
    self.FeedList.BP_OnItemClicked:Clear()
    self.FeedList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnFeedItemClicked(item)
    end)

    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
    self.GHSButtonForge.OnGHSClicked:Add(self, self.OnClickedForge)
    self.GHSButtonFeed.OnGHSClicked:Add(self, self.OnClickedFeed)
    self.CloseButton.OnGHSClicked:Add(self, self.OnCloseFeedPanel)
    self.CancelButton.OnGHSClicked:Add(self, self.OnClickedFeedCancel)
    self.OKButton.OnGHSClicked:Add(self, self.OnClickedFeedOK)

    self.GHSSlider.OnGHSValueChanged:Add(self, self.OnSlider_Value_Changed)
    self.BtnMinus.OnGHSClicked:Add(self, self.OnClicked_Minus)
    self.BtnAdd.OnGHSClicked:Add(self, self.OnClicked_Add)

    self.MindEngine.OnCheckStateChanged:Add(self, function(self, isOn)  
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Heart)
        end
    end)
    self.LunglobeTurbine.OnCheckStateChanged:Add(self, function(self, isOn)  
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Lung)
        end
    end)
    
    self.RenalGlandBurners.OnCheckStateChanged:Add(self, function(self, isOn)  
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.kidney)
        end
    end)
    
    self.HepaticCrystal.OnCheckStateChanged:Add(self, function(self, isOn)  
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Liver)
        end
    end)

    self.GastricParietal.OnCheckStateChanged:Add(self, function(self, isOn) 
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Stomach)
        end
    end)
    self.BrainComputer.OnCheckStateChanged:Add(self, function(self, isOn) 
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Brain)
        end
    end)
    self:InitData()
    self.MindEngine:SetIsCheckedAndFireEvent(true)
    self.LastClickedBtnIndex = 1
    self.Img_HightIcon:SetRenderTranslation(UE.FVector2D(70, 0))

    NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
    MessageManager:GetInstance():AddListener("OnMsg_Bag_Get_New_Item", self)
    MessageManager:GetInstance():AddListener("OnMsg_Ntf_Item_Info", self)

    self.ExplainBtn.OnGHSClicked:Add(self, self.OnClicked_ExplainBtn)
end

function M:Destruct()
    if self.NPC then
        self.NPC:K2_DestroyActor()
    end
    NetworkMessageManager:GetInstance():RemoveListener("ntf_item_info", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Bag_Get_New_Item", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Ntf_Item_Info", self)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitData()
    self.CurTabIndex = 1
    self.SelectedFeedIndex = 0
    self.ClickedFeedIndex = 1
    self.BPItemInfos = {}
    self.FeedItemInfos = {}
    self.BagBPItemInfos = {}
    self.ActivedBPItemIds = {}
    self.ReturnMaterial = {}

    self.MaxMoveTime = 0.2

    local bagBP = BackpackSystem:GetInstance():GetAllItemByType(UIUtils.ItemMainType.TempProp, UIUtils.ItemTempPropType.ForgeBP)
    local activedArmBP = BackpackSystem:GetInstance().PlayerInfo.arm_blueprint_ids
    for _, value in ipairs(bagBP) do
        self.BagBPItemInfos[value.item_id] = value
    end

    for _, value in ipairs(activedArmBP) do
        self.ActivedBPItemIds[value.blueprintId] = value
    end

    for _, value in pairs(d_equip_forge) do
        value.item_equip_config = d_bag_item_equip[value.equipId]
        value.actived = self.ActivedBPItemIds[value.id] and true or false
        if not self.BPItemInfos[value.item_equip_config.subType] then
            self.BPItemInfos[value.item_equip_config.subType] = {}
        end
        table.insert(self.BPItemInfos[value.item_equip_config.subType], value)
    end

    for _, value in pairs(d_bag_item) do
        if value.itemType == UIUtils.ItemMainType.TempProp and value.subType == UIUtils.ItemTempPropType.Material then
            if value.subParam[1] and value.subParam[1] <= #d_equip_forge_feed then
                --一种锻造投料只会对应一个bag item
                value.feed_config = d_equip_forge_feed[value.subParam[1]]
                value.count = BackpackSystem:GetInstance():GetItemCount(value.id)
                value.item_uuid = 0
                if value.count > 0 then
                    local itemInfo = BackpackSystem:GetInstance().BagInfo[value.id]
                    value.item_uuid = itemInfo[1].item_uuid
                end
                self.FeedItemInfos[value.subParam[1]] = value
            end
        end
    end

    for i = 1, 6 do
        if self.BPItemInfos[i] and #self.BPItemInfos[i] > 1 then
            table.sort(self.BPItemInfos[i], function(a, b)
                if a.actived == true and b.actived == false then
                    return true
                elseif a.actived == false and b.actived == true then
                    return false
                elseif a.actived == b.actived then
                    if a.item_equip_config.rarity ~= b.item_equip_config.rarity then
                        return a.item_equip_config.rarity > b.item_equip_config.rarity
                    else
                        return a.item_equip_config.id > b.item_equip_config.id
                    end
                end
            end)
        end
    end

    local path = string.format("'/Game/_Game/Blueprints/NPCs/BP_NPC_Forge.BP_NPC_Forge_C'") 
    local playerClass = LoadClass(path)
    local trans = UE.UKismetMathLibrary.MakeTransform(
        UE.FVector(400, 350, 100),
        UE.FRotator(0, 0, 0),
        UE.FVector(1, 1, 1))
    self.NPC = self:GetWorld():SpawnActor(playerClass, trans,
        UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
end

function M:RefreshFeedData()
    for _, value in pairs(self.FeedItemInfos) do
        value.count = BackpackSystem:GetInstance():GetItemCount(value.id)
        value.item_uuid = 0
        if value.count > 0 then
            local itemInfo = BackpackSystem:GetInstance().BagInfo[value.id]
            value.item_uuid = itemInfo[1].item_uuid
        end
        self.FeedItemInfos[value.subParam[1]] = value
    end
end

function M:InitUI()
    self.ItemDataSource = {}
    if self.BPItemInfos[self.CurTabIndex] then
        for index, item_info in pairs(self.BPItemInfos[self.CurTabIndex]) do
            local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            local ItemData = NewObject(ItemClass)
            ItemData.Index = index
            ItemData.ItemId = item_info.id
            table.insert(self.ItemDataSource, ItemData)
        end
    end
    self.List:ClearListItems()
    self.List:BP_SetListItems(self.ItemDataSource)
end

function M:InifFeedUI()
    self.FeedItemDataSource = {}
    for index, item_info in pairs(d_equip_forge_feed) do
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        local ItemData = NewObject(ItemClass)
        ItemData.Index = index
        ItemData.ItemId = item_info.id
        table.insert(self.FeedItemDataSource, ItemData)
    end
    self.FeedList:ClearListItems()
    self.FeedList:BP_SetListItems(self.FeedItemDataSource)

    local ItemInfo = self.FeedItemInfos[self.ClickedFeedIndex]
    if ItemInfo.count > 0 then
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
        self.OKButton:SetColorAndOpacity(opacity)
        self.OKButton:SetVisibility(UE.ESlateVisibility.Visible)
    else
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
        self.OKButton:SetColorAndOpacity(opacity)
        self.OKButton:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    end

    if self.ClickedFeedIndex == self.SelectedFeedIndex then
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
        self.CancelButton:SetColorAndOpacity(opacity)
        self.CancelButton:SetVisibility(UE.ESlateVisibility.Visible)
    else
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
        self.CancelButton:SetColorAndOpacity(opacity)
        self.CancelButton:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    end
end

function M:Tick(MyGeometry, InDeltaTime)
    if self.bStartMove then
        self.StartMoveTime = self.StartMoveTime + InDeltaTime
        if self.StartMoveTime > self.MaxMoveTime then
            self.StartMoveTime = self.MaxMoveTime
            self.bStartMove = false
        end
        local length = self.ImgEndPosX - self.ImgStartPosX
        local fadeRate = self.StartMoveTime / self.MaxMoveTime
        -- print('---length:' .. tostring(length) .. ",rate:" .. tostring(fadeRate))
        local posX = self.ImgStartPosX + length * fadeRate
        -- print('--- StartMoveTime:' .. tostring(self.StartMoveTime) .. ",posX:" .. tostring(posX))
        -- UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.Img_HightIcon):SetPosition(UE.FVector2D(posX, 0))
        self.Img_HightIcon:SetRenderTranslation(UE.FVector2D(posX, 0))
    end
end

function M:TabSelected(equip_type)
    if self.LastClickedBtnIndex then
        if self.LastClickedBtnIndex ~= equip_type then
            local startPosX = 70
            local offsetX = (800 - 70) / 5
            self.ImgStartPosX = startPosX + (self.LastClickedBtnIndex - 1) * offsetX
            self.ImgEndPosX = startPosX + (equip_type - 1) * offsetX

            self.StartMoveTime = 0
            self.bStartMove = true
            -- UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.Img_HightIcon):SetPosition(endPos)

            self.LastClickedBtnIndex = equip_type
        end
    end
    self:PlayAnimationForward(self.switch)

    self.CurTabIndex = equip_type
    self.SelectedItemIndex = 1
    self:InitUI()
    self:RefreshSidePanel()
end

function M:BP_OnEntryInitialized(item, widget)
    widget.Index = item.Index
    widget.ItemId = item.ItemId
    local item_data = {}
    item_data.arm_info = { exp = 0, locked = false, break_times = 0 }
    item_data.config = self.BPItemInfos[self.CurTabIndex][widget.Index].item_equip_config
    item_data.item_id = item_data.config.id
    widget.UI_Com_ItemBox:RefreshUI(item_data, false)

    local canActive = self.BagBPItemInfos[item.ItemId] and true or false
    local actived = self.BPItemInfos[self.CurTabIndex][widget.Index].actived
    local forge_id = self.BPItemInfos[self.CurTabIndex][widget.Index].id

    if self.ActivedBPItemIds[forge_id] and self.ActivedBPItemIds[forge_id].isNew then
        widget.ImageNew:SetVisibility(UE.ESlateVisibility.Visible)
    else
        widget.ImageNew:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    if actived then
        widget.ImageMask:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.ImageCanActivate:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.NeverOwnsPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        widget.ImageNew:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.ImageMask:SetVisibility(UE.ESlateVisibility.Visible)
        widget.ImageCanActivate:SetVisibility(canActive and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        widget.NeverOwnsPanel:SetVisibility(canActive and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    end

    --选中
    widget.UI_Com_ItemBox.GHSButtonLock:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.UI_Com_ItemBox:RefreshSelectState(self.SelectedItemIndex == item.Index)
end

function M:BP_OnItemClicked(item)
    if self.SelectedItemIndex == item.index then return end
    self.SelectedItemIndex = item.index

    --选中
    local widgets = self.List:GetDisplayedEntryWidgets()
    for _, widget in pairs(widgets) do
        local bIsSelected = widget.Index == item.Index
        widget.UI_Com_ItemBox:RefreshSelectState(bIsSelected)

        --New
        if bIsSelected then
            local forge_id = self.BPItemInfos[self.CurTabIndex][widget.Index].id
            if self.ActivedBPItemIds[forge_id] and self.ActivedBPItemIds[forge_id].isNew then
                self.ActivedBPItemIds[forge_id].isNew = false
                widget.ImageNew:SetVisibility(UE.ESlateVisibility.Hidden)
            end
        end
    end

    self:RefreshSidePanel()
end

function M:BP_OnFeedEntryInitialized(item, widget)
    widget.Index = item.Index
    widget.ItemId = item.ItemId
    local ItemInfo = self.FeedItemInfos[item.Index]
    if ItemInfo.rarityPath and ItemInfo.rarityPath ~= '' then
        local strArr = string.split(ItemInfo.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            widget.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if ItemInfo.iconPath and ItemInfo.iconPath ~= '' then
        local strArr = string.split(ItemInfo.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', ItemInfo.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            widget.icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    end
    widget.TextName:SetText(Database.L10n(ItemInfo.itemName))
    widget.TextDesc:SetText(Database.L10n(ItemInfo.effectDesc))
    widget.image_selected:SetVisibility(widget.Index == self.ClickedFeedIndex and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    if ItemInfo.count > 0 then
        widget.NeverOwnsPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.TextCount:SetVisibility(UE.ESlateVisibility.Visible)
        widget.TextCount:SetText(Database.L10n(5014002) .. ItemInfo.count)
    else
        widget.NeverOwnsPanel:SetVisibility(UE.ESlateVisibility.Visible)
        widget.TextCount:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:BP_OnFeedItemClicked(item)
    if self.ClickedFeedIndex == item.index then return end
    self.ClickedFeedIndex = item.index

    --选中
    local widgets = self.FeedList:GetDisplayedEntryWidgets()
    for _, widget in pairs(widgets) do
        local bIsSelected = widget.Index == item.Index
        widget.image_selected:SetVisibility(bIsSelected and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end

    local ItemInfo = self.FeedItemInfos[item.Index]
    if ItemInfo.count > 0 then
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
        self.OKButton:SetColorAndOpacity(opacity)
        self.OKButton:SetVisibility(UE.ESlateVisibility.Visible)
    else
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
        self.OKButton:SetColorAndOpacity(opacity)
        self.OKButton:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    end

    if self.ClickedFeedIndex == self.SelectedFeedIndex then
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
        self.CancelButton:SetColorAndOpacity(opacity)
        self.CancelButton:SetVisibility(UE.ESlateVisibility.Visible)
    else
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
        self.CancelButton:SetColorAndOpacity(opacity)
        self.CancelButton:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    end
end

function M:RefreshSidePanel()
    --稀有度背景图片
    self.forge_count = 1
    self.max_forge_num = 0
    local ItemInfo = self.BPItemInfos[self.CurTabIndex][self.SelectedItemIndex].item_equip_config
    if ItemInfo.rarityPath and ItemInfo.rarityPath ~= '' then
        local strArr = string.split(ItemInfo.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            self.UI_Item_BP.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    if ItemInfo.rarity <= 6 then
        self.UI_Item_BP.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.UI_Item_BP.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end

    --icon
    if ItemInfo.iconPath and ItemInfo.iconPath ~= '' then
        local strArr = string.split(ItemInfo.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', ItemInfo.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            self.UI_Item_BP.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    end
    self.UI_Item_BP.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
    self.UI_Item_BP.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
    self.TextName:SetText(Database.L10n(ItemInfo.itemName))

    self.UI_Item_BP.Img_bg.OnMouseButtonDownEvent:Unbind()
    self.UI_Item_BP.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
        UIUtils.ShowItemInfo(ItemInfo.id)
        return UE.UWidgetBlueprintLibrary.Handled()
    end)

    --符文几率
    local equip_info = d_equip[ItemInfo.id]
    local rune_num = #equip_info.randomRune / 2
    local sum_weight = 0
    local weights = {}
    for i = 1, rune_num do
        sum_weight = sum_weight + equip_info.randomRune[i * 2]
    end

    --锻造消耗
    local forge_config = self.BPItemInfos[self.CurTabIndex][self.SelectedItemIndex]
    local item_num = #forge_config.item / 2
    for i = 1, 3 do
        self["UI_Item_" .. i]:SetVisibility(UE.ESlateVisibility.Collapsed)
        self["DoubleBorder_" .. i]:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
    local enough_goods = true
    if item_num > 0 then
        local item_index = 0
        for i = 1, item_num do
            local cosume_id = forge_config.item[i * 2 - 1]
            if d_bag_item[cosume_id].itemType == UIUtils.ItemMainType.Currency then
                --货币
                local iconObject = LoadObject(string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', cosume_id, cosume_id))
                self.ImageCurrency:SetBrushFromAtlasInterface(iconObject)
                local has_num = BackpackSystem:GetInstance():GetItemCount(cosume_id)
                local can_forge_count = math.floor(has_num / forge_config.item[i * 2])
                if can_forge_count > 1 then
                    if self.max_forge_num > 0 then
                        if can_forge_count < self.max_forge_num then
                            self.max_forge_num = can_forge_count
                        end
                    else
                        self.max_forge_num = can_forge_count
                    end
                else
                    self.max_forge_num = 1
                end
                if has_num < forge_config.item[i * 2] then
                    self.TemaranRichText_NeedGold:SetText(string.format(
                        '<span color="#de5d24">%d</><span color="#FFFFFFFF">/%d</>', has_num, forge_config.item[i * 2]))
                    enough_goods = false
                else
                    self.TemaranRichText_NeedGold:SetText(string.format(
                        '<span color="#FFFFFFFF">%d/%d</>', has_num, forge_config.item[i * 2]))
                end
            else
                self["UI_Item_" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
                self["DoubleBorder_" .. i]:SetVisibility(UE.ESlateVisibility.Hidden)
                item_index = item_index + 1
                --稀有度背景图片
                if d_bag_item[cosume_id].rarityPath and d_bag_item[cosume_id].rarityPath ~= '' then
                    local strArr = string.split(d_bag_item[cosume_id].rarityPath, '/')
                    local littePath = strArr[#strArr]
                    local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                    local itemRarityPic = LoadObject(rarityPath)
                    if itemRarityPic then
                        self["UI_Item_" .. item_index].wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                    end
                end

                if d_bag_item[cosume_id].rarity <= 6 then
                    self["UI_Item_" .. item_index].wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
                else
                    self["UI_Item_" .. item_index].wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                end

                --icon
                if d_bag_item[cosume_id].iconPath and d_bag_item[cosume_id].iconPath ~= '' then
                    local strArr = string.split(d_bag_item[cosume_id].iconPath, '/')
                    local littePath = strArr[#strArr]
                    local iconResPath = string.format('/Game/_Game/%s.%s', d_bag_item[cosume_id].iconPath, littePath)
                    local iconRes = LoadObject(iconResPath)
                    if iconRes then
                        self["UI_Item_" .. item_index].wp_icon_res:SetBrushFromAtlasInterface(iconRes)
                    end
                end

                self["UI_Item_" .. item_index].Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
                self["UI_Item_" .. item_index].Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
                self["UI_Item_" .. item_index].TemaranRichText_Count:SetVisibility(UE.ESlateVisibility.Visible)
                local has_num = BackpackSystem:GetInstance():GetItemCount(cosume_id)
                local can_forge_count = math.floor(has_num / forge_config.item[i * 2])
                if can_forge_count > 1 then
                    if self.max_forge_num > 0 then
                        if can_forge_count < self.max_forge_num then
                            self.max_forge_num = can_forge_count
                        end
                    else
                        self.max_forge_num = can_forge_count
                    end
                else
                    self.max_forge_num = 1
                end
                if has_num < forge_config.item[item_index * 2] then
                    self["UI_Item_" .. item_index].TemaranRichText_Count:SetText(string.format(
                        '<span color="#de5d24">%d</><span color="#2E374CFF">/%d</>', has_num, forge_config.item[item_index * 2]))
                    enough_goods = false
                else
                    self["UI_Item_" .. item_index].TemaranRichText_Count:SetText(string.format(
                        '<span color="#2E374CFF">%d/%d</>', has_num, forge_config.item[item_index * 2]))
                end
                self["UI_Item_" .. item_index].Img_bg.OnMouseButtonDownEvent:Unbind()
                self["UI_Item_" .. item_index].Img_bg.OnMouseButtonDownEvent:Bind(self, function()
                    UIUtils.ShowItemInfo(cosume_id, forge_config.item[item_index * 2])
                    return UE.UWidgetBlueprintLibrary.Handled()
                end)
            end
        end
    end

    local config = require('ClientDatas.d_com_params')
    if self.max_forge_num > config[22].value2 then
        self.max_forge_num = config[22].value2 
    end

    if enough_goods and forge_config.actived then
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
        self.GHSButtonForge:SetColorAndOpacity(opacity)
        self.GHSButtonForge:SetVisibility(UE.ESlateVisibility.Visible)
    else
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
        self.GHSButtonForge:SetColorAndOpacity(opacity)
        self.GHSButtonForge:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    end
    self:RefreshSlider()

    if self.SelectedFeedIndex == 0 then
        --无投料
        for i = 1, rune_num do
            table.insert(weights, { rune_id = equip_info.randomRune[i * 2 - 1],
                prob = equip_info.randomRune[i * 2] / sum_weight * 100 })
        end
        if #weights > 1 then
            table.sort(weights, function(a, b) 
                return a.prob > b.prob
            end)
        end

        local randomRuneProb = 100
        for i = 1, 8 do 
            randomRuneProb = randomRuneProb - math.floor(weights[i].prob)
            self['UI_Forge_Rune_' .. i].UI_Forge_Rune_Attr.TextProb:SetText(math.floor(weights[i].prob) .. '%')
            self['UI_Forge_Rune_' .. i].UI_Forge_Rune_Attr.ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
            self['UI_Forge_Rune_' .. i].UI_Forge_Rune_Attr.AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)

            local rune_info = Database.Query("d_equip_rune", weights[i].rune_id)
            local strArr = string.split(rune_info.runeIcon, '/')
            local littePath = strArr[#strArr]
            local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
            if itemRarityPic then
                self['UI_Forge_Rune_' .. i].Rune:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end
        self.Border:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        local ItemInfo = self.FeedItemInfos[self.SelectedFeedIndex]
        if ItemInfo.subParam[1] == FeedType.Suit then
            --提升随出套装倾向符文的概率
            local addProb = ItemInfo.feed_config.number[1]
            for i = 1, rune_num do
                table.insert(weights, { rune_id = equip_info.randomRune[i * 2 - 1],
                    prob = equip_info.randomRune[i * 2]})
            end
            if #weights > 1 then
                table.sort(weights, function(a, b) 
                    return a.prob > b.prob
                end)
            end
            sum_weight = sum_weight + addProb * 4
            local randomRuneProb = 100
            for i = 1, 4 do 
                local prob = math.floor((weights[i].prob + addProb) / sum_weight * 100 + 0.5)
                randomRuneProb = randomRuneProb - prob
                self['UI_Forge_Rune_Attr_' .. i].TextProb:SetText(prob .. '%')
                self['UI_Forge_Rune_Attr_' .. i].ImageProbUp:SetVisibility(UE.ESlateVisibility.Visible)
                self['UI_Forge_Rune_Attr_' .. i].AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)

                local rune_info = Database.Query("d_equip_rune", weights[i].rune_id)
                local strArr = string.split(rune_info.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                if itemRarityPic then
                    self['Rune_' .. i]:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            self.UI_Forge_Rune_Attr_5.TextProb:SetText(math.floor(randomRuneProb) .. '%')
            self.UI_Forge_Rune_Attr_5.ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_Forge_Rune_Attr_5.AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Border:SetVisibility(UE.ESlateVisibility.Hidden)
        elseif ItemInfo.subParam[1] == FeedType.HightRarity then
            --提升随出高稀有度符文的概率
            local rune_ids = {}
            local addProb = ItemInfo.feed_config.number[1]
            local d_equip_rune = require("ClientDatas.d_equip_rune")
            for i = 1, rune_num do
                local rune_id = equip_info.randomRune[i * 2 - 1]
                if d_equip_rune[rune_id] and d_equip_rune[rune_id].rarity >= 6 then
                    sum_weight = sum_weight + addProb
                    rune_ids[rune_id] = 1
                    table.insert(weights, { rune_id = rune_id, prob = equip_info.randomRune[i * 2] + addProb })
                else
                    table.insert(weights, { rune_id = rune_id, prob = equip_info.randomRune[i * 2] })
                end
            end
            if #weights > 1 then
                table.sort(weights, function(a, b) 
                    return a.prob > b.prob
                end)
            end
            local randomRuneProb = 100
            for i = 1, 4 do 
                local prob = math.floor((weights[i].prob) / sum_weight * 100 + 0.5)
                local rune_id = weights[i].rune_id
                randomRuneProb = randomRuneProb - prob
                self['UI_Forge_Rune_Attr_' .. i].TextProb:SetText(prob .. '%')
                self['UI_Forge_Rune_Attr_' .. i].ImageProbUp:SetVisibility(rune_ids[rune_id] and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
                self['UI_Forge_Rune_Attr_' .. i].AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)

                local rune_info = Database.Query("d_equip_rune", weights[i].rune_id)
                local strArr = string.split(rune_info.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                if itemRarityPic then
                    self['Rune_' .. i]:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            self.UI_Forge_Rune_Attr_5.TextProb:SetText(math.floor(randomRuneProb) .. '%')
            self.UI_Forge_Rune_Attr_5.ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_Forge_Rune_Attr_5.AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Border:SetVisibility(UE.ESlateVisibility.Hidden)
        elseif ItemInfo.subParam[1] == FeedType.HighAttr then
            --符文初始属性值随机段，有一定概率随到更高
            for i = 1, rune_num do
                table.insert(weights, { rune_id = equip_info.randomRune[i * 2 - 1],
                    prob = equip_info.randomRune[i * 2] / sum_weight * 100 })
            end
            
            if #weights > 1 then
                table.sort(weights, function(a, b) 
                    return a.prob > b.prob
                end)
            end
    
            local randomRuneProb = 100
            for i = 1, 4 do 
                randomRuneProb = randomRuneProb - math.floor(weights[i].prob)
                self['UI_Forge_Rune_Attr_' .. i].TextProb:SetText(math.floor(weights[i].prob) .. '%')
                self['UI_Forge_Rune_Attr_' .. i].ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
                self['UI_Forge_Rune_Attr_' .. i].AttrBorder:SetVisibility(UE.ESlateVisibility.Visible)

                local rune_info = Database.Query("d_equip_rune", weights[i].rune_id)
                local strArr = string.split(rune_info.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                if itemRarityPic then
                    self['Rune_' .. i]:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            self.UI_Forge_Rune_Attr_5.TextProb:SetText(math.floor(randomRuneProb) .. '%')
            self.UI_Forge_Rune_Attr_5.ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_Forge_Rune_Attr_5.AttrBorder:SetVisibility(UE.ESlateVisibility.Visible)
            self.Border:SetVisibility(UE.ESlateVisibility.Hidden)
        elseif ItemInfo.subParam[1] == FeedType.DoubleMaterial_HightRarity then
            --锻造素材需求加倍，大幅提升随出高稀有度符文的概率
            if item_num > 0 then
                local item_index = 0
                for i = 1, item_num do
                    local cosume_id = forge_config.item[i * 2 - 1]
                    if d_bag_item[cosume_id].itemType ~= UIUtils.ItemMainType.Currency then
                        self["DoubleBorder_" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
                        item_index = item_index + 1
                        self["UI_Item_" .. item_index].TemaranRichText_Count:SetVisibility(UE.ESlateVisibility.Visible)
                        local has_num = BackpackSystem:GetInstance():GetItemCount(cosume_id)
                        local need_num = forge_config.item[item_index * 2] * 2
                        if has_num < need_num then
                            self["UI_Item_" .. item_index].TemaranRichText_Count:SetText(string.format(
                                '<span color="#de5d24">%d</><span color="#2E374CFF">/%d</>', has_num, need_num))
                        else
                            self["UI_Item_" .. item_index].TemaranRichText_Count:SetText(string.format(
                                '<span color="#2E374CFF">%d/%d</>', has_num, need_num))
                        end
                    end
                end
            end
            local rune_ids = {}
            local addProb = ItemInfo.feed_config.number[1]
            local d_equip_rune = require("ClientDatas.d_equip_rune")
            for i = 1, rune_num do
                local rune_id = equip_info.randomRune[i * 2 - 1]
                if d_equip_rune[rune_id] and d_equip_rune[rune_id].rarity >= 6 then
                    sum_weight = sum_weight + addProb
                    rune_ids[rune_id] = 1
                    table.insert(weights, { rune_id = rune_id, prob = equip_info.randomRune[i * 2] + addProb })
                else
                    table.insert(weights, { rune_id = rune_id, prob = equip_info.randomRune[i * 2] })
                end
            end

            if #weights > 1 then
                table.sort(weights, function(a, b) 
                    return a.prob > b.prob
                end)
            end

            local randomRuneProb = 100
            for i = 1, 4 do 
                local prob = math.floor((weights[i].prob) / sum_weight * 100 + 0.5)
                local rune_id = weights[i].rune_id
                randomRuneProb = randomRuneProb - prob
                self['UI_Forge_Rune_Attr_' .. i].TextProb:SetText(prob .. '%')
                self['UI_Forge_Rune_Attr_' .. i].ImageProbUp:SetVisibility(rune_ids[rune_id] and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
                self['UI_Forge_Rune_Attr_' .. i].AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)

                local rune_info = Database.Query("d_equip_rune", weights[i].rune_id)
                local strArr = string.split(rune_info.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                if itemRarityPic then
                    self['Rune_' .. i]:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            self.UI_Forge_Rune_Attr_5.TextProb:SetText(math.floor(randomRuneProb) .. '%')
            self.UI_Forge_Rune_Attr_5.ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_Forge_Rune_Attr_5.AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Border:SetVisibility(UE.ESlateVisibility.Hidden)
        elseif ItemInfo.subParam[1] == FeedType.DoubleMaterial_HightAttr then
            --锻造素材需求加倍，符文属性有大概率随到更高
            if item_num > 0 then
                local item_index = 0
                for i = 1, item_num do
                    local cosume_id = forge_config.item[i * 2 - 1]
                    if d_bag_item[cosume_id].itemType ~= UIUtils.ItemMainType.Currency then
                        self["DoubleBorder_" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
                        item_index = item_index + 1
                        self["UI_Item_" .. item_index].TemaranRichText_Count:SetVisibility(UE.ESlateVisibility.Visible)
                        local has_num = BackpackSystem:GetInstance():GetItemCount(cosume_id)
                        local need_num = forge_config.item[item_index * 2] * 2
                        if has_num < need_num then
                            self["UI_Item_" .. item_index].TemaranRichText_Count:SetText(string.format(
                                '<span color="#de5d24">%d</><span color="#2E374CFF">/%d</>', has_num, need_num))
                        else
                            self["UI_Item_" .. item_index].TemaranRichText_Count:SetText(string.format(
                                '<span color="#2E374CFF">%d/%d</>', has_num, need_num))
                        end
                    end
                end
            end
            for i = 1, rune_num do
                table.insert(weights, { rune_id = equip_info.randomRune[i * 2 - 1],
                    prob = equip_info.randomRune[i * 2] / sum_weight * 100 })
            end

            if #weights > 1 then
                table.sort(weights, function(a, b) 
                    return a.prob > b.prob
                end)
            end
    
            local randomRuneProb = 100
            for i = 1, 4 do 
                randomRuneProb = randomRuneProb - math.floor(weights[i].prob)
                self['UI_Forge_Rune_Attr_' .. i].TextProb:SetText(math.floor(weights[i].prob) .. '%')
                self['UI_Forge_Rune_Attr_' .. i].ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
                self['UI_Forge_Rune_Attr_' .. i].AttrBorder:SetVisibility(UE.ESlateVisibility.Visible)

                local rune_info = Database.Query("d_equip_rune", weights[i].rune_id)
                local strArr = string.split(rune_info.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                if itemRarityPic then
                    self['Rune_' .. i]:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            self.UI_Forge_Rune_Attr_5.TextProb:SetText(math.floor(randomRuneProb) .. '%')
            self.UI_Forge_Rune_Attr_5.ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_Forge_Rune_Attr_5.AttrBorder:SetVisibility(UE.ESlateVisibility.Visible)
            self.Border:SetVisibility(UE.ESlateVisibility.Hidden)
        elseif ItemInfo.subParam[1] == FeedType.ReturnMaterial then
            --有一定概率返还所有锻造素材
            local addProb = ItemInfo.feed_config.number[1]
            for i = 1, rune_num do
                table.insert(weights, { rune_id = equip_info.randomRune[i * 2 - 1],
                    prob = equip_info.randomRune[i * 2] })
            end

            if #weights > 1 then
                table.sort(weights, function(a, b) 
                    return a.prob > b.prob
                end)
            end

            sum_weight = sum_weight + addProb * 4
            local randomRuneProb = 100
            for i = 1, 4 do 
                local prob = math.floor((weights[i].prob + addProb) / sum_weight * 100 + 0.5)
                randomRuneProb = randomRuneProb - prob
                self['UI_Forge_Rune_Attr_' .. i].TextProb:SetText(prob .. '%')
                self['UI_Forge_Rune_Attr_' .. i].ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
                self['UI_Forge_Rune_Attr_' .. i].AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)

                local rune_info = Database.Query("d_equip_rune", weights[i].rune_id)
                local strArr = string.split(rune_info.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                if itemRarityPic then
                    self['Rune_' .. i]:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            self.UI_Forge_Rune_Attr_5.TextProb:SetText(math.floor(randomRuneProb) .. '%')
            self.UI_Forge_Rune_Attr_5.ImageProbUp:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_Forge_Rune_Attr_5.AttrBorder:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Border:SetVisibility(UE.ESlateVisibility.Visible)
        end
    end
end

function M:RefreshCurrency()
    local forge_config = self.BPItemInfos[self.CurTabIndex][self.SelectedItemIndex]
    local item_num = #forge_config.item / 2
    if item_num > 0 then
        for i = 1, item_num do
            local cosume_id = forge_config.item[i * 2 - 1]
            if d_bag_item[cosume_id].itemType == UIUtils.ItemMainType.Currency then
                local has_num = BackpackSystem:GetInstance():GetItemCount(cosume_id)
                local need_num = forge_config.item[i * 2] * self.forge_count
                if has_num < need_num then
                    self.TemaranRichText_NeedGold:SetText(string.format(
                        '<span color="#de5d24">%d</><span color="#FFFFFFFF">/%d</>', has_num, need_num))
                    enough_goods = false
                else
                    self.TemaranRichText_NeedGold:SetText(string.format(
                        '<span color="#FFFFFFFF">%d/%d</>', has_num, need_num))
                end
            end
        end
    end
end

function M:OnClickedForge()
    self:PlayAnimationForward(self.anniu, 1, false)
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    local msg = {}
    local blueprint_id = self.BPItemInfos[self.CurTabIndex][self.SelectedItemIndex].id
    local ItemInfo = self.FeedItemInfos[self.SelectedFeedIndex]
    msg.blueprint_id = blueprint_id
    msg.feed_item_uuid = ItemInfo and ItemInfo.item_uuid or nil
    msg.count = self.forge_count
    Client.send("req_arm_forge", msg)
    BackpackSystem:CacheChangeItem(msg)
end

function M:OnClickedFeed()
    self.ClickedFeedIndex = self.SelectedFeedIndex == 0 and 1 or self.SelectedFeedIndex
    self.FeedPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self:InifFeedUI()
end

function M:OnCloseFeedPanel()
    self.FeedPanel:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:OnClickedFeedCancel()
    if self.SelectedFeedIndex ~= 0 then
        self.SelectedFeedIndex = 0
        self:HideFeedItem()
        self:RefreshSidePanel()
    end
end

function M:HideFeedItem()
    self.FeedPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    self.EmptyFeed:SetVisibility(UE.ESlateVisibility.Visible)
    self.FeedItem:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:OnClickedFeedOK()
    self.FeedPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    self.SelectedFeedIndex = self.ClickedFeedIndex
    local ItemInfo = self.FeedItemInfos[self.SelectedFeedIndex]
    if ItemInfo.rarityPath and ItemInfo.rarityPath ~= '' then
        local strArr = string.split(ItemInfo.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            self.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if ItemInfo.iconPath and ItemInfo.iconPath ~= '' then
        local strArr = string.split(ItemInfo.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', ItemInfo.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            self.icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    end
    self.EmptyFeed:SetVisibility(UE.ESlateVisibility.Hidden)
    self.FeedItem:SetVisibility(UE.ESlateVisibility.Visible)
    self:RefreshSidePanel()
end

function M:RefreshCostInfo(percent)
    self.ProgressBar:SetPercent(percent)
    local num = math.floor(percent * (self.max_forge_num)) + 1
    if math.floor(percent * (self.max_forge_num)) + 1 > self.max_forge_num then
        num = self.max_forge_num
    end
    self.Text_Num:SetText(math.floor(num))
    self.forge_count = num
    self:RefreshCurrency()
    -- if self.price ~= 0 then
    --     self.Text_NeedGold:SetText(num * self.price)
    -- end
end

function M:OnSlider_Value_Changed(target, value)
    if value then
        self:RefreshCostInfo(value / self.GHSSlider.MaxValue)
    end
end

function M:RefreshSlider()
    self.GHSSlider:SetMaxValue(self.max_forge_num)
    self.GHSSlider:SetStepSize(1)

    if self.max_forge_num >= 1 then
        self.GHSSlider:SetValue(self.GHSSlider.MaxValue * self.forge_count / self.max_forge_num)
        local percent = self.forge_count / self.max_forge_num
        self.ProgressBar:SetPercent(percent)
    else
        self.GHSSlider:SetValue(self.GHSSlider.MaxValue)
        self.ProgressBar:SetPercent(1)
    end
    self.Text_Num:SetText(self.forge_count)
    self:RefreshCurrency()
    -- if self.price > 0 then
    --     self.Text_NeedGold:SetText(self.forge_count * self.price)
    -- end
end

function M:OnClicked_Minus()
    if self.forge_count > 1 then
        self.forge_count = self.forge_count - 1
        self:RefreshSlider()
    end
end

function M:OnClicked_Add()
    if self.forge_count < self.max_forge_num then
        self.forge_count = self.forge_count + 1
        self:RefreshSlider()
    end
end

function M:OnClicked_Exit()
    self:BindToAnimationFinished(self.quit, function() 
        if self.NPC then
            self.NPC:K2_DestroyActor()
        end
        UIManager:GetInstance():RemoveUI(self)
        UIManager:GetInstance():SetForceShowCursor(false)
    end)
    self:PlayAnimationReverse(self.quit, 1, false)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:OnClicked_ExplainBtn()
    UIUtils.ShowSystemDes(1002)
end

function M:ntf_item_info(result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg and parsed_msg.ntf_item_info and parsed_msg.ntf_item_info.changed_item_infos then
            -- if self.NewEquipItem then
            --     self.ReturnMaterial = {}
            --     for _, value in ipairs(parsed_msg.ntf_item_info.changed_item_infos) do
            --         if value.count > 0 then
            --             table.insert(self.ReturnMaterial, value)
            --         end
            --     end
            -- else
            --     for _, value in ipairs(parsed_msg.ntf_item_info.changed_item_infos) do
            --         if value.count > 0 and value.arm_info then
            --             self.NewEquipItem = value
            --             break
            --         end
            --     end
            -- end
            self.NewEquipItem = {}
            for _, value in ipairs(parsed_msg.ntf_item_info.changed_item_infos) do
                if value.item_extra == "arm_info" then
                    table.insert(self.NewEquipItem, value)
                end
            end
        end
    end
end

function M:OnMsg_Bag_Get_New_Item()
    if #self.NewEquipItem > 1 then
        self.UI_GetItem_Notice = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetItem_Notice')
        self.UI_GetItem_Notice:RefreshUI(self.NewEquipItem, function(item) 
            self.UI_GetEquip = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetEquip')
            self.UI_GetEquip.Img_Title:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_GetEquip.Text_Title:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_GetEquip:RefreshUI(item)
        end)
    elseif #self.NewEquipItem == 1 then
        self.UI_GetEquip = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetEquip')
        self.UI_GetEquip:RefreshUI(self.NewEquipItem[1])
    end
    self.NewEquipItem = {}

    --返还消耗
    -- if #self.ReturnMaterial > 0 then
    --     self.UI_GetItem_Notice = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetItem_Notice')
    --     self.UI_GetItem_Notice:RefreshUI(self.ReturnMaterial)
    -- end
    -- self.ReturnMaterial = {}
    

    self.SelectedFeedIndex = 0
    self.ClickedFeedIndex = 1
    self:HideFeedItem()
    self:RefreshFeedData()
    self:RefreshSidePanel()
end

function M:OnMsg_Ntf_Item_Info()
    self:RefreshSidePanel()
end

return M
