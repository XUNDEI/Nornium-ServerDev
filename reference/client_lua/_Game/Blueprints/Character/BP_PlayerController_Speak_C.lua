local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type BP_PlayerController_Speak_C
local M = UnLua.Class()

function M:SetUpInput()
    ---@type APlayerController
    local PC = UE.UGameplayStatics.GetPlayerController(self, 0)

    InputUtils.AddMappingContext(PC, InputAssets.IMC_Common)
    InputUtils.AddMappingContext(PC, InputAssets.IMC_Move)
    InputUtils.RegisterAllMappingContext(PC)

    PC.bShowMouseCursor = false
end

function M:ReceiveBeginPlay()
    self:SetUpInput()
    
    self.Overridden.ReceiveBeginPlay(self)
    UIManager:GetInstance():OnBeginPlay(self)
    UIManager:GetInstance():ShowWaterMask(self)
end

return M
