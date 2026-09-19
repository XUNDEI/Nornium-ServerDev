---@type SO_EnterBuildLevel_C
local M = UnLua.Class()

function M:ReceiveBeginPlay()
    self.OptionItemList = {}
end

function M:ReceiveEndPlay()
    self:ClearAllOption()
end

function M:ClearAllOption()
    if self.OptionItemList then
        UIManager:GetInstance():RemoveInteractOptionByObject(self)
        self.OptionItemList = {}
    end
end

function M:ReceiveActorBeginOverlap(OtherActor)
    self.Overridden.ReceiveActorBeginOverlap(self, OtherActor)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and OtherActor and OtherActor == playerController:K2_GetPawn() then
        UIManager:GetInstance():ClearInteractOption()
        local ui = UIManager:GetInstance():AddInteractOption(self, self.IsEnter and 515 or 516, function()
            self:OnOptionItemClicked()
        end)
        table.insert(self.OptionItemList, ui)
    end
end

function M:ReceiveActorEndOverlap(OtherActor)
    self.Overridden.ReceiveActorEndOverlap(self, OtherActor)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and OtherActor and OtherActor == playerController:K2_GetPawn() then
        self:ClearAllOption()
    end
end

function M:OnOptionItemClicked(option)
    self:ClearAllOption()

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then 
        if self.IsEnter then  
            if gameInstance:OpenLink(9025, '') then
                if playerController.EnterBuildLevel then
                    playerController:EnterBuildLevel('City1Hotel', self.PlayerStartName)
                end
            end
        else
            if gameInstance:OpenLink(9025, '') then
                if playerController.LeaveBuildLevel then
                    playerController:LeaveBuildLevel(self.PlayerStartName)
                end
            end
        end
    end
end

return M