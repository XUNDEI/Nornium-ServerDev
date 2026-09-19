---@type BPC_BuildingComponent_C
local M = UnLua.Class()

function M:BuildTick()
    if self.IsBuildModeOn then
        self:TraceBuildLocation()
    else
        self:StopBuildMode()
    end
end

function M:StartBuildMode(buildRegion)
    self.IsBuildModeOn = true
    self.BuildRegion = buildRegion
    print("---->buildPlayStart")
    UE.UKismetSystemLibrary.K2_UnPauseTimerHandle(self, self.BuildModeTimerHandle)
end

function M:StopBuildMode()
    self.IsBuildModeOn = false
    self.CanBuild = false
    print("---->buildPlayEnd")
    if self.BuildGhost then
        self.BuildGhost:K2_DestroyComponent(self:GetOwner())
        self.BuildGhost = nil
    end
    UE.UKismetSystemLibrary.K2_PauseTimerHandle(self, self.BuildModeTimerHandle)
end

--在当前位置生成模型
function M:SpawnBuildable()
    if self.CanBuild then
        local trans = self.BuildGhost:K2_GetComponentToWorld()
        local actorPath = self.BuildPath
        if actorPath ~= '' then
            local buildActor = self:GetWorld():SpawnActor(UE.LoadClass(actorPath),
                trans,
                UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
                self, self)
            buildActor:SetID(self.BuildID)
            -- --判断是否吸附到hitActor上
            -- if self.CategorieIndex == 3 and self.HitActor and self.HitActor.GetID then
            --     local id = self.HitActor:GetID()
            --     local type = self:GetTypeByBuildId(id)
            --     if type == 2 then
            --         buildActor:K2_AttachToActor(self.HitActor, "",
            --             UE.EAttachmentRule.KeepWorld,
            --             UE.EAttachmentRule.KeepWorld,
            --             UE.EAttachmentRule.KeepWorld,
            --             false)
            --     end
            -- end
            self:StopBuildMode()
        end
    end
end

--生成预览模型
function M:SpawnGhostMesh()
    self.BuildGhost = self:GetOwner():AddComponentByClass(UE.UStaticMeshComponent, false, self.InitGhostTransform, false)
    self.BuildGhost:SetCollisionEnabled(UE.ECollisionEnabled.NoCollision)
    self.BuildGhost:SetCollisionResponseToChannel(UE.ECollisionChannel.ECC_Visibility, UE.ECollisionResponse.ECR_Ignore)
end

--切换预览模型
function M:ChangeGhostMesh(buildId)
    -- if self.BuildID == buildId then
    --     return 
    -- end
    local config = require('ClientDatas.d_bag_item_furniture')[buildId]
    if not config then
        LOG_ERROR('---->d_bag_item_furniture未找到id:' .. tostring(buildId))
        self:StopBuildMode()
        return
    end
    self.BuildID = buildId --建筑id
    self.IsFreeHeight = config.freeHeight == 1 --是否自由高度
    self.GridModificator = config.GridModificator
    self.CategorieIndex = config.type

    local path = config.actorPath
    if not string.endswith(path, "_C'") then
        path = string.sub(path, 1, -2) .. "_C'"
    end
    self.BuildPath = path

    if not self.BuildGhost then
        self:SpawnGhostMesh()
    end

    do return end

    if self.TempGhostActor then
        self.TempGhostActor:K2_DetachFromActor()
        self.TempGhostActor:K2_DestroyActor()
        self.TempGhostActor = nil
    end
    
    --切换模型Mesh
    self.BuildGhost:SetStaticMesh(LoadObject(config.smPath))
    if path ~= '' then
        local actorPath = self.BuildPath
        local trans = self.BuildGhost:K2_GetComponentToWorld()
        self.TempGhostActor = self:GetWorld():SpawnActor(UE.LoadClass(actorPath),
            trans,
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
            self, self)

        self.TempGhostActor:K2_AttachToComponent(self.BuildGhost, "",
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            UE.EAttachmentRule.KeepWorld,
            false)
    end
   

    --记录范围
    local boundsMax = UE.FVector(0, 0, 0)
    self.BuildGhost:GetLocalBounds(nil, boundsMax)
    local boxExtend = UE.FVector(0, 0, 0)
    UE.UKismetSystemLibrary.GetComponentBounds(self.BuildGhost, nil, boxExtend, nil)
    self.GhostSize = UE.FVector(boundsMax.X, boundsMax.Y, boxExtend.Z)

    self.InitGhostLocation = self.BuildGhost:K2_GetComponentLocation()
end

function M:GetTypeByBuildId(buildId)
    if not buildId or buildId <= 0 then
        return -1
    end
    local config = require('ClientDatas.d_bag_item_furniture')[buildId]
    if not config then
        LOG_ERROR('---->d_bag_item_furniture未找到id:' .. tostring(buildId))
        return -1
    end 
    --print('---buildid:' .. tostring(buildId) .. ',type:' .. tostring(config.type))
    return config.type
end

return M
