--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_NPCBase_C
local M = UnLua.Class()

function M:ReceiveBeginPlay()
    self.Box.OnComponentBeginOverlap:Add(self, self.OnBoxCollisionOverlapStart)
    self.Box.OnComponentEndOverlap:Add(self, self.OnBoxCollisionOverlapEnd)
end

function M:OnBoxCollisionOverlapStart(OverlappedComponent, OtherActor, OtherComp, OtherBodyIndex, bFromSweep, SweepResult)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        local player = playerController:K2_GetPawn()
        if player then
            if player == OtherActor then
                playerController.BP_PlayerController_City_UniverseBridge.SitTransform = self:CacheSitTrans(self.Box)
                UIManager:GetInstance():AddInteractOption(self, 218, function()
                    self:OnClickOptionItem()
                end)
            end
        end
    end
end

function M:OnBoxCollisionOverlapEnd(OverlappedComponent, OtherActor, OtherComp, OtherBodyIndex, bFromSweep, SweepResult)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        local player = playerController:K2_GetPawn()
        if player then
            if player == OtherActor then
                UIManager:GetInstance():RemoveInteractOptionByObject(self)
            end
        end
    end
end

function M:OnClickOptionItem()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        playerController.BP_PlayerController_City_UniverseBridge.Sitting = true
    end
end

function M:LoadForgeUI()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OpenLink(9005)
end

return M