--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "Global"
require "UnLua"

local Database = require "_Game.Utils.Database"
local GlobalConfig = require("GlobalConfig")
local SrpgController = require "Module.Srpg.SrpgController"
local hex_grid = require "Helper.hex_grid"
local UI_Dialog_Story_C = require("_Game.Blueprints.UI.UI_Dialog_Story_C")
local InputAssets = require "_Game.Utils.Input.InputAssets"

---@type BP_PlayerController_UniverseMenu_C
local M = Class()

function M:Initialize()
end

function M:ReceiveBeginPlay()
    --重置音乐
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:ClearBgm()

    local ui = gameInstance:AddUMG("UI_Menu")
    if ui then
        self.UI_Menu = ui
        ui:InitUI()
        ui:RefreshUI(true)
        ui:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    self.Overridden.ReceiveBeginPlay(self)

    MessageManager:GetInstance():AddListener(UI_Dialog_Story_C.DialogEnd, self)
end

function M:ReceiveEndPlay(EndPlayReason)
    MessageManager:GetInstance():RemoveListener(UI_Dialog_Story_C.DialogEnd, self)

    self.Overridden.ReceiveEndPlay(self, EndPlayReason)
end

function M:MoveInMapMenu()
    self.Overridden.MoveInMapMenu(self)

    self.UI_Menu:UpdateAllIcon()
end

function M:UpdateMapBounds()
    self.Overridden.UpdateMapBounds(self)

    self.MapMinX = self.MapMinX - GlobalConfig.ExtraSpaceX * self.SpringArmScale
    self.MapMinY = self.MapMinY - GlobalConfig.ExtraSpaceY * self.SpringArmScale
    self.MapMaxX = self.MapMaxX + GlobalConfig.ExtraSpaceX * self.SpringArmScale
    self.MapMaxY = self.MapMaxY + GlobalConfig.ExtraSpaceY * self.SpringArmScale
end

local function IsNear(a, b, epsilon)
    return math.abs(a - b) < epsilon
end

function M:UpdateMapBoundEffect()
    ---@type FVector
    local actorLocation = UE.UGameplayStatics.GetPlayerController(self, 0):K2_GetPawn():K2_GetActorLocation()

    if IsNear(actorLocation.X, self.MapMinX, 0.1) then
        if not self.leftWarningVisible then
            self.UI_Menu:PlayAnimationForward(self.UI_Menu.SpaceEdge_Left_Anination, 1, false)
            self.leftWarningVisible = true
        end
    else
        if self.leftWarningVisible then
            self.UI_Menu.Image_L_a:SetOpacity(0)
            self.UI_Menu.Image_L_b:SetOpacity(0)
            self.leftWarningVisible = false
        end
    end
    if IsNear(actorLocation.X, self.MapMaxX, 0.1) then
        if not self.rightWarningVisible then
            self.UI_Menu:PlayAnimationForward(self.UI_Menu.SpaceEdge_Right_Animation, 1, false)
            self.rightWarningVisible = true
        end
    else
        if self.rightWarningVisible then
            self.UI_Menu.Image_R_a:SetOpacity(0)
            self.UI_Menu.Image_R_b:SetOpacity(0)
            self.rightWarningVisible = false
        end
    end
    if IsNear(actorLocation.Y, self.MapMaxY, 0.1) then
        if not self.downWarningVisible then
            self.UI_Menu:PlayAnimationForward(self.UI_Menu.SpaceEdge_Down_Animation, 1, false)
            self.downWarningVisible = true
        end
    else
        if self.downWarningVisible then
            self.UI_Menu.Image_Down_a:SetOpacity(0)
            self.UI_Menu.Image_Down_b:SetOpacity(0)
            self.downWarningVisible = false
        end
    end
    if IsNear(actorLocation.Y, self.MapMinY, 0.1) then
        if not self.topWarningVisible then
            self.UI_Menu:PlayAnimationForward(self.UI_Menu.SpaceEdge_Top_Animation, 1, false)
            self.topWarningVisible = true
        end
    else
        if self.topWarningVisible then
            self.UI_Menu.Image_Top_a:SetOpacity(0)
            self.UI_Menu.Image_Top_b:SetOpacity(0)
            self.topWarningVisible = false
        end
    end
end

---@param Widget UWidget
---@param Location FVector
local function IsInBound(Widget, Location)
    if UE.UKismetSystemLibrary.IsValid(Widget) and Widget:IsVisible() then
        local geometry = Widget:GetCachedGeometry()
        local absolutePosition = UE.FVector2D(Location.X, Location.Y)
        return UE.USlateBlueprintLibrary.IsUnderLocation(geometry, absolutePosition)
    end
    return false
end

function M:BlockInput()
    return self.UI_Menu.UI_SRPG_Option:IsVisible()
end

---@param Location FVector
function M:BlockTouchInput(Location)
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    if SrpgController:GetInstance():HasPendingEvent() then
        LOG_WARN("Blocked by events")
        LOG_WARN(table.dump(SrpgController:GetInstance().model.pendingEvents))
    end

    return SrpgController:GetInstance():HasPendingEvent() or (playerController.UI_CityMenu and playerController.UI_CityMenu:IsVisible())
end

function M:SetUIMenuVisibility(visible)
    self.UI_Menu:UpdateHp()
    self.Overridden.SetUIMenuVisibility(self, visible)
end

-- 这个值是星图场景角色的高度，可能应该改成进星图时去取
local CHARACTER_HEIGHT = 1258

local function clamp(x, min, max)
    return math.min(math.max(x, min), max)
end

function M:AddScale(deltaScale)
    self.SpringArmScale = clamp(self.SpringArmScale * GlobalConfig.ScaleStep ^ deltaScale, GlobalConfig.ScaleMin, GlobalConfig.ScaleMax)

    local cameraHeight = CHARACTER_HEIGHT - CHARACTER_HEIGHT / self.SpringArmScale

    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    ---@type BP_Character_Menu_C
    local character = playerController:K2_GetPawn()
    local characterLocation = character:K2_GetActorLocation()
    local cameraForward = character.Camera:GetForwardVector()

    local cameraLocation = characterLocation - cameraForward * cameraHeight / cameraForward.Z

    character.Camera:K2_SetWorldLocation(cameraLocation, false, nil, true)

    self:UpdateDetailsVisibility()
    self:UpdateMapBounds()
    self:UpdateUISize()
end

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_Scale_Triggered(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    local pawn = playerController:K2_GetPawn()

    if not UE.UGameplayStatics.ObjectIsA(pawn, LoadClass('/Game/_Game/Blueprints/Character/BP_Character_Menu.BP_Character_Menu_C')) then
        return
    end

    local value = ActionValue:GetAxis1D()

    self:AddScale(value > 0 and GlobalConfig.ScaleStep or -GlobalConfig.ScaleStep)
end

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Scale, UE.ETriggerEvent.Triggered, M.IA_Scale_Triggered)

function M:HidePlanetUI()
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    for _, mapPlanet in pairs(playerController.MapPlanets) do
        mapPlanet:HideAllUI()
    end
end

function M:UpdateDetailsVisibility()
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    for _, mapPlanet in pairs(playerController.MapPlanets) do
        mapPlanet.Model:SetVisibility(self.SpringArmScale >= GlobalConfig.DetailThreshold, true)
    end
    if playerController.detailedBosses then
        for _, boss in pairs(playerController.detailedBosses) do
            boss:SetActorHiddenInGame(self.SpringArmScale < GlobalConfig.DetailThreshold)
        end
    end
    if playerController.detailedShip then
        playerController.detailedShip:SetActorHiddenInGame(self.SpringArmScale < GlobalConfig.DetailThreshold)
    end
    for _, mapPlanet in pairs(playerController.MapPlanets) do
        mapPlanet:SetUIZoomLevel(self.SpringArmScale)
    end
end

M[UI_Dialog_Story_C.DialogEnd] = function(self, originDialogId, dialogId)
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    for _, mapPlanet in pairs(playerController.MapPlanets) do
        mapPlanet:ResetUI()
    end
end

function M:InputTouchReleased(Location, FingerIndex)
    if self.SpringArmScale >= GlobalConfig.DetailThreshold then
        self.Overridden.InputTouchReleased(self, Location, FingerIndex)
    end
end

function M:InputTouchMove(Location, FingerIndex)
    self.Overridden.InputTouchMove(self, Location, FingerIndex)

    self.UI_Menu:UpdateAllIcon()
end

function M:GetPlayerHexId()
    return hex_grid.to_string(SrpgController:GetInstance():GetPlayerHex())
end

return M
