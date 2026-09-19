--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"

---@type UI_Build_C
local M = Class()

local Database = require('_Game.Utils.Database')
local UIUtils = require('_Game.Utils.UIUtils')
local BackpackSystem = require 'Module.Backpack.BackpackSystem'
local BuildSystem = require('Module.BuildSystem.BuildSystem')
local CharacterSystem = require('Module.CharacterSystem.CharacterSystem')

--构造函数
function M:Construct()
    self.Overridden.Construct(self)
    self:InitData()
    self:InitUI()
    self:InitBuild()
    self:InitBuildData()

    MessageManager:GetInstance():AddListener("OnResBuildHome", self)

    local isApp = not UE.UGHSFunctionLibrary.WithEditor() and UIUtils.IsAndroidOrIOS()
    self.TouchJoystickLeft:SetVisibility(isApp and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnResBuildHome", self)

    self.HitActor = nil
    self.BuildRegion = nil
    self.GhostComponentRef = nil
end 

function M:OnResBuildHome()
    UIUtils.ShowNotify(self, Database.L10n(279))
end

function M:InitBuildData()
    self.FurnitureData = {}
    self.CachedItemDataList = {}

    --从背包中获取建筑物品
    local itemInfos = BackpackSystem:GetInstance():GetAllItemByMainType(UIUtils.ItemMainType.Build) 
    for _, itemInfo in pairs(itemInfos) do
        if not self.FurnitureData[itemInfo.config.subType] then
            self.FurnitureData[itemInfo.config.subType] = {}
        end
        local buildCount = BuildSystem:GetInstance():GetBuildCount(itemInfo.item_id)

        local bHasChar = true
        if itemInfo and itemInfo.config and itemInfo.config.subType == 1 and itemInfo.config.subParam and itemInfo.config.subParam[1] then
            local charId = itemInfo.config.subParam[1]
            if charId and charId > 0 then
                local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId)
                if not charInfo then
                    bHasChar = false
                end
            end
        end
        
        -- if bHasChar then
            local buildInfo = 
            {
                item_id = itemInfo.item_id,
                item_count = itemInfo.count, --道具个数
                build_count = buildCount, --已经建造个数
                temp_build_count = 0, --临时建造个数
                config = itemInfo.config,
                selected = false,
                cached_selected = false,
            }
            table.insert(self.FurnitureData[itemInfo.config.subType], buildInfo)
        -- end
    end
   
    for _, datas in pairs(self.FurnitureData) do
        if #datas > 1 then
            table.sort(datas, function(a, b)
                return a.item_id < b.item_id
            end)
        end
    end
end

function M:InitData()
    self.HitActor = nil
    self.MoveRate = 10
    self.isBackpackOpen = true
    self.isEditing = false
    self.ControlType = 1
    self.GhostComponentRef = nil
    self.TempBuild = false
    self.ItemDataList = {}
    self.CachedItemDataList = {}

    self.FurnitureData = {}
    self.AllBuildActors = {}

    self.isChanged = false

    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    local player = controller:K2_GetPawn()
    local nearDistance = 0
    local nearIndex = 1
    self.CameraList = {}
    --获取场景中所有的actor
    local regionCameras = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "BuildRegion")
    if regionCameras:Length() > 0 then
        for i = 1, regionCameras:Length() do
            local camera = regionCameras:Get(i)
            local posTag = camera.Tags:Get(2)
            local index = string.sub(posTag, 4, -1)
            local distance = UE.UKismetMathLibrary.Vector_Distance(camera:K2_GetActorLocation(), player:K2_GetActorLocation())
            if nearDistance == 0 then
                nearDistance = distance
                nearIndex = index
            else
                if distance < nearDistance then
                    nearDistance = distance
                    nearIndex = index
                end
            end
            self.CameraList[index] = camera
        end
    end
    self.CameraIndex = nearIndex
end

function M:InitUI()
    self.Btn_Exit.OnGHSClicked:Add(self, self.OnClicked_Btn_Exit)
    self.Btn_Backpack.OnClicked:Add(self, self.OnClicked_Btn_Backpack)

    self.Btn_Sticker.OnGHSClicked:Add(self, self.OnClicked_Btn_Sticker)
    self.Btn_Platform.OnGHSClicked:Add(self, self.OnClicked_Btn_Platform)
    self.Btn_Decorate.OnGHSClicked:Add(self, self.OnClicked_Btn_Decorate)
    self.Btn_Hang.OnGHSClicked:Add(self, self.OnClicked_Btn_Hang)

    self.Btn_Cancel.OnClicked:Add(self, self.OnClicked_Btn_Cancel)
    self.Btn_Back.OnClicked:Add(self, self.OnClicked_Btn_Back)
    self.Btn_Sure.OnClicked:Add(self, self.OnClicked_Btn_Sure)
    self.Btn_Move.OnClicked:Add(self, self.OnClicked_Btn_Move)
    self.Btn_Change.OnClicked:Add(self, self.OnClicked_Btn_Change)

    self.Btn_Save.OnClicked:Add(self, self.OnClicked_Btn_Save)
    self.Btn_BackAll.OnClicked:Add(self, self.OnClicked_Btn_BackAll)

    self.Panel_Backpack:SetVisibility(self.isBackpackOpen and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

    --生成器
    self.ListView_Backpack.BP_OnEntryInitialized:Clear()
    self.ListView_Backpack.BP_OnEntryInitialized:Add(self, function(wbp, data, ui) 
        self:BP_OnEntryInitialized_Backpack(data, ui)
    end)
    --点击事件
    self.ListView_Backpack.BP_OnItemClicked:Clear()
    self.ListView_Backpack.BP_OnItemClicked:Add(self, function(wbp, data)
        self:BP_OnItemClicked_Backpack(data)
    end)

    --缓存栏
    self.ListView_Cached.BP_OnEntryInitialized:Clear()
    self.ListView_Cached.BP_OnEntryInitialized:Add(self, function(wpb, data, ui)
        self:BP_OnEntryInitialized_Cached(data, ui)
    end)
    self.ListView_Cached.BP_OnItemClicked:Clear()
    self.ListView_Cached.BP_OnItemClicked:Add(self, function(wpb, data)
        self:BP_OnItemClicked_Cached(data)
    end)

    self.Btn_Cancel:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Btn_Back:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Btn_Sure:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:SetRegion(buildRegion)
    self.BuildRegion = buildRegion
end

function M:BuildPlayStart()
    print("-----BuildPlayStart")
    self:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    if controller and controller.BP_PlayerController_City_UniverseBridge then
        controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        --controller:EnableInput()
    end
    if self.isBackpackOpen then
        self:TabSelected(1)
    end
end

function M:BuildPlayEnd(bIsOutRegion)
    print("-----BuildPlayEnd")
    self:ExitEditing()
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    
    if not self.isChanged then 
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:RemoveTopUI(true)
        return 
    end
    --提示是否保存
    UIUtils.ShowComNotice(Database.L10n(278), self, 
        function()
            self:OnClicked_Btn_Save()
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            gameInstance:RemoveTopUI(true)
        end,
        function()
            self:RecoveryAllBuildActors()
            self:BuildDefaultActors()
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            gameInstance:RemoveTopUI(true)
        end)
end

function M:BuildDefaultActors()
    self.AllBuildActors = {}

    local BuildSystem = require('Module.BuildSystem.BuildSystem')
    local buildInfo = BuildSystem:GetInstance().BuildInfo
    for _, info in pairs(buildInfo) do
        local strArr = string.split(info.blob, ',')
        local loc = UE.FVector(tonumber(strArr[1]), tonumber(strArr[2]), tonumber(strArr[3]))
        local rot = UE.FRotator(tonumber(strArr[4]), tonumber(strArr[6]), tonumber(strArr[5]))
        local trans = UE.UKismetMathLibrary.MakeTransform(loc, rot, UE.FVector(1, 1, 1))
        local uuid = tonumber(strArr[7])
        local parentUUID = tonumber(strArr[8])

        local UIUtils = require('_Game.Utils.UIUtils')
        local d_bag_item_furniture = require('ClientDatas.d_bag_item_furniture')
        local config = d_bag_item_furniture[info.item_id]
        if config then
            local actorPath = config.actorPath
            -- if not string.endswith(actorPath, "_C'") then
                actorPath = string.sub(actorPath, 1, -2) .. "_C'"
            -- end
            if actorPath ~= '' then
                local buildActor = self:GetWorld():SpawnActor(UE.LoadClass(actorPath),
                    trans,
                    UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
                    self, self)
                buildActor:SetID(info.item_id)
                buildActor:SetUUID(uuid)
                buildActor:SetParentUUID(parentUUID)

                table.insert(self.AllBuildActors, buildActor)
            end
        end
    end

    --父子关系
    for uuid, actor in pairs(self.AllBuildActors ) do
        local parentUUID = actor:GetParentUUID()
        if parentUUID > 0 then
            local parentActor = self.AllBuildActors[parentUUID]
            if parentActor then
                actor:K2_AttachToActor(parentActor, "",
                    UE.EAttachmentRule.KeepWorld,
                    UE.EAttachmentRule.KeepWorld,
                    UE.EAttachmentRule.KeepWorld,
                    false)
            end
        end
    end
end


function M:InitBuild()
    self.AllBuildActors = {} --所有构建出来的actor

    --获取场景中所有的actor
    local buildActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "Buildable")
    for i = 1, buildActors:Length() do
        local actor = buildActors:Get(i)
        local uuid = actor:GetUUID()
        self.AllBuildActors[uuid] = actor
    end
end

function M:ChangeBuildActor()
    if self.HitActor then
        if self.HitActor then
            if self.TempBuild then
                self.HitActor:K2_DestroyActor()
            else
                self:SetBuildCustomStencil(self.HitActor, false, 0)
            end
            
            self.HitActor = nil
        end
    end
    if self.SelectedItemData then
        local charLocation = UE.FVector(0, 0, 0)
        local forwardVector = UE.FVector(0, 0, 0)
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        local character = pc:K2_GetPawn()
        if character and character.BuildingComponent then
            charLocation = character:K2_GetActorLocation()
            forwardVector = character:GetActorForwardVector() * 500
            forwardVector.Z = 0
        end

        --获取当前摄像机朝向
        -- local cameraManger = UE.UGameplayStatics.GetPlayerCameraManager(self, 0)
        -- local forwardVector = cameraManger:GetActorForwardVector() * 500
        -- forwardVector.Z = 0
        -- local pos = charLocation + forwardVector

        local pos = charLocation + forwardVector
        

        local trans = UE.UKismetMathLibrary.MakeTransform(pos, UE.FRotator(0, 0, 0), UE.FVector(1, 1, 1))
        local d_bag_item_furniture = require('ClientDatas.d_bag_item_furniture')
        local config = d_bag_item_furniture[self.SelectedItemData.item_id]
        local actorPath = config.actorPath
        -- if not string.endswith(actorPath, "_C'") then
            actorPath = string.sub(actorPath, 1, -2) .. "_C'"
        -- end
        if actorPath ~= '' then
            local actorClass = UE.LoadClass(actorPath)
            if not actorClass then
                LOG_ERROR('----加载actorclass失败:' .. tostring(actorPath))
                return
            end
            local buildActor = self:GetWorld():SpawnActor(UE.LoadClass(actorPath),
                trans,
                UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
                self, self)

            buildActor:SetID(self.SelectedItemData.item_id)
            local uuid = tostring(self.SelectedItemData.item_id) .. tostring(os.time())
            buildActor:SetUUID(tonumber(uuid))
            self.HitActor = buildActor
            self:EnterEditing()

            local canBuild = self:CheckOverlap()
            self:ChangeLockedActorColor(canBuild)
            --重设一下位置信息
            self.LockedActorTrans = self.HitActor:GetTransform()

            self.TempBuild = true
        end
    end
end

function M:TabSelected(index)
    self.TabSwitcher1:SetActiveWidgetIndex(index == 1 and 1 or 0)
    self.TabSwitcher2:SetActiveWidgetIndex(index == 2 and 1 or 0)
    self.TabSwitcher3:SetActiveWidgetIndex(index == 3 and 1 or 0)
    self.TabSwitcher4:SetActiveWidgetIndex(index == 4 and 1 or 0)

    self.ListView_Backpack:ClearListItems()
    self.ItemDataList = self.FurnitureData[index] or {}

    local itemDataSource = {}
    if self.ItemDataList and #self.ItemDataList > 0 then
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Item.UI_Item_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)

        for i, data in ipairs(self.ItemDataList) do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i
            ItemData.ItemId = data.item_id
            table.insert(itemDataSource, ItemData)
        end
    end
    self.ListView_Backpack:BP_SetListItems(itemDataSource)
end

function M:RefreshCachedList()
    self.ListView_Cached:ClearListItems()

    local itemDataSource = {}
    if self.CachedItemDataList and #self.CachedItemDataList > 0 then
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Item.UI_Item_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)

        for i, data in ipairs(self.CachedItemDataList) do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i
            ItemData.ItemId = data.item_id
            table.insert(itemDataSource, ItemData)
        end
    end
    self.ListView_Cached:BP_SetListItems(itemDataSource)
end

function M:RefreshItemCell(itemData, ui, isBackpack)
    ui.ItemId = itemData.item_id

    --个数/名字
    ui.TextPrice:SetText(itemData.item_count - itemData.build_count - itemData.temp_build_count)
    ui.TextName:SetText(Database.L10n(itemData.config.itemName))

    --品质框
    if itemData and itemData.config and itemData.config.rarityPath and itemData.config.rarityPath ~= '' then
        local strArr = string.split(itemData.config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            ui.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if itemData and itemData.config and itemData.config.iconPath and itemData.config.iconPath ~= '' then
        local strArr = string.split(itemData.config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        local sprite_object = UE.UObject.Load(iconResPath)
        local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
        if iconRes then
            ui.icon_res:SetBrush(icon_sprite)
        end
    end

    -- if itemData.rarity <= 6 then
    --     ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
    -- else
    --     ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    -- end

    -- ui.ImageBG.OnMouseButtonDownEvent:Bind(self, function()
    --     UIUtils.ShowItemInfo(itemData.item_id, BackpackSystem:GetInstance():GetItemCount(itemData.item_id))
    --     return UE.UWidgetBlueprintLibrary.Handled()
    -- end)

    if isBackpack then
        ui.ImageBGSelected:SetVisibility(itemData.selected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        ui.Panel_Selected:SetVisibility(itemData.selected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    else
        ui.ImageBGSelected:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Panel_Selected:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:GetIsBuildModeOpen()
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    local character = pc:K2_GetPawn()
    if character and character.BuildingComponent then
        return character.BuildingComponent.IsBuildModeOn
    end
    return false
end

function M:ChangeLockedActorColor(bCanBuild)
    self.CanBuild = bCanBuild
    self.Btn_Sure:SetIsEnabled(bCanBuild)
    if self.LockedActor then
        self:SetBuildCustomStencil(self.LockedActor, true, bCanBuild and 233 or 234)
    end
end

--保存当前编辑的建筑
function M:SaveTempBuildActor()
    if self.LockedActor then
        if not self.CanBuild then
            self.LockedActor:K2_DestroyActor()
            self.LockedActor = nil
            self.TempParentActor = nil
            self.TempBuild = false
            return
        end

        if not self.isEditing then
            if self:CheckHasSomeCharId(self.SelectedItemData.item_id) then
                UIUtils.ShowNotify(self, Database.L10n(277))
                return
            end
        end

        --附加到父actor
        if self.TempParentActor then
            self.LockedActor:K2_AttachToActor(self.TempParentActor, "",
                UE.EAttachmentRule.KeepWorld,
                UE.EAttachmentRule.KeepWorld,
                UE.EAttachmentRule.KeepWorld,
                false)
            self.LockedActor:SetParentUUID(self.TempParentActor:GetUUID())
        else
            self.LockedActor:SetParentUUID(0)
        end

        local buildId = self.LockedActor:GetID()
        local uuid = self.LockedActor:GetUUID()
        print('--------lockedActor buildId is ' .. tostring(buildId))
        if buildId <= 0 then
            LOG_ERROR('-----错误的buildId:' .. tostring(buildId))
            return
        end

        local itemData = self:GetBuildDataById(buildId)
        if itemData then
            --修正个数
            itemData.build_count = itemData.build_count + 1
            itemData.temp_build_count = 0
            local count = itemData.item_count - itemData.build_count - itemData.temp_build_count
            if count <= 0 then
                itemData.selected = false
                self:RemoveCachedBuild(buildId)
                self:RefreshCachedList()
            end
            self:RefreshListItemCount(buildId)
        end
        if self.SelectedItemData then
            self.SelectedItemData.cached_selected = false
            self:RefreshCachedListSelectedItem(self.SelectedItemData.item_id, self.SelectedItemData.cached_selected)
        end
        self.AllBuildActors[tonumber(uuid)] = self.LockedActor
        
        self.TempBuild = false
    end
end

--回收所有建筑
function M:RecoveryAllBuildActors()
    for uuid, actor in pairs(self.AllBuildActors) do 
        local buildId = actor:GetID()
        --判断是否是地台
        if self:GetTypeByBuildId(buildId) == 2 then
            local attachedActors = UE.TArray(UE.AActor)
            actor:GetAttachedActors(attachedActors, true, false)
            for j = 1, attachedActors:Length() do
                local attachedActor = attachedActors:Get(j)
                if attachedActor then
                    if attachedActor and attachedActor.GetID then
                        local childId = attachedActor:GetID()
                        --print('=====childId' .. tostring(childId))
                        local itemData = self:GetBuildDataById(childId)
                        if itemData then
                            itemData.temp_build_count = 0
                            itemData.build_count = math.max(itemData.build_count - 1, 0)
                            local count = itemData.item_count - itemData.build_count - itemData.temp_build_count
                            if count <= 0 then
                                self:RemoveCachedBuild(childId)
                                self:RefreshCachedList()
                            end
                            self:RefreshListItemCount(childId)
                            itemData.selected = count <= 0
                            self:RefreshBackpackListSelectedItem(childId, count <= 0)
                        end
                    end
                end
            end
        end

        local itemData = self:GetBuildDataById(buildId)
        if itemData then
            itemData.temp_build_count = 0
            if not self.TempBuild then
                itemData.build_count = math.max(itemData.build_count - 1, 0)
            end
            local count = itemData.item_count - itemData.build_count - itemData.temp_build_count
            if count <= 0 then
                self:RemoveCachedBuild(buildId)
                self:RefreshCachedList()
            end
            self:RefreshListItemCount(buildId)
            itemData.selected = count <= 0
            self:RefreshBackpackListSelectedItem(buildId, count <= 0)
        end
        actor:K2_DestroyActor()
    end
    self.AllBuildActors = {}
    self.isChanged = true
end

--选中的actor
function M:OnHitActor(bHitActor)
    local show = not self.isBackpackOpen and bHitActor
    self.Btn_Sure:SetVisibility(show and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    if show then
        self.Btn_Sure:SetIsEnabled(true)
    end
end

----------------------------------------------------------------------
---编辑状态
function M:EnterEditing()
    if self.HitActor then
        self.LockedActor = self.HitActor
        self.LockedActorTrans = self.HitActor:GetTransform()
        if self.LockedActor then
            self:SetBuildCustomStencil(self.LockedActor, true, 233)
        end
        local staticComps = self.LockedActor:K2_GetComponentsByClass(UE.USkeletalMeshComponent)
        for i = 1, staticComps:Length() do
            local staticMeshComp = staticComps:Get(i)
            if staticMeshComp then
                staticMeshComp:SetCollisionEnabled(UE.ECollisionEnabled.NoCollision)
                staticMeshComp:SetCollisionResponseToChannel(UE.ECollisionChannel.ECC_Visibility, UE.ECollisionResponse.ECR_Ignore)
            end
        end
      
        self.isEditing = true

        self.Btn_Cancel:SetVisibility(UE.ESlateVisibility.Visible)
        self.Btn_Back:SetVisibility(UE.ESlateVisibility.Visible)
        self.Btn_Sure:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function M:ExitEditing()
    if self.LockedActor then
        self:SetBuildCustomStencil(self.LockedActor, false, 0)
        if self.TempBuild then
            self.LockedActor:K2_DestroyActor()
        end
        self.LockedActor = nil
    elseif self.HitActor then
        self:SetBuildCustomStencil(self.HitActor, false, 0)
        self.HitActor = nil
    end
   
    self.isEditing = false
    self.TempBuild = false
    self.Btn_Sure:SetIsEnabled(true)

    self.Btn_Cancel:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Btn_Back:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Btn_Sure:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:CancelEditing()
    if self.LockedActor then
        self.LockedActor:K2_SetActorTransform(self.LockedActorTrans, false, nil, false)
        self:ExitEditing()
    end
end

function M:OnCanBuildChanged()
    self.Btn_Sure:SetIsEnabled(true)
end

----------------------------------------------------------------------
--- ui event
function M:OnClicked_Btn_Exit()
    self:BuildPlayEnd()
end

--背包按钮
function M:OnClicked_Btn_Backpack()
    self.isBackpackOpen = not self.isBackpackOpen
    self.Panel_Backpack:SetVisibility(self.isBackpackOpen and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Img_BackpackArrow:SetRenderTransformAngle(self.isBackpackOpen and -90 or 90)
    if self.isBackpackOpen then
        --退出编辑状态
        self:CancelEditing()
    end
    
    local show = not self.isBackpackOpen and self.HitActor
    self.Btn_Sure:SetVisibility(show and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

function M:OnClicked_Btn_Sticker()
    self:TabSelected(1)
end

function M:OnClicked_Btn_Platform()
    self:TabSelected(2)
end

function M:OnClicked_Btn_Decorate()
    self:TabSelected(3)
end

function M:OnClicked_Btn_Hang()
    self:TabSelected(4)
end

function M:BP_OnEntryInitialized_Backpack(data, ui)
    local itemData = self.ItemDataList[data.Index]
    self:RefreshItemCell(itemData, ui, true)
end

function M:BP_OnItemClicked_Backpack(data)
    local itemData = self.ItemDataList[data.index]
    local leftCount = itemData.item_count - itemData.build_count - itemData.temp_build_count
    if leftCount <= 0 then
        UIUtils.ShowNotify(self, Database.L10n(280))
        return
    end 
    local hasData = false
    for _, iData in ipairs(self.CachedItemDataList) do
        if iData.item_id == itemData.item_id then
            hasData = true
            break
        end
    end
    if not hasData then
        --设置选中
        itemData.selected = true
        self:RefreshBackpackListSelectedItem(itemData.item_id, itemData.selected)
        --加入缓存列表
        itemData.cached_selected = false
        table.insert(self.CachedItemDataList, itemData)
        self:RefreshCachedList()
    end
end

function M:BP_OnEntryInitialized_Cached(data, ui)
    local itemData = self.CachedItemDataList[data.Index]
    self:RefreshItemCell(itemData, ui)
end

function M:BP_OnItemClicked_Cached(data)
    if self.isBackpackOpen then
        local itemData = self:GetBuildDataById(data.ItemId)
        if itemData then
            itemData.selected = false
            self:RefreshBackpackListSelectedItem(itemData.item_id, itemData.selected)
        end

        table.remove(self.CachedItemDataList, data.index)

        self:RefreshCachedList()
    else
        --原来选中
        if self.SelectedItemData then
            self.SelectedItemData.cached_selected = false
            self.SelectedItemData.temp_build_count = 0
            self:RefreshCachedListSelectedItem(self.SelectedItemData.item_id, self.SelectedItemData.cached_selected)
        end
        --新选中的
        self.SelectedItemData = self.CachedItemDataList[data.index]
        self.SelectedItemData.cached_selected = true
        self.SelectedItemData.temp_build_count = 1
        self:RefreshCachedListSelectedItem(self.SelectedItemData.item_id, self.SelectedItemData.cached_selected)
        --切换模型
        self:ChangeBuildActor()
    end
end

function M:RefreshBackpackListSelectedItem(buildId, bSelected)
    local ui = self:GetBackpackUIById(buildId)
    if ui then
        ui.ImageBGSelected:SetVisibility(bSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        ui.Panel_Selected:SetVisibility(bSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    end
end

function M:RefreshCachedListSelectedItem(buildId, bSelected)
    local ui = self:GetCachedUIById(buildId)
    if ui then
        ui.ImageBGSelected:SetVisibility(bSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        ui.Panel_Selected:SetVisibility(bSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    end
end 

function M:RefreshListItemCount(buildId)
    local itemData = self:GetBuildDataById(buildId)
    local leftCount = itemData.item_count - itemData.build_count - itemData.temp_build_count
    local backpackUI = self:GetBackpackUIById(buildId)
    if backpackUI then
        backpackUI.TextPrice:SetText(leftCount)
    end
    local cachedUI = self:GetCachedUIById(buildId)
    if cachedUI then
        cachedUI.TextPrice:SetText(leftCount)
    end
end

--复位
function M:OnClicked_Btn_Cancel()
    if self.LockedActor then
        if self.TempBuild then
            self.LockedActor:K2_DestroyActor()
            self.LockedActor = nil
        else
            self.LockedActor:K2_SetActorTransform(self.LockedActorTrans, false, nil, false)
        end
        
        self:ExitEditing()
    end
end

--收纳
function M:OnClicked_Btn_Back()
    --删除这个
    local targetActor = self.LockedActor
    if targetActor then
        --判断是否是地台
        local buildId = targetActor:GetID()
        if self:GetTypeByBuildId(buildId) == 2 then
            local attachedActors = UE.TArray(UE.AActor)
            targetActor:GetAttachedActors(attachedActors, true, false)
            for j = 1, attachedActors:Length() do
                local attachedActor = attachedActors:Get(j)
                if attachedActor then
                    if attachedActor and attachedActor.GetID then
                        local childId = attachedActor:GetID()
                        print("----childId:" .. tostring(childId))
                        local itemData = self:GetBuildDataById(childId)
                        if itemData then
                            itemData.temp_build_count = 0
                            itemData.build_count = math.max(itemData.build_count - 1, 0)
                            local count = itemData.item_count - itemData.build_count - itemData.temp_build_count
                            if count <= 0 then
                                self:RemoveCachedBuild(childId)
                                self:RefreshCachedList()
                            end
                            self:RefreshListItemCount(childId)
                            itemData.selected = count <= 0
                            self:RefreshBackpackListSelectedItem(childId, count <= 0)
                        end
                    end
                    self.AllBuildActors[attachedActor:GetUUID()] = nil
                    attachedActor:K2_DestroyActor()
                end
            end
        end

        local itemData = self:GetBuildDataById(buildId)
        if itemData then
            itemData.temp_build_count = 0
            if not self.TempBuild then
                itemData.build_count = math.max(itemData.build_count - 1, 0)
            end
           
            local count = itemData.item_count - itemData.build_count - itemData.temp_build_count
            if count <= 0 then
                self:RemoveCachedBuild(buildId)
                self:RefreshCachedList()
            end
            self:RefreshListItemCount(buildId)
            itemData.selected = count <= 0
            self:RefreshBackpackListSelectedItem(buildId, count <= 0)
        end
        self.AllBuildActors[targetActor:GetUUID()] = nil
        targetActor:K2_DestroyActor()
        targetActor = nil
        self:ExitEditing()
    end
end

--安置
function M:OnClicked_Btn_Sure()
    if not self.isEditing then
        self:EnterEditing()
    else
        self:SaveTempBuildActor()
        self:ExitEditing()
        self.isChanged = true
    end
end

--移动
function M:OnClicked_Btn_Move()
    self.ControlType = 1
    self.SwitchMove:SetActiveWidgetIndex(1)
    self.SwitchChange:SetActiveWidgetIndex(0)
end

--变换
function M:OnClicked_Btn_Change()
    self.ControlType = 2
    self.SwitchMove:SetActiveWidgetIndex(0)
    self.SwitchChange:SetActiveWidgetIndex(1)
end

--保存 存储父子类关系
function M:OnClicked_Btn_Save()
    self:SaveTempBuildActor()
    self:ExitEditing()

    local buildInfo = {}
    -- local buildActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "Buildable")
    -- for i = 1, buildActors:Length() do 
    for uuid, actor in pairs(self.AllBuildActors) do
        local loc = actor:K2_GetActorLocation()
        local rot = actor:K2_GetActorRotation()
        table.insert(buildInfo, {
            item_id = actor:GetID(),
            blob = loc.X .. ',' .. loc.Y .. ',' .. loc.Z .. "," .. rot.Roll .. ',' .. rot.Pitch .. ',' .. rot.Yaw .. ',' .. uuid .. ',' .. tostring(actor:GetParentUUID() or 0)
        })
    end
    BuildSystem:GetInstance():ReqBuildHome(buildInfo)
    self.isChanged = false
end

--吸纳所有
function M:OnClicked_Btn_BackAll()
    self:ExitEditing()
    --提示是否保存
    UIUtils.ShowComNotice(Database.L10n(276), self, 
        function()
            self:RecoveryAllBuildActors()
        end, 
        function() end)
end

function M:OnAxisChanged_Right(axis)
    if axis.X == 0 and axis.Y == 0 then 
        return 
    end
    -- if not self.LockedActor then
    --     self:EnterEditing()
    -- end

    if self.LockedActor then
        local moveDirection = UE.FVector(1, 1, 0)
        local cameraManager = UE.UGameplayStatics.GetPlayerCameraManager(self, 0)
        local forward = cameraManager:GetActorForwardVector()
        forward.Z = 0 
        local dirNormal = UE.UKismetMathLibrary.Normal(forward, 0.0001)
        
        -- local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        -- local character = pc:K2_GetPawn()
        -- if character then 
        --     local actorPos = self.LockedActor:K2_GetActorLocation()
        --     local charPos = character:K2_GetActorLocation()
        --     local dirPos = actorPos - charPos
        --     dirPos.Z = 0
        --     local dirNormal = UE.UKismetMathLibrary.Normal(dirPos, 0.0001)
        --     --垂直向量
        --     moveDirection = UE.FVector(dirNormal.Y, -dirNormal.X, 0)
        -- end
        if self.ControlType == 1 then --移动
            if math.abs(axis.X) > math.abs(axis.Y) then
                moveDirection = UE.FVector(dirNormal.Y, -dirNormal.X, 0)
                self.LockedActor:K2_AddActorWorldOffset(moveDirection * (-axis.X * self.MoveRate), false, nil, false)
            else
                moveDirection = forward * -1
                self.LockedActor:K2_AddActorWorldOffset(moveDirection * (axis.Y * self.MoveRate), false, nil, false)
            end
        else --位置变换
            if math.abs(axis.X) > math.abs(axis.Y) then --旋转
                self.LockedActor:K2_AddActorWorldRotation(UE.FRotator(0, -axis.X * self.MoveRate, 0), false, nil, false)
            else --高度
                --print('-------当前选中id:' .. tostring(self.LockedActor.ID))
                if self:GetIsFreeHeight(self.LockedActor.ID) then
                    self.LockedActor:K2_AddActorWorldOffset(UE.FVector(0, 0, -axis.Y * self.MoveRate), false, nil, false)
                end
            end
        end
        self.isChanged = true
    end
end

--检测是否只有同一角色id的建筑
function M:CheckHasSomeCharId(temBuildId)
    local tempCharId = self:GetCharIdByBuildId(temBuildId)
    if tempCharId > 0 then
        for uuid, actor in pairs(self.AllBuildActors) do 
            print('---build_id:' .. tostring(actor:GetID()) .. ',uuid:' .. tostring(uuid))
            local buildId = actor:GetID()
            local charId = self:GetCharIdByBuildId(buildId)
            if charId > 0 and charId == tempCharId then
                return true
            end
        end
    end
    
    return false
end

----------------------------------------------------------------------
--配置
function M:GetCharIdByBuildId(buildId)
    local config = UIUtils.GetItemConfigById(buildId)
    if config and config.subParam and config.subParam[1] then
        return config.subParam[1] or 0
    end
    return 0
end

function M:GetTypeByBuildId(buildId)
    if not buildId or buildId <= 0 then
        return -1
    end
    local config = UIUtils.GetItemConfigById(buildId)
    if not config then
        LOG_ERROR('---->UIUtils.GetItemConfigById未找到id:' .. tostring(buildId))
        return -1
    end 
    -- print('---buildid:' .. tostring(buildId) .. ',type:' .. tostring(config.type))
    return config.subType
end

function M:GetIsFreeHeight(buildId)
    if not buildId or buildId <= 0 then
        return true
    end
    local config = UIUtils.GetItemConfigById(buildId)
    if not config then
        LOG_ERROR('---->UIUtils.GetItemConfigById未找到id:' .. tostring(buildId))
        return true
    end 
    -- print('---buildid:' .. tostring(buildId) .. ',freeHeight:' .. tostring(config.subType == 4))
    return config.subType == 4
end

----------------------------------------------------------------------
--数据/ui
function M:GetBuildDataById(buildId)
    local data = nil
    for _, itemList in pairs(self.FurnitureData) do 
        for _, item in pairs(itemList) do
            if item.item_id == buildId then
                data = item
                break
            end
        end
    end
    return data
end

function M:GetBackpackUIById(buildId)
    local mainUI = nil
    local allWidgets = self.ListView_Backpack:GetDisplayedEntryWidgets()
    for i = 1, allWidgets:Length() do 
        local widget = allWidgets:Get(i)
        if widget and widget.ItemId == buildId then
            mainUI = widget
            break
        end
    end 
    return mainUI
end

function M:GetCachedUIById(buildId)
    local cachedUI = nil
    local allWidgets = self.ListView_Cached:GetDisplayedEntryWidgets()
    for i = 1, allWidgets:Length() do 
        local widget = allWidgets:Get(i)
        if widget and widget.ItemId == buildId then
            cachedUI = widget
            break
        end
    end
    return cachedUI
end

function M:RemoveCachedBuild(buildId)
    local index = -1
    for idx, v in pairs(self.CachedItemDataList) do
        if v.item_id == buildId then
            index = idx
            break
        end
    end
    if index > 0 then
        table.remove(self.CachedItemDataList, index)
    end
end

return M
