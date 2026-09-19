local Database = require '_Game.Utils.Database'
local InputAssets = require "_Game.Utils.Input.InputAssets"
local activitysystem = require("Module.Activity.ActivitySystem")

---@type BP_PlayerController_City_C
local M = UnLua.Class()

function M:ReceiveBeginPlay()
    print('--------------->city.beginplay')

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    --清理缓存
    gameInstance.UICahed = {}
    --重置音乐
    gameInstance:ClearBgm()

    --强制设置时间缩放1
    -- UE.UGameplayStatics.SetGlobalTimeDilation(self, 1)
    gameInstance.Walk = false

    print("===gameInstance.BackFromFight:" .. tostring(gameInstance.BackFromFight))
    print("===gameInstance.UIName:" .. tostring(gameInstance.UIName))
    print("===gameInstance.UIArgs:" .. tostring(gameInstance.UIArgs))
    if gameInstance.BackFromFight then
        local isSpecialLevel = false
        local topInfo = gameInstance:GetTopLevelInfo()
        if topInfo and topInfo[2] then
            for _, levelName in ipairs(topInfo[2]) do
                if levelName == 'City1Station' then
                    local gameMode = UE.UGameplayStatics.GetGameMode(self)
                    gameMode:SpawnActors()
                    self:LoadStationScene(true, true)
                    isSpecialLevel = true
                    --播放bgm
                    self:OnLevelShowStart()
                    break
                elseif levelName == 'City1Hotel' then
                    local gameMode = UE.UGameplayStatics.GetGameMode(self)
                    gameMode:SpawnActors()
                    self:EnterBuildLevel('City1Hotel', self.PlayerStartName, true)
                    isSpecialLevel = true
                    break
                end
            end
        end
        if not isSpecialLevel then
            --不用加载商业区,加载资关卡
            gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
            if gameInstance.ToCityFromFightArgString == 'LoadFightBefore' then
                self:BackFromFightAndOpenFightBefore(nil, true)
            else
                self:BackFromFight()
            end
        else
            -- local sgspeak = gameInstance:LoadSaveGameSpeak()
            -- if not sgspeak.StoryFinished then
            --     self.BP_StateTree:SetStateTree(gameInstance.PlotStateTree)
            --     self.BP_StateTree:StartLogic()
            -- end
        end
    else
        if gameInstance.BackFromSpeicalUniverse then
            gameInstance.BackFromSpeicalUniverse = false
            gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
        end
        local cineCameraActor = UE.UGameplayStatics.GetActorOfClass(self, UE.ACineCameraActor)
        playerController:SetViewTargetWithBlend(cineCameraActor, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
        self:CreateFlyChair()
        self:OpenLevelSequence()
    end
    gameInstance.BackFromFight = false
    gameInstance.ToCityFromFightArgString = ""
    gameInstance.UIName = ""
    gameInstance.UIArgs = ""

    self.Overridden.ReceiveBeginPlay(self)
end

function M:OnBackFromFightFinished()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- gameInstance:RemoveUMG("UI_Loading2")
    local ui = gameInstance:GetUMG("UI_Loading2")
    if ui then
        ui:DelayDestroy(true)
    end
end

function M:ReceiveEndPlay()
    if self.LevelSequenceActor then
        self.LevelSequenceActor:K2_DestroyActor()
        self.LevelSequenceActor = nil
        self.LevelSequencePlayer  = nil
    end
end

function M:InitUI()
    if self.bIsInStationScene then return end 
    if UE.UKismetSystemLibrary.IsValid(self.UI_City) then
        self.UI_City:SetVisibility(UE.ESlateVisibility.Visible)
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:AddUMG("UI_City")
        if ui then
            self.UI_City = ui
            self.BP_PlayerController_City_UniverseBridge.UI_City = ui
            ui:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
    self.Overridden.InitUI(self)
end

function M:OnShowUISettings()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    ---@type UI_SetSystem_C
    local ui = gameInstance:AddUMG("UI_SetSystem")
    ui:ChangeTab(0)
    ui:PlayAnimation(ui.In, 0, 1, UE.EUMGSequencePlayMode.Forward, 1, false)
end

function M:ShowUI()
    if self.bIsInStationScene then return end 
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.UICahed then
        for ui_name, _ in pairs(gameInstance.UICahed) do
            if ui_name == 'ui_city' then
                return
            end
        end
    end
    if UE.UKismetSystemLibrary.IsValid(self.UI_City) then
        self.UI_City:OnShowUI()
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:AddUMG("UI_City")
        if ui then
            self.UI_City = ui
            self.BP_PlayerController_City_UniverseBridge.UI_City = ui
            ui:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
    self.UI_City:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self:CallOnShowUI()
    self.Overridden.ShowUI(self)
end


function M:ClearPreLevelSequencePlayer()
    if self.LevelSequenceActor then
        self.LevelSequenceActor:K2_DestroyActor()
        self.LevelSequenceActor = nil
        self.LevelSequencePlayer  = nil
    end
end

function M:OnProcessLevelLoaded()
    self.Overridden.OnProcessLevelLoaded(self)
    local sequencePath = '/Game/_Game/Characters/perform/enteranim_fly_loop1.enteranim_fly_loop1'
    local levelSequence = LoadObject(sequencePath)
    if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
        LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(sequencePath))
        return 
    end
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
    local LoopCount = UE.FMovieSceneSequenceLoopCount()
    LoopCount.Value = -1
    local Settings = UE.FMovieSceneSequencePlaybackSettings()
    Settings.LoopCount = LoopCount
    print('-----------OnProcessLevelLoaded')
    self.LevelSequencePlayer, self.LevelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
    self.LevelSequencePlayer:Play()
end

function M:EnterGame()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:ShowTalkUI(0)
    self:ProcessEnterGame()
end

function M:ProcessEnterGame()
    self.EnterGameAnimating = false
    self.PreLevelSequencePlayer = self.LevelSequencePlayer
    self.Overridden.ProcessEnterGame(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    if saveGameSpeak.StoryFinished then
        coroutine.resume(coroutine.create(function()
            gameInstance.UnloadStreamLevelCoroutine(self, "CityLoginMap", false)
            coroutine.resume(coroutine.create(function()
                gameInstance.LoadStreamLevelCoroutine(self, gameMode.LevelName, true, false)
                if UE.UKismetMaterialLibrary.IsValid(self.UILoading) then
                    gameInstance:RemoveUMG("UI_Loading")
                    self.UILoading = nil
                end
                self:InitUI()
                self:OnLevelShown()
            end))
        end))
    else
        local in_city = self:OnEnterStateTree()
        if in_city then
            if UE.UGameplayStatics.ObjectIsA(gameMode, UE.AGHSGameModeCity:StaticClass()) then
                gameMode:SpawnActors()
                coroutine.resume(coroutine.create(function()
                    gameInstance.UnloadStreamLevelCoroutine(self, "CityLoginMap", false)
                    coroutine.resume(coroutine.create(function()
                        gameInstance.LoadStreamLevelCoroutine(self, gameMode.LevelName, true, false)
                        if UE.UKismetMaterialLibrary.IsValid(self.UILoading) then
                            gameInstance:RemoveUMG("UI_Loading")
                            self.UILoading = nil
                        end
                        self:InitUI()
                        self:OnLevelShown()
                    end))
                end))
            end
        else
            self:ClearPreLevelSequencePlayer()
            if UE.UKismetMaterialLibrary.IsValid(self.UILoading) then
                gameInstance:RemoveUMG("UI_Loading")
                self.UILoading = nil
            end
            gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
        end
    end
end

function M:OnEnterGameEnd()
    print('-------enteranim_fly_loop1 end')
    -- UIManager:GetInstance().isBlockInput = false
    if self.LoadStateTreeAfterEnterGameEnd then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        self.BP_StateTree:SetStateTree(gameInstance.PlotStateTree)
        self.BP_StateTree:StartLogic()
        self:InitUI()
        --在transcondition里removeumg
        if self.LevelShownFromSequenceEnd then
            -- 穿梭机下来不需要黑屏，或可以延迟黑屏，没必要一开始就遮
            self.LevelShownFromSequenceEnd = false
        else
            gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
        end
    end
    if UE.UKismetMaterialLibrary.IsValid(self.LevelSequenceActor) then
        self.LevelSequenceActor:K2_DestroyActor()
        self.LevelSequenceActor = nil
        self.LevelSequencePlayer  = nil
    end
end

function M:OpenLevelSequence()
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    print("===OpenLevelSequence:" .. tostring(gameInstance.LoggedIn))
    if gameInstance.LoggedIn then
        -- self.UILoading = gameInstance:AddUMG("UI_Loading", nil, 1)
        if gameMode.InitData then gameMode:InitData() end
        -- gameMode.BP_Preload:PreloadAssets()
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.2)
            self:OnCurrentLevelOpenFinished()
        end))
    else
        local ui = gameInstance:AddUMG('UI_Login')
        ui:InitUI()
        ui:LoadStreamLevelProces()
        self.UI_Login = ui
        
        --if gameMode.InitData then gameMode:InitData() end
        gameMode:SpawnActors()
        --加载登录地图
        UE.UGHSFunctionLibrary.PreloadStreamingLevelByName(self, "CityLoginMap")
        local level = UE.UGameplayStatics.GetStreamingLevel(self, "CityLoginMap")
        if level then
            gameInstance:StreamLevelSetShouldBeVisible("CityLoginMap", true)
        end
    end
end

function M:ShowSRPGLevelSelection()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9007) then
        local ui_city = gameInstance:GetUMG('UI_City')
        if ui_city then
            ui_city:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        local ui = gameInstance:GetUMG('UI_SRPG_Start')
        if ui then
            ui:InitUI()
            ui:UpdateUI()
        end
    end
end

function M:OnLevelShown()
    if self.LevelSequencePlayer then
        self.LevelSequencePlayer:Stop()
        self.LevelSequencePlayer = nil
    end
    if self.LevelSequenceActor then
        self.LevelSequenceActor:K2_DestroyActor()
        self.LevelSequenceActor = nil
    end

    self:PlaySequenceOnce()

    self.Overridden.OnLevelShown(self)
end


function M:PlaySequenceOnce()
    LOG_DEBUG_TRACKBACK("PlaySequenceOnce")
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local charId = gameInstance:GetPlayerCharacterIdInCity()
    if charId <= 0 then
        LOG_ERROR('--------> error char id:' .. tostring(charId))
        return
    end
    local charConfig = Database.Query('d_character', charId)
    if not charConfig or not charConfig.CityCarPath or '' == charConfig.CityCarPath then
        LOG_ERROR('--------> error CityCarPath:' .. tostring(charId))
        return
    end
    local levelSequencePath = charConfig.CityCarPath

    local levelSequence = LoadObject(levelSequencePath)
    if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
        LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(levelSequencePath))
        return
    end
    local player = self:K2_GetPawn()
    if player then
        print("------------------------------>>has player")
    end
    gameInstance:RemoveUMG('UI_Loading2')
    --主控角色
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        player:SetActorHiddenInGame(false)
    end
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
    print('-----------PlaySequenceOnce')
    local LoopCount = UE.FMovieSceneSequenceLoopCount()
    LoopCount.Value = 0
    local Settings = UE.FMovieSceneSequencePlaybackSettings()
    Settings.LoopCount = LoopCount
    local sequencePlayer, sequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)

    sequenceActor:AddBindingByTag("MainObj", player, false)

    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, 'MainCharacterCamera')
    if cineCameraActors:Length() > 0 then
        local camObj = cineCameraActors:Get(1)
        sequenceActor:AddBindingByTag("CamObj", camObj, false)
    end

    if sequenceActor and sequenceActor.SequencePlayer then
        sequenceActor.SequencePlayer.OnPlay:Clear()
        sequenceActor.SequencePlayer.OnPlay:Add(self, function()
            sequenceActor.SequencePlayer.OnPlay:Clear()
            self:OnLevelShowStart()
        end)
        sequenceActor.SequencePlayer.OnFinished:Clear()
        sequenceActor.SequencePlayer.OnFinished:Add(self, function()
            sequenceActor.SequencePlayer.OnFinished:Clear()

            if self.LevelSequencePlayer then
                self.LevelSequencePlayer:Stop()
                self.LevelSequencePlayer = nil
            end
            if self.LevelSequenceActor then
                self.LevelSequenceActor:K2_DestroyActor()
                self.LevelSequenceActor = nil
            end

            self.LevelShownFromSequenceEnd = true
            self:OnLevelShowEnd()
        end)
        sequenceActor.SequencePlayer:Play()
    end

    self.LevelSequencePlayer = sequencePlayer
    self.LevelSequenceActor = sequenceActor

    if charId == 10601 then
        self:OnLevelShow_1006()
    end
end

function M:LoadFightBeforeInCity()
    self.BP_PlayerController_City_UniverseBridge:LoadFightBefore(false, true)
end

---------------------------------------------------------
---进入家装地图
function M:EnterBuildLevel(mapName, playerStartName, isRecover)
    if self.BP_PlayerController_City_UniverseBridge then
        self.BP_PlayerController_City_UniverseBridge.BlockSpecialSkill = true 
    end
    --隐藏一些额外的飞船,模型 
    self:HiddenStaticMeshActorByTag('flybox_coli', UE.AStaticMeshActor, true)
    self:HiddenStaticMeshActorByTag('MainFly', UE.ASkeletalMeshActor, true)

    self.MapName = mapName
    self.PlayerStartName = playerStartName or self.PlayerStartName

    local targetLevels = { 'City1Hotel', 'City1Hotel_Day', 'City1Hotel_Night' }
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local unloadLevels, loadedLevels = gameInstance:GetEnterStreamingLevels(targetLevels)
    print('----->unloadLevels:' .. tostring(#unloadLevels))
    print('----->loadedLevels:' .. tostring(#loadedLevels))
    if 0 == #unloadLevels and 0 == #loadedLevels then
        self.DontLoadLevel = true
        self:OnEnterBuildLevelFinished()
    else
        self.DontLoadLevel = false
        -- self.BP_ScreenFade.OnFadeInFinished:Add(self, function()
        --     self.BP_ScreenFade.OnFadeInFinished:Clear()
    
            local player = self:K2_GetPawn()
            if player then
                gameMode:BPI_SetPlayer(player)
    
                player:SetActorEnableCollision(false)
                -- player:SetActorHiddenInGame(true)
                player.CharacterMovement:SetActive(false, false)
                self:UnPossess()
            else
                gameInstance:CreateDefaultCharacterInCity()
            end
            UE.UGameplayStatics.GetGameInstance(self):EnterStreamingLevel(targetLevels, false, isRecover, { self, function() 
                -- self.BP_ScreenFade:FadeOut(false)
                --切换角色信封
                self.OldCharacterId = gameInstance:GetPlayerCharacterIdInCity()
                gameInstance:ChangePlayerCharacterInCity(10501)
                local player = gameMode:BPI_GetPlayer()
                if player then
                    local springArmComp = player:GetComponentByClass(UE.USpringArmComponent)
                    springArmComp.bEnableCameraLag = false
                    springArmComp.bDoCollisionTest = false
                    if self.PlayerStartName then
                        local playerStart = gameMode:FindPlayerStart(self, self.PlayerStartName)
                        if playerStart then
                            self.PlayerCameraManager:K2_SetActorTransform(playerStart:GetTransform(), false, nil, false)
                            player:K2_SetActorLocation(playerStart:K2_GetActorLocation(), false, nil, false)
                            player:K2_SetActorRotation(playerStart:K2_GetActorRotation(), false)
                            -- player:K2_SetActorTransform(playerStart:GetTransform(), false, nil, false)
    
                            local rotator = playerStart:K2_GetActorRotation()
                            rotator = rotator - UE.FRotator(0, -20, 0)
                            self:SetControlRotation(rotator)
                        end
                    else
                        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                        player:K2_SetActorTransform(gameInstance.PlayerInCity, false, nil, false)
                    end
    
                    self.OnPossessedPawnChanged:Add(self, self.OnEnterBuildLevelFinished)
                    self:Possess(player)
                end
            end })
        -- end)
        -- self.BP_ScreenFade:FadeIn(false)
        gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
    end
end


function M:OnEnterBuildLevelFinished()
    self.OnPossessedPawnChanged:Remove(self, self.OnEnterBuildLevelFinished)

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()

    local cityUI = gameInstance:GetUMG('UI_City')
    if cityUI then
        cityUI:EnterBuildRegion()
        cityUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

        -- cityUI:Refresh_UI_City(true)
    else
        cityUI = gameInstance:AddUMG('UI_City')
        cityUI:EnterBuildRegion()
        -- cityUI:Refresh_UI_City(true)
        cityUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    end
    if not self.AllBuildActors or #self.AllBuildActors <= 0 then
        self:CreateBuildHome()
    end

    if player and not self.DontLoadLevel then
        -- player:SetActorHiddenInGame(false)
        player:SetActorEnableCollision(true)
        if not UE.UGameplayStatics.ObjectIsA(player, LoadClass('/Game/_Game/Blueprints/BuildingSystem/Blueprints/Interactables/BP_BuildActor.BP_BuildActor_C')) then
            player.CharacterMovement:SetActive(true, false)
        end

        local springArmComp = player:GetComponentByClass(UE.USpringArmComponent)
        -- springArmComp.bEnableCameraLag = true
        -- springArmComp.bDoCollisionTest = true

        -- self.BP_ScreenFade:FadeOut(false)
        -- LOG_DEBUG_TRACKBACK("FadeOut")
        -- springArmComp.bEnableCameraLag = false
        -- springArmComp:K2_SetWorldLocationAndRotation(player:K2_GetActorLocation(), player:K2_GetActorRotation(), false, nil, false)
        -- self.PlayerCameraManager:K2_SetActorLocationAndRotation(player:K2_GetActorLocation(), player:K2_GetActorRotation(), false, nil, false)
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.3)
            springArmComp.bEnableCameraLag = true
            springArmComp.bDoCollisionTest = true
            gameInstance:RemoveUMG("UI_Loading2")

            self.IsInBuildLevel = true

            self.LastControlledBuildActor = nil
            
            print("--------------进入家装场景完成")
            MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')

            local isOpenDay = gameInstance:GetIsBuildOpenDay()
    
            local levelScene = UE.UGameplayStatics.GetStreamingLevel(self, isOpenDay and 'City1Hotel_Night' or 'City1Hotel_Day')
            if levelScene and levelScene:IsLevelLoaded() and levelScene:IsLevelVisible() then
                levelScene:SetShouldBeVisible(false)
            end
            UIManager:GetInstance():UpdateCursor()
            UIManager:GetInstance():UpdateRequireShowInteractOptions()
            local InputUtils = require "_Game.Utils.Input.InputUtils"
            InputUtils.RemoveMappingContext(self, InputAssets.IMC_UI_Cursor)
        end))
        return
    end
    self.IsInBuildLevel = true

    self.LastControlledBuildActor = nil
    
    print("--------------进入家装场景完成")
    MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')

    local isOpenDay = gameInstance:GetIsBuildOpenDay()
    
    local levelScene = UE.UGameplayStatics.GetStreamingLevel(self, isOpenDay and 'City1Hotel_Night' or 'City1Hotel_Day')
    if levelScene and levelScene:IsLevelLoaded() and levelScene:IsLevelVisible() then
        levelScene:SetShouldBeVisible(false)
    end
    UIManager:GetInstance():UpdateCursor()
    UIManager:GetInstance():UpdateRequireShowInteractOptions()
    local InputUtils = require "_Game.Utils.Input.InputUtils"
    InputUtils.RemoveMappingContext(self, InputAssets.IMC_UI_Cursor)
end

---离开家装地图
function M:LeaveBuildLevel(playerStartName, callback)
    self.OnLeaveBuildLevelCallBack = callback
    self.PlayerStartName = playerStartName

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    local cityUI = gameInstance:GetUMG('UI_City')
    if cityUI then
        cityUI:Refresh_UI_City(true)
    end
    UIManager:GetInstance():ClearTracker()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local unloadLevels, loadedLevels = gameInstance:GetLeaveStreamingLevels()
    if 0 == #unloadLevels and 0 == #loadedLevels then
        self.DontLoadLevel = true
        self:OnLeaveBuildLevelFinished()
    else
        local topLevelInfo = gameInstance:GetTopLevelInfo()
        if topLevelInfo and topLevelInfo[1] and topLevelInfo[2] then
            local enterLevels = topLevelInfo[1]
            local unloadLevels = topLevelInfo[2]
            if #enterLevels == 0 then
                local topIndex = #gameInstance.LoadedStreamingLevelNameStack
                table.remove(gameInstance.LoadedStreamingLevelNameStack, topIndex)
                local loadedLevels = UE.TArray(UE.FName)
                UE.UGHSFunctionLibrary.LSS_Plugin_GetStreamingLevelsInfo(self, nil, nil, loadedLevels, nil)
                table.insert(gameInstance.LoadedStreamingLevelNameStack, {{'City1BusinessCenter'}, loadedLevels:ToTable()})
            end
        end
        self.DontLoadLevel = false
        gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
        local player = self:K2_GetPawn()
        if player then
            gameMode:BPI_SetPlayer(player)
            player:SetActorEnableCollision(false)
            player:SetActorHiddenInGame(true)
            player.CharacterMovement:SetActive(false, false)
            local springArmComp = player:GetComponentByClass(UE.USpringArmComponent)
            if springArmComp then
                springArmComp.bEnableCameraLag = false
                springArmComp.bDoCollisionTest = false 
            end
        end
        self:ClearBuildHome()
        self.LastControlledBuildActor = nil
        
        UE.UGameplayStatics.GetGameInstance(self):LeaveStreamingLevel(false, { self, function(self)
            -- self.BP_ScreenFade:FadeOut(false)
            --切换角色默认
            gameInstance:ChangePlayerCharacterInCity(self.OldCharacterId)
            local player = gameMode:BPI_GetPlayer()
            if player then
                local playerStart = gameMode:FindPlayerStart(self, self.PlayerStartName)
                if playerStart then
                    player:K2_SetActorTransform(playerStart:GetTransform(), false, nil, false)
                end
                local rotator = playerStart:K2_GetActorRotation()
                rotator = rotator - UE.FRotator(0, -20, 0)
                self:SetControlRotation(rotator)

                -- self:SetViewTargetWithBlend(player, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
                self.OnPossessedPawnChanged:Add(self, self.OnLeaveBuildLevelFinished)
                self:Possess(player)
                -- self:OnLeaveBuildLevelFinished()
            end
        end })
    end
end

function M:OnLeaveBuildLevelFinished()
    if self.DontLoadLevel then
        self:HiddenStaticMeshActorByTag('flybox_coli', UE.AStaticMeshActor, false)
        self:HiddenStaticMeshActorByTag('MainFly', UE.ASkeletalMeshActor, false)    
    end
   
    if self.BP_PlayerController_City_UniverseBridge then
        self.BP_PlayerController_City_UniverseBridge.BlockSpecialSkill = false 
    end
    
    self.IsInBuildLevel = false
    self.OnPossessedPawnChanged:Remove(self, self.OnLeaveBuildLevelFinished)
   
    local BuildSystem = require('Module.BuildSystem.BuildSystem')
    self.AllBuildActors = {}
    BuildSystem:GetInstance():ClearAllCachedCharacterMesh()

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local cityUI = gameInstance:GetUMG('UI_City')
    if cityUI then
        cityUI:ExitBuildRegion() 
    end
    -- self.BP_ScreenFade:FadeOut(false)
    coroutine.resume(coroutine.create(function()
        print("--------------离开家装场景完成")
        UE.UKismetSystemLibrary.Delay(self, 0.3)
        gameInstance:RemoveUMG("UI_Loading2")
        MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')
        if self.OnLeaveBuildLevelCallBack then
            local obj = self.OnLeaveBuildLevelCallBack[1]
            local func = self.OnLeaveBuildLevelCallBack[2]
            func(obj)
            self.OnLeaveBuildLevelCallBack = nil
        end

        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        local player = gameMode:BPI_GetPlayer()
        if player then
            local springArmComp = player:GetComponentByClass(UE.USpringArmComponent)
            if springArmComp then
                springArmComp.bEnableCameraLag = true
                springArmComp.bDoCollisionTest = true 
            end
            player:SetActorHiddenInGame(false)
            player:SetActorEnableCollision(true)
            if not UE.UGameplayStatics.ObjectIsA(player, LoadClass('/Game/_Game/Blueprints/BuildingSystem/Blueprints/Interactables/BP_BuildActor.BP_BuildActor_C')) then
                player.CharacterMovement:SetActive(true, false)
            end
        end
    end))
    -- print("--------------离开家装场景完成")
    
    -- MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')
    -- if self.OnLeaveBuildLevelCallBack then
    --     local obj = self.OnLeaveBuildLevelCallBack[1]
    --     local func = self.OnLeaveBuildLevelCallBack[2]
    --     func(obj)
    -- end
end
---------------------------------------------------------------

---------------------------------------------------------------
---创建建筑
function M:CreateBuildHome()
    --加载历史建筑
    self.AllBuildActors = {}
    local buildPosList = {}
    local buildPosActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "BuildPos")
    for i = 1, buildPosActors:Length() do 
        local buildActor = buildPosActors:Get(i)
        buildPosList[buildActor.BuildPosIndex] = buildActor
    end
    local BuildSystem = require('Module.BuildSystem.BuildSystem')
    local buildInfo = BuildSystem:GetInstance().BuildInfo
    for _, info in pairs(buildInfo) do
        if info and info.item_id and info.item_id > 0 then
            local posIndex = tonumber(info.posIndex)

            local d_bag_item_furniture = require('ClientDatas.d_bag_item_furniture')
            local config = d_bag_item_furniture[info.item_id]
            if config then
                local actorPath = config.actorPath
                -- if not string.endswith(actorPath, "_C'") then
                    actorPath = string.sub(actorPath, 1, -2) .. "_C'"
                -- end
    
                --坐标信息
                local posActor = buildPosList[posIndex]
                if posActor then
                    posActor:SetActorHiddenInGame(true)
                    posActor:SetActorEnableCollision(false)
                end
                
                if posActor and actorPath ~= '' then
                    local buildActor = BuildSystem:GetInstance():GetCharacterMeshFromCache(self:GetWorld(), actorPath)
                    buildActor:K2_SetActorTransform(posActor:GetTransform(), false, nil, false)
                    buildActor.ID = info.item_id
                    buildActor.SkinId = info.skinId
                    if buildActor.InitDress then
                        buildActor:InitDress(true)
                    end
                    self.AllBuildActors[posIndex] = buildActor
                end
            end
        end
    end
end

function M:ClearBuildHome()
    if self.AllBuildActors then
        for _, actor in pairs(self.AllBuildActors) do
            actor:K2_DestroyActor()
        end
        self.AllBuildActors = {}
    end

    local triggerActors = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.ATriggerBox)
    for i = 1, triggerActors:Length() do 
        local actor = triggerActors:Get(i)
        if actor then
            actor.OnActorBeginOverlap:Clear()
        end
    end
end

function M:SaveBuildActorInfo()
    local buildInfo = {}
    for posIndex, actor in pairs(self.AllBuildActors) do
        print("---pos:" .. tostring(posIndex) .. ',id' .. tostring(actor.ID))

        local tab = {
            posIndex = posIndex,
            skinId = actor.SkinId
        }
        local rapidjson = require "rapidjson"
        local jsonStr = rapidjson.encode(tab)

        table.insert(buildInfo, {
            item_id = actor.ID,
            blob = tostring(jsonStr),
        })
    end
    local BuildSystem = require('Module.BuildSystem.BuildSystem')
    BuildSystem:GetInstance():ReqBuildHome(buildInfo)
end

---------------------------------------------------------------

function M:HiddenStaticMeshActorByTag(tag, type, bHiddenInGame, bNotFindAllChild)
    local actorList = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, type, tag)
    if actorList:Length() > 0 then
        for i = 1, actorList:Length() do
            local actor = actorList:Get(i)
            actor:SetActorHiddenInGame(bHiddenInGame)
            actor:SetActorEnableCollision(not bHiddenInGame)
            if not bNotFindAllChild then
                local attachedActors = UE.TArray(UE.AActor)
                actor:GetAttachedActors(attachedActors, true, false)
                for i = 1, attachedActors:Length() do 
                    local attachActor = attachedActors:Get(i)
                    attachActor:SetActorHiddenInGame(bHiddenInGame)
                    attachActor:SetActorEnableCollision(not bHiddenInGame)
                end
            end
        end
    end
end

---------------------------------------------------------------
--- 进入地铁站逻辑
function M:LoadStationScene(bFreeInStationScene, isRecover)
    if self.BP_PlayerController_City_UniverseBridge then
        self.BP_PlayerController_City_UniverseBridge.BlockSpecialSkill = true 
    end
    self.IsFreeInStationScene = bFreeInStationScene
    --隐藏一些额外的飞船,模型 
    self:HiddenStaticMeshActorByTag('flybox_coli', UE.AStaticMeshActor, true)
    self:HiddenStaticMeshActorByTag('MainFly', UE.ASkeletalMeshActor, true)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = self:K2_GetPawn()
    if player then
        if not isRecover then
           
            gameInstance.OnEnterStationPlayerPos = player:GetTransform()
        end
        gameMode:BPI_SetPlayer(player)
        player:SetActorEnableCollision(false)
        player:SetActorHiddenInGame(true)
        player.Mesh:SetEnableGravity(false)
        player.CharacterMovement:SetActive(false, false)
        -- self:UnPossess()
        local springArmComp = player:GetComponentByClass(UE.USpringArmComponent)
        if springArmComp then
            springArmComp.bEnableCameraLag = false
            springArmComp.bDoCollisionTest = false 
        end
    else
        gameInstance:CreateDefaultCharacterInCity()
    end
    
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
    UE.UGameplayStatics.GetGameInstance(self):EnterStreamingLevel({ 'City1Station' }, false, isRecover, { self, function() 
        local gameMode = UE.UGameplayStatics.GetGameMode(self)

        --UI相关
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:GetUMG('UI_City')
        if ui then
            gameInstance:RemoveUMG('UI_City')
            self.BP_PlayerController_City_UniverseBridge.UI_City = nil
            self.UI_City = nil
        end
        -- local topUI = UIManager:GetInstance():GetTopUI()
        -- if topUI then
        --     UIManager:GetInstance():RemoveUI(topUI)
        -- end
    
        MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')
        local player = gameMode:BPI_GetPlayer()
        print('----------player:' .. tostring(player))
        if player then
            local playerStart = gameMode:FindPlayerStart(self, 'StationInPosition')
            if playerStart then
                print('--------->' .. tostring(playerStart:GetTransform()))
                player:K2_SetActorLocation(playerStart:K2_GetActorLocation() + UE.FVector(0, 0, 0), false, nil, false)
                player:K2_SetActorRotation(playerStart:K2_GetActorRotation(), false)
                local rotator = playerStart:K2_GetActorRotation()
                rotator = rotator - UE.FRotator(0, -20, 0)
                self:SetControlRotation(rotator)
            else
                
            end
        end

        self.bIsInStationScene = true
       
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.3)

            local springArmComp = player:GetComponentByClass(UE.USpringArmComponent)
            if springArmComp then
                springArmComp.bEnableCameraLag = true
                springArmComp.bDoCollisionTest = true 
            end
            local player = gameMode:BPI_GetPlayer()
            if player then
                player:SetActorEnableCollision(false)
                player:SetActorHiddenInGame(true)
                player.Mesh:SetEnableGravity(false)
                player.CharacterMovement:SetActive(true, false)
            end
            
            local topUI = gameInstance:GetTopUI(false)
            if topUI then
                UIManager:GetInstance():RemoveUI(topUI) 
            end
            gameInstance:AddUMG('UI_TrainStation')
            local ui = gameInstance:GetUMG('UI_TrainStation')
            if ui then
                ui:OnInitAnimation()
            end
            gameInstance:RemoveUMG("UI_Loading2")
        end))

        -- local gameMode = UE.UGameplayStatics.GetGameMode(self)
        -- local player = gameMode:BPI_GetPlayer()
        -- if player then
        --     self.OnPossessedPawnChanged:Add(self, self.OnLoadStationSceneEnd)
        --     self:Possess(player)
        -- end
    end })
end

function M:OnLoadStationSceneEnd()
    self.OnPossessedPawnChanged:Remove(self, self.OnLoadStationSceneEnd)

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        player:SetActorEnableCollision(true)
        player:SetActorHiddenInGame(false)
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        local playerStart = gameMode:FindPlayerStart(self, 'StationInPosition')
        if playerStart then
            player:K2_SetActorTransform(playerStart:GetTransform(), false, nil, false)
            local rotator = playerStart:K2_GetActorRotation()
            rotator = rotator - UE.FRotator(0, -20, 0)
            self:SetControlRotation(rotator)
            player.Mesh:SetEnableGravity(true)
            player.CharacterMovement:SetActive(false, false)
        end
    end

    MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')

    self.BP_ScreenFade:FadeOut(false)
    self.bIsInStationScene = true
end

function M:UnloadStationScene(callback)
    self.UnloadStationSceneCallBack = callback
    self:HiddenStaticMeshActorByTag('flybox_coli', UE.AStaticMeshActor, false)
    self:HiddenStaticMeshActorByTag('MainFly', UE.ASkeletalMeshActor, false)

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
    local topUI = gameInstance:GetUMG('UI_TrainStation')
    if topUI then
        UIManager:GetInstance():RemoveUI(topUI)
    end

    local player = self:K2_GetPawn()
    if player then
        gameMode:BPI_SetPlayer(player)
        player:SetActorEnableCollision(false)
        player:SetActorHiddenInGame(true)
        player.Mesh:SetEnableGravity(false)
        player.CharacterMovement:SetActive(false, false)
        self:UnPossess()

        local springArmComp = player:GetComponentByClass(UE.USpringArmComponent)
        if springArmComp then
            springArmComp.bEnableCameraLag = false
            springArmComp.bDoCollisionTest = false 
        end
    end
    UE.UGameplayStatics.GetGameInstance(self):LeaveStreamingLevel(false, { self, function()
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:AddUMG('UI_City')
        --UI相关
        self.BP_PlayerController_City_UniverseBridge.UI_City = ui
        self.UI_City = ui
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        local player = gameMode:BPI_GetPlayer()
        if player then
            self.OnPossessedPawnChanged:Add(self, self.OnUnloadStationSceneEnd)
            self:Possess(player)
        end 
    end })
end

function M:OnUnloadStationSceneEnd()
    self.OnPossessedPawnChanged:Remove(self, self.OnUnloadStationSceneEnd)
    if self.BP_PlayerController_City_UniverseBridge then
        self.BP_PlayerController_City_UniverseBridge.BlockSpecialSkill = false 
    end

    local player = self:K2_GetPawn()
    if player then
        -- self:SetViewTargetWithBlend(player, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
       
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        if self.IsFreeInStationScene then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            print("------->OnEnterStationPlayerPos:" .. tostring(gameInstance.OnEnterStationPlayerPos))
            if gameInstance.OnEnterStationPlayerPos then
                player:K2_SetActorTransform(gameInstance.OnEnterStationPlayerPos, false, nil, false)
            end
        else
            local playerStart = gameMode:FindPlayerStart(self, 'LeaveTrainPosition')
            if playerStart then
                player:K2_SetActorTransform(playerStart:GetTransform(), false, nil, false)
                local rotator = playerStart:K2_GetActorRotation()
                rotator = rotator - UE.FRotator(0, -20, 0)
                self:SetControlRotation(rotator)
            end
        end
    end
    self.bIsInStationScene = false
    MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')
    coroutine.resume(coroutine.create(function()
        UE.UKismetSystemLibrary.Delay(self, 0.3)
        -- self.BP_ScreenFade:FadeOut(false)
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        local player = gameMode:BPI_GetPlayer()
        if player then
            local springArmComp = player:GetComponentByClass(UE.USpringArmComponent)
            if springArmComp then
                springArmComp.bEnableCameraLag = true
                springArmComp.bDoCollisionTest = true 
            end
            player:SetActorHiddenInGame(false)
            player:SetActorEnableCollision(true)
            if not UE.UGameplayStatics.ObjectIsA(player, LoadClass('/Game/_Game/Blueprints/BuildingSystem/Blueprints/Interactables/BP_BuildActor.BP_BuildActor_C')) then
                player.CharacterMovement:SetActive(true, false)
            end
        end

        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        print("-------->DelayHideUILoading2:" .. tostring(self.DelayHideUILoading2))
        if self.DelayHideUILoading2 then
            self.DelayHideUILoading2 = false
            
        else
            gameInstance:RemoveUMG("UI_Loading2")
        end

        self.bIsInStationScene = false
        if self.UnloadStationSceneCallBack then
            local obj = self.UnloadStationSceneCallBack[1]
            local func = self.UnloadStationSceneCallBack[2]
            func(obj)
            self.UnloadStationSceneCallBack = nil
        end
    end))
    self.bIsInStationScene = false
end

function M:OnEnterStateTree()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    --判断当前剧情任务是否需要播下船动画
    local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
    local new_mission_id = 0
    local in_city = false
    local no_jump = false
    if saveGameSpeak.SubMissionIds:Length() > 0 then
        local mission_id = saveGameSpeak.SubMissionIds:Get(1)
        local config = Database.Query('d_task_story', mission_id)
        if config then
            new_mission_id = mission_id
            if config.inCity == 1 then
                in_city = true
            else
                in_city = false
            end

            if config.unJump == 1 then
                no_jump = true
            else
                no_jump = false
            end
        end
    end

    if new_mission_id == 0 then
        if saveGameSpeak.MissionIds:Length() > 0 then
            local mission_id = saveGameSpeak.MissionIds:Get(1)
            local config = Database.Query('d_task_story', mission_id)
            if config then
                new_mission_id = mission_id
                if config.inCity == 1 then
                    in_city = true
                else
                    in_city = false
                end

                if config.unJump == 1 then
                    no_jump = true
                else
                    no_jump = false
                end
            end
        end
    end

    if not in_city then
        self:InitUI()
        self.BP_StateTree:SetStateTree(gameInstance.PlotStateTree)
        self.BP_StateTree:StartLogic()
        if UE.UKismetSystemLibrary.IsValid(self.LevelSequencePlayer) then
            self.LevelSequencePlayer:Stop()
            self.LevelSequencePlayer = nil
        end
        -- self:InitUI()

        --在transcondition里removeumg
        -- gameInstance:AddUMG("UI_Loading2", nil, 1)
    end

    if gameInstance.JumpFromUINodeTree then
        --通过剧情树UI跳转
        self.LoadStateTreeAfterEnterGameEnd = false
        self.StateTreeNoJump = false
        gameInstance.JumpFromUINodeTree = false
        LOG_DEBUG_TRACKBACK("self.StateTreeNoJump", self.StateTreeNoJump, "mission_id", new_mission_id, in_city)
        return false
    else
        self.LoadStateTreeAfterEnterGameEnd = in_city
        self.StateTreeNoJump = no_jump
        LOG_DEBUG_TRACKBACK("self.StateTreeNoJump", self.StateTreeNoJump, "mission_id", new_mission_id, in_city)
    end
    return in_city
end

--播放主城飞船开门动画
function M:PlayFlyOpenSequence() 
    if self.LevelSequencePlayer then
        self.LevelSequencePlayer:Stop()
        self.LevelSequencePlayer = nil
    end
    if self.LevelSequenceActor then
        self.LevelSequenceActor:K2_DestroyActor()
        self.LevelSequenceActor = nil
    end

    local MainFlys = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ASkeletalMeshActor, "MainFly")
    if MainFlys:Length() > 0 then
        local mainFlyActor = MainFlys:Get(1)
        mainFlyActor.SkeletalMeshComponent:PlayAnimation(LoadObject("/Game/_Game/Characters/perform/anim/Share_leavescene_fly_open_LR.Share_leavescene_fly_open_LR"), false)
    end
end

function M:ClearLoopSequence()
    if self.LevelSequencePlayer then
        self.LevelSequencePlayer:Stop()
        self.LevelSequencePlayer = nil
    end
    if self.LevelSequenceActor then
        self.LevelSequenceActor:K2_DestroyActor()
        self.LevelSequenceActor = nil
    end
end

---------------------------------------------------------------
return M