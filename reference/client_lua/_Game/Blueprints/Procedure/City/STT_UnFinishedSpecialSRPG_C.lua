--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local SrpgController = require("Module.Srpg.SrpgController")

---@type STT_UnfinishedSpecialSrpg_C
local M = UnLua.Class()

function M:ExecTask()
    if SrpgController:GetInstance():IsUniverseExist() and SrpgController:GetInstance():IsSpecificMap() then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.SRPGBackLevel = "CityMap"

        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        gameMode.LevelName = "UniverseMap"
        ---@type BP_PlayerController_City_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

        gameInstance:LoadLevel("UniverseMap")
    else
        self.Completed = true
    end
end

return M