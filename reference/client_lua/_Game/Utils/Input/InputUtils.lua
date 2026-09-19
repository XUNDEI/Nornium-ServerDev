local InputAssets = require "_Game.Utils.Input.InputAssets"
local Database = require "_Game.Utils.Database"

local M = {}

M.MappingContextPriority = {
    [InputAssets.IMC_UI_Cursor] = 8,
    [InputAssets.IMC_UI_StoryCursor] = 8,
    [InputAssets.IMC_BuildActor] = 7,
    [InputAssets.IMC_UI_Options] = 6,
    [InputAssets.IMC_UI_Gacha] = 5,
    [InputAssets.IMC_UI_MoveUp] = 5,
    [InputAssets.IMC_UI_MoveDown] = 5,
    [InputAssets.IMC_UI_MoveRight] = 5,
    [InputAssets.IMC_UI_MoveLeft] = 5,
    [InputAssets.IMC_UI_ZoomIn] = 5,
    [InputAssets.IMC_UI_Common] = 4,
    [InputAssets.IMC_Fight] = 3,
    [InputAssets.IMC_UI_SystemEntry] = 2,
    [InputAssets.IMC_Common] = 1,
    [InputAssets.IMC_Move] = 1,
    [InputAssets.IMC_Character] = 0,
}

---添加 InputMappingContext
---@param PC APlayerController
---@param InputMappingContext UInputMappingContext
---@param Priority integer
---@param Options FModifyContextOptions @[opt] 
function M.AddMappingContext(PC, InputMappingContext, Options)
    -- LOG_DEBUG_TRACKBACK("AddMappingContext", PC, InputMappingContext, Options)
    local Options = Options or UE.FModifyContextOptions()
    Options.bIgnoreAllPressedKeysUntilRelease = true
    local Priority = M.MappingContextPriority[InputMappingContext]
    ---@type UEnhancedInputLocalPlayerSubsystem
    local EnhancedInputLocalPlayerSubsystem = UE.USubsystemBlueprintLibrary.GetLocalPlayerSubSystemFromPlayerController(PC, UE.UEnhancedInputLocalPlayerSubsystem)
    if EnhancedInputLocalPlayerSubsystem then
        EnhancedInputLocalPlayerSubsystem:AddMappingContext(InputMappingContext, Priority, Options)
    end
end

---@param PC APlayerController
---@param InputMappingContext UInputMappingContext
---@param Options FModifyContextOptions @[opt] 
function M.RemoveMappingContext(PC, InputMappingContext, Options)
    -- LOG_DEBUG_TRACKBACK("RemoveMappingContext", PC, InputMappingContext, Options)
    local Options = Options or UE.FModifyContextOptions()
    Options.bIgnoreAllPressedKeysUntilRelease = true
    ---@type UEnhancedInputLocalPlayerSubsystem
    local EnhancedInputLocalPlayerSubsystem = UE.USubsystemBlueprintLibrary.GetLocalPlayerSubSystemFromPlayerController(PC, UE.UEnhancedInputLocalPlayerSubsystem)
    if EnhancedInputLocalPlayerSubsystem then
        EnhancedInputLocalPlayerSubsystem:RemoveMappingContext(InputMappingContext, Options)
    end
end

---@param PC APlayerController
function M.ClearAllMappings(PC)
    -- LOG_DEBUG_TRACKBACK("ClearAllMappings", PC)
    ---@type UEnhancedInputLocalPlayerSubsystem
    local EnhancedInputLocalPlayerSubsystem = UE.USubsystemBlueprintLibrary.GetLocalPlayerSubSystemFromPlayerController(PC, UE.UEnhancedInputLocalPlayerSubsystem)
    if EnhancedInputLocalPlayerSubsystem then
        EnhancedInputLocalPlayerSubsystem:ClearAllMappings()
    end
end

function M.RegisterAllMappingContext(PC)
    -- LOG_DEBUG_TRACKBACK("RegisterAllMappingContext", PC)
    ---@type UEnhancedInputLocalPlayerSubsystem
    local EnhancedInputLocalPlayerSubsystem = UE.USubsystemBlueprintLibrary.GetLocalPlayerSubSystemFromPlayerController(PC, UE.UEnhancedInputLocalPlayerSubsystem)
    local UserSetting = EnhancedInputLocalPlayerSubsystem:GetUserSettings()

    for _, entry in pairs(InputAssets) do
        if UE.UGameplayStatics.ObjectIsA(entry, UE.UInputMappingContext) then
            UserSetting:RegisterInputMappingContext(entry)
        end
    end

    UserSetting:ApplySettings()
end

---@param WorldContext UObject
---@param BindName string
---@param Slot EPlayerMappableKeySlot
function M.GetMapping(WorldContext, BindName, Slot)
    ---@type APlayerController
    local PC = UE.UGameplayStatics.GetPlayerController(WorldContext, 0)

    ---@type UEnhancedInputLocalPlayerSubsystem
    local EnhancedInputLocalPlayerSubsystem = UE.USubsystemBlueprintLibrary.GetLocalPlayerSubSystemFromPlayerController(PC, UE.UEnhancedInputLocalPlayerSubsystem)

    local UserSetting = EnhancedInputLocalPlayerSubsystem:GetUserSettings()

    local Mapping = UE.FPlayerKeyMapping()

    local Slot = Slot or UE.EPlayerMappableKeySlot.First
    local Args = UE.FMapPlayerKeyArgs()
    Args.Slot = Slot
    Args.MappingName = BindName

    UserSetting:GetCurrentKeyProfile():K2_FindKeyMapping(Mapping, Args)

    return Mapping
end

function M.SaveMapping(WorldContext, BindName, Key, Slot)
    ---@type APlayerController
    local PC = UE.UGameplayStatics.GetPlayerController(WorldContext, 0)

    ---@type UEnhancedInputLocalPlayerSubsystem
    local EnhancedInputLocalPlayerSubsystem = UE.USubsystemBlueprintLibrary.GetLocalPlayerSubSystemFromPlayerController(PC, UE.UEnhancedInputLocalPlayerSubsystem)

    local UserSetting = EnhancedInputLocalPlayerSubsystem:GetUserSettings()

    local Slot = Slot or UE.EPlayerMappableKeySlot.First
    local Args = UE.FMapPlayerKeyArgs()
    Args.Slot = Slot
    Args.MappingName = BindName
    Args.NewKey = Key

    UserSetting:MapPlayerKey(Args)
    UserSetting:ApplySettings()
    UserSetting:SaveSettings()
end

function M.ResetMapping(WorldContext, BindName, Slot)
    ---@type APlayerController
    local PC = UE.UGameplayStatics.GetPlayerController(WorldContext, 0)

    ---@type UEnhancedInputLocalPlayerSubsystem
    local EnhancedInputLocalPlayerSubsystem = UE.USubsystemBlueprintLibrary.GetLocalPlayerSubSystemFromPlayerController(PC, UE.UEnhancedInputLocalPlayerSubsystem)

    local UserSetting = EnhancedInputLocalPlayerSubsystem:GetUserSettings()

    local Slot = Slot or UE.EPlayerMappableKeySlot.First
    local Args = UE.FMapPlayerKeyArgs()
    Args.Slot = Slot
    Args.MappingName = BindName

    UserSetting:ResetAllPlayerKeysInRow(Args)
    UserSetting:ApplySettings()
    UserSetting:SaveSettings()
end

function M.GetInternalUIActionName(InputAction, TriggerEvent)
    return string.format("UnLuaUIAction_%s_%d", InputAction:GetName(), TriggerEvent)
end

---@param Module table
---@param InputAction UInputAction
---@param TriggerEvent ETriggerEvent
---@param Handler fun(self:UObject, ActionValue:boolean|number|FVector2D|FVector3d, ElapsedSeconds:number, TriggeredSeconds:number, InputAction:UInputAction)
function M.RegisterUIAction(Module, InputAction, TriggerEvent, Handler)
    local callbackName = M.GetInternalUIActionName(InputAction, TriggerEvent)

    if not Module[callbackName] then
        Module[callbackName] = Handler
    else
        LOG_WARN("Name conflict!", "callbackName")
    end
end

local EVENTS = {
    UE.ETriggerEvent.Triggered,
    UE.ETriggerEvent.Started,
    UE.ETriggerEvent.Ongoing,
    UE.ETriggerEvent.Canceled,
    UE.ETriggerEvent.Completed,
}

---直接把 InputMappingContext 内所有 InputAction 的所有事件全绑定
---目前可能只有 UI 要这么做
---@param Module table @需要绑定的lua模块
---@param InputMappingContexts UInputMappingContext[]
---@param Handler fun(self:UObject, ActionValue:boolean|number|FVector2D|FVector3d, ElapsedSeconds:number, TriggeredSeconds:number, InputAction:UInputAction, TriggerEvent:ETriggerEvent)
function M.BindAllEvents(Module, InputMappingContexts, Handler)
    local boundInputAction = {}

    local callbacks = {}

    for _, Event in ipairs(EVENTS) do
        callbacks[Event] = function(self, ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
            Handler(self, ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction, Event)
        end
    end

    for _, InputMappingContext in pairs(InputMappingContexts) do
        local Mappings = InputMappingContext.Mappings
        
        ---@param Mapping FEnhancedActionKeyMapping
        for _, Mapping in pairs(Mappings) do
            local InputAction = Mapping.Action
            
            if not boundInputAction[InputAction] then
                for _, Event in ipairs(EVENTS) do
                    UnLua.EnhancedInput.BindAction(Module, InputAction, Event, callbacks[Event])
                    boundInputAction[InputAction] = true
                end
            end
        end
    end
end

M.Platform = {
    PC = 1,
    Xbox = 2,
    PS = 3,
    NS = 4,
}

M.PlatformName = {
    "PC_",
    "XBox_",
    "PS_",
    "NS_",
}

M.PlatformDependentKeys = {
    "Gamepad_FaceButton_Bottom",
    "Gamepad_FaceButton_Right",
    "Gamepad_FaceButton_Left",
    "Gamepad_FaceButton_Top",
}

function M.GetPlatformName(platform)
    return M.PlatformName[platform]
end

function M.IsGamepad(platform)
    return platform ~= M.Platform.PC
end

local AssetNameFormat = '%s%s_png'
local AssetPathFormat = '/Game/_Game/TP_New/SetSystem/Frames/%s.%s'

---@param Key FKey
---@param platform string
function M.GetKeyAsset(Key, platform)
    if Key == UE.EKeys.None or tostring(Key.KeyName) == "None" then
        return nil
    end
    local platform = platform or M.Platform.PC
    local platformName = M.GetPlatformName(platform)

    local needPlatformPrefix = (platform == M.Platform.PC) or table.any(M.PlatformDependentKeys, function(name)
        return name == Key.KeyName
    end)

    local assetName = string.format(AssetNameFormat, needPlatformPrefix and platformName or "", Key.KeyName)
    local assetPath = string.format(AssetPathFormat, assetName, assetName)

    return LoadObject(assetPath)
end

M.UnassignableKeys = {
    "LeftMouseButton",
    "RightMouseButton",
    "MiddleMouseButton",
    "MouseScrollUp",
    "MouseScrollDown",
    "LeftAlt",
    "Escape",
}

---@param Key FKey
function M.IsKeyAssignable(Key)
    return not table.any(M.UnassignableKeys, function(name)
        return name == Key.KeyName
    end)
end

---@param WorldContext UObject
---@param Key FKey
---@return number, TArray<string>
function M.FindConflictMapping(WorldContext, Key)
    ---@type APlayerController
    local PC = UE.UGameplayStatics.GetPlayerController(WorldContext, 0)

    ---@type UEnhancedInputLocalPlayerSubsystem
    local EnhancedInputLocalPlayerSubsystem = UE.USubsystemBlueprintLibrary.GetLocalPlayerSubSystemFromPlayerController(PC, UE.UEnhancedInputLocalPlayerSubsystem)

    local UserSetting = EnhancedInputLocalPlayerSubsystem:GetUserSettings()

    return UserSetting:GetCurrentKeyProfile():GetMappingNamesForKey(Key)
end

---@param MappingName string
function M.FindDefineMappingContext(MappingName)
    ---@param entry UInputMappingContext
    for _, entry in pairs(InputAssets) do
        if UE.UGameplayStatics.ObjectIsA(entry, UE.UInputMappingContext) then
            ---@param Mapping FEnhancedActionKeyMapping
            for _, Mapping in pairs(entry.Mappings) do
                if Mapping.SettingBehavior == UE.EPlayerMappableKeySettingBehaviors.OverrideSettings then
                    if MappingName == Mapping.PlayerMappableKeySettings.Name then
                        return entry
                    end
                end
            end
        end
    end
end

M.MappingContextType = {
    [InputAssets.IMC_UI_Common] = 334,
    [InputAssets.IMC_UI_SystemEntry] = 334,
    [InputAssets.IMC_UI_Cursor] = 334,
    [InputAssets.IMC_Move] = 333,
    [InputAssets.IMC_Common] = 333,
    [InputAssets.IMC_Character] = 333,
    [InputAssets.IMC_Fight] = 335,
}

M.CompatibleContext = {
    [InputAssets.IMC_Fight] = {
        [InputAssets.IMC_UI_SystemEntry] = true,
        [InputAssets.IMC_Character] = true,
    },
    [InputAssets.IMC_UI_SystemEntry] = {
        [InputAssets.IMC_Fight] = true,
    },
    [InputAssets.IMC_Character] = {
        [InputAssets.IMC_Fight] = true,
    },
}

function M.IsCompatible(contextA, contextB)
    return M.CompatibleContext[contextA] and M.CompatibleContext[contextA][contextB]
end

local CursorSpeed = Database.Query("d_com_params", 24).value2

-- 通用的移动鼠标回调，这两个回调只关心worldcontext
---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_MoveCursor(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    local inputValue = ActionValue:GetAxis2D() * CursorSpeed
    UIManager:GetInstance():MoveCursor(inputValue)
end

function M:IA_SimulateClick_Started(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    UE.UGHSFunctionLibrary.SimulateLeftMouseButton(true)
end

function M:IA_SimulateClick_Completed(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    UE.UGHSFunctionLibrary.SimulateLeftMouseButton(false)
end

function M.RegisterMouseEvent(module)
    M.RegisterUIAction(module, InputAssets.IA_SimulateClick, UE.ETriggerEvent.Started, M.IA_SimulateClick_Started)
    M.RegisterUIAction(module, InputAssets.IA_SimulateClick, UE.ETriggerEvent.Completed, M.IA_SimulateClick_Completed)
    M.RegisterUIAction(module, InputAssets.IA_MoveCursor, UE.ETriggerEvent.Triggered, M.IA_MoveCursor)
end

function M.RegisterConfirmAndCancel(module, confirmCallback, cancelCallback)
    if confirmCallback then
        M.RegisterUIAction(module, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, confirmCallback)
    end

    if cancelCallback then
        M.RegisterUIAction(module, InputAssets.IA_Back, UE.ETriggerEvent.Completed, cancelCallback)
    end
end

function M.IA_Back(self)
    UIManager:GetInstance():RemoveUI(self)
end

-- 普通按b关闭，简单关闭
function M.BindClose(module)
    M.RegisterUIAction(module, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.IA_Back)
end

return M
