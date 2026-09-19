---@type UI_TrackPoint_C
local M = UnLua.Class()

function M:Tick(MyGeometry, InDeltaTime)
    self.Overridden.Tick(self, MyGeometry, InDeltaTime)

    self:UpdatePosition()
end

function M:UpdatePosition()
    ---@type BP_PlayerController_UniverseCutScene_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    local screenPos = UE.FVector2D(0, 0)
    local width, height = UE.UGameplayStatics.GetPlayerController(self, 0):GetViewportSize()
    local scale = UE.UWidgetLayoutLibrary.GetViewportScale(self)
    width = width / scale - 62
    height = height / scale - 91
    local center = UE.FVector2D(width, height) / 2
    self.StartPos = center
    --不能映射到屏幕上时
    if not playerController:ProjectWorldLocationToScreen(self.TrackPosition, screenPos, false) then
        local cameraManagerActor = UE.UGameplayStatics.GetPlayerCameraManager(self, 0)
        local camToTarget = cameraManagerActor:GetCameraLocation() - self.TrackPosition
        local locX = UE.UKismetMathLibrary.VSize(UE.UKismetMathLibrary.ProjectVectorOnToVector(camToTarget, cameraManagerActor:GetActorRightVector()))
        local locY = UE.UKismetMathLibrary.VSize(UE.UKismetMathLibrary.ProjectVectorOnToVector(camToTarget, cameraManagerActor:GetActorUpVector()))
        local Rotator = UE.UKismetMathLibrary.NormalizedDeltaRotator(cameraManagerActor:GetCameraRotation(), UE.UKismetMathLibrary.FindLookAtRotation(cameraManagerActor:GetCameraLocation(), self.TrackPosition))
        if Rotator.Pitch >= 0 and Rotator.Yaw <= 0 then
            locY = locY * -1
        elseif Rotator.Pitch >= 0 and Rotator.Yaw > 0 then
            locX = locX * -1
            locY = locY * -1
        elseif Rotator.Pitch < 0 and Rotator.Yaw <= 0 then

        elseif Rotator.Pitch < 0 and Rotator.Yaw > 0 then
            locX = locX * -1
        end
        
        screenPos = center + UE.UKismetMathLibrary.Normal2D(UE.FVector2D(locX, locY)) * 10000
        local px = center.X + center.Y * (screenPos.X - center.X) / math.abs(screenPos.Y - center.Y)
        local py = center.Y + center.X * (screenPos.Y - center.Y) / math.abs(screenPos.X - center.X)
        screenPos.X = px
        screenPos.Y = py
        if screenPos.X < 0 then screenPos.X = 0 end
        if screenPos.X > width then screenPos.X = width end
        if screenPos.Y < 0 then screenPos.Y = 0 end
        if screenPos.Y > height then screenPos.Y = height end
    else
        screenPos = screenPos / scale

        if screenPos.X < 0 then screenPos.X = 0 end
        if screenPos.X > width then screenPos.X = width end
        if screenPos.Y < 0 then screenPos.Y = 0 end
        if screenPos.Y > height then screenPos.Y = height end
    end
    self.Slot:SetPosition(screenPos)
end

return M
