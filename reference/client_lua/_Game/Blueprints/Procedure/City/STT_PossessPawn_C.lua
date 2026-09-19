--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require '_Game.Utils.UIUtils'
local PlotSystem = require "Module.Plot.PlotSystem"
local PlayerSystem = require('Module.Player.PlayerSystem')
local Database = require "_Game.Utils.Database"

---@type STT_PossessPawn_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState()
    self.executing = false
    if not PlotSystem:GetInstance().STTEnteringLevel then
        self:ExecTask()
    end
    MessageManager:GetInstance():AddListener("OnMsg_Res_Mall_Receive_Month_Card", self)
end

function M:ReceiveLatentExitState(Transition)
    MessageManager:GetInstance():RemoveListener("OnMsg_Res_Mall_Receive_Month_Card", self)
    self.Overridden.ReceiveLatentExitState(self, Transition)
end

function M:ReceiveLatentTick()
    if self.executing then return end
    if not PlotSystem:GetInstance().STTEnteringLevel then
        self:ExecTask()
    end
end

function M:ExecTask()
    if self.MissionId and self.MissionId > 0 then
        local plot_info = PlotSystem:GetInstance().PlotInfo
        local bFinished = false
        local task_info = Database.Query("d_task_story", self.MissionId)
    
        if task_info.taskType == UIUtils.ETaskType.Main then --主线
            for _, completed_mission_id in ipairs(plot_info.node_completed_mission_ids) do
                --当前节点已完成任务
                if completed_mission_id == self.MissionId then
                    bFinished = true
                    self.Complete = true
                    self:FinishTask(true)
                    return 
                end
            end
        elseif task_info.taskType == UIUtils.ETaskType.Tutorial then --教学
            for _, completed_mission_id in ipairs(plot_info.node_completed_mission_ids) do
                --当前节点已完成任务
                if completed_mission_id == self.MissionId then
                    bFinished = true
                    self.Complete = true
                    self:FinishTask(true)
                    return 
                end
            end
            for _, completed_mission_id in ipairs(plot_info.completed_mission_ids) do
                --已完成任务
                if completed_mission_id == self.MissionId then
                    bFinished = true
                    self.Complete = true
                    self:FinishTask(true)
                    return 
                end
            end
        end
    end
   

    self.executing = true
    self.skipPossess = false
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.IsSTTLoading = true
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if gameInstance.firstMission then
        if playerController.LoadStateTreeAfterEnterGameEnd then
            playerController.LoadStateTreeAfterEnterGameEnd = false
            self.skipPossess = true
            -- self:ShowNodeReward()
            self:ShoWTutorial()
        end
    else
        -- if playerController.StateTreeNoJump then
        --     self.skipPossess = true
        --     -- self:ShowNodeReward()
        --     self:ShoWTutorial()
        -- end
    end

    if not self.skipPossess then
        self:StartPossessPawn()
    end
end

function M:ShowNodeReward()
    local UI_GetItem_Notice = PlotSystem:GetInstance():ShowNodeReward()
    --有节点奖励
    if UI_GetItem_Notice then
        UI_GetItem_Notice.callback = function()
            -- self:ShoWTutorial()
            self:ShowMonthCardReward()
        end
    else
        -- self:ShoWTutorial()
        self:ShowMonthCardReward()
    end
end

function M:ShoWTutorial()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local tutorial_ids = PlotSystem:GetInstance().TutorialIds
    if tutorial_ids and #tutorial_ids > 0 then
        --有教学 点击关闭节点奖励之后 显示教学
        local IsCurrentlyShowingLoadingScreen = gameInstance:IsCurrentlyShowingLoadingScreen()
        if IsCurrentlyShowingLoadingScreen then
            coroutine.resume(coroutine.create(function()
                local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
                playerController:DisableInput()
                UE.UKismetSystemLibrary.Delay(self, 2)
                playerController:EnableInput()
                gameInstance:RemoveUMG("UI_Loading2")
                gameInstance:ShowTutorial(tutorial_ids[1], true)
                MessageManager:GetInstance():AddListener("Finished_Tutorial", self)
            end))
        else
            coroutine.resume(coroutine.create(function()
                local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
                playerController:DisableInput()
                UE.UKismetSystemLibrary.Delay(self, 1)
                playerController:EnableInput()
                gameInstance:RemoveUMG("UI_Loading2")
                gameInstance:ShowTutorial(tutorial_ids[1], true)
                MessageManager:GetInstance():AddListener("Finished_Tutorial", self)
            end))
            -- gameInstance:ShowTutorial(tutorial_ids[1], true)
            -- MessageManager:GetInstance():AddListener("Finished_Tutorial", self)
        end
    else
        --没有教学 判断是否有月卡奖励
        -- self:ShowMonthCardReward()
        self:ShowNodeReward()
    end
end

function M:ShowMonthCardReward()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.MonthCardItems and #gameInstance.MonthCardItems > 0 then
        local ui = gameInstance:AddUMG('UI_TopUp_MonthCard_GetItem')
        ui:RefreshUI(gameInstance.MonthCardItems)
        gameInstance.MonthCardItems = {}
    end
end

function M:Finished_Tutorial()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    table.remove(PlotSystem:GetInstance().TutorialIds, 1)
    local tutorial_ids = PlotSystem:GetInstance().TutorialIds
    if tutorial_ids and #tutorial_ids > 0 then
        gameInstance:ShowTutorial(tutorial_ids[1], true)
    else
        MessageManager:GetInstance():RemoveListener("Finished_Tutorial", self)
        --教学之后显示月卡奖励
        -- self:ShowMonthCardReward()
        self:ShowNodeReward()
    end
end

function M:StartPossessPawn()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui_loading2 = gameInstance:GetUMG('UI_Loading2')
    if ui_loading2 then
        ui_loading2:DelayDestroy()
    end

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    self:SetPostProcess()
    local playerStarts = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.APlayerStart, self.PlayerStartTag)
    if playerStarts:Length() > 0 then
        local transform = playerStarts:Get(1):GetTransform()
        self.SpawnTransform = transform
    end
    
    if self.MasterCharacter then
        local charId = gameInstance:GetPlayerCharacterIdInCity()
        self.Character = gameInstance:GetCityCharacterClass(charId)
        LOG_DEBUG_TRACKBACK("==========StartPossessPawn.MasterCharacter:" .. tostring(charId))
    else
        local LoadedCharacterClass = UE.UKismetSystemLibrary.Conv_SoftClassReferenceToClass(self.CharacterClass)
        if not UE.UKismetSystemLibrary.IsValidClass(LoadedCharacterClass) then
            UE.UKismetSystemLibrary.LoadClassAsset_Blocking(self.CharacterClass)
            LoadedCharacterClass = UE.UKismetSystemLibrary.Conv_SoftClassReferenceToClass(self.CharacterClass)
        end
        self.Character = LoadedCharacterClass
    end

    if UE.UKismetSystemLibrary.IsValidClass(self.Character) then
        local pawn = UE.UGameplayStatics.GetActorOfClass(self, self.Character)

        --拿记录位置数据
        local player_transform = {}
        local playerInfo = PlayerSystem:GetInstance().PlayerInfo
        if playerInfo and #playerInfo.player_transform_in_scenes > 0 then
            local transform_in_scene = playerInfo.player_transform_in_scenes[1]
            local trans = UE.UKismetMathLibrary.MakeTransform(
                UE.FVector(transform_in_scene.location[1], transform_in_scene.location[2], transform_in_scene.location[3]),
                UE.FRotator(0, transform_in_scene.yaw, 0),
                UE.FVector(1, 1, 1))
            playerController:SetControlRotation(UE.FRotator(0, 0, 0))
            player_transform = trans

            --清除位置信息
            local scene_id = transform_in_scene.scene_id
            local msg = {}
            msg.scene_ids = { scene_id }
            LOG_DEBUG("req_remove_player_transform_in_scene", scene_id)
            Client.send("req_remove_player_transform_in_scene", msg)
        else
            player_transform = self.SpawnTransform
        end

        if UE.UKismetSystemLibrary.IsValid(pawn) then
            self.PawnRef = pawn
            self.PawnRef:K2_SetActorTransform(player_transform, false, nil, false)
        else
            self.PawnRef = self:GetWorld():SpawnActor(self.Character,
                player_transform,
                UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
                self, self)
            LOG_DEBUG("SpawnActor", self.Character:GetName())
            gameInstance.Walk = false
            --判断下是否换肤
            if self.MasterCharacter then
                local gameMode = UE.UGameplayStatics.GetGameMode(self)
                gameMode:BPI_SetPlayer(self.PawnRef)
                gameInstance:ChangeDress()
            end
        end
    end
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    gameMode.Player = self.PawnRef
    UIManager:GetInstance():ClearInteractOption()
    UIManager:GetInstance():SetForceShowCursor(false)
    -- ---@type UE.USpringArmComponent
    -- local sr = self.PawnRef:GetComponentByClass(UE.USpringArmComponent:StaticClass())
    -- if sr then
    --     sr.bEnableCameraLag = false
    --     coroutine.resume(coroutine.create(function()
    --         UE.UKismetSystemLibrary.Delay(self, 0.1)
    --         sr.bEnableCameraLag = true
    --     end))
    -- end
    playerController:Possess(self.PawnRef)
    playerController:InitUI()
    playerController:ShowUI()
    -- playerController:EnableInput()
    if self.HideCityUI then
        local ui_city = gameInstance:GetUMG("UI_City")
        if ui_city then
            gameInstance:RemoveUMG("UI_City")
            -- UIManager:GetInstance():RemoveUI(ui_city)
        end
        -- local topUI = UIManager:GetInstance():GetTopUI()
        -- local UICityClass = UE.LoadClass('/Game/_Game/Blueprints/UI/UI_City.UI_City_C')
        -- if UE.UGameplayStatics.ObjectIsA(topUI, UICityClass) then
        --     UIManager:GetInstance():RemoveUI(topUI)
        -- end
    end

    if self.HideCityMenuButton then
        local ui_city = gameInstance:GetUMG("UI_City")
        if ui_city then
            ui_city.UI_MenuButton:SetVisibility(UE.ESlateVisibility.Hidden)
            ui_city.UI_Key_Esc:SetVisibility(UE.ESlateVisibility.Hidden)
            ui_city.BuildButton:SetVisibility(UE.ESlateVisibility.Hidden)
            ui_city.BackButton:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    else
        local ui_city = gameInstance:GetUMG("UI_City")
        if ui_city then
            ui_city.UI_MenuButton:SetVisibility(UE.ESlateVisibility.Visible)
            ui_city.UI_Key_Esc:SetVisibility(UE.ESlateVisibility.Visible)
        end
    end

    self.PawnRef:SetActorEnableCollision(true)
    self.PawnRef:SetActorHiddenInGame(false)
    self.PawnRef.CharacterMovement:SetActive(true, false)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance and self.RemoveUILoading then
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 1)
            gameInstance:RemoveUMG('UI_StreamLoading')
        end))
    end
    local QuestSystem = require "Module.Quest.QuestSystem"
    if QuestSystem.TrackQuestId ~= 100030018 then
        gameInstance:RemoveUMG("UI_Loading2")
    end 
    
    -- self:ShowNodeReward()
    -- playerController.BP_ScreenFade.OnFadeOutFinished:Add(self, function()
        playerController:EnableInput()
        self:ShoWTutorial()
    -- end)
    -- playerController.BP_ScreenFade:FadeOut(false, true)
    -- playerController.BP_ScreenFade:PauseFade()
    -- coroutine.resume(coroutine.create(function()
    --     UE.UKismetSystemLibrary.Delay(self, 0.3)
    --     playerController.BP_ScreenFade:ResumeFade()
    -- end))
end

function M:OnMsg_Res_Mall_Receive_Month_Card()
    self:ShowMonthCardReward()
end

return M
