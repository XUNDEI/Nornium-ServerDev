--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"

local Database = require('_Game.Utils.Database')
local UIUtils = require('_Game.Utils.UIUtils')
local PlotSystem = require("Module.Plot.PlotSystem")
local ActivitySystem = require('Module.Activity.ActivitySystem')
local PlayerSystem = require('Module.Player.PlayerSystem')
local PlotSystem = require('Module.Plot.PlotSystem')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Activity_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

--构造函数
function M:Construct()
    self:InitUI()
    self:InitData()
    MessageManager:GetInstance():AddListener('OnMsg_Res_Activity_Sign', self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener('OnMsg_Res_Activity_Sign', self)
end

function M:OnMsg_Res_Activity_Sign()
    self:InitData(true)
    self:InitUIEx(nil, true)
end

function M:InitData(skipAnimation)
    self.ActivityList = ActivitySystem:GetInstance():GetActivity()
    if #self.ActivityList > 1 then
        table.sort(self.ActivityList, function(a, b)
            local aConfig = Database.Query('d_activity', a)
            local bConfig = Database.Query('d_activity', b)
            return aConfig.order < bConfig.order
        end)
    end
    self.ListView_Tab:ClearListItems()
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Character/UI_Data/BP_ListItemData.BP_ListItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local itemDataSource = {}
    local index = 1
    for _, activityId in ipairs(self.ActivityList) do
        local itemData = NewObject(ItemClass)
        itemData.Index = index
        itemData.Id = activityId
        table.insert(itemDataSource, itemData)
        index = index + 1
    end
   
    self.ListView_Tab:BP_SetListItems(itemDataSource)
    self.ItemSourceData = itemDataSource

    if not self.UIList then
        self.UIList = {}
    end

    self.MaxItemNumInDisplay = 4
    self.minValue = math.min(self.MaxItemNumInDisplay, #self.ItemSourceData)
    self.Time1 = 0.06 --每个item时间间隔
    self.DoAnimationIndexList = {}
    self.PastTime = 0
    self.InitHideItemUI = true
    self.StartPlayAnim = not skipAnimation and self.minValue > 0 
end

function M:InitUI()
    self.Btn_Quit.OnGHSClicked:Add(self, self.OnClicked_Btn_Quit)

    self.ListView_Tab.BP_OnEntryInitialized:Add(self, function(wbp, data, ui)
        self:BP_OnEntryInitialized_Tab(data, ui)
    end)
    self.ListView_Tab.BP_OnItemClicked:Add(self, function(wbp, data)
        self:BP_OnItemClicked_Tab(data)
    end)
end

function M:InitUIEx(activity_id, skipAnimation)
    --默认选中第一个
    if (not activity_id or '' == activity_id or activity_id == 0) and #self.ItemSourceData > 0 then
        self.SelectedTabIndex = 1
        activity_id = self.ItemSourceData[self.SelectedTabIndex].Id
        self:RefreshUI(self.SelectedTabIndex, activity_id)
        self:RefreshActivityUI(activity_id, skipAnimation)
    end
end

function M:Tick(MyGeometry, InDeltaTime)
    if self.StartPlayAnim then
        local uiNum = self.ListView_Tab:GetDisplayedEntryWidgets():Length()
        local itemNum = self.minValue
        if uiNum >= itemNum then
            self.PastTime = self.PastTime + InDeltaTime
            for i = 1, self.minValue do 
                local curTime = self.Time1 * (i - 1)
               
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
    local widgets = self.ListView_Tab:GetDisplayedEntryWidgets()
    print('----index:' .. tostring(index) .. ',array:' .. tostring(#self.DoAnimationIndexList) .. ', count:' .. tostring(widgets:Length()))
    if index <= widgets:Length() then
        local widget = widgets:Get(index)
        if widget then 
            -- widget:StopAllAnimations()
            widget:PlayAnimationForward(widget.InitAnimation, 1, false)
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
    end
end

function M:RefreshUI(TabIndex, activity_id)
    if self.SelectedTabIndex and self.SelectedTabIndex > 0 then
        local ui = nil 
        local widgets = self.ListView_Tab:GetDisplayedEntryWidgets()
        for i = 1, widgets:Length() do
            local widget = widgets:Get(i)
            if widget.Index == self.SelectedTabIndex then
                ui = widget 
                break
            end
        end
        if ui then
            ui:PlayAnimationReverse(ui.selected, 1, false)
        end
    end
   
    if self.UIList[self.SelectedActivityId] then
        self.UIList[self.SelectedActivityId]:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    self.SelectedTabIndex = TabIndex
    self.SelectedActivityId = activity_id
    if self.SelectedTabIndex and self.SelectedTabIndex > 0 then
        local ui = nil 
        local widgets = self.ListView_Tab:GetDisplayedEntryWidgets()
        for i = 1, widgets:Length() do
            local widget = widgets:Get(i)
            if widget.Index == self.SelectedTabIndex then
                ui = widget 
                break
            end
        end
        if ui then
            ui:PlayAnimationForward(ui.selected, 1, false)
        end
    end
end

function M:RefreshActivityUI(activityId, skipAnimation)
    local config = Database.Query("d_activity", activityId)
    if config then
        if not self.UIList[activityId] then
            local uiPath = string.sub(config.detailPic, 1, -2) .. "_C'"
            local ui = UE.UWidgetBlueprintLibrary.Create(self, LoadClass(uiPath))
            self.Panel_Right:AddChild(ui)

            local anchors = UE.FAnchors()
            local offsets = UE.FMargin()
            anchors.Maximum = UE.FVector2D(1, 1)
            anchors.Minimum = UE.FVector2D(0, 0)
            ui.Slot:SetAnchors(anchors)
            ui.Slot:SetOffsets(offsets)
            ui.Slot:SetAutoSize(true)
            ui.Slot:SetAlignment(UE.FVector2D(0.5, 0.5))

            self.UIList[activityId] = ui
        end
        local ui = self.UIList[activityId]
        ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        if ui and ui.RefreshUI then
            ui:RefreshUI(activityId, skipAnimation)
        end
    end
end

----------------------------------------------------------------------
---ui Event
function M:OnClicked_Btn_Quit()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveTopUI(true)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Quit)

function M:BP_OnEntryInitialized_Tab(data, ui)
    ui.Index = data.Index
    ui.ActivityId = data.Id

    if self.StartPlayAnim and self.InitHideItemUI then
        if data.index > self.MaxItemNumInDisplay then
            ui.Panel_Root:SetRenderOpacity(1)
        else
            ui.Panel_Root:SetRenderOpacity(0)
        end
    else
        ui.Panel_Root:SetRenderOpacity(1)
    end

    ui:StopAllAnimations()

    local isSelected = data.Index == self.SelectedTabIndex
    ui.Panel_Selected:SetRenderOpacity(isSelected and 1 or 0)
    ui.Panel_Normal:SetRenderOpacity(isSelected and 0 or 1)

    local config = Database.Query("d_activity", data.Id)
    if config then
        if config.bannerPic and config.bannerPic ~= '' then
            local bg_texture = UE.UObject.Load(config.bannerPic)
            if bg_texture then
                ui.Img_Bg_Normal_2:SetBrushFromAtlasInterface(bg_texture)
                ui.Img_Bg_Selected_2:SetBrushFromAtlasInterface(bg_texture)
            end
        end
      
        ui.Text_Name_Normal:SetText(Database.L10n(config.eventName))
        ui.Text_Name_Selected:SetText(Database.L10n(config.eventName))
    end

    ui.Notify:SetVisibility(ActivitySystem:GetInstance():ActivityRewardAvailable(data.Id) and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
end

function M:BP_OnItemClicked_Tab(data)
    if self.SelectedTabIndex == data.Index then
        return
    end
    self:RefreshUI(data.Index, data.Id)
    self:RefreshActivityUI(data.Id)
end

return M
