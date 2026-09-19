--
-- DESCRIPTION
--


-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "Global"
require "UnLua"

--角色模型配置表
local TeamRoleConfig = require "ClientDatas.d_role_team_config"
local RoleModelConfig = require "ClientDatas.d_role_team_model"
local Database = require "_Game.Utils.Database"
local UIUtils = require "_Game.Utils.UIUtils"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local chairMeshPath = "SkeletalMesh'/Game/_Game/3DRES/scene/warship/chair.chair'"


---@type BP_PlayerController_City_UniverseBridge_C
local M = Class()

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_MoveCamera(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    -- if self.BlockInputAction then
    --     print("----------------------blockInput")
    --     return
    -- end

    ---@type APlayerController
    local PC = self:GetOwner()

    if PC.bShowMouseCursor then
        return
    end

    local pawn = PC:K2_GetPawn()

    if not pawn then
        return
    end

    local input = ActionValue:GetAxis2D()
    -- if self.LimitPitch and self:LimitPitch(UE.FVector(input.X, input.Y, 0)) then
    --     return
    -- end

    if pawn.Input_CameraMove then
        pawn:Input_CameraMove(input, InputAction)
    else
        ---@type BP_GameInstance_C
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local cameraSensitive = gameInstance:LoadSaveGameSettings().GameCameraSensitivity
        pawn:AddControllerPitchInput(input.Y * self.LookUpRate * cameraSensitive)
        pawn:AddControllerYawInput(input.X * self.TurnRate * cameraSensitive)
    end
    if pawn.CheckSpringCamera then
        pawn:CheckSpringCamera()
    end
end

function M:IA_Scale_Triggered(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    -- if self.BlockInputAction then
    --     return
    -- end

    ---@type APlayerController
    local PC = self:GetOwner()

    if PC.bShowMouseCursor then
        return
    end

    local pawn = PC:K2_GetPawn()

    if not pawn then
        return
    end

    local scale = ActionValue:GetAxis1D()
    if pawn.LimitScale then
        local scaleValue = self.ScaleRate * scale * UE.UGameplayStatics.GetWorldDeltaSeconds(self)
        if not pawn:LimitScale(scaleValue) then
            return
        end
    end
    self:AddScale(self.ScaleRate * scale)
    -- if self.LimitPitch and not self:LimitPitch(UE.FVector(0, scale, 0)) then
    --     self:AddScale(self.ScaleRate * scale)
    -- end
end

-- TODO 自己移到lua这边来

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_Jump_Start(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    self:Jump()
end

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_Jump_Complete(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    self:StopJumping()
end

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_ToggleSprint(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    -- TODO 这东西明显应该移到这边来吧

    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    gameInstance:ToggleWalk()
end

-- TODO 蓝图里的逻辑我很确定就长这样，名字还打错了

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_DashSkill_Start(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    if self.BlockSpecialSkill then return end
    if not self.VehicleSkill then
        self:Dash()
    end

    if self.VehicleSkill then
        self:Dash()
    end
end

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_DashSkill_Complete(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    if self.BlockSpecialSkill then return end
    self:VehicelSkill()
end

function M:ShowCursor()
    UIManager:GetInstance():SetForceShowCursor(true)
end

function M:HideCursor()
    UIManager:GetInstance():SetForceShowCursor(false)
end

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_MoveCamera, UE.ETriggerEvent.Triggered, M.IA_MoveCamera)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Scale, UE.ETriggerEvent.Triggered, M.IA_Scale_Triggered)

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Jump, UE.ETriggerEvent.Started, M.IA_Jump_Start)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Jump, UE.ETriggerEvent.Completed, M.IA_Jump_Complete)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_ToggleSprint, UE.ETriggerEvent.Completed, M.IA_ToggleSprint)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_DashSkill, UE.ETriggerEvent.Started, M.IA_DashSkill_Start)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_DashSkill, UE.ETriggerEvent.Completed, M.IA_DashSkill_Complete)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_ShowCursor, UE.ETriggerEvent.Started, M.ShowCursor)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_ShowCursor, UE.ETriggerEvent.Completed, M.HideCursor)

UnLua.EnhancedInput.BindActionValue(M, InputAssets.IA_Move)

function M:Initialize()
    self.SequenceActor = {}
    self.ActorList = {}

    self.AllCachedSequenceActor = {}
    self.AllCachedSkeletonActor = {}

    self.DefaultChairList = {}

    self.CachedRoleList = {}
end

function M:SetUpInput()
    ---@type APlayerController
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)

    InputUtils.AddMappingContext(PC, InputAssets.IMC_Common)
    InputUtils.AddMappingContext(PC, InputAssets.IMC_Move)
    InputUtils.AddMappingContext(PC, InputAssets.IMC_Character)
    InputUtils.RegisterAllMappingContext(PC)

    PC.bShowMouseCursor = false
end

function M:ReceiveBeginPlay()
    self:SetUpInput()
    
    self.Overridden.ReceiveBeginPlay(self)
    UIManager:GetInstance():OnBeginPlay(self)
    UIManager:GetInstance():ShowWaterMask(self)
    print('--------------->city_univers.beginplay')
end

function M:ReceiveEndPlay()
    UIManager:GetInstance():OnEndPlay()
end

function M:ReceiveTick(DeltaTime)
    self.Overridden.ReceiveTick(self, DeltaTime)

    if self.bCanMove then
        self.passTime = self.passTime + DeltaTime
        -- local rot = self.EndRotator - self.MoveCameraObj:K2_GetActorRotation()
        -- if UE.UKismetMathLibrary.Vector_IsNearlyZero() then
        --     local InterpRot = UE.UKismetMathLibrary.RInterpTo(self.MoveCameraObj:K2_GetActorRotation(), self.EndRotator, DeltaTime, 5)
        --     self.MoveCameraObj:K2_SetActorRotation(InterpRot, false)
        -- else
        --     --print("=====move end:")
        --     self.bCanMove = false
        -- end
        if self.passTime <= self.RotationTime then
            local alpha = self.passTime / self.RotationTime
            local rot = UE.UKismetMathLibrary.RLerp(self.StartRotator, self.EndRotator, alpha, true)
            --print("===rot:" .. tostring(rot))
            self.MoveCameraObj:K2_SetActorRotation(rot, false)

           

            --print("===pos:" .. tostring(pos))
            --local InterpRot = UE.UKismetMathLibrary.RInterpTo(self.MoveCameraObj:K2_GetActorRotation(), self.EndRotator, DeltaTime, 5)
            --self.MoveCameraObj:K2_SetActorRotation(InterpRot, false)

            local pos = UE.UKismetMathLibrary.TransformLocation(self.SplineComponent:GetTransformAtTime(alpha, UE.ESplineCoordinateSpace.World, false, false), nil)
            self.MoveCameraObj:K2_SetActorLocation(pos, false, nil, false)
        else
            --print("=====move end:")
            self.bCanMove = false
        end
    end
end

function M:ClearAllCacheActors()
    self.CurBindingTag = nil
    self.CurBindingActor = nil

    -- if self.DefaultChairList then
    --     for _, chairActor in pairs(self.DefaultChairList) do
    --         chairActor:K2_DestroyActor()
    --     end
    -- end
    --self.DefaultChairList = {}

    if self.SequenceActor then
        for _, sequenceActor in pairs(self.SequenceActor) do 
            sequenceActor:K2_DestroyActor()
        end
    end
    self.SequenceActor = {}

    if self.ActorList then
        for _, actorList in pairs(self.ActorList) do
            for _, actor in pairs(actorList) do 
                actor:K2_DestroyActor()
            end
        end
    end
    self.ActorList = {}

    if self.AllCachedSequenceActor then
        for _, actor in pairs(self.AllCachedSequenceActor) do 
            actor:K2_DestroyActor()
        end
    end
    self.AllCachedSequenceActor = {}

    if self.AllCachedSkeletonActor then
        for _, actorList in pairs(self.AllCachedSkeletonActor) do 
            for _, actor in pairs(actorList) do 
                actor:K2_DestroyActor()
            end
        end
    end

    self.AllCachedSkeletonActor = {}

    if self.FlySequenceActor then
        self.FlySequenceActor:K2_DestroyActor()
        self.FlySequenceActor = nil
    end

    self.CachedRoleList = {}

    if self.ChangeRoleCameraTimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.ChangeRoleCameraTimerHandle)
        self.ChangeRoleCameraTimerHandle = nil
    end

    if self.TeamModelTimerHander1 then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TeamModelTimerHander1)
        self.TeamModelTimerHander1 = nil
    end
    if self.TeamModelTimerHander2 then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TeamModelTimerHander2)
        self.TeamModelTimerHander2 = nil
    end
    if self.TeamModelTimerHander3 then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TeamModelTimerHander3)
        self.TeamModelTimerHander3 = nil
    end
end

function M:LoadFight()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:AddUMG("UI_Loading", nil, 1)
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    local function OnFadeInFinished()
        PC.BP_ScreenFade.OnFadeInFinished:Remove(self, OnFadeInFinished)
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.3)
            self.Overridden.LoadFight(self)
        end))
    end
    PC.BP_ScreenFade.OnFadeInFinished:Add(self, OnFadeInFinished)
    PC.BP_ScreenFade:FadeIn(false, true)
    PC:DisableInput()
end

function M:FastLoadFight()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:AddUMG("UI_Loading", nil, 1)
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    local function OnFadeInFinished()
        PC.BP_ScreenFade.OnFadeInFinished:Remove(self, OnFadeInFinished)
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.3)
            self.Overridden.FastLoadFight(self)
        end))
    end
    PC.BP_ScreenFade.OnFadeInFinished:Add(self, OnFadeInFinished)
    PC.BP_ScreenFade:FadeIn(false, true)
    PC:DisableInput()
end

function M:OnLoadFight()
    if self.FlySequenceActor then
        self.FlySequenceActor:K2_DestroyActor()
        self.FlySequenceActor = nil
    end
    -- local gameMode = UE.UGameplayStatics.GetGameMode(self)
    -- local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- if pc then
    --     local player = pc:K2_GetPawn()
    --     if player then
    --         gameMode:BPI_SetPlayer(player)
    --         gameInstance.PlayerInCity = player:GetTransform()
    --     end
    -- end
end

function M:CacheAllActor()
    if self.SequenceActor then
        for _, sequenceActor in pairs(self.SequenceActor) do
            sequenceActor.SequencePlayer:Pause()
            sequenceActor:ResetBindings()
            sequenceActor:SetActorHiddenInGame(true)
            local pathName = UE.UKismetSystemLibrary.GetPathName(sequenceActor.SequencePlayer:GetSequence())
            self.AllCachedSequenceActor[pathName] = sequenceActor
        end
    end
    self.SequenceActor = {}
    if self.ActorList then
        for _, actorList in pairs(self.ActorList) do
            for _, actor in pairs(actorList) do 
                actor:K2_DetachFromActor()
                --actor:SetActorHiddenInGame(true)
                actor:SetActorScale3D(UE.FVector(0.01, 0.01, 0.01))
                local pathName = UE.UKismetSystemLibrary.GetPathName(actor.SkeletalMeshComponent.SkeletalMesh)
                if not self.AllCachedSkeletonActor[pathName] then 
                    self.AllCachedSkeletonActor[pathName] = {}
                end
                table.insert(self.AllCachedSkeletonActor[pathName], actor)
            end
        end
    end
    self.ActorList = {}
end

function M:CachePartyActor(index)
    --print("===CachePartyActor:" .. tostring(index))
    if self.SequenceActor then
        for idx, sequenceActor in pairs(self.SequenceActor) do
            if idx == index then
                sequenceActor.SequencePlayer:Pause()
                sequenceActor:ResetBindings()
                sequenceActor:SetActorHiddenInGame(true)
                --sequenceActor:SetActorEnableCollision(false)
                local pathName = UE.UKismetSystemLibrary.GetPathName(sequenceActor.SequencePlayer:GetSequence())
                self.AllCachedSequenceActor[pathName] = sequenceActor
                break
            end
        end
    end
    if self.ActorList then
        for idx, actorList in pairs(self.ActorList) do
            if idx == index then
                for _, actor in pairs(actorList) do
                    actor:K2_DetachFromActor()
                    --actor:SetActorHiddenInGame(true)
                    actor:SetActorScale3D(UE.FVector(0.01, 0.01, 0.01))
                    --actor:SetActorEnableCollision(false)
                    local pathName = UE.UKismetSystemLibrary.GetPathName(actor.SkeletalMeshComponent.SkeletalMesh)
                    if not self.AllCachedSkeletonActor[pathName] then 
                        self.AllCachedSkeletonActor[pathName] = {}
                    end
                    local lowerPathName = string.lower(pathName)
                    local str_start, str_end = string.find(lowerPathName, "hair")
                    if str_start and str_end then
                        actor.SkeletalMeshComponent.BodyInstance.CollisionEnabled = 0
                        actor.SkeletalMeshComponent.BodyInstance.bSimulatePhysics = false
                        actor.SkeletalMeshComponent:SetSimulatePhysics(false)
                    end
                    table.insert(self.AllCachedSkeletonActor[pathName], actor)
                end
            end
        end
    end
end

function M:GetFromAllCachedSequenceActor(path)
    local cachedActor = nil
    for resPath, v in pairs(self.AllCachedSequenceActor) do
        local startIndex, _, _ = string.find(path, resPath)
        if startIndex then
            cachedActor = v
            self.AllCachedSequenceActor[resPath] = nil
            break
        end
    end
    
    if nil == cachedActor then
        local levelSequence = LoadObject(path)
        if not levelSequence then
            print("====>Load path:" .. tostring(path) .. "   failed!!!!")
            return nil
        end
        -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
        print("--------------------->GetFromAllCachedSequenceActor:" .. tostring(path))
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = -1
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
        cachedActor = levelSequenceActor
    end
    -- cachedActor:SetActorHiddenInGame(false)
    --cachedActor:SetActorEnableCollision(true)
   
    return cachedActor
end

function M:GetFromAllCachedSkeletonActor(path, isMainBody, charId)
    LOG_INFO_TRACKBACK('---path:' .. tostring(path))
    local cachedActor = nil
    for resPath, actorList in pairs(self.AllCachedSkeletonActor) do
        LOG_INFO(resPath)
        local startIndex, _, _ = string.find(path, resPath)
        if startIndex then
            for id, obj in pairs(actorList) do 
                if obj then
                    cachedActor = obj
                    self.AllCachedSkeletonActor[resPath][id] = nil
                    break
                end
            end
            break
        end
    end
    if nil == cachedActor then
        local skeletonActor = self:GetWorld():SpawnActor(UE.LoadClass("Class '/Script/Engine.SkeletalMeshActor'"))
        local obj = LoadObject(path)
        if not obj then
            LOG_ERROR('--------->load mesh path failed:' .. tostring(path))
        end
        skeletonActor.SkeletalMeshComponent:SetSkeletalMeshAsset(obj, false)
        cachedActor = skeletonActor
        if isMainBody then
            -- print('--------------create char:' .. tostring(charId)) 
           
        end
    else
        --cachedActor:SetActorScale3D(UE.FVector(1, 1, 1))
    end
    --cachedActor.RootComponent:K2_SetRelativeTransform(UE.UKismetMathLibrary.MakeTransform(UE.FVector(0, 0, 0), UE.FRotator(0, 0, 0), UE.FVector(1, 1, 1)), false, nil, false)
    --cachedActor:SetActorHiddenInGame(false)
    --cachedActor:SetActorEnableCollision(true)
    return cachedActor
end

function M:OnTeamModelTimerEnd1()
    local cameraRole = self.CachedRoleList[self.CacheCameraIndex]
    self:ChangeRoleCamera(self.CacheCameraIndex, false, cameraRole)

    local roleId = self.CachedRoleList[1]
    self:ShowModelSingle(1, roleId)
end

function M:OnTeamModelTimerEnd2()
    local cameraRole = self.CachedRoleList[self.CacheCameraIndex]
    self:ChangeRoleCamera(self.CacheCameraIndex, false, cameraRole)

    local roleId = self.CachedRoleList[2]
    self:ShowModelSingle(2, roleId)
end

function M:OnTeamModelTimerEnd3()
    local cameraRole = self.CachedRoleList[self.CacheCameraIndex]
    self:ChangeRoleCamera(self.CacheCameraIndex, false, cameraRole)

    local roleId = self.CachedRoleList[3]
    self:ShowModelSingle(3, roleId)
end

function M:ShowModelSingle(index, roleId)
    --切人之前,特效+隐藏角色
    local touchActor = self.DefaultChairList[index]
    if touchActor then
        touchActor.EF_ChangePlayer:SetHiddenInGame(true)
        touchActor.EF_ChangePlayer:ResetSystem()
        touchActor.EF_ChangePlayer:SetHiddenInGame(false)
    end
    self:OnTeamCreateCharacter(roleId)
    print("====ShowModelSingle.index:" .. tostring(index) .. ",roleId:" .. tostring(roleId))
    self:ShowModelInneral(index, TeamRoleConfig[roleId])
end

function M:ShowTeamModel(roleList)
    --print("====ShowTeamModel.cachedRoleList:" .. tostring(table.dump(self.CachedRoleList)))
    --print("====ShowTeamModel.roleList:" .. tostring(table.dump(roleList)))

    self:ChangeRoleCamera(0)
   
    for index, roleId in pairs(roleList) do
        local oldRoleId = self.CachedRoleList[index] or 0
        if (roleId ~= 0 or oldRoleId ~= 0) and roleId ~= oldRoleId then
            self:CachePartyActor(index)
        end
    end
    --self:CacheAllActor(roleList)
    for index, roleId in pairs(roleList) do
        local oldRoleId = self.CachedRoleList[index] or 0
        if (roleId ~= 0 or oldRoleId ~= 0) and roleId ~= oldRoleId then
            local configData = TeamRoleConfig[roleId]
            if configData then
                self:ShowDefaultChair(index, configData.chair == 0, roleId, false)
                self:ShowModelInneral(index, configData)
            else
                self:ShowDefaultChair(index, true, roleId)
            end
        else
            local configData = TeamRoleConfig[roleId]
            if configData then
                self:ShowDefaultChair(index, configData.chair == 0, roleId, false)
            else
                self:ShowDefaultChair(index, true, roleId)
            end
        end
    end
    --缓存当前的角色列表
    --self.CachedRoleList = roleList
    for index, roleId in pairs(roleList) do
        self.CachedRoleList[index] = roleId
    end
    self.bIsFirstEnter = false
end

function M:DoDelayTimeStart()
    self.OnDoDelayTimeStart:Broadcast(self)
end

function M:DoDelayTimeEnd()
    self.OnDoDelayTimeEnd:Broadcast(self)
end

function M:ShowAllTeamModel(roleList)
    --print("===ShowAllTeamModl:" .. tostring(table.dump(self.CachedRoleList)))
    --print("===roleList:" .. tostring(table.dump(roleList)))
    for index, roleId in pairs(roleList) do 
        local oldRoleId = self.CachedRoleList[index] or 0
        --print("===oldRole:" .. tostring(oldRoleId) .. ", roleId:" .. tostring(roleId))
        if oldRoleId ~= 0 then
            --切人之前,特效+隐藏角色
            -- local touchActor = self.DefaultChairList[index]
            -- if touchActor then
            --     touchActor.EF_ChangePlayer:SetHiddenInGame(true)
            --     touchActor.EF_ChangePlayer:ResetSystem()
            --     touchActor.EF_ChangePlayer:SetHiddenInGame(false)
            -- end
            self:CachePartyActor(index)
        end
    end

    self.CacheCameraIndex = 0
  
    local doDelayTimer = false
    for index, roleId in pairs(roleList) do
        --旧角色
        local oldRoleId = self.CachedRoleList[index] or 0
        local oldRoleConfig = TeamRoleConfig[oldRoleId]
        --新角色
        local configData = TeamRoleConfig[roleId]
        if oldRoleId == 0 and roleId ~= 0 then
            if configData then
                self:ShowDefaultChair(index, configData.chair == 0, roleId, configData.chair == 1)
                -- if configData.chair == 1 then
                    self:SelectTeamModelTimerEx(index, true)
                -- else
                --     self:ShowModelSingle(index, roleId)
                -- end
            end
        else
            if roleId == 0 then
                if oldRoleConfig then
                    self:ShowDefaultChair(index, true, roleId, oldRoleConfig.chair == 1)
                else
                    self:ShowDefaultChair(index, true, roleId, false)
                end
            else
                if configData and oldRoleConfig then
                    doDelayTimer = true
                    local showEffect = (oldRoleConfig.chair == 1 and configData.chair == 0) or ( oldRoleConfig.chair == 0 and configData.chair == 1)
                    self:ShowDefaultChair(index, configData.chair == 0, roleId, showEffect)
                    self:SelectTeamModelTimerEx(index, true)
                end
            end
        end
    end
    for index, roleId in pairs(roleList) do
        self.CachedRoleList[index] = roleId
    end

    if doDelayTimer then
        self:DoDelayTimeStart()
        self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            {self, self.DoDelayTimeEnd}, 
            self.ChangePlayerWaitTime, 
            false
        )
    end
end

function M:SelectTeamModelTimerEx(index)
    --定时器
    if index == 1 then
        self.TeamModelTimerHander1 = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            {self, self.OnTeamModelTimerEnd1}, 
            0.4, 
            false
        )
    elseif index == 2 then
        self.TeamModelTimerHander2 = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            {self, self.OnTeamModelTimerEnd2}, 
            0.2, 
            false
        )
    else 
        self.TeamModelTimerHander3 = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            {self, self.OnTeamModelTimerEnd3}, 
            0.3, 
            false
        )
    end
end

function M:SelectTeamModelTimer(index)
    --定时器
    if index == 1 then
        self.TeamModelTimerHander1 = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            {self, self.OnTeamModelTimerEnd1}, 
            self.ChangePlayerWaitTime, 
            false
        )
    elseif index == 2 then
        self.TeamModelTimerHander2 = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            {self, self.OnTeamModelTimerEnd2}, 
            self.ChangePlayerWaitTime, 
            false
        )
    else 
        self.TeamModelTimerHander3 = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            {self, self.OnTeamModelTimerEnd3}, 
            self.ChangePlayerWaitTime, 
            false
        )
    end
end

function M:SwapTeamModel(cameraIndex, roleList, bForceCameraFocus)
    -- print("====SwapTeamModel.cachedRoleList:" .. tostring(table.dump(self.CachedRoleList)))
    -- print("====SwapTeamModel.roleList:" .. tostring(table.dump(roleList)))
    for index, roleId in pairs(roleList) do 
        local oldRoleId = self.CachedRoleList[index] or 0
        --print("===oldRole:" .. tostring(oldRoleId) .. ", roleId:" .. tostring(roleId))
        if oldRoleId ~= 0 and oldRoleId ~= roleId then
            --if roleId ~= 0 then
                --切人之前,特效+隐藏角色
                local touchActor = self.DefaultChairList[index]
                if touchActor then
                    touchActor.EF_ChangePlayer:SetHiddenInGame(true)
                    touchActor.EF_ChangePlayer:ResetSystem()
                    touchActor.EF_ChangePlayer:SetHiddenInGame(false)
                end
            --end
           
            self:CachePartyActor(index)
        end
    end

    self.CacheCameraIndex = cameraIndex
  
    local doDelayTimer = false
    for index, roleId in pairs(roleList) do
        --旧角色
        local oldRoleId = self.CachedRoleList[index] or 0
        local oldRoleConfig = TeamRoleConfig[oldRoleId]
        --新角色
        local configData = TeamRoleConfig[roleId]
        -- print("===newRoleId:" .. tostring(roleId) .. ",oldRoleId:" .. tostring(oldRoleId))
        if oldRoleId == 0 and roleId == 0 then
        elseif oldRoleId == 0 and roleId ~= 0 then
            if configData then
                self:ShowDefaultChair(index, configData.chair == 0, roleId, configData.chair == 1)
                if configData.chair == 1 then
                    self:SelectTeamModelTimer(index, true)
                else
                    if bForceCameraFocus then
                        self:ChangeRoleCamera(self.CacheCameraIndex, false, roleId)
                    end
                    self:ShowModelSingle(index, roleId)
                end
            end
        elseif oldRoleId ~= 0 and roleId == 0 then
            if oldRoleConfig then
                self:ShowDefaultChair(index, true, roleId, oldRoleConfig.chair == 1)
            end
        elseif oldRoleId ~= 0 and roleId ~= 0 and oldRoleId == roleId then
        elseif oldRoleId ~= 0 and roleId ~= 0 and oldRoleId ~= roleId then
            if configData and oldRoleConfig then
                doDelayTimer = true
                local showEffect = (oldRoleConfig.chair == 1 and configData.chair == 0) or ( oldRoleConfig.chair == 0 and configData.chair == 1)
                self:ShowDefaultChair(index, configData.chair == 0, roleId, showEffect)
                self:SelectTeamModelTimer(index, true)
            end
        end
    end
    --self.CachedRoleList = roleList
    for index, roleId in pairs(roleList) do
        self.CachedRoleList[index] = roleId
    end

    if doDelayTimer then
        self:DoDelayTimeStart()
        self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            {self, self.DoDelayTimeEnd}, 
            self.ChangePlayerWaitTime, 
            false
        )
    end
end

function M:GetMaterialPath(modelList, tag)
    for k, v in pairs(modelList) do
        local modelConfig = RoleModelConfig[v]
        if modelConfig and modelConfig.tag == tag then
            return modelConfig.spherePath
        end
    end
    return ''
end

function M:ShowModelInneral(index, config)
    print("===ShowModelInneral:" .. tostring(table.dump(config, nil, 10)))
    --动画播放器对象
    local SequencePath = config["sequencePath" .. index]
    local LoopCount = -1
    local modelList = config["modelList" .. index]
    
    if not SequencePath or SequencePath == "" then
        print("====config[" .. tostring(config.id) .. "] SequencePath is nil or empty!!!")
        return
    end
    --解析SequencePath
    local strArr = string.split(SequencePath, '/')
    local seqPath = string.format("LevelSequence'/Game/_Game/Characters/%s/Animation/perform/%s.%s'", strArr[1], strArr[2], strArr[2])
    --加载sequence
    local sequenceActor = self:GetFromAllCachedSequenceActor(seqPath)
    if not sequenceActor then
        return
    end
    self.SequenceActor[index] = sequenceActor
    --self.SequenceActor[index].RootComponent:K2_SetWorldLocation(UE.FVector(0, 0, -5000), false, nil, false)
    --self.SequenceActor[index].SequencePlayer:PlayLooping(LoopCount)

    self.ActorList[index] = {}

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.bEnableClickEvents = true

    --角色皮肤
    local _, _, saveCitySkinId, _, _, defaultCitySkinId = UIUtils.GetIdolAndCharMeshByCharacterId(config.id)
    local skinId = defaultCitySkinId
    if saveCitySkinId ~= defaultCitySkinId then
        skinId = saveCitySkinId
    end
    local clothesConfig = Database.Query("d_char_clothes", skinId)
    --身体
    if clothesConfig and config.modelF ~= '' then
        local newMesh = LoadObject(clothesConfig.modelF)
        if newMesh then
            local skeletonActor = self:GetFromAllCachedSkeletonActor(clothesConfig.modelF, true, config.id)
            if skeletonActor.SetLightingChannels then
                skeletonActor:SetLightingChannels(false, true, false)
            else
                skeletonActor.SkeletalMeshComponent:SetLightingChannels(false, true, false)
                -- skeletonActor.SkeletalMeshComponent:SetBoundsScale(10)
            end
            
            --获取勾线路径
            -- local outlinePath = self:GetMaterialPath(modelList, 'MainObj')
            -- if outlinePath ~= '' then
            --     local materail = LoadObject(outlinePath)
            --     if materail then
            --         skeletonActor.SkeletalMeshComponent.SecondPassMaterial = materail
                     skeletonActor.SkeletalMeshComponent.NeedSecondPass = true
            --     end
            -- end
            self.SequenceActor[index]:AddBindingByTag('MainObj', skeletonActor, true)
            table.insert(self.ActorList[index], skeletonActor)
        end
    end
    --头发
    if clothesConfig and clothesConfig.modelHair ~= '' then
        local skeletonActor = self:GetFromAllCachedSkeletonActor(clothesConfig.modelHair)
        if skeletonActor.SetLightingChannels then
            skeletonActor:SetLightingChannels(false, true, false)
        else
            skeletonActor.SkeletalMeshComponent:SetLightingChannels(false, true, false)
        end
        --获取勾线路径
        -- local outlinePath = self:GetMaterialPath(modelList, 'HairObj')
        -- if outlinePath ~= '' then
        --     local materail = LoadObject(outlinePath)
        --     if materail then
        --         skeletonActor.SkeletalMeshComponent.SecondPassMaterial = materail
                 skeletonActor.SkeletalMeshComponent.NeedSecondPass = true
        --     end
        -- end
        self.SequenceActor[index]:AddBindingByTag('HairObj', skeletonActor, true)
        table.insert(self.ActorList[index], skeletonActor)
    end
    --脸
    if clothesConfig and clothesConfig.modelFace ~= '' then
        local skeletonActor = self:GetFromAllCachedSkeletonActor(clothesConfig.modelFace)
        if skeletonActor.SetLightingChannels then
            skeletonActor:SetLightingChannels(false, true, false)
        else
            skeletonActor.SkeletalMeshComponent:SetLightingChannels(false, true, false)
        end
        --获取勾线路径
        local outlinePath = self:GetMaterialPath(modelList, 'FaceObj')
        if outlinePath ~= '' then
            local materail = LoadObject(outlinePath)
            if materail then
                skeletonActor.SkeletalMeshComponent.SecondPassMaterial = materail
                skeletonActor.SkeletalMeshComponent.NeedSecondPass = true
            end
        end
        self.SequenceActor[index]:AddBindingByTag('FaceObj', skeletonActor, true)
        table.insert(self.ActorList[index], skeletonActor)
    end

    --小物件
    for k, v in pairs(modelList) do
        local modelConfig = RoleModelConfig[v]
        if modelConfig and modelConfig.tag ~= 'MainObj' and modelConfig.tag ~= 'HairObj' and modelConfig.tag ~= 'FaceObj' then
            if modelConfig.skeletonMeshPath ~= "" then
                local skeletonActor = self:GetFromAllCachedSkeletonActor(modelConfig.skeletonMeshPath)
                if skeletonActor.SetLightingChannels then
                    skeletonActor:SetLightingChannels(false, true, false)
                else
                    skeletonActor.SkeletalMeshComponent:SetLightingChannels(false, true, false)
                end

                --材质
                skeletonActor.SkeletalMeshComponent.NeedSecondPass = true
                 if modelConfig.spherePath and modelConfig.spherePath ~= '' and 
                    skeletonActor.SkeletalMeshComponent.NeedSecondPass == false then
                     local materail = LoadObject(modelConfig.spherePath)
                     if materail then
                         skeletonActor.SkeletalMeshComponent.SecondPassMaterial = materail
                     end
                 end
                
                table.insert(self.ActorList[index], skeletonActor)
                skeletonActor.SkeletalMeshComponent:SetSimulatePhysics(false)
            
                --tag 与 动画绑定
                if modelConfig.tag ~= "" then
                    self.SequenceActor[index]:AddBindingByTag(modelConfig.tag, skeletonActor, true)
                end
            end
        end
    end

    self.SequenceActor[index].SequencePlayer:PlayLooping(LoopCount)

end

function M:OnClickTeamIndex(index, roleId)
    --print("====OnClickTeamIndex:" .. tostring(index) .. ", roleId:" .. tostring(roleId))
    local touchActor = self.DefaultChairList[index]
    if touchActor and roleId <= 0 then
        touchActor.EF_AddPlayerTouch:SetHiddenInGame(true)
        touchActor.EF_AddPlayerTouch:ResetSystem()
        touchActor.EF_AddPlayerTouch:SetHiddenInGame(false)
    end
end

function M:ChangeRoleCamera(index, bFirst, roleId)
    if self.LastCameraIndex == index and self.LastRoledId == roleId then
        return
    end
    
    --self.Overridden.ChangeRoleCamera(self, index, bFirst or false, roleId or 0)
   
    if not self.FlySequenceActor then
        return
    end
  
    local cameraTag = tostring(roleId) .. "_" .. tostring(index)
    local defaultTag = "CameraObj" .. tostring(index)
    if index == 0 then
        cameraTag = defaultTag
    end
    
    local cameraObj = nil
    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, cameraTag)
    if cineCameraActors:Length() > 0 then
        cameraObj = cineCameraActors:Get(1)
    end
    if not cameraObj then
        cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, defaultTag)
        if cineCameraActors:Length() > 0 then
            cameraObj = cineCameraActors:Get(1)
        end
    end
    if cameraObj then
        self.TargetCameraObj = cameraObj
    end
    if not self.SplineActor then
        self.SplineActor = self:GetWorld():SpawnActor(UE.AActor,
            self.MoveCameraObj:GetTransform(),
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
            self, self)

        local trans = UE.UKismetMathLibrary.MakeTransform(
                UE.FVector(0, 0, 0), 
                UE.FRotator(0, 0, 0), 
                UE.FVector(1, 1, 1))
        self.SplineComponent = self.SplineActor:AddComponentByClass(UE.USplineComponent, false, trans, false)
    end
    if not self.SplineComponent then
        self.SplineComponent = self.SplineActor:GetComponentByClass(UE.USplineComponent)
        if not self.SplineComponent then
            print("=====Error! cant find UE.USplineComponent")
        end
    end
    if self.MoveCameraObj and self.TargetCameraObj and self.SplineComponent then
        self.SplineComponent:ClearSplinePoints(true)

        local MoveCameraObjPos = self.MoveCameraObj:K2_GetActorLocation()
        local TargetCameraObjPos = index == 0 and self.InitCameraLocation or self.TargetCameraObj:K2_GetActorLocation()
       
        --修正坐标高度:宇宙坐标异常
        if MoveCameraObjPos.Z > 0 then
            MoveCameraObjPos.Z = MoveCameraObjPos.Z - 5000
        end
        if TargetCameraObjPos.Z > 0 then
            TargetCameraObjPos.Z = TargetCameraObjPos.Z - 5000
        end
        self.SplineComponent:AddSplinePoint(MoveCameraObjPos, UE.ESplineCoordinateSpace.World, true)
        self.SplineComponent:AddSplinePoint(TargetCameraObjPos, UE.ESplineCoordinateSpace.World, true)


        local isBack = self.LastCameraIndex > index
        local MoveTangent = isBack and self.SplineTangentList2[self.LastCameraIndex + 1] or self.SplineTangentList[index + 1]
        local TargetTangent = isBack and self.SplineTangentList[self.LastCameraIndex + 1] or self.SplineTangentList2[index + 1]

        
        MoveTangent = self.LastCameraIndex == index and UE.FVector(0, 0, 0) or MoveTangent
        TargetTangent = self.LastCameraIndex == index and UE.FVector(0, 0, 0) or TargetTangent

        if isBack then
            MoveTangent = MoveTangent * -1
            TargetTangent = TargetTangent * -1
        end

        -- print("====MoveTangent:" .. tostring(MoveTangent))
        -- print("====TargetTangent:" .. tostring(TargetTangent))
        self.SplineComponent:SetTangentAtSplinePoint(0, MoveTangent, UE.ESplineCoordinateSpace.World, true)
        self.SplineComponent:SetTangentAtSplinePoint(1, TargetTangent, UE.ESplineCoordinateSpace.World, true)

        self.SplineComponent:SetDrawDebug(true)

        self.StartRotator = self.MoveCameraObj:K2_GetActorRotation()
        self.EndRotator = index == 0 and self.InitCameraRotation or self.TargetCameraObj:K2_GetActorRotation()
     
        local idx = self.LastCameraIndex > index and self.LastCameraIndex or index
        local rotationSpeed = self["RotationSpeed" .. tostring(idx)]
        if rotationSpeed == nil then
            rotationSpeed = self.RotationSpeed3
        end

        local dis = UE.UKismetMathLibrary.Vector_Distance(MoveCameraObjPos, TargetCameraObjPos)
        local calcRotationTime = dis / rotationSpeed

        self.RotationTime = self.LastCameraIndex == index and self.CameraBlendTime2 or calcRotationTime
       
        --相同位置摄像机移动处理
        self.passTime = 0
        if self.LastCameraIndex == index then
            self.MoveCameraObj:K2_SetActorLocation(TargetCameraObjPos, false, nil, false)
            self.MoveCameraObj:K2_SetActorRotation(self.TargetCameraObj:K2_GetActorRotation(), false)
            self.bCanMove = false
        else
            local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
            playerController:SetViewTargetWithBlend(self.MoveCameraObj, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
            self.bCanMove = true
        end
        
    end

    --定时器
    if not bFirst and self.LastCameraIndex ~= index then
        self.ChangeRoleCameraTimerHandle = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            { self, self.ChangeRoleCameraEvent }, self.RotationTime, false)
    end

    self.LastRoledId = roleId
    self.LastCameraIndex = index
end

function M:ChangeRoleCameraEvent()
    self.ChangeRoleCameraTimerHandle = nil
    if self.LastCameraIndex == 0 then
        self:SetEnableCollision_ChairActorList(true)
    end
    self.Overridden.ChangeRoleCameraEvent(self)

end

function M:IsChangeRoleCamera()
    return self.ChangeRoleCameraTimerHandle ~= nil
end

function M:ChangeModel(index, roleList)
    self:SwapTeamModel(index, roleList, true)
end

function M:ShowDefaultChair(index, bShow, roledId, bPlayChairEffect)
    -- print("====ShowDefaultChair:" .. tostring(index) .. ",bShow:" .. tostring(bShow) .. ", roleId:" .. tostring(roledId) .. ",bplayEffect:" .. tostring(bPlayChairEffect))
    local lockedFlags = {}
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Fight_Start')
    if ui and ui.LockedFlags then
        lockedFlags = ui.LockedFlags
    end
    local skeletonActor = self.DefaultChairList[index]
    if skeletonActor then
        if index > 1 then
            if not bShow then
                if self.bIsFirstEnter or not bPlayChairEffect then
                    skeletonActor:SetDissolveValue(0)
                else
                    skeletonActor:Dissolve(true)
                end
            else
                if bPlayChairEffect then
                    skeletonActor:Dissolve(false)
                else
                    skeletonActor:SetDissolveValue(1)
                end
                
            end
        end
        local isLocked = lockedFlags[index] or 0
        isLocked = isLocked == 1 and true or false 
        skeletonActor.EF_AddPlayer:SetHiddenInGame(roledId > 0 or isLocked)
        skeletonActor.EF_UILocked:SetHiddenInGame(not isLocked)
    end
end

function M:CreateDefualtChair()
    local charClass = UE.LoadClass('/Game/_Game/Blueprints/Character/BP_TouchActor.BP_TouchActor_C')
    local chairActors = UE.UGameplayStatics.GetAllActorsOfClass(self, charClass)
    print("=====createDefaultChair:" .. tostring(chairActors:Length()))
    for i = 1, chairActors:Length() do 
        local charActor = chairActors:Get(i)
        for _, tag in ipairs(charActor.Tags) do
            local has = string.contains(tag, "TouchActor")
            if has then
                local len = string.len(tag)
                local tagetChar = string.sub(tag, len, -1)
                local index = tonumber(tagetChar or "1")
                self.DefaultChairList[index] = charActor
                charActor.TeamIndex = index
                break
            end
        end
    end
    for _, charActor in pairs(self.DefaultChairList) do 
        charActor:SetActorEnableCollision(true)
        charActor:SetActorHiddenInGame(false) 
    end
end

function M:SetEnableCollision_ChairActorList(enable)
    for _, actor in pairs(self.DefaultChairList) do
        if UE.UGameplayStatics.IsValid(actor) then
            actor:SetActorEnableCollision(enable)
        end
    end
end

-----------------------------------------------------------------------------------
--进入编队场景
function M:LoadFightBefore(noFadeIn, GotoFight, isRecover)
    self.IsGotoFight = GotoFight
   
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:ShowTopUI(false)
    UIManager:GetInstance():ClearNotifications()


    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not noFadeIn then
        -- PC.BP_ScreenFade.OnFadeInFinished:Add(self, function()
        --     PC.BP_ScreenFade.OnFadeInFinished:Clear()

        --     local player = PC:K2_GetPawn()
        --     if player then
        --         if not isRecover then
        --             gameInstance.PlayerInCity = player:GetTransform()
        --         end
        --         player:SetActorEnableCollision(false)
        --         player:SetActorHiddenInGame(true)
        --         player.CharacterMovement:SetActive(false, false)
        --     end
        --     PC:UnPossess()
    
        --     if PC.RecordFightState then
        --         PC:RecordFightState()
        --     end
        --     UE.UGameplayStatics.GetGameInstance(self):EnterStreamingLevel({ 'UniverseFightBefore' }, false, isRecover, { self, self.OnFightBeforeEnd })
        -- end)
        -- PC.BP_ScreenFade:FadeIn(false)
        gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
        local player = PC:K2_GetPawn()
        if player then
            if not isRecover then
                gameInstance.PlayerInCity = player:GetTransform()
            end
            player:SetActorEnableCollision(false)
            player:SetActorHiddenInGame(true)
            player.CharacterMovement:SetActive(false, false)
        end
        PC:UnPossess()

        if PC.RecordFightState then
            PC:RecordFightState()
        end
        UE.UGameplayStatics.GetGameInstance(self):EnterStreamingLevel({ 'UniverseFightBefore' }, false, isRecover, { self, self.OnFightBeforeEnd })
    else
        local player = PC:K2_GetPawn()
        if player then
            if not isRecover then
                gameInstance.PlayerInCity = player:GetTransform()
            end
            player:SetActorEnableCollision(false)
            player:SetActorHiddenInGame(true)
            player.CharacterMovement:SetActive(false, false)
        end
        PC:UnPossess()

        if PC.RecordFightState then
            PC:RecordFightState()
        end
        UE.UGameplayStatics.GetGameInstance(self):EnterStreamingLevel({ 'UniverseFightBefore' }, false, isRecover, { self, self.OnFightBeforeEnd })
    end
end

--进入编队场景完成
function M:OnFightBeforeEnd()
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if pc then
        if pc.LevelSequencePlayer then
            pc.LevelSequencePlayer:Stop()
            pc.LevelSequencePlayer = nil
        end
        if pc.LevelSequenceActor then
            pc.LevelSequenceActor:K2_DestroyActor()
            pc.LevelSequenceActor = nil
        end
    end

    local level = UE.UGameplayStatics.GetStreamingLevel(self, 'UniverseFightBefore')
    if level then
        level.LevelTransform = UE.UKismetMathLibrary.MakeTransform(UE.FVector(0, 0, -5000), UE.FRotator(0, 0, 0), UE.FVector(1, 1, 1))
    end
    self.CurBindingTag = nil
    self.CurBindingActor = nil
    self.LastCameraIndex = -1
    self.LastRoledId = 0
    self.bIsFirstEnter = true

    print("--------------------->1111111111111111")
    --播放器对象
    local levelSequence = LoadObject("/Game/_Game/Characters/perform/GoWar_loop.GoWar_loop")
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
    print("--------------------->levelSequence")
    local LoopCount = UE.FMovieSceneSequenceLoopCount()
    LoopCount.Value = -1
    local Settings = UE.FMovieSceneSequencePlaybackSettings()
    Settings.LoopCount = LoopCount
    local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
    self.FlySequenceActor = levelSequenceActor
    print("--------------------->22222222")
    --场景摄像机
    --local cineCameraActor = UE.UGameplayStatics.GetActorOfClass(self, UE.ACineCameraActor)
    --self.FlySequenceActor:AddBindingByTag("CameraObj0", cineCameraActor, false)
    self.FlySequenceActor.SequencePlayer:PlayLooping(-1)

    -- local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    -- playerController:SetViewTargetWithBlend(cineCameraActor, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)

    --获取CameraObj0保存trans
    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "CameraObj0")
    if cineCameraActors:Length() > 0 then
        self.MoveCameraObj = cineCameraActors:Get(1)
        local pos = UE.FVector(-332.485345, 195.221594, -4874.0)
        local rot = UE.FRotator(0, -50, 0)
        self.MoveCameraObj:K2_SetActorLocation(pos, false, nil, false)
        self.MoveCameraObj:K2_SetActorRotation(rot, false)
        self.InitCameraLocation = self.MoveCameraObj:K2_GetActorLocation()
        self.InitCameraRotation = self.MoveCameraObj:K2_GetActorRotation()
        self.InitCameraForward = self.MoveCameraObj:GetActorForwardVector()
    end

    --查找飞船
    local flyActors = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.ASkeletalMeshActor)
    --print("==========flyActors:" .. tostring(flyActors:Length()))
    -- local attachedActors = UE.TArray(UE.AActor)
    if flyActors:Length() > 0 then
        for i = 1, flyActors:Length() do 
            flyActors:Get(i):SetActorEnableCollision(false)
            -- --获取附加的actor
            -- flyActors:Get(i):GetAttachedActors(attachedActors, true, false)
            -- for j = 1, attachedActors:Length() do
            --     local attachedActor = attachedActors:Get(j)
            --     for _, tag in ipairs(attachedActor.Tags) do
            --         local has = string.contains(tag, "TouchActor")
            --         if has then
            --             local len = string.len(tag)
            --             local tagetChar = string.sub(tag, len, -1)
            --             local index = tonumber(tagetChar or "1")
            --             print("===attachedActor:" .. tostring(index))
            --             break
            --         end
            --     end
            -- end
        end
    end

    self:CreateDefualtChair()
    self:ChangeRoleCamera(0, true)

    local topUi = UIManager:GetInstance():GetTopUI()
    if topUi then
        topUi:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Fight_Start')
    if ui and ui.OnShowUI then
        ui:OnShowUI()
    end

    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    -- PC.BP_ScreenFade:FadeOut(false)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2")
    print('---------------------->OnFightBeforeEnd')
end

--退出编队场景
function M:UnloadFightBefore()
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    -- PC.BP_ScreenFade.OnFadeInFinished:Add(self, function()
    --     PC.BP_ScreenFade.OnFadeInFinished:Clear()
    --     if PC.RecordFightState then
    --         PC:RecordFightState()
    --     end
    --     UE.UGameplayStatics.GetGameInstance(self):LeaveStreamingLevel(false, { self, function(self) 
    --         self:ClearAllCacheActors()
    --         local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    --         local gameMode = UE.UGameplayStatics.GetGameMode(self)
    --         local player = gameMode:BPI_GetPlayer()
    --         if player then
    --             PC.OnPossessedPawnChanged:Add(self, self.OnUnloadFightBeforeEnd)
    --             PC:Possess(player)
    --         else
    --             self:OnUnloadFightBeforeEnd()
    --         end
    --     end })
    -- end)
    -- PC.BP_ScreenFade:FadeIn(false)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
    if PC.RecordFightState then
        PC:RecordFightState()
    end
    UE.UGameplayStatics.GetGameInstance(self):LeaveStreamingLevel(false, { self, function(self) 
        self:ClearAllCacheActors()
        local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        local player = gameMode:BPI_GetPlayer()
        if player then
            PC.OnPossessedPawnChanged:Add(self, self.OnUnloadFightBeforeEnd)
            PC:Possess(player)
        else
            self:OnUnloadFightBeforeEnd()
        end
    end })
end

--卸载编队场景完成
function M:OnUnloadFightBeforeEnd()
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    PC.OnPossessedPawnChanged:Remove(self, self.OnUnloadFightBeforeEnd)

    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    --针对缓存的ui和参数进行处理
  
    if gameInstance.UIName ~= '' and gameInstance.UIArgs ~= '' then
        -- gameInstance:RemoveTopUI(false)
        local oldUI = gameInstance:GetUMG('UI_BossRush_Main')
        if oldUI then
            gameInstance:ShowAllUI()
        else
            if gameInstance.UIName == 'UI_Challenge_Copy' then
                local ui = gameInstance:AddUMG('UI_Challenge_Copy')
                if ui then
                    ui:RefreshUI(gameInstance.UIArgs)
                end
            elseif gameInstance.UIName == 'UI_Daily_Copy' then
                local args = string.split(gameInstance.UIArgs, '|')
                local ui = gameInstance:AddUMG('UI_Daily_Copy')
                if ui then
                    ui:InitUI(tonumber(args[1]))
                    ui:RefreshUI(tonumber(args[2]), tonumber(args[3]))
                end
            elseif gameInstance.UIName == 'UI_CharTrain' then
                local ui = gameInstance:AddUMG('UI_CharTrain')
                if ui then
                    ui:RefreshUI(gameInstance.UIArgs)
                end
            elseif gameInstance.UIName == 'UI_Dps_Copy' then
                local ui = gameInstance:AddUMG('UI_Dps_Copy')
                if ui then
                    ui:RefreshUI(gameInstance.UIArgs)
                end
            elseif gameInstance.UIName == 'UI_BossRush_Main' then
                local ui = gameInstance:AddUMG('UI_BossRush_Main')
                if ui then
                    ui:Setup()
                end
            end
        end
    else
        gameInstance:ShowTopUI(true)
    end
    gameInstance.UIName = ''
    gameInstance.UIArgs = ''

    MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')
    
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        -- player.bGenerateOverlapEventsDuringLevelStreaming = false
        -- player.UpdateOverlapsMethodDuringLevelStreaming = UE.EActorUpdateOverlapsMethod.NeverUpdate
        player:K2_SetActorTransform(gameInstance.PlayerInCity, false, nil, false)
        player:SetActorEnableCollision(true)
        player:SetActorHiddenInGame(false)
        if not UE.UGameplayStatics.ObjectIsA(player, LoadClass('/Game/_Game/Blueprints/BuildingSystem/Blueprints/Interactables/BP_BuildActor.BP_BuildActor_C')) then
            player.CharacterMovement:SetActive(true, false)
        end
    end

    gameInstance:RemoveUMG("UI_Loading2")
end
-----------------------------------------------------------------------------------

-----------------------------------------------------------------------------------
---进入角色场景
function M:LoadCharacterSystem(selectedRoleId, initTabIndex, isRecover)
    self.CachedRoleId = selectedRoleId or 0 
    self.CachedInitTabIndex = initTabIndex or 0

    --临时处理
    MessageManager:GetInstance():Broadcast('OnLoadCharacterSystem', true)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)

    -- PC.BP_ScreenFade.OnFadeInFinished:Add(self, function()
    --     PC.BP_ScreenFade.OnFadeInFinished:Clear()
    --     local player = PC:K2_GetPawn()
        
    --     if player then
    --         gameMode:BPI_SetPlayer(player)
    --         gameInstance.PlayerInCity = player:GetTransform()
    --         player:SetActorEnableCollision(false)
    --         player:SetActorHiddenInGame(true)
    --         player.CharacterMovement:SetActive(false, false)
    --         PC:UnPossess()
    --     end

    --     if PC.RecordFightState then
    --         PC:RecordFightState()
    --     end
    --     gameInstance:EnterStreamingLevel({ 'CharecterScene' }, false, isRecover, { self, self.OnLoadCharacterSystemEnd })
    -- end)
    -- PC.BP_ScreenFade:FadeIn(false)
    gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
    local player = PC:K2_GetPawn()
    if player then
        gameMode:BPI_SetPlayer(player)
        gameInstance.PlayerInCity = player:GetTransform()
        player:SetActorEnableCollision(false)
        player:SetActorHiddenInGame(true)
        player.CharacterMovement:SetActive(false, false)
        PC:UnPossess()
    end

    if PC.RecordFightState then
        PC:RecordFightState()
    end
    gameInstance:EnterStreamingLevel({ 'CharecterScene' }, false, isRecover, { self, self.OnLoadCharacterSystemEnd })
end

---角色场景加载完成
function M:OnLoadCharacterSystemEnd()
    self:ClearAllCacheActors()

    self.IsInCharacterScene = true

    local skydomeActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AStaticMeshActor, "Sky_Dome")
    if skydomeActors:Length() > 0 then
        self.SkyDomeActor = skydomeActors:Get(1)
        if self.SkyDomeActor then
            self.SkyDomeActor:SetActorHiddenInGame(true)
        end
    end

    local topUi = UIManager:GetInstance():GetTopUI()
    if topUi then
        topUi:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:AddUMG('UI_CharacterSystem')
    if ui then
        ui:OnShowUI(self.CachedRoleId, self.CachedInitTabIndex)
    end

    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    -- PC.BP_ScreenFade:FadeOut(false)
    gameInstance:RemoveUMG("UI_Loading2")
end

--卸载角色场景
function M:UnloadCharacterSystem()
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    -- PC.BP_ScreenFade.OnFadeInFinished:Add(self, function()
    --     PC.BP_ScreenFade.OnFadeInFinished:Clear()
    --     if PC.RecordFightState then
    --         PC:RecordFightState()
    --     end
    --     local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    --     self.TopLevelInfo = gameInstance:GetTopLevelInfo()
    --     UE.UGameplayStatics.GetGameInstance(self):LeaveStreamingLevel(false, { self, function(self)
    --         print('----self.TopLevelInfo:' .. tostring(table.dump(self.TopLevelInfo, nil, 10)))
    --         if self:IsTopLevelHasScene('UniverseFightBefore') then
    --             self:OnFightBeforeEnd()
    --         else
    --             local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    --             local gameMode = UE.UGameplayStatics.GetGameMode(self)
    --             local player = gameMode:BPI_GetPlayer()
    --             if player then
    --                 PC.OnPossessedPawnChanged:Add(self, self.OnUnLoadCharacterSystemEnd)
    --                 PC:Possess(player)
    --             else
    --                 self:OnUnLoadCharacterSystemEnd()
    --             end
    --         end
    --     end })
    -- end)
    -- PC.BP_ScreenFade:FadeIn(false)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
    if PC.RecordFightState then
        PC:RecordFightState()
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    self.TopLevelInfo = gameInstance:GetTopLevelInfo()
    UE.UGameplayStatics.GetGameInstance(self):LeaveStreamingLevel(false, { self, function(self)
        print('----self.TopLevelInfo:' .. tostring(table.dump(self.TopLevelInfo, nil, 10)))
        if self:IsTopLevelHasScene('UniverseFightBefore') then
            self:OnFightBeforeEnd()
        else
            local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            local player = gameMode:BPI_GetPlayer()
            if player then
                PC.OnPossessedPawnChanged:Add(self, self.OnUnLoadCharacterSystemEnd)
                PC:Possess(player)
            else
                self:OnUnLoadCharacterSystemEnd()
            end
        end
    end })
end

function M:IsTopLevelHasScene(levelName)
    if self.TopLevelInfo then
        if self.TopLevelInfo[1] then
            for _, LevelName in pairs(self.TopLevelInfo[1]) do 
                if LevelName == levelName then
                    return true
                end
            end
        end
    end
    return false
end

---角色场景卸载载完成
function M:OnUnLoadCharacterSystemEnd()
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    PC.OnPossessedPawnChanged:Remove(self, self.OnUnLoadCharacterSystemEnd)

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
   
    if not PC.bIsInShop and PC.BPI_OnLevelShown then
        PC:BPI_OnLevelShown()
    else
        if player then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            player:K2_SetActorTransform(gameInstance.PlayerInCity, false, nil, false)
            player:SetActorEnableCollision(true)
            player:SetActorHiddenInGame(false)
            if not UE.UGameplayStatics.ObjectIsA(player, LoadClass('/Game/_Game/Blueprints/BuildingSystem/Blueprints/Interactables/BP_BuildActor.BP_BuildActor_C')) then
                player.CharacterMovement:SetActive(true, false)
            end
        end
    end

    self.IsInCharacterScene = false

    if self.SkyDomeActor then
        self.SkyDomeActor:SetActorHiddenInGame(false)
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_CharacterSystem')
    if ui then
        UIManager:GetInstance():RemoveUI(ui)
    end
   
    local topUi = UIManager:GetInstance():GetTopUI()
    if topUi then
        topUi:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    end
    MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')

    -- local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    -- PC.BP_ScreenFade:FadeOut(false)
    gameInstance:RemoveUMG("UI_Loading2")

    MessageManager:GetInstance():Broadcast('OnLoadCharacterSystem', false)
end
-----------------------------------------------------------------------------------

return M
