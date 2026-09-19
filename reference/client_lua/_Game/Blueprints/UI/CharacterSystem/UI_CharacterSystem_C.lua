require "UnLua"
require "Common.TableUtil"
local utf8 = require "Common.Tools.utf8"
local UIUtils = require "_Game.Utils.UIUtils"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local CharacterConfig = require "ClientDatas.d_character"
local MessageManager = require "Framework.Updater.MessageManager"
local Database = require "_Game.Utils.Database"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_CharaterSystem_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

--构造函数
function M:Construct()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Level_Up_Success", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Level_Break_Success", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Swap_Weapon", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Strengthen_Weapon_Success", self)
    NetworkMessageManager:GetInstance():AddListener("ntf_character_info", self)

    MessageManager:GetInstance():AddListener("showchar", self)
end

function M:Destruct()
    if self.TabTimeHander then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.TabTimeHander)
        self.TabTimeHander = nil
    end

    local weaponActors = UE.TArray(UE.AActor)
    if self.ModelActors then
        for _, actor in pairs(self.ModelActors) do
            --获取附加的actor
            actor:GetAttachedActors(weaponActors, true, false)
            for i = 1, weaponActors:Length() do 
                local attachActor = weaponActors:Get(i)
                attachActor:K2_DestroyActor()
            end
            actor:K2_DestroyActor()
        end
    end

    self.SplineComponent = nil
    if self.SplineActor then
        self.SplineActor:K2_DestroyActor()
    end
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Level_Up_Success", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Level_Break_Success", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Swap_Weapon", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Strengthen_Weapon_Success", self)
    NetworkMessageManager:GetInstance():RemoveListener("ntf_character_info", self)

    MessageManager:GetInstance():RemoveListener("showchar", self)
end

function M:showchar()
    local newActor = self.ModelActors[self.SelectedCharacterData.character_id]
    if newActor then
        local pos = newActor:K2_GetActorLocation()
        print("===pos:" .. tostring(pos))
        local visible = newActor:K2_GetRootComponent():IsVisible()
        print("===IsVisible:" .. tostring(visible))
        if self.MoveCameraObj then
            local campos = self.MoveCameraObj:K2_GetActorLocation()
            print("===campos:" .. tostring(campos))
        end
    end
end

function M:ntf_character_info()
    self:InitData(self.SelectedCharacterData and self.SelectedCharacterData.character_id or 0)
end

function M:OnMsg_Req_Character_Level_Up_Success()
    self:InitData(self.SelectedRoleId)
    --角色详情
    self.UI_Panel_Detail:RefreshUI(self.SelectedCharacterData)
end

function M:OnMsg_Req_Character_Level_Break_Success()
    self:InitData(self.SelectedRoleId)
    --角色详情
    self.UI_Panel_Detail:RefreshUI(self.SelectedCharacterData)
end

function M:OnMsg_Req_Character_Swap_Weapon()
    self:RefreshRoleWeapon(self.SelectedCharacterData.weapon_info.item_id)
    self:RefreshWeaponPanel()
end

function M:OnMsg_Req_Strengthen_Weapon_Success()
    self:RefreshWeaponPanel()
end

function M:OnShowUI(RoleId, initTab)
    self.SelectedRoleId = 0
    --默认选中角色tab
    self.SelectedTabIndex = initTab or 0
    self.UI_Tab.detailTab:SetIsCheckedAndFireEvent(true)

    self.ModelActors = {}
    self.AttachActors = {}
    if not RoleId or RoleId == 0 then
        RoleId = UE.UGameplayStatics.GetGameInstance(self):GetPlayerCharacterIdInCity()
    end
    self:InitData(RoleId)

    --选定角色
    self:RefreshSelectedRole()
    self:RefreshTab()
    self:ChangeActorAndCamera(0, 0, true)
end

function M:GetSelectedCharacterData()
    return self.SelectedCharacterData
end

function M:InitData(roleId) 
    self.CharacterConfigList = CharacterSystem:GetInstance().CharacterInfo
    for _, charData in pairs(self.CharacterConfigList) do
        charData.config = CharacterConfig[charData.character_id]
    end
    if #self.CharacterConfigList > 1 then
        table.sort(self.CharacterConfigList, function(a, b)
            return a.character_id < b.character_id
        end)
    end

    self.SelectedCharacterIndex = 1

    if roleId > 0 then
        for idx, config in pairs(self.CharacterConfigList) do
            if config.character_id == roleId then
                self.SelectedCharacterIndex = idx
            end
        end
    end

    self.SelectedCharacterData = self.CharacterConfigList[self.SelectedCharacterIndex]
    if not self.SelectedCharacterData then
        print("========获取不到数据:" .. tostring(self.SelectedCharacterIndex))
        --print("===>CharacterConfigList:" .. tostring(table.dump(self.CharacterConfigList or {}, false, 10)))
    end
    self.SelectedRoleId = self.SelectedCharacterData.character_id

    self.PlayerCharacterIdInCity = 0
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance and gameInstance.GetPlayerCharacterIdInCity then
        self.PlayerCharacterIdInCity = gameInstance:GetPlayerCharacterIdInCity()
    end

    self.startChangeAlpha = false
    self.delayTime = 0
    self.Alpha = 0
end

function M:InitUI()
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
    --装扮按钮
    self.DressBtn.OnGHSClicked:Add(self, self.OnClicked_DressBtn)
    --主城切换角色
    self.DressBtn_control.OnGHSClicked:Add(self, self.OnClicked_PlayerControl)
    self.ExplainBtn2.OnGHSClicked:Add(self, self.OnClicked_ExplainBtn2)

    self.UI_Tab.detailTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_DetailTab)
    self.UI_Tab.WeaponTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_WeaponTab)
    self.UI_Tab.EquipTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_EquipTab)
    self.UI_Tab.SkillTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_SkillTab)
    self.UI_Tab.TalentTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_TablentTab)

    --Detail面板按钮
    --元素相性
    self.UI_Panel_Detail.Btn_Element.OnGHSClicked:Add(self, self.OnClicked_BtnElement)
    --角色详情升级
    self.UI_Panel_Detail.UI_Sub_LevelEntrance.LevelUp.OnGHSClicked:Add(self, self.OnClicked_DetailLevelUp)
    --角色详情特性
    self.UI_Panel_Detail.UI_Sub_Feature.FightProperty.OnGHSClicked:Add(self, self.OnClicked_FightProperty)

    --Weapon面板按钮
    self.UI_Panel_Weapon.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Replace.OnGHSClicked:Add(self,
        self.OnClicked_WeaponReplace)
    self.UI_Panel_Weapon.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Level.OnGHSClicked:Add(self,
        self.OnClicked_WeaponLevelUp)
    self.UI_Panel_Weapon.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Level_short.OnGHSClicked:Add(self,
        self.OnClicked_WeaponLevelUp)
    self.UI_Panel_Weapon.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Refine.OnGHSClicked:Add(self,
        self.OnClicked_WeaponRefine)
    self.UI_Panel_Weapon.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Refine_short.OnGHSClicked:Add(self,
        self.OnClicked_WeaponRefine)

    self.ChangeRoleList:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.ChangeRole.OnGHSClicked:Add(self, self.OnClicked_ChangeRole)

    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "MainCharacterCamera")
    if cineCameraActors:Length() > 0 then
        self.MoveCameraObj = cineCameraActors:Get(1)
    else
        cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.ACineCameraActor)
        if cineCameraActors:Length() > 0 then
            self.MoveCameraObj = cineCameraActors:Get(1)
        end
    end
    if self.MoveCameraObj then
        self.MoveCameraObj:K2_SetActorLocationAndRotation(UE.FVector(-615.0, 40.0, 32.0), UE.FRotator(0, 0, 0), false, nil, true)
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController:SetViewTargetWithBlend(self.MoveCameraObj, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
    end

    --技能面板空白
    self.Image_Skill_White.OnMouseButtonDownEvent:Bind(self, self.OnClicked_Btn_Imame_Skill_White)


    self.LastCameraIndex = 0
    self.SplineTangentList = self.TangentList:ToTable()
    self.SplineSpeedList = self.SpeedList:ToTable()

    self:PlayAnimationForward(self.In, 1, false)
    self.UI_Tab:PlayAnimationForward(self.UI_Tab.In, 1, false)
end

-- function M:TouchMoved(TouchBegin, TouchCurrent, TouchDelta)
--     local actor = self.ModelActors[self.SelectedCharacterData.character_id]
--     if actor then
--         local rot = actor:K2_GetActorRotation() + UE.FRotator(0, -TouchDelta.X, 0)
--         actor:K2_SetActorRotation(rot, false, nil, false)
--     end
-- end

function M:OnBack()
    self.WidgetSwitcher:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.ChangeRoleList:SetVisibility(UE.ESlateVisibility.Collapsed)
    self:MoveCameraPlane(true)
end

--切换角色
function M:SelectedRole(Index, CameraIndex)
    self:HideActor()
    self.WidgetSwitcher:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.SelectedCharacterIndex = Index
    self.SelectedCharacterData = self.CharacterConfigList[self.SelectedCharacterIndex]
    if self.SelectedCharacterData and not self.SelectedCharacterData.config then
        self.SelectedCharacterData.config = CharacterConfig[self.SelectedCharacterData.character_id]
    end
    self.SelectedRoleId = self.SelectedCharacterData.character_id
    self:RefreshSelectedRole(CameraIndex)
    CameraIndex = CameraIndex and CameraIndex or self.SelectedTabIndex
    --self:ChangeActorAndCamera(CameraIndex, CameraIndex)
    self:MoveCameraPlane(true)
    print("====SelectedRole.tab:" .. tostring(self.SelectedTabIndex))
    self:RefreshTab()

    self.ChangeRoleList:SetVisibility(UE.ESlateVisibility.Collapsed)

    --主控按钮判断
    self.control2:SetVisibility(self.PlayerCharacterIdInCity ~= self.SelectedCharacterData.character_id and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInvisible)
end

function M:HideActor(ignoreTab)
    local oldActor = self.ModelActors[self.SelectedCharacterData.character_id]
    if oldActor then
        if oldActor and oldActor.Mesh then
            if not ignoreTab then
                local animInstance = oldActor.Mesh:GetAnimInstance()
                if animInstance and animInstance.ChangeTab then
                    local curIndex = self.SelectedTabIndex
                    local toIndex = 0
                    if curIndex == 0 then
                        toIndex = 1
                    elseif curIndex == 1 or curIndex == 2 then
                        toIndex = 0
                    end
                    animInstance:ChangeTab(curIndex, toIndex)
                end
            end
           
            oldActor:SetActive(false)
        end

        
    end
end

function M:ShowActor(ignoreTab)
    local newActor = self.ModelActors[self.SelectedCharacterData.character_id]
    if newActor and newActor.Mesh then
        newActor:SetActive(true)
        local animInstance = newActor.Mesh:GetAnimInstance()
        if animInstance and animInstance.OnActorShow then
            animInstance:OnActorShow(self.SelectedTabIndex)
        end
       
        if not ignoreTab then
            local niagaraComponents = newActor:K2_GetComponentsByClass(UE.UNiagaraComponent)
            for _, niagaraComponent in pairs(niagaraComponents) do
                niagaraComponent:SetVisibility(false)
            end
            
            local animInstance = newActor.Mesh:GetAnimInstance()
            if animInstance and animInstance.ChangeTab then
                local curIndex = self.SelectedTabIndex
                local toIndex = 0
                if curIndex == 0 then
                    toIndex = 1
                elseif curIndex == 1 or curIndex == 2 then
                    toIndex = 0
                end
                animInstance:ChangeTab(toIndex, curIndex)
            end
        end
    end
end

function M:GetSelectedActor()
    return self.ModelActors[self.SelectedCharacterData.character_id] or nil
end

function M:RefreshSelectedRole(cameraIndex)
    local actorMode = self.ModelActors[self.SelectedCharacterData.character_id] or nil
    if actorMode then
        local pos, rot = self:GetActorPosConfig(cameraIndex or self.SelectedTabIndex)
        actorMode:K2_SetActorLocationAndRotation(pos, rot, false, nil, true)
        self:ShowActor()
    elseif not actorMode and 
        self.SelectedCharacterData.config.fightModelPath and 
        self.SelectedCharacterData.config.fightModelPath ~= "" then

        local strArr = string.split(self.SelectedCharacterData.config.fightModelPath, '/')
        local modelPath = string.format("/Script/Engine.Blueprint'/Game/_Game/Blueprints/Players/%s.%s_C'", self.SelectedCharacterData.config.fightModelPath, strArr[2]) 
        -- UE.UAssetManager.GetStreamableManager().RequestAsyncLoad(modelPath, function(self, widget)
        --     print("---------hello world")
        -- end)
        local pos, rot = self:GetActorPosConfig(cameraIndex or self.SelectedTabIndex)

        -- local objPath = UE.FSoftObjectPath(modelPath)
        -- print('--------objPath:' .. tostring(UE.UGHSFunctionLibrary.SoftObjectPathToPackageName(objPath)))
        -- UE.UGHSFunctionLibrary.PreloadClassAssetWithPath(self, objPath, function(obj)
        --     print('---------异步加载')
        --     if obj then
        --         print('----load success') 
        --     end
        -- end)
        local transfrom = UE.UKismetMathLibrary.MakeTransform(pos, rot, UE.FVector(1, 1, 1))
        local actor = self:GetWorld():SpawnActor(UE.UClass.Load(modelPath),
            transfrom, 
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, 
            self, self)
        if actor then
            actor.Mesh:SetEnableGravity(false)
            self.ModelActors[self.SelectedCharacterData.character_id] = actor

            self:LoadActorMesh()
            -- if self.SelectedCharacterData.character_id == 10301 then
            --     print("====id:" .. tostring(self.SelectedCharacterData.character_id))
            --     local idoelMesh = LoadObject("/Script/Engine.SkeletalMesh'/Game/_Game/Characters/1003/Model/Mecha/10301_02/10301_02_Mecha_D.10301_02_Mecha_D'")
            --     local charMesh = LoadObject("/Script/Engine.SkeletalMesh'/Game/_Game/Characters/1003/Model/human/10301_02/10301_02_D.10301_02_D'")
            --     actor:ChangeIdolAndCharMesh(idoelMesh, charMesh)
            -- end

            if self.SelectedCharacterData.config.systemAnimPath ~= '' then
                local systemAnimInstance = UE.UClass.Load(self.SelectedCharacterData.config.systemAnimPath)
                if systemAnimInstance then
                    actor.Mesh:SetAnimClass(systemAnimInstance)
                end

                local animInstance = actor.Mesh:GetAnimInstance()
                if animInstance and animInstance.InitCharacter then
                    animInstance:InitCharacter()
                end
            end
            local idolId, _, _, defaultIdolId, _, _ = UIUtils.GetIdolAndCharMeshByCharacterId(self.SelectedRoleId)
            if idolId <= 0 then idolId = defaultIdolId end
            if actor.InitIdol then
                actor:InitIdol(idolId)
            end
        end
        -- self:RefreshRoleWeapon(self.SelectedCharacterData.weapon_info.item_id)
        self:ShowActor()

        -- 设置overlaymaterial
        if not self.overlayMaterialInstance then
            local materialInstanceObjec = UE.UObject.Load(
                '/Game/_Game/3DRES/Effect/MaterialInstance/ZhuangbeiUI/T_Lianxian2_Mat_Inst.T_Lianxian2_Mat_Inst')
            local materialInstance = actor.mesh:CreateDynamicMaterialInstance(3, materialInstanceObjec, 'None')
            if materialInstance then
                self.overlayMaterialInstance = materialInstance
                actor.mesh:SetOverlayMaterial(self.overlayMaterialInstance)
                actor.SkeletalMesh:SetOverlayMaterial(self.overlayMaterialInstance)
                --男主没有face
                if actor.face then
                    actor.face:SetOverlayMaterial(self.overlayMaterialInstance)
                end

                for _, weaponActor in pairs(actor.weaponActors) do
                    weaponActor.SkeletalMesh:SetOverlayMaterial(self.overlayMaterialInstance)
                end
            else
                LOG_ERROR("====:OverlayMaterialInstance 初始化失败")
            end
        else
            actor.mesh:SetOverlayMaterial(self.overlayMaterialInstance)
            actor.SkeletalMesh:SetOverlayMaterial(self.overlayMaterialInstance)
            --男主没有face
            if actor.face then
                actor.face:SetOverlayMaterial(self.overlayMaterialInstance)
            end
            
            for _, weaponActor in pairs(actor.weaponActors) do
                if UE.UGameplayStatics.IsValid(weaponActor) then
                    weaponActor.SkeletalMesh:SetOverlayMaterial(self.overlayMaterialInstance)
                end
            end
        end
    end
end

function M:RefreshRoleWeapon(item_id)
    local mainHandWeaponModelPath = Database.Query('d_weapon', item_id).weaponModel1
    local offHandWeaponModelPath = Database.Query('d_weapon', item_id).weaponModel2

    if mainHandWeaponModelPath ~= "" then
        if not string.endswith(mainHandWeaponModelPath, "_C'") then
            local sub = string.sub(mainHandWeaponModelPath, 1, -2) .. "_C'"
            mainHandWeaponModelPath = sub
        end
    end

    if offHandWeaponModelPath ~= "" then
        if not string.endswith(offHandWeaponModelPath, "_C'") then
            local sub = string.sub(offHandWeaponModelPath, 1, -2) .. "_C'"
            offHandWeaponModelPath = sub
        end
    end
    LOG_INFO("====RefreshRoleWeapon:" .. tostring(item_id) .. ",mainHandWeaponModelPath:" .. tostring(mainHandWeaponModelPath) .. ",offHandWeaponModelPath:" .. tostring(offHandWeaponModelPath))

    local mainHandWeaponClass = UE.UClass.Load(mainHandWeaponModelPath) or nil
    local offHandWeaponClass = UE.UClass.Load(offHandWeaponModelPath) or nil
    self.ModelActors[self.SelectedCharacterData.character_id].WeaponID = item_id
    self.ModelActors[self.SelectedCharacterData.character_id]:UpdateAllWeapon(mainHandWeaponClass, offHandWeaponClass)
    -- self.ModelActors[self.SelectedCharacterData.character_id]:UpdateWeaponScaleAndOffset()
end

function M:SetRoleVisibility(visible)
    local actor = self.ModelActors[self.SelectedCharacterData.character_id]
    if actor then
        actor:SetActorHiddenInGame(visible)
        local attachedActors = UE.TArray(UE.AActor)
        actor:GetAttachedActors(attachedActors, true, false)
        for i = 1, attachedActors:Length() do 
            local attachActor = attachedActors:Get(i)
            attachActor:SetActorHiddenInGame(visible)
        end
        for _, weaponActor in pairs(actor.weaponActors) do
            weaponActor:SetActorHiddenInGame(visible)
        end
    end
end

function M:RefreshTab()
    if self.SelectedTabIndex == 0 then
        --主控按钮判断
        self.control2:SetVisibility(self.PlayerCharacterIdInCity ~= self.SelectedCharacterData.character_id and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInvisible)
        --角色详情
        self.UI_Panel_Detail:RefreshUI(self.SelectedCharacterData)
        self.UI_Tab:PlayAnimationForward(self.UI_Tab.xiangqing, 1, false)
    elseif self.SelectedTabIndex == 1 then
        --武器
        self:RefreshWeaponPanel()
        self.UI_Tab:PlayAnimationForward(self.UI_Tab.wuqi, 1, false)
    elseif self.SelectedTabIndex == 2 then
        --装备
        self:RefreshEquipPanel()
        self.UI_Tab:PlayAnimationForward(self.UI_Tab.neitianti, 1, false)
    elseif self.SelectedTabIndex == 3 then
        --技能
        self:RefreshSkillPanel()
        self.UI_Tab:PlayAnimationForward(self.UI_Tab.jineng, 1, false)
    elseif self.SelectedTabIndex == 4 then
        --天赋
        self:RefreshTalentPanel(true)
        self.UI_Tab:PlayAnimationForward(self.UI_Tab.xingwei, 1, false)
    end
    self:RefreshEquipEffectAndMaterial()
end

function M:RefreshWeaponPanel()
    self.UI_Panel_Weapon.UI_Itemlist_siderbar:RefreshUI(self.SelectedCharacterData.weapon_info, false, self)
end

function M:RefreshEquipPanel()
    self.UI_Panel_Equip:RefreshUI(self, self.SelectedCharacterData)
end

function M:RefreshSkillPanel()
    self.UI_Panel_Skill:RefreshUI(self, self.SelectedCharacterData)
end

function M:RefreshTalentPanel()
    self.UI_Panel_Talent:RefreshUI(self, self.SelectedCharacterData, true)
end

function M:SetEquipEffectVisibility(visible)
    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "equip")
    local tarCamera = nil
    if cineCameraActors:Length() > 0 then
        tarCamera = cineCameraActors:Get(1)
    end
    local niagaraComponents = tarCamera:K2_GetComponentsByClass(UE.UNiagaraComponent)
    for _, niagaraComponent in pairs(niagaraComponents) do
        niagaraComponent:SetVisibility(visible)
    end
end

function M:RefreshEquipEffectAndMaterial()
    local canShow = false
    if self.SelectedTabIndex == 2 then
        canShow = true
    elseif self.OldSelectTabIndex == 2 then
        canShow = false
    else
        return
    end

    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "equip")
    local tarCamera = nil
    if cineCameraActors:Length() > 0 then
        tarCamera = cineCameraActors:Get(1)
    end
    local niagaraComponents = tarCamera:K2_GetComponentsByClass(UE.UNiagaraComponent)
    for _, niagaraComponent in pairs(niagaraComponents) do
        if not canShow then
            niagaraComponent:SetVisibility(canShow)
        end
    end

    -- 修改mesh SkeletalMesh face weapon的overlaymaterialinstance的alpha
    local curActor = self.ModelActors[self.SelectedCharacterData.character_id]
    if curActor and curActor.mesh then
        if self.overlayMaterialInstance then
            if canShow then
                self.startChangeAlpha = true
                self.delayTime = 0
                self.Alpha = 0
            else
                self.startChangeAlpha = false
                self.overlayMaterialInstance:SetScalarParameterValue('Alpha', 0.0)
            end
        end
    end
end

function M:ChangeActorAndCamera(cameraIndex, charIndex, bFirst)
    self:ChangeCharacterTrans(charIndex, bFirst or false)
    self:ChangeToTargetCamera(cameraIndex, bFirst or false)
end

--设置角色位置和旋转
function M:ChangeCharacterTrans(index, bFirst)
    print("============>>ChangeCharacterTrans:" .. tostring(index) .. ",lastIndex:" .. tostring(self.LastActorTransIndex))
    if not bFirst and index == self.LastActorTransIndex then
        return
    end
    local oldActor = self.ModelActors[self.SelectedCharacterData.character_id]
    if oldActor then
        self.TargetActorStartPos = oldActor:K2_GetActorLocation()
        self.TargetActorStartRot = oldActor:K2_GetActorRotation()
        local pos, rot = self:GetActorPosConfig(index)
        print("============>>pos:" .. tostring(pos) .. ",rot:" .. tostring(rot))
        -- self.TargetActorEndPos = pos
        -- self.TargetActorEndRot = rot
        oldActor:K2_SetActorLocationAndRotation(pos, rot, false, nil, true)
        -- if bFirst then
        --     oldActor:K2_SetActorLocationAndRotation(self.TargetActorEndPos, self.TargetActorEndRot, false, nil, true)
        -- else
        --     local moveSpeed = 500
        --     if index == 7 or self.LastActorTransIndex == 7 then
        --         moveSpeed = 500
        --     end
        --     --计算移动所需时间
        --     local dis = UE.UKismetMathLibrary.Vector_Distance(self.TargetActorStartPos, self.TargetActorEndPos)
        --     self.ActorRotationTime = dis / moveSpeed
        --     self.ActorPassTime = 0
        --     self.bActorCanMove = true
        -- end
    end
    self.LastActorTransIndex = index
end

--切换到指定摄像机角度
function M:ChangeToTargetCamera(index, bFirst)
    print("============>>ChangeToTargetCamera:" .. tostring(index) .. ",last:" .. tostring(self.LastCameraIndex))
    if not bFirst and index == self.LastCameraIndex then
        return
    end
    local curPreTag = self:GetPreTag(index)
    local lastPreTag = self:GetPreTag(self.LastCameraIndex)

    --local charId = self.SelectedCharacterData.character_id
    local defaultTag = curPreTag 
    local preTag = lastPreTag

    local tarCamera = nil
    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, defaultTag)
    if cineCameraActors:Length() > 0 then
        tarCamera = cineCameraActors:Get(1)
    end
    if not tarCamera then
        LOG_ERROR("====找不到移动摄像机:" .. tostring(defaultTag))
        return 
    end
    --print("===========preTag:" .. tostring(preTag) .. ",defaultTag:" .. tostring(defaultTag))
    if tarCamera then
        self.TargetCameraObj = tarCamera
    end
 
    if bFirst then
        if self.MoveCameraObj and self.TargetCameraObj then
            local pos = self.TargetCameraObj:K2_GetActorLocation()
            if pos.Z < -10000 then
                pos.Z = pos.Z + 5000
            end
            self.MoveCameraObj:K2_SetActorLocationAndRotation(pos, self.TargetCameraObj:K2_GetActorRotation(), false, nil, true)

            self.MoveCameraObj.CameraComponent:SetCurrentFocalLength(self.TargetCameraObj.CameraComponent.CurrentFocalLength)
            self.MoveCameraObj.CameraComponent:SetCurrentAperture(self.TargetCameraObj.CameraComponent.CurrentAperture)
        end
        self.LastCameraIndex = index
        return
    end

    if not self.MoveCameraObj then
        LOG_ERROR("====找不到移动摄像机")
        return 
    end

    --创建splineactor
    if not self.SplineActor then
        self.SplineActor = self:GetWorld():SpawnActor(UE.AActor,
            self.MoveCameraObj:GetTransform(),
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
            self, self)

        local trans = UE.UKismetMathLibrary.MakeTransform(
            UE.FVector(0, 0, 0),
            UE.FRotator(0, 0, 0),
            UE.FVector(1, 1, 1))
        self.SplineComponent = self.SplineActor:AddComponentByClass(UE.USplineComponent, false, trans, false)
    end
    if not self.SplineComponent then
        self.SplineComponent = self.SplineActor:GetComponentByClass(UE.USplineComponent)
        if not self.SplineComponent then
            print("=====Error! cant find UE.USplineComponent")
        end
    end

    if self.MoveCameraObj and self.TargetCameraObj and self.SplineComponent then
        self.SplineComponent:ClearSplinePoints(true)

        local MoveCameraObjPos = self.MoveCameraObj:K2_GetActorLocation()
        local TargetCameraObjPos = self.TargetCameraObj:K2_GetActorLocation()
    
        --修正坐标高度:宇宙坐标异常
        if MoveCameraObjPos.Z > 0 then
            MoveCameraObjPos.Z = MoveCameraObjPos.Z - 5000
        end
        if MoveCameraObjPos.Z < -10000 then
            MoveCameraObjPos.Z = MoveCameraObjPos.Z + 5000
        end
        if TargetCameraObjPos.Z > 0 then
            TargetCameraObjPos.Z = TargetCameraObjPos.Z - 5000
        end
        if TargetCameraObjPos.Z < -10000 then
            TargetCameraObjPos.Z = TargetCameraObjPos.Z + 5000
        end

        self.SplineComponent:AddSplinePoint(MoveCameraObjPos, UE.ESplineCoordinateSpace.World, true)
        self.SplineComponent:AddSplinePoint(TargetCameraObjPos, UE.ESplineCoordinateSpace.World, true)

        local isBack = self.LastCameraIndex > index

        local tag = isBack and (curPreTag .. '_' .. lastPreTag) or (lastPreTag .. '_' .. curPreTag)
       
        local Tangentvalue = self.SplineTangentList[tag]

        local MoveTangent = Tangentvalue.Start or UE.FVector(0, 0, 0)
        local TargetTangent = Tangentvalue.End or UE.FVector(0, 0, 0)

        self.SplineComponent:SetTangentAtSplinePoint(0, MoveTangent, UE.ESplineCoordinateSpace.World, true)
        self.SplineComponent:SetTangentAtSplinePoint(1, TargetTangent, UE.ESplineCoordinateSpace.World, true)

        self.SplineComponent:SetDrawDebug(true)

        self.StartRotator = self.MoveCameraObj:K2_GetActorRotation()
        self.EndRotator = self.TargetCameraObj:K2_GetActorRotation()

        local rotationSpeed = self.SplineSpeedList[tag]

        if rotationSpeed == nil then
            rotationSpeed = 500
        end

        local dis = UE.UKismetMathLibrary.Vector_Distance(MoveCameraObjPos, TargetCameraObjPos)
        local calcRotationTime = dis / rotationSpeed
        print("==dis:" .. tostring(dis) .. ",speed:" .. tostring(rotationSpeed) .. ",time:" .. tostring(calcRotationTime))
        if self.LastCameraIndex == 2 or index == 2 then
            calcRotationTime = 0.1
        end
        self.RotationTime = calcRotationTime
        self.passTime = 0
        self.bCanMove = true
    end
    self.LastCameraIndex = index
end

function M:Tick(MyGeometry, InDeltaTime)
    if self.bCanMove then
        self.passTime = self.passTime + InDeltaTime
        if self.passTime <= self.RotationTime then
            local alpha = self.passTime / self.RotationTime
            --角色
            -- local actor = self.ModelActors[self.SelectedCharacterData.character_id]
            -- if actor then
            --     local actorPos = UE.UKismetMathLibrary.VLerp(actor:K2_GetActorLocation(), self.TargetActorEndPos, alpha)
            --     actor:K2_SetActorLocation(actorPos, false, nil, false)
            --     local actorRot = UE.UKismetMathLibrary.RLerp(actor:K2_GetActorRotation(), self.TargetActorEndRot, alpha, true)
            --     actor:K2_SetActorRotation(actorRot, false)
            -- end
            
            --摄像机
            local rot = UE.UKismetMathLibrary.RLerp(self.StartRotator, self.EndRotator, alpha, true)
            self.MoveCameraObj:K2_SetActorRotation(rot, false)
            local pos = UE.UKismetMathLibrary.TransformLocation(self.SplineComponent:GetTransformAtTime(alpha, UE.ESplineCoordinateSpace.World, false, false), nil)
            if pos.Z < -10000 then
                pos.Z = pos.Z + 5000
            end
            self.MoveCameraObj:K2_SetActorLocation(pos, false, nil, false)

            self.MoveCameraObj.CameraComponent:SetCurrentFocalLength(UE.UKismetMathLibrary.Lerp(self.MoveCameraObj.CameraComponent.CurrentFocalLength, self.TargetCameraObj.CameraComponent.CurrentFocalLength, alpha))
            self.MoveCameraObj.CameraComponent:SetCurrentAperture(UE.UKismetMathLibrary.Lerp(self.MoveCameraObj.CameraComponent.CurrentAperture, self.TargetCameraObj.CameraComponent.CurrentAperture, alpha))
        else
            local pos = UE.UKismetMathLibrary.TransformLocation(self.SplineComponent:GetTransformAtTime(1, UE.ESplineCoordinateSpace.World, false, false), nil)
            if pos.Z < -10000 then
                pos.Z = pos.Z + 5000
            end
            self.MoveCameraObj:K2_SetActorRotation(self.EndRotator, false)
            self.MoveCameraObj:K2_SetActorLocation(pos, false, nil, false)
            self.MoveCameraObj.CameraComponent:SetCurrentFocalLength(self.TargetCameraObj.CameraComponent.CurrentFocalLength)
            self.MoveCameraObj.CameraComponent:SetCurrentAperture(self.TargetCameraObj.CameraComponent.CurrentAperture)

            self.bCanMove = false
        end
    end

    -- if self.bActorCanMove then
    --     self.ActorPassTime = self.ActorPassTime + InDeltaTime
    --     if self.ActorPassTime <= self.ActorRotationTime then
    --         local alpha = self.ActorPassTime / self.ActorRotationTime
    --         --角色
    --         local actor = self.ModelActors[self.SelectedCharacterData.character_id]
    --         if actor then
    --             local actorPos = UE.UKismetMathLibrary.VLerp(self.TargetActorStartPos, self.TargetActorEndPos, alpha)
    --             actor:K2_SetActorLocation(actorPos, false, nil, false)
    --             local actorRot = UE.UKismetMathLibrary.RLerp(self.TargetActorStartRot, self.TargetActorEndRot, alpha, true)
    --             actor:K2_SetActorRotation(actorRot, false)
    --         end
    --     else
    --         self.bActorCanMove = false
    --     end
    -- end

    if self.bCanCameraMove then
        self.CameraPassTime = self.CameraPassTime + InDeltaTime
        if self.CameraPassTime <= self.CameraMoveTime then
            local alpha = self.CameraPassTime / self.CameraMoveTime
            local actorPos = UE.UKismetMathLibrary.VLerp(self.CameraStartPos, self.CameraEndPos, alpha)
            if actorPos.Z < -10000 then
                actorPos.Z = actorPos.Z + 5000
            end
            self.MoveCameraObj:K2_SetActorLocation(actorPos, false, nil, false)
        else
            if self.CameraEndPos.Z < -10000 then
                self.CameraEndPos.Z = self.CameraEndPos.Z + 5000
            end
            self.MoveCameraObj:K2_SetActorLocation(self.CameraEndPos, false, nil, false)
            self.bCanCameraMove = false
        end
    end

    if self.startChangeAlpha then
        if self.delayTime >= 0.4 then
            if self.Alpha < 1 then
                self.Alpha = self.Alpha + 0.006
                self.overlayMaterialInstance:SetScalarParameterValue('Alpha', self.Alpha)
            else
                self.startChangeAlpha = false
            end
        else
            self.delayTime = self.delayTime + InDeltaTime
        end
    end
end

function M:BackFromLevelUp()
    self:ChangeRoleAnimation(self.PreTabIndex or 0)
    self:ChangeActorAndCamera(self.PreTabIndex or 0, self.PreTabIndex or 0)
end

function M:SetAllTabBtnEnabled(enable)
    self.UI_Tab.detailTab:SetIsEnabled(enable)
    self.UI_Tab.WeaponTab:SetIsEnabled(enable)
    self.UI_Tab.EquipTab:SetIsEnabled(enable)
    self.UI_Tab.SkillTab:SetIsEnabled(enable)
    self.UI_Tab.TalentTab:SetIsEnabled(enable)
    --返回
    self.Exit:SetIsEnabled(enable)
    --选角
    self.ChangeRole:SetIsEnabled(enable)
end

--加载机甲/皮肤模型
function M:LoadActorMesh()
    local idolId, charId, cityCharId, defaultIdolId, defaultCharId, defaultCityCharId = UIUtils.GetIdolAndCharMeshByCharacterId(self.SelectedRoleId)
    if idolId <= 0 then idolId = defaultIdolId end
    if charId <= 0 then charId = defaultCharId end
    if cityCharId <= 0 then cityCharId = defaultCityCharId end

    local actor = self.ModelActors[self.SelectedCharacterData.character_id] or nil
    if not actor then return end
    
    if idolId > 0 then
        local config = Database.Query("d_char_clothes", idolId)
        if config then
            local newMesh = LoadObject(config.modelF)
            if newMesh then
                actor.Mesh:SetSkeletalMeshAsset(newMesh)
            end
        end
    end

    if cityCharId > 0 then 
        self:ChangeActorMeshEx(cityCharId - 2000000)
    end
   
    local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(self.SelectedCharacterData.character_id)
    if character_info and character_info.weapon_info then
        actor.weapon_id = character_info.weapon_info.item_id
        --刷新武器
        if actor.weapon_id and actor.weapon_id > 0 then
            -- actor:RefreshRoleWeapon(actor.weapon_id)
            self:RefreshRoleWeapon(actor.weapon_id)
        end
    end
end

--刷新当前角色的机甲/角色模型 
function M:ChangeActorMesh(idolPath, charPath)
    local actor = self.ModelActors[self.SelectedCharacterData.character_id] or nil
    if not actor then return end
    
    if idolPath then
        local newMesh = LoadObject(idolPath)
        if newMesh then
            actor.Mesh:SetSkinnedAssetAndUpdate(newMesh, true)
            actor.SkeletalMesh:SetSimulatePhysics(true)
        end
    elseif charPath then
        local newMesh = LoadObject(charPath)
        if newMesh then
            actor.SkeletalMesh:SetSkinnedAssetAndUpdate(newMesh, true)
        end
    end
end

function M:ChangeIdol(idoleId)
    local actor = self.ModelActors[self.SelectedCharacterData.character_id] or nil
    if not actor then return end
    if actor.ChangeIdol then
        actor:ChangeIdol(idoleId)
    end
end

function M:ChangeActorMeshEx(config)
    local actor = self.ModelActors[self.SelectedCharacterData.character_id] or nil
    if not actor then return end

    if type(config) == 'number' then
        local d_char_clothes = require("ClientDatas.d_char_clothes")
        config = d_char_clothes[tonumber(config)]
    end
    -- print("--------ChangeActorMeshEx:" .. table.dump(config, nil, 10))
    --身体
    if config and config.modelF ~= '' then
        local newMesh = LoadObject(config.modelF)
        if newMesh then
            actor.SkeletalMesh:SetSkinnedAssetAndUpdate(newMesh, true)
        end
    end
    --头发
    if config and config.modelHair ~= '' then
        local newMesh = LoadObject(config.modelHair)
        if newMesh then
            actor.Hair:SetSkinnedAssetAndUpdate(newMesh, true)
        end
    end
    --脸
    if config and config.modelFace ~= '' then
        local newMesh = LoadObject(config.modelFace)
        if newMesh then
            actor.face:SetSkinnedAssetAndUpdate(newMesh, true)
        end
    end
end

----------------------------------------------------------------------
---ui event
function M:OnClicked_BtnElement()
    --隐藏UI_CharacterSystem
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Sub_Element')
    ui:SetBackUI(self, self.SelectedCharacterData)
end

function M:OnClicked_DetailLevelUp()
    --隐藏UI_CharacterSystem
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    --角色旋转归零
    -- local actor = self.ModelActors[self.SelectedCharacterData.character_id]
    -- if actor then
    --     actor:K2_SetActorRotation(UE.FRotator(0, 180.0, 0), false, nil, false)
    -- end

    -- print("====roledata:" .. tostring(table.dump(self.SelectedCharacterData, false, 10)))
    local gameInstance = UE4.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9016) then
        local ui = gameInstance:GetUMG('UI_Panel_LevelUp')
        ui:SetBackUI(self, "Character", nil, self.SelectedCharacterData.character_id, self.SelectedCharacterData.break_times, self.SelectedCharacterData.exp)
    end
    
    ---切换角色动作
    -- self.PreTabIndex = self.SelectedTabIndex
    -- self:ChangeRoleAnimation(4)
    -- self:ChangeActorAndCamera(5, 5)
    -- self.CameraStartPos = self.MoveCameraObj:K2_GetActorLocation()
    -- if not self.InitTeamListCameraPos then
    --     self.InitTeamListCameraPos = self.CameraStartPos
    -- end
    -- local offset = self:GetTalentTabOffset() 
    -- local cameraEndPos = self.InitTeamListCameraPos + UE.FVector(0, offset, 0)
    -- self.MoveCameraObj:K2_SetActorLocation(cameraEndPos, false, nil, false)
    self:MoveCameraToLevelUp()
end

function M:OnClicked_FightProperty()
    --隐藏UI_CharacterSystem
    self:SetVisibility(UE.ESlateVisibility.Hidden)

    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_FightProperty')
    ui:SetBackUI(self, self.SelectedCharacterData)
end

function M:OnClicked_WeaponReplace()
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Weapon_Change')
    ui:SetBackUI(self, self.SelectedCharacterData)
end

function M:OnClicked_WeaponLevelUp()
    local weaponInfo = self.SelectedCharacterData.weapon_info
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9017, "") then
        self:SetVisibility(UE.ESlateVisibility.Hidden)
        local ui = gameInstance:GetUMG('UI_Levelup_weapon')
        ui:SetBackUI(self, weaponInfo, true)
        ---切换角色动作
        self.PreTabIndex = self.SelectedTabIndex
        -- self:ChangeRoleAnimation(4)
        -- self:ChangeActorAndCamera(6, 6)
    end
end

function M:OnClicked_WeaponRefine()
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_weapon_refined')
    local weaponInfo = self.SelectedCharacterData.weapon_info
    ui:SetBackUI(self, weaponInfo, false)
end

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if pc and pc.BP_PlayerController_City_UniverseBridge and pc.BP_PlayerController_City_UniverseBridge.UnloadCharacterSystem then
        pc.BP_PlayerController_City_UniverseBridge:UnloadCharacterSystem()
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:OnClicked_DressBtn()
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_idol_Dress')
    ui:RefreshUI(self, self.SelectedCharacterIndex)

    ---切换角色动作
    self.PreTabIndex = self.SelectedTabIndex
    self:ChangeRoleAnimation(3)
    self:ChangeActorAndCamera(5, 8)
end

function M:OnClicked_PlayerControl()
    print("self.PlayerCharacterIdInCity:" .. tostring(self.PlayerCharacterIdInCity))
    print("self.SelectedCharacterData.character_id:" .. tostring(self.SelectedCharacterData.character_id))
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if pc and pc.IsInBuildLevel then
        UIUtils.ShowNotify(self, Database.L10n(326))
        return
    end
    if self.PlayerCharacterIdInCity ~= self.SelectedCharacterData.character_id then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:ChangePlayerCharacterInCity(self.SelectedCharacterData.character_id)
        MessageManager:GetInstance():Broadcast('OnChangePlayerController', self.SelectedCharacterData.character_id)

        --主控按钮判断
        self.PlayerCharacterIdInCity = self.SelectedCharacterData.character_id
        self.control2:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end
end

function M:OnClicked_ExplainBtn2()
    UIUtils.ShowSystemDes(1001)
end

function M:OnCheckStateChanged_DetailTab(isOn)
    if isOn then
        self:OnTabCheckStateChanged(0)
    end
end

function M:OnCheckStateChanged_WeaponTab(isOn)
    if isOn then
        self:OnTabCheckStateChanged(1)
    end
end

function M:OnCheckStateChanged_EquipTab(isOn)
    if isOn then
        self:OnTabCheckStateChanged(2)
    end
end

function M:OnCheckStateChanged_SkillTab(isOn)
    if isOn then
        self:OnTabCheckStateChanged(3)
    end
end

function M:OnCheckStateChanged_TablentTab(isOn)
    if isOn then
        self:OnTabCheckStateChanged(4)
    end
    --UIUtils.ShowComNotice(Database.L10n(50500), self)
end

function M:OnTabCheckStateChanged(index)
    if self.SelectedTabIndex ~= index then
        if self.SelectedTabIndex == 4 then
            self.UI_Panel_Talent:OnHide()
        end

        self:ChangeRoleAnimation(index)
        self:ChangeActorAndCamera(index, index)
        self.WidgetSwitcher:SetActiveWidgetIndex(index)
        self:RefreshTab()

        self:SetAllTabBtnEnabled(false)
        self.TabTimeHander = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            { self, self.DoDelayTabTimeEnd }, 
            self.TabTime, 
            false
        )
    end
end

function M:DoDelayTabTimeEnd()
    self:SetAllTabBtnEnabled(true)
end

function M:OnClicked_ChangeRole()
    self.UI_Panel_Talent:OnHide()
    self.WidgetSwitcher:SetVisibility(UE.ESlateVisibility.Hidden)
    self.ChangeRoleList:SetVisibility(UE.ESlateVisibility.Visible)
    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Team_List')
    if ui then
        ui:SetBackUI(self, 0, "CharacterSystem", self.SelectedCharacterIndex)
    end
    --self:ChangeActorAndCamera(7, 7)

    self:MoveCameraPlane(false)
end

function M:OnClicked_Btn_Imame_Skill_White()
    self.UI_Panel_Skill:ClickWhiteArea()
    return UE.UWidgetBlueprintLibrary.Handled()
end

function M:MoveCameraPlane(bBack)
    --print("===MoveCameraPlane:" .. tostring(bBack) .. ",skillpos:" .. tostring(self.InitSkillCameraPos) .. ",team:" .. tostring(self.InitTeamListCameraPos))
    if self.SelectedTabIndex == 2 then
        self:SetEquipEffectVisibility(bBack)
        if bBack then
            self:RefreshEquipPanel()
        end
    elseif self.SelectedTabIndex == 4 then
        --星位特效
        self:RefreshTalentPanel(true)
    end
    
    self.CameraStartPos = self.MoveCameraObj:K2_GetActorLocation()
    if not bBack or not self.InitTeamListCameraPos then
        self.InitTeamListCameraPos = self.CameraStartPos
    end
    local offset = bBack and 0 or (self:GetTalentTabOffset() + (self.LastSkillCameraOffsetY or 0))
    self.CameraEndPos = self.InitTeamListCameraPos - UE.FVector(0, offset, 0)

    self.CameraMoveTime = 0.1
    self.CameraPassTime = 0
    self.bCanCameraMove = true
end

function M:SkillMoveCamera(bBack)
    --print("===SkillMoveCamera:" .. tostring(bBack) .. ",skillpos:" .. tostring(self.InitSkillCameraPos) .. ",team:" .. tostring(self.InitTeamListCameraPos))
    self.CameraStartPos = self.MoveCameraObj:K2_GetActorLocation()
    if not bBack or not self.InitSkillCameraPos then
        self.InitSkillCameraPos = self.CameraStartPos
    end
    self.LastSkillCameraOffsetY = (bBack and 0 or (20))
    self.CameraEndPos = self.InitSkillCameraPos + UE.FVector(0, self.LastSkillCameraOffsetY, 0)
    self.CameraMoveTime = 0.1
    self.CameraPassTime = 0
    self.bCanCameraMove = true
end

function M:MoveCameraToLevelUp(bBack)
    -- self.CameraStartPos = self.MoveCameraObj:K2_GetActorLocation()
    -- if not bBack or not self.InitTeamListCameraPos then
    --     self.InitTeamListCameraPos = self.CameraStartPos
    -- end
    -- local offset = bBack and 0 or self:GetTalentTabOffset()
    -- self.CameraEndPos = self.InitTeamListCameraPos + UE.FVector(0, offset, 0)
    -- if self.CameraEndPos.Z < -10000 then
    --     self.CameraEndPos.Z = self.CameraEndPos.Z + 5000
    -- end
    -- self.MoveCameraObj:K2_SetActorLocation(self.CameraEndPos, false, nil, false)

    local offset = self.SelectedCharacterData.config.levelUpOffset
   
    local actorMode = self.ModelActors[self.SelectedCharacterData.character_id] or nil
    if actorMode then
        local offset = bBack and offset or (-offset)
        local newPos = actorMode:K2_GetActorLocation() + UE.FVector(0, offset, 0)
        actorMode:K2_SetActorLocation(newPos, false, nil, true)
    end
end

----------------------------------------------------------------------
---辅助函数
function M:GetTalentTabOffset()
    local offsetY = 0
    local index = self.SelectedTabIndex
    if index == 0 then
        offsetY = 80
    elseif index == 1 then
        offsetY = 80
    elseif index == 2 then
        offsetY = 120
    elseif index == 3 then
        offsetY = 40
    elseif index == 4 then
        offsetY = 70
    end
    return offsetY
end

---切换角色动作
function M:ChangeRoleAnimation(index)
    --print("====ChangeRoleAnimation:" .. tostring(index) .. ",pre:" .. tostring(self.PreTabIndex) .. ",selectedindex:" .. tostring(self.SelectedTabIndex))
    --主角模型
    local actor = self.ModelActors[self.SelectedCharacterData.character_id]
    if actor and actor.Mesh then
        local animInstance = actor.Mesh:GetAnimInstance()
        if animInstance and animInstance.ChangeTab then
            animInstance:ChangeTab(self.SelectedTabIndex, index)
        end
    end
    self.OldSelectTabIndex = self.SelectedTabIndex
    self.SelectedTabIndex = index
end

function M:ShowActorWeapon(visible)
    local actor = self.ModelActors[self.SelectedCharacterData.character_id]
    for _, weaponActor in pairs(actor.weaponActors) do
        weaponActor:SetActorHiddenInGame(not visible)
    end
end

function M:RefreshActorLocation(index)
    local actorMode = self.ModelActors[self.SelectedCharacterData.character_id] or nil
    if actorMode then
        local pos, rot = self:GetActorPosConfig(index)
        actorMode:K2_SetActorLocationAndRotation(pos, rot, false, nil, true)
    end
end

function M:GetPreTag(index)
    local preTab = ""
    if index == 0 then
        preTab = "detail"
    elseif index == 1 then
        preTab = "weapon"
    elseif index == 2 then 
        preTab = "equip"
    elseif index == 3 then
        preTab = "skill"
    elseif index == 4 then
        preTab = "talent"
    elseif index == 5 then
        preTab = "dress"
    elseif index == 6 then
        preTab = "level"
    elseif index == 7 then
        preTab = "list"
    elseif index == 8 then
        preTab = "side"
    end
    return preTab
end

function M:GetConfigAxisName(index)
    local cameraPos = ""
    if index < 5 then
        cameraPos = "charAxis" .. (index + 1)
    elseif index == 5 then
        cameraPos = "charAxisLevel"	--升级
    elseif index == 6 then
        cameraPos = "charAxisSide" --技能侧边栏
    elseif index == 7 then
        cameraPos = "charAxisList" --角色列表
    elseif index == 8 then
        cameraPos = "charAxisDress2" --装扮里的服装页签
    elseif index == 9 then
        cameraPos = "mechaDressAxis" --装扮里的机甲页签
    elseif index == 10 then
        cameraPos = 'charAxisDress' --装扮主城页签
    end
    return cameraPos
end

function M:GetActorPosConfig(index)
    local axisName = self:GetConfigAxisName(index)
    local posConfig = self.SelectedCharacterData.config[axisName]
    local pos = UE.FVector(posConfig[1] / 1000000, posConfig[2] / 1000000, posConfig[3] / 1000000)
    local rot = UE.FRotator(posConfig[5] / 1000000, posConfig[6] / 1000000, posConfig[4] / 1000000)
    return pos, rot
end

function M:OnKey2()

    --获取当前角色的位置信息
    local actor = self.ModelActors[self.SelectedCharacterData.character_id]
    if actor then
        local pos = actor:K2_GetActorLocation()
        local rot = actor:K2_GetActorRotation()
        local d_character = require("ClientDatas.d_character")
        local axisName = self:GetConfigAxisName(self.LastActorTransIndex)
        local curConfig = d_character[self.SelectedCharacterData.character_id]
        print("==axisName:" .. tostring(axisName))
        if self.SelectedCharacterData.config[axisName] then
            self.SelectedCharacterData.config[axisName][1] = math.floor(pos.X * 1000000)
            self.SelectedCharacterData.config[axisName][2] = math.floor(pos.Y * 1000000)
            self.SelectedCharacterData.config[axisName][3] = math.floor(pos.Z * 1000000)

            self.SelectedCharacterData.config[axisName][4] = math.floor(rot.Roll * 1000000)
            self.SelectedCharacterData.config[axisName][5] = math.floor(rot.Pitch * 1000000)
            self.SelectedCharacterData.config[axisName][6] = math.floor(rot.Yaw * 1000000)
        end
      
        d_character[self.SelectedCharacterData.character_id] = self.SelectedCharacterData.config
        print("====当前路径:" .. tostring(UE.FPaths.ProjectContentDir()))
        local file = io.open(UE.FPaths.ProjectContentDir() .. "Script/ClientDatas/d_character.lua", "w+")
        io.output(file) --设置默认输出文件
        local content = "return " .. table.dump(d_character, false, 10)
        content = string.sub(content, 0, string.len(content) - 1)
        print("==content:" .. content)
        io.write(content)
        io.close()
    end
end

return M