require "UnLua"
require "Common.TableUtil"
local Database = require('_Game.Utils.Database')
local UIUtils = require('_Game.Utils.UIUtils')
local BackpackSystem = require 'Module.Backpack.BackpackSystem'
local BuildSystem = require('Module.BuildSystem.BuildSystem')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"


---@type UI_Build_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

--构造函数
function M:Construct()
    self:InitUI()
    self:InitData()
    MessageManager:GetInstance():AddListener("OnResBuildHome", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnResBuildHome", self)
    -- self:ClearTempBuildActorInfo()
end

function M:InitUI()
    self.FirstItem.OnClicked:Add(self, self.SelectFirstItem)
    self.Btn_Exit.OnGHSClicked:Add(self, self.OnClicked_Btn_Exit)
    self.Btn_Left.OnGHSClicked:Add(self, self.OnClicked_Btn_Left)
    self.Btn_Right.OnGHSClicked:Add(self, self.OnClicked_Btn_Right)
    self.Btn_Save.OnClicked:Add(self, self.OnClicked_Btn_Save)

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
end

function M:InitData()
    self.FurnitureData = {}
    self.AllBuildActors = {}
    self.BuildPosList = {}
    self.CameraList = {}
    self.CameraNameIdList = {}
    self.ItemDataList = {}
    self.TempBuildActor = nil
    self.TempBuildPosIndex = 0
    self.SelectedIndex = 0

    self:InitCameraRegionInfo()

    self:InitBuildPosActorInfo()

    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    self.AllBuildActors = controller.AllBuildActors or {}

    self:InitBuildActorInfo()

    self:InitBuildItemInfo()

    self:RefreshUI()
end

function M:OnResBuildHome()
    self.FurnitureData = {}
    self:InitBuildActorInfo()
    self:InitBuildItemInfo()
    self:RefreshUI()
end

function M:RefreshUIByMask(id)
    if '' ~= id then
        self.CameraIndex = tonumber(id)
        local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        controller:SetViewTargetWithBlend(self.CameraList[self.CameraIndex], 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
    end
end

function M:RefreshUI()
    self:GetRegionItemInfo()

    --区域名字
    local nameId = self.CameraNameIdList[self.CameraIndex]
    if nameId and nameId > 0 then
        self.Text_RegionName:SetText(Database.L10n(nameId))
    else
        self.Text_RegionName:SetText('None')
    end

    for i = 1, 6 do
        local img = self['Selected_' .. i]
        if img then
            img:SetVisibility(i == self.CameraIndex and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
        end
    end
end

function M:RefreshItemCell(itemData, ui, isBackpack)
    ui.ItemId = itemData.item_id

    local config = UIUtils.GetItemConfigById(itemData.item_id)
    --个数/名字
    ui.TextPrice:SetText(itemData.item_count)
    ui.TextName:SetText(Database.L10n(config.itemName))

    --品质框
    if config and config.rarityPath and config.rarityPath ~= '' then
        local strArr = string.split(config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            ui.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if config and config.iconPath and config.iconPath ~= '' then
        local strArr = string.split(config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', config.iconPath, littePath)
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
    local isSelected = self.SelectedItemData and self.SelectedItemData.item_id == itemData.item_id or false
    ui.ImageBGSelected:SetVisibility(isSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    ui.Panel_Selected:SetVisibility(itemData.buildPos > 0 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
end

--保存当前所有建筑信息通知服务器
function M:SaveBuildInfo()
    local buildInfo = {}
    for posIndex, actor in pairs(self.AllBuildActors) do
        print("---pos:" .. tostring(posIndex) .. ',id' .. tostring(actor.ID))

        local tab = {
            posIndex = posIndex,
            skinId = actor.SkinId
        }
        local rapidjson = require "rapidjson"
        local jsonStr = rapidjson.encode(tab)

        table.insert(buildInfo, {
            item_id = actor.ID,
            blob = tostring(jsonStr),
        })
    end
    BuildSystem:GetInstance():ReqBuildHome(buildInfo)
end

---获取场景中所有摄像机区域
function M:InitCameraRegionInfo()
    local gameMode = UE.UGameplayStatics.GetGameMode(self, 0)
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    local player = gameMode:BPI_GetPlayer()
    local nearDistance = 0
    local nearIndex = 1
   
    --获取场景中所有的摄像机位置
    local regionCameras = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "BuildRegion")
    if regionCameras:Length() > 0 then
        for i = 1, regionCameras:Length() do
            local camera = regionCameras:Get(i)
            local posTag = camera.Tags:Get(2)
            local nameId = tonumber(camera.Tags:Get(3) or 0)
            local index = tonumber(string.sub(posTag, 7, -1))
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
            self.CameraNameIdList[index] = nameId
        end
    end

    local minDistance = 100000
    -- self.TriggerBoxActors = {}
    local triggerActors = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.ATriggerBox)
    for i = 1, triggerActors:Length() do 
        local actor = triggerActors:Get(i)
        if actor then
            local tags = actor.Tags
            if tags:Length() > 0 then
                local triggerTag = tags:Get(1)
                print('---tag:' .. tostring(triggerTag))
                if string.contains(triggerTag, 'Region') then
                    local cameraIndex = string.sub(triggerTag, 7, -1)
                    local index = tonumber(cameraIndex)
                    if index ~= nil then
                        -- self.BuildCameraIndex = index 
                        -- table.insert(self.TriggerBoxActors, actor)
                        local distance = UE.UKismetMathLibrary.Vector_Distance(actor:K2_GetActorLocation(), player:K2_GetActorLocation())
                        print('-----distance:' .. tostring(distance) .. ",minDistance:" .. tostring(minDistance))
                        if distance < minDistance then
                            minDistance = distance
                            self.CameraIndex = index
                        end
                    end
                end
            end
        end
    end

    print("---------------cameraIndex:" .. tostring(self.CameraIndex))
    -- self.CameraIndex = controller.BuildCameraIndex or 1
    controller:SetViewTargetWithBlend(self.CameraList[self.CameraIndex], 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
end

--获取场景中建筑摆放点
function M:InitBuildPosActorInfo()
    self.CameraRegionPosInfo = {}
    local buildPosActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "BuildPos")
    for i = 1, buildPosActors:Length() do 
        local buildActor = buildPosActors:Get(i)
        self.BuildPosList[buildActor.BuildPosIndex] = buildActor
        if not self.CameraRegionPosInfo[buildActor.BuildRegionIndex] then
            self.CameraRegionPosInfo[buildActor.BuildRegionIndex] = {}
        end
        table.insert(self.CameraRegionPosInfo[buildActor.BuildRegionIndex], buildActor.BuildPosIndex)
    end
end

--创建服务器存储的建筑
function M:InitBuildActorInfo()
    local buildInfo = BuildSystem:GetInstance().BuildInfo
    for _, info in pairs(buildInfo) do
        if info and info.item_id and info.item_id > 0 then
            local buildInfo = 
            {
                item_id = info.item_id,
                item_count = 1, --道具个数
                buildPos = info.posIndex, --位置
            }
            table.insert(self.FurnitureData, buildInfo)
        end
    end
end


--从背包中获取建筑物品
function M:InitBuildItemInfo()
    local itemInfos = BackpackSystem:GetInstance():GetAllItemByMainType(UIUtils.ItemMainType.Build) 
    for _, itemInfo in pairs(itemInfos) do
        local bHasChar = true
        -- if itemInfo and itemInfo.config and itemInfo.config.subType == 1 and itemInfo.config.subParam and itemInfo.config.subParam[1] then
        --     local charId = itemInfo.config.subParam[1]
        --     if charId and charId > 0 then
        --         local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId)
        --         if not charInfo then
        --             bHasChar = false
        --         end
        --     end
        -- end
        
        
        if bHasChar then
            --已经建造个数
            local buildCount = BuildSystem:GetInstance():GetBuildCount(itemInfo.item_id)
            local leftCount = itemInfo.count - buildCount
            if leftCount > 0 then
                local buildInfo = 
                {
                    item_id = itemInfo.item_id,
                    item_count = leftCount, --道具个数
                    buildPos = 0,
                }
                table.insert(self.FurnitureData, buildInfo)
            end
        end
    end
end

--判断tabA中至少有1个数在tabB中
function M:TableInTable(tabA, tabB)
    for i = 1, #tabA do
        for j = 1, #tabB do 
            if tabA[i] == tabB[j] then
                return true
            end
        end
    end
    return false
end

function M:GetRegionItemInfo()
    self.ItemDataList = {}
    local posIndexList = self.CameraRegionPosInfo[self.CameraIndex] or {}
    for _, info in pairs(self.FurnitureData) do
        local d_bag_item_furniture = require('ClientDatas.d_bag_item_furniture')
        local config = d_bag_item_furniture[info.item_id]
        if config then
            if self:TableInTable(config.posIndex, posIndexList) then
                table.insert(self.ItemDataList, info)
            end
        end
    end

    if #self.ItemDataList > 0 then
        table.sort(self.ItemDataList, function(a, b)
            return a.item_id < b.item_id
        end)
    end

    self.ListView_Backpack:ClearListItems()

    local itemDataSource = {}
    if self.ItemDataList and #self.ItemDataList > 0 then
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Item.UI_Item_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)

        for i, data in ipairs(self.ItemDataList) do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i
            ItemData.ItemId = data.item_id
            table.insert(itemDataSource, ItemData)

            if self.SelectedItemData and self.SelectedItemData.item_id == data.item_id then
                self.SelectedItemData = data
            end
        end
    end
    self.ListView_Backpack:BP_SetListItems(itemDataSource)
end

--2个table表的交集
function M:TableIntersection(tabA, tabB)
    local posList = {}
    for i = 1, #tabA do
        for j = 1, #tabB do 
            if tabA[i] == tabB[j] then
                table.insert(posList, tabA[i])
            end
        end
    end
    return posList
end

function M:FindPosIndex(posIndex)
    local regionPosList = self.CameraRegionPosInfo[self.CameraIndex]
    local posList = self:TableIntersection(posIndex, regionPosList)
    if #posList <= 0 then
        LOG_ERROR('-------查找错误:' .. tostring(self.CameraIndex))
        return 1
    end
    for i = 1, #posList do
        local posIndex = posList[i]
        if not self.AllBuildActors[posIndex] then
            return posIndex
        end
    end
    return posList[1]
end

function M:SetActorAllHidden(actor, bHiddenInGame, bOnlyActor)
    if bHiddenInGame then
        if actor.OnLuaHideActor then
            actor:OnLuaHideActor()
            return
        end
    else
        if actor.OnLuaShowActor then
            actor:OnLuaShowActor()
            return
        end
    end

    actor:SetActorHiddenInGame(bHiddenInGame)
    actor:SetActorEnableCollision(not bHiddenInGame)

    local attachedActors = UE.TArray(UE.AActor)
    actor:GetAttachedActors(attachedActors, true, false)
    if not bOnlyActor then
        for i = 1, attachedActors:Length() do 
            local attachActor = attachedActors:Get(i)
            attachActor:SetActorHiddenInGame(bHiddenInGame)
            attachActor:SetActorEnableCollision(not bHiddenInGame)
        end
    end
end

function M:ClearTempBuildActorInfo()
    -- if self.TempBuildActor then
    --     self.TempBuildActor:K2_DestroyActor()
    --     self.TempBuildActor = nil
    -- end
    -- if self.TempBuildPosIndex > 0 then
    --     if self.AllBuildActors[self.TempBuildPosIndex] then
    --         self:SetActorAllHidden(self.AllBuildActors[self.TempBuildPosIndex], true)
    --     else
    --         if self.BuildPosList[self.TempBuildPosIndex] then
    --             self:SetActorAllHidden(self.BuildPosList[self.TempBuildPosIndex], true)
    --         end
    --     end
    --     self.TempBuildPosIndex = 0
    -- end
end

function M:ShowTempBuildActor()
    self:ClearTempBuildActorInfo()

    if self.SelectedItemData then
        local d_bag_item_furniture = require('ClientDatas.d_bag_item_furniture')
        local config = d_bag_item_furniture[self.SelectedItemData.item_id]
        if config then
            local actorPath = config.actorPath
            -- if not string.endswith(actorPath, "_C'") then
                actorPath = string.sub(actorPath, 1, -2) .. "_C'"
            -- end
            print("-----config.posIndex:" .. tostring(config.posIndex) .. ',itemId:' .. tostring(self.SelectedItemData.item_id))
            local posIndex = self:FindPosIndex(config.posIndex)
            if self.BuildPosList[posIndex] then
                self:SetActorAllHidden(self.BuildPosList[posIndex], true)
            end
            if self.AllBuildActors[posIndex] then
                self:CacheCharacterMesh(self.AllBuildActors[posIndex])
                self.AllBuildActors[posIndex] = nil
            end
            --坐标信息
            local posActor = self.BuildPosList[posIndex]
            if not posActor then
                LOG_ERROR('--->posIndex:' .. tostring(posIndex) .. ', not have posActor!')
                return
            end
            if actorPath ~= '' then
                local buildActor = self:GetCharacterMeshFromCache(actorPath)
                buildActor:K2_SetActorTransform(posActor:GetTransform(), false, nil, false)
                buildActor:ResetAnimation()
                self:SetActorAllHidden(buildActor, true)
                buildActor.ID = self.SelectedItemData.item_id
                buildActor.SkinId = config.trialClothes
                if buildActor.InitDress then
                    buildActor:InitDress(true)
                end
                self.AllBuildActors[posIndex] = buildActor

                self:SaveBuildInfo()
            end
        end
    end
end

function M:HideTempBuildActor()
    if self.SelectedItemData then
        local d_bag_item_furniture = require('ClientDatas.d_bag_item_furniture')
        local config = d_bag_item_furniture[self.SelectedItemData.item_id]
        if config then
            print("-----config.posIndex:" .. tostring(config.posIndex) .. ',itemId:' .. tostring(self.SelectedItemData.item_id))
            local posIndex = self:FindPosIndex(config.posIndex)
            if self.BuildPosList[posIndex] then
                self:SetActorAllHidden(self.BuildPosList[posIndex], false)
            end
            if self.AllBuildActors[posIndex] then
                self:CacheCharacterMesh(self.AllBuildActors[posIndex])
                self.AllBuildActors[posIndex] = nil
            end
            self:SaveBuildInfo()
        end
    end
end

-------------------------------------------------------
-------------------------------------------------------
---ui event
function M:OnClicked_Btn_Exit()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveTopUI(true)

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller:SetViewTargetWithBlend(player, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Exit)

function M:OnClicked_Btn_Left()
    self.CameraIndex = self.CameraIndex - 1
    if self.CameraIndex <= 0 then
        self.CameraIndex = #self.CameraList
    end
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller:SetViewTargetWithBlend(self.CameraList[self.CameraIndex], 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
    self:RefreshUI()
end

function M:OnClicked_Btn_Right()
    self.CameraIndex = self.CameraIndex + 1
    if self.CameraIndex > #self.CameraList then
        self.CameraIndex = 1
    end
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller:SetViewTargetWithBlend(self.CameraList[self.CameraIndex], 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
    self:RefreshUI()
end

function M:BP_OnEntryInitialized_Backpack(data, ui)
    local itemData = self.ItemDataList[data.Index]
    self:RefreshItemCell(itemData, ui, true)
end

function M:BP_OnItemClicked_Backpack(data)
    local itemData = self.ItemDataList[data.Index]
    print("--->onclicked:" .. tostring(table.dump(itemData, nil, 10)))
    if self.SelectedItemData ~= itemData then
        if self.SelectedItemData and self.SelectedItemData.item_id > 0 then
            local widgets = self.ListView_Backpack:GetDisplayedEntryWidgets()
            for i = 1, widgets:Length() do
                local ui = widgets:Get(i)
                if ui.ItemId == self.SelectedItemData.item_id then
                    ui.ImageBGSelected:SetVisibility(UE.ESlateVisibility.Hidden)
                    break
                end
            end
        end
        local widgets = self.ListView_Backpack:GetDisplayedEntryWidgets()
        for i = 1, widgets:Length() do
            local ui = widgets:Get(i)
            if ui.ItemId == itemData.item_id then
                ui.ImageBGSelected:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                break
            end
        end

        self.SelectedItemData = itemData
        self.SelectedIndex = data.Index

        if itemData.buildPos > 0 then
            itemData.buildPos = 0
            -- self.Btn_Sure:SetVisibility(UE.ESlateVisibility.Hidden)
            -- self.Btn_Back:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self:HideTempBuildActor()
        else
            -- self.Btn_Sure:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            -- self.Btn_Back:SetVisibility(UE.ESlateVisibility.Hidden)
            self:ShowTempBuildActor()
        end
    else
        if self.SelectedItemData.buildPos > 0 then
            self.SelectedItemData.buildPos = 0
            -- self.Btn_Sure:SetVisibility(UE.ESlateVisibility.Hidden)
            -- self.Btn_Back:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self:HideTempBuildActor()
        else
            self:ShowTempBuildActor()
        end
    end
end

--安置
function M:OnClicked_Btn_Sure()
    if self.TempBuildActor and self.TempBuildPosIndex > 0 then
        local oldActor = self.AllBuildActors[self.TempBuildPosIndex]
        if oldActor then
            oldActor:K2_DestroyActor()
            oldActor = nil
            self.AllBuildActors[self.TempBuildPosIndex] = nil
        end
        self.AllBuildActors[self.TempBuildPosIndex] = self.TempBuildActor
        self.TempBuildActor = nil
        self.TempBuildPosIndex = 0
    end

    self:SaveBuildInfo()
end

function M:OnClicked_Btn_Save()
    self:SaveBuildInfo()
end

--吸纳
function M:OnClicked_Btn_Back()
    if self.SelectedItemData and self.SelectedItemData.buildPos > 0 then
        local oldActor = self.AllBuildActors[self.SelectedItemData.buildPos]
        if oldActor then
            oldActor:K2_DestroyActor()
            oldActor = nil 
        end 
        self.AllBuildActors[self.SelectedItemData.buildPos] = nil

        if self.BuildPosList[self.SelectedItemData.buildPos] then
            self:SetActorAllHidden(self.BuildPosList[self.SelectedItemData.buildPos], false)
        end
        self.SelectedItemData = nil
    end
    self:SaveBuildInfo()
end

function M:OnClicked_Btn_BackAll()
    -- self:ClearTempBuildActorInfo()
    if self.ItemDataList and #self.ItemDataList > 0 then
        for _, v in pairs(self.ItemDataList) do 
            if v.buildPos > 0 then
                local oldActor = self.AllBuildActors[v.buildPos]
                if oldActor then
                    oldActor:K2_DestroyActor()
                    oldActor = nil 
                end 
                self.AllBuildActors[v.buildPos] = nil
                if self.BuildPosList[v.buildPos] then
                    self:SetActorAllHidden(self.BuildPosList[v.buildPos], false)
                end
            end
        end
    end

    self.SelectedItemData = nil
    self:SaveBuildInfo()
end

function M:SelectFirstItem()
    self.ListView_Backpack:ScrollToTop()
    local items = self.ListView_Backpack:GetListItems()
    self:BP_OnItemClicked_Backpack(items[1])
end

-------------------------------------------------------
---缓存模型
function M:CacheCharacterMesh(actor)
    BuildSystem:GetInstance():CacheCharacterMesh(actor)
end

function M:GetCharacterMeshFromCache(path)
    return BuildSystem:GetInstance():GetCharacterMeshFromCache(self:GetWorld(), path)
end

return M
