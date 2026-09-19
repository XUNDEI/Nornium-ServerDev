local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local Database = require("_Game.Utils.Database")

---@type UI_Layers_C
local M = UnLua.Class()

local Client = require "Network.Client"

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
---@param TriggerEvent ETriggerEvent
function M:BroadcastInputAction(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction, TriggerEvent)
    --print('===BroadcastInputAction ', ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction, TriggerEvent)
    UIManager:GetInstance():BroadcastInputAction(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction, TriggerEvent)
end

InputUtils.BindAllEvents(M, {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
    InputAssets.IMC_UI_SystemEntry,
    InputAssets.IMC_UI_Gacha,
    InputAssets.IMC_UI_MoveUp,
    InputAssets.IMC_UI_MoveDown,
    InputAssets.IMC_UI_MoveRight,
    InputAssets.IMC_UI_MoveLeft,
    InputAssets.IMC_UI_ZoomIn,
    InputAssets.IMC_UI_StoryCursor,
}, M.BroadcastInputAction)

function M:Construct()
    if not M.UI_Com_Option_Item then
        M.UI_Com_Option_Item = LoadClass('/Game/_Game/Blueprints/UI/UI_Com_Option_Item.UI_Com_Option_Item_C')
        M.UI_Com_Option_ItemRef = UnLua.Ref(M.UI_Com_Option_Item)
        M.BP_FingerPosRecorder = LoadClass('/Game/_Game/Blueprints/Character/BP_FingerPosRecorder.BP_FingerPosRecorder_C')
        M.BP_FingerPosRecorderRef = UnLua.Ref(M.BP_FingerPosRecorder)
    end

    self.UI_Cursor.Trail_lizi.NiagaraComponent:SetAllowScalability(false)
    self.UI_Cursor.NiagaraSystemWidget_65.NiagaraComponent:SetAllowScalability(false)
    self.UI_Cursor.WEAK.NiagaraComponent:SetAllowScalability(false)
    

    -- 顶层ui是否需要显示选项
    self.requireShowInteractOptions = false

    ---@type table<UObject, UI_Com_Option_Item_C[]>
    self.interactOptions = {}
    self.selectedOptionIndex = 0
end

local function clamp(x, min, max)
    return math.min(math.max(x, min), max)
end

function M:SelectInteractOption(index)
    self.Options:GetChildAt(index - 1).Key:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
end

function M:UnselectInteractOption(index)
    self.Options:GetChildAt(index - 1).Key:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:SwitchInteractOption(dir)
    local optionCount = self.Options:GetChildrenCount()

    if self.selectedOptionIndex ~= 0 then
        self:UnselectInteractOption(self.selectedOptionIndex)
    end

    local newIndex = self.selectedOptionIndex + (dir > 0 and 1 or -1)

    if newIndex == 0 then
        newIndex = optionCount
    elseif newIndex > optionCount then
        newIndex = 1
    end
    self.selectedOptionIndex = newIndex
    self:SelectInteractOption(self.selectedOptionIndex)
end

function M:IA_Interact()
    local index = self.selectedOptionIndex - 1
    local itemCount = self.Options:GetChildrenCount()
    -- print("------>index:" .. tostring(index) .. ",itemCount:" .. tostring(itemCount))
    if itemCount > 0 and index < itemCount then
        self.Options:GetChildAt(self.selectedOptionIndex - 1).Button.OnClicked:Broadcast()
    end
end

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_SwitchOption(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    local dir = ActionValue:GetAxis1D()

    self:SwitchInteractOption(dir)
end

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Interact, UE.ETriggerEvent.Completed, M.IA_Interact)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_SwitchOption, UE.ETriggerEvent.Started, M.IA_SwitchOption)

-- 根据选项数量更新交互状态
-- 0：解绑交互绑定，隐藏选项
-- >0：绑定交互，显示选项
-- >1：显示切换提示
function M:UpdateInteractOptions()
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    local optionCount = self.Options:GetChildrenCount()
    LOG_INFO(self.requireShowInteractOptions)
    local showOptions = optionCount > 0 and self.requireShowInteractOptions

    self.InteractOption:SetVisibility(showOptions and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)

    if optionCount > 0 then
        -- 如果因为选项减少导致选定选项变更，显然只需要更新新选定选项
        self.selectedOptionIndex = clamp(self.selectedOptionIndex, 1, optionCount)
        self:SelectInteractOption(self.selectedOptionIndex)
    else
        self.selectedOptionIndex = 0
    end
    
    if showOptions then
        InputUtils.AddMappingContext(PC, InputAssets.IMC_UI_Options)
    else
        InputUtils.RemoveMappingContext(PC, InputAssets.IMC_UI_Options)
    end

    self.Switch:SetVisibility(optionCount > 1 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
end

function M:SetRequireShowInteractOptions(show)
    self.requireShowInteractOptions = show

    self:UpdateInteractOptions()
end

function M:AddInteractOption(object, textId, callback)
    LOG_DEBUG_TRACKBACK("AddInteractOption", object, textId, callback)
    ---@type UI_Com_Option_Item_C
    local option = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Com_Option_Item)
    self.Options:AddChild(option)
    self:UpdateInteractOptions()

    local text = textId

    if type(textId) == "number" then
        text = Database.L10n(textId)
    end

    option.Name:SetText(text)

    option.Button.OnClicked:Add(option.Button, function()
        callback()
    end)

    if not self.interactOptions[object] then
        self.interactOptions[object] = {}
    end

    table.insert(self.interactOptions[object], option)

    return option
end

-- 移除单个选项
function M:RemoveInteractOption(option)
    if self.Options:RemoveChild(option) then
        self:UpdateInteractOptions()
    end
end

-- 移除某个object引入的所有交互选项
function M:RemoveInteractOptionByObject(object)
    local options = self.interactOptions[object]

    if options then
        for _, option in pairs(options) do
            if UE.UKismetSystemLibrary.IsValid(option) then
                option:RemoveFromParent()
            end
        end
    end

    self:UpdateInteractOptions()

    self.interactOptions[object] = nil
end

function M:ClearInteractOption()
    self.Options:ClearChildren()

    self:UpdateInteractOptions()
end

---Ticks this widget.  Override in derived classes, but always call the parent implementation.
---@param MyGeometry FGeometry
---@param InDeltaTime number
function M:Tick(MyGeometry, InDeltaTime)
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    ---@type BP_FingerPosRecorder_C
    local recorder = PC:GetComponentByClass(M.BP_FingerPosRecorder)

    -- todo 显然移动端不会隐藏
    if recorder and UIManager:GetInstance():ShouldShowCursor() then
        -- 移动端当时要除的 可能要改
        local position = UE.UKismetMathLibrary.Conv_VectorToVector2D(recorder.FingerLastPos:Find(UE.ETouchIndex.CursorPointerIndex))

        self.UI_Cursor.Slot:SetPosition(position)

        if recorder.FingerJustPressed:Find(UE.ETouchIndex.CursorPointerIndex) then
            self.UI_Cursor:PlayAnimationForward(self.UI_Cursor.CursorBurst_strong, 1, true)
            self.UI_Cursor.Trail_lizi:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            recorder.FingerJustPressed:Add(UE.ETouchIndex.CursorPointerIndex, false)
        end

        if recorder.FingerJustReleased:Find(UE.ETouchIndex.CursorPointerIndex) then
            self.UI_Cursor.Trail_lizi:SetVisibility(UE.ESlateVisibility.Hidden)
            recorder.FingerJustReleased:Add(UE.ETouchIndex.CursorPointerIndex, false)
        end
    end

    self.Overridden.Tick(self, MyGeometry, InDeltaTime)
end


function M:res_record_player_transform_in_scene(result, msgId, parsed_msg)
    if result == 0 then
    end
end

return M
