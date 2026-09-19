--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"
require "Common.StringUtil"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local Database = require "_Game.Utils.Database"
local utf8 = require "Common.Tools.utf8"

---@type UI_Dialog_Story_C
local UI_Dialog_Story_C = Class()

UI_Dialog_Story_C.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(UI_Dialog_Story_C)

local UIUtils = require "_Game.Utils.UIUtils"

--剧情对话配置表
local StoryDialogTable = require "ClientDatas.d_story_dialog"

UI_Dialog_Story_C.DialogEnd = "UI_Dialog_Story_C.DialogEnd"

local EPlayType =
{
    PlayMedia = 0, --播放视频
    PlayDialog = 1, --播放对话
    PlayBackground = 2, --播放黑白
    Option = 3, --选项
    PlaySequence = 4, --非CG演出
    Event = 5,--事件
    AsideEvent = 6,--旁白事件
    BackGroundEvent = 7,--背景事件
};

--构造函数
function UI_Dialog_Story_C:Construct()
    self.AutoPlay.OnClicked:Clear()
    self.AutoPlay.OnClicked:Add(self, UI_Dialog_Story_C.OnClicked_AutoPlay)

    self.SKIP.OnClicked:Add(self, UI_Dialog_Story_C.OnClicked_Skip)
    self.BlackgroundMask.OnMouseButtonDownEvent:Unbind()
    self.BlackgroundMask.OnMouseButtonDownEvent:Bind(self, UI_Dialog_Story_C.OnClicked_BlackgroundMask)

    self.Mask_skipplay.OnClicked:Add(self, UI_Dialog_Story_C.OnClicked_MaskSkipPlay)
    self.Mask_skipplay.OnPressed:Add(self, self.OnPressed_MaskShipPlay)
    self.Mask_skipplay.OnReleased:Add(self, self.OnReleased_MaskShipPlay)

    --倍速播放
    self.Btn_PlayRate.OnGHSClicked:Add(self, self.OnGHSClicked_Btn_PlayRate)
    self.Btn_PlayRate.OnGHSPressed:Add(self, self.OnGHSPressed_Btn_PlayRate)
    self.Btn_PlayRate.OnGHSReleased:Add(self, self.OnGHSReleased_Btn_PlayRate)

    --self.UI_Mask:SetVisibility(UE.ESlateVisibility.Hidden)

    self.Img_HLinkBg.OnMouseButtonDownEvent:Unbind()
    self.Img_HLinkBg.OnMouseButtonDownEvent:Bind(self, UI_Dialog_Story_C.OnClicked_HLinkBg)

    -- self.RichText_1.OnHyperlinkClicked:Add(self, UI_Dialog_Story_C.OnClicked_RichTextLink)
    -- self.RichText_2.OnHyperlinkClicked:Add(self, UI_Dialog_Story_C.OnClicked_RichTextLink)
    -- self.RichText_3.OnHyperlinkClicked:Add(self, UI_Dialog_Story_C.OnClicked_RichTextLink)
    self.Text_Content.OnHyperlinkClicked:Add(self, UI_Dialog_Story_C.OnClicked_RichTextLink)

    self.Img_Media.OnMouseButtonDownEvent:Unbind()
    self.Img_Media.OnMouseButtonDownEvent:Bind(self, UI_Dialog_Story_C.OnClicked_Img_Media)
    self.Img_OptionBg.OnMouseButtonDownEvent:Bind(self, UI_Dialog_Story_C.OnClicked_Img_OptionBg)

    self.UI_Event.Btn_Aside.OnGHSClicked:Add(self, self.OnClicked_Btn_Aside)

    self.CurData = nil
    self.PlayType = -1
    self.bIsFirstEnter = true
    self.bIsMaskSkipPlayDelay = false
    self.sequencePlayer = nil
    self.blackgroundString = ""
    self.isAutoPlay = false
    self.DialogStart = true
    self.LastMapPath = ""

    self.PlayRateTime = self.PlayRateTime > 0.00001 and self.PlayRateTime or 0.5

    self.ListOption = {}
    for i = 1, 6 do
        table.insert(self.ListOption, self["UI_Dialog_Option_" .. i])
    end
    -- self.ListText = {}
    -- for i = 1, 8 do
    --     table.insert(self.ListText, self["Text_" .. i])
    -- end

    self.Text_Blackword:SetText('')
    self.CachedBlackString = ''

    self.CachedSequence:Clear()

    MessageManager:GetInstance():AddListener('AnimationLooping', self)
    MessageManager:GetInstance():AddListener('AnimationDialog', self)
end

function UI_Dialog_Story_C:Destruct()
    MessageManager:GetInstance():RemoveListener('AnimationLooping', self)
    MessageManager:GetInstance():RemoveListener('AnimationDialog', self)
    if self.LongPressedTimeHanlder then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressedTimeHanlder)
        self.LongPressedTimeHanlder = nil
    end
   
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
    end
    self.AudioComp = nil

    self.CachedSequence:Clear()
    local c = collectgarbage("count")
    print("Begin gc count = " .. string.format("%02f", c / 1024) .. " mb")
    collectgarbage("collect")
    c = collectgarbage("count")
    print("End    gc count =" .. string.format("%02f", c / 1024) .. " mb")

    if self.SubLevelSequenceActor then
        self.SubLevelSequenceActor.SequencePlayer:Stop()
        self.SubLevelSequenceActor.SequencePlayer.OnFinished:Clear()
        -- self.SubLevelSequenceActor.SequencePlayer:GoToEndAndStop()
        self.SubLevelSequenceActor:K2_DestroyActor()
        self.SubLevelSequenceActor = nil
    end

    if self.CameraSequenceActor then
        if self.CameraSequenceActor.SequencePlayer then
            self.CameraSequenceActor.SequencePlayer:Stop()
            self.CameraSequenceActor.SequencePlayer.OnFinished:Clear()
        end
        self.CameraSequenceActor:K2_DestroyActor()
        self.CameraSequenceActor = nil
    end

    if self.MediaPlayerActor then
        self.MediaPlayerActor:K2_DestroyActor()
        self.MediaPlayerActor = nil
    end
end

function UI_Dialog_Story_C:AnimationLooping()
    -- print("----------AnimationLooping:")
    self.AnimationLooping = true
    if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer and self.SubLevelSequenceActor.SequencePlayer:IsPlaying() then
        self.SubLevelSequenceActor.SequencePlayer:SetPlayRate(1)
        if self.AnimationSkip or self.CurData.playType == EPlayType.PlaySequence then
            self:PlayToNext()
            self.AnimationSkip = false
        end
    end
end

function UI_Dialog_Story_C:AnimationDialog(id)
    self.AnimationLooping = false
    local toPlayDialogId = tonumber(id)
    print('---toPlayDialogId:' .. tostring(toPlayDialogId) .. ",curId:" .. tostring(self.dialogId))
    if toPlayDialogId == 0 then
        print('-----toplayDialog 0')
        self:IsPlayEnd()
    elseif self.dialogId ~= toPlayDialogId then
        print("----------AnimationDialog:" .. tostring(id))
        if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer then
            self.SubLevelSequenceActor.SequencePlayer:PlayLooping(0)
        end
        if self.CameraSequenceActor and self.CameraSequenceActor.SequencePlayer then
            self.CameraSequenceActor.SequencePlayer:PlayLooping(0)
        end
        self.IsAnimationNotify = true
        self:UpdateUI(toPlayDialogId)
    end
end
function UI_Dialog_Story_C:BlendCameraToMainCamera()
    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "PlotCamera")
    if cineCameraActors:Length() > 0 then
        local plotCamera = cineCameraActors:Get(1)
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController:SetViewTargetWithBlend(plotCamera, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
    end
end

function UI_Dialog_Story_C:ParseFadeParams()
    self.CurData.StartMaskFadeIn = 0
    self.CurData.StartMaskFadeOut = 0
    self.CurData.EndMaskFadeIn = 0
    self.CurData.EndMaskFadeOut = 0

    self.CurData.MaskFadeInTime = 0
    self.CurData.MaskFadeOutTime = 0
    if self.CurData.playMaskFade and self.CurData.playMaskFade ~= "" then
        local splitTab = string.split(self.CurData.playMaskFade, ',')
        self.CurData.StartMaskFadeIn = tonumber(splitTab[1] or 0)
        self.CurData.StartMaskFadeOut = tonumber(splitTab[2] or 0)
        self.CurData.EndMaskFadeIn = tonumber(splitTab[3] or 0)
        self.CurData.EndMaskFadeOut = tonumber(splitTab[4] or 0)

        self.CurData.MaskFadeInTime = tonumber(splitTab[5] or 0)
        self.CurData.MaskFadeOutTime = tonumber(splitTab[6] or 0)
    end
end

function UI_Dialog_Story_C:SetShouldSkipLoading()
    self.ShouldSkipLoading = true
end

function UI_Dialog_Story_C:InitUI(id)
    self.originDialogId = id

    self:PlayAnimation(self.vfxLoop, 0, 1, UE.EUMGSequencePlayMode.Forward, 1, false)
    self:UpdateUI(id)
end

function UI_Dialog_Story_C:SetShouldHideLoading2InBackLevel()
    self.ShouldHideLoading2InBackLevel = true
end

function UI_Dialog_Story_C:UpdateUI(id)
    local should_skip_loading = self.ShouldSkipLoading
    self.ShouldSkipLoading = false
    LOG_DEBUG_TRACKBACK("--------->>curDialogId:" .. tostring(self.dialogId) .. ",ToPlayId:" .. tostring(id))
    if self.dialogId and self.dialogId == id then
        return
    end
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not pc.BP_PlayerController_City_UniverseBridge.BlockInputAction then
        pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
        self.InitBlock = true
    end

    --self:SetVisibility(UE.ESlateVisibility.Visible)
    self.dialogId = id
    local data = self:GetStoryDialogTable(id)
    if not data then
        print("==>>Error: not find this key:[" .. tostring(id) .. "] in [ d_story_dialog ] table!!!")
        self:IsPlayEnd()
        return
    end
    -- print("====play id:" .. tostring(id) .. ',type:' .. tostring(self:GetDisplayName(data.playType)))

    self.CurData = data
    self.PrePlayType = self.PlayType
    self.PlayType = data.playType --- 0:播放视频,1:对话,2:黑白文字,3:选项

    self.Panel_Media:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.Hidden)
    --self.BlackgroundMask:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Background:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Option:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_HLink:SetVisibility(UE.ESlateVisibility.Hidden)
    --self.Mask_skipplay:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.BG_Image_News:SetVisibility(UE.ESlateVisibility.Hidden)
    self.UI_Event:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Black:SetVisibility(UE.ESlateVisibility.Visible)

    self.BG:SetVisibility(self.PlayType == EPlayType.BackGroundEvent and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    
    if not self.DefaultGravityScale or self.DefaultGravityScale <= 0 then
        if gameMode.Player then
            self.DefaultGravityScale = gameMode.Player.CharacterMovement.GravityScale
            gameMode.Player.CharacterMovement.GravityScale = 0
            gameMode.Player:SetActorHiddenInGame(true)
        end
    end

    --预加载sequence
    self:CacheLevelSequence(self.CurData.playType, self.CurData.cutScenePath)
    -- self:CacheLevelSequence(self.CurData.playType, self.CurData.playLoopPath)
    -- if self.CurData.next and self.CurData.next > 0 then
        --     print('-----next:' .. tostring(self.CurData.next))
        --     local nextData = self:GetStoryDialogTable(self.CurData.next)
        --     if nextData then
            --         -- self:CacheLevelSequence(nextData.playType, nextData.cutScenePath)
            --         -- self:CacheLevelSequence(nextData.playType, nextData.playLoopPath)
        --     end
    -- end

    if self.CurData.mapPath ~= "" and self.LastMapPath ~= self.CurData.mapPath then
        print("=============mapPath:" .. tostring(self.CurData.mapPath))
        self.LastMapPath = self.CurData.mapPath
        if gameMode.Player then
            --设置character 
            gameMode.Player.CharacterMovement.GravityScale = 0
            gameMode.Player:SetActorHiddenInGame(true)
        end
        self.bIsLoadingMap = true
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
        local mapNameList = string.split(self.CurData.mapPath, '|')
        gameInstance:EnterStreamingLevel(mapNameList, not should_skip_loading, false, { self, self.OnLoadLevel })
    else
        self.Black:SetVisibility(UE.ESlateVisibility.Hidden)
        self:OnLoadLevel()
    end
end

function UI_Dialog_Story_C:CacheLevelSequence(playType, path)
    -- print('-----CacheLevelSequence:' .. tostring(playType) .. ',path:' .. tostring(path))
    if playType == EPlayType.PlayDialog or playType == EPlayType.PlaySequence or playType == EPlayType.Event then
        if path and path ~= '' then
            if not self:GetSequence(path) then
                local levelSequence = LoadObject(path)
                if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
                    LOG_ERROR("===加载缓存sequence错误!!!,path:" .. tostring(path) .. ',levelsequence:' .. tostring(levelSequence or nil) .. ',classType:' .. tostring(levelSequence and levelSequence:GetClass() or 'nil') .. ',plotId:' .. tostring(self.dialogId))
                    return
                else
                    -- print('-----path:' .. tostring(path) .. tostring(levelSequence))
                    self:AddSequence(path, levelSequence)
                end
            end
        end
    end
end

function UI_Dialog_Story_C:OnLoadLevel()
    self.bIsLoadingMap = false
    if not UE.UKismetSystemLibrary.IsValid(self) then
        LOG_ERROR_TRACKBACK("我为什么提前被删除了")
        return
    end
    LOG_DEBUG_TRACKBACK('-----OnLoadLevel:')
    --优化屏蔽玩家点击太快导致的各种bug
    self.LastBlackBackgroundTime = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
    self.LastDialogTime = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2")
    gameInstance.UI_Loading2 = nil

    -- self:IsPlayEnd()
    -- do return end
    --修正黑白文字参数配置PlayMaskFade解析
    if self.CurData.playType == EPlayType.PlayBackground then
        if self.CurData.playMaskFade == "" then
            self.CurData.MaskFadeInTime = 0
            self.CurData.MaskFadeOutTime = 0

            if self.bIsFirstEnter then
                self.CurData.StartMaskFadeIn = 1
            end
            if self.CurData.next == 0 then --判断后续如果结束
                self.CurData.EndMaskFadeOut = 1
            else --下一个不是黑白字
                local nextData = self:GetStoryDialogTable(self.CurData.next)
                if nextData and nextData.playType ~= EPlayType.PlayBackground then
                    --self.CurData.EndMaskFadeOut = 1
                end
            end
        else
            self:ParseFadeParams()
        end
    else
        self:ParseFadeParams()
    end

    if self.CurData.StartMaskFadeIn == 1 then
        self:PlayStartMaskFadeIn()
    elseif self.CurData.StartMaskFadeOut == 1 then
        self:PlayStartMaskFadeOut()
    else
        self:StartPlay()
    end
end

function UI_Dialog_Story_C:PlayStartMaskFadeIn()
    self:UnbindAllFromAnimationFinished(self.MaskFadeIn)
    self:UnbindAllFromAnimationFinished(self.MaskFadeOut)
    if self.CurData.StartMaskFadeOut ~= 1 then
        self:StartPlay()
    end
    print('---------------->PlayStartMaskFadeIn:')
    self:BindToAnimationFinished(self.MaskFadeIn, function()
        if self.CurData.StartMaskFadeOut == 1 then
            self:PlayStartMaskFadeOut()
        else
            if self.CurData.showText == '' then
                self:PlayToNext()
            end
        end
    end)
    --self.UI_Mask:SetVisibility(UE.ESlateVisibility.Visible)
    local AnimLength = self.MaskFadeIn:GetEndTime() - self.MaskFadeIn:GetStartTime()
    local targetTime = self.CurData.MaskFadeInTime <= 0 and AnimLength or self.CurData.MaskFadeInTime
    local PlaySpeed  = AnimLength / targetTime
    self:PlayAnimation(self.MaskFadeIn, 0.0, 1, UE.EUMGSequencePlayMode.Forward, PlaySpeed)
    --self:PlayAnimationForward(self.MaskFadeIn, PlaySpeed)
end

function UI_Dialog_Story_C:PlayStartMaskFadeOut()
    self:UnbindAllFromAnimationFinished(self.MaskFadeIn)
    self:UnbindAllFromAnimationFinished(self.MaskFadeOut)
    self:StartPlay()

    print('---------------->PlayStartMaskFadeOut:')
    self:BindToAnimationFinished(self.MaskFadeOut, function()
        
    end)
    --self.UI_Mask:SetVisibility(UE.ESlateVisibility.Visible)
    local AnimLength = self.MaskFadeOut:GetEndTime() - self.MaskFadeOut:GetStartTime()
    local targetTime = self.CurData.MaskFadeOutTime <= 0 and AnimLength or self.CurData.MaskFadeOutTime
    local PlaySpeed  = AnimLength / targetTime

    self:PlayAnimation(self.MaskFadeOut, 0.0, 1, UE.EUMGSequencePlayMode.Forward, PlaySpeed)
    --self:PlayAnimationForward(self.MaskFadeOut, PlaySpeed)
end

function UI_Dialog_Story_C:PlayEndMaskFadeIn()
    self:UnbindAllFromAnimationFinished(self.MaskFadeIn)
    self:UnbindAllFromAnimationFinished(self.MaskFadeOut)
 
    print('---------------->PlayEndMaskFadeIn:')
    self:BindToAnimationFinished(self.MaskFadeIn, function()
        if self.CurData.EndMaskFadeOut == 1 then
            self:PlayEndMaskFadeOut()
        else
            self:PlayToNext()
        end
    end)
    --self.UI_Mask:SetVisibility(UE.ESlateVisibility.Visible)
    local AnimLength = self.MaskFadeIn:GetEndTime() - self.MaskFadeIn:GetStartTime()
    local targetTime = self.CurData.MaskFadeInTime <= 0 and AnimLength or self.CurData.MaskFadeInTime
    local PlaySpeed  = AnimLength / targetTime
    self:PlayAnimation(self.MaskFadeIn, 0.0, 1, UE.EUMGSequencePlayMode.Forward, PlaySpeed)
    --self:PlayAnimationForward(self.MaskFadeIn, PlaySpeed)
end

function UI_Dialog_Story_C:PlayEndMaskFadeOut()
    self:UnbindAllFromAnimationFinished(self.MaskFadeIn)
    self:UnbindAllFromAnimationFinished(self.MaskFadeOut)
    print('---------------->PlayEndMaskFadeOut:')
    self:BindToAnimationFinished(self.MaskFadeOut, function()
        self:PlayToNext()
    end)
    --self.UI_Mask:SetVisibility(UE.ESlateVisibility.Visible)
    local AnimLength = self.MaskFadeOut:GetEndTime() - self.MaskFadeOut:GetStartTime()
    local targetTime = self.CurData.MaskFadeOutTime <= 0 and AnimLength or self.CurData.MaskFadeOutTime
    local PlaySpeed  = AnimLength / targetTime
    self:PlayAnimation(self.MaskFadeOut, 0.0, 1, UE.EUMGSequencePlayMode.Forward, PlaySpeed)
    --self:PlayAnimationForward(self.MaskFadeOut, PlaySpeed)
end


function UI_Dialog_Story_C:StartPlay()
    self.bIsPlayEnd = false
    self.AnimationLooping = false
    --面板显示控制
    self.Panel_Media:SetVisibility(
        self.PlayType == EPlayType.PlayMedia and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Panel_Dialog:SetVisibility((self.PlayType == EPlayType.PlayDialog or self.PlayType == EPlayType.Option) 
        and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    --self.BlackgroundMask:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Background:SetVisibility(
        self.PlayType == EPlayType.PlayBackground and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Panel_Option:SetVisibility(
        self.PlayType == EPlayType.Option and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.AutoPlay:SetVisibility(UE.ESlateVisibility.Collapsed)
    --  self.PlayType == EPlayType.PlayDialog and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    
    --     self.PlayType == EPlayType.Option and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.UI_Event:SetVisibility(self.PlayType == EPlayType.AsideEvent and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    self.BG:SetVisibility(self.PlayType == EPlayType.BackGroundEvent and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Black:SetVisibility((self.PlayType == EPlayType.BackGroundEvent or self.PlayType == EPlayType.PlayBackground) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    -- self.UI_Mask:SetVisibility(UE.ESlateVisibility.Hidden)

    self.AllFinished, self.TargetOptionId = self:FindOptionId()
    if self.CurData.skipButton == 1 then
        self.SKIP:SetVisibility(UE.ESlateVisibility.Visible)
        self.SKIP_Text:SetText(Database.L10n(471))
        self.word_id = 471
        -- self.Mask_skipplay:SetVisibility(UE.ESlateVisibility.Collapsed)
    else
        if true or self.AllFinished then
            if (self.TargetOptionId > 0 and self.CurData.id < self.TargetOptionId) then
                self.SKIP:SetVisibility(UE.ESlateVisibility.Visible)
                self.SKIP_Text:SetText(Database.L10n(472))
                self.word_id = 472
            elseif self.TargetOptionId == 0 then --没有选项的
                self.SKIP:SetVisibility(UE.ESlateVisibility.Visible)
                self.SKIP_Text:SetText(Database.L10n(472))
                self.word_id = 472
            end
           
        else
            --self.SKIP:SetVisibility(UE.ESlateVisibility.Collapsed)
        end
        --self.Mask_skipplay:SetVisibility(UE.ESlateVisibility.Visible)
    end
    if self.PlayType == EPlayType.PlayBackground then
        self.SKIP:SetVisibility(UE.ESlateVisibility.Collapsed) 
    end
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
    end
    self.AudioComp = nil
    
   
    -- print('--->self.TargetOptionId:' .. tostring(self.TargetOptionId))
    --播放声音
    if self.CurData.soundCue ~= '' then
        local audioSource = LoadObject(self.CurData.soundCue)
        if audioSource then
            -- print('---->音效长度:' .. audioSource.Duration)
            if UE.UGameplayStatics.ObjectIsA(audioSource, UE.USoundBase.StaticClass()) then
                self.AudioComp = UE.UGameplayStatics.SpawnSound2D(self, audioSource)
            else
                LOG_ERROR("===错误的音频资源类型:", self.CurData.soundCue)
            end
        end
    end

    if not self.LastBgmCue then self.LastBgmCue = '' end
    if self.CurData.bgmCue ~= '' and self.CurData.bgmCue ~= self.LastBgmCue then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:ChangeBgm(self.CurData.bgmCue, self.CurData.bgmParameter)
        self.LastBgmCue = self.CurData.bgmCue
    end

    if self.PlayType == EPlayType.PlayMedia then
        self:PlayMedia()
    elseif self.PlayType == EPlayType.PlayDialog then
        self:PlayDialog()
    elseif self.PlayType == EPlayType.PlayBackground then
        --文字对齐方式
        local justification = UE.ETextJustify.Center
        local type = self.CurData.options1 ~= '' and tonumber(self.CurData.options1) or 2
        if type == 1 then
            justification = UE.ETextJustify.Left
        elseif type == 2 then
            justification = UE.ETextJustify.Center
        else
            justification = UE.ETextJustify.Right
        end
        self.Text_Blackword:SetJustification(justification)
        
        --文字排版方式
        local verticalAlignment = UE.EVerticalAlignment.VAlign_Fill
        local type = self.CurData.options2 ~= '' and tonumber(self.CurData.options2) or 4
        if type == 1 then
            verticalAlignment = UE.EVerticalAlignment.VAlign_Top
        elseif type == 2 then
            verticalAlignment = UE.EVerticalAlignment.VAlign_Center
        elseif type == 3 then
            verticalAlignment = UE.EVerticalAlignment.VAlign_Bottom
        end
        self.VerticalBox_Blackword.Slot:SetVerticalAlignment(verticalAlignment)

        --翻页标识
        if self.CurData.options3 ~= '' then
            local type = tonumber(self.CurData.options3)
            if type == 1 then
                self.CachedBlackString = ''
                self.Text_Blackword:SetText('')
            end
        end
        self.Text_Blackword:SetAutoWrapText(false)
        self:PlayBackground()
    elseif self.PlayType == EPlayType.Option then
        self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.Hidden)
        -- self.Black:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

        if self.CurData.showText == "" then
            self:PlayOption()
        else
            self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self.Panel_OptionList:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Img_OptionBg:SetRenderOpacity(0)
            self.Img_OptionBg:SetVisibility(UE.ESlateVisibility.Visible)
            self.BackgroundBlur_Option:SetVisibility(UE.ESlateVisibility.Hidden)
            self:ShowDialogText()
        end
    elseif self.PlayType == EPlayType.PlaySequence then
        self:ShowDialogText()
        self:PlaySequence()
    elseif self.PlayType == EPlayType.Event then
        self.UI_Mask:SetRenderOpacity(0)
        self:ShowDialogText()
        if self.CurData.cutScenePath and self.CurData.cutScenePath ~= '' then
            self:PlaySequenceOnce(self.CurData.cutScenePath)
        end
    elseif self.PlayType == EPlayType.AsideEvent then
        self:PlayAsideEvent()
    elseif self.PlayType == EPlayType.BackGroundEvent then
        self:PlayBackgroundEvent()
    else
        print("==>>Error: not support this PlayType:" .. tostring(self.PlayType) .. ",id:" .. tostring(id) .. " !!!")
        self:IsPlayEnd()
    end

    if self.CurData.TutorialId > 0 then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:ShowTutorial(self.CurData.TutorialId, true)
    end
end

function UI_Dialog_Story_C:FindOptionId()
    local PlotSystem = require("Module.Plot.PlotSystem")

    local curId = self.CurData.id
    local config = self.CurData
    local allFinished = false
    local plotId = 0
    local subFinished = PlotSystem:GetInstance():IsCompletedDialog(curId)
    if subFinished then allFinished = true end
    if config.playType == EPlayType.Option then
        plotId = curId
    end

    while (config.next and config.next > 0) do
        local data = self:GetStoryDialogTable(config.next)
        if data then
            curId = data.id
            subFinished = PlotSystem:GetInstance():IsCompletedDialog(curId)
            if subFinished then allFinished = true end
            if data.playType == EPlayType.Option then
                plotId = curId
            end
            config = data
        else
            break
        end
    end
    return allFinished, plotId
end

function UI_Dialog_Story_C:PlayMedia()
    if self.CurData.cutScenePath and self.CurData.cutScenePath ~= '' then
        ---创建视频播放
        if not self.MediaPlayerActor then
            local world = self:GetWorld()
            local transfrom = UE.UKismetMathLibrary.MakeTransform(
                UE.FVector(0, 0, 0), 
                UE.FRotator(0, 0, 0), 
                UE.FVector(1, 1, 1))
            local MediaPlayerActorPath = "Blueprint'/Game/_Game/Blueprints/MediaPlayer/MediaPlayerActor.MediaPlayerActor_C'"
            self.MediaPlayerActor = world:SpawnActor(
                UE.UClass.Load(MediaPlayerActorPath), 
                transfrom, 
                UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, 
                self, self)
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            local volume = gameInstance:GetSoundVolume(3) / 100 * gameInstance:GetSoundVolume(0) / 100
            print("--------->volume1:" .. tostring(gameInstance:GetSoundVolume(3) / 100) .. ', vloume2:' .. tostring(gameInstance:GetSoundVolume(0) / 100) .. ',v:' .. tostring(volume))
            self.MediaPlayerActor.MediaSound:SetVolumeMultiplier(volume)
        end

        local mediaSource = LoadObject(self.CurData.cutScenePath)
        self.MediaPlayer:OpenSource(mediaSource)
        self.MediaPlayer.OnEndReached:Clear()
        self.MediaPlayer.OnEndReached:Add(self, UI_Dialog_Story_C.OnPlayMediaEnd)
        --视频加速
        local playRate = 1.0
        if self.isPlayRate then
            playRate = 2
        end
        self.MediaPlayer:SetRate(playRate)
    else
        self:PlayNext()
    end
end

function UI_Dialog_Story_C:PlayDialog()
    if self.CurData.showText == "" then
        self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self:ShowDialogText()
    end

    self:PlaySequence(self.CurData.showText ~= "")
end

function UI_Dialog_Story_C:ShowDialogText()
    self.Panel_Dialog:SetVisibility(self.CurData.showText ~= "" and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    if self.CurData.showText == '' then return end
    local roleName = UIUtils.ReplacePlayerName(self.CurData.roleName)
    self.Text_RoleName:SetText(roleName)
    self.Text_RoleTitle:SetText(self.CurData.roleTitle)

    local titleShow = self.CurData.roleTitle == "" and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible
    self.Img_TitleLeft:SetVisibility(titleShow)
    self.Img_TitleRight:SetVisibility(titleShow)

    self.CurData.showText = string.gsub(self.CurData.showText, '/n', '\n')
    self.CurData.showText = string.gsub(self.CurData.showText, '\r\n', '\n')
    self.CurData.showText = string.gsub(self.CurData.showText, '\\n', '\n')
    --self.Text_Content:SetText(string.gsub(self.CurData.ShowText, '\\n', '\n'))

    local strArr = string.split(self.CurData.showText, '\n')
    if #strArr > 0 then
        local showText = UIUtils.ReplacePlayerName(self.CurData.showText)
        showText = self:DoHypeLinkAction(showText)
        self:SetTextContent(showText, #strArr, 1.05)
    end
end

function UI_Dialog_Story_C:DoHypeLinkAction(showText)
    local result = self:FindAction(showText)
    -- print("---------------->" .. tostring(table.dump(result, nil, 10)))
    local unlocked = false
    for i, str in ipairs(result) do 
        local vars = string.split(str, ':')
        if vars and #vars > 1 then
            local t = tonumber(vars[1])
            local v = vars[2]
            -- print('------t->' .. tostring(t) .. ',v->' .. tostring(v))
            if t == 2 then
                local PlotSystem = require("Module.Plot.PlotSystem")
                unlocked = unlocked or PlotSystem:GetInstance():ReqUnlockStoryLines(tonumber(v))
            end
        end
    end
    if unlocked then
        showText = string.gsub(showText, [[%s+color="#%x%x%x%x%x%x%x?%x?"%s+]], " ")
    end
    return showText
end

function UI_Dialog_Story_C:FindAction(showText)
    local curStr = showText
    local result = {}
    local p1, p2 = 1, 1 
    local startPos = 1
    repeat
        p1, p2 = string.find(curStr, 'action=%b""', startPos)
        if p1 and p1 > 1 then
            local str = string.sub(curStr, p1, p2)
            local p3, p4 = string.find(str, '%b""')
            if p3 and p3 > 1 then
                str = string.sub(str, p3 + 1, p4 - 1)
                table.insert(result, str)
                startPos = p2
            end
        end
    until (not p1)

    return result
end

function UI_Dialog_Story_C:GetAllBlackBackgroundString()
    local tempData = self.CurData
    local listString = {}
    while tempData and tempData.playType == EPlayType.PlayBackground do
        local realStr = string.gsub(tempData.showText, '\\n', '\n')
        table.insert(listString, realStr)
        local nextData = self:GetStoryDialogTable(tempData.next)
        if nextData and nextData.playType == EPlayType.PlayBackground then
            tempData = nextData
        else
            tempData = nil
        end
    end
    return listString
end

function UI_Dialog_Story_C:PlayBackground()
    --播放渐显动画
    if self.bIsFirstEnter then
        self.bIsFirstEnter = false
        self.CachedBlackString = string.gsub(self.CurData.showText, '\\n', '\n')
        self.Text_Blackword:SetText(self.CachedBlackString)
        self.Text_Blackword:SetAutoWrapText(true)
        self.UI_Mask:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self:BindToAnimationFinished(self.BlackGroundFadeIn, function()
            self:OnPlayAnimationFadeInEnd()
        end)
        self:PlayAnimation(self.BlackGroundFadeIn)
        return
    end
    self.CachedBlackString = self.CachedBlackString .. '\n' .. string.gsub(self.CurData.showText, '\\n', '\n')
    self.Text_Blackword:SetText(self.CachedBlackString)
    self.Text_Blackword:SetAutoWrapText(true)
    --播放文字淡入淡出
    -- self.TimerHandle = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
    --     { self, self.OnTimerFadeInEnd }, self.PlayMaskFadeInTime, false)
end

function UI_Dialog_Story_C:PlayOption()
    self.Black:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.Panel_Option:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_OptionList:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.Img_OptionBg:SetRenderOpacity(1)
    local sprite_object = LoadObject(self.CurData.OptionBackgtound)
    if sprite_object then
        self.Img_OptionBg:SetBrushFromTexture(sprite_object)
    end
    self.OptionData = {}
    --初始化
    for i = 1, 6 do
        local OpKey = "options" .. i
        if self.CurData[OpKey] and "" ~= self.CurData[OpKey] then
            local tempTab = {}
            local splitTab = string.split(self.CurData[OpKey], '=')
            for _, str in ipairs(splitTab) do
                local strArr = string.split(str, '|')
                for _, str in ipairs(strArr) do
                    table.insert(tempTab, str)
                end
            end
            table.insert(self.OptionData, tempTab)
        end
    end
    print("---option:" .. tostring(table.dump(self.OptionData, nil, 10)))

    local StartIndex = #self.ListOption - #self.OptionData
    for i = 1, #self.ListOption do
        local optionItemUI = self.ListOption[i]
        if optionItemUI then
            optionItemUI:SetVisibility(i > StartIndex and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
            optionItemUI.Option.OnClicked:Clear()
            if i > StartIndex then
                local PlotSystem = require("Module.Plot.PlotSystem")
                local opData = self.OptionData[i - StartIndex]
                if opData then
                    optionItemUI.Text = opData[1]
                    optionItemUI.Option.OnClicked:Add(optionItemUI.Option, function()
                        print('-----------Option.OnClicke:' .. tostring(i - StartIndex) .. ', content:' .. tostring(opData[2]))
                        self:OnClicked_Option(i - StartIndex, opData[2])
                    end)
                    local hasPassed = PlotSystem:GetInstance():IsCompletedDialogOption(self.CurData.id, i - StartIndex)
                    if hasPassed then
                        -- optionItemUI.Option:SetIsEnabled(false)
                        optionItemUI.Panel_Locked:SetVisibility(UE.ESlateVisibility.Hidden)
                        optionItemUI.Panel_Unlock:SetVisibility(UE.ESlateVisibility.Hidden)
                        optionItemUI.Panel_Finish:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    else
                        local key = tonumber(opData[3] or 0)
                        if key > 0 then
                            --解锁
                            if PlotSystem:GetInstance():IsHasKey(key) then
                                optionItemUI.Option:SetIsEnabled(true)
                                optionItemUI.Panel_Locked:SetVisibility(UE.ESlateVisibility.Hidden)
                                optionItemUI.Panel_Unlock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                                optionItemUI.Image_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                                optionItemUI.Image_2:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                                optionItemUI.Panel_Finish:SetVisibility(UE.ESlateVisibility.Hidden)
                            else
                                optionItemUI.Option:SetIsEnabled(false)
                                optionItemUI.Panel_Locked:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                                optionItemUI.Panel_Unlock:SetVisibility(UE.ESlateVisibility.Hidden)
                                optionItemUI.Panel_Finish:SetVisibility(UE.ESlateVisibility.Hidden)
                            end
                        else
                            optionItemUI.Option:SetIsEnabled(true)
                            optionItemUI.Panel_Locked:SetVisibility(UE.ESlateVisibility.Hidden)
                            optionItemUI.Panel_Unlock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                            optionItemUI.Image_1:SetVisibility(UE.ESlateVisibility.Hidden)
                            optionItemUI.Image_2:SetVisibility(UE.ESlateVisibility.Hidden)
                            optionItemUI.Panel_Finish:SetVisibility(UE.ESlateVisibility.Hidden)
                        end
                    end
                end
            end
        end
    end
end

function UI_Dialog_Story_C:PlaySequence()
    --print("===play sequence  path:" .. tostring(self.CurData.cutScenePath))
    self.UI_Mask:SetRenderOpacity(0)
    if not self.InSequenceIneraction then 
        self.InSequenceIneraction = true
    end
    if self.CurData.cutScenePath and self.CurData.cutScenePath ~= '' then
        self:PlaySequenceOnce(self.CurData.cutScenePath, self.CurData.cutSceneStartFrame > 0)
    elseif self.CurData.playLoopPath and self.CurData.playLoopPath ~= '' then
        self:PlaySequenceLoop(self.CurData.playLoopPath)
        if self.isAutoPlay then
            self:PlayNext()
        end
    end

    --口型
    if self.CurData.NpcSpeak ~= '' then
        local arrString = string.split(self.CurData.NpcSpeak, '|')
        if arrString[1] and arrString[1] ~= '' then
            local charList = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, arrString[1])
            if charList:Length() > 0 then
                local charActor = charList:Get(1)
                if charActor and charActor.PlaySpeakAnimation then
                    if self.AudioComp and self.AudioComp.Sound then
                        charActor:PlaySpeakAnimation(self.AudioComp.Sound.Duration)
                    else
                        charActor:PlaySpeakAnimation(tonumber(arrString[2] or 0))
                    end
                end
            end
        end
    end

    ---剧情跳帧
    if self.SubLevelSequenceActor then
        local startFrame = tonumber(self.CurData.cutSceneStartFrame)
        if startFrame and startFrame > 0 then
            -- self.SubLevelSequenceActor.SequencePlayer:Pause()
            LOG_INFO('--->main.startFrame:' .. tostring(startFrame) .. ",end:" .. tostring(self.InitFrameDuration) .. ",duration:" .. tostring(self.InitFrameDuration - startFrame))
            self.SubLevelSequenceActor.SequencePlayer:SetPlayRate(1)
            self.SubLevelSequenceActor.SequencePlayer:SetFrameRange(startFrame, self.InitFrameDuration - startFrame, 0)
            self.SubLevelSequenceActor.SequencePlayer:PlayLooping(0)

            self.SubLevelSequenceActor.SequencePlayer.OnFinished:Clear()
            self.SubLevelSequenceActor.SequencePlayer.OnFinished:Add(self, UI_Dialog_Story_C.OnPlaySequenceEnd)
        end
    end

    --摄像机sequence
    if self.CurData.cameraPath and '' ~= self.CurData.cameraPath then
        self:PlayCameraSequence(self.CurData.cameraPath, self.CurData.cameraStartFrame > 0)
    end
    if not self.LastCameraStartFrame then self.LastCameraStartFrame = 0 end
    ---摄像机跳帧
    if self.CameraSequenceActor then
        local startFrame = tonumber(self.CurData.cameraStartFrame)
        if startFrame and startFrame > 0 then
            -- self.SubLevelSequenceActor.SequencePlayer:Pause()
            LOG_INFO('--->camer.startFrame:' .. tostring(startFrame) .. ",end:" .. tostring(self.CameraInitFrameDuration) .. ",LastCameraStartFrame:" .. tostring(self.LastCameraStartFrame))
            self.SubLevelSequenceActor.SequencePlayer:SetPlayRate(1)
            local player = self.CameraSequenceActor.SequencePlayer
            local StartTime = player.StartTime.Value
            local DurationFrames = player.DurationFrames
            local DurationSubFrames = player.DurationSubFrames
            local numLoops = player.PlaybackSettings.LoopCount.Value
            local curTime = player:GetCurrentTime().Time.FrameNumber.Value
            if StartTime ~= startFrame or DurationFrames ~= self.CameraInitFrameDuration - startFrame or not UE.UKismetMathLibrary.NearlyEqual_FloatFloat(DurationSubFrames, 0, 0.0001)
            or numLoops ~= 0
            or curTime ~= startFrame
            then
                if self.LastCameraStartFrame and self.LastCameraStartFrame  ~= startFrame then
                    player:SetFrameRange(startFrame, self.CameraInitFrameDuration - startFrame, 0)
                    player:PlayLooping(0)
                end

                self.LastCameraStartFrame = startFrame
            end
            -- self.CameraSequenceActor.SequencePlayer:SetFrameRange(startFrame, self.CameraInitFrameDuration - startFrame, 0)
            -- self.CameraSequenceActor.SequencePlayer:PlayLooping(0)
        else
            --self.LastCameraStartFrame = 0
        end
    end
end

function UI_Dialog_Story_C:PlayAsideEvent(isPref)
    if self.CurData.cutScenePath ~= '' then
        local bg_texture = UE.UObject.Load(self.CurData.cutScenePath)
        if bg_texture then
            self.UI_Event.Img_Aside:SetBrushFromTexture(bg_texture)
        end
    end
    if not isPref then
        self.UI_Event.Text_Aside:SetText(self.CurData.showText)
    end
end

function UI_Dialog_Story_C:PlayBackgroundEvent(isPref)
    if self.CurData.cutScenePath ~= '' then
        local bg_texture = UE.UObject.Load(self.CurData.cutScenePath)
        if bg_texture then
            self.BG:SetBrushFromTexture(bg_texture)
        end
    end
    if not isPref then
        if self.CurData.showText == "" then
            self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self:ShowDialogText()
        end
    end
end

function UI_Dialog_Story_C:PlaySequenceSingle(path)
    local levelSequence = self:GetSequence(path)
    if not levelSequence or not UE.UKismetSystemLibrary.IsValid(levelSequence) then
        levelSequence = LoadObject(path)
        if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
            LOG_ERROR("===播放Onece->sequence错误!!!,path:" .. tostring(path))
            return 
        end
        self:AddSequence(path, levelSequence)
    end
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
    if not self.SingleSequenceActor then
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        --配置
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount

        local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, 
            Settings, nil)

        self.SingleSequenceActor = levelSequenceActor
        self.SingleSequenceActorRef = UnLua.Ref(levelSequenceActor)
        -- self.SingleSequenceActor.CameraSettings = UE.FLevelSequenceCameraSettings()
        -- self.SingleSequenceActor.SequencePlayer.OnFinished:Clear()
        -- self.SingleSequenceActor.SequencePlayer.OnFinished:Add(self, UI_Dialog_Story_C.OnPlaySequenceSingleEnd)

        self.SingleInitFrameDuration = self.SingleSequenceActor.SequencePlayer:GetFrameDuration()
        --print("-----GetFrameDuration:" .. tostring(self.InitFrameDuration))
    end

    --停止其他2个
    -- if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer then
    --     self.SubLevelSequenceActor.SequencePlayer:GoToEndAndStop()
    -- end
    -- if self.CameraSequenceActor and self.CameraSequenceActor.SequencePlayer then
    --     self.CameraSequenceActor.SequencePlayer:Pause()
    -- end
    
    if self.SingleSequenceActor and self.SingleSequenceActor.SequencePlayer then
        --self.SingleSequenceActor:SetSequence(levelSequence)
        self.SingleSequenceActor.SequencePlayer.OnFinished:Clear()
        self.SingleSequenceActor.SequencePlayer.OnFinished:Add(self, UI_Dialog_Story_C.OnPlaySequenceSingleEnd)

        local playRate = 1.0
        -- if self.isPlayRate then
        --     local endTime = self.SingleSequenceActor.SequencePlayer:GetEndTime().Time.FrameNumber.Value
        --     local curTime = self.SingleSequenceActor.SequencePlayer:GetCurrentTime().Time.FrameNumber.Value
        --     local leftTime = (endTime - curTime) / self.SingleSequenceActor.SequencePlayer:GetFrameRate().Numerator
        --     playRate = leftTime / self.PlayRateTime
        -- end
        LOG_INFO("------->init play rate:" .. tostring(playRate))
        self.SingleSequenceActor.SequencePlayer:SetPlayRate(playRate)
        self.SingleSequenceActor.SequencePlayer:PlayLooping(0)
    end

    -- if self.CameraSequenceActor and self.CameraSequenceActor.SequencePlayer then
    --     self.CameraSequenceActor.SequencePlayer:GoToEndAndStop()
    -- end
end

function UI_Dialog_Story_C:OnPlaySequenceSingleEnd()
    print("========OnPlaySequenceSingleEnd:" .. tostring(self.CurData.cutScenePath))
    if self.SingleSequenceActor and self.SingleSequenceActor.SequencePlayer then
        --self.SubLevelSequenceActor.SequencePlayer:GoToEndAndStop()
        self.SingleSequenceActor.SequencePlayer.OnFinished:Clear()
        self.SingleSequenceActor:K2_DestroyActor()
        self.SingleSequenceActor = nil
    end

    if self.isAutoPlay or self.PlayType == EPlayType.PlaySequence or self.PlayType == EPlayType.Event then
        self:PlayNext()
    end
end

--拆分非循环sequence的播放和循环sequence的播放
function UI_Dialog_Story_C:PlaySequenceOnce(path, should_play_after)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2")
    print("===PlaySequenceOnce:" .. tostring(path) .. ',range:' .. tostring(self.CurData.playLoopPath))
    if self.IsAnimationNotify then
        self.IsAnimationNotify = false
        print("---------isAn")
        do return end
    end
    if self.LastSubLevelSequencePath == path then
        return
    end
    -- if self.MainLevelSequenceActor and self.MainLevelSequenceActor.SequencePlayer then
    --     self.MainLevelSequenceActor.SequencePlayer:GoToEndAndStop()
    -- end


    --加载sequence
    local levelSequence = self:GetSequence(path)
    if not levelSequence or not UE.UKismetSystemLibrary.IsValid(levelSequence) then
        levelSequence = LoadObject(path)
        if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
            LOG_ERROR("===播放Onece->sequence错误!!!,path:" .. tostring(path))
            return 
        else
            self:AddSequence(path, levelSequence)
        end
    end
    
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation

    -- if self.SubLevelSequenceActor then
    --     self.SubLevelSequenceActor:K2_DestroyActor()
    --     self.SubLevelSequenceActor = nil
    -- end
    if self.LastSubLevelSequencePath ~= path and self.SubLevelSequenceActor and UE.UKismetSystemLibrary.IsValid(self.SubLevelSequenceActor) then
        self.SubLevelSequenceActor:K2_DestroyActor()
        self.SubLevelSequenceActor = nil
    end
    self.LastSubLevelSequencePath = path

    if not self.SubLevelSequenceActor then
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        --配置
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        Settings.bDisableCameraCuts = true
        Settings.bInheritTickIntervalFromOwner = true
        Settings.bAllowRounding = true
        local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, 
            Settings, nil)

        self.SubLevelSequenceActor = levelSequenceActor
        self.SubLevelSequenceActorRef = UnLua.Ref(levelSequenceActor)

        self.InitFrameDuration = self.SubLevelSequenceActor.SequencePlayer:GetFrameDuration()
        print("---------:" .. tostring(self.InitFrameDuration))
        print("------end:" .. tostring(self.SubLevelSequenceActor.SequencePlayer:GetEndTime().Time.FrameNumber.Value))
    else
        self.SubLevelSequenceActor:SetSequence(levelSequence)
    end
    
    if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer then
        
        self.SubLevelSequenceActor.SequencePlayer.OnFinished:Clear()
        self.SubLevelSequenceActor.SequencePlayer.OnFinished:Add(self, UI_Dialog_Story_C.OnPlaySequenceEnd)
        local playRate = 1.0
        if self.isPlayRate then
            local endTime = self.SubLevelSequenceActor.SequencePlayer:GetEndTime().Time.FrameNumber.Value
            local curTime = self.SubLevelSequenceActor.SequencePlayer:GetCurrentTime().Time.FrameNumber.Value
            local leftTime = (endTime - curTime) / self.SubLevelSequenceActor.SequencePlayer:GetFrameRate().Numerator
            playRate = leftTime / self.PlayRateTime
        end
        LOG_INFO("------->init play rate:" .. tostring(playRate))
        self.SubLevelSequenceActor.SequencePlayer:SetPlayRate(playRate)
        if not should_play_after then
            self.SubLevelSequenceActor.SequencePlayer:PlayLooping(0)
        end
    end
end

function UI_Dialog_Story_C:PlayCameraSequence(path, should_play_after)
    print("===PlayCameraSequence:" .. tostring(path) .. ',cameraPath:' .. tostring(self.CurData.cameraPath))
    if self.IsAnimationNotify then
        self.IsAnimationNotify = false
        print("---------isAn")
        do return end
    end
    if self.LastCameraSequencePath == path then
        return
    end

    --加载sequence
    local levelSequence = self:GetSequence(path)
    if not levelSequence or not UE.UKismetSystemLibrary.IsValid(levelSequence) then
        levelSequence = LoadObject(path)
        if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
            LOG_ERROR("===播放Onece->sequence错误!!!,path:" .. tostring(path))
            return 
        else
            self:AddSequence(path, levelSequence)
        end
    end
    if self.LastCameraSequencePath ~= path and self.CameraSequenceActor and UE.UKismetSystemLibrary.IsValid(self.CameraSequenceActor) then
        self.CameraSequenceActor:K2_DestroyActor()
        self.CameraSequenceActor = nil
    end
    self.LastCameraSequencePath = path
    print("-------->levelSequence.SequenceFlags:" .. tostring(levelSequence))
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation

    if not self.CameraSequenceActor then
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        --配置
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        
        local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, 
            Settings, nil)

        self.CameraSequenceActor = levelSequenceActor
        self.CameraSequenceActorRef = UnLua.Ref(levelSequenceActor)
        -- self.SubLevelSequenceActor.CameraSettings = UE.FLevelSequenceCameraSettings()
        -- self.CameraSequenceActor.SequencePlayer.OnFinished:Clear()
        -- self.CameraSequenceActor.SequencePlayer.OnFinished:Add(self, UI_Dialog_Story_C.OnPlaySequenceEnd)

       
        --print("-----GetFrameDuration:" .. tostring(self.InitFrameDuration))
        -- self.CameraSequenceActor.SequencePlayer:PlayLooping(0)
    else
         self.CameraSequenceActor:SetSequence(levelSequence)
    end
    
    if self.CameraSequenceActor and self.CameraSequenceActor.SequencePlayer then
        -- self.CameraSequenceActor:SetSequence(levelSequence)
        self.CameraInitFrameDuration = self.CameraSequenceActor.SequencePlayer:GetFrameDuration()


        -- self.CameraSequenceActor.SequencePlayer.OnFinished:Clear()
        -- self.CameraSequenceActor.SequencePlayer.OnFinished:Add(self, UI_Dialog_Story_C.OnPlaySequenceEnd)

        local playRate = 1.0
        if self.isPlayRate then
            local endTime = self.CameraSequenceActor.SequencePlayer:GetEndTime().Time.FrameNumber.Value
            local curTime = self.CameraSequenceActor.SequencePlayer:GetCurrentTime().Time.FrameNumber.Value
            local leftTime = (endTime - curTime) / self.CameraSequenceActor.SequencePlayer:GetFrameRate().Numerator
            playRate = leftTime / self.PlayRateTime
        end
        LOG_INFO("------->init play rate:" .. tostring(playRate))
        self.CameraSequenceActor.SequencePlayer:SetPlayRate(playRate)
        if not should_play_after then
            self.CameraSequenceActor.SequencePlayer:PlayLooping(0)
        end
    end
end

function UI_Dialog_Story_C:PlaySequenceLoop(path)
    -- print("===self.MainSequencePath:" .. tostring(self.MainSequencePath))
    print("===PlaySequenceLoop:" .. tostring(path))
    do return end
    if not self.MainSequencePath or self.MainSequencePath ~= path then
        --加载sequence
        local levelSequence = self:GetSequence(path)
        if not levelSequence then
            levelSequence = LoadObject(path)
            if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
                LOG_ERROR("===播放Loop->sequence错误!!!,path:" .. tostring(path))
                return 
            end
            self:AddSequence(path, levelSequence)
        end

        -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
    
        if not self.MainLevelSequenceActor then
            local LoopCount = UE.FMovieSceneSequenceLoopCount()
            LoopCount.Value = -1
            --配置
            local Settings = UE.FMovieSceneSequencePlaybackSettings()
            Settings.LoopCount = LoopCount
            --Settings.bPauseAtEnd = false
            --Settings.bRestoreState = false
    
            -- local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, 
            --     Settings, self.MainLevelSequenceActor)
            local _, levelSequenceActor = self:PlayLoopSequence(levelSequence)
            self.MainLevelSequenceActor = levelSequenceActor
            self.SubLevelSequenceActorRef = UnLua.Ref(levelSequenceActor)
            --self.MainLevelSequenceActor.CameraSettings = UE.FLevelSequenceCameraSettings()
        end

        if self.MainLevelSequenceActor and self.MainLevelSequenceActor.SequencePlayer then
            self.MainLevelSequenceActor.SequencePlayer:GoToEndAndStop()
            self.MainLevelSequenceActor:SetSequence(levelSequence)
            local playRate = 1.0
            if self.isPlayRate then
                local endTime = self.MainLevelSequenceActor.SequencePlayer:GetEndTime().Time.FrameNumber.Value
                local curTime = self.MainLevelSequenceActor.SequencePlayer:GetCurrentTime().Time.FrameNumber.Value
                local leftTime = (endTime - curTime) / self.MainLevelSequenceActor.SequencePlayer:GetFrameRate().Numerator
                playRate = leftTime / self.PlayRateTime
            end
            LOG_INFO("------->init play rate:" .. tostring(playRate))
            self.MainLevelSequenceActor.SequencePlayer:SetPlayRate(playRate)
            --self.MainLevelSequenceActor.SequencePlayer:PlayLooping(-1)
            self.MainLevelSequenceActor.SequencePlayer:PlayLooping(-1)
        end
    else
        if self.MainLevelSequenceActor and self.MainLevelSequenceActor.SequencePlayer then
            -- self.MainLevelSequenceActor.SequencePlayer:GoToEndAndStop()
            -- local playRate = 1.0
            -- if self.isPlayRate then
            --     local endTime = self.MainLevelSequenceActor.SequencePlayer:GetEndTime().Time.FrameNumber.Value
            --     local curTime = self.MainLevelSequenceActor.SequencePlayer:GetCurrentTime().Time.FrameNumber.Value
            --     local leftTime = (endTime - curTime) / self.MainLevelSequenceActor.SequencePlayer:GetFrameRate().Numerator
            --     playRate = leftTime / self.PlayRateTime
            -- end
            -- self.MainLevelSequenceActor.SequencePlayer:SetPlayRate(playRate)
            self.MainLevelSequenceActor.SequencePlayer:PlayLooping(-1)
        end
    end
    self.MainSequencePath = path
end

function UI_Dialog_Story_C:OnTimerFadeInEnd()
    -- 相当于在蓝图中的 Clear and Invalidate Timer by Handle
    UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
    self.TimerHandle = nil

    self:StartPlay()
end

function UI_Dialog_Story_C:OnTimerFadeOutEnd()
    -- 相当于在蓝图中的 Clear and Invalidate Timer by Handle
    UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
    self.TimerHandle = nil

    self:PlayToNext()
end

--播放完毕处理
function UI_Dialog_Story_C:IsPlayEnd()
    self.bIsPlayEnd = true
    print("------------UI_Dialog_Story_C:IsPlayEnd")
    -- self.CachedSequence:Clear()
    if self.MainLevelSequenceActor then
        -- self.MainLevelSequenceActor.SequencePlayer.OnFinished:Clear()
        self.MainLevelSequenceActor:K2_DestroyActor()
        self.MainLevelSequenceActor = nil
    end

    if self.SubLevelSequenceActor then
        -- self.SubLevelSequenceActor.SequencePlayer:Stop()
        self.SubLevelSequenceActor.SequencePlayer.OnFinished:Clear()
        -- self.SubLevelSequenceActor.SequencePlayer:GoToEndAndStop()
        self.SubLevelSequenceActor:K2_DestroyActor()
        self.SubLevelSequenceActor = nil
    end

    if self.CameraSequenceActor then
        if self.CameraSequenceActor.SequencePlayer then
            -- self.CameraSequenceActor.SequencePlayer:Stop()
            self.CameraSequenceActor.SequencePlayer.OnFinished:Clear()
        end
        self.CameraSequenceActor:K2_DestroyActor()
        self.CameraSequenceActor = nil
    end

    if self.MediaPlayerActor then
        self.MediaPlayerActor:K2_DestroyActor()
        self.MediaPlayerActor = nil
    end

    --self:BlendCameraToMainCamera()
   
    self:UnbindAllFromAnimationFinished(self.MaskFadeIn)
    self:UnbindAllFromAnimationFinished(self.MaskFadeOut)
    self:UnbindAllFromAnimationFinished(self.BlackGroundFadeIn)
    self:UnbindAllFromAnimationFinished(self.BlackGroundFadeOut)

    --避免黑屏
    --local PlayerCameraManager = UE.UGameplayStatics.GetPlayerCameraManager(self,0)
    --PlayerCameraManager:StopCameraFade()
    -- print("====map:" .. tostring(self.CurData.mapPath))
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if self.LastMapPath ~= '' then
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        -- 卸载场景时会有高级黑屏UI_Loading2
        -- pc.BP_ScreenFade:FadeIn(false)
        local player = pc:K2_GetPawn()
        if player then
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            gameMode:BPI_SetPlayer(player)
            player:SetActorEnableCollision(false)
            player:SetActorHiddenInGame(true)
            player.Mesh:SetEnableGravity(false)
            player.CharacterMovement:SetActive(false, false)
        end

        gameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
        gameInstance:LeaveStreamingLevel(true, { self, self.OnBackLevel })
    else
        self:OnBackLevel()
    end
end

function UI_Dialog_Story_C:OnBackLevel()
    print('-----OnBackLevel:')
    if not UE.UGameplayStatics.IsValid(self) then
        print("------------>场景已经切换，后续不再处理")
        self = UIManager:GetInstance():AddUMG('UI_Dialog_Story')
        self:OnBackLevel()
        do return end
    end
     
    if self.InitBlock then
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        self.InitBlock = false
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    --关闭load2
    if self.ShouldHideLoading2InBackLevel then
        self.ShouldHideLoading2InBackLevel = false
        local ui = gameInstance:GetUMG("UI_Loading2")
        if ui then
            ui:DelayDestroy()
        end
    end

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        MessageManager:GetInstance():Broadcast('Set_Disable_LoadingAnim')
        -- playerController.BP_ScreenFade:FadeOut(false)

        if gameMode.Player and playerController then
            gameMode.Player.CharacterMovement.GravityScale = self.DefaultGravityScale
            gameMode.Player:SetActorHiddenInGame(false)
            
            playerController:SetViewTargetWithBlend(gameMode.Player, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
        else
            if UE.UKismetSystemLibrary.IsValid(gameInstance.PreViewTarget) then
                playerController:Possess(gameInstance.PreViewTarget)
                -- playerController:SetViewTargetWithBlend(gameInstance.PreViewTarget, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
                gameInstance.PreViewTarget = nil
            end
        end
    end
    gameInstance:ShowAllUI()
       
    if gameInstance.UI_Dialog_Story then
        gameInstance.UI_Dialog_Story = nil
    end 
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        player:SetActorEnableCollision(true)
        player:SetActorHiddenInGame(false)
        player.Mesh:SetEnableGravity(true)
        player.CharacterMovement:SetActive(true, false)
    end
 
    self:OnPlayEnd()
end

function UI_Dialog_Story_C:OnPlayAnimationFadeInEnd()
    print("---------OnPlayAnimationFadeInEnd")
    --self.BlackgroundMask:SetVisibility(UE.ESlateVisibility.Visible)
    if self.CurData.showText == '' and (self.CurData.StartMaskFadeIn <= 0) then
        self:PlayToNext()
    end
end

function UI_Dialog_Story_C:OnPlayAnimationFadeOutEnd()
    self.bIsFirstEnter = true
    self:PlayNext()
end

function UI_Dialog_Story_C:OnPlayMediaEnd()
    self:PlayNext()
end

function UI_Dialog_Story_C:OnPlaySequenceEnd()
    self.Black:SetVisibility(UE.ESlateVisibility.Visible)
    print("========OnPlaySequenceEnd:" .. tostring(self.CurData.cutScenePath))
    -- if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer then
    --     --self.SubLevelSequenceActor.SequencePlayer:GoToEndAndStop()
    --     self.SubLevelSequenceActor.SequencePlayer.OnFinished:Clear()
    --             self.SubLevelSequenceActor:K2_DestroyActor()
    --         self.SubLevelSequenceActor = nil
    --     end
    -- if self.PlayType == EPlayType.Event then
       
    -- end

    -- if self.CurData.playLoopPath and self.CurData.playLoopPath ~= '' then
    --     self:PlaySequenceLoop(self.CurData.playLoopPath)
    --     if self.isAutoPlay or self.PlayType == EPlayType.PlaySequence or self.PlayType == EPlayType.Event then
    --         self:PlayNext()
    --     end
    if self.isAutoPlay or self.PlayType == EPlayType.PlaySequence or self.PlayType == EPlayType.Event then
        self:PlayNext()
    end
    -- elseif self.CurData.playLoopPath and self.CurData.playLoopPath == '' then
    --     if self.PlayType ~= EPlayType.Option and self.PlayType ~= EPlayType.PlaySequence then
    --         self:PlayNext()
    --     end
    -- end
end

function UI_Dialog_Story_C:PlayNext()
    self.DialogStart = false
    if not self.CurData then
        return
    end
   
    if self.MediaPlayer and self.MediaPlayer:IsPlaying() then
        self.MediaPlayer:Close()
        self.MediaPlayer.OnEndReached:Clear()
    end

    if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer then
        self.SubLevelSequenceActor.SequencePlayer.OnFinished:Clear()
    end 

    self:UnbindAllFromAnimationFinished(self.MaskFadeIn)
    self:UnbindAllFromAnimationFinished(self.MaskFadeOut)
    self:UnbindAllFromAnimationFinished(self.BlackGroundFadeIn)
    self:UnbindAllFromAnimationFinished(self.BlackGroundFadeOut)

    self.Panel_Media:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Dialog:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Background:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Option:SetVisibility(UE.ESlateVisibility.Hidden)

    if self.CurData.EndMaskFadeIn == 1 then
        self:PlayEndMaskFadeIn()
    elseif self.CurData.EndMaskFadeOut == 1 then
        self:PlayEndMaskFadeOut()
    else
        self:PlayToNext()
    end
end

function UI_Dialog_Story_C:PlayToNext()
    if self.bIsPlayEnd or self.PlayType == EPlayType.Option then
        return
    end
    -- print('---------PlayToNext:' .. tostring(UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)))
    --口型
    if self.CurData.NpcSpeak ~= '' then
        local arrString = string.split(self.CurData.NpcSpeak, '|')
        if arrString[1] and arrString[1] ~= '' then
            local charList = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, arrString[1])
            if charList:Length() > 0 then
                local charActor = charList:Get(1)
                if charActor and charActor.StopSpeakAnimation then
                    charActor:StopSpeakAnimation() 
                end
            end
        end
    end

    --下一节id
    if self.CurData.next and self.CurData.next > 0 then
        self.IsAnimationNotify = false
        self:UpdateUI(self.CurData.next)
    else
        self.bIsPlayEnd = true
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.025)
            self:IsPlayEnd()
        end))
    end
end

function UI_Dialog_Story_C:UIMaskFadeUpdate()
    
end


--暂停
function UI_Dialog_Story_C:Pause()
    self.IsPause = true
  
    if self.SubLevelSequenceActor then
        self.SubLevelSequenceActor.SequencePlayer:Pause()
    end

    if self.CameraSequenceActor then
        self.CameraSequenceActor.SequencePlayer:Pause()
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
function UI_Dialog_Story_C:Resume()
    if self.SubLevelSequenceActor then
        self.SubLevelSequenceActor.SequencePlayer:Play()
    end

    if self.CameraSequenceActor then
        self.CameraSequenceActor.SequencePlayer:Play()
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

----------------------------------------------------------------------
---自动播放点击事件
function UI_Dialog_Story_C:OnClicked_AutoPlay()
    self.isAutoPlay = not self.isAutoPlay
    if self.isAutoPlay then
        self:PlayNext()
    end
end

function UI_Dialog_Story_C:OnClicked_Skip()
    self:Pause()
    UIManager:GetInstance():ShowConfirm({
        notice = Database.L10n(self.word_id == 471 and 496 or 497),
        confirm = function()
            if not UE.UKismetSystemLibrary.IsValid(self) then return end
            self:Resume()
            self:ConfirmSkip()
        end,
        cancel = function ()
            self:Resume()
        end,
        showCancel = true,
    })
end

function UI_Dialog_Story_C:ConfirmSkip()
    -- UIManager:GetInstance():ClearConfirm()
    if not self.CurData or self:IsAnimationPlaying(self.BlackGroundFadeIn) or 
        self:IsAnimationPlaying(self.BlackGroundFadeOut) or
        self:IsAnimationPlaying(self.MaskFadeIn) or 
        self:IsAnimationPlaying(self.MaskFadeOut) then
            print("-------------->is play fade")
        return
    end

    local now = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
    if not self.LastDialogTime then
        self.LastDialogTime = now - 1 
    end
    local duration = now - self.LastDialogTime
    if duration < self.DialogDuration then
        return
    end
    self.LastDialogTime = now
    
    if self.PlayType == EPlayType.PlayBackground then
        self:OnClicked_BlackgroundMask()
    else
        if (not self.CurData or self.CurData.skipButton ~= 1)--[[ and self.AllFinished]] then
            if self.TargetOptionId > 0 then
                self:UpdateUI(self.TargetOptionId)
            else
                self:IsPlayEnd()
            end
        else
            --self:PlayNext()
            if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer and self.SubLevelSequenceActor.SequencePlayer:IsPlaying() then
                -- if not self.AnimationLooping then
                --     local sequencePlayer = self.SubLevelSequenceActor.SequencePlayer
                --     local playRate = 1.0
                --     local targetTime = 1
                --     local endTime = sequencePlayer:GetEndTime().Time.FrameNumber.Value
                --     local curTime = sequencePlayer:GetCurrentTime().Time.FrameNumber.Value
                --     local leftTime = (endTime - curTime) / sequencePlayer:GetFrameRate().Numerator
                --     if leftTime > targetTime then
                --         playRate = leftTime / targetTime
                --         playRate = math.min(5, playRate)
                --     end

                --     print("---------播放速率:" .. tostring(playRate))
                --     sequencePlayer:SetPlayRate(playRate)
                --     self.AnimationSkip = true
                -- else
                    self:PlayNext()
                -- end
            else
                self:PlayNext()
            end
        end
    end
end

function UI_Dialog_Story_C:OnClicked_BlackgroundMask()
    if self.LongPressedTimeHanlder then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressedTimeHanlder)
        self.LongPressedTimeHanlder = nil
    end

    if not self.CurData or self:IsAnimationPlaying(self.BlackGroundFadeIn) or 
        self:IsAnimationPlaying(self.BlackGroundFadeOut) or
        self:IsAnimationPlaying(self.MaskFadeIn) or 
        self:IsAnimationPlaying(self.MaskFadeOut) then
        LOG_ERROR('----------等待黑白文字 播放完毕')
        return UE.UWidgetBlueprintLibrary.Handled()
    end

    --时间判断
    -- local duration = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self) - self.LastBlackBackgroundTime
    -- if duration < self.BlackBackgroundDuration then
        --     --UIUtils.ShowNotify(self, '点击太频繁, 请等待')
        --     return UE.UWidgetBlueprintLibrary.Handled()
    -- end

    if self.PlayType == EPlayType.Option or self.PlayType == EPlayType.AsideEvent or self.CurData.skipButton == 1 then
        return UE.UWidgetBlueprintLibrary.Handled()
    end

    self:CheckNext()

    return UE.UWidgetBlueprintLibrary.Handled()
end

function UI_Dialog_Story_C:CheckNext()
    -- print('---------next:' .. tostring(UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)))
    --下一节id
    if self.CurData.next then
        --结束播放
        if (self.CurData.next == 0 and self.PlayType == EPlayType.PlayBackground) then
            self:BindToAnimationFinished(self.BlackGroundFadeOut, function()
                self:OnPlayAnimationFadeOutEnd()
            end)
            --播放渐隐动画
            self:PlayAnimation(self.BlackGroundFadeOut)
        elseif self.CurData.next > 0 then --判断下一节是否是黑白文字
            --特殊处理,判断下一节是否还是黑底白字
            local data = self:GetStoryDialogTable(self.CurData.next)
            if data and self.PlayType == EPlayType.PlayBackground and data.playType ~= self.PlayType then
                self:BindToAnimationFinished(self.BlackGroundFadeOut, function()
                    self:OnPlayAnimationFadeOutEnd()
                end)
                --播放渐隐动画
                self:PlayAnimationForward(self.BlackGroundFadeOut)
            else
                self:UpdateUI(self.CurData.next)
            end
        else
            self:UpdateUI(self.CurData.next)
        end
    else
        self:IsPlayEnd()
    end
end

function UI_Dialog_Story_C:OnClicked_Option(index, content)
    MessageManager:GetInstance():Broadcast("Dialog_clicked_option", self.CurData.id, index)
    content = tonumber(content)
    if content and content > 0 then
        self:UpdateUI(content)
    else
        self:IsPlayEnd()
    end
end

function UI_Dialog_Story_C:OnClicked_MaskSkipPlay()
    local now = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
    self.YouJustLookAtMe = self.YouJustLookAtMe or -1
    if now - self.YouJustLookAtMe < 0.1 then
        return
    end
    self.YouJustLookAtMe = now
    if self.PlayType == EPlayType.Option or self.PlayType == EPlayType.AsideEvent or self.CurData.skipButton == 1 then
        return
    end
    -- local duration = now - (self.LastDialogTime or now)

    -- if duration < self.DialogDuration then
        --     --UIUtils.ShowNotify(self, '点击太频繁, 请等待')
        --     return
    -- end

    if not self.CurData or self:IsAnimationPlaying(self.BlackGroundFadeIn) or 
        self:IsAnimationPlaying(self.BlackGroundFadeOut) or
        self:IsAnimationPlaying(self.MaskFadeIn) or 
        self:IsAnimationPlaying(self.MaskFadeOut) then
        return
    end
  
    if not self.LastDialogTime then
        self.LastDialogTime = (now - 1)
    end
    local duration = now - self.LastDialogTime 
    if duration < self.DialogDuration then
        return
    end
    --如果在加载场景
    if self.bIsLoadingMap then 
        print("----------当前在加载地图！！！")
        return 
    end

    if self.bIsPlayEnd then
        print("----------剧情已经结束！！！")
        return 
    end

    if self.PlayType == EPlayType.PlayBackground then
        self:OnClicked_BlackgroundMask()
    else
        if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer and self.SubLevelSequenceActor.SequencePlayer:IsPlaying() then
            -- if not self.AnimationLooping then
            --     local sequencePlayer = self.SubLevelSequenceActor.SequencePlayer
            --     local playRate = 1.0
            --     local targetTime = 0.5
            --     local endTime = sequencePlayer:GetEndTime().Time.FrameNumber.Value
            --     local curTime = sequencePlayer:GetCurrentTime().Time.FrameNumber.Value
            --     local leftTime = (endTime - curTime) / sequencePlayer:GetFrameRate().Numerator
            --     if leftTime > targetTime then
            --         playRate = leftTime / targetTime
            --         playRate = math.min(10, playRate)
            --     end
                
            --     print("---------播放速率:" .. tostring(playRate))
                -- sequencePlayer:SetPlayRate(playRate)
                -- self.AnimationSkip = true
            -- else
                self:PlayNext()
            -- end
        else
            self:PlayNext()
        end
    end
end

function UI_Dialog_Story_C:OnPressed_MaskShipPlay()
    if self.PlayType == EPlayType.Option then
        return
    end
    if self.LongPressedTimeHanlder then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressedTimeHanlder)
        self.LongPressedTimeHanlder = nil
    end

    self.LongPressedTimeHanlder = UE.UKismetSystemLibrary.K2_SetTimerDelegate({ self, self.OnLongPressed }, self.LongPressedTimeDuration or 1, true, self.LongPressedInitDelay or 2)
end

function UI_Dialog_Story_C:OnReleased_MaskShipPlay()
    if self.LongPressedTimeHanlder then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressedTimeHanlder)
        self.LongPressedTimeHanlder = nil
    end
end

-- function UI_Dialog_Story_C:IA_Confirm_Completed()
--     self:OnReleased_MaskShipPlay()
--     self:OnClicked_MaskSkipPlay()

--     if self.PlayType == EPlayType.AsideEvent then
--         self:OnClicked_Btn_Aside()
--     end
--     if self.PlayType == EPlayType.Option then
--         self:OnClicked_Img_OptionBg()
--     end
-- end

function UI_Dialog_Story_C:OnLongPressed()
    if self.PlayType == EPlayType.Option or self.PlayType == EPlayType.AsideEvent or self.CurData.skipButton == 1 then
        if self.LongPressedTimeHanlder then
            UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressedTimeHanlder)
            self.LongPressedTimeHanlder = nil
        end
        return
    end
    local now = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
    if not self.LastDialogTime then
        self.LastDialogTime = now - 1 
    end
    local duration = now - (self.LastDialogTime or now)

    if duration < self.DialogDuration then
        return
    end
    self.LastDialogTime = now

    self:PlayNext()
end

function UI_Dialog_Story_C:OnClicked_HLinkBg()
    self.Panel_HLink:SetVisibility(UE.ESlateVisibility.Hidden)
    return UE.UWidgetBlueprintLibrary.Handled()
end

function UI_Dialog_Story_C:OnClicked_RichTextLink(action)
    local vars = string.split(action, ':')
    if vars and #vars > 1 then
        local t = tonumber(vars[1])
        local v = vars[2]
        -- print('------t->' .. tostring(t) .. ',v->' .. tostring(v))
        if t == 1 then
            self.Text_LinkDes:SetText(action)
            self.Panel_HLink:SetVisibility(UE.ESlateVisibility.Visible)
        elseif t == 2 then
            UE.UGameplayStatics.GetGameInstance(self):OnMessage('handbook', tonumber(v))
        end
    end
end

--视频跳过
function UI_Dialog_Story_C:OnClicked_Img_Media()
    if not self.CurData or self:IsAnimationPlaying(self.BlackGroundFadeIn) or 
        self:IsAnimationPlaying(self.BlackGroundFadeOut) or
        self:IsAnimationPlaying(self.MaskFadeIn) or 
        self:IsAnimationPlaying(self.MaskFadeOut) then
        return UE.UWidgetBlueprintLibrary.Handled()
    end

    local now = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
    if not self.LastDialogTime then
        self.LastDialogTime = now - 1
    end
    --对话间隔时间一致
    local duration = now - self.LastDialogTime 
    if duration < self.DialogDuration then
        return UE.UWidgetBlueprintLibrary.Handled()
    end
    self.LastDialogTime = now

    self:PlayNext()
    return UE.UWidgetBlueprintLibrary.Handled()
end

function UI_Dialog_Story_C:OnClicked_Img_OptionBg()
    self.Img_OptionBg:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.BackgroundBlur_Option:SetVisibility(UE.ESlateVisibility.Visible)
    self:PlayOption()
    return UE.UWidgetBlueprintLibrary.Handled()
end

function UI_Dialog_Story_C:OnGHSClicked_Btn_PlayRate()
    --类型判断
    if self.CurData then
        if self.PlayType == EPlayType.PlaySequence or self.PlayType == EPlayType.PlayDialog then
            if self.SubLevelSequenceActor and self.SubLevelSequenceActor.SequencePlayer and self.SubLevelSequenceActor.SequencePlayer:IsPlaying() then
                local sequencePlayer = self.SubLevelSequenceActor.SequencePlayer
                local playRate = 1.0
                local targetTime = self.PlayRateTime
                targetTime = targetTime > 0.00001 and targetTime or 0.5
                local endTime = sequencePlayer:GetEndTime().Time.FrameNumber.Value
                local curTime = sequencePlayer:GetCurrentTime().Time.FrameNumber.Value
                local leftTime = (endTime - curTime) / sequencePlayer:GetFrameRate().Numerator
                if leftTime > self.PlayRateTime then
                    playRate = leftTime / targetTime
                end
                LOG_INFO("------->init play rate:" .. tostring(playRate))
                sequencePlayer:SetPlayRate(playRate)
            elseif self.MainLevelSequenceActor and self.MainLevelSequenceActor.SequencePlayer and self.MainLevelSequenceActor.SequencePlayer:IsPlaying() then
                self:PlayNext()
            end
        elseif self.PlayType == EPlayType.PlayMedia then
            if self.MediaPlayer and self.MediaPlayer:IsPlaying() then
                --视频加速
                self.MediaPlayer:SetRate(2)
            end
        else
            --self:PlayNext()
        end
    end
end

function UI_Dialog_Story_C:OnGHSPressed_Btn_PlayRate()
    self.isPlayRate = true
end

function UI_Dialog_Story_C:OnGHSReleased_Btn_PlayRate()
    self.isPlayRate = false
end

function UI_Dialog_Story_C:OnClicked_Btn_Aside()
    if not self:IsAnimationPlaying(self.MaskFadeIn) and not self:IsAnimationPlaying(self.MaskFadeOut) then
        self:PlayNext()
    end
end

----------------------------------------------------------------------
---获取配置表
function UI_Dialog_Story_C:GetStoryDialogTable(key, attr)
    if type(key) ~= "number" then
        key = tonumber(key)
    end
    if StoryDialogTable[key] then
        if attr and StoryDialogTable[key][attr] then
            return StoryDialogTable[key][attr]
        else
            return StoryDialogTable[key]
        end
    end
end

function UI_Dialog_Story_C:OnPlayEnd()
    local dialogEndId  = self:GetStartDialogId()
    print('----end:' .. tostring(dialogEndId) .. ',cur:' .. tostring(self.dialogId))
    if dialogEndId ~= self.dialogId then
        MessageManager:GetInstance():Broadcast(UI_Dialog_Story_C.DialogEnd, self.originDialogId, dialogEndId, 1)
    else
        MessageManager:GetInstance():Broadcast(UI_Dialog_Story_C.DialogEnd, self.originDialogId, self.dialogId, 1)
    end
    if dialogEndId == 1000095002 
        or 1000119 == dialogEndId 
        or 1000009 == dialogEndId 
        or 1000093002 == dialogEndId 
        or 1000052 == dialogEndId
        or 1000020 == dialogEndId
        or 1000010 == dialogEndId
        or 1000029001 == dialogEndId
        or 1000030000 == dialogEndId
        or 1000034001 == dialogEndId
        or 1000079020 == dialogEndId then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:GetOrAddUMG('UI_Loading2')
    end

    self.Overridden.OnPlayEnd(self)
    print('--------播放完毕:')
    UIManager:GetInstance():RemoveUI(self)
end

function UI_Dialog_Story_C:GetDisplayName(type)
    for name, value in pairs(EPlayType) do
        if value == type then
            return name
        end
    end
    return 'None'
end

function UI_Dialog_Story_C:GetNextConfig(id)
    for id, config in pairs(StoryDialogTable) do
        if config and config.next == id then
            return config
        end
    end
    return nil
end

function UI_Dialog_Story_C:GetStartDialogId()
    local PlotSystem = require("Module.Plot.PlotSystem")
    local config = self.CurData
    while (config and config.next > 0) do
        local data = self:GetStoryDialogTable(config.next)
        if data then
            config = data
        else
            break
        end
    end
    return config.id
end

return UI_Dialog_Story_C
