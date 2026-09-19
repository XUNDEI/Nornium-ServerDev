
require "UnLua"
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@class BP_BuildActor_C : BP_BuildActor_C
local M = UnLua.Class()

local UIUtils = require('_Game.Utils.UIUtils')
local CharacterSystem = require('Module.CharacterSystem.CharacterSystem')
local BuildSystem = require('Module.BuildSystem.BuildSystem')

local EDialogType = {
    NonInterrupt = 1, --不可打断
    Interrupt = 2, --可打断->显示对话选项
}

---@param ActionValue FInputActionValue
---@param ElapsedSeconds number
---@param TriggeredSeconds number
---@param InputAction UInputAction
function M:IA_Move(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    -- self.IA_Move_Flag = math.abs(self.IA_Move_Flag - 1)
    -- if self.IA_Move_Flag == 0 then return end
    local input = ActionValue:GetAxis2D()
    self:Input_Move(input)
end

function M:IA_ChangeSkin(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    local value = ActionValue:GetBool()
    print('-------value:' .. tostring(value))
    if self.bIsDialogMode then return end
    print('------------IA_ChangeSkin')
    -- self.IA_ChangeSkin_Flag = math.abs(self.IA_ChangeSkin_Flag - 1)
    -- if self.IA_ChangeSkin_Flag == 0 then return end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Idol_Dress_Hotel')
    if ui then
        do return end
        -- local skinId = ui:GetSelectedSkinId()
        -- if skinId ~= self.SkinId then
        --     self:OnCloseDress()
        -- end
        -- gameInstance:RemoveUMG('UI_Idol_Dress_Hotel')
        -- gameInstance:ShowTopUI(true)
    else
        
        gameInstance:ShowTopUI(false)
        ui = gameInstance:AddUMG('UI_Idol_Dress_Hotel')
        ui:RefreshUI(self)
    end
end

function M:IA_Controlled(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    print('------------IA_Controlled')
    -- self.IA_Controlled_Flag = math.abs(self.IA_Controlled_Flag - 1)
    -- if self.IA_Controlled_Flag == 0 then return end
    if not self.bIsDialogMode and self.bIsControlled then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:GetUMG('UI_Idol_Dress_Hotel')
        if not ui then 
            self:OnClicked_UnControlled()
        end
    end
end

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Move, UE.ETriggerEvent.Triggered, M.IA_Move)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_ChangeSkin, UE.ETriggerEvent.Completed, M.IA_ChangeSkin)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Controlled, UE.ETriggerEvent.Completed, M.IA_Controlled)


function M:ReceiveBeginPlay()
    -- self:InitDialogConfig()
    self.IsPlayDialog = false --是否正在播放对话
    self.Widget_Dialog:SetVisibility(false)
    self.Widget_Dialog:SetHiddenInGame(true, false)
    if self.Widget_Dialog:GetUserWidgetObject() then
        self.Widget_Dialog:GetUserWidgetObject().Border:SetRenderOpacity(0)
    end
    MessageManager:GetInstance():AddListener('BuildActorPlayDialog', self)
    MessageManager:GetInstance():AddListener('BuildActorStopDialog', self)
    -- self.Overridden.ReceiveBeginPlay(self)

    --临时处理
    self.IA_Move_Flag = 0
    self.IA_ChangeSkin_Flag = 0
    self.IA_Controlled_Flag = 0

    self:PlayFacialAnimation(0)
end

function M:ReceiveEndPlay()
    MessageManager:GetInstance():RemoveListener('BuildActorPlayDialog', self)
    MessageManager:GetInstance():RemoveListener('BuildActorStopDialog', self)
end

function M:OnEndTouchChar()
    print('------------OnEndTouchChar:' .. tostring(self.ID))
    MessageManager:GetInstance():Broadcast('OnMsg_InteractionBuildActor', self.ID)
    if self.bIsDialogMode then
        self:OnClicked_UnControlled(nil, 0)
    end
end

function M:OnCoinTouchChar()
    if not self.bIsDialogMode then
        BuildSystem:GetInstance():ReqBuildInteract(self.ID)
    end
end

--隐藏角色
function M:ShowCharacter(bShow)
    if bShow then
        self:OnLuaShowActor()
    else
        self:OnLuaHideActor()
    end
    -- self.SkeletalMesh1:SetHiddenInGame(not bShow)
    -- self.Face:SetHiddenInGame(not bShow)
end

function M:ReceiveActorBeginOverlap(OtherActor)
    self.Overridden.ReceiveActorBeginOverlap(self, OtherActor)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    local controlledPawn = playerController:K2_GetPawn()
    if playerController and OtherActor and controlledPawn and OtherActor == playerController:K2_GetPawn() then
        if not self.bIsControlled then
            if self.bIsDialogMode then
                self:OnClicked_Controlled(nil, 0)
            else
                UIManager:GetInstance():ClearInteractOption()
                local ui = UIManager:GetInstance():AddInteractOption(self, 369, function()
                    self:OnClicked_Controlled()
                end)
                self.OptionItem_Controlled = ui
            end
        end
    end
end

function M:ReceiveActorEndOverlap(OtherActor)
    self.Overridden.ReceiveActorEndOverlap(self, OtherActor)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and OtherActor and OtherActor == playerController:K2_GetPawn() then
        if self.bIsDialogMode then
            self:OnClicked_UnControlled(nil, 0)
        else
            if self.OptionItem_Controlled then
                UIManager:GetInstance():RemoveInteractOption(self.OptionItem_Controlled)
                self.OptionItem_Controlled = nil
            end
            if self.OptionItem_UnControlled then
                UIManager:GetInstance():RemoveInteractOption(self.OptionItem_UnControlled)
                self.OptionItem_UnControlled = nil
            end
        end
    end
end

--点击控制
function M:OnClicked_Controlled(item, index)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and playerController.BP_PlayerController_City_UniverseBridge then
        playerController.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    end

    if self:ActorHasTag('100010101') then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:ShowTopUI(true)
        gameInstance:ShowFightNotify(50603, 10)
    end

    self.bIsControlled = true
    playerController.BuildActorIsControlled = true

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = playerController:K2_GetPawn()
    if player then
        gameMode:BPI_SetPlayer(player)
    end

    --判定当前角色是否解锁
    if not self.bIsDialogMode and self.ID and self.ID > 0 then
        -- local itemConfig = UIUtils.GetItemConfigById(self.ID)
        -- if itemConfig and itemConfig.subParam and itemConfig.subParam[1] and itemConfig.subParam[1] > 0 then
        --     local charId = itemConfig.subParam[1]
        --     local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId)
        --     if not charInfo then
        --         local tip = ''
        --         local charConfig = require('ClientDatas.d_character')[charId]
        --         if charConfig and charConfig.name then
        --             tip = Database.L10n(charConfig.name)
        --         end
        --         UIUtils.ShowNotify(self, Database.L10n(451) .. tip)
        --         return
        --     end
        -- end

        local nearDistance = -1 --临时最短距离(玩家位置)
        local nearIndex = -1 --最近摄像机的索引
        --获取场景中所有的摄像机位置
        local regionCameras = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "BuildRegion")
        if regionCameras:Length() > 0 then
            for i = 1, regionCameras:Length() do
                local camera = regionCameras:Get(i)
                local posTag = camera.Tags:Get(2)
                local index = tonumber(string.sub(posTag, 7, -1))
                local distance = UE.UKismetMathLibrary.Vector_Distance(camera:K2_GetActorLocation(), player:K2_GetActorLocation())
                if nearDistance < 0 then
                    nearDistance = distance
                    nearIndex = index
                else
                    if distance < nearDistance then
                        nearDistance = distance
                        nearIndex = index
                    end
                end
            end
        end
        --建筑摆放点信息
        local buildPosActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "BuildPos")
        for i = 1, buildPosActors:Length() do 
            local buildPos = buildPosActors:Get(i)
            if buildPos.BuildRegionIndex == nearIndex then
                local buildActor = playerController.AllBuildActors[buildPos.BuildPosIndex]
                if buildActor and buildActor ~= self and buildActor.ShowCharacter then
                    buildActor:ShowCharacter(false)
                end
            end
        end
    end

    self.Overridden.OnClicked_Controlled(self, item, index)
    --播放渐入动画
    local CharMeshHidden = self.SkeletalMesh1.bHiddenInGame
    if CharMeshHidden then
        playerController.BP_ScreenFade:FadeIn(false)
    end
    --移除控制选项
    if self.OptionItem_Controlled then
        UIManager:GetInstance():RemoveInteractOption(self.OptionItem_Controlled)
        self.OptionItem_Controlled = nil
    end

    --隐藏角色/关闭碰撞
    -- print("----------player.bHidden:" .. tostring(player.bHidden))
    if player then
        self.PlayerInCityPos = player:K2_GetActorLocation()
        -- player:SetActorEnableCollision(false)
        -- player:K2_SetActorLocation(UE.FVector(0, 0, -5000), false, nil, false)
        player:SetActorHiddenInGame(true)
        player:SetActorScale3D(UE.FVector(0.01, 0.01, 0.01))
        player.Mesh:SetEnableGravity(false)
        player.CharacterMovement:SetActive(false, false)
        player.RootComponent:SetCollisionResponseToChannel(UE.ECollisionChannel.ECC_Camera, UE.ECollisionResponse.ECR_Ignore)
    end

    self:ShowCharacter(true)

    self:OnControlled()
    playerController.LastControlledBuildActor = self

    --播放淡出动画
    if CharMeshHidden then
        playerController.BP_ScreenFade:FadeOut(false, true)
    end

    --添加解控选项
    if not self.bIsDialogMode then
        -- local ui = UIManager:GetInstance():AddInteractOption(self, 368, function()
        --     self:OnClicked_Controlled()
        -- end)
        -- ui:SetVisibility(UE.ESlateVisibility.Hidden)
        -- self.OptionItem_UnControlled = ui
    end

    --刷新主ui显示
    self:Refresh_UI_City(false)

    --测试播放对话
    -- self:PlayDialog(700001)

    --查找组件中最大的包围盒
    self.MaxBoundActor = self:FindMaxBoundActor()

    self.InitArmLength = self.SpringArm.TargetArmLength
    self.SpringArm.TargetOffset = UE.FVector(0, 0, 30)
    InputUtils.RemoveMappingContext(playerController, InputAssets.IMC_UI_SystemEntry)
    InputUtils.AddMappingContext(playerController, InputAssets.IMC_BuildActor)
end

--点击解绑
function M:OnClicked_UnControlled()
    self.Overridden.OnClicked_UnControlled(self)
    if self:ActorHasTag('100010101') then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:HideFightNotify()
    end

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    self.bIsControlled = false
    playerController.BuildActorIsControlled = false

    --移除控制选项
    if self.OptionItem_UnControlled then
        UIManager:GetInstance():RemoveInteractOption(self.OptionItem_UnControlled)
        self.OptionItem_UnControlled = nil
    end

    --刷新主ui显示
    self:Refresh_UI_City(true)
  
    --隐藏角色/关闭碰撞
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        player:SetActorScale3D(UE.FVector(1, 1, 1))
        player:K2_SetActorLocation(self.PlayerInCityPos, false, nil, false)
        
        -- player:SetActorHiddenInGame(false)
        -- player.Mesh:SetEnableGravity(true)
        -- player.CharacterMovement:SetActive(true, false)
    end


    self:OnUnControlled()

    if player then
        -- player:SetActorScale3D(UE.FVector(1, 1, 1))
        -- player:K2_SetActorLocation(self.PlayerInCityPos, false, nil, false)
        player:SetActorHiddenInGame(false)
        player.Mesh:SetEnableGravity(true)
        player.CharacterMovement:SetActive(true, false)
        player.RootComponent:SetCollisionResponseToChannel(UE.ECollisionChannel.ECC_Camera, UE.ECollisionResponse.ECR_Overlap)
    end

    --测试播放对话
    -- self:PlayDialog(700003)

    playerController.bShowMouseCursor = false
    InputUtils.RemoveMappingContext(playerController, InputAssets.IMC_BuildActor)
    InputUtils.AddMappingContext(playerController, InputAssets.IMC_UI_SystemEntry)
end

--开始播放
function M:BuildActorPlayDialog(dialogId, npcId)
    if npcId == self.NpcId then
        self:PlayDialog(dialogId)
    end
end

--停止播放
function M:BuildActorStopDialog(npcId)
    if npcId == self.NpcId then
        self:StopDialog()
    end
end

----------------------------------------------------------------------
---
function M:PlayDialog(dialogId)
    if self.CurDialogId == dialogId then
        return
    else
        if self.CurDialogId > 0 then
            self:StopDialog()
        end
    end
    local config = Database.Query('d_story_bubble', dialogId)
    if not config then
        return
    end

    self.CurDialogId = dialogId
    -- print("==PlayDialog mainId:" .. tostring(self.MainNpcId) .. ",npcId:" .. tostring(self.NpcId))
    -- print("===list:" .. tostring(table.dump(self.DialogConfigList, nil, 10)))
    self.IsPlayDialog = true
    self.Widget_Dialog:SetVisibility(true)
    self.Widget_Dialog:SetHiddenInGame(false, false)
    local ui = self.Widget_Dialog:GetUserWidgetObject() 
    if ui and self.CurDialogId > 0 then
        ui.EventOnPlayEnd:Clear()
        ui.EventOnPlayEnd:Add(self, self.EventOnPlayEnd)
        ui:InitUI(self.CurDialogId)
    end
end

function M:StopDialog()
    self.CurDialogId = 0
    self.IsPlayDialog = false
    self.Widget_Dialog:SetVisibility(false)
    self.Widget_Dialog:SetHiddenInGame(true, false)
    local ui = self.Widget_Dialog:GetUserWidgetObject() 
    if ui then
        ui.EventOnPlayEnd:Remove(self, self.EventOnPlayEnd)
        ui:StopUI()
    end
end

function M:PlayNextDialog(curDialogId)
    -- print("====PlayNextDialog:" .. tostring(curDialogId))
    local config = Database.Query('d_story_bubble', curDialogId)
    if config then 
        local nextId = tonumber(config.next)
        if nextId > 0 then
            local nextConfig = Database.Query('d_story_bubble', nextId)
            if nextConfig then
                local nextNpcId = tonumber(nextConfig.npcID)
                if nextId > 0 and nextNpcId > 0 then
                    MessageManager:GetInstance():Broadcast('BuildActorPlayDialog', nextId, 0)
                elseif nextId == 0 then
                    self:StopDialog()
                else
                    print("====playNextDialog nextId:" .. tostring(nextId))
                end
            end
        end
    else
        print("====playNextDialog error:" .. tostring(curDialogId))
    end
end

----------------------------------------------------------------------
---ui Event
function M:EventOnPlayEnd()
    if self.Widget_Dialog:GetUserWidgetObject() then
        self.Widget_Dialog:GetUserWidgetObject().EventOnPlayEnd:Remove(self, self.EventOnPlayEnd)
        self.Widget_Dialog:SetVisibility(false)
        self.Widget_Dialog:SetHiddenInGame(true, false)
    end
    self:PlayNextDialog(self.CurDialogId)
end

--添加 移除一个指定的input
function M:ModifyInput_UI_Options(show)
    local layers = UIManager:GetInstance().layers
    if layers then
        UIManager:GetInstance().layers:SetRequireShowInteractOptions(show)
    end
end

----------------------------------------------------------------------
---换皮
function M:GetDressMesh(charId)
    local d_char_clothes = require('ClientDatas.d_char_clothes')
    local _, _, savedCityCharId, _, _, defaultCityCharId = UIUtils.GetIdolAndCharMeshByCharacterId(charId)
    print("-->>changeDress:" .. tostring(savedCityCharId) .. ",defualtCharid:" .. tostring(defaultCityCharId))
    if savedCityCharId > 0 then
        savedCityCharId = savedCityCharId + 1000000
        local config = Database.Query("d_char_clothes", savedCityCharId)
        print("-->>2222changeDress:" .. tostring(savedCityCharId) .. ",config.modelF:" .. tostring(config.modelF))
        if config and config.modelF ~= '' then
            local newMesh = LoadObject(config.modelF)
            if newMesh then
                return newMesh
            end
        end
    end
    return nil
end

function M:InitDress(bForce)
    print('--------初始化换装')
    if self.ID and self.ID > 0 then
        local buildConfig = Database.Query('d_bag_item_furniture', self.ID)
        local defaultSkinId = buildConfig.trialClothes
        print('---defaultSkinId:' .. tostring(defaultSkinId) .. ',curSkinId:' .. tostring(self.SkinId))
        --获取缓存的家具信息
        if self.SkinId and self.SkinId > 0 then
            if bForce or (defaultSkinId ~= self.SkinId) then
                local d_char_clothes = require("ClientDatas.d_char_clothes")
                local config = d_char_clothes[self.SkinId]
                if config then
                    self:ChangeActorMesh(config)
                end
            end
        end
    end
end

--换装 
function M:ChangeActorMesh(config)
    if not config then return end
    print("------->modelF:" .. tostring( config.modelF))
    print("------->modelHair:" .. tostring( config.modelHair))
    print("------->modelFace:" .. tostring( config.modelFace))
 
 
    --身体
    if config.modelF and config.modelF ~= '' then
        --1004特殊处理
        local newMesh = LoadObject(config.modelF)
        if newMesh then
            if self.ID == 7060101 then
                self.SkeletalMesh_0:SetSkinnedAssetAndUpdate(newMesh)
            else
                self.SkeletalMesh1:SetSkinnedAssetAndUpdate(newMesh)
            end
            local mats = newMesh:GetMaterials()
            for i = 1, mats:Length() do
                local mi = mats:Get(i).MaterialInterface
                if self.ID == 7060101 then
                    self.SkeletalMesh_0:CreateDynamicMaterialInstance(i - 1, mi)
                else
                    self.SkeletalMesh1:CreateDynamicMaterialInstance(i - 1, mi)
                end
            end
        end
    end
    --头发
    if config.modelHair and config.modelHair ~= '' then
        local newMesh = LoadObject(config.modelHair)
        if newMesh then
            self.Hair:SetSkinnedAssetAndUpdate(newMesh)
        end
    end
    --脸
    if config.modelFace and config.modelFace ~= '' then
        local newMesh = LoadObject(config.modelFace)
        if newMesh then
            self.Face:SetSkinnedAssetAndUpdate(newMesh)
        end
    end
    if self.OnDressChanged then
        print('------------------->ChangeActorMesh')
        self:OnDressChanged()
    end

    self:ResetAnimation()
end

function M:OnCloseDress()
    self:InitDress(true)
end

return M