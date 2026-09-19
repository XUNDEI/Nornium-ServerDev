--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require '_Game.Utils.Database'

---@type STT_LoadSubLevel_C
local M = UnLua.Class()

function M:ShowLoading()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG("UI_Loading2")
    if not ui then
        gameInstance:AddUMG("UI_Loading2", nil, 1)
        self.LoadingUI = gameInstance:GetUMG("UI_Loading2")
    else
        ui:CancelDelayDestroy()
    end
end

return M
