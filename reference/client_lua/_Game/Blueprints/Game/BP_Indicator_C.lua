local PlayerSystem = require('Module.Player.PlayerSystem')

---@type BP_Indicator_C
local M = UnLua.Class()

---@param Player AActor
---@param Target AActor
function M:SetUp(Player, Target)
    self.player = Player
    self.target = Target

    self:K2_AttachToActor(self.player, "", UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.KeepWorld, false)
end

function M:ReceiveTick()
    if not self.target or not self.target then return end

    local playerLocation = self.player:K2_GetActorLocation()
    local targetLocation = self.target:K2_GetActorLocation()

    local lookRotation = UE.UKismetMathLibrary.FindLookAtRotation(playerLocation, targetLocation)

    self:K2_SetActorRotation(lookRotation, true)

    local location = self.player:K2_GetActorLocation() + self:GetActorForwardVector() * self.IndicatorOffset

    self:K2_SetActorLocation(location, false, nil, true)

    local pickInfo = PlayerSystem:GetInstance():GetPickInfo(self.target.ConfigId)
    local isPicked = pickInfo and pickInfo.picking_seconds > 0

    self:SetActorHiddenInGame(isPicked)
end

return M
