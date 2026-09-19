--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type STT_PossessBuild_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState(Transition)
    LOG_DEBUG('STT_PossessBuild_C:ReceiveLatentEnterState')
    local actor = LoadClass('/Game/_Game/Blueprints/BuildingSystem/Blueprints/Interactables/BP_BuildActor.BP_BuildActor_C')
    local builds = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, actor, '100010101')
    for i = 1, builds:Num() do
        local build = builds[i]
        LOG_DEBUG('STT_PossessBuild_C:ReceiveLatentEnterState OnClicked_Controlled', build)
        build:OnClicked_Controlled()
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2")
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_ScreenFade:FadeOut(false, true)
    playerController.BP_ScreenFade:PauseFade()
    coroutine.resume(coroutine.create(function()
        UE.UKismetSystemLibrary.Delay(self, 0.3)
        playerController.BP_ScreenFade:ResumeFade()
    end))
end

return M