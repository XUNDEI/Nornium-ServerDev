--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"

---@type UI_HandBook_C
local M = Class()

local Database = require('_Game.Utils.Database')
local UIUtils = require('_Game.Utils.UIUtils')
local PlotSystem = require("Module.Plot.PlotSystem")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

--构造函数
function M:Construct()
    self:InitUI()
    self:InitData()
end

function M:Destruct()

end

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:InitData()
    self.InitItemID = 0
    self.CachedSelectedItemData = {}
end

function M:InitUI()
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not pc.BP_PlayerController_City_UniverseBridge.BlockInputAction then
        pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
        self.InitIsBlock = true
    end

    self.Btn_Exit.OnGHSClicked:Add(self, self.OnClicked_Btn_Exit)
    self.Btn_Search.OnGHSClicked:Add(self, self.OnClicked_Btn_Search)
    self.Btn_Left.OnGHSClicked:Add(self, self.OnClicked_Btn_Left)
    self.Btn_Right.OnGHSClicked:Add(self, self.OnClicked_Btn_Right)

    self.Txt_White_1.OnHyperlinkClicked:Add(self, self.OnClicked_RichTextLink)
    self.Txt_White_2.OnHyperlinkClicked:Add(self, self.OnClicked_RichTextLink)


    self.TreeView.BP_OnEntryInitialized:Add(self, function(wbp, data, ui)
        self:BP_OnEntryInitialized(data, ui)
    end)

    self.TreeView.BP_OnItemExpansionChanged:Add(self, function(wbp, data, expand)
        self:BP_OnItemExpansionChanged(data, expand)
    end)

    self.TreeView.BP_OnItemClicked:Add(self, function(wbp, data)
        self:BP_OnItemClicked(data)
    end)
end

function M:InitUIEx(itemId)
    print("---->openlink:" .. tostring(itemId))
    self.InitItemID = itemId or 0
    self.CachedSelectedItemData = {}
    self:RefreshTreeView()
end

function M:RefreshUI()
    self:RefreshTreeView()
end

function M:RefreshTreeView()
    self.AllDataList = {}

    local d_handbook_entry = require('ClientDatas.d_handbook_entry')
    local PlotInfo = PlotSystem:GetInstance().PlotInfo
    local storyLines = PlotInfo and PlotInfo.unlocked_story_line_ids or {}
    for id, itemId in pairs(storyLines) do
        print("--------解锁id列表:" .. tostring(itemId))
        local config = d_handbook_entry[itemId]
        if config then
            if not self.AllDataList[config.classId] then
                self.AllDataList[config.classId] = {}
            end
            local data = {
                id = config.id,
            }
            table.insert(self.AllDataList[config.classId], data)
        end
    end
    for id, config in pairs(d_handbook_entry) do
        if config.classId == 1004 then
            if not self.AllDataList[config.classId] then
                self.AllDataList[config.classId] = {}
            end
            local data = {
                id = id,
            }
            table.insert(self.AllDataList[config.classId], data)
        end
    end
    --排序
    for _, datas in pairs(self.AllDataList) do
        if #datas > 1 then
            table.sort(datas, function(a, b) 
                return a.id < b.id
            end)
        end
    end

    self.TreeView:ClearListItems()
    self.MainItemDataSource = {}
    self.SubItemDataSource = {}

    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Quest/UI_Data/BP_QuestData.BP_QuestData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    self.LastSelectedItemData = nil
    self.LastExpandMainItemData = nil
    self.CachedSelectedItemData = {}
    self.CachedSelectedIndex = 0

    local defaultSelectedItemData = nil
    local initSelectedItemData = nil
    local mainIdx = 1
    for classId, datas in pairs(self.AllDataList) do
        local mainItemData = NewObject(ItemClass)
        mainItemData.Index = classId
        mainItemData.ID = classId
        mainItemData.Layer = 1
        for idx, entry in ipairs(datas) do 
            local subItemData = NewObject(ItemClass)
            subItemData.Index = classId
            subItemData.ID = entry.id
            subItemData.Layer = 2
            mainItemData.Children:Add(subItemData)
            table.insert(self.SubItemDataSource, subItemData)

            if mainIdx == 1 and idx == 1 then
                defaultSelectedItemData = subItemData
            end

            if not initSelectedItemData then
                if self.InitItemID > 0 then
                    if entry.id == self.InitItemID then
                        initSelectedItemData = subItemData
                        self.LastExpandMainItemData = mainItemData
                    end
                end
            end
        end
        self.TreeView:AddItem(mainItemData)
        self.MainItemDataSource[classId] = mainItemData

        mainIdx = mainIdx + 1
    end

    if not initSelectedItemData then 
        initSelectedItemData = defaultSelectedItemData 
        self.LastExpandMainItemData = self.MainItemDataSource[1]
    end
    if initSelectedItemData then
        self:ScrollItem(initSelectedItemData)
    end

    self:RefreshDetailPanel()
end

function M:RefreshDetailPanel()
    if self.LastSelectedItemData then
        local config = self:GetEntryConfigById(self.LastSelectedItemData.ID)
        local name = config and Database.L10n(config.nameId) or ''
        -- self.Text_Name:SetText(config and Database.L10n(config.nameId) or '')
        -- self.Text_Des:SetText(config.id .. '-' .. config.text)
        
        if config.img ~= '' then
            self.DetailPanel_1:SetVisibility(UE.ESlateVisibility.Hidden)
            self.DetailPanel_2:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            local bg_texture = UE.UObject.Load(config.img)
            if bg_texture then
                self.Img_Des_2:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                self.Img_Des_2:SetBrushFromTexture(bg_texture)
            else
                self.Img_Des_2:SetVisibility(UE.ESlateVisibility.Hidden)
            end
            self.Text_Name_2:SetText(config and Database.L10n(config.nameId) or '')
            self.Txt_White_2:SetText(Database.L10n(tonumber(config.text)))
        else
            if config.BGimg ~= '' then
                local bg_texture = UE.UObject.Load(config.BGimg)
                if bg_texture then
                    self.Img_Des_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    self.Img_Des_1:SetBrushFromTexture(bg_texture)
                else
                    self.Img_Des_1:SetVisibility(UE.ESlateVisibility.Hidden)
                end
            end
            self.DetailPanel_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self.DetailPanel_2:SetVisibility(UE.ESlateVisibility.Hidden)
            
            self.Text_Name_1:SetText(config and Database.L10n(config.nameId) or '')
            self.Txt_White_1:SetText(Database.L10n(tonumber(config.text)))
        end
    end
end

----------------------------------------------------------------------
---ui Event
function M:BP_OnEntryInitialized(data, ui)
    ui.Index = data.Index
    ui.Layer = data.Layer
    ui.ID = data.ID

    ui.Panel_Main:SetVisibility(data.Layer == 1 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
    ui.Panel_Sub:SetVisibility(data.Layer == 2 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

    if ui.Layer == 1 then
        local config = self:GetClassConfigById(ui.ID)
        ui.Text_Main:SetText(config and Database.L10n(config.nameId) or '')
        ui.Text_Main_Selected:SetText(config and Database.L10n(config.nameId) or '')

        local isExpand = data == self.LastExpandMainItemData
        self:RefreshMainItem(ui, isExpand)
    else
        local config = self:GetEntryConfigById(ui.ID)

        ui.Text_Sub:SetText(config and Database.L10n(config.nameId) or '')
        ui.Text_Sub_Selected:SetText(config and Database.L10n(config.nameId) or '')

        self:RefreshSubItem(ui, data == self.LastSelectedItemData, true)
    end
end

function M:BP_OnItemExpansionChanged(itemData, expand)
    if itemData.Layer == 1 then
      
        local ui, index = self:GetItem(itemData)
        print("---------->>BP_OnItemExpansionChanged:" .. tostring(index) .. ",expand:" .. tostring(expand))
        if ui then
            self:RefreshMainItem(ui, expand)
        end
    end
end

function M:BP_OnItemClicked(data)
    if data.Layer == 1 then
        if self.LastExpandMainItemData and self.LastExpandMainItemData ~= data then
            local ui = self:GetItem(self.LastSelectedItemData)
            if ui then
                ui:PlayAnimationReverse(ui.switch)
            end
            self.TreeView:SetItemExpansion(self.LastExpandMainItemData, false) 
            self.LastExpandMainItemData = data

            self.LastSelectedItemData = data.Children:Get(1)
            table.insert(self.CachedSelectedItemData, data)
            self.CachedSelectedIndex = #self.CachedSelectedItemData
            -- LOG_INFO("CacheSelectedIndex:", self.CachedSelectedIndex)

            if self.LastSelectedItemData then
                local ui = self:GetItem(self.LastSelectedItemData)
                if ui then
                    self:RefreshSubItem(ui, true)
                end
            end
            self:RefreshDetailPanel()
        end
        return
    end
    if data.Layer ~= 2 or self.LastSelectedItemData == data then return end
    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshSubItem(ui, false)
        end
    end
    self.LastSelectedItemData = data
    table.insert(self.CachedSelectedItemData, data)
    self.CachedSelectedIndex = #self.CachedSelectedItemData
    -- LOG_INFO("CacheSelectedIndex:", self.CachedSelectedIndex)

    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshSubItem(ui, true)
        end
    end
    self:RefreshDetailPanel()
end

function M:OnClicked_Btn_Exit()
    if self.InitIsBlock then
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        self.InitIsBlock = false
    end
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Exit)

function M:OnClicked_Btn_Search()
    local searchStr = self.Label_Input:GetText()
    if searchStr == '' then
        UIUtils.ShowNotify(self, Database.L10n(318))
        return
    end
    local subItem = nil
    for _, subItemData in pairs(self.SubItemDataSource) do 
        local config = self:GetEntryConfigById(subItemData.ID)
        if config then
            local showText = Database.L10n(config.nameId)
            if string.contains(showText, searchStr) then
                subItem = subItemData
                break
            end
        end
    end
    if not subItem then
        UIUtils.ShowNotify(self, string.format(Database.L10n(319), searchStr))
        return
    end

    self:ScrollItem(subItem)
end

function M:OnClicked_Btn_Left()
    print('----Left')
    self.CachedSelectedIndex = self.CachedSelectedIndex - 1
    if self.CachedSelectedIndex <= 0 then
        self.CachedSelectedIndex = 1
    end
    -- LOG_INFO("CacheSelectedIndex:", self.CachedSelectedIndex)
    local itemData = self.CachedSelectedItemData[self.CachedSelectedIndex]
    if itemData then
        self:ScrollItem(itemData, true)
    end
end

function M:OnClicked_Btn_Right()
    self.CachedSelectedIndex = self.CachedSelectedIndex + 1
    if self.CachedSelectedIndex > #self.CachedSelectedItemData then
        self.CachedSelectedIndex = #self.CachedSelectedItemData
    end
    -- LOG_INFO("CacheSelectedIndex:", self.CachedSelectedIndex)
    local itemData = self.CachedSelectedItemData[self.CachedSelectedIndex]
    if itemData then
        self:ScrollItem(itemData, true)
    end
end

function M:OnClicked_RichTextLink(action)
    print('action:' .. tostring(action))
    local strArr = string.split(action, ':')
    if #strArr > 1 then
        local actionType = tonumber(strArr[1])
        if actionType == 2 then
            UE.UGameplayStatics.GetGameInstance(self):OnMessage('handbook', strArr[2])
        end
    end
end

----------------------------------------------------------------------
----------------------------------------------------------------------

function M:ScrollItem(subItem, skip_cache)
    for _, mainItemData in pairs(self.MainItemDataSource) do
        local ui = self:GetItem(mainItemData)
        if ui then
            self:RefreshMainItem(ui, false)
        end
    end
    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshSubItem(ui, false)
        end
    end
    self.LastSelectedItemData = subItem
    if not skip_cache then
        table.insert(self.CachedSelectedItemData, subItem)
        self.CachedSelectedIndex = #self.CachedSelectedItemData
        -- LOG_INFO("CacheSelectedIndex:", self.CachedSelectedIndex)
    end

    self.TreeView:CollapseAll()
    if subItem then
        local expandItemData = self.MainItemDataSource[subItem.Index]
        if expandItemData then
            self.TreeView:SetItemExpansion(expandItemData, true)
            self.LastExpandMainItemData = expandItemData
            self.TreeView:BP_ScrollItemIntoView(expandItemData)
            self.TreeView:BP_ScrollItemIntoView(subItem)
        end
    end

    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshSubItem(ui, true)
        end
    end

    self:RefreshDetailPanel()
end

function M:GetItem(itemData)
    local widgets = self.TreeView:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.Index == itemData.Index and widget.Layer == itemData.Layer and widget.ID == itemData.ID then
            return widget, i
        end
    end
    return nil, 0
end

function M:RefreshMainItem(ui, isExpand)
    -- ui.Img_Main_Bg_Selected:SetVisibility(isExpand and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    ui.Text_Main_Selected:SetVisibility(isExpand and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    ui.Img_Main_Selected:SetVisibility(isExpand and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    if isExpand then 
        ui:PlayAnimationForward(ui.switch)
    else
        ui:PlayAnimationReverse(ui.switch)
    end
end

function M:RefreshSubItem(ui, selected, bIsInit)
    ui.Text_Sub:SetVisibility(selected and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
    
    ui.Text_Sub_Selected:SetVisibility(selected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    if bIsInit then
        ui.Img_Sub_Selected:SetRenderOpacity(selected and 1 or 0)
    else
        if selected then 
            ui:PlayAnimationForward(ui.switch)
        else
            ui:PlayAnimationReverse(ui.switch)
        end
    end
end

function M:GetClassConfigById(id)
    local config = require('ClientDatas.d_handbook_class')
    if not config or not config[id] then
        LOG_ERROR('d_handbook_class not this id:' .. tostring(id))
        return nil
    end
    return config[id]
end

function M:GetEntryConfigById(id)
    local config = require('ClientDatas.d_handbook_entry')
    if not config or not config[id] then
        LOG_ERROR('d_handbook_entry not this id:' .. tostring(id))
        return nil
    end
    return config[id]
end

function M:GetSubItemClassById(id)
    local config = require('ClientDatas.d_handbook_entry')
    if not config or not config[id] then
        LOG_ERROR('d_handbook_entry not this id:' .. tostring(id))
        return 0
    end
    return config[id].classId
end

return M
