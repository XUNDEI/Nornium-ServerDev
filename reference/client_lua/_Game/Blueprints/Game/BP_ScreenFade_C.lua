--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type BP_ScreenFade_C
local M = UnLua.Class()

-- function M:Initialize(Initializer)
-- end

-- function M:ReceiveBeginPlay()
-- end

-- function M:ReceiveEndPlay()
-- end

-- function M:ReceiveTick(DeltaSeconds)
-- end

function M:FadeIn(LongTime, KeepState)
    LOG_DEBUG_TRACKBACK("BP_ScreenFade_C:FadeIn")
    LongTime = LongTime or false
    KeepState = KeepState or false
    self.resume_use_fade_in = true
    self.resume_use_fade_out = false
    self.keep_state = KeepState
    -- self.Overridden.FadeIn(self)
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    ---@type UI_StreamLoading_C
    local loading_ui = gameInstance:GetUMG("UI_StreamLoading")
    if loading_ui then
        if self.DisableLoadingAnim then
            self:OnUIFadeInFinished()
        else
            -- loading_ui.OnFadeInFinished:Clear()
            -- loading_ui.OnFadeOutFinished:Clear()
            loading_ui.OnFadeInFinished:Remove(self, self.OnUIFadeInFinished)
            loading_ui.OnFadeOutFinished:Remove(self, self.OnUIFadeOutFinished)
            loading_ui.OnFadeInFinished:Add(self, self.OnUIFadeInFinished)
            -- loading_ui.OnFadeOutFinished:Add(self, self.OnUIFadeOutFinished)
            loading_ui:SetVisibility(UE.ESlateVisibility.Visible)
            loading_ui:PlayFadeIn(LongTime)
            gameInstance.IsFadeInOrOut = true
            if loading_ui:IsFadeAnimationPlaying() then
                local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
                PC:DisableInput()
            end
        end
    else
        loading_ui = gameInstance:AddUMG("UI_StreamLoading")
        loading_ui.OnFadeInFinished:Add(self, self.OnUIFadeInFinished)
        -- loading_ui.OnFadeOutFinished:Add(self, self.OnUIFadeOutFinished)
        loading_ui:SetVisibility(UE.ESlateVisibility.Visible)
        loading_ui:PlayFadeIn(LongTime)
        gameInstance.IsFadeInOrOut = true
        if loading_ui:IsFadeAnimationPlaying() then
            local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
            PC:DisableInput()
        end
    end
end

function M:FadeOut(LongTime, RestoreState)
    LOG_DEBUG_TRACKBACK("BP_ScreenFade_C:FadeOut")
    LongTime = LongTime or false
    RestoreState = RestoreState or false
    self.resume_use_fade_out = true
    self.resume_use_fade_in = false
    -- self.Overridden.FadeIn(self)
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    ---@type UI_StreamLoading_C
    local loading_ui = gameInstance:GetUMG("UI_StreamLoading")
    if loading_ui then
        if self.DisableLoadingAnim then
            self:OnUIFadeOutFinished()
        else
            -- loading_ui.OnFadeInFinished:Clear()
            -- loading_ui.OnFadeOutFinished:Clear()
            loading_ui.OnFadeInFinished:Remove(self, self.OnUIFadeInFinished)
            loading_ui.OnFadeOutFinished:Remove(self, self.OnUIFadeOutFinished)
            -- loading_ui.OnFadeInFinished:Add(self, self.OnUIFadeInFinished)
            loading_ui.OnFadeOutFinished:Add(self, self.OnUIFadeOutFinished)
            loading_ui:SetVisibility(UE.ESlateVisibility.Visible)
            loading_ui:PlayFadeOut(LongTime, RestoreState)
            gameInstance.IsFadeInOrOut = true
            if loading_ui:IsFadeAnimationPlaying() then
                local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
                PC:DisableInput()
            end
        end
    else
        loading_ui = gameInstance:AddUMG("UI_StreamLoading")
        -- loading_ui.OnFadeInFinished:Add(self, self.OnUIFadeInFinished)
        loading_ui.OnFadeOutFinished:Add(self, self.OnUIFadeOutFinished)
        loading_ui:SetVisibility(UE.ESlateVisibility.Visible)
        loading_ui:PlayFadeOut(LongTime, RestoreState)
        gameInstance.IsFadeInOrOut = true
        if loading_ui:IsFadeAnimationPlaying() then
            local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
            PC:DisableInput()
        end
    end
end

function M:PauseFade(LongTime)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local loading_ui = gameInstance:GetUMG("UI_StreamLoading")
    if loading_ui then
        loading_ui:PauseFade(LongTime)
    end
end

function M:ResumeFade(LongTime)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local loading_ui = gameInstance:GetUMG("UI_StreamLoading")
    if loading_ui then
        if self.resume_use_fade_in then
            self.resume_use_fade_in = false
            loading_ui:PlayFadeIn(LongTime)
        elseif self.resume_use_fade_out then
            self.resume_use_fade_out = false
            loading_ui:PlayFadeOut(LongTime, false)
        end
    end
end

function M:OnUIFadeInFinished()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    ---@type UI_StreamLoading_C
    local loading_ui = gameInstance:GetUMG("UI_StreamLoading")
    if loading_ui then
        -- loading_ui.OnFadeInFinished:Clear()
        -- loading_ui.OnFadeOutFinished:Clear()
        loading_ui.OnFadeInFinished:Remove(self, self.OnUIFadeInFinished)
        loading_ui.OnFadeOutFinished:Remove(self, self.OnUIFadeOutFinished)
        if not self.DisableLoadingAnim and not self.keep_state then
            gameInstance:RemoveUMG("UI_StreamLoading")
        end
    end
    self:CallOnFadeInFinished()
    gameInstance.IsFadeInOrOut = false
end

function M:OnUIFadeOutFinished()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    ---@type UI_StreamLoading_C
    local loading_ui = gameInstance:GetUMG("UI_StreamLoading")
    if loading_ui then
        -- loading_ui.OnFadeInFinished:Clear()
        -- loading_ui.OnFadeOutFinished:Clear()
        loading_ui.OnFadeInFinished:Remove(self, self.OnUIFadeInFinished)
        loading_ui.OnFadeOutFinished:Remove(self, self.OnUIFadeOutFinished)
        -- if not self.DisableLoadingAnim then
        --     gameInstance:RemoveUMG("UI_StreamLoading")
        -- end
        gameInstance:RemoveUMG("UI_StreamLoading")
    end
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    PC:EnableInput()
    self:CallOnFadeOutFinished()
    gameInstance.IsFadeInOrOut = false
end

return M
