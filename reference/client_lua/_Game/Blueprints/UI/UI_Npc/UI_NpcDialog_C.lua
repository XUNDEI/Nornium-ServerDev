--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"

---@type UI_NpcDialog_C
local UI_NpcDialog_C = Class()

local UIUtils = require "_Game.Utils.UIUtils"
local DialogTalkTable = require "ClientDatas.d_story_bubble"
--构造函数
-- function UI_NpcDialog_C:Construct()
--     -- self.AudioComp = nil
--     -- self.LastShowHeadIcon = false

--     -- self.talkBox.OnMouseButtonDownEvent:Unbind()
--     -- self.talkBox.OnMouseButtonDownEvent:Bind(self, UI_NpcDialog_C.OnClicked_TalkBox)

    
-- end

function UI_NpcDialog_C:Destruct()
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
    end
    self.AudioComp = nil
end


function UI_NpcDialog_C:InitUI(id)
    self.IsStopping = false
    --self:StopAnimationsAndLatentActions()
    --print("===UI_NpcDialog_C.InitUI:" .. tostring(id))
    if not id or id == "" or not tonumber(id) or id == 0 then
        LOG_ERROR("=====>>错误id UI_NpcDialog_C:InitUI" .. tostring(id))
        self:OnPlayEnd()
        return
    end

    self.CurData = DialogTalkTable[id]
    if not self.CurData then
        LOG_ERROR("=====>>错误id not find in ClientDatas.d_story_bubble : " .. tostring(id))
        self:OnPlayEnd()
        return
    end

    self.Border:SetRenderOpacity(0)

    self.IsStopping = false

    self.TextShowTime = self.CurData.showTime
    self.TalkIndex = id

    self.CurData.showText = string.gsub(self.CurData.showText, '/n', '\n')
    self.CurData.showText = string.gsub(self.CurData.showText, '\r\n', '\n')
    self.CurData.showText = string.gsub(self.CurData.showText, '\\n', '\n')
    -- if self.CurData.showText ~= "" then
    --     local strArr = string.split(self.CurData.showText, '\n')
    --     if #strArr > 0 then
    --         self:SetTextContent(self.CurData.showText, #strArr, 1.15)
    --     end
    -- end
    local showText = UIUtils.ReplacePlayerName(self.CurData.showText)
    self.Text:SetText(showText)

    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
    end
    self.AudioComp = nil

    --播放声音
    if self.CurData.soundCue ~= '' then
        local audioSource = LoadObject(self.CurData.soundCue)
        if audioSource then
            if audioSource.Duration > self.TextShowTime then
                self.TextShowTime = audioSource.Duration
            end
            self.AudioComp = UE.UGameplayStatics.SpawnSound2D(self, audioSource)
        end
    end

    self.InitDelayTime = self.CurData.delayTime or 0.5
    if self.InitDelayTime > 0 then
        self.TimerHandle = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            { self, self.StartUI }, self.InitDelayTime, false)
    else
        self:StartUI()
    end
end

function UI_NpcDialog_C:StartUI()
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end

    self:UnbindAllFromAnimationFinished(self.UIFade)
    self:BindToAnimationFinished(self.UIFade, function()
        self:StartTextTimer()
    end)
    self:PlayAnimation(self.UIFade, 0.0, 1, UE.EUMGSequencePlayMode.Reverse)
end

function UI_NpcDialog_C:StopUI()
    self:CloseUI()
end

function UI_NpcDialog_C:CloseUI()
    self.Border:SetRenderOpacity(0)
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end
    if UE.UKismetSystemLibrary.IsValid(self.AudioComp) then
        self.AudioComp:Stop()
        self.AudioComp = nil
    end
    if self.TextFade then
        self:UnbindAllFromAnimationFinished(self.TextFade)
    end
    if self.UIFade then
        self:UnbindAllFromAnimationFinished(self.UIFade)
    end
    --self:StopAnimationsAndLatentActions()
    --self:RemoveFromViewport()
    if self.EventOnPlayEnd then
        self.EventOnPlayEnd:Broadcast()
    end
end

function UI_NpcDialog_C:StartTextTimer()
    self.TimerHandle = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        { self, self.OnPlayTextEnd }, self.TextShowTime, false)
end

function UI_NpcDialog_C:OnPlayTextEnd()
    if self.TimerHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TimerHandle)
        self.TimerHandle = nil
    end
    self:UnbindAllFromAnimationFinished(self.UIFade)
    if self.CurData and self.CurData.next and self.CurData.next ~= 0 then
        local nextConfig = DialogTalkTable[self.CurData.next]
        if nextConfig.npcID == self.CurData.npcID then
            self:BindToAnimationFinished(self.UIFade, function()
                self:InitUI(self.CurData.next)
            end)
            self:PlayAnimation(self.UIFade, 0.0, 1, UE.EUMGSequencePlayMode.Forward)
        else
            self:PlayNext()
        end
    else
        self:PlayNext()
    end
end

function UI_NpcDialog_C:PlayNext()
    self:CloseUI()
end

function UI_NpcDialog_C:OnPlayEnd()
    self:BindToAnimationFinished(self.UIFade, function() self:CloseUI() end)
    self:PlayAnimation(self.UIFade)
end

return UI_NpcDialog_C
