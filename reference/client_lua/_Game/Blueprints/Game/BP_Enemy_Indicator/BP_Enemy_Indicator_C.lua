--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type BP_Enemy_Indicator_C
local M = UnLua.Class()

---@param Player BP_PlayerCharacter_Fight_C
---@param Enemy BP_EnemyCharacter_Fight_C
function M:SetUp(Player, Enemy)
    self.player = Player
    self.enemy = Enemy

    self:K2_AttachToActor(self.player, "", UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.KeepWorld, false)
end

function M:ReceiveBeginPlay()
    self.Normal:Activate(true)
    self.Warning:Deactivate()
    self.showWarning = nil
    self.visible = nil
    self.hidden = false
end

function M:SetHidden(hidden)
    self.hidden = hidden

    self:SetActorHiddenInGame(self.hidden or not self.visible)
end

function M:ReceiveTick()
    if not self.enemy or not self.enemy then return end
    local playerLocation = self.player:K2_GetActorLocation()
    local enemyLocation = self.enemy:K2_GetActorLocation()

    -- 检查敌人可见性
    local enemyViewportPosition = UE.FVector2D()
    UE.UGameplayStatics.GetPlayerController(self, 0):ProjectWorldLocationToScreen(enemyLocation, enemyViewportPosition)
    local viewportSize = UE.UWidgetLayoutLibrary.GetViewportSize(self)

    local indicatorVisible = not (0 < enemyViewportPosition.X and enemyViewportPosition.X < viewportSize.X and
                                  0 < enemyViewportPosition.Y and enemyViewportPosition.Y < viewportSize.Y)
    
    self:SetActorHiddenInGame(self.hidden or not self.visible)

    if self.visible ~= indicatorVisible then
        self.visible = indicatorVisible

        if self.visible then
            if self.showWarning then
                self.Warning:Activate(true)
            else
                self.Normal:Activate(true)
            end
        else
            self.Normal:Deactivate()
            self.Warning:Deactivate()
            return
        end
    end

    local lookRotation = UE.UKismetMathLibrary.FindLookAtRotation(playerLocation, enemyLocation)

    self:K2_SetActorRotation(lookRotation, true)

    local location = self.player:K2_GetActorLocation() + self:GetActorForwardVector() * self.IndicatorOffset

    self:K2_SetActorLocation(location, false, nil, true)

    if self.showWarning ~= self.enemy:IsAttacking() then
        self.showWarning = self.enemy:IsAttacking()
        if self.showWarning then
            self.Warning:Activate(true)
            self.Normal:Deactivate()
        else
            self.Normal:Activate(true)
            self.Warning:Deactivate()
        end
    end
end

return M
