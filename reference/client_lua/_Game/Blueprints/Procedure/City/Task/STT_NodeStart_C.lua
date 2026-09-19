--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type STT_NodeStart_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState(Transition)
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    local function OnFadeInFinished()
        PC.BP_ScreenFade.OnFadeInFinished:Remove(self, OnFadeInFinished)
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:RemoveUMG("UI_Loading2")
        PC.BP_ScreenFade:FadeOut(false, true)
        PC.BP_ScreenFade:PauseFade()
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.3)
            PC.BP_ScreenFade:ResumeFade()
            self.Overridden.ReceiveLatentEnterState(self, Transition)
        end))
    end
    PC.BP_ScreenFade.OnFadeInFinished:Add(self, OnFadeInFinished)
    PC.BP_ScreenFade:FadeIn(false, true)
end

function M:ExecTask()
    if self.playTime > 0 then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        ---@type UI_NodeStart_C
        local ui = gameInstance:AddUMG("UI_NodeStart")
        ui:InitUI(self.NameId, self.Index)
        ui.OnButtonDown:Add(self, self.DestroyUIImmediately)
        return UE.EStateTreeRunStatus.Running
    else
        self:FinishTask(false)
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:GetOrAddUMG("UI_Loading2")
        if ui then
            ui:DelayDestroy()
        end
        return UE.EStateTreeRunStatus.Failed
    end
end

function M:DestroyUI()
    coroutine.resume(coroutine.create(function()
        UE.UKismetSystemLibrary.Delay(self, self.playTime)
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:RemoveUMG("UI_NodeStart")
        self:FinishTask(true)
        self.Complete = true
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:GetOrAddUMG("UI_Loading2")
        if ui then
            ui:DelayDestroy()
        end
    end))
end

function M:DestroyUIImmediately()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_NodeStart")
    self:FinishTask(true)
    self.Complete = true
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:GetOrAddUMG("UI_Loading2")
        if ui then
            ui:DelayDestroy()
        end
end

return M