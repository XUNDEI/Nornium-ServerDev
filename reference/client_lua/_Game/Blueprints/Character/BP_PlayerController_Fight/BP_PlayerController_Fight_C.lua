local FightTestConfig = require("_Game.FightTestConfig")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local UIUtils = require "_Game.Utils.UIUtils"

local USE_TEST_CONFIG = false

---@type BP_PlayerController_Fight_C
local M = UnLua.Class()

function M:IA_NormalAttack_Started()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill1(true)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill1(true)
                end
            end
        end
    end
end

function M:IA_NormalAttack_Completed()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill1(false)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill1(false)
                end
            end
        end
    end
end

function M:IA_Skill_Started()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill2(true)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill2(true)
                end
            end
        end
    end
end

function M:IA_Skill_Completed()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill2(false)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill2(false)
                end
            end
        end
    end
end

function M:IA_Ultimate_Started()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill3(true)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill3(true)
                end
            end
        end
    end
end

function M:IA_Ultimate_Completed()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill3(false)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill3(false)
                end
            end
        end
    end
end

function M:IA_Ultimate_Started()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill3(true)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill3(true)
                end
            end
        end
    end
end

function M:IA_Ultimate_Completed()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill3(false)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill3(false)
                end
            end
        end
    end
end

function M:IA_Step_Started()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill4(true)
            LOG_DEBUG("Step")
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill4(true)
                end
            end
        end
    end
end

function M:IA_Step_Completed()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() then
        ---@type BP_PlayerCharacter_Fight_C
        local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
        if UE.UKismetSystemLibrary.IsValid(pawn) then
            pawn:OnInputActionSkill4(false)
            ---@param actor BP_XieTongActor_Fight_C
            for _, actor in pairs(self.XieTongActor) do
                if UE.UKismetSystemLibrary.IsValid(actor) then
                    actor:OnInputActionSkill4(false)
                end
            end
        end
    end
end

-- TODO 传TagContainer干啥，似乎单Tag就够用了

function M:IA_ShipSkill()
    if self.IsAnyCharcterPlayingSequence then
        return
    end

    if self.UIFight:IsVisible() and self.UIFight.UI_SkillButton5:IsVisible() then
        local tag = UE.UGHSFunctionLibrary.RequestGameplayTag("Ability.Skill.Boat", false)
        local tagContainer = UE.UBlueprintGameplayTagLibrary.MakeGameplayTagContainerFromTag(tag)
        self.Boat:DoSkill(tagContainer, false)
    end
end

function M:IA_NextCharacter()
    local tag = UE.UGHSFunctionLibrary.RequestGameplayTag("Ability.Skill.3", false)
    local tagContainer = UE.UBlueprintGameplayTagLibrary.MakeGameplayTagContainerFromTag(tag)

    
    ---@type BP_PlayerCharacter_Fight_C
    local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
    if pawn:IsUsingSkill(tagContainer) then
        return
    end

    self.UIFight:OnUpdateHeadOffset()

    if math.abs(self.SwitchPlayerCD) <= 0.000001 then
        self.UIFight:ChangePlayer(10)
    else
        self.UIFight:PlayAnimation(self.UIFight.HeadWave_SwitchLock, 0, 1, UE.EUMGSequencePlayMode.Forward, 1.0, false)
    end

    self.UIFight.UI_TouchPad_ChangePlayer.TouchDown = false
    self.UIFight.HeadOffsetUpdate = true
end

function M:IA_PrevCharacter()
    local tag = UE.UGHSFunctionLibrary.RequestGameplayTag("Ability.Skill.3", false)
    local tagContainer = UE.UBlueprintGameplayTagLibrary.MakeGameplayTagContainerFromTag(tag)

    
    ---@type BP_PlayerCharacter_Fight_C
    local pawn = UE.UGameplayStatics.GetPlayerCharacter(self, 0)
    if pawn:IsUsingSkill(tagContainer) then
        return
    end

    self.UIFight:OnUpdateHeadOffset()

    if math.abs(self.SwitchPlayerCD) <= 0.000001 then
        self.UIFight:ChangePlayer(-10)
    else
        self.UIFight:PlayAnimation(self.UIFight.HeadWave_SwitchLock, 0, 1, UE.EUMGSequencePlayMode.Forward, 1.0, false)
    end

    self.UIFight.UI_TouchPad_ChangePlayer.TouchDown = false
    self.UIFight.HeadOffsetUpdate = true
end

-- 以后手机拖动可能要用
function M:HorizontalAxis(value)
    local pawn = self:K2_GetPawn()
    if not UE.UKismetSystemLibrary.IsValid(pawn) then
        return
    end
    pawn:AddControllerYawInput(self.TurnRate * value)

    if math.abs(value) > 0.5 and self.ChangeLockTragetAxisPreValue <= 0.5 then
        self:ChangeLockTarget(value * 10)
    end

    self.ChangeLockTragetAxisPreValue = value
end

function M:IA_NextTarget()
    self:ChangeLockTarget(10)
end

function M:IA_PrevTarget()
    self:ChangeLockTarget(-10)
end

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

    if math.abs(input.X) > 0.5 and math.abs(self.ChangeLockTragetAxisPreValue) <= 0.5 then
        self:ChangeLockTarget(input.X * 10)
    end

    self.ChangeLockTragetAxisPreValue = input.X
end

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_Move(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    if self.bShowMouseCursor then
        return
    end

    local input = ActionValue:GetAxis2D()

    local cameraRotation = UE.UGameplayStatics.GetPlayerCameraManager(self, 0):GetCameraRotation()
    local moveDirection = cameraRotation:RotateVector(input)

    moveDirection:Normalize()

    local pawn = self:K2_GetPawn()

    if not pawn then
        return
    end
    pawn:AddMovementInput(moveDirection, 1.0, false)
end

function M:IA_Pause()
    self.UIFight:Pause()
end

function M:ShowCursor()
    UIManager:GetInstance():SetForceShowCursor(true)
end

function M:HideCursor()
    UIManager:GetInstance():SetForceShowCursor(false)
end

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_NormalAttack, UE.ETriggerEvent.Triggered, M.IA_NormalAttack_Started)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_NormalAttack, UE.ETriggerEvent.Completed, M.IA_NormalAttack_Completed)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Skill, UE.ETriggerEvent.Triggered, M.IA_Skill_Started)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Skill, UE.ETriggerEvent.Completed, M.IA_Skill_Completed)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Ultimate, UE.ETriggerEvent.Triggered, M.IA_Ultimate_Started)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Ultimate, UE.ETriggerEvent.Completed, M.IA_Ultimate_Completed)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Step, UE.ETriggerEvent.Triggered, M.IA_Step_Started)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Step, UE.ETriggerEvent.Completed, M.IA_Step_Completed)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_ShipSkill, UE.ETriggerEvent.Started, M.IA_ShipSkill)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_NextCharacter, UE.ETriggerEvent.Started, M.IA_NextCharacter)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_PrevCharacter, UE.ETriggerEvent.Started, M.IA_PrevCharacter)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_NextTarget, UE.ETriggerEvent.Started, M.IA_NextTarget)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_PrevTarget, UE.ETriggerEvent.Completed, M.IA_PrevTarget)

if UIUtils.IsAndroidOrIOS() then
    UnLua.EnhancedInput.BindAction(M, InputAssets.IA_MoveCamera, UE.ETriggerEvent.Triggered, M.IA_MoveCamera)
end

-- UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Move, UE.ETriggerEvent.Triggered, M.IA_Move)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Pause, UE.ETriggerEvent.Completed, M.IA_Pause)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_ShowCursor, UE.ETriggerEvent.Started, M.ShowCursor)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_ShowCursor, UE.ETriggerEvent.Completed, M.HideCursor)


UnLua.EnhancedInput.BindActionValue(M, InputAssets.IA_Move)

function M:SetUpInput()
    ---@type APlayerController
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)

    InputUtils.AddMappingContext(PC, InputAssets.IMC_Common)
    InputUtils.AddMappingContext(PC, InputAssets.IMC_Move)
    InputUtils.AddMappingContext(PC, InputAssets.IMC_Fight)
    InputUtils.RegisterAllMappingContext(PC)

    PC.bShowMouseCursor = false
end

function M:ReceiveBeginPlay()
    self:SetUpInput()

    UIManager:GetInstance():OnBeginPlay(self)
    UIManager:GetInstance():ShowWaterMask(self)

    MessageManager:GetInstance():RemoveListener("res_login", self)
    self.Overridden.ReceiveBeginPlay(self)
end

function M:ReceiveEndPlay(EndPlayReason)
    self.Overridden.ReceiveEndPlay(self, EndPlayReason)
    UIManager:GetInstance():OnEndPlay()
end

function M:OpenLevelSequence()
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    print("===OpenLevelSequence")
    self.UILoading = gameInstance:AddUMG("UI_Loading", nil, 1)
    coroutine.resume(coroutine.create(function()
        UE.UKismetSystemLibrary.Delay(self, 0.2)
        gameMode.BP_Preload:PreloadAssets()
    end))
end

function M:InitUI()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    self.UIFight = gameInstance:AddUMG("UI_Fight")
    self.UIFight:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:OnShowUISettings()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    ---@type UI_SetSystem_C
    local ui = gameInstance:GetUMG("UI_SetSystem")
    if ui then
        ui:SetVisibility(UE.ESlateVisibility.Visible)
    else
        ui = gameInstance:AddUMG("UI_SetSystem")
    end
end

function M:RemoveUILoading()
    if self.UILoading then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:RemoveUMG("UI_Loading")
        self.UILoading = nil
    end
end

function M:OnCurrentLevelOpenFinished()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- 直接打开的FightMap
    if not gameInstance.resUniverse and USE_TEST_CONFIG then
        gameInstance.testFightMap = true

        for tableName, content in pairs(FightTestConfig.overrides) do
            local table = require(tableName)
            for key, value in pairs(content) do
                table[key] = value
            end
        end

        MessageManager:GetInstance():AddListener("res_login", self)
        gameInstance:LuaLogin(FightTestConfig.username, FightTestConfig.password, gameInstance:GetDeviceId())
    else
        self.Overridden.OnCurrentLevelOpenFinished(self)
    end
end

function M:res_login(result, msgId, parsed_msg)
    self.Overridden.OnCurrentLevelOpenFinished(self)
end

return M
