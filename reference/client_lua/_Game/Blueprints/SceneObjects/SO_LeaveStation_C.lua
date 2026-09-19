--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_LeaveStation_C
local M = UnLua.Class()

function M:OnOverlap()
    local textId = self.bIsEnter and 224 or 223
    UIManager:GetInstance():ClearInteractOption()
    UIManager:GetInstance():AddInteractOption(self, textId, function()
        self:OnOptionItemClicked()
    end)
end

function M:EndOverlap()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
end

function M:OnOptionItemClicked()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if gameInstance:OpenLink(9024) then
        if self.bIsEnter then
            if pc and pc.LoadStationScene then
                pc:LoadStationScene(false)
            end
        else
            local ui = gameInstance:GetUMG('UI_TrainStation')
            if ui then
                ui:OnHide()
            end
        end
    end
end

return M