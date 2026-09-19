--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"

---@type UI_Dialog_Talk_C
local UI_Dialog_Talk_C = Class()

UI_Dialog_Talk_C.EnableMove = true

UI_Dialog_Talk_C.TalkEnd = "UI_Dialog_Talk_C.TalkEnd"

local UIUtils = require "_Game.Utils.UIUtils"
local DialogTalkTable = require "ClientDatas.d_story_windowchat"
--构造函数
function UI_Dialog_Talk_C:Construct()
    self.AudioComp = nil
    self.LastShowHeadIcon = false
    self.HideCursor = true

    self.talkBox.OnMouseButtonDownEvent:Unbind()
    self.talkBox.OnMouseButtonDownEvent:Bind(self, UI_Dialog_Talk_C.OnClicked_TalkBox)
end

function UI_Dialog_Talk_C:Destruct()
    self.LastShowHeadIcon = false
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
    end
    self.AudioComp = nil

    if self.TextFade then
        self:UnbindAllFromAnimationFinished(self.TextFade)
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.UI_Dialog_Talk then
        gameInstance.UI_Dialog_Talk = nil
    end
end

function UI_Dialog_Talk_C:OnDialogEvent(params)
    if not params or type(params) ~= "string" or params == "" then
        return
    end
    local paramList = string.split(params, '|')
    if #paramList >= 2 then
        if tonumber(paramList[2]) == 1 then
            self:Pause()
        else
            self:Resume()
        end
    end
end

function UI_Dialog_Talk_C:InitUI(id)
    self.bIsEnding = false
    --self:StopAnimationsAndLatentActions()
    print("===lua talk initUI id:" .. tostring(id))
    if not id or id == "" or not tonumber(id) or id == 0 then
        LOG_ERROR("=====>>错误id UI_Dialog_CutScene_C:InitUI " .. tostring(id))
        self:OnPlayEnd()
        return
    end

    self.CurData = DialogTalkTable[id]
    if not self.CurData then
        LOG_ERROR("=====>>错误id not find in ClientDatas.d_story_windowchat : " .. tostring(id))
        self:OnPlayEnd()
        return
    end

    self.TextShowTime = self.CurData.showTime
    self.TalkIndex = id

    local GameInstance = UE.UGameplayStatics.GetGameInstance(self)
    GameInstance.DialogTalkIndex = id

    --self:SetVisibility(UE.ESlateVisibility.HitTestInvisible)

    self.Panel_Head:SetVisibility(self.CurData.headPath ~= "" and UE.ESlateVisibility.HitTestInvisible or UE.ESlateVisibility.Collapsed)
    if self.CurData.headPath ~= "" then
        local iconTexture = LoadObject(self.CurData.headPath)
        if iconTexture then
            --self.Talk_Head:SetBrushFromTexture(iconTexture)
            self.Talk_Head:SetBrushFromAtlasInterface(iconTexture)
        end
        if not self.LastShowHeadIcon then
            self:PlayAnimationReverse(self.HeadHidden)
        end
        self.LastShowHeadIcon = true
    else
        if self.LastShowHeadIcon then
            self:PlayAnimationForward(self.HeadHidden)
        end
        self.LastShowHeadIcon = false
    end

    local roleName = UIUtils.ReplacePlayerName(self.CurData.roleName)
    self.Text_RoleName:SetText(roleName)
    self.Text_RoleTitle:SetText(self.CurData.roleTitle)
    self.CurData.showText = string.gsub(self.CurData.showText, '/n', '\n')
    self.CurData.showText = string.gsub(self.CurData.showText, '\r\n', '\n')
    self.CurData.showText = string.gsub(self.CurData.showText, '\\n', '\n')
    if self.CurData.showText ~= "" then
        local strArr = string.split(self.CurData.showText, '\n')
        if #strArr > 0 then
            local showText = UIUtils.ReplacePlayerName(self.CurData.showText)
            self:SetTextContent(showText, #strArr, 1.15)
        end
    end

    local titleShow = self.CurData.roleTitle == "" and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible
    self.Img_TitleLeft:SetVisibility(titleShow)
    self.Img_TitleRight:SetVisibility(titleShow)

    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
    end
    self.AudioComp = nil

    if self.CurData.soundCue ~= "" then
        local audioSource = LoadObject(self.CurData.soundCue)
        if audioSource then
            if UE.UGameplayStatics.ObjectIsA(audioSource, UE.USoundBase.StaticClass()) then
                self.AudioComp = UE.UGameplayStatics.SpawnSound2D(self, audioSource)
            else
                LOG_ERROR("===错误的音频资源类型:", self.CurData.soundCue)
            end
        end
    end
    print("===self.TextFade:" .. tostring(self.TextFade))

    self:PlayAnimation(self.TextFade, 0.0, 1, UE.EUMGSequencePlayMode.Forward)
    self:StartTextTimer()
end

function UI_Dialog_Talk_C:CloseUI()
    self.LastShowHeadIcon = false
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:SetPaused(true)
    end

    --self:StopAnimationsAndLatentActions()
    UIManager:GetInstance():RemoveUI(self)

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.DialogTalkIndex = 0
    if gameInstance.UI_Dialog_Talk then
        gameInstance.UI_Dialog_Talk = nil
    end
    if self.EventOnPlayEnd then
        self.EventOnPlayEnd:Broadcast()
    end

    MessageManager:GetInstance():Broadcast(UI_Dialog_Talk_C.TalkEnd, self.TalkIndex, 3)
end

function UI_Dialog_Talk_C:StartTextTimer()
    print("====StartTextTimer:TextShowTime:" .. tostring(self.TextShowTime))
    self.TimerHandle = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        { self, self.OnPlayTextEnd }, self.TextShowTime, false)
end

function UI_Dialog_Talk_C:OnPlayTextEnd()
    print("====OnPlayTextEnd")
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end
    if not UE.UGameplayStatics.IsValid(self.TextFade) then
        print("----error in talk")
        return
    end
    self:UnbindAllFromAnimationFinished(self.TextFade)
    if self.CurData and self.CurData.next and self.CurData.next ~= 0 then
        if UE.UGameplayStatics.IsValid(self.TextFade) then
            print("===self.TextFade2:" .. tostring(self.TextFade))
            self:BindToAnimationFinished(self.TextFade, function()
                self:UnbindAllFromAnimationFinished(self.TextFade)
                self:PlayNext()
            end)
            self:PlayAnimation(self.TextFade, 0.0, 1, UE.EUMGSequencePlayMode.Reverse)
        else
            self:PlayNext()
        end
        
    else
        self:PlayNext()
    end
end

function UI_Dialog_Talk_C:PlayNext()
    if self.bIsEnding then return end
    print("====PlayNext")
    if self.CurData and self.CurData.next and self.CurData.next ~= 0 then
        self:InitUI(self.CurData.next)
    else
        self:OnPlayEnd()
    end
end

function UI_Dialog_Talk_C:OnPlayEnd()
    self.bIsEnding = true
    print("====OnPlayEnd")
    local GameInstance = UE.UGameplayStatics.GetGameInstance(self)
    GameInstance.DialogTalkIndex = 0

    self:BindToAnimationFinished(self.UIFade, function() self:CloseUI() end)
    self:PlayAnimation(self.UIFade)
    --self:CloseUI()
end

--暂停
function UI_Dialog_Talk_C:Pause()
    local GameInstance = UE.UGameplayStatics.GetGameInstance(self)
    GameInstance.DialogTalkIndex = self.CurData.id

    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        -- self.AudioComp.OnAudioFinished:Clear()
        self.AudioComp:FadeOut(self.AudioFadeOutDuration)
        --self.AudioComp:SetPaused(true)
    end
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end

    if self.TextFade then
        self:UnbindAllFromAnimationFinished(self.TextFade)
    end

    --self:SetVisibility(UE.ESlateVisibility.Hidden)
end

--恢复
function UI_Dialog_Talk_C:Resume()
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end
    -- if self.AudioComp then
    --     self.AudioComp.OnAudioFinished:Clear()
    -- end
    if self.TextFade then
        self:UnbindAllFromAnimationFinished(self.TextFade)
    end
    self:InitUI(self.CurData.id)
end

--隐藏显示头像
function UI_Dialog_Talk_C:ForceHideHeadUI(bShow)
    self.Panel_Head:SetVisibility(bShow and UE.ESlateVisibility.HitTestInvisible or UE.ESlateVisibility.Collapsed)
end

function UI_Dialog_Talk_C:OnClicked_TalkBox()
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        -- self.AudioComp.OnAudioFinished:Clear()
        self.AudioComp:FadeOut(self.AudioFadeOutDuration)
        --self.AudioComp:SetPaused(true)
    end
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end

    if self.TextFade then
        self:UnbindAllFromAnimationFinished(self.TextFade)
    end

    self:PlayNext()
    return UE.UWidgetBlueprintLibrary.Handled()
end

return UI_Dialog_Talk_C
