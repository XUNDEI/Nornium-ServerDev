---@type SO_BuildLevel_Interaction_C
local M = UnLua.Class()

function M:ReceiveBeginPlay()
    self.bIsOpen = false
end

function M:ReceiveEndPlay()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
end

function M:ReceiveActorBeginOverlap(OtherActor)
    self.Overridden.ReceiveActorBeginOverlap(self, OtherActor)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and OtherActor and OtherActor == playerController:K2_GetPawn() then
        UIManager:GetInstance():ClearInteractOption()
        UIManager:GetInstance():AddInteractOption(self, self.bIsOpen and 470 or 469, function()
            self:OnOptionItemClicked()
        end)
    end
end

function M:ReceiveActorEndOverlap(OtherActor)
    self.Overridden.ReceiveActorEndOverlap(self, OtherActor)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and OtherActor and OtherActor == playerController:K2_GetPawn() then
        UIManager:GetInstance():RemoveInteractOptionByObject(self)
    end
end

function M:OnOptionItemClicked()
    self.bIsOpen = not self.bIsOpen
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    self.Overridden.OnOptionItemClicked(self)
end

return M