local PlayerSystem = require "Module.Player.PlayerSystem"

---@type STT_Name_C
local M = UnLua.Class()

---@param DeltaTime number
function M:ReceiveLatentTick(DeltaTime)
    local player_system = PlayerSystem:GetInstance()
    if player_system.PlayerInfo.player_sequence_name and player_system.PlayerInfo.player_sequence_name ~= "" then
        self:FinishTask(true)
    end
end

function M:ReceiveLatentEnterState(Transition)
    self.NamingWidget = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_Name.UI_Name_C'))
    UIManager:GetInstance():AddUI(self.NamingWidget)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2")
end

function M:ReceiveLatentExitState(Transition)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:AddUMG("UI_Loading2")
end

function M:ReceiveStateCompleted(CompletionStatus, CompletedActiveStates)
    UIManager:GetInstance():RemoveUI(self.NamingWidget)
end

return M
