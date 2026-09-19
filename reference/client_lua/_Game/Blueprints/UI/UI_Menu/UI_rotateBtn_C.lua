--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type UI_rotateBtn_C
local M = UnLua.Class()

local ROTATE_SPEED = 5

function M:Tick(MyGeometry, InDeltaTime)
    if self.rotateLeftBtn:IsPressed() then
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController:K2_GetPawn():AddControllerYawInput(ROTATE_SPEED * InDeltaTime)
    elseif self.rotateRightBtn:IsPressed() then
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController:K2_GetPawn():AddControllerYawInput(-ROTATE_SPEED * InDeltaTime)
    end
end

return M
