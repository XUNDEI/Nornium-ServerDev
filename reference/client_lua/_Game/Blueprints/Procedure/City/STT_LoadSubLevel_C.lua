--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require '_Game.Utils.Database'

---@type STT_LoadSubLevel_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState(Transition)
    --如果task story配置了不跳转 就不卸载多余场景
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_ScreenFade.DisableLoadingAnim = true

    if not gameInstance.firstMission then
        if playerController.StateTreeNoJump then
            self.Completed = true
        else
            self:UnloadOtherLevel()
        end
    else
        self:UnloadOtherLevel()
    end
end

function M:ReceiveExitState()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if self.registered_stream_level then
        self.registered_stream_level.OnLevelShown:Remove(self, self.OnLevelShown)
        self.registered_stream_level = nil
    end
    gameInstance.OnStreamLevelLoaded:Remove(self, self.OnLevelLoaded)
    gameInstance.OnStreamLevelUnloaded:Remove(self, self.UnloadNextLevel)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_ScreenFade.DisableLoadingAnim = false
    -- local ui = gameInstance:GetUMG('UI_StreamLoading')
    -- if ui and UE.UKismetSystemLibrary.IsValid(ui) then
    --     UIManager:GetInstance():RemoveUI(ui)
    -- end
    -- if self.LoadingUI and UE.UKismetSystemLibrary.IsValid(self.LoadingUI) then
    --     gameInstance:RemoveUMG("UI_Loading2")
    -- end
end

function M:ReceiveLatentTick(DeltaTime)
    if not self.Completed then return end
    local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ASkeletalMeshActor, "MainFly")
    for i = 1, actors:Num() do
        ---@type UE.ASkeletalMeshActor
        local actor = actors[i]
        actor:K2_GetRootComponent():SetVisibility(false, true)
        actor.SkeletalMeshComponent:SetCollisionProfileName("Spectator", true)
    end
    local actor_class = LoadClass("/Game/_Game/Blueprints/Levels/BP_IronArmLow.BP_IronArmLow_C")
    local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, actor_class, "BP_IronArmLow")
    for i = 1, actors:Num() do
        ---@type BP_IronArmLow_C
        local actor = actors[i]
        actor:K2_GetRootComponent():SetVisibility(false, true)
    end
    local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AStaticMeshActor, "flybox_coli")
    for i = 1, actors:Num() do
        ---@type UE.AStaticMeshActor
        local actor = actors[i]
        actor:K2_GetRootComponent():SetVisibility(false, true)
        actor.StaticMeshComponent:SetCollisionProfileName("Spectator", true)
    end
    self:FinishTask(true)
end

function M:ExecTask()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if not gameInstance then return end
    local load_level_names = gameInstance:GetLoadLevelName()
    if load_level_names:Num() > 0 then
        for i = 1, load_level_names:Num() do
            self.LevelName:Add(load_level_names[i])
        end
    end
    if self.LevelName:Num() > 0 then
        for i = 1, self.LevelName:Num() do
            local level_name = self.LevelName[i]
            if level_name == "SC000006" or level_name == "SC000005" then
                self.WithoutUILoadingName:Add(level_name)
            else
                local stream_level = UE.UGameplayStatics.GetStreamingLevel(self, level_name)
                if not (stream_level and stream_level:IsLevelLoaded() and stream_level:IsLevelVisible()) then
                    self.WithUILoadingName:Add(level_name)
                end
            end
        end
        local tempLevelName = self.levelName:ToTable()
        local tempWithoutUILoadingName = self.WithoutUILoadingName:ToTable()
        local tempWithUILoadingName = self.WithUILoadingName:ToTable()
        if self.WithoutUILoadingName:Length() == 0 or gameInstance.bPlotSystemRemoveAllUI then
            self:ShowLoading()
        else
            local ui = gameInstance:GetUMG('UI_Loading2')
            if ui then
                ui:CancelDelayDestroy()
            end
        end
        gameInstance.bPlotSystemRemoveAllUI = false
       
        self.LoadCount = self.LevelName:Num()
        LOG_DEBUG("STT_LoadSubLevel_C::ExecTask", self.LoadCount)
        local level_name = self.LevelName[self.LoadCount]
        local stream_level = UE.UGameplayStatics.GetStreamingLevel(self, level_name)
        if stream_level and stream_level:IsLevelLoaded() then
            if stream_level:IsLevelVisible() then
                self:OnlLoadNextLevel("")
            else
                self.registered_stream_level = stream_level
                stream_level.OnLevelShown:Add(self, self.OnLevelShown)
                gameInstance:StreamLevelSetShouldBeVisible(level_name, true)
            end
        else
            gameInstance.OnStreamLevelLoaded:Add(self, self.OnLevelLoaded)
            gameInstance:LoadStreamLevel(level_name)
        end
    else
        self.Completed = true
    end
end

function M:OnLevelShown()
    if self.registered_stream_level then
        self.registered_stream_level.OnLevelShown:Remove(self, self.OnLevelShown)
        self.registered_stream_level = nil
    end
    self:OnlLoadNextLevel("")
end

function M:OnLevelLoaded(LevelName)
    LOG_DEBUG("STT_LoadSubLevel_C::OnLevelLoaded", LevelName)
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.OnStreamLevelLoaded:Remove(self, self.OnLevelLoaded)
    local plot_level_names = gameInstance.PlotLevelsName
    local index = plot_level_names:Find(LevelName)
    if index < 1 then
        plot_level_names:Add(LevelName)
    end
    self:OnlLoadNextLevel("")
end

function M:LoadLevel(LevelName)
    local stream_level = UE.UGameplayStatics.GetStreamingLevel(self, LevelName)
    if stream_level:IsLevelLoaded() then
        if stream_level:IsLevelVisible() then
            self:OnlLoadNextLevel("")
        else
            LOG_DEBUG("STT_LoadSubLevel_C::LoadLevel", LevelName)
            self.registered_stream_level = stream_level
            stream_level.OnLevelShown:Add(self, self.OnLevelShown)
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            gameInstance:StreamLevelSetShouldBeVisible(LevelName, true)
        end
    else
        LOG_DEBUG("STT_LoadSubLevel_C::LoadLevel", LevelName)
        ---@type BP_GameInstance_C
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.OnStreamLevelLoaded:Add(self, self.OnLevelLoaded)
        gameInstance:LoadStreamLevel(LevelName)
    end
end

function M:OnlLoadNextLevel(LevelName)
    self.LoadCount = self.LoadCount - 1
    LOG_DEBUG_TRACKBACK("OnlLoadNextLevel", LevelName, self.LoadCount)
    if self.LoadCount > 0 then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:GetUMG('UI_Loading2')
        if ui then
            ui:CancelDelayDestroy()
        end
        local level_name = self.LevelName[self.LoadCount]
        self:LoadLevel(level_name)
    else
        self:HideLoading()
        self.Completed = true
    end
end

function M:UnloadOtherLevel()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- local loadedLevels = UE.TArray(UE.FName)
    local loadedLevels = select(3, UE.UGHSFunctionLibrary.LSS_Plugin_GetStreamingLevelsInfo(gameInstance))
    -- print("loadedLevels", loadedLevels:Num())
    for i = 1, loadedLevels:Num() do
        local level_name = loadedLevels[i]
        local index = self.LevelName:Find(level_name)
        if index < 1 then
            self.UnloadLevelName:Add(level_name)
        end
    end
    if self.UnloadLevelName:Num() > 0 then
        self:ShowLoading()
        gameInstance.OnStreamLevelUnloaded:Add(self, self.UnloadNextLevel)
        gameInstance:UnloadStreamLevel(self.UnloadLevelName[1])
    else
        self:ExecTask()
    end
end

function M:UnloadNextLevel()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.OnStreamLevelUnloaded:Remove(self, self.UnloadNextLevel)
    self.UnloadLevelName:Clear()
    self:UnloadOtherLevel()
end

function M:ShowLoading()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetOrAddUMG("UI_Loading2")
    if ui then
        ui:CancelDelayDestroy()
    end
end

function M:HideLoading()
    print("-->hideLoading")
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG("UI_Loading2")
    if ui then
        ui:DelayDestroy()
    end
end

return M
