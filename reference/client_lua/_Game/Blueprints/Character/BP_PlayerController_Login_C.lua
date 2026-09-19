require "UnLua"

---@type BP_PlayerCharacter_City_C
local M = UnLua.Class()

function M:ReceiveBeginPlay()
    if not UIManager then
        UIManager = require("_Game.UI.UIManager")
    end
    UIManager:GetInstance():OnBeginPlay(self)
    UIManager:GetInstance():ShowWaterMask(self)

    --摄像机控制
    local cineCameraActor = UE.UGameplayStatics.GetActorOfClass(self, UE.ACineCameraActor)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController:SetViewTargetWithBlend(cineCameraActor, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.LoggedIn then
        local ui = gameInstance:AddLoadingUMG('UI_Loading', false)
        self.UILoading = ui

        -- gameMode.BP_Preload:PreloadAssets()
        coroutine.resume(coroutine.create(function()
            UE.UKismetSystemLibrary.Delay(self, 0.2)
            self:OnCurrentLevelOpenFinished()
        end))
    else
        local ui = gameInstance:AddUMG('UI_Login', false)
        ui:InitUI()
        ui:PlayShowCompanyLogo()
        self.UI_Login = ui

        --加载登录地图
        -- UE.UGHSFunctionLibrary.PreloadStreamingLevelByNampe(self, "CityLoginMap")
        -- local level = UE.UGameplayStatics.GetStreamingLevel(self, "CityLoginMap")
        -- gameInstance:StreamLevelSetShouldBeVisible("CityLoginMap", true)
    end
    UIManager:GetInstance().account = nil
    local LSM = UE.USubsystemBlueprintLibrary.GetGameInstanceSubsystem(self, UE.ULoadingScreenManager)
    LSM:SetForceSkipLoadingScreen(true)
    LSM:SetHoldLoadingScreenAdditionalSecsEvenInEditor(true)
end

function M:OnProcessLevelLoaded()
    print("====OnProcessLevelLoaded login")
    self.LoginPanelAnimating = false

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Login')
    ui:InitUI()
    if ui then
        ui:OnLevelLoaded()
    end
end

function M:OnCurrentLevelOpenFinished()
    if self.UILoading then
        UIManager:GetInstance():RemoveUI(self.UILoading)
        self.UILoading = nil
    end
    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Login')
    ui:PlayShowCompanyLogo()
    self.UI_Login = ui
end

return M