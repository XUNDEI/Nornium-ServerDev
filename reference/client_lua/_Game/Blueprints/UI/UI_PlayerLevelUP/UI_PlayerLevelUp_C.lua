
local Database = require('_Game.Utils.Database')

---@type UI_PlayerLevelUp_C
local M = UnLua.Class()

M.EnableMove = true

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

function M:Construct()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and playerController.BP_PlayerController_City_UniverseBridge then
        playerController.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    end
    self.ShowInteractOptions = false
    -- self.HideCursor = true
    self.Overridden.Construct(self)
end


return M
