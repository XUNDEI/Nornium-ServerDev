--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"

---@class BP_Projectile_C : BP_Projectile
local BP_Projectile_C = Class()

--function BP_Projectile_C:Initialize(Initializer)
--end

--function BP_Projectile_C:UserConstructionScript()
--end

-- function BP_Projectile_C:ReceiveBeginPlay()
--     -- self.Overridden.ReceiveBeginPlay(self)
--     LOG_DEBUG("BP_Projectile_C ..........................", self:GetName(), self:GetModuleName())
--     LOG_DEBUG(self.CharacterOwner.CustomTimeDilation)
--     self.CustomTimeDilation = self.CharacterOwner.CustomTimeDilation
--     coroutine.resume(coroutine.create(function(GameMode, Duration)
--         UE.UKismetSystemLibrary.Delay(GameMode, Duration)
--         self.Sphere:SetCollisionEnabled(UE.ECollisionEnabled.NoCollision)
--         UE.UPlayMontageCallbackProxy.CreateProxyObjectForPlayMontage(self.SkeletalMesh, self.Montage)
--         self:SetTimerDelegate({self, self.AutoDestroyWithLifeSpan}, self.LifeSpan)
--         ---@type BP_GameMode_Fight
--         local GameModeFight = UE.UGameplayStatics.GetGameMode(self)
--         GameModeFight.OnCharacterDead:Add(self, self.AutoDestroyWithOwnerDead)
--     end), self, 0.01)
-- end

--function BP_Projectile_C:ReceiveEndPlay()
--end

-- function BP_Projectile_C:ReceiveTick(DeltaSeconds)
--     self.Overridden.ReceiveTick(self, DeltaSeconds)
--     local CollisionDamages = self.CollisionDamages
--     local CollisionOverlaps = self.CollisionOverlaps
--     for i = 1, CollisionDamages:Length() do
--         ---@type ANS_CollisionDamage
--         local CollisionDamage = CollisionDamages:Get(i)
--         if CollisionDamage:IsValid() then
--             if CollisionDamage.CollisionTimeSpace > 0 then
--                 for j = 1, CollisionOverlaps:Length() do
--                     ---@type FS_Overlap
--                     local CollisionOverlap = CollisionOverlaps:Get(j)
--                     if CollisionOverlap.IsOverlaping then
--                         local time = UE.UGameplayStatics.GetTimeSeconds(self)
--                         if time - CollisionOverlap.LastTime >= CollisionDamage.CollisionTimeSpace then
--                             self:ProcessCollisionDamage(CollisionDamage, CollisionOverlap.OverlappedComponent,
--                                 CollisionOverlap.OtherActor)
--                             CollisionOverlap.LastTime = time
--                             CollisionDamages:Set(j, CollisionOverlap)
--                         end
--                     end
--                 end
--             end
--         end
--     end
-- end

--function BP_Projectile_C:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
--end

--function BP_Projectile_C:ReceiveActorBeginOverlap(OtherActor)
--end

--function BP_Projectile_C:ReceiveActorEndOverlap(OtherActor)
--end

function BP_Projectile_C:UpdateTrackTarget(DeltaSeconds)
    if not self.Tracking or not self.TargetMeshComponent then
        return
    end
    if self.TrackNearDelay > 0 then
        self.TrackNearDelay = self.TrackNearDelay - DeltaSeconds
    end
    local TimeSeconds = UE.UGameplayStatics.GetTimeSeconds(self)
    if self.TrackNearDelay <= 0 and not self.TrackNear then
        local Distance = UE.UKismetMathLibrary.Vector_Distance(self:K2_GetActorLocation(),
            self.TargetMeshComponent:GetSocketLocation(self.TargetSocketName))
        if Distance < self.TrackNearDistance then
            self.TrackNear = true
            self.TrackNearTime = TimeSeconds
        end
    end
    local TempTrackSpeed = self.TrackSpeed
    if self.TrackNear then
        TempTrackSpeed = TempTrackSpeed * self.TrackNearSpeedRate
        if TimeSeconds - self.TrackNearTime > self.TrackNearDuration then
            TempTrackSpeed = TempTrackSpeed * self.TrackNearNextSpeedRate
        end
    end
    local Velocity = self.ProjectileMovement.Velocity
    local RotatorBegin = UE.UKismetMathLibrary.Conv_VectorToRotator(Velocity)
    local RotatorEnd = UE.UKismetMathLibrary.FindLookAtRotation(self:K2_GetActorLocation(),
        self.TargetMeshComponent:GetSocketLocation(self.TargetSocketName))
    local Rot = UE.UGHSFunctionLibrary.RotateTo(RotatorBegin, RotatorEnd, TempTrackSpeed, DeltaSeconds)
    local Direction = Rot:GetForwardVector() * Velocity:Size()
    local NewVelocity = UE.UKismetMathLibrary.InverseTransformDirection(self:GetTransform(), Direction)
    self.ProjectileMovement:SetVelocityInLocalSpace(NewVelocity)
    if self.TrackNear then
        if TimeSeconds - self.TrackNearTime > self.TrackNearLifeSpan then
            self:K2_DestroyActor()
        end
    end
end

return BP_Projectile_C
