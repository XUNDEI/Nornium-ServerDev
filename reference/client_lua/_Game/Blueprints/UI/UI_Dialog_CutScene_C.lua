--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"

local UIUtils = require "_Game.Utils.UIUtils"
local CutsceneTable = require "ClientDatas.d_story_cutscene"
local CutsceneSubTable = require "ClientDatas.d_story_cutscene_sub"
local Database = require "_Game.Utils.Database"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Dialog_CutScene_C
local UI_Dialog_CutScene_C = Class()

UI_Dialog_CutScene_C.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(UI_Dialog_CutScene_C)
local EPlayType =
{
    Media = 0,
    Sequence = 1,
}

--构造函数
function UI_Dialog_CutScene_C:Construct()
    self.IsPause = true
    self.PlayTime = 0
    self.AudioComp = nil
    self.PlayingAudioPath = ""
    self.FirstShow = true
    -- self.SKIP:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.SKIP.OnClicked:Add(self, UI_Dialog_CutScene_C.OnClicked_SKIP)
end

function UI_Dialog_CutScene_C:Destruct()
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
    end
    self.AudioComp = nil
end

function UI_Dialog_CutScene_C:InitUI(id)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.OnPlayDialogCutScene then
        playerController:OnPlayDialogCutScene(true)
    end
    self:ShowContext("")
    self.SKIP:SetVisibility(UE.ESlateVisibility.Visible)
    if not id or id == "" or not tonumber(id) then
        print("=====>>错误id UI_Dialog_CutScene_C:InitUI " .. tostring(id))
        self:IsPlayEnd()
        return
    end

    self.SubData = {}
    for _, v in pairs(CutsceneSubTable) do
        if v.playId == id then
            table.insert(self.SubData, v)
        end
    end
    self.SKIP:SetVisibility(UE.ESlateVisibility.Collapsed)
    ---创建视频播放
    local world = self:GetWorld()
    local transfrom = UE.UKismetMathLibrary.MakeTransform(UE.FVector(0, 0, 0), UE.FRotator(0, 0, 0), UE.FVector(1, 1, 1))
    local MediaPlayerActorPath = "Blueprint'/Game/_Game/Blueprints/MediaPlayer/MediaPlayerActor.MediaPlayerActor_C'"
    self.MediaPlayerActor = world:SpawnActor(UE.UClass.Load(MediaPlayerActorPath), transfrom, 
        UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local volume = gameInstance:GetSoundVolume(3) / 100 * gameInstance:GetSoundVolume(0) / 100
    print("--------->volume1:" .. tostring(gameInstance:GetSoundVolume(3) / 100) .. ', vloume2:' .. tostring(gameInstance:GetSoundVolume(0) / 100) .. ',v:' .. tostring(volume))
    self.MediaPlayerActor.MediaSound:SetVolumeMultiplier(volume)

    local data = CutsceneTable[id]
    self.CurData = data
    if not data or not data.cutScenePath and data.cutScenePath == "" then
        print("=====>>错误id 在配置表(ClientDatas.d_story_cutscene)中! " .. tostring(id))
        self:IsPlayEnd()
        return
    end

    if self.CurData.bgmCue ~= '' then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:ChangeBgm(self.CurData.bgmCue, self.CurData.bgmParameter)
    end

    if data.playType == EPlayType.Media then
        if data.skipButton == 1 then
            self.SKIP:SetVisibility(UE.ESlateVisibility.Visible)
        end
        self.Panel_Media:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local mediaSource = LoadObject(data.cutScenePath)
        print("===mediaSource:GetClass():" .. tostring(mediaSource and mediaSource:GetClass() or "nil"))
        if not mediaSource or mediaSource:GetClass() ~= UE.UFileMediaSource:StaticClass() then
            print("=====错误的资源配置类型:mediaSource:" .. tostring(id) .. ", PlayType:" .. tostring(data.playType) .. 
                ",Path:" .. tostring(data.cutScenePath))
            self:IsPlayEnd()
            return
        end
      
        self.MediaPlayer:OpenSource(mediaSource)
       
        self.MediaPlayer.OnEndReached:Clear()
        self.MediaPlayer.OnEndReached:Add(self, UI_Dialog_CutScene_C.OnPlayMediaEnd)

        self.IsPause = false
        self.PlayTime = 0
        gameInstance:RemoveUMG("UI_Loading2")
    elseif data.playType == EPlayType.Sequence then
        if self.CurData.SECue ~= '' then
            local strArr = string.split(self.CurData.SECue, '|')
            for i = 1, #strArr do
                local music = LoadObject(strArr[i])
                LOG_WARN(strArr[i], music)
            end
        end

        if data.skipButton == 1 then
            self.SKIP:SetVisibility(UE.ESlateVisibility.Visible)
        end
        self.Panel_Media:SetVisibility(UE.ESlateVisibility.Hidden)
        if self.CurData.mapPath ~= "" and self.LastMapPath ~= self.CurData.mapPath then
            print("=============mapPath:" .. tostring(self.CurData.mapPath))
            self.LastMapPath = self.CurData.mapPath

            local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            local player = PC:K2_GetPawn()
            if player then
                gameMode:BPI_SetPlayer(player)
    
                player:SetActorEnableCollision(false)
                -- player:SetActorHiddenInGame(true)
                player.CharacterMovement:SetActive(false, false)
            end

            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
            local mapNameList = string.split(self.CurData.mapPath, '|')
            gameInstance:EnterStreamingLevel(mapNameList, true, false, { self, self.OnLoadStreamLevelEnd })
        else
            self:OnLoadStreamLevelEnd()
        end
    else
        print("===配置路径错误!!!" .. tostring(id))
        self:IsPlayEnd()
        return
    end
end

function UI_Dialog_CutScene_C:OnLoadStreamLevelEnd()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2")
    gameInstance.UI_Loading2 = nil

    local levelSequence = LoadObject(self.CurData.cutScenePath)
    print("==levelSequence:GetClass():" .. tostring(levelSequence:GetClass()))
    if not levelSequence then--or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
        print("=====错误的资源配置类型:levelSequence:" .. tostring(self.CurData.id) .. ", PlayType:" .. tostring(self.CurData.playType) .. 
            ",Path:" .. tostring(self.CurData.cutScenePath))
        self:IsPlayEnd()
        return
    end
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation

    local LoopCount = UE.FMovieSceneSequenceLoopCount()
    LoopCount.Value = 0
    --配置
    local Settings = UE.FMovieSceneSequencePlaybackSettings()
    Settings.LoopCount = LoopCount

    local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, 
        Settings)

    self.sequencePlayerActor = levelSequenceActor
    self.sequencePlayerActorRef = UnLua.Ref(levelSequenceActor)
    self.sequencePlayerActor.CameraSettings = UE.FLevelSequenceCameraSettings()


    self.sequencePlayerActor.SequencePlayer.OnFinished:Clear()
    self.sequencePlayerActor.SequencePlayer.OnFinished:Add(self, UI_Dialog_CutScene_C.OnPlaySequenceEnd)

    self.LoadStreamLevelEnded = true
    -- self.sequencePlayerActor.SequencePlayer:Play()
    if gameInstance:CheckLevelSequenceBindings(self.sequencePlayerActor) then
        self.sequencePlayerActor_NeedPlay = 0.1
        self.sequencePlayerActor.SequencePlayer:Play()
        self.sequencePlayerActor.SequencePlayer:Pause()
        self.Played = true
        self:TickSubData()
    else
        self.sequencePlayerActor_NeedPlay = 0.1
        LOG_INFO("===等待绑定完成")
    end

    self.IsPause = false
    self.PlayTime = 0
end

function UI_Dialog_CutScene_C:ShowContext(Context)
    self.Text_Content:SetText(Context)
end

function UI_Dialog_CutScene_C:PlayAudio(audioPath)
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
    end
    self.AudioComp = nil
    --audioPath = "SoundCue'/Game/SuperGrid/TutorialLevel/SoundEffects/Cue_Lift.Cue_Lift'"
    if audioPath and audioPath ~= "" then
        self.PlayingAudioPath = audioPath
        local audioSource = LoadObject(audioPath)
        if audioSource then
            if UE.UGameplayStatics.ObjectIsA(audioSource, UE.USoundBase.StaticClass()) then
                self.AudioComp = UE.UGameplayStatics.SpawnSound2D(self, audioSource)
            else
                LOG_ERROR("===错误的音频资源类型:", audioPath)
            end
        end
    end
end

function UI_Dialog_CutScene_C:TickSubData()
    local index = -1
    for k, v in ipairs(self.SubData) do
        if self.PlayTime >= (v.timeTable / 10000 + v.duration / 10000) then
            self:ShowContext("")
            self.FirstShow = true
            index = k
            break
        elseif self.PlayTime >= (v.timeTable / 10000) then
            if self.FirstShow then
                self.FirstShow = false
                local showText = UIUtils.ReplacePlayerName(v.showText)
                self:ShowContext(showText)
                self:PlayAudio(v.soundCue)
            end
            break
        end
    end
    if index ~= -1 then
        table.remove(self.SubData, index)
    end
end

function UI_Dialog_CutScene_C:Tick(_, DeltaTime)
    if not self.LoadStreamLevelEnded then return end
    if self.sequencePlayerActor_NeedPlay then
        self.sequencePlayerActor_NeedPlay = self.sequencePlayerActor_NeedPlay - DeltaTime
        if self.sequencePlayerActor_NeedPlay > 0 then
            return
        end
        if self.Played then
            self.sequencePlayerActor.SequencePlayer:Play()
            self.sequencePlayerActor_NeedPlay = nil
            return 
        end
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance:CheckLevelSequenceBindings(self.sequencePlayerActor) then
            LOG_INFO("===绑定完成")
            self.sequencePlayerActor_NeedPlay = 0.1
            self.sequencePlayerActor.SequencePlayer:Play()
            self.sequencePlayerActor.SequencePlayer:Pause()
            self.Played = true
            self:TickSubData()
        end
        return
    end
    if not self.Played then return end
    if not self.IsPause then
        self.PlayTime = self.PlayTime + DeltaTime
        self:TickSubData()
    end
end

--暂停
function UI_Dialog_CutScene_C:Pause()
    self.IsPause = true
  
    if self.sequencePlayerActor then
        self.sequencePlayerActor.SequencePlayer:Pause()
    end

    if self.MediaPlayer then
        self.MediaPlayer:Pause()
    end

    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:SetPaused(true)
    end
    UE.UGameplayStatics.SetGlobalTimeDilation(self, 0)
    LOG_DEBUG_TRACKBACK("UE.UGameplayStatics.SetGlobalTimeDilation(self, 0)")
end

--恢复
function UI_Dialog_CutScene_C:Resume()
    if self.sequencePlayerActor then
        self.sequencePlayerActor.SequencePlayer:Play()
    end

    if self.MediaPlayer then
        self.MediaPlayer:Play()
    end

    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:SetPaused(false)
    end

    UE.UGameplayStatics.SetGlobalTimeDilation(self, 1)
    LOG_DEBUG_TRACKBACK("UE.UGameplayStatics.SetGlobalTimeDilation(self, 1)")

    self.IsPause = false
end

function UI_Dialog_CutScene_C:IsPlayEnd()
    print("-------UI_Dialog_CutScene_C:IsPlayEnd")
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- UIManager:GetInstance():ClearConfirm()
    if self.LastMapPath ~= '' then
        -- local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        -- pc.BP_ScreenFade:FadeIn(false)
        gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
        gameInstance:LeaveStreamingLevel(true, { self, self.OnBackLevel })
    else
        self:OnBackLevel()
    end
end

function UI_Dialog_CutScene_C:OnBackLevel()
    self.IsPause = true
    if UE.UGameplayStatics.IsValid(self.MediaPlayerActor) then
        self.MediaPlayerActor:K2_DestroyActor()
        self.MediaPlayerActor = nil
    end

    if UE.UGameplayStatics.IsValid(self.MediaPlayer) then
        self.MediaPlayer.OnEndReached:Clear()
        self.MediaPlayer = nil
    end

    if UE.UGameplayStatics.IsValid(self.sequencePlayerActor) then
        self.sequencePlayerActor.SequencePlayer.OnFinished:Clear()
        self.sequencePlayerActor:K2_DestroyActor()
        self.sequencePlayerActor = nil
    end

    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        --print("===audioComp:" .. tostring(self.AudioComp))
        --交给ue4自动去删除音效组件
        --self.AudioComp.DestroyComponent()
        self.AudioComp:Stop()
    end
    self.AudioComp = nil

    UIManager:GetInstance():RemoveUI(self)
    
    -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- gameInstance:RemoveUMG("UI_Loading2")
    -- gameInstance.UI_Loading2 = nil
    
    local GameInstance = UE.UGameplayStatics.GetGameInstance(self)
    GameInstance:ShowAllUI()
    GameInstance:DebugUI()
    if GameInstance.UI_Dialog_CutScene then
        GameInstance.UI_Dialog_CutScene = nil
    end
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    pc.BP_ScreenFade:FadeOut(false)
    print('=========播放完毕!!')
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_SetPlayer()
    if player then
        player:SetActorEnableCollision(true)
        -- player:SetActorHiddenInGame(true)
        player.CharacterMovement:SetActive(true, false)
    end

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.OnPlayDialogCutScene then
        playerController:OnPlayDialogCutScene(false)
    end

    self:OnPlayEnd()
end

function UI_Dialog_CutScene_C:OnPlayMediaEnd()
    self:IsPlayEnd()
end

function UI_Dialog_CutScene_C:OnPlaySequenceEnd()
    self:IsPlayEnd()
end

----------------------------------------------------------------------
function UI_Dialog_CutScene_C:OnClicked_SKIP()
    self:Pause()
    UIManager:GetInstance():ShowConfirm({
        notice = Database.L10n(471),
        confirm = function()
            if not UE.UKismetSystemLibrary.IsValid(self) then return end
            self:Resume()
            print("=======OnClicked_SKIP:")
            -- self:ShowUIComNotify()
            self:IsPlayEnd()
        end,
        cancel = function()
            self:Resume()
        end,
        showCancel = true,
    })
end

return UI_Dialog_CutScene_C
