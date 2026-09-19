require "UnLua"
require "Common.TableUtil"

local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local GachaSystem = require('Module.Gacha.GachaSystem')
local UIUtils = require('_Game.Utils.UIUtils')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Window_Details_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
    InputAssets.IMC_UI_Common,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitData()
    self:InitUI()
end

function M:InitData()
    --历史记录
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    self.RecordItemClass = UE.UClass.Load(ItemSourcePath)

    self.PageNum = 10 --记录 每页 物品个数
end

function M:InitUI()
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    -- self.Btn_Confirm.OnGHSClicked:Add(self, self.OnClicked_Btn_Confirm)

    --tab
    self.Btn_All.OnGHSClicked:Add(self, self.OnClicked_Btn_All)
    self.Btn_Details.OnGHSClicked:Add(self, self.OnClicked_Btn_Details)
    self.Btn_Record.OnGHSClicked:Add(self, self.OnClicked_Btn_Record)

    --历史列表左右按钮
    self.Button_L.OnGHSClicked:Add(self, self.OnClick_Btn_L)
    self.Button_R.OnGHSClicked:Add(self, self.OnClick_Btn_R)

    
    --生成器
    self.ListView_Record.BP_OnEntryInitialized:Clear()
    self.ListView_Record.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.ListView_Record.BP_OnItemClicked:Clear()
    self.ListView_Record.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    self.SelectedTabIndex = 1
    self:RefreshTab(self.SelectedTabIndex)
end

function M:RefreshUI(gachaId, gachaInfo, gachaTypeInfo)
    self.GachaId = gachaId
    self.GachaInfo = gachaInfo
    self.GachaTypeInfo = gachaTypeInfo

    local gachaSchedule = nil
    local d_gacha_schedule = require('ClientDatas.d_gacha_schedule')
    for _, v in pairs(d_gacha_schedule) do
        if v.gachaId == gachaId then
            gachaSchedule = v
            break
        end
    end
    --总览信息
    for i = 1, 6 do 
        local ui = self['UI_Detail_All' .. i]
        if ui then
            if gachaSchedule then
                local blockText = gachaSchedule['block' .. i]
                local blockPool = gachaSchedule['block' .. i .. 'pool']
                if blockText and blockText[1] ~= '' and blockPool and #blockPool > 0 then
                    ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    self:RefreshDetailItem(ui, blockText[1], blockPool, i)
                else
                    ui:SetVisibility(UE.ESlateVisibility.Collapsed)
                end
            else
                ui:SetVisibility(UE.ESlateVisibility.Collapsed)
            end
        end
    end
    --规则说明
    if gachaSchedule then
        for i = 1, 4 do
            local ui = self['UI_Detial_Welfare' .. i]
            if ui then
                if gachaSchedule and gachaSchedule.rule then
                    local blockText1 = gachaSchedule.rule[i]   
                    local blockText2 = gachaSchedule.rule[i + 1]   
                    if blockText1 and blockText1 > 0 and blockText2 and blockText2 > 0 then
                        ui.Text_Title:SetText(Database.L10n(blockText1))
                        ui.Text_Desc:SetText(Database.L10n(blockText2))
                    else
                        ui:SetVisibility(UE.ESlateVisibility.Collapsed)
                    end
                else
                    ui:SetVisibility(UE.ESlateVisibility.Collapsed)
                end
            end
        end
    end

    self.CurPageIndex = 1
    self.PageMax = 1

    self.RecordInfos = {}
    if gachaTypeInfo.gacha_record_infos and #gachaTypeInfo.gacha_record_infos > 0 then
        self.PageMax = math.ceil(#gachaTypeInfo.gacha_record_infos / self.PageNum)
        self.RecordInfos = {} 
        for i = #gachaTypeInfo.gacha_record_infos, 1, -1 do
            table.insert(self.RecordInfos, DeepCopy(gachaTypeInfo.gacha_record_infos[i]))
        end
    elseif gachaInfo and gachaInfo.gacha_pending_record_infos and #gachaInfo.gacha_pending_record_infos > 0 then
        self.PageMax = math.ceil(#gachaInfo.gacha_pending_record_infos / self.PageNum)
        self.RecordInfos = {} 
        for i = #gachaInfo.gacha_pending_record_infos, 1, -1 do
            table.insert(self.RecordInfos, DeepCopy(gachaInfo.gacha_pending_record_infos[i]))
        end
    end
    self:RefreshRecord(self.CurPageIndex)
end

function M:RefreshDetailItem(ui, blockText, blockPool, index)
    ui.Text_Desc:SetText(Database.L10n(blockText))
    --生成器
    ui.TileView.BP_OnEntryInitialized:Clear()
    ui.TileView.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        local gachaItemConfig = Database.Query('d_gacha_item', item.ItemId)
        if gachaItemConfig and gachaItemConfig.itemid then
            local itemConfig = UIUtils.GetItemConfigById(gachaItemConfig.itemid)
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
    
                if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                    local strArr = string.split(itemConfig.iconPath, '/')
                    local littePath = strArr[#strArr]
                    local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                    local iconRes = LoadObject(iconResPath)
                    if iconRes then
                        widget.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
                    end
                end

                if gachaItemConfig.rarity <= 6 then
                    widget.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
                else
                    widget.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                end
    
                --道具名字
                widget.Text_Count:SetText(Database.L10n(itemConfig.itemName))
            end
        end
        widget.Img_Clicked:SetVisibility(UE.ESlateVisibility.Visible)
        widget.Img_Clicked.OnMouseButtonDownEvent:Unbind()
        widget.Img_Clicked.OnMouseButtonDownEvent:Bind(self, function()
            UIUtils.ShowItemInfo(gachaItemConfig.itemid, 1, 20)
            return UE.UWidgetBlueprintLibrary.Handled()
        end)
    end)
    --点击事件
    -- ui.TileView.BP_OnItemClicked:Clear()
    -- ui.TileView.BP_OnItemClicked:Add(self, function(wbp, item)
    --     local gachaItemConfig = Database.Query('d_gacha_item', item.ItemId)
    --     if gachaItemConfig and gachaItemConfig.itemid then
    --         UIUtils.ShowItemInfo(gachaItemConfig.itemid, 1, 20)
    --     end
    -- end)

    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    --队列中排序(简单)
    local ItemDataSource = {}

    for i = 1, #blockPool do
        local configs = self:FindGachaPoolId(blockPool[i])
        for _, config in ipairs(configs) do
            if not table.indexof(ItemDataSource, nil, nil, function(v)
                return v.ItemId == config.gachaItemId
            end) then
                local ItemData = NewObject(ItemClass)
                ItemData.Index = i
                ItemData.ItemId = config.gachaItemId
                LOG_INFO('--->index:', index, 'gachaItemId:', config.gachaItemId)
                table.insert(ItemDataSource, ItemData)
            end
        end
    end
    ui.TileView:ClearListItems()
    ui.TileView:BP_SetListItems(ItemDataSource)
end

function M:RefreshTab(index)
    self.WidgetSwitcher_All:SetActiveWidgetIndex(index == 1 and 1 or 0)
    self.WidgetSwitcher_Details:SetActiveWidgetIndex(index == 2 and 1 or 0)
    self.WidgetSwitcher_Record:SetActiveWidgetIndex(index == 3 and 1 or 0)

    self.Panel_All:SetVisibility(index == 1 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Panel_Details:SetVisibility(index == 2 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Panel_Record:SetVisibility(index == 3 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
end

function M:RefreshRecord(pageIndex)
    self.Text_Page:SetText(pageIndex)
    self.ListView_Record:ClearListItems()

    local num = self:GetRecordList(pageIndex, self.PageNum)

    local ItemDataSource = {}
    for i = 1, num do
        local ItemData = NewObject(self.RecordItemClass)
        ItemData.Index = i
        ItemData.ItemId = (pageIndex - 1) * self.PageNum + i
        table.insert(ItemDataSource, ItemData)
    end
    
    self.ListView_Record:BP_SetListItems(ItemDataSource)
end

function M:FindGachaPoolId(poolId)
    local ret = {}
    local d_gacha_pool = require('ClientDatas.d_gacha_pool')
    for _, v in pairs(d_gacha_pool) do 
        if v.poolId == poolId then
            table.insert(ret, v)
        end
    end
    return ret
end

function M:GetRecordList(pageIndex, pageNum)
    if self.RecordInfos then
        local allCount = #self.RecordInfos
        if (pageIndex * pageNum) > allCount then
            return allCount - (pageIndex - 1) * pageNum
        end
    end
    return pageNum
end

-------------------------------------------------------
--- ui event
function M:OnClicked_Btn_Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)

function M:OnClicked_Btn_All()
    if self.SelectedTabIndex ~= 1 then
        self.SelectedTabIndex = 1
        self:RefreshTab(self.SelectedTabIndex)
    end
end

function M:OnClicked_Btn_Details()
    if self.SelectedTabIndex ~= 2 then
        self.SelectedTabIndex = 2
        self:RefreshTab(self.SelectedTabIndex)
    end
end

function M:OnClicked_Btn_Record()
    if self.SelectedTabIndex ~= 3 then
        self.SelectedTabIndex = 3
        self:RefreshTab(self.SelectedTabIndex)
    end
end

function M:OnClick_Btn_L()
    if self.CurPageIndex == 1 then
        return
    end
    self.CurPageIndex = math.max(self.CurPageIndex - 1, 1)
    self:RefreshRecord(self.CurPageIndex)
end

function M:OnClick_Btn_R()
    if self.CurPageIndex == self.PageMax then
        return
    end
    self.CurPageIndex = math.min(self.CurPageIndex + 1, self.PageMax)
    self:RefreshRecord(self.CurPageIndex)
end

function M:BP_OnEntryInitialized(item, widget)
    widget.Index = item.Index
    widget.ItemId = item.ItemId
    local data = self.RecordInfos[item.ItemId]
    -- print('-----BP_OnEntryInitialized:' .. tostring(data.gacha_item_id))
    local gachaItemConfig = Database.Query('d_gacha_item', data.gacha_item_id)
    if gachaItemConfig and gachaItemConfig.itemid then
        --self:RefreshItemUI(widget, gachaItemConfig.itemid)
        local itemConfig = UIUtils.GetItemConfigById(gachaItemConfig.itemid)
       
        local config = require('ClientDatas.d_gacha_list')[self.GachaId]
        --新手池不用管
        if config and config.gachaType then
            --卡池类型
            local nameId = UIUtils.EGachaPoolTypeName[config.gachaType]
            widget.Text_1:SetText(Database.L10n(nameId))
        end

        

        local typeName = 500011
        if data.gacha_item_type == 10 then --武器
            typeName = 500012
        elseif data.gacha_item_type == 93 then --家具
            typeName = 500013
        end
       
        --类型
        widget.Text_2:SetText(Database.L10n(typeName))
        --道具名字
        if itemConfig then
            local str = '<span color="#' .. UIUtils.EItemRarityColor[itemConfig.rarity] .. 'FF">' .. Database.L10n(itemConfig.itemName) .. '</>'
            widget.Text_3:SetText(str) 
        end

        --时间
        widget.Text_4:SetText(os.date("%Y/%m/%d %H:%M", data.gacha_seconds))
    end
end

function M:BP_OnItemClicked(item)
    -- local data = self.GachaItemList[item.Index]
    -- print('-----BP_OnItemClicked:' .. tostring(data.gacha_item_id))
    -- local gachaItemConfig = Database.Query('d_gacha_item', data.gacha_item_id)
    -- if gachaItemConfig and gachaItemConfig.itemid then
    --     UIUtils.ShowItemInfo(gachaItemConfig.itemid, 1, 20)
    -- end
end

return M
