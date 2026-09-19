local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type BP_PlayerController_UniverseCutScene_C
local M = UnLua.Class()

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_MoveCamera(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    local pawn = self:K2_GetPawn()

    if not pawn then
        return
    end

    local input = ActionValue:GetAxis2D()
    pawn:AddControllerPitchInput(input.Y * self.LookUpRate)
    pawn:AddControllerYawInput(input.X * self.TurnRate)
end

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_MoveCamera, UE.ETriggerEvent.Triggered, M.IA_MoveCamera)
UnLua.EnhancedInput.BindActionValue(M, InputAssets.IA_Move)

function M:SetUpInput()
    ---@type APlayerController
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)

    InputUtils.AddMappingContext(PC, InputAssets.IMC_Common)
    InputUtils.AddMappingContext(PC, InputAssets.IMC_Move)
    InputUtils.RegisterAllMappingContext(PC)

    PC.bShowMouseCursor = false
end

function M:SetupIndicator()
    local player = self:K2_GetPawn()

    local pickups = UE.UGameplayStatics.GetAllActorsOfClass(self, LoadClass('/Game/_Game/Blueprints/SceneObjects/SO_PickUpItem_Universe.SO_PickUpItem_Universe_C'))

    for i = 1, pickups:Num() do
        local pickup = pickups[i]

        ---@type BP_Indicator_C
        local indicator = self:GetWorld():SpawnActor(LoadClass('/Game/_Game/Blueprints/Game/BP_Indicator.BP_Indicator_C'),
            player:GetTransform(),
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
            self, self)

        indicator:SetUp(player, pickup)
    end
end

function M:ReceiveBeginPlay()
    self:SetUpInput()

    UIManager:GetInstance():OnBeginPlay(self)
    UIManager:GetInstance():ShowWaterMask(self)

    self.Overridden.ReceiveBeginPlay(self)

    self:SetupIndicator()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
    coroutine.resume(coroutine.create(function()
        UE.UKismetSystemLibrary.Delay(self, 1)
        gameInstance:RemoveUMG("UI_Loading2")
    end))
end

function M:ReceiveEndPlay(EndPlayReason)
    self.Overridden.ReceiveEndPlay(self, EndPlayReason)
    UIManager:GetInstance():OnEndPlay()
end

---@param TrackPosition FVector
function M:CreateTracker(TrackPosition)
    UIManager:GetInstance():CreateTracker(TrackPosition)
end

function M:ClearTracker()
    UIManager:GetInstance():ClearTracker()
end


return M
