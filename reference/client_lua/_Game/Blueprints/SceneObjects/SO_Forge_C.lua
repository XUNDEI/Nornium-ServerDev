--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_LeaveStation_C
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
                UIManager:GetInstance():ClearInteractOption()
                UIManager:GetInstance():AddInteractOption(self, 246, function()
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
            LOG_INFO(player, OtherActor)
            if player == OtherActor then
                UIManager:GetInstance():RemoveInteractOptionByObject(self)
            end
        end
    end
end

function M:OnClickOptionItem()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    --self.Overridden.OnClickOptionItem(self, nil, 0)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local isOpen, config = gameInstance:OpenLinkEx(9006)
    if isOpen and config then
        if self.ShopGate then
            local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
            pc.BP_ScreenFade:FadeIn(false)

            self.ShopGate:OpenDoor(true)

            coroutine.resume(coroutine.create(function()
                UE.UKismetSystemLibrary.Delay(self, 0.5)
                self.ShopGate:OpenDoor(false)
                local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                if config.UI and config.UI ~= '' then
                    local ui = gameInstance:AddUMG(config.UI)
                    if ui and ui.InitUIEx then
                        ui:InitUIEx(config.args)
                    end
                end
                local ui = gameInstance:GetUMG('UI_StreamLoading')
                if ui then
                    ui:SetVisibility(UE.ESlateVisibility.Hidden)
                    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
                    pc:EnableInput()
                end
            end))
        end
    end
end

function M:LoadForgeUI()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OpenLink(9006)
end



return M