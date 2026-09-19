--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local SrpgController = require("Module.Srpg.SrpgController")

---@type SO_BridgeNpc_C
local M = UnLua.Class()

function M:PlayDialog()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OpenStory(20101013)
end

function M:ShowShop()
    local shopUI = UE4.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Shop/UI_SRPG_GrowthShop.UI_SRPG_GrowthShop_C'))

    UIManager:GetInstance():AddUI(shopUI)

    shopUI:Init()
end

function M:IsSpecificSRPG()
    return SrpgController:GetInstance():IsSpecificMap()
end

return M
