--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type STT_SwitchMap_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState(Transition)
    LOG_DEBUG('STT_SwitchMap_C:ReceiveLatentEnterState')
    -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- gameInstance:RemoveUMG("UI_Loading2")
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
    local function OnFadeInFinished()
        PC.BP_ScreenFade.OnFadeInFinished:Remove(self, OnFadeInFinished)
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.3)
            self.Overridden.ReceiveLatentEnterState(self, Transition)
        end))
    end
    PC.BP_ScreenFade.OnFadeInFinished:Add(self, OnFadeInFinished)
    PC.BP_ScreenFade:FadeIn(false, true)
    PC:DisableInput()
end

return M