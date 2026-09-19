local UIUtils = require("_Game.Utils.UIUtils")
local SrpgModel = require("Module.Srpg.SrpgModel")
local GlobalConfig = require("GlobalConfig")
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@class UIManager
---@field layers UI_Layers_C
---@field notifications string[]
---@field GetInstance fun():UIManager
local UIManager = BaseClass("UIManager", Singleton)

local NOTIFICATION_INTERVAL = 1.0

function UIManager:ShowWaterMask(wco, account)
    account = account or self.account
    if not account then return end
    if GlobalConfig.Channel ~= "cb4_steam" and GlobalConfig.Channel ~= "cb4_zb" then return end
    self.account = account

    local widget_class = UE.UClass.Load('/Game/_Game/Blueprints/UI/UI_WaterMark.UI_WaterMark_C')
    local ui = UE.UWidgetBlueprintLibrary.Create(wco, widget_class)

    ui:AddToViewport(10000)
    ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    ui.TextBlock_WaterMark:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    ui.TextBlock_WaterMark:SetText(account)
end

--ui会跟着worldcontextobject一起销毁，ui_layers不一定一直存在
function UIManager:OnBeginPlay(WorldContextObject)
    if not UIManager.UI_LayersRef then   
        UIManager.UI_Layers = LoadClass('/Game/_Game/Blueprints/UI/UI_Layers.UI_Layers_C')
        UIManager.UI_LayersRef = UnLua.Ref(UIManager.UI_Layers)
        UIManager.UI_FloatingText = LoadClass('/Game/_Game/Blueprints/UI/UI_FloatingText.UI_FloatingText_C')
        UIManager.UI_FloatingTextRef = UnLua.Ref(UIManager.UI_FloatingText)
        UIManager.UI_DescText = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_DescText.UI_DescText_C')
        UIManager.UI_DescTextRef = UnLua.Ref(UIManager.UI_DescText)
        UIManager.UI_HighLight = LoadClass('/Game/_Game/Blueprints/UI/UI_HighLight.UI_HighLight_C')
        UIManager.UI_HighLightRef = UnLua.Ref(UIManager.UI_HighLight)
        UIManager.UI_TrackPoint = LoadClass('/Game/_Game/Blueprints/UI/UI_TrackPoint.UI_TrackPoint_C')
        UIManager.UI_TrackPointRef = UnLua.Ref(UIManager.UI_TrackPoint)
        UIManager.UI_Com_Notice  = LoadClass('/Game/_Game/Blueprints/UI/UI_Com_Notice.UI_Com_Notice_C')
        UIManager.UI_Com_NoticeRef = UnLua.Ref(UIManager.UI_Com_Notice)
        UIManager.UI_MaskedHighlight = LoadClass('/Game/_Game/Blueprints/UI/UI_MaskedHighlight.UI_MaskedHighlight_C')
        UIManager.UI_MaskedHighlightRef = UnLua.Ref(UIManager.UI_MaskedHighlight)
        UIManager.UI_Banner_exclamation = LoadClass('/Game/_Game/Blueprints/UI/UI_Bulletin/UI_Banner_exclamation.UI_Banner_exclamation_C')
        UIManager.UI_Banner_exclamationRef = UnLua.Ref(UIManager.UI_Banner_exclamation)
    end

    ---@type BP_PlayerController_City_C | BP_PlayerController_Fight_C | BP_Playercontroller_Login_C | BP_PlayerController_Universe_C
    self.playerController = UE.UGameplayStatics.GetPlayerController(WorldContextObject, 0)
    
    self.layers = UE.UWidgetBlueprintLibrary.Create(WorldContextObject, UIManager.UI_Layers, nil)

    self.layers:AddToViewport(0)
    self.layers:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)

    self.lastNofiticationElapsed = 0
    self.notificationAvailable = true
    self.notifications = {}

    self.banner = nil
    self.banners = {}

    local OnTick = function(_, DeltaTime)
        self:UpdateNotificationTimer(DeltaTime)
        self:UpdateBanner()
    end

    self.layers.OnTick:Add(self.layers, OnTick)

    MessageManager:GetInstance():AddListener(SrpgModel.HpChanged, self)
    MessageManager:GetInstance():AddListener(SrpgModel.BoatEnergyChanged, self)
    MessageManager:GetInstance():AddListener(SrpgModel.ResourceChanged, self)

    UE.UGHSFunctionLibrary.GHSEnableTouchCursor()

    -- UE.UGHSFunctionLibrary.FocusViewport(self.playerController)
    UE.UWidgetBlueprintLibrary.SetInputMode_GameOnly(self.playerController, nil, UE.EMouseLockMode.LockAlways, false, false)

    self.trackers = {}
    self.special_trackers = {}
    self.should_show_tracker = self.should_show_tracker or false
    -- 这些UI在顶层时才显示图钉
    self.tracker_show_top_uis = {
        string.lower("UI_City"),
        string.lower("UI_TrainStation"),
    }
    self.tracker_hide_uis = {
        string.lower("UI_Quest"),
        string.lower("UI_Fight_Start"),
        string.lower("UI_Demon_Furnace"),
        string.lower("UI_Dialog_Story"),
        string.lower("UI_Dialog_Cutscene"),
        string.lower("UI_Shop"),
    }

    ---@type UI_HighLight_C[]
    self.highlights = {}
    self.requestedHighlight = {}
end

function UIManager:OnEndPlay()
    InputUtils.ClearAllMappings(self.playerController)

    MessageManager:GetInstance():RemoveListener(SrpgModel.HpChanged, self)
    MessageManager:GetInstance():RemoveListener(SrpgModel.BoatEnergyChanged, self)
    MessageManager:GetInstance():RemoveListener(SrpgModel.ResourceChanged, self)

    UE.UGHSFunctionLibrary.GHSDisableTouchCursor()
end

function UIManager:UpdateNotificationTimer(deltaTime)
    if not self.notificationAvailable then
        self.lastNofiticationElapsed = self.lastNofiticationElapsed + deltaTime
        if self.lastNofiticationElapsed > NOTIFICATION_INTERVAL then
            self.lastNofiticationElapsed = self.lastNofiticationElapsed - NOTIFICATION_INTERVAL
            self.notificationAvailable = true
        end
    end

    if self.notificationAvailable then
        if #self.notifications > 0 then
            self:ShowNotification(self.notifications[1])
            table.remove(self.notifications, 1)
            self.notificationAvailable = false
        else
            self.lastNofiticationElapsed = 0
        end
    end
end

---@param confirmArgs NoticeArgs
function UIManager:ShowConfirm(confirmArgs)
    -- self:ClearConfirm()
    ---@type UI_Com_Notice_C
    local notice = UE.UWidgetBlueprintLibrary.Create(self.layers, UIManager.UI_Com_Notice)

    self:AddUI(notice, true)

    notice:ShowArgs(confirmArgs)
end

function UIManager:ClearConfirm()
    local widgetList = self.layers.UpNormal:GetAllChildren()
    for i = widgetList:Length(), 1, -1 do
        local ui = widgetList:Get(i)
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className == "ui_com_notice" then
            self:RemoveUI(ui, true)
            LOG_INFO('remove ui_com_notice --index:' .. tostring(i) .. ",ui:" .. tostring(className))
            break
        end
    end
end

local HIGHLIGHT_DEFAULT_SIZE = 100
function UIManager:ShowHighlight(pos, size, anchors)
    ---@type UI_HighLight_C
    local highlight = UE.UWidgetBlueprintLibrary.Create(self.layers, UIManager.UI_HighLight)
    self.layers.Floating:AddChild(highlight)

    highlight.Slot:SetAutoSize(true)
    highlight.Slot:SetAlignment(UE.FVector2D(0.5, 0.5))
    highlight.Slot:SetAnchors(anchors)
    highlight.Slot:SetPosition(pos)
    highlight:SetRenderScale(UE.FVector2D(size / HIGHLIGHT_DEFAULT_SIZE))

    table.insert(self.highlights, highlight)

    return highlight
end

function UIManager:UpdateHighlights()
    for _, highlight in ipairs(self.highlights) do
        highlight:RemoveFromParent()
    end
    self.highlights = {}
    
    local topUI = self:GetTopUI()

    for UIClass, highlightInfos in pairs(self.requestedHighlight) do
        if UE.UGameplayStatics.ObjectIsA(topUI, UIClass) then
            for _, highlightInfo in ipairs(highlightInfos) do
                local highlight = self:ShowHighlight(table.unpack(highlightInfo))
                table.insert(self.highlights, highlight)
            end
            break
        end
    end
end

function UIManager:RequestShowHighlight(pos, size, anchors, class)
    if not self.requestedHighlight[class] then
        self.requestedHighlight[class] = {}
    end

    table.insert(self.requestedHighlight[class], { pos, size, anchors })

    self:UpdateHighlights()
end

function UIManager:RemoveHighlight(class)
    self.requestedHighlight[class] = nil

    self:UpdateHighlights()
end

function UIManager:UpdateMaskedHighlight()
    if self.maskedHighlight then
        return
    end

    local topUI = self:GetTopUI()

    if self.requestedMaskedHighlight then
        local config = self.requestedMaskedHighlight.config
        local task = self.requestedMaskedHighlight.task
        if UE.UGameplayStatics.ObjectIsA(topUI, UE.UKismetSystemLibrary.Conv_SoftClassReferenceToClass(config.UI)) then
            ---@type UI_MaskedHighlight_C
            self.maskedHighlight = UE.UWidgetBlueprintLibrary.Create(self.playerController, UIManager.UI_MaskedHighlight)
            self:AddUI(self.maskedHighlight)

            local path = config.WidgetPath
            local fields = string.split(path, ".")

            local targetWidget = topUI
            if task.UIParam ~= '' then
                if topUI.RefreshUIByMask then
                    topUI:RefreshUIByMask(task.UIParam)
                end
            end 

            for _, field in ipairs(fields) do
                targetWidget = targetWidget[field]
            end

            self.maskedHighlight.Highlight.Slot:SetAnchors(config.Anchors)
            self.maskedHighlight.Highlight.Slot:SetPosition(config.Position)
            self.maskedHighlight.highlight:SetRenderScale(UE.FVector2D(config.Size / HIGHLIGHT_DEFAULT_SIZE))

            self.maskedHighlight.Trigger.OnClicked:Add(self.maskedHighlight.Trigger, function()
                self:RemoveUI(self.maskedHighlight)
                self.maskedHighlight = nil
                UIUtils.TriggerWidget(targetWidget)
                if UE.UKismetSystemLibrary.IsValid(task) then
                    task:NextStep()
                end
            end)

            self.requestedMaskedHighlight = nil
        end
    end
end

---@param task STT_ShowMaskedHighlight_C
---@param config FMaskedHighlightConfig
function UIManager:RequestShowMaskedHighlight(task, config)
    self.requestedMaskedHighlight = {
        task = task,
        config = config,
    }

    self:UpdateMaskedHighlight()
end

function UIManager:ShowNotification(text)
    ---@type UI_FloatingText_C
    local floatingText = UE.UWidgetBlueprintLibrary.Create(self.layers, UIManager.UI_FloatingText)
    self.layers.Notify:AddChild(floatingText)
    UIUtils.SetAnchorPositionToCenter(floatingText.Slot)
    floatingText.Text:SetText(text)
    floatingText:PlayAnimationForward(floatingText.FloatUp, 1, true)
end

function UIManager:ClearNotifications()
    if self.layers then
        self.layers.Notify:ClearChildren()
    end
    self.notifications = {}
    self.lastNofiticationElapsed = 0
    self.notificationAvailable = true
end

function UIManager:Notify(text)
    if self.notificationAvailable then
        self:ShowNotification(text)
        self.notificationAvailable = false
    else
        table.insert(self.notifications, text)
    end
end

function UIManager:ShowBanner(text)
    ---@type UI_Banner_exclamation_C
    self.banner = UE.UWidgetBlueprintLibrary.Create(self.layers, UIManager.UI_Banner_exclamation)
    self.layers.Floating:AddChild(self.banner)
    UIUtils.SetAnchorPositionToFullScreen(self.banner.Slot)
    self.banner:Show(text)
end

function UIManager:RemoveBanner()
    self.banner:RemoveFromParent()
    self.banner = nil
    self:UpdateBanner()
end

function UIManager:UpdateBanner()
    if not self.banner and #self.banners > 0 then
        local text = table.remove(self.banners, 1)
        self:ShowBanner(text)
    end
end

function UIManager:RequestShowBanner(text)
    if self.banner then
        if not table.indexof(self.banners, text) then
            table.insert(self.banners, text)
        end
    else
        self:ShowBanner(text)
    end
end

function UIManager:ShowDesc(screenPos, name, desc, alignment)
    ---@type UI_DescText_C
    local descTextWidget = UE.UWidgetBlueprintLibrary.Create(self.layers, UIManager.UI_DescText)

    self.layers.Floating:AddChild(descTextWidget)

    local anchors = UE.FAnchors()
    local offsets = UE.FMargin()
    anchors.Minimum = UE.FVector2D(0, 0)
    anchors.Maximum = UE.FVector2D(1, 1)
    descTextWidget.Slot:SetAnchors(anchors)
    descTextWidget.Slot:SetOffsets(offsets)

    local alignment = alignment or UE.FVector2D(0, 0)
    descTextWidget.float.Slot:SetAlignment(alignment)
    descTextWidget.float.Slot:SetPosition(screenPos)

    descTextWidget.name:SetText(name)
    descTextWidget.desc:SetText(desc)
end

-- 事件

local RESOURCE_IMG = {
    [1] = "<img src=\"srpg_res01\" size=\"50,50\"></>赎罪奖券",
    [2] = "<img src=\"srpg_res02\" size=\"50,50\"></>金刚凝胶",
    [3] = "<img src=\"srpg_res03\" size=\"50,50\"></>影响因子",
    [4] = "<img src=\"srpg_fuel\" size=\"50,50\"></>诺伦燃料",
}

UIManager[SrpgModel.ResourceChanged] = function(self, index, value, showNotify)
    local show = (showNotify == nil) or showNotify
    if value ~= 0 and show then
        local sign = value > 0 and "+" or "-"
        self:Notify(sign .. tostring(math.abs(value)) .. RESOURCE_IMG[index])
    end
end

UIManager[SrpgModel.HpChanged] = function(self, value)
    if value ~= 0 then
        local sign = value > 0 and "+" or "-"
        self:Notify(sign .. tostring(math.abs(value)) .. "<img src=\"srpg_hp\" size=\"50,50\"></>生存值")
    end
end

UIManager[SrpgModel.BoatEnergyChanged] = function(self, value)
    if value and value ~= 0 then
        local sign = value > 0 and "+" or "-"
        self:Notify(sign .. tostring(math.abs(value)) .. "<img src=\"srpg_bomb\" size=\"50,50\"></>舰武载弹")
    end
end

function UIManager:AddInteractOption(object, textId, callback)
    return self.layers:AddInteractOption(object, textId, callback)
end

function UIManager:RemoveInteractOption(widget)
    self.layers:RemoveInteractOption(widget)
end

function UIManager:RemoveInteractOptionByObject(object)
    self.layers:RemoveInteractOptionByObject(object)
end

function UIManager:ClearInteractOption()
    self.layers:ClearInteractOption()
end

---@param TrackPosition FVector
function UIManager:CreateTracker(TrackPosition)
    LOG_DEBUG_TRACKBACK("----createtracker")
    ---@type UI_TrackPoint_C
    local tracker = NewObject(UIManager.UI_TrackPoint, self.layers)
    self.layers.Floating:AddChild(tracker)

    tracker.TrackPosition = TrackPosition

    table.insert(self.trackers, tracker)
    self:UpdateTracker(self:ShouldShowTracker())
    return tracker
end

function UIManager:ClearTracker()
    LOG_DEBUG_TRACKBACK("----cleartracker")
    while #self.trackers > 0 do
        local tracker = table.remove(self.trackers)
        if UE.UKismetSystemLibrary.IsValid(tracker) then
            tracker:RemoveFromParent()
        end
    end
end

---@param TrackPosition FVector
function UIManager:CreateSpecialTracker(TrackPosition)
    LOG_DEBUG_TRACKBACK("----createspecialtracker")
    ---@type UI_TrackPoint_C
    local tracker = NewObject(UIManager.UI_TrackPoint, self.layers)
    self.layers.Floating:AddChild(tracker)

    tracker.TrackPosition = TrackPosition

    table.insert(self.special_trackers, tracker)
    self:UpdateTracker(self:ShouldShowTracker(), self.special_trackers)
    return tracker
end

function UIManager:ClearSpecialTracker()
    LOG_DEBUG_TRACKBACK("----clearspecialtracker")
    while #self.special_trackers > 0 do
        local tracker = table.remove(self.special_trackers)
        if UE.UKismetSystemLibrary.IsValid(tracker) then
            tracker:RemoveFromParent()
        end
    end
end

function UIManager:ShouldShowTracker()
    --宇宙航行中，没ui
    if self.layers.Normal:GetAllChildren():Length() == 0 then
        return true 
    end
    if not self.should_show_tracker then
        return false
    end
    local topUI = self:GetTopUI(true, false)
    if not topUI then
        return false
    end
    local visible = true
    local widgetList = self.layers.Normal:GetAllChildren()
    for idx = widgetList:Length(), 1, -1 do
        local widget = widgetList:Get(idx)
        local widget_class = string.lower(widget:GetClass():GetName())
        if string.endswith(widget_class, "_c") then
            widget_class = string.sub(widget_class, 1, -3)
        end
        local found = false
        if idx == widgetList:Length() then
            -- 在顶层，找到就显示
            for _, tracker_show_top_ui in pairs(self.tracker_show_top_uis) do
                if widget_class == tracker_show_top_ui then
                    visible = true
                    found = true
                    break
                end
            end
        else
            -- 不在顶层，找到就不显示
            for _, tracker_show_top_ui in pairs(self.tracker_show_top_uis) do
                if widget_class == tracker_show_top_ui then
                    visible = false
                    found = true
                    break
                end
            end
        end
        if found then
            break
        end
        -- 找到就不显示
        for _, tracker_hide_ui in pairs(self.tracker_hide_uis) do
            if widget_class == tracker_hide_ui then
                visible = false
                found = true
                break
            end
        end
        if found then
            break
        end
    end
    return visible
end

function UIManager:SetShouldShowTracker(should_show)
    if self.should_show_tracker == should_show then return end
    self.should_show_tracker = should_show
    local real_should_show = self:ShouldShowTracker()
    self:UpdateTracker(real_should_show, self.trackers)
    self:UpdateTracker(real_should_show, self.special_trackers)
end

function UIManager:UpdateTracker(visible, trackers)
    trackers = trackers or self.trackers
    for _, tracker in ipairs(trackers) do
        if UE.UKismetSystemLibrary.IsValid(tracker) then
            
            tracker:SetVisibility(visible and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        end
    end
    return visible
end

function UIManager:ReorderNormalUI()
    local widgetList = self.layers.Normal:GetAllChildren()
    for idx = 1, widgetList:Length() do
        local widget = widgetList:Get(idx)
        widget.Slot:SetZOrder(idx)
    end
    local start = 0--widgetList:Length()
    local widgetList = self.layers.UpNormal:GetAllChildren()
    for idx = 1, widgetList:Length() do
        local widget = widgetList:Get(idx)
        widget.Slot:SetZOrder(start+idx)
    end
end


function UIManager:UpdateRequireShowInteractOptions()
    local topUI = self:GetTopUI()

    local show = topUI and topUI.ShowInteractOptions

    LOG_INFO(show)

    self.layers:SetRequireShowInteractOptions(show)
end

function UIManager:SetForceShowCursor(force, skip_simulate_click)
    self.forceShowCursor = force

    self:UpdateCursor(skip_simulate_click)
end

local function clamp(x, min, max)
    return math.min(math.max(x, min), max)
end

function UIManager:MoveCursor(delta)
    local viewportSize = UE.UWidgetLayoutLibrary.GetViewportSize(self.playerController)
    local _, X, Y = self.playerController:GetMousePosition()
    local posX = clamp(UE.UKismetMathLibrary.Round(X + delta.X), 1, math.floor(viewportSize.X))
    local posY = clamp(UE.UKismetMathLibrary.Round(Y + delta.Y), 1, math.floor(viewportSize.Y))
    self.playerController:SetMouseLocation(posX, posY)
end

function UIManager:ShouldShowCursor()
    local topUI = self:GetTopUI()

    local showCursor = self.forceShowCursor or (topUI and not topUI.HideCursor)

    return showCursor
end

function UIManager:UpdateCursor(skip_simulate_click)
    local showCursor = self:ShouldShowCursor()
    local changed = showCursor ~= self.playerController.bShowMouseCursor
    self.playerController.bShowMouseCursor = showCursor
    -- 显示鼠标时手动聚焦到UI（实际模拟左键点击一次）
    -- 隐藏时聚焦到Viewport
    -- 能用但不算合理，不知道有没有更好的办法
    if showCursor then
        local topUI = self:GetTopUI()
        if topUI then
            UE.UWidgetBlueprintLibrary.SetInputMode_GameAndUIEx(self.playerController, nil, UE.EMouseLockMode.DoNotLock, false, false)
            -- UE.UGameplayStatics.SetViewportMouseCaptureMode(self.playerController, UE.EMouseCaptureMode.CapturePermanently_IncludingInitialMouseDown)
        end
    end
    if changed then
        if showCursor then
            local viewportSize = UE.UWidgetLayoutLibrary.GetViewportSize(self.playerController)
            self.playerController:SetMouseLocation(math.floor((viewportSize.X) / 2), math.floor((viewportSize.Y) / 2))

            -- if not skip_simulate_click then
            --     UE.UGHSFunctionLibrary.SimulateLeftMouseButtonClick()
            -- end
        else
            UE.UWidgetBlueprintLibrary.SetInputMode_GameOnly(self.playerController, nil, UE.EMouseLockMode.LockAlways, false, false)
            -- UE.UGameplayStatics.SetViewportMouseCaptureMode(self.playerController, UE.EMouseCaptureMode.CapturePermanently_IncludingInitialMouseDown)
        end
    end
end

function UIManager:UpdateIAMove()
    local topUI = self:GetTopUI()

    if topUI and not topUI.EnableMove then
        LOG_DEBUG_TRACKBACK("UIManager:UpdateIAMove remove mapping context")
        InputUtils.RemoveMappingContext(self.playerController, InputAssets.IMC_Move)
    else
        LOG_DEBUG_TRACKBACK("UIManager:UpdateIAMove add mapping context")
        InputUtils.AddMappingContext(self.playerController, InputAssets.IMC_Move)
    end
end

function UIManager:RemoveMappingContext(widget)
    ---@type UInputMappingContext[]
    local contexts = widget.InputMappingContexts or {}

    for _, context in pairs(contexts) do
        InputUtils.RemoveMappingContext(self.playerController, context)
    end
end

function UIManager:UpdateMappingContext(widget)
    ---@type UInputMappingContext[]
    local contexts = widget.InputMappingContexts or {}

    for _, context in pairs(contexts) do
        InputUtils.AddMappingContext(self.playerController, context)
    end
end

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
---@param TriggerEvent ETriggerEvent
function UIManager:BroadcastInputAction(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction, TriggerEvent)
    local UIActionName = InputUtils.GetInternalUIActionName(InputAction, TriggerEvent)

    local topUI = self:GetTopUI()

    if topUI and topUI:IsVisible() and topUI[UIActionName] then
        topUI[UIActionName](topUI, ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    end
end

function UIManager:CreateUI(UIName)
    local uiConfig = nil
    UIName = string.lower(UIName)
    local d_ui_path = require('ClientDatas.d_ui_path')
    for _, v in pairs(d_ui_path) do
        if string.lower(v.uiName) == UIName then
            uiConfig = v
            break
        end
    end
    if uiConfig and uiConfig.path and uiConfig.path ~= '' then
        --重新创建新的ui
        local path = uiConfig.path
        if not string.endswith(path, "_C'") then
            path = string.sub(path, 1, -2) .. "_C'"
        end
        local widget_class = UE.UClass.Load(path)
        if widget_class then
            local ui = UE4.UWidgetBlueprintLibrary.Create(self.layers, widget_class,
            UE.UGameplayStatics.GetPlayerController(self.layers, 0))
            return ui
        end
    else
        LOG_ERROR('---添加ui:' .. tostring(UIName) .. ',未在配置表中配置d_ui_path')
    end
end

---@param widget UUserWidget
function UIManager:AddUI(widget, upUI)
    if type(widget) == "string" then
        LOG_DEBUG_TRACKBACK("----addui:" .. string.lower(widget))
        widget = self:CreateUI(widget)
        if not widget then
            return
        end
    else
        LOG_DEBUG_TRACKBACK("----addui:" .. string.lower(widget:GetClass():GetName()))
    end

    local oldTopUI = self:GetTopUI()

    if upUI then
        self.layers.UpNormal:AddChild(widget)
    else
        self.layers.Normal:AddChild(widget)
    end

    local anchors = UE.FAnchors()
    local offsets = UE.FMargin()
    anchors.Minimum = UE.FVector2D(0, 0)
    anchors.Maximum = UE.FVector2D(1, 1)
    widget.Slot:SetAnchors(anchors)
    widget.Slot:SetOffsets(offsets)

    self:ReorderNormalUI()
    self:SetForceShowCursor(false, true)
    self:UpdateCursor(true)
    self:UpdateIAMove()
    self:UpdateRequireShowInteractOptions()
    self:UpdateHighlights()
    self:UpdateMaskedHighlight()
    local visible = self:ShouldShowTracker()
    self:UpdateTracker(visible)
    self:UpdateTracker(visible, self.special_trackers)

    local topUI = self:GetTopUI()
    if oldTopUI ~= topUI then
        if oldTopUI then
            self:RemoveMappingContext(oldTopUI)
        end
        self:UpdateMappingContext(topUI)
    end
    return widget
end

---@param widget UUserWidget
function UIManager:RemoveUI(widget, upUI)
    LOG_DEBUG_TRACKBACK("----removeui:" .. tostring(string.lower(widget:GetClass():GetName())))
    local oldTopUI = self:GetTopUI()

    if self.highlights[widget] then
        for _, highlight in ipairs(self.highlights[widget]) do
            highlight:RemoveFromParent()
        end
    end

    local removed
    if upUI then
        removed = self.layers.UpNormal:RemoveChild(widget)
    else
        removed = self.layers.Normal:RemoveChild(widget)
    end

    local topUI = self:GetTopUI()
    if oldTopUI ~= topUI then
        self:RemoveMappingContext(oldTopUI)
        if topUI then
            self:UpdateMappingContext(topUI)
        end
    end

    if removed then
        self:ReorderNormalUI()
        self:SetForceShowCursor(false)
        self:UpdateCursor()
        self:UpdateIAMove()
        self:UpdateRequireShowInteractOptions()
        self:UpdateHighlights()
        self:UpdateMaskedHighlight()
        local visible = self:ShouldShowTracker()
        self:UpdateTracker(visible)
        self:UpdateTracker(visible, self.special_trackers)
    else
        widget:RemoveFromParent()
    end
end

function UIManager:GetTopUI(useFilter, upUI)
    if useFilter then
        if upUI then
            local count = self.layers.UpNormal:GetChildrenCount()
            if count > 0 then
                local top = self.layers.UpNormal:GetChildAt(count - 1)
                return top, count, true
            end
        else
            local count = self.layers.Normal:GetChildrenCount()
            if count > 0 then
                local top = self.layers.Normal:GetChildAt(count - 1)
                return top, count, false
            end
        end
        return nil, 0, false
    end
    local count = self.layers.UpNormal:GetChildrenCount()
    if count > 0 then
        local top = self.layers.UpNormal:GetChildAt(count - 1)
        return top, count, true
    end
    local count = self.layers.Normal:GetChildrenCount()
    if count > 0 then
        local top = self.layers.Normal:GetChildAt(count - 1)
        return top, count, false
    end
    return nil, 0, false
end

function UIManager:AddLoadingUI(widget, z_order)
    LOG_DEBUG_TRACKBACK("----addloadingui:" .. tostring(string.lower(widget:GetClass():GetName())))
    self.layers.Loading:AddChild(widget)
    
    local anchors = UE.FAnchors()
    local offsets = UE.FMargin()
    anchors.Minimum = UE.FVector2D(0, 0)
    anchors.Maximum = UE.FVector2D(1, 1)
    widget.Slot:SetAnchors(anchors)
    widget.Slot:SetOffsets(offsets)
    if z_order then
        widget.Slot:SetZOrder(z_order)
    end
end

function UIManager:RemoveLoadingUI(widget)
    LOG_DEBUG_TRACKBACK("----removeloadingui:" .. tostring(string.lower(widget:GetClass():GetName())))
    self.layers.Loading:RemoveChild(widget)
end

function UIManager:DebugUI()
    print('------------------Debug UI------------------')
    local widgetList = self.layers.UpNormal:GetAllChildren()
    for i = widgetList:Length(), 1, -1 do
        local ui = widgetList:Get(i)
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        print('--index:' .. tostring(i) .. ",ui:" .. tostring(className))
    end
    local widgetList = self.layers.Normal:GetAllChildren()
    for i = widgetList:Length(), 1, -1 do
        local ui = widgetList:Get(i)
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        print('--index:' .. tostring(i) .. ",ui:" .. tostring(className))
    end
    print('--------------------------------------------')
end

function UIManager:RemoveAll()
    LOG_DEBUG_TRACKBACK('-----removeAllUI')
    while true do
        local widget, count, upUI = self:GetTopUI()
        if count <= 1 then break end
        self:RemoveUI(widget, upUI)
    end
end

return UIManager
