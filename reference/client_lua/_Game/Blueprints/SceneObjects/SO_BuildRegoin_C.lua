---@type SO_BuildRegoin_C
local M = UnLua.Class()
local BuildSystem = require('Module.BuildSystem.BuildSystem')

function M:OnBuildPlayStart()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local cityUI = gameInstance:GetUMG('UI_City')
    if cityUI then
        cityUI:EnterBuildRegion()
        cityUI.BuildRegion = self
    end
end

function M:OnBuildPlayEnd()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local cityUI = gameInstance:GetUMG('UI_City')
    if cityUI then
        cityUI:ExitBuildRegion()
    end
    local ui = gameInstance:GetUMG('UI_Build')
    if ui then
        ui:BuildPlayEnd(true)
    end
end

return M
